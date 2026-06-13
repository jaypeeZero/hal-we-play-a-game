class_name ShipViewModal
extends Control

## Read-only hull/ship view in a centered modal over a dimmed backdrop.
## Mirrors CrewViewModal's chrome exactly. Shows condition meters and
## a crew list where each callsign opens a CrewViewModal.

signal closed

const MODAL_WIDTH := 560
const BACKDROP_ALPHA := 0.85
const FOOTER_GAP := 10
const CONDITION_LOW_RATIO := 0.4


## Build, attach to `parent`, and show the modal for one hull dict.
static func open(parent: Node, hull: Dictionary) -> ShipViewModal:
	var modal: ShipViewModal = ShipViewModal.new()
	parent.add_child(modal)
	modal.setup(hull)
	return modal


func setup(hull: Dictionary) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := UiKit.BG
	dim.a = BACKDROP_ALPHA
	add_child(UiKit.backdrop(dim))

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(MODAL_WIDTH, 0)
	panel.add_theme_stylebox_override("panel", UiKit.panel_box(UiKit.PANEL_2, UiKit.LINE))
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", FOOTER_GAP)
	panel.add_child(box)

	# Header: ship type + on-ice badge
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 8)
	var ship_type: String = str(hull.get("ship_type", "unknown"))
	header_row.add_child(UiKit.label(ship_type.capitalize(), UiKit.INK, 18))
	if hull.get("iced", false):
		header_row.add_child(UiKit.badge("On ice"))
	box.add_child(header_row)

	# Condition meters
	var cond := HullConditionSystem.condition(hull)
	box.add_child(UiKit.meter_bar("Armor", cond.armor, UiKit.ACCENT,
		cond.armor < CONDITION_LOW_RATIO))
	box.add_child(UiKit.meter_bar("Systems", cond.systems, UiKit.GOLD,
		cond.systems < CONDITION_LOW_RATIO))

	# Crew section
	box.add_child(UiKit.section_title("Crew"))
	var crew: Array = hull.get("crew", [])
	for member in crew:
		box.add_child(_crew_row(member))

	# Vacant slots note
	var complement_count: int = hull.get("complement", []).size()
	var vacant := complement_count - crew.size()
	if vacant > 0:
		box.add_child(UiKit.label("%d vacant slot(s)" % vacant, UiKit.DIM))

	# Footer close button
	var close := UiKit.style_button(_make_button("Close"), "ghost")
	close.pressed.connect(_on_close)
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_child(close)
	box.add_child(footer)


func _crew_row(member: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var role_name := CrewData.get_role_name(member.get("role", CrewData.Role.PILOT))
	row.add_child(UiKit.label(role_name, UiKit.DIM))

	var callsign_btn := Button.new()
	callsign_btn.text = str(member.get("callsign", ""))
	UiKit.style_button(callsign_btn, "ghost")
	var entry := CrewData.entry_from_crew(member)
	callsign_btn.pressed.connect(func(): CrewViewModal.open(self, entry))
	row.add_child(callsign_btn)

	return row


func _on_close() -> void:
	closed.emit()
	queue_free()


func _make_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	return btn
