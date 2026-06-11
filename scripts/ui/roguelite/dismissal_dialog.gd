class_name DismissalDialog
extends Control

## Modal shown when the player cannot afford a battle's upkeep, styled via
## UiKit (see design/dismissal_dialog.mockup.html). They dismiss ships
## (the hull and everyone aboard) and crew (opening a vacancy) to cut upkeep —
## no insurance is owed, the crew are simply let go. A live ledger (Credits /
## Upkeep / Short by) shows the gap closing; Confirm unlocks only once the
## remaining fleet's upkeep is affordable and at least one piloted hull remains.
## Pressing it emits `resolved(true)` so the map deducts upkeep and launches.

signal resolved(launched: bool)

const MODAL_WIDTH := 560
const BODY_MAX_HEIGHT := 300

var _ledger: HBoxContainer
var _content: VBoxContainer
var _confirm: Button


func setup() -> void:
	_build_chrome()
	_rebuild()


# ============================================================================
# UI CONSTRUCTION
# ============================================================================

func _build_chrome() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.backdrop())

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var modal := PanelContainer.new()
	modal.custom_minimum_size = Vector2(MODAL_WIDTH, 0)
	modal.add_theme_stylebox_override("panel",
		UiKit.panel_box(UiKit.PANEL_2, UiKit.WARN_BORDER, 14, 0))
	center.add_child(modal)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	modal.add_child(root)

	root.add_child(_build_head())

	_ledger = HBoxContainer.new()
	_ledger.add_theme_constant_override("separation", 10)
	root.add_child(_pad(_ledger, 14))

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, BODY_MAX_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 10)
	scroll.add_child(_pad(_content, 14))

	root.add_child(_build_foot())


func _build_head() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.add_child(UiKit.label("⚠ INSUFFICIENT FUNDS", UiKit.BAD, 11))
	box.add_child(UiKit.label("Dismiss ships or crew to cover this battle's upkeep", UiKit.INK, 16))
	return _pad(box, 16)


func _build_foot() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var hint := UiKit.label("Dismissed crew are let go — no insurance owed.", UiKit.DIM, 11)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(hint)

	_confirm = UiKit.style_button(_make_button("Launch battle"), "primary")
	_confirm.pressed.connect(func(): resolved.emit(true))
	row.add_child(_confirm)
	return _pad(row, 14)


func _rebuild() -> void:
	var upkeep: int = EconomySystem.per_battle_upkeep(RoguelikeRun.fleet_hulls).total
	var short: int = maxi(0, upkeep - RoguelikeRun.money)
	var fieldable: bool = RoguelikeRun.sortieable_hulls().size() > 0
	_confirm.disabled = short > 0 or not fieldable

	for child in _ledger.get_children():
		child.queue_free()
	_ledger.add_child(_meter("Credits", str(RoguelikeRun.money), UiKit.GOLD, ""))
	_ledger.add_child(_meter("Upkeep this battle", str(upkeep), UiKit.INK, _fleet_summary()))
	if short > 0:
		_ledger.add_child(_meter("Short by", str(short), UiKit.BAD, "dismiss to close the gap", true))
	else:
		_ledger.add_child(_meter("Ready", "✓", UiKit.GOOD, "upkeep covered", false, UiKit.GOOD))

	for child in _content.get_children():
		child.queue_free()
	for hull in RoguelikeRun.fleet_hulls:
		_content.add_child(_hull_card(hull))


# ============================================================================
# PIECES
# ============================================================================

func _meter(lbl: String, value: String, value_color: Color, sub: String, danger := false, border_override := Color(0, 0, 0, 0)) -> Control:
	var border := UiKit.LINE
	if danger:
		border = Color("5a2a2a")
	elif border_override.a > 0.0:
		border = Color(border_override.r, border_override.g, border_override.b, 0.5)
	var card := UiKit.card(UiKit.PANEL, border, 10)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	card.add_child(box)
	box.add_child(UiKit.label(lbl.to_upper(), UiKit.DIM, 10))
	box.add_child(UiKit.label(value, value_color, 22))
	if sub != "":
		box.add_child(UiKit.label(sub, UiKit.DIM, 11))
	return card


