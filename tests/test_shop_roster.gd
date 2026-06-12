extends GutTest

## Tests for the shop roster operations on RoguelikeRun and the ShopScreen
## overlay - FUNCTIONALITY ONLY. Buying, hiring into real vacancies, crew
## transfer into matching vacancies, and icing hulls — plus the shop UI's
## affordability gate and stock persistence.

var _saved_fleet_hulls: Array
var _saved_money: int
var _saved_doctrine: Dictionary
var _saved_active: bool
var _saved_campaign: Dictionary
var _saved_hired_ids: Array


func before_each() -> void:
	_saved_fleet_hulls = RoguelikeRun.fleet_hulls.duplicate(true)
	_saved_money = RoguelikeRun.money
	_saved_doctrine = RoguelikeRun.doctrine.duplicate(true)
	_saved_active = RoguelikeRun.active
	_saved_campaign = RoguelikeRun.campaign.duplicate(true)
	_saved_hired_ids = RoguelikeRun.hired_roster_ids.duplicate()


func after_each() -> void:
	RoguelikeRun.fleet_hulls = _saved_fleet_hulls
	RoguelikeRun.money = _saved_money
	RoguelikeRun.doctrine = _saved_doctrine
	RoguelikeRun.active = _saved_active
	RoguelikeRun.campaign = _saved_campaign
	RoguelikeRun.hired_roster_ids = _saved_hired_ids


## First available roster candidate id for a slot's role.
func _candidate_id(slot: Dictionary) -> String:
	var candidates := CrewRosterManager.available_entries(
		RoguelikeRun.hired_roster_ids, slot.get("role", -1))
	return candidates[0].id if not candidates.is_empty() else ""


func _counts(overrides: Dictionary = {}) -> Dictionary:
	var base := {"fighter": 0, "heavy_fighter": 0,
		"torpedo_boat": 0, "corvette": 0, "capital": 0}
	for key in overrides:
		base[key] = overrides[key]
	return base


func _find_gunner_slot(hull: Dictionary) -> Dictionary:
	for slot in RoguelikeRun.hull_vacancies(hull):
		if slot.get("role", -1) == CrewData.Role.GUNNER:
			return slot
	return {}


# ============================================================================
# BUYING HULLS
# ============================================================================

func test_buying_deducts_price_and_adds_a_crewless_hull():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	RoguelikeRun.money = 100000
	var before := RoguelikeRun.fleet_hulls.size()
	var price := EconomySystem.ship_purchase_price("corvette")

	var hull := RoguelikeRun.add_purchased_hull("corvette")

	assert_eq(RoguelikeRun.money, 100000 - price, "Buying deducts the purchase price")
	assert_eq(RoguelikeRun.fleet_hulls.size(), before + 1, "The bought hull joins the fleet")
	assert_eq(hull.ship_type, "corvette", "It is the type that was bought")
	assert_true(hull.crew.is_empty(), "A bought hull arrives crewless")
	assert_gt(hull.complement.size(), 0, "...but with a full standard complement to crew")


func test_purchased_hull_is_not_sortieable_until_crewed():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	RoguelikeRun.money = 100000

	var hull := RoguelikeRun.add_purchased_hull("fighter")

	assert_eq(RoguelikeRun.sortieable_hulls().filter(
		func(h): return h.hull_id == hull.hull_id).size(), 0,
		"A crewless hull has no pilot and cannot sortie")


# ============================================================================
# VACANCIES & HIRING
# ============================================================================

func test_empty_hull_reports_its_full_complement_as_vacancies():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	RoguelikeRun.money = 100000
	var hull := RoguelikeRun.add_purchased_hull("corvette")

	assert_eq(RoguelikeRun.hull_vacancies(hull).size(), hull.complement.size(),
		"Every slot on a crewless hull is a vacancy")


func test_hiring_fills_one_vacancy():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	RoguelikeRun.money = 100000
	var hull := RoguelikeRun.add_purchased_hull("fighter")
	var vacancies_before := RoguelikeRun.hull_vacancies(hull).size()

	var slot: Dictionary = RoguelikeRun.hull_vacancies(hull)[0]
	var ok := RoguelikeRun.fill_vacancy(hull.hull_id, slot, _candidate_id(slot))

	assert_true(ok, "Hiring into a real vacancy succeeds")
	assert_eq(hull.crew.size(), 1, "One crew member is hired")
	assert_eq(RoguelikeRun.hull_vacancies(hull).size(), vacancies_before - 1,
		"The filled slot is no longer a vacancy")


