class_name RunCrewScreen
extends Control

## Read-only crew roster for the active roguelike run: every crew member
## currently serving aboard the fleet (RoguelikeRun.fielded_crew). Clicking a
## card opens the shared read-only CrewViewModal. Editing crew assignments
## happens through Fleet Command, not here.

const SCREEN_MARGIN := 40
const TOP_GAP := 16
const CARD_SIZE := Vector2(140, 0)
const PORTRAIT_SIZE := Vector2(72, 84)
const CARD_GAP := 8

var _nav_bar: NavBar


func _ready() -> void:
	"""Build the read-only crew roster and the nav bar."""
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.backdrop(UiKit.BG))
	_build_body()
	# Nav bar added last so it draws above the body (and any modal opened from a
	# card is added after it, so the modal covers the bar).
	_nav_bar = NavBar.attach(self, NavGraph.Screen.CREW, true)


func _build_body() -> void:
	"""Build the scrollable crew gallery below the nav bar."""
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_top", NavBar.NAV_BAR_HEIGHT + TOP_GAP)
	margin.add_theme_constant_override("margin_left", SCREEN_MARGIN)
	margin.add_theme_constant_override("margin_right", SCREEN_MARGIN)
	margin.add_theme_constant_override("margin_bottom", SCREEN_MARGIN)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", TOP_GAP)
	margin.add_child(col)

	var crew: Array = RoguelikeRun.fielded_crew()
	col.add_child(UiKit.section_title("Crew Roster · %d aboard" % crew.size()))

	if crew.is_empty():
		col.add_child(UiKit.label("No crew aboard.", UiKit.DIM))
		return

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)

	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", CARD_GAP)
	flow.add_theme_constant_override("v_separation", CARD_GAP)
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(flow)

	for member in crew:
		flow.add_child(_make_crew_card(member))


## Build one clickable read-only crew card: portrait + callsign + serving role.
func _make_crew_card(entry: Dictionary) -> PanelContainer:
	"""Return a card for `entry` that opens the read-only crew modal on click."""
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_SIZE
	card.add_theme_stylebox_override("panel", UiKit.panel_box(UiKit.PANEL, UiKit.LINE, 6, 8))
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
				and (event as InputEventMouseButton).pressed:
			CrewViewModal.open(self, entry))

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	card.add_child(box)

	var portrait := CrewPortrait.new()
	portrait.custom_minimum_size = PORTRAIT_SIZE
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	portrait.mouse_filter = Control.MOUSE_FILTER_PASS
	portrait.setup(entry)
	box.add_child(portrait)

	var callsign := UiKit.label(str(entry.get("callsign", "?")), UiKit.INK, 12)
	callsign.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	callsign.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(callsign)

	var role := UiKit.label(
		CrewData.role_to_name(int(entry.get("role", -1))), UiKit.DIM, 10)
	role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	role.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(role)

	return card
