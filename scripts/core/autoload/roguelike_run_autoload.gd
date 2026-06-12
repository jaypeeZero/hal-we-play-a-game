extends Node

## Holds state for an active Roguelike campaign: the player's persistent
## fleet, the enemy's persistent fleet, and the multi-sector star chart.
## When `active` is true, the battle scene and map scene swap their behavior
## to use this state instead of the on-disk team fleets.

## Star dates: each jump advances the date by the destination node's gap;
## jump repairs scale with the gap (longer downtime, more repair time).
const STAR_DATE_RUN_START = 2300

var active: bool = false
var started_first_battle: bool = false
## The player fleet as per-hull records, each with a stable identity:
## {
##   "hull_id": String,          # stable for the run
##   "ship_type": String,
##   "iced": bool,               # mothballed: never sorties, no per-battle ship cost
##   "crew": Array,              # crew dicts; may be empty (purchased hull) or partial
##   "complement": Array,        # fixed standard crew slots [{role, weapon_id?}, ...]
##   "ship": Dictionary,         # persisted damage state, crew stripped; {} = pristine
## }
## Per-hull identity lets ships be moved, iced, lost, or purchased without the
## old type+order matching: survivors carry their hull_id back from battle.
var fleet_hulls: Array = []
## Player standing instructions for this run (see DoctrineSystem).
## Run state: reset at run start, wiped at run end.
var doctrine: Dictionary = DoctrineSystem.empty_doctrine()
var enemy_fleet: Dictionary = {}
## The multi-sector star chart (see CampaignGenerator.generate).
var campaign: Dictionary = {}
## Run economy: credits on hand, spent on ships/upkeep/insurance and earned
## from battle rewards (see EconomySystem). Rolled at run start.
var money: int = 0
## Summary of the most recent battle's economy (reward, insurance, casualties),
## kept so the map can report it once the player returns. Wiped after display.
var last_battle_summary: Dictionary = {}
var pending_battle_node_id: String = ""
## Battle outcome (CampaignSystem.RESULT_*) stashed by the battle scene
## and consumed by the campaign map's _resolve_pending_battle.
var pending_battle_result: String = ""
## Final state of a wiped fleet (ships and crew groups at the moment of
## defeat), kept so a demotion can roll damaged survivors from it.
var lost_fleet_final_ships: Array = []
var lost_fleet_final_crew: Array = []
var editor_return_scene: String = ""
var current_star_date: int = STAR_DATE_RUN_START
## Last jump's repair summary, kept so the map can report repairs that
## happened on the way into a battle once the player returns to the map.
var last_jump_repair_summary: Dictionary = {}

## Skill for throwaway template crews that only derive a hull's standard
## complement (slot roles + weapon bindings); template members are never
## fielded, so the value is irrelevant.
const COMPLEMENT_TEMPLATE_SKILL := 0.5

## Roster entry ids consumed from the hiring pool this run — by run-start
## crews, demotion refills, and shop hires alike. Consumed ids never return
## to the pool, even when the crew member dies or is dismissed. Reset when a
## run starts or ends; persisted with the campaign save.
var hired_roster_ids: Array = []
## Monotonic source of unique hull ids for the run.
var _next_hull_id: int = 0


func start_run(initial_fleet: Dictionary) -> void:
	active = true
	started_first_battle = false
	hired_roster_ids = []
	_next_hull_id = 0
	fleet_hulls = _create_fleet_roster(initial_fleet)
	doctrine = DoctrineSystem.empty_doctrine()
	campaign = CampaignGenerator.generate(_new_rng())
	enemy_fleet = CampaignSystem.scaled_enemy_fleet(
		FleetDataManager.load_fleet(1), campaign["current_sector"])
	money = EconomySystem.roll_starting_money(fleet_hulls, _new_rng())
	last_battle_summary = {}
	pending_battle_node_id = ""
	pending_battle_result = ""
	lost_fleet_final_ships = []
	lost_fleet_final_crew = []
	current_star_date = STAR_DATE_RUN_START
	last_jump_repair_summary = {}


func end_run() -> void:
	active = false
	started_first_battle = false
	fleet_hulls = []
	doctrine = DoctrineSystem.empty_doctrine()
	enemy_fleet = {}
	campaign = {}
	money = 0
	last_battle_summary = {}
	pending_battle_node_id = ""
	pending_battle_result = ""
	lost_fleet_final_ships = []
	lost_fleet_final_crew = []
	current_star_date = STAR_DATE_RUN_START
	last_jump_repair_summary = {}
	hired_roster_ids = []
	_next_hull_id = 0


