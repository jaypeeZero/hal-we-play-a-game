class_name ShopScreen
extends OverlayScreen

## Full-screen shop overlay for a SHOP map node. Three sections operate on
## RoguelikeRun's economy and roster:
##   - Ships for sale: buy a bare hull (price deducted, arrives crewless).
##   - Hiring: fill a hull's vacant crew slots (recurring salary, no up-front
##     cost; insurance is owed if they later die).
##   - Fleet roster: crew assignment board (drag-and-drop + ice/activate).
## Purchases mutate the node's `shop_stock` in place so a bought ship is gone
## when the player reopens the shop (stock persists on the campaign node, saved
## via CampaignSaveManager). Every action rebuilds the content. `closed` fires
## when the player leaves.

const CARD_MIN_WIDTH := 230
## Below this fraction, an armor/systems meter is shown in the warning colour.
const CONDITION_LOW_RATIO := 0.6
## Flag shown beside crew serving in a role they are not qualified for.
const OFF_ROLE_TAG := "⚠ off-role %d%%" % int(round((CrewData.OFF_ROLE_PERFORMANCE_MULTIPLIER - 1.0) * 100.0))

var _shop_node: Dictionary = {}
var _money_label: Label
var _content: VBoxContainer


func setup(shop_node: Dictionary) -> void:
	_shop_node = shop_node
	build_chrome()
	var topbar := _build_topbar()
	var body_scroll := _build_body()
	var leave := UiKit.style_button(_make_button("Leave shop"), "warn")
	leave.pressed.connect(func(): emit_closed())
	footer.add_child(leave)
	_finalize_chrome(topbar, body_scroll)
	_rebuild()


# UI CONSTRUCTION

func _build_topbar() -> Control:
	var bar := UiKit.card(UiKit.PANEL_2, UiKit.LINE, 14)
	var row := HBoxContainer.new()
	bar.add_child(row)

	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_child(UiKit.label("SHIPYARD & CREW HALL", UiKit.INK, 16))
	title_box.add_child(UiKit.label("Trade outpost", UiKit.DIM, 11))
	row.add_child(title_box)

	var manage_btn := Button.new()
	manage_btn.text = "Manage Crew"
	UiKit.style_button(manage_btn, "ghost")
	manage_btn.pressed.connect(func() -> void:
		FleetCommandScreen.open_overlay(self))
	row.add_child(manage_btn)

	var credits_box := VBoxContainer.new()
	credits_box.alignment = BoxContainer.ALIGNMENT_END
	_money_label = UiKit.label("", UiKit.GOLD, 26)
	_money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	credits_box.add_child(_money_label)
	var lbl := UiKit.label("CREDITS", UiKit.DIM, 10)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	credits_box.add_child(lbl)
	row.add_child(credits_box)
	return bar


func _build_body() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", SECTION_GAP)
	scroll.add_child(_content)
	return scroll


func _rebuild() -> void:
	_money_label.text = _commas(RoguelikeRun.money)
	for child in _content.get_children():
		child.queue_free()
	_build_ships_for_sale()
	_build_hiring()


# SECTION: SHIPS FOR SALE

func _build_ships_for_sale() -> void:
	_content.add_child(UiKit.section_title("Ships for sale", "hulls arrive crewless — hire below"))
	var stock: Array = _shop_node.get("shop_stock", [])
	if stock.is_empty():
		_content.add_child(UiKit.label("Nothing in stock.", UiKit.DIM))
		return

	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	_content.add_child(grid)

	for i in range(stock.size()):
		grid.add_child(_ship_card(stock[i], i))


func _ship_card(ship_type: String, stock_index: int) -> Control:
	var price := EconomySystem.ship_purchase_price(ship_type)
	var affordable := RoguelikeRun.money >= price

	var card := UiKit.card()
	card.custom_minimum_size = Vector2(CARD_MIN_WIDTH, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)
	card.add_child(box)

	box.add_child(UiKit.label(_type_label(ship_type), UiKit.INK, 14))

	var stats := HBoxContainer.new()
	var upkeep := UiKit.label("upkeep %d/battle" % EconomySystem.ship_per_battle_cost(ship_type), UiKit.DIM, 12)
	upkeep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.add_child(upkeep)
	stats.add_child(UiKit.label("%d cr" % price, UiKit.GOLD if affordable else UiKit.BAD, 13))
	box.add_child(stats)

	var foot := HBoxContainer.new()
	var tag := UiKit.label(
		"CREWLESS HULL" if affordable else "CAN'T AFFORD",
		UiKit.DIM if affordable else UiKit.BAD, 10)
	tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(tag)

	var buy := UiKit.style_button(_make_button("Buy"), "primary")
	buy.disabled = not affordable
	buy.pressed.connect(func(): _on_buy(stock_index))
	foot.add_child(buy)
	box.add_child(foot)
	return card