func test_hiring_never_exceeds_the_complement():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	RoguelikeRun.money = 100000
	var hull := RoguelikeRun.add_purchased_hull("fighter")
	for slot in RoguelikeRun.hull_vacancies(hull).duplicate(true):
		RoguelikeRun.fill_vacancy(hull.hull_id, slot, _candidate_id(slot))

	# With no vacancy left, another pilot cannot be hired.
	var full_slot := {"role": CrewData.Role.PILOT}
	var ok := RoguelikeRun.fill_vacancy(hull.hull_id, full_slot, _candidate_id(full_slot))

	assert_false(ok, "A fully crewed hull rejects further hires")
	assert_eq(hull.crew.size(), hull.complement.size(),
		"Crew never exceeds the standard complement")


func test_hiring_a_gunner_binds_them_to_the_vacant_weapon():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	RoguelikeRun.money = 100000
	var hull := RoguelikeRun.add_purchased_hull("heavy_fighter")
	var gunner_slot := _find_gunner_slot(hull)
	assert_false(gunner_slot.is_empty(), "precondition: a heavy fighter has a gunner slot")

	RoguelikeRun.fill_vacancy(hull.hull_id, gunner_slot, _candidate_id(gunner_slot))

	var hired_weapon := ""
	for member in hull.crew:
		if member.get("role", -1) == CrewData.Role.GUNNER:
			hired_weapon = member.get("weapon_id", "")
	assert_eq(hired_weapon, gunner_slot.weapon_id,
		"A hired gunner mans the specific weapon whose slot was vacant")


# ============================================================================
# CREW TRANSFER
# ============================================================================

func test_transfer_into_a_matching_vacancy_moves_the_crew():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	RoguelikeRun.money = 100000
	var src: Dictionary = RoguelikeRun.fleet_hulls[0]
	var dest := RoguelikeRun.add_purchased_hull("fighter")  # empty: pilot vacancy
	var pilot_id: String = src.crew[0].crew_id

	var ok := RoguelikeRun.transfer_crew(pilot_id, dest.hull_id)

	assert_true(ok, "A pilot transfers into another fighter's open pilot seat")
	assert_eq(RoguelikeRun.hull_by_id(dest.hull_id).crew.size(), 1, "Destination gains the pilot")
	assert_true(src.crew.is_empty(), "Source gives up the pilot")


func test_transfer_is_rejected_without_a_matching_vacancy():
	RoguelikeRun.start_run(_counts({"fighter": 2}))
	var src: Dictionary = RoguelikeRun.fleet_hulls[0]
	var dest: Dictionary = RoguelikeRun.fleet_hulls[1]  # already has a pilot
	var pilot_id: String = src.crew[0].crew_id

	var ok := RoguelikeRun.transfer_crew(pilot_id, dest.hull_id)

	assert_false(ok, "A hull with no matching vacancy refuses the transfer")
	assert_eq(src.crew.size(), 1, "The crew member stays put")


func test_transfer_preserves_crew_identity():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	RoguelikeRun.money = 100000
	var src: Dictionary = RoguelikeRun.fleet_hulls[0]
	var dest := RoguelikeRun.add_purchased_hull("fighter")
	var pilot: Dictionary = src.crew[0]
	var pilot_id: String = pilot.crew_id
	var piloting: float = pilot.get("stats", {}).get("skills", {}).get("piloting", -1.0)

	RoguelikeRun.transfer_crew(pilot_id, dest.hull_id)

	var moved: Dictionary = RoguelikeRun.hull_by_id(dest.hull_id).crew[0]
	assert_eq(moved.crew_id, pilot_id, "The same crew member arrives, identity intact")
	assert_eq(moved.get("stats", {}).get("skills", {}).get("piloting", -2.0), piloting,
		"Their skills are unchanged by the transfer")


# ============================================================================
# ICING
# ============================================================================

func test_icing_a_hull_removes_it_from_the_sortie_list():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	var hull_id: String = RoguelikeRun.fleet_hulls[0].hull_id

	RoguelikeRun.set_hull_iced(hull_id, true)
	assert_eq(RoguelikeRun.sortieable_hulls().size(), 0, "An iced hull does not sortie")

	RoguelikeRun.set_hull_iced(hull_id, false)
	assert_eq(RoguelikeRun.sortieable_hulls().size(), 1, "Reactivating restores it to the line")