## A freshly seeded RNG for economy rolls. Centralized so all run-economy
## randomness flows through one place.
func _new_rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng


func _create_fleet_roster(fleet_counts: Dictionary) -> Array:
	var roster: Array = []
	for ship_type in FleetDataManager.SHIP_TYPES:
		for _i in range(int(fleet_counts.get(ship_type, 0))):
			roster.append(_make_hull(ship_type))
	return roster


## Create one hull record for a ship type. With `with_crew`, the complement
## is crewed from the roster hiring pool (slots whose role is exhausted in
## the pool stay vacant); otherwise the hull arrives empty (a purchased bare
## hull). The standard `complement` is always derived so vacancies are known
## even for an empty hull.
func _make_hull(ship_type: String, with_crew := true) -> Dictionary:
	var weapons: Array = ShipData.get_ship_template(ship_type).get("weapons", [])
	var template_crew: Array = CrewData.create_crew_for_ship_type(
		ship_type, weapons.size(), COMPLEMENT_TEMPLATE_SKILL)
	template_crew = CrewData.bind_gunners_to_weapons(template_crew, weapons)
	var complement: Array = _complement_from_crew(template_crew)
	var crew: Array = _crew_from_pool(template_crew) if with_crew else []
	var hull_id := "hull_%d" % _next_hull_id
	_next_hull_id += 1
	return {
		"hull_id": hull_id,
		"ship_type": ship_type,
		"iced": false,
		"crew": crew,
		"complement": complement,
		"ship": {},
	}


## Crew a template complement from the roster hiring pool: each template
## member takes a drawn pool entry's identity and skills while keeping the
## template's structure (crew_id, command chain, weapon binding). Members
## whose role is exhausted in the pool are dropped — their slot stays a
## vacancy for the shop to fill later.
func _crew_from_pool(template_crew: Array) -> Array:
	var rng := _new_rng()
	var crew: Array = []
	for member in template_crew:
		var entry := _draw_from_pool(int(member.get("role", CrewData.Role.PILOT)), rng)
		if entry.is_empty():
			continue
		crew.append(CrewData.apply_roster_entry(member, entry))
	return _prune_command_chains(crew)


## Draw one random available roster entry of `role` and consume it from the
## run's pool. {} when the pool has no one of that role left.
func _draw_from_pool(role: int, rng: RandomNumberGenerator) -> Dictionary:
	var candidates := CrewRosterManager.available_entries(hired_roster_ids, role)
	if candidates.is_empty():
		return {}
	var entry: Dictionary = candidates[rng.randi_range(0, candidates.size() - 1)]
	hired_roster_ids.append(entry.id)
	return entry


## Remove command-chain references to crew that were dropped (pool-exhausted
## slots), so nobody reports to or commands a member who never boarded.
func _prune_command_chains(crew: Array) -> Array:
	var kept := {}
	for member in crew:
		kept[member.crew_id] = true
	for member in crew:
		if member.command_chain.superior != null and not kept.has(member.command_chain.superior):
			member.command_chain.superior = null
		member.command_chain.subordinates = member.command_chain.subordinates.filter(
			func(crew_id): return kept.has(crew_id))
	return crew


## The fixed standard crew slots for a hull, derived from a freshly created
## crew. Drives vacancy detection when hiring or transferring.
func _complement_from_crew(crew: Array) -> Array:
	var complement: Array = []
	for member in crew:
		var slot := {"role": member.get("role", CrewData.Role.PILOT)}
		if member.has("weapon_id"):
			slot["weapon_id"] = member.weapon_id
		complement.append(slot)
	return complement


func hull_by_id(hull_id: String) -> Dictionary:
	for hull in fleet_hulls:
		if hull.get("hull_id", "") == hull_id:
			return hull
	return {}


## A hull sorties when it is not mothballed and has someone to fly it.
func _has_pilot(hull: Dictionary) -> bool:
	for member in hull.get("crew", []):
		if member.get("role", -1) == CrewData.Role.PILOT:
			return true
	return false


## Hulls that take the field this battle: active (not iced) and crewed by a
## pilot. Empty purchased hulls and mothballed hulls stay home.
func sortieable_hulls() -> Array:
	return fleet_hulls.filter(
		func(hull): return not hull.get("iced", false) and _has_pilot(hull))


