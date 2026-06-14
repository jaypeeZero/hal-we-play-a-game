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


func _find_gallery(node: Node) -> GridContainer:
	# The crew gallery is the GridContainer whose direct children are the
	# clickable crew cards (each a PanelContainer holding a CrewPortrait).
	for child in node.get_children():
		if child is GridContainer:
			return child as GridContainer
		var found := _find_gallery(child)
		if found != null:
			return found
	return null


func _find_crew_cards(node: Node, _acc: Array) -> Array:
	# Crew cards are the direct PanelContainer children of the gallery grid.
	var gallery := _find_gallery(node)
	var cards: Array = []
	if gallery == null:
		return cards
	for child in gallery.get_children():
		if child is PanelContainer:
			cards.append(child)
	return cards


func test_gallery_has_one_selectable_card_per_roster_entry():
	var screen := _screen()
	var roster_size := CrewRosterManager.load_roster().size()
	assert_gt(roster_size, 0, "Sanity: roster is non-empty")

	var cards := _find_crew_cards(screen, [])
	assert_eq(cards.size(), roster_size,
		"Every roster entry produces exactly one crew card")


func test_selecting_a_card_updates_the_shown_crew():
	var screen := _screen()
	var roster: Array = CrewRosterManager.load_roster()
	if roster.size() < 2:
		pass_test("Need at least two crew to verify selection changes")
		return

	var cards := _find_crew_cards(screen, [])
	# Selecting the second card should drive the dossier to the second entry's
	# callsign. The dossier (CrewMemberView) shows the selected callsign somewhere.
	var second_callsign: String = str(roster[1].get("callsign", ""))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	cards[1]._gui_input(click)

	var shown := _label_texts_contain(screen, second_callsign)
	assert_true(shown, "Clicking a card shows that crew member in the dossier")


func _label_texts_contain(node: Node, needle: String) -> bool:
	for child in node.get_children():
		if child is LineEdit and (child as LineEdit).text == needle:
			return true
		if child is Label and (child as Label).text.find(needle) != -1:
			return true
		if _label_texts_contain(child, needle):
			return true
	return false


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
