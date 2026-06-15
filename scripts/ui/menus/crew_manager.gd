extends OverlayScreen

## Crew Manager: browse and edit the crew roster that the roguelite hiring
## pool draws from. The list shows every entry in the active roster; the
## selected entry is edited in place through an editable CrewMemberView.
## Save writes the whole roster to user://crew_roster.json (the local
## override); Reset deletes the override so the shipped roster applies again.
## Lifecycle: dual-entry. Inside a roguelike run the NavBar provides Back
## (→ Map); launched standalone from the title menu it shows a footer Back
## (→ main menu). Either path auto-saves when dirty so edits are never lost.

const LIST_WIDTH := 320
const CARD_PORTRAIT_SIZE := Vector2(72, 84)
const CARD_MIN_SIZE := Vector2(140, 0)
const GALLERY_COLUMNS := 2
const GALLERY_GAP := 8

var _entries: Array = []
var _selected_index := -1
var _dirty := false
var _gallery: GridContainer
var _detail: CrewMemberView
var _subtitle: Label
var _cards: Array = []
var _nav_bar: NavBar


func _ready() -> void:
	"""Build the Crew Manager screen; nav bar only inside a roguelike run."""
	_entries = CrewRosterManager.load_roster()
	build_chrome()
	var topbar := _build_topbar()
	var body_node := _build_body()
	_build_footer_buttons()
	_finalize_chrome(topbar, body_node)
	_rebuild_list()
	if not _entries.is_empty():
		_select(0)
	# In a run the nav bar carries Back; standalone (from the title menu) the
	# footer Back added in _build_footer_buttons is used instead.
	_nav_bar = NavBar.attach(self, NavGraph.Screen.CREW, true, _on_back)


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

	_detail = CrewMemberView.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_detail.entry_changed.connect(_on_entry_changed)
	body_node.add_child(_detail)
	return body_node


func _build_footer_buttons() -> void:
	if not RoguelikeRun.active:
		# Standalone entry from the title menu has no nav bar, so the footer
		# carries Back.
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
	_detail.setup(_entries[index], true)
	for i in _cards.size():
		(_cards[i] as _CrewCard).set_selected(i == index)


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
	# Auto-save when dirty so changes are never silently lost on navigation.
	if _dirty:
		_on_save()
	if RoguelikeRun.active:
		Nav.back(NavGraph.Screen.CREW)
	else:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# HELPERS

func _refresh_subtitle() -> void:
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