## Hulls the player likely expects to fight but won't: active (not deliberately
## iced) yet with no pilot to fly them — a Capital whose pilot was dismissed or
## killed, or a bought hull never crewed. Surfaced before launch so a ship is
## never silently left behind.
func benched_hulls() -> Array:
	return fleet_hulls.filter(
		func(hull): return not hull.get("iced", false) and not _has_pilot(hull))


## Fleet composition counts by ship type. With `only_sortieable`, counts only
## the hulls that will actually take the field (drives the battle plan).
func fleet_counts(only_sortieable := false) -> Dictionary:
	var counts: Dictionary = {}
	for ship_type in FleetDataManager.SHIP_TYPES:
		counts[ship_type] = 0
	var hulls: Array = sortieable_hulls() if only_sortieable else fleet_hulls
	for hull in hulls:
		var t: String = hull.get("ship_type", "")
		if counts.has(t):
			counts[t] += 1
	return counts


## Fold a battle's outcome back into the persistent fleet. Survivors carry
## their hull_id and live crew; their damage state and crew replace the hull's
## records. Sortied hulls that did not survive are removed (and their doctrine
## pruned). Iced / uncrewed hulls never sortied and are left untouched.
func apply_battle_outcome(surviving_ships: Array) -> void:
	var survivors_by_id: Dictionary = {}
	for ship in surviving_ships:
		survivors_by_id[ship.get("hull_id", "")] = ship

	var rng := _new_rng()
	var new_hulls: Array = []
	var dropped_crew_ids: Array = []
	var death_count: int = 0
	for hull in fleet_hulls:
		var sortied: bool = not hull.get("iced", false) and _has_pilot(hull)
		if not sortied:
			new_hulls.append(hull)
			continue
		var hull_id: String = hull.get("hull_id", "")
		if survivors_by_id.has(hull_id):
			var survivor: Dictionary = survivors_by_id[hull_id]
			var after: Dictionary = _strip_crew(survivor)
			# Crew aboard a surviving hull live or die by the components that
			# were destroyed this battle (sortie-time state vs the survivor).
			var live_crew: Array = survivor.get("crew", []).duplicate(true)
			var casualties: Dictionary = CasualtySystem.resolve_hull_casualties(
				live_crew, hull.get("ship", {}), after, rng)
			hull.crew = casualties.survivors
			hull.ship = after
			for dead in casualties.deaths:
				dropped_crew_ids.append(dead.get("crew_id", ""))
			death_count += casualties.deaths.size()
			new_hulls.append(hull)
		else:
			# A hull lost with all hands: everyone aboard is a casualty.
			for member in hull.get("crew", []):
				dropped_crew_ids.append(member.get("crew_id", ""))
				death_count += 1

	fleet_hulls = new_hulls
	var insurance: int = EconomySystem.insurance_total(death_count)
	money -= insurance
	last_battle_summary = {"casualties": death_count, "insurance": insurance}
	_prune_doctrine_for_roster(dropped_crew_ids, fleet_counts())


## A survivor ship dict as it persists between battles: crew is stored on the
## hull, not inside the ship damage state.
func _strip_crew(ship: Dictionary) -> Dictionary:
	var stripped: Dictionary = ship.duplicate(true)
	stripped.erase("crew")
	return stripped


## Rebuild the fleet to match new ship counts while preserving the identity of
## hulls that remain. Existing hulls of each type are kept in order up to the
## new count; surplus counts spawn fresh hulls, shortfalls drop trailing hulls.
## Doctrine is reconciled for dropped crew. Used by the Edit Fleet screen so
## fleet edits mid-setup keep the doctrine already authored for survivors.
func reconcile_roster_to_counts(new_counts: Dictionary) -> void:
	var existing_by_type: Dictionary = {}
	for hull in fleet_hulls:
		var t: String = hull.get("ship_type", "")
		if not existing_by_type.has(t):
			existing_by_type[t] = []
		existing_by_type[t].append(hull)

	var new_hulls: Array = []
	var dropped_crew_ids: Array = []
	for ship_type in FleetDataManager.SHIP_TYPES:
		var desired: int = int(new_counts.get(ship_type, 0))
		var existing: Array = existing_by_type.get(ship_type, [])
		for i in range(desired):
			if i < existing.size():
				new_hulls.append(existing[i])
			else:
				new_hulls.append(_make_hull(ship_type))
		for i in range(desired, existing.size()):
			for member in existing[i].get("crew", []):
				dropped_crew_ids.append(member.get("crew_id", ""))

	fleet_hulls = new_hulls
	_prune_doctrine_for_roster(dropped_crew_ids, new_counts)

	# The run starts at the main menu, so the player can still edit the fleet
	# before the first battle. Keep starting money matched to the fleet they
	# actually launch with — but freeze it once the run is underway.
	if not started_first_battle:
		money = EconomySystem.roll_starting_money(fleet_hulls, _new_rng())


