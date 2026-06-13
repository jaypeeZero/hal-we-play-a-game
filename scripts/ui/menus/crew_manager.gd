extends OverlayScreen

## Crew Manager: browse and edit the crew roster that the roguelite hiring
## pool draws from. The list shows every entry in the active roster; the
## selected entry is edited in place through an editable CrewMemberView.
## Save writes the whole roster to user://crew_roster.json (the local
## override); Reset deletes the override so the shipped roster applies again.
## Lifecycle: standalone scene — Back calls change_scene_to_file.

const LIST_WIDTH := 300

var _entries: Array = []
var _selected_index := -1
var _dirty := false
var _list: VBoxContainer
var _detail: CrewMemberView
var _subtitle: Label
var _row_buttons: Array = []


func _ready() -> void:
	_entries = CrewRosterManager.load_roster()
	build_chrome()
	var topbar := _build_topbar()
	var body_node := _build_body()
	_build_footer_buttons()
	_finalize_chrome(topbar, body_node)
	_rebuild_list()
	if not _entries.is_empty():
		_select(0)


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
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	body_node.add_child(scroll)

	_detail = CrewMemberView.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_detail.entry_changed.connect(_on_entry_changed)
	body_node.add_child(_detail)
	return body_node


func _build_footer_buttons() -> void:
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
	for child in _list.get_children():
		_list.remove_child(child)
		child.free()
	_row_buttons = []
	for i in _entries.size():
		var btn := UiKit.style_button(_make_button(_row_text(_entries[i])), "ghost")
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var index := i
		btn.pressed.connect(func(): _select(index))
		_row_buttons.append(btn)
		_list.add_child(btn)


# SELECTION & EDITS

func _select(index: int) -> void:
	if _selected_index == index:
		return
	_selected_index = index
	_detail.setup(_entries[index], true)
	for i in _row_buttons.size():
		UiKit.style_button(_row_buttons[i], "primary" if i == index else "ghost")


func _on_entry_changed(entry: Dictionary) -> void:
	if _selected_index < 0:
		return
	_entries[_selected_index] = entry
	_row_buttons[_selected_index].text = _row_text(entry)
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
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# HELPERS

func _refresh_subtitle() -> void:
	var source := "custom roster" if CrewRosterManager.has_user_override() else "default roster"
	_subtitle.text = "%d crew · %s%s" % [
		_entries.size(), source, " · unsaved changes" if _dirty else ""]


func _row_text(entry: Dictionary) -> String:
	return "%s · %s" % [
		entry.get("callsign", "?"), CrewData.display_role_names(entry.get("roles", []))]


func _make_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	return btn
