class_name CrewAssignmentBoard
extends VBoxContainer

## One card per hull. Each card shows the hull header (type · crew count ·
## condition meters) with an optional ice/activate button (when show_ice=true),
## then a CrewChip per crew member and an explicit vacant-slot row per empty
## slot (the move drop target).
##
## Drop semantics:
##   Drop on occupied CrewChip (same role) → swap (RoguelikeRun.swap_crew).
##   Drop on vacant-slot row or hull card → move (RoguelikeRun.transfer_crew).
##
## While a crew chip is dragged, each hull card that cannot accept it is dimmed
## (NOTIFICATION_DRAG_BEGIN/END), so the valid drop targets read at a glance.

signal changed

## When true, each hull card shows an ice/activate button.
var show_ice: bool = false
## Full-screen host (the OverlayScreen) that stat modals are parented to, so
## they fill the screen rather than a card cell. Falls back to the window.
var modal_host: Control = null

const CARD_SEP := 8
const CHIP_SEP := 4
const CONDITION_LOW_RATIO := 0.6
const DRAG_DIM_MODULATE := Color(1, 1, 1, 0.4)

## Hull cards paired with their hull_id, for drag-time highlighting.
var _cards: Array = []


func setup() -> void:
	add_theme_constant_override("separation", CARD_SEP)
	rebuild()


func rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_cards = []
	for hull in RoguelikeRun.fleet_hulls:
		var card := _hull_card(hull)
		_cards.append({"card": card, "hull_id": hull.hull_id})
		add_child(card)


## Dim hull cards that can't accept the dragged crew; restore on drag end.
func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		var data: Variant = get_viewport().gui_get_drag_data() if get_viewport() != null else null
		for entry in _cards:
			entry.card.modulate = (Color.WHITE if _hull_accepts(entry.hull_id, data)
				else DRAG_DIM_MODULATE)
	elif what == NOTIFICATION_DRAG_END:
		for entry in _cards:
			entry.card.modulate = Color.WHITE


## Whether a hull can receive the dragged payload — a move into a vacancy, or a
## swap with one of its crew. Mirrors the drop targets' own acceptance checks.
func _hull_accepts(hull_id: String, data: Variant) -> bool:
	if not (data is Dictionary and data.get("kind", "") == "crew"):
		return false
	var crew_id: String = data.crew_id
	if RoguelikeRun.can_transfer(crew_id, hull_id):
		return true
	for member in RoguelikeRun.hull_by_id(hull_id).get("crew", []):
		if RoguelikeRun.can_swap(crew_id, member.get("crew_id", "")):
			return true
	return false


func on_changed() -> void:
	rebuild()
	changed.emit()


# ---- Hull card ----

func _hull_card(hull: Dictionary) -> Control:
	var card := UiKit.card(UiKit.PANEL, UiKit.LINE, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	card.add_child(box)

	# Header with optional ice button
	var ice_btn: Button = null
	if show_ice:
		ice_btn = UiKit.style_button(_make_button(
			"Activate" if hull.get("iced", false) else "Put on ice"), "ghost")
		var hull_id: String = hull.hull_id
		var now_iced: bool = not hull.get("iced", false)
		ice_btn.pressed.connect(func():
			RoguelikeRun.set_hull_iced(hull_id, now_iced)
			on_changed())
	box.add_child(_hull_header(hull, ice_btn))

	# Crew chips
	var crew: Array = hull.get("crew", [])
	if crew.is_empty():
		box.add_child(_indented(UiKit.label("(no crew aboard)", UiKit.DIM, 11)))

	for member in crew:
		var chip := CrewChip.new()
		chip.setup(member, self)
		box.add_child(_indented(chip))

	# Vacant-slot rows (move drop targets)
	for slot in RoguelikeRun.hull_vacancies(hull):
		box.add_child(_vacant_row(hull, slot))

	return card


func _hull_header(hull: Dictionary, trailing: Button) -> Control:
	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", UiKit.panel_box(UiKit.PANEL_2, UiKit.LINE, 0, 11))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	head.add_child(row)

	var type_lbl := UiKit.label(_type_label(hull.get("ship_type", "")), UiKit.INK, 13)
	row.add_child(type_lbl)
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

	# Click on header opens ShipViewModal on the full-screen host.
	head.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton \
				and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var host := resolve_modal_parent()
			if host != null:
				ShipViewModal.open(host, hull))

	return head


## The node stat modals should parent to: the host screen if set, else the
## window, else self (keeps standalone/test instances functional).
func resolve_modal_parent() -> Node:
	if modal_host != null:
		return modal_host
	if get_viewport() != null:
		return get_viewport().get_window()
	return self


## A vacant slot row: role label + weapon binding + drop target for move.
func _vacant_row(hull: Dictionary, slot: Dictionary) -> Control:
	var wrap := _indented_container()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var role_name := CrewData.get_role_name(slot.get("role", -1))
	row.add_child(UiKit.label("VACANT · %s" % role_name, UiKit.DIM, 11))
	if slot.has("weapon_id"):
		row.add_child(UiKit.label(str(slot.weapon_id), UiKit.ACCENT, 11))

	wrap.add_child(row)

	# Drop-target behaviour injected via a thin wrapper that holds context.
	var drop_target := _VacantDropTarget.new()
	drop_target.hull_id = hull.hull_id
	drop_target.board = self
	drop_target.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	drop_target.mouse_filter = Control.MOUSE_FILTER_PASS
	wrap.add_child(drop_target)
	return wrap


# ---- inner class: drop target logic for vacant slots ----

class _VacantDropTarget extends Control:
	var hull_id: String = ""
	var board: CrewAssignmentBoard

	func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
		if not (data is Dictionary and data.get("kind", "") == "crew"):
			return false
		return RoguelikeRun.can_transfer(data.crew_id, hull_id)

	func _drop_data(_pos: Vector2, data: Variant) -> void:
		if RoguelikeRun.transfer_crew(data.crew_id, hull_id):
			board.on_changed()


# ---- Helpers ----

func _indented(content: Control) -> MarginContainer:
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_left", 14)
	wrap.add_theme_constant_override("margin_right", 14)
	wrap.add_theme_constant_override("margin_top", 6)
	wrap.add_theme_constant_override("margin_bottom", 6)
	wrap.add_child(content)
	return wrap


func _indented_container() -> MarginContainer:
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_left", 14)
	wrap.add_theme_constant_override("margin_right", 14)
	wrap.add_theme_constant_override("margin_top", 6)
	wrap.add_theme_constant_override("margin_bottom", 6)
	return wrap


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


func _type_label(ship_type: String) -> String:
	return ship_type.replace("_", " ").capitalize()


func _make_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	return btn