## Drop doctrine that no longer has a referent after a roster change.
func _prune_doctrine_for_roster(dropped_crew_ids: Array, new_counts: Dictionary) -> void:
	for crew_id in dropped_crew_ids:
		doctrine[DoctrineSystem.SCOPE_CREW].erase(crew_id)
		doctrine["disabled"].erase(crew_id)
	for ship_type in FleetDataManager.SHIP_TYPES:
		if int(new_counts.get(ship_type, 0)) == 0:
			doctrine[DoctrineSystem.SCOPE_CLASS].erase(ship_type)


# ============================================================================
# ROSTER OPS (shop screen: buy hulls, hire/transfer crew, ice ships)
# ============================================================================

## Buy a bare hull of `ship_type`: full standard complement, no crew aboard,
## price deducted from money. Returns the new hull record.
func add_purchased_hull(ship_type: String) -> Dictionary:
	var hull := _make_hull(ship_type, false)
	money -= EconomySystem.ship_purchase_price(ship_type)
	fleet_hulls.append(hull)
	return hull


## The unfilled crew slots on a hull: its standard complement minus the crew
## currently aboard. Gunner slots are matched by weapon_id (so a hull missing
## one specific gun's gunner shows exactly that vacancy); other roles match by
## count.
func hull_vacancies(hull: Dictionary) -> Array:
	var filled_weapon_ids: Dictionary = {}
	var remaining_role_counts: Dictionary = {}
	for member in hull.get("crew", []):
		var role: int = member.get("role", -1)
		if role == CrewData.Role.GUNNER and member.has("weapon_id"):
			filled_weapon_ids[member.weapon_id] = true
		else:
			remaining_role_counts[role] = remaining_role_counts.get(role, 0) + 1

	var vacancies: Array = []
	for slot in hull.get("complement", []):
		var role: int = slot.get("role", -1)
		if role == CrewData.Role.GUNNER and slot.has("weapon_id"):
			if not filled_weapon_ids.has(slot.weapon_id):
				vacancies.append(slot)
		elif remaining_role_counts.get(role, 0) > 0:
			remaining_role_counts[role] -= 1
		else:
			vacancies.append(slot)
	return vacancies


## Hire one roster candidate into one vacant slot on a hull (weapon bound for
## gunner slots, wired into the hull's command chain). Fails when the slot is
## not a real vacancy, the candidate is already consumed this run, no longer
## exists in the roster (mid-run override edit), or has the wrong role.
func fill_vacancy(hull_id: String, slot: Dictionary, roster_id: String) -> bool:
	var hull := hull_by_id(hull_id)
	if hull.is_empty() or not _slot_is_vacant(hull, slot):
		return false
	if hired_roster_ids.has(roster_id):
		return false
	var entry := CrewRosterManager.entry_by_id(roster_id)
	if entry.is_empty():
		return false
	var slot_role: int = slot.get("role", CrewData.Role.PILOT)
	if CrewData.role_from_name(entry.role) != slot_role:
		return false
	var member := CrewData.from_roster_entry(entry)
	if slot_role == CrewData.Role.GUNNER and slot.has("weapon_id"):
		member["weapon_id"] = slot.weapon_id
	_wire_into_command_chain(hull, member)
	hull.crew.append(member)
	hired_roster_ids.append(roster_id)
	return true


