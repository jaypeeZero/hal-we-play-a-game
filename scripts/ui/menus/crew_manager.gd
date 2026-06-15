extends OverlayScreen

## Crew Manager: a master-detail crew browser with two modes.
##
## EDIT mode (standalone, from the title menu — no active run): edits the global
## crew roster template the roguelite hiring pool draws from. Save writes the
## whole roster to user://crew_roster.json; Reset deletes that override.
##
## READ-ONLY mode (inside a run — reached via the nav bar Crew tab): shows the
## run's hired crew (RoguelikeRun.fielded_crew) with no editing, and reports each
## selected member's ship assignment (which ship + position, or unassigned).
##
## The mode is chosen by RoguelikeRun.active — the only way each entry point is
## reached — so no scene parameter is needed.

const LIST_WIDTH := 320
const CARD_PORTRAIT_SIZE := Vector2(72, 84)
const CARD_MIN_SIZE := Vector2(140, 0)
const GALLERY_COLUMNS := 2
const GALLERY_GAP := 8

var _read_only := false
var _entries: Array = []
var _selected_index := -1
var _dirty := false
var _gallery: GridContainer
var _detail: CrewMemberView
var _subtitle: Label
var _assignment_label: Label
var _cards: Array = []
var _nav_bar: NavBar


func _ready() -> void:
	"""Build the Crew Manager screen in edit or read-only mode."""
	_read_only = RoguelikeRun.active
	_entries = _load_entries()
	build_chrome()
	var topbar := _build_topbar()
	var body_node := _build_body()
	_build_footer_buttons()
	_finalize_chrome(topbar, body_node)
	_rebuild_list()
	if not _entries.is_empty():
		_select(0)
	# In a run the nav bar carries Back (read-only mode); standalone the footer
	# Back is used instead. attach() is a no-op when no run is active.
	_nav_bar = NavBar.attach(self, NavGraph.Screen.CREW, true, _on_back)


## Load the entries to display, in roster-entry shape (id, callsign, roles,
## skills). Edit mode pulls the global roster; read-only mode pulls the run's
## hired crew converted from hull-crew shape via CrewData.entry_from_crew.
func _load_entries() -> Array:
	"""Return roster-shape entries for the current mode."""
	if not _read_only:
		return CrewRosterManager.load_roster()
	var entries: Array = []
	for member in RoguelikeRun.fielded_crew():
		entries.append(CrewData.entry_from_crew(member))
	return entries


# UI CONSTRUCTION

func _build_topbar() -> Control:
	var bar := UiKit.card(UiKit.PANEL_2, UiKit.LINE, 14)
	var box := VBoxContainer.new()
	bar.add_child(box)
	box.add_child(UiKit.label("CREW MANAGER", UiKit.INK, 16))
	_subtitle = UiKit.label("", UiKit.DIM, 11)
	box.add_child(_subtitle)
	_refresh_subtitle()
	return bar


func _build_body() -> Control:
	var body_node := HBoxContainer.new()
	body_node.add_theme_constant_override("separation", SECTION_GAP)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(LIST_WIDTH, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_gallery = GridContainer.new()
	_gallery.columns = GALLERY_COLUMNS
	_gallery.add_theme_constant_override("h_separation", GALLERY_GAP)
	_gallery.add_theme_constant_override("v_separation", GALLERY_GAP)
	_gallery.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_gallery)
	body_node.add_child(scroll)

	var detail_col := VBoxContainer.new()
	detail_col.add_theme_constant_override("separation", SECTION_GAP)
	detail_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Ship-assignment status, shown only in read-only (in-run) mode.
	_assignment_label = UiKit.label("", UiKit.ACCENT, 12)
	_assignment_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_assignment_label.visible = false
	detail_col.add_child(_assignment_label)

	_detail = CrewMemberView.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_detail.entry_changed.connect(_on_entry_changed)
	detail_col.add_child(_detail)

	body_node.add_child(detail_col)
	return body_node


func _build_footer_buttons() -> void:
	# Read-only mode has no footer: the nav bar provides Back and there is
	# nothing to save or reset.
	if _read_only:
		return

	var back := UiKit.style_button(_make_button("Back"), "ghost")
	back.pressed.connect(_on_back)
	footer.add_child(back)

	var reset := UiKit.style_button(_make_button("Reset to defaults"), "warn")
	reset.pressed.connect(_on_reset)
	footer.add_child(reset)

	var save := UiKit.style_button(_make_button("Save"), "primary")
	save.pressed.connect(_on_save)
	footer.add_child(save)