# ============================================================================
# STOCK PERSISTENCE
# ============================================================================

func test_shop_stock_survives_a_campaign_save_round_trip():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	# Roll once and stash the stock on a campaign node, the way the map does the
	# first time the player opens a shop.
	var node_id: String = RoguelikeRun.campaign["nodes"].keys()[0]
	RoguelikeRun.campaign["nodes"][node_id]["shop_stock"] = ["fighter", "corvette"]

	RoguelikeRun.save_campaign_to_disk()
	assert_true(RoguelikeRun.load_campaign_from_disk(), "A saved campaign reloads")

	assert_eq(RoguelikeRun.campaign["nodes"][node_id].get("shop_stock", []),
		["fighter", "corvette"],
		"A shop node's rolled stock persists across a campaign save/load")
	CampaignSaveManager.delete_save()


# ============================================================================
# SHOP UI (affordability gate + buying through the overlay)
# ============================================================================

func _find_buttons(node: Node, text: String, acc: Array) -> Array:
	for child in node.get_children():
		if child is Button and child.text == text:
			acc.append(child)
		_find_buttons(child, text, acc)
	return acc


func test_buy_button_is_disabled_when_unaffordable():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	RoguelikeRun.money = 0
	var shop := ShopScreen.new()
	add_child_autofree(shop)
	shop.setup({"shop_stock": ["fighter"]})

	var buys := _find_buttons(shop, "Buy", [])
	assert_eq(buys.size(), 1, "One ship is offered")
	assert_true(buys[0].disabled, "Buy is disabled when the player cannot afford the ship")


func _find_option_buttons(node: Node, acc: Array) -> Array:
	for child in node.get_children():
		if child is OptionButton:
			acc.append(child)
		_find_option_buttons(child, acc)
	return acc


func test_transfer_dropdown_defaults_to_placeholder_not_a_target():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	RoguelikeRun.money = 100000
	RoguelikeRun.add_purchased_hull("fighter")  # empty hull → a pilot vacancy
	var shop := ShopScreen.new()
	add_child_autofree(shop)
	shop.setup({"shop_stock": []})

	var dropdowns := _find_option_buttons(shop, [])
	assert_gt(dropdowns.size(), 0, "A transfer dropdown appears once a matching vacancy exists")
	var dd: OptionButton = dropdowns[0]
	assert_eq(dd.selected, 0, "The dropdown shows the placeholder by default, not a hull")
	assert_eq(dd.get_item_text(0), "Transfer to…", "Item 0 is the placeholder header")


func test_picking_a_transfer_target_moves_the_crew():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	RoguelikeRun.money = 100000
	var src: Dictionary = RoguelikeRun.fleet_hulls[0]
	var dest := RoguelikeRun.add_purchased_hull("fighter")
	var shop := ShopScreen.new()
	add_child_autofree(shop)
	shop.setup({"shop_stock": []})

	var dd: OptionButton = _find_option_buttons(shop, [])[0]
	dd.item_selected.emit(1)  # user picks the first transfer target

	assert_eq(RoguelikeRun.hull_by_id(dest.hull_id).crew.size(), 1,
		"Choosing a target transfers the crew member there")
	assert_true(src.crew.is_empty(), "...and removes them from the source hull")


func test_buying_through_the_overlay_consumes_stock_and_grows_the_fleet():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	RoguelikeRun.money = 100000
	var node := {"shop_stock": ["fighter"]}
	var before := RoguelikeRun.fleet_hulls.size()
	var shop := ShopScreen.new()
	add_child_autofree(shop)
	shop.setup(node)

	var buys := _find_buttons(shop, "Buy", [])
	buys[0].pressed.emit()

	assert_true(node.shop_stock.is_empty(), "The bought ship is removed from the node's stock")
	assert_eq(RoguelikeRun.fleet_hulls.size(), before + 1, "The fleet gains the purchased hull")


func _find_buttons_prefix(node: Node, prefix: String, acc: Array) -> Array:
	for child in node.get_children():
		if child is Button and child.text.begins_with(prefix):
			acc.append(child)
		_find_buttons_prefix(child, prefix, acc)
	return acc