## Move a crew member into a matching vacancy on another hull. Succeeds only
## when the destination has an unfilled slot of the same role; gunners rebind
## to that slot's weapon. The crew dict (identity, skills, doctrine) is intact.
func transfer_crew(crew_id: String, dest_hull_id: String) -> bool:
	var dest := hull_by_id(dest_hull_id)
	if dest.is_empty():
		return false

	var src: Dictionary = {}
	var member: Dictionary = {}
	for hull in fleet_hulls:
		for m in hull.get("crew", []):
			if m.get("crew_id", "") == crew_id:
				src = hull
				member = m
	if member.is_empty() or src.get("hull_id", "") == dest_hull_id:
		return false

	var slot := _matching_vacancy(dest, member)
	if slot.is_empty():
		return false

	src.crew.erase(member)
	_unwire_from_command_chain(src, member)
	if slot.get("role", -1) == CrewData.Role.GUNNER and slot.has("weapon_id"):
		member["weapon_id"] = slot.weapon_id
	elif member.has("weapon_id"):
		member.erase("weapon_id")
	_wire_into_command_chain(dest, member)
	dest.crew.append(member)
	return true


## Mothball or reactivate a hull. Iced hulls never sortie and cost no per-battle
## ship upkeep (their crew are still paid).
func set_hull_iced(hull_id: String, iced: bool) -> void:
	var hull := hull_by_id(hull_id)
	if not hull.is_empty():
		hull.iced = iced


## Dismiss a whole hull and everyone aboard (no insurance — they are let go,
## not lost). Used by the dismissal dialog to cut upkeep. Doctrine for the
## dismissed crew is pruned.
func dismiss_hull(hull_id: String) -> void:
	var hull := hull_by_id(hull_id)
	if hull.is_empty():
		return
	var dropped: Array = []
	for member in hull.get("crew", []):
		dropped.append(member.get("crew_id", ""))
	fleet_hulls.erase(hull)
	_prune_doctrine_for_roster(dropped, fleet_counts())


## Dismiss a single crew member, opening a vacancy on their hull (no insurance).
func dismiss_crew(crew_id: String) -> void:
	for hull in fleet_hulls:
		for member in hull.get("crew", []):
			if member.get("crew_id", "") == crew_id:
				_unwire_from_command_chain(hull, member)
				hull.crew.erase(member)
				_prune_doctrine_for_roster([crew_id], fleet_counts())
				return


## Whether the player can still field a minimum battle force: at least one
## piloted hull whose solo upkeep (its ship cost + one pilot's salary, every
## other hull and crew dismissed) is affordable. False ⇒ the run is lost.
func can_field_minimum() -> bool:
	return _can_field_minimum(fleet_hulls, money)


## Pure form: is a minimum affordable battle force fieldable from `hulls` with
## `funds`? Used both for the live check and to vet a prospective dismissal.
func _can_field_minimum(hulls: Array, funds: int) -> bool:
	var salary := EconomySystem.crew_salary_per_battle()
	var cheapest := -1
	for hull in hulls:
		if not _has_pilot(hull):
			continue
		var cost := EconomySystem.ship_per_battle_cost(hull.get("ship_type", "")) + salary
		if cheapest < 0 or cost < cheapest:
			cheapest = cost
	if cheapest < 0:
		return false
	return funds >= cheapest


## Whether this crew member may be dismissed without soft-locking the run —
## i.e. a minimum affordable force is still fieldable afterward. The dismissal
## dialog disables dismissals that would fail this (e.g. the last affordable
## pilot). Non-pilots and crew on a redundant hull are always safe.
func may_dismiss_crew(crew_id: String) -> bool:
	var hulls := fleet_hulls.duplicate(true)
	for hull in hulls:
		var crew: Array = hull.get("crew", [])
		for i in range(crew.size()):
			if crew[i].get("crew_id", "") == crew_id:
				crew.remove_at(i)
				return _can_field_minimum(hulls, money)
	return true


## Whether this whole hull may be dismissed without soft-locking the run.
func may_dismiss_hull(hull_id: String) -> bool:
	var hulls := fleet_hulls.filter(func(h): return h.get("hull_id", "") != hull_id)
	return _can_field_minimum(hulls, money)


func _slot_is_vacant(hull: Dictionary, slot: Dictionary) -> bool:
	for vacancy in hull_vacancies(hull):
		if vacancy.get("role", -2) == slot.get("role", -1) \
				and vacancy.get("weapon_id", "") == slot.get("weapon_id", ""):
			return true
	return false


func _matching_vacancy(hull: Dictionary, member: Dictionary) -> Dictionary:
	var role: int = member.get("role", -1)
	for slot in hull_vacancies(hull):
		if slot.get("role", -2) == role:
			return slot
	return {}


