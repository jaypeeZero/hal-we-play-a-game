class_name CrewChip
extends PanelContainer

## The draggable + droppable unit in the crew assignment board.
## - Inner ghost Button handles callsign click → opens CrewViewModal.
## - PanelContainer handles drag/drop at the ship-swap level.
## The drag threshold keeps click and drag distinct (Godot built-in).

const CHIP_ROW_SEP := 6
const DRAG_PREVIEW_WIDTH := 200

## The board that owns this chip; notified on successful drop.
var board: CrewAssignmentBoard
var crew_id: String = ""
var role: int = CrewData.Role.PILOT

var _member: Dictionary = {}


func setup(member: Dictionary, owner_board: CrewAssignmentBoard) -> void:
	_member = member
	crew_id = str(member.get("crew_id", ""))
	role = int(member.get("role", CrewData.Role.PILOT))
	board = owner_board

	add_theme_stylebox_override("panel", UiKit.panel_box(UiKit.CHIP, UiKit.LINE))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", CHIP_ROW_SEP)
	add_child(row)

	# Role badge
	var role_lbl := UiKit.label(CrewData.get_role_name(role), UiKit.DIM, 10)
	row.add_child(role_lbl)

	# Callsign — ghost Button for click; the PanelContainer handles drag.
	var callsign_btn := Button.new()
	callsign_btn.text = str(member.get("callsign", ""))
	UiKit.style_button(callsign_btn, "ghost")
	callsign_btn.mouse_filter = Control.MOUSE_FILTER_PASS
	callsign_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var entry := CrewData.entry_from_crew(member)
	# Open on the board's full-screen host, not the chip's own cell.
	callsign_btn.pressed.connect(func():
		var host := board.resolve_modal_parent()
		if host != null:
			CrewViewModal.open(host, entry))
	row.add_child(callsign_btn)

	if CrewData.is_off_role(member):
		row.add_child(UiKit.badge("off-role", UiKit.BAD))

	if member.has("weapon_id"):
		row.add_child(UiKit.label(str(member.weapon_id), UiKit.ACCENT, 10))


# ---- Drag source ----

func _get_drag_data(_pos: Vector2) -> Variant:
	var preview := PanelContainer.new()
	preview.add_theme_stylebox_override("panel", UiKit.panel_box(UiKit.CHIP, UiKit.ACCENT))
	var lbl := UiKit.label(
		"%s · %s" % [str(_member.get("callsign", "")), CrewData.get_role_name(role)],
		UiKit.ACCENT, 12)
	preview.add_child(lbl)
	preview.custom_minimum_size = Vector2(DRAG_PREVIEW_WIDTH, 0)
	# set_drag_preview requires an active drag gesture; guard for headless tests.
	if get_viewport() != null and get_viewport().gui_is_dragging():
		set_drag_preview(preview)
	return {"kind": "crew", "crew_id": crew_id, "role": role}


# ---- Drop target (swap: only occupied chips of the same role) ----

func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	if not (data is Dictionary and data.get("kind", "") == "crew"):
		return false
	return RoguelikeRun.can_swap(data.crew_id, crew_id)


func _drop_data(_pos: Vector2, data: Variant) -> void:
	if RoguelikeRun.swap_crew(data.crew_id, crew_id):
		board.on_changed()