func _on_buy(stock_index: int) -> void:
	var stock: Array = _shop_node.get("shop_stock", [])
	if stock_index < 0 or stock_index >= stock.size():
		return
	var ship_type: String = stock[stock_index]
	if RoguelikeRun.money < EconomySystem.ship_purchase_price(ship_type):
		return
	RoguelikeRun.add_purchased_hull(ship_type)
	stock.remove_at(stock_index)
	_rebuild()


# SECTION: HIRING

func _build_hiring() -> void:
	_content.add_child(UiKit.section_title("Hire crew",
		"%d/battle salary · %d insurance on death" % [
			EconomySystem.crew_salary_per_battle(), EconomySystem.crew_insurance_payout()]))

	var any := false
	for hull in RoguelikeRun.fleet_hulls:
		var vacancies: Array = RoguelikeRun.hull_vacancies(hull)
		if vacancies.is_empty():
			continue
		any = true
		_content.add_child(_hire_hull_card(hull, vacancies))

	if not any:
		_content.add_child(UiKit.label("Every hull is fully crewed.", UiKit.DIM))


func _hire_hull_card(hull: Dictionary, vacancies: Array) -> Control:
	var card := UiKit.card(UiKit.PANEL, UiKit.LINE, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	card.add_child(box)
	box.add_child(_hull_header(hull, null))

	for slot in vacancies:
		var row := _row()
		row.add_child(UiKit.label(CrewData.get_role_name(slot.get("role", -1)), UiKit.GOLD, 11))
		if slot.has("weapon_id"):
			row.add_child(UiKit.label(slot.weapon_id, UiKit.ACCENT, 11))
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
		var hull_id: String = hull.hull_id
		var slot_copy: Dictionary = slot
		var candidates := RoguelikeRun.available_crew(slot.get("role", CrewData.Role.PILOT))
		var hire := UiKit.style_button(
			_make_button("Hire (%d)" % candidates.size()), "primary")
		hire.disabled = candidates.is_empty()
		if candidates.is_empty():
			hire.tooltip_text = "No candidates left in the roster pool"
		hire.pressed.connect(func(): _open_hire_dialog(hull_id, slot_copy))
		row.add_child(hire)
		box.add_child(_indented(row))
	return card


func _open_hire_dialog(hull_id: String, slot: Dictionary) -> void:
	var role: int = slot.get("role", CrewData.Role.PILOT)
	var dialog := CrewHireDialog.new()
	add_child(dialog)
	dialog.setup(role, RoguelikeRun.available_crew(role))
	dialog.hired.connect(func(roster_id: String):
		RoguelikeRun.fill_vacancy(hull_id, slot, roster_id)
		_rebuild())


# HELPERS

## A hull card header: name, crew count, on-ice badge, and an optional trailing
## action button (the ice/activate toggle on the hiring section).
func _hull_header(hull: Dictionary, trailing: Button) -> Control:
	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", UiKit.panel_box(UiKit.PANEL_2, UiKit.LINE, 0, 11))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	head.add_child(row)

	row.add_child(UiKit.label(_type_label(hull.get("ship_type", "")), UiKit.INK, 13))
	row.add_child(UiKit.label("· crew %d / %d" % [
		hull.get("crew", []).size(), hull.get("complement", []).size()], UiKit.DIM, 12))
	row.add_child(UiKit.label("· eng %d" % _engineer_count(hull), UiKit.DIM, 12))
	if hull.get("iced", false):
		row.add_child(UiKit.badge("On ice"))
	elif not _has_pilot(hull):
		row.add_child(UiKit.badge("Won't sortie", UiKit.BAD))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var cond := HullConditionSystem.condition(hull)
	row.add_child(UiKit.mini_meter("Arm", cond.armor, UiKit.ACCENT,
		cond.armor < CONDITION_LOW_RATIO))
	row.add_child(UiKit.mini_meter("Sys", cond.systems, UiKit.GOLD,
		cond.systems < CONDITION_LOW_RATIO))

	if trailing != null:
		row.add_child(trailing)
	return head


func _engineer_count(hull: Dictionary) -> int:
	var n := 0
	for member in hull.get("crew", []):
		if member.get("role", -1) == CrewData.Role.ENGINEER:
			n += 1
	return n


func _has_pilot(hull: Dictionary) -> bool:
	for member in hull.get("crew", []):
		if member.get("role", -1) == CrewData.Role.PILOT:
			return true
	return false


func _row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	return row


func _indented(content: Control) -> MarginContainer:
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_left", 14)
	wrap.add_theme_constant_override("margin_right", 14)
	wrap.add_theme_constant_override("margin_top", 8)
	wrap.add_theme_constant_override("margin_bottom", 8)
	wrap.add_child(content)
	return wrap


func _make_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	return btn


func _type_label(ship_type: String) -> String:
	return ship_type.replace("_", " ").capitalize()


func _commas(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out