func _hull_card(hull: Dictionary) -> Control:
	var card := UiKit.card(UiKit.PANEL, UiKit.LINE, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	card.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	header.add_child(UiKit.label(_type_label(hull.get("ship_type", "")), UiKit.INK, 13))
	header.add_child(UiKit.label("· crew %d" % hull.get("crew", []).size(), UiKit.DIM, 12))
	if hull.get("iced", false):
		header.add_child(UiKit.badge("On ice"))
	elif not _has_pilot(hull):
		# Dismissing a hull's last pilot benches it — flag it so the player
		# isn't surprised when it doesn't sortie.
		header.add_child(UiKit.badge("Won't sortie", UiKit.BAD))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	header.add_child(UiKit.label("upkeep %d" % _hull_upkeep(hull), UiKit.DIM, 11))

	var hull_id: String = hull.hull_id
	var dismiss_ship := UiKit.style_button(_make_button("Dismiss ship"), "warn")
	dismiss_ship.disabled = not RoguelikeRun.may_dismiss_hull(hull_id)
	if dismiss_ship.disabled:
		dismiss_ship.tooltip_text = "Needed to field a battle force"
	dismiss_ship.pressed.connect(func(): _on_dismiss_hull(hull_id))
	header.add_child(dismiss_ship)

	var head_panel := PanelContainer.new()
	head_panel.add_theme_stylebox_override("panel", UiKit.panel_box(UiKit.PANEL_2, UiKit.LINE, 0, 11))
	head_panel.add_child(header)
	box.add_child(head_panel)

	for member in hull.get("crew", []):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(UiKit.label(CrewData.get_role_name(member.get("role", -1)), UiKit.DIM, 11))
		row.add_child(UiKit.label(member.get("callsign", ""), UiKit.INK, 13))
		var s := Control.new()
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(s)
		var crew_id: String = member.crew_id
		var dismiss := UiKit.style_button(_make_button("Dismiss"), "warn")
		dismiss.disabled = not RoguelikeRun.may_dismiss_crew(crew_id)
		if dismiss.disabled:
			dismiss.tooltip_text = "Needed to field a battle force"
		dismiss.pressed.connect(func(): _on_dismiss_crew(crew_id))
		row.add_child(dismiss)
		box.add_child(_indent(row))
	return card


func _on_dismiss_hull(hull_id: String) -> void:
	RoguelikeRun.dismiss_hull(hull_id)
	_rebuild()


func _on_dismiss_crew(crew_id: String) -> void:
	RoguelikeRun.dismiss_crew(crew_id)
	_rebuild()


# ============================================================================
# HELPERS
# ============================================================================

## Per-hull upkeep contribution: ship cost when active, plus crew salaries.
func _hull_upkeep(hull: Dictionary) -> int:
	var salary := EconomySystem.crew_salary_per_battle()
	var ship_cost := 0 if hull.get("iced", false) else EconomySystem.ship_per_battle_cost(hull.get("ship_type", ""))
	return ship_cost + hull.get("crew", []).size() * salary


func _fleet_summary() -> String:
	var ships := RoguelikeRun.fleet_hulls.size()
	var crew := 0
	for hull in RoguelikeRun.fleet_hulls:
		crew += hull.get("crew", []).size()
	return "%d ships · %d crew" % [ships, crew]


func _pad(content: Control, amount: int) -> MarginContainer:
	var wrap := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		wrap.add_theme_constant_override(side, amount)
	wrap.add_child(content)
	return wrap


func _indent(row: Control) -> MarginContainer:
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_left", 14)
	wrap.add_theme_constant_override("margin_right", 14)
	wrap.add_theme_constant_override("margin_top", 8)
	wrap.add_theme_constant_override("margin_bottom", 8)
	wrap.add_child(row)
	return wrap


func _make_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	return btn


func _has_pilot(hull: Dictionary) -> bool:
	for member in hull.get("crew", []):
		if member.get("role", -1) == CrewData.Role.PILOT:
			return true
	return false


func _type_label(ship_type: String) -> String:
	return ship_type.replace("_", " ").capitalize()