## is_class only knows engine classes; script classes are found by script.
func _find_by_script(node: Node, script: Script, acc: Array) -> Array:
	for child in node.get_children():
		if child.get_script() == script:
			acc.append(child)
		_find_by_script(child, script, acc)
	return acc


func test_hire_button_shows_the_remaining_candidate_count():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	RoguelikeRun.money = 100000
	RoguelikeRun.add_purchased_hull("fighter")
	var pilots_left := CrewRosterManager.available_entries(
		RoguelikeRun.hired_roster_ids, CrewData.Role.PILOT).size()
	var shop := ShopScreen.new()
	add_child_autofree(shop)
	shop.setup({"shop_stock": []})

	var hires := _find_buttons_prefix(shop, "Hire (", [])
	assert_eq(hires.size(), 1, "One vacancy offers a hire")
	assert_eq(hires[0].text, "Hire (%d)" % pilots_left,
		"The hire button shows how many candidates remain in the pool")
	assert_false(hires[0].disabled, "With candidates available the button is live")


func test_hire_button_is_disabled_when_the_pool_is_exhausted():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	RoguelikeRun.money = 100000
	RoguelikeRun.add_purchased_hull("fighter")
	for entry in CrewRosterManager.load_roster():
		if entry.role == "pilot":
			RoguelikeRun.hired_roster_ids.append(entry.id)
	var shop := ShopScreen.new()
	add_child_autofree(shop)
	shop.setup({"shop_stock": []})

	var hires := _find_buttons_prefix(shop, "Hire (", [])
	assert_eq(hires[0].text, "Hire (0)", "An exhausted pool reads zero candidates")
	assert_true(hires[0].disabled, "...and cannot be pressed")


func test_hiring_through_the_candidate_dialog_fills_the_vacancy():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	RoguelikeRun.money = 100000
	var hull := RoguelikeRun.add_purchased_hull("fighter")
	var shop := ShopScreen.new()
	add_child_autofree(shop)
	shop.setup({"shop_stock": []})

	_find_buttons_prefix(shop, "Hire (", [])[0].pressed.emit()
	var dialogs := _find_by_script(shop, CrewHireDialog, [])
	assert_eq(dialogs.size(), 1, "Pressing Hire opens the candidate picker")

	# The first candidate is pre-selected; the footer hire button carries
	# their callsign ("Hire <callsign>", never "Hire (").
	var confirm: Button = _find_buttons_prefix(dialogs[0], "Hire ", [])[0]
	assert_false(confirm.disabled, "A pre-selected candidate can be hired")
	confirm.pressed.emit()

	assert_eq(hull.crew.size(), 1, "Confirming the candidate fills the vacancy")
	assert_eq(RoguelikeRun.hull_vacancies(hull).size(), 0,
		"The fighter's only slot is no longer vacant")


func test_clicking_a_crew_callsign_opens_their_stat_sheet():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	var callsign: String = RoguelikeRun.fleet_hulls[0].crew[0].callsign
	var shop := ShopScreen.new()
	add_child_autofree(shop)
	shop.setup({"shop_stock": []})

	var name_buttons := _find_buttons(shop, callsign, [])
	assert_eq(name_buttons.size(), 1, "The crew member's callsign is clickable")
	name_buttons[0].pressed.emit()

	assert_eq(_find_by_script(shop, CrewViewModal, []).size(), 1,
		"Clicking a callsign opens the crew member's stat sheet")


func test_roster_renders_condition_for_a_damaged_hull():
	RoguelikeRun.start_run(_counts({"corvette": 1}))
	# Persist a damaged ship state so the roster header's condition meters
	# render off the damaged branch (not the pristine 100%/100% shortcut).
	var ship := ShipData.create_ship_instance("corvette", 0, Vector2.ZERO)
	ship["armor_sections"][0]["current_armor"] = 0
	ship.erase("crew")
	RoguelikeRun.fleet_hulls[0].ship = ship
	var shop := ShopScreen.new()
	add_child_autofree(shop)

	shop.setup({"shop_stock": []})

	# The damaged hull still renders in the roster with its ice toggle intact.
	assert_gt(_find_buttons(shop, "Put on ice", []).size(), 0,
		"A damaged hull renders in the roster with condition shown and controls working")