## A hull's commander is its captain, or its pilot on craft with no captain.
func _hull_commander(hull: Dictionary) -> Dictionary:
	var captain := _find_role(hull, CrewData.Role.CAPTAIN)
	return captain if not captain.is_empty() else _find_role(hull, CrewData.Role.PILOT)


func _find_role(hull: Dictionary, role: int) -> Dictionary:
	for member in hull.get("crew", []):
		if member.get("role", -1) == role:
			return member
	return {}


func _wire_into_command_chain(hull: Dictionary, member: Dictionary) -> void:
	var commander := _hull_commander(hull)
	if commander.is_empty() or commander.get("crew_id", "") == member.get("crew_id", ""):
		return
	member.command_chain.superior = commander.crew_id
	if member.crew_id not in commander.command_chain.subordinates:
		commander.command_chain.subordinates.append(member.crew_id)


func _unwire_from_command_chain(hull: Dictionary, member: Dictionary) -> void:
	var commander := _hull_commander(hull)
	if not commander.is_empty():
		commander.command_chain.subordinates.erase(member.get("crew_id", ""))


## The run is lost when no hulls remain at all.
func is_fleet_empty() -> bool:
	return fleet_hulls.is_empty()


## Repair the fleet during a jump. Engineers use the downtime: each heals
## their ship by REPAIR_FRACTION_PER_STAR_DATE × machinery skill × date gap
## (× RNR_REPAIR_MULTIPLIER when the destination is an R&R stop). Pristine
## hulls (no recorded damage) and crewless hulls are skipped.
## Returns {ships_repaired, points_repaired, date_delta}.
func apply_jump_repairs(destination_star_date: int, is_rnr: bool) -> Dictionary:
	var date_delta: int = maxi(0, destination_star_date - current_star_date)
	current_star_date = destination_star_date

	var fraction: float = WingConstants.REPAIR_FRACTION_PER_STAR_DATE * date_delta
	if is_rnr:
		fraction *= WingConstants.RNR_REPAIR_MULTIPLIER

	var ships_repaired := 0
	var points_repaired := 0
	for hull in fleet_hulls:
		var saved: Dictionary = hull.get("ship", {})
		if saved.is_empty():
			continue
		var merged: Dictionary = saved.duplicate(true)
		merged["crew"] = hull.get("crew", [])
		var before := _ship_health_total(merged)
		var repaired: Dictionary = RepairSystem.apply_engineer_repairs(merged, fraction)
		var healed := _ship_health_total(repaired) - before
		if healed > 0:
			ships_repaired += 1
			points_repaired += healed
		hull.ship = _strip_crew(repaired)

	last_jump_repair_summary = {
		"ships_repaired": ships_repaired,
		"points_repaired": points_repaired,
		"date_delta": date_delta,
	}
	return last_jump_repair_summary


func _ship_health_total(ship: Dictionary) -> int:
	return DamageResolver.calculate_total_armor(ship) + DamageResolver.calculate_total_internal_health(ship)


## Record a battle's outcome for the campaign map to resolve. Victory folds
## the survivors back into the persistent hull fleet (damage, casualties,
## insurance, doctrine pruning all via apply_battle_outcome). Defeat stashes
## the wiped fleet's final state so a demotion can roll damaged survivors
## from it, then empties the hull fleet. `final_ships` is every team-0 ship's
## end-of-battle state, each carrying its hull_id and its live crew.
func record_battle_result(result: String, final_ships: Array) -> void:
	pending_battle_result = result
	if result == CampaignSystem.RESULT_VICTORY:
		apply_battle_outcome(final_ships.filter(
			func(ship): return ship.get("status", "") != "destroyed"))
		lost_fleet_final_ships = []
		lost_fleet_final_crew = []
	else:
		lost_fleet_final_ships = final_ships.duplicate(true)
		lost_fleet_final_crew = _crew_groups_for_ships(final_ships)
		fleet_hulls = []


## Crew groups (ship_type + crew) rebuilt from the crew attached to each ship
## dict. Feeds the demotion survivor roll (DemotionFleetBuilder), which matches
## crews to ships by type.
func _crew_groups_for_ships(ships: Array) -> Array:
	var groups: Array = []
	for ship in ships:
		var members: Array = ship.get("crew", [])
		if not members.is_empty():
			groups.append({"ship_type": ship.get("type", ""), "crew": members.duplicate(true)})
	return groups


