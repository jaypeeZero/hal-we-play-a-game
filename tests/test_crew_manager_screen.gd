extends GutTest

## Tests for the Crew Manager screen - FUNCTIONALITY ONLY. Editing a roster
## entry and saving writes the user override; resetting restores the shipped
## roster. Navigation (Back) is not exercised: scene changes don't belong in
## unit tests.

const CrewManagerScreen := preload("res://scripts/ui/menus/crew_manager.gd")

const EDIT_SKILL := 0.93

var _saved_override: String = ""


func before_each() -> void:
	_saved_override = ""
	if FileAccess.file_exists(CrewRosterManager.USER_PATH):
		_saved_override = FileAccess.get_file_as_string(CrewRosterManager.USER_PATH)
	CrewRosterManager.reset_to_defaults()


func after_each() -> void:
	CrewRosterManager.reset_to_defaults()
	if _saved_override != "":
		var file := FileAccess.open(CrewRosterManager.USER_PATH, FileAccess.WRITE)
		file.store_string(_saved_override)
		file.close()


func _screen() -> Control:
	var screen: Control = CrewManagerScreen.new()
	add_child_autofree(screen)
	return screen


func _find_button(node: Node, text: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text == text:
			return child
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _find_sliders(node: Node, acc: Array) -> Array:
	for child in node.get_children():
		if child is HSlider:
			acc.append(child)
		_find_sliders(child, acc)
	return acc


func test_screen_lists_the_whole_roster():
	var screen := _screen()
	var roster_size := CrewRosterManager.load_roster().size()

	# One list row per entry plus the three footer buttons.
	var buttons: Array = []
	for child in screen.find_children("*", "Button", true, false):
		buttons.append(child)
	assert_gte(buttons.size(), roster_size,
		"Every roster entry gets a selectable row")


func test_editing_and_saving_writes_the_user_override():
	var screen := _screen()
	var first_skill: String = CrewData.SKILL_NAMES[0]

	_find_sliders(screen, [])[0].value = EDIT_SKILL
	_find_button(screen, "Save").pressed.emit()

	assert_true(CrewRosterManager.has_user_override(),
		"Saving creates the local override file")
	assert_eq(CrewRosterManager.load_roster()[0].skills[first_skill], EDIT_SKILL,
		"The edited skill value is what got saved")


func test_unsaved_edits_do_not_touch_the_roster_on_disk():
	var screen := _screen()

	_find_sliders(screen, [])[0].value = EDIT_SKILL

	assert_false(CrewRosterManager.has_user_override(),
		"Edits stay in the screen until Save is pressed")


func test_reset_discards_the_override_and_reloads_shipped_values():
	var screen := _screen()
	var shipped_value: float = CrewRosterManager.load_roster()[0].skills[CrewData.SKILL_NAMES[0]]
	_find_sliders(screen, [])[0].value = EDIT_SKILL
	_find_button(screen, "Save").pressed.emit()

	_find_button(screen, "Reset to defaults").pressed.emit()

	assert_false(CrewRosterManager.has_user_override(), "Reset removes the override")
	assert_eq(CrewRosterManager.load_roster()[0].skills[CrewData.SKILL_NAMES[0]], shipped_value,
		"The shipped roster applies again")