func _rebuild_list() -> void:
	for child in _gallery.get_children():
		_gallery.remove_child(child)
		child.free()
	_cards = []
	for i in _entries.size():
		var card: _CrewCard = _CrewCard.new()
		var index: int = i
		card.setup(_entries[i], func() -> void: _select(index))
		_cards.append(card)
		_gallery.add_child(card)


# SELECTION & EDITS

func _select(index: int) -> void:
	if _selected_index == index:
		return
	_selected_index = index
	_detail.setup(_entries[index], not _read_only)
	if _read_only:
		_update_assignment_label(_entries[index])
	for i in _cards.size():
		(_cards[i] as _CrewCard).set_selected(i == index)


## Show which ship the selected crew member serves on and in what position,
## or that they are not aboard any ship. Read-only mode only.
func _update_assignment_label(entry: Dictionary) -> void:
	"""Set the assignment status line for the selected crew member."""
	var assignment: Dictionary = RoguelikeRun.assignment_of(str(entry.get("id", "")))
	if assignment.is_empty():
		_assignment_label.text = "Status: not assigned to a ship"
	else:
		var ship: String = str(assignment.get("ship_name", ""))
		var position: String = CrewData.role_to_name(int(assignment.get("role", -1)))
		_assignment_label.text = "Aboard %s — %s" % [ship, position]
	_assignment_label.visible = true


func _on_entry_changed(entry: Dictionary) -> void:
	if _selected_index < 0:
		return
	_entries[_selected_index] = entry
	(_cards[_selected_index] as _CrewCard).refresh(entry)
	_dirty = true
	_refresh_subtitle()


func _on_save() -> void:
	if CrewRosterManager.save_roster(_entries):
		_dirty = false
	_refresh_subtitle()


func _on_reset() -> void:
	CrewRosterManager.reset_to_defaults()
	_entries = CrewRosterManager.load_roster()
	_dirty = false
	_selected_index = -1
	_rebuild_list()
	if not _entries.is_empty():
		_select(0)
	_refresh_subtitle()


func _on_back() -> void:
	if _read_only:
		# In-run view: Back follows the nav hierarchy (→ Map). Nothing to save.
		Nav.back(NavGraph.Screen.CREW)
		return
	# Auto-save when dirty so edits are never silently lost on navigation.
	if _dirty:
		_on_save()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# HELPERS

func _refresh_subtitle() -> void:
	if _read_only:
		_subtitle.text = "%d crew aboard the fleet" % _entries.size()
		return
	var source := "custom roster" if CrewRosterManager.has_user_override() else "default roster"
	_subtitle.text = "%d crew · %s%s" % [
		_entries.size(), source, " · unsaved changes" if _dirty else ""]


func _make_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	return btn


# ── Inner classes ─────────────────────────────────────────────────────────────

## A clickable crew card: portrait face + callsign + role badge(s). Clicking
## anywhere on the card selects this crew member (drives the dossier).
class _CrewCard extends PanelContainer:
	var _portrait: CrewPortrait
	var _callsign: Label
	var _roles: Label
	var _on_click: Callable

	func setup(entry: Dictionary, on_click: Callable) -> void:
		_on_click = on_click
		custom_minimum_size = CARD_MIN_SIZE
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		set_selected(false)

		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		col.mouse_filter = Control.MOUSE_FILTER_PASS
		add_child(col)

		_portrait = CrewPortrait.new()
		_portrait.custom_minimum_size = CARD_PORTRAIT_SIZE
		_portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_portrait.mouse_filter = Control.MOUSE_FILTER_PASS
		col.add_child(_portrait)

		_callsign = UiKit.label("", UiKit.INK, 12)
		_callsign.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_callsign.clip_contents = true
		_callsign.mouse_filter = Control.MOUSE_FILTER_PASS
		col.add_child(_callsign)

		_roles = UiKit.label("", UiKit.DIM, 10)
		_roles.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_roles.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_roles.mouse_filter = Control.MOUSE_FILTER_PASS
		col.add_child(_roles)

		refresh(entry)

	## Update portrait + text from a (possibly edited) roster entry.
	func refresh(entry: Dictionary) -> void:
		_portrait.setup(entry)
		_callsign.text = str(entry.get("callsign", "?"))
		_roles.text = CrewData.display_role_names(entry.get("roles", []))

	## Highlight when this card is the selected crew member.
	func set_selected(selected: bool) -> void:
		var bg: Color = UiKit.PANEL_2 if selected else UiKit.PANEL
		var border: Color = UiKit.ACCENT if selected else UiKit.LINE
		add_theme_stylebox_override("panel", UiKit.panel_box(bg, border, 6, 8))

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
				and (event as InputEventMouseButton).pressed:
			_on_click.call()