## Rebuild the run's hull fleet for a demotion: the saved fleet config (fresh
## hulls, fresh crews, undamaged) plus the rolled survivors of the lost fleet
## (battered hulls keeping their crews). Survivor crews keep their identity;
## doctrine authored for crew that did not survive the rout is pruned.
func apply_demotion(survivors: Dictionary, fleet_config: Dictionary) -> void:
	var survivor_ships: Array = survivors.get("ships", [])
	var survivor_crew_groups: Array = survivors.get("crew_groups", [])

	var dead_ids := _dead_crew_ids(survivor_crew_groups)
	fleet_hulls = _create_fleet_roster(fleet_config)
	for survivor_hull in _hulls_from_survivors(survivor_ships, survivor_crew_groups):
		fleet_hulls.append(survivor_hull)

	_prune_doctrine_for_roster(dead_ids, fleet_counts())
	# The stash is consumed: the demotion is its only reader.
	lost_fleet_final_ships = []
	lost_fleet_final_crew = []


## Turn the demotion's rolled survivor ships + crew groups into hull records:
## each battered ship becomes a hull keeping its damage state and (by type) its
## surviving crew, so the limped-home remnant carries forward intact.
func _hulls_from_survivors(survivor_ships: Array, survivor_crew_groups: Array) -> Array:
	var remaining_groups: Array = survivor_crew_groups.duplicate(true)
	var hulls: Array = []
	for ship in survivor_ships:
		var ship_type: String = ship.get("type", "")
		var crew: Array = _take_crew_group_for_type(remaining_groups, ship_type)
		var weapons: Array = ShipData.get_ship_template(ship_type).get("weapons", [])
		var template_crew: Array = CrewData.bind_gunners_to_weapons(
			CrewData.create_crew_for_ship_type(ship_type, weapons.size(), COMPLEMENT_TEMPLATE_SKILL), weapons)
		var hull_id := "hull_%d" % _next_hull_id
		_next_hull_id += 1
		hulls.append({
			"hull_id": hull_id,
			"ship_type": ship_type,
			"iced": false,
			"crew": crew,
			"complement": _complement_from_crew(template_crew),
			"ship": _strip_crew(ship),
		})
	return hulls


func _take_crew_group_for_type(groups: Array, ship_type: String) -> Array:
	for i in range(groups.size()):
		if groups[i].get("ship_type", "") == ship_type:
			return groups.pop_at(i).get("crew", [])
	return []


## Crew ids present in the lost fleet's final state but absent from the
## demotion survivors: their doctrine no longer has a referent.
func _dead_crew_ids(survivor_crew_groups: Array) -> Array:
	var survived := {}
	for group in survivor_crew_groups:
		for member in group.get("crew", []):
			survived[member.get("crew_id", "")] = true
	var dead: Array = []
	for group in lost_fleet_final_crew:
		for member in group.get("crew", []):
			var crew_id: String = member.get("crew_id", "")
			if not survived.has(crew_id):
				dead.append(crew_id)
	return dead


func save_campaign_to_disk() -> bool:
	return CampaignSaveManager.save_campaign({
		"campaign": campaign,
		"fleet_hulls": fleet_hulls,
		"doctrine": doctrine,
		"enemy_fleet": enemy_fleet,
		"money": money,
		"current_star_date": current_star_date,
		"hired_roster_ids": hired_roster_ids,
		"next_hull_id": _next_hull_id,
	})


## Resume a saved campaign. Returns false (leaving the run untouched)
## when no usable save exists.
func load_campaign_from_disk() -> bool:
	var data := CampaignSaveManager.load_campaign()
	if data.is_empty():
		return false
	campaign = data.get("campaign", {})
	fleet_hulls = data.get("fleet_hulls", [])
	doctrine = data.get("doctrine", DoctrineSystem.empty_doctrine())
	enemy_fleet = data.get("enemy_fleet", {})
	money = int(data.get("money", 0))
	current_star_date = data.get("current_star_date", STAR_DATE_RUN_START)
	# Older saves have no consumed-pool list: an unconsumed pool is correct
	# for them, since their crews predate roster hiring.
	hired_roster_ids = data.get("hired_roster_ids", [])
	_next_hull_id = data.get("next_hull_id", fleet_hulls.size())
	last_battle_summary = {}
	pending_battle_node_id = ""
	pending_battle_result = ""
	lost_fleet_final_ships = []
	lost_fleet_final_crew = []
	last_jump_repair_summary = {}
	started_first_battle = not fleet_hulls.is_empty()
	active = true
	return true
