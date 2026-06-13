class_name ShipViewModal
extends ModalDialog

## Read-only hull/ship view in a centered modal over a dimmed backdrop.
## Shows condition meters and a crew list where each callsign opens a
## CrewViewModal.

const MODAL_WIDTH := 560
const CONDITION_LOW_RATIO := 0.4


## Build, attach to `parent`, and show the modal for one hull dict.
static func open(parent: Node, hull: Dictionary) -> ShipViewModal:
	var modal: ShipViewModal = ShipViewModal.new()
	parent.add_child(modal)
	modal.setup(hull)
	return modal


func setup(hull: Dictionary) -> void:
	build_chrome(MODAL_WIDTH)

	# Header: ship type + on-ice badge
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 8)
	var ship_type: String = str(hull.get("ship_type", "unknown"))
	header_row.add_child(UiKit.label(ship_type.capitalize(), UiKit.INK, 18))
	if hull.get("iced", false):
		header_row.add_child(UiKit.badge("On ice"))
	content.add_child(header_row)

	# Condition meters
	var cond := HullConditionSystem.condition(hull)
	content.add_child(UiKit.meter_bar("Armor", cond.armor, UiKit.ACCENT,
		cond.armor < CONDITION_LOW_RATIO))
	content.add_child(UiKit.meter_bar("Systems", cond.systems, UiKit.GOLD,
		cond.systems < CONDITION_LOW_RATIO))

	# Crew section
	content.add_child(UiKit.section_title("Crew"))
	var crew: Array = hull.get("crew", [])
	for member in crew:
		content.add_child(_crew_row(member))

	# Vacant slots note
	var complement_count: int = hull.get("complement", []).size()
	var vacant := complement_count - crew.size()
	if vacant > 0:
		content.add_child(UiKit.label("%d vacant slot(s)" % vacant, UiKit.DIM))

	add_footer()


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
