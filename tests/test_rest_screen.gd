extends GutTest

## Tests for RestScreen — BEHAVIOR ONLY.
## Verifies: board is present, no buy/hire/dismiss buttons, Leave emits closed.

var _saved_fleet_hulls: Array
var _saved_money: int
var _saved_active: bool
var _saved_hired_ids: Array


func before_each() -> void:
	_saved_fleet_hulls = RoguelikeRun.fleet_hulls.duplicate(true)
	_saved_money = RoguelikeRun.money
	_saved_active = RoguelikeRun.active
	_saved_hired_ids = RoguelikeRun.hired_roster_ids.duplicate()


func after_each() -> void:
	RoguelikeRun.fleet_hulls = _saved_fleet_hulls
	RoguelikeRun.money = _saved_money
	RoguelikeRun.active = _saved_active
	RoguelikeRun.hired_roster_ids = _saved_hired_ids


func _counts(overrides: Dictionary = {}) -> Dictionary:
	var base := {"fighter": 0, "heavy_fighter": 0,
		"torpedo_boat": 0, "corvette": 0, "capital": 0}
	for key in overrides:
		base[key] = overrides[key]
	return base


func _find_by_script(node: Node, script: Script, acc: Array) -> Array:
	for child in node.get_children():
		if child.get_script() == script:
			acc.append(child)
		_find_by_script(child, script, acc)
	return acc


func _find_buttons(node: Node, text: String, acc: Array) -> Array:
	for child in node.get_children():
		if child is Button and child.text == text:
			acc.append(child)
		_find_buttons(child, text, acc)
	return acc


func _find_buttons_prefix(node: Node, prefix: String, acc: Array) -> Array:
	for child in node.get_children():
		if child is Button and child.text.begins_with(prefix):
			acc.append(child)
		_find_buttons_prefix(child, prefix, acc)
	return acc


func _make_screen() -> RestScreen:
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	var screen := RestScreen.new()
	add_child_autofree(screen)
	screen.setup()
	return screen


func test_rest_screen_has_an_assignment_board():
	var screen := _make_screen()

	assert_gt(_find_by_script(screen, CrewAssignmentBoard, []).size(), 0,
		"RestScreen contains a CrewAssignmentBoard")


func test_rest_screen_board_has_show_ice_enabled():
	var screen := _make_screen()
	var boards := _find_by_script(screen, CrewAssignmentBoard, [])
	assert_false(boards.is_empty(), "precondition: board is present")

	var board: CrewAssignmentBoard = boards[0]
	assert_true(board.show_ice,
		"The R&R board shows ice/activate controls")


func test_rest_screen_has_no_buy_button():
	var screen := _make_screen()

	assert_eq(_find_buttons(screen, "Buy", []).size(), 0,
		"RestScreen has no Buy button (ship purchases are Shop-only)")


func test_rest_screen_has_no_hire_button():
	var screen := _make_screen()

	assert_eq(_find_buttons_prefix(screen, "Hire", []).size(), 0,
		"RestScreen has no Hire button (hiring is Shop-only)")


func test_rest_screen_has_no_dismiss_button():
	var screen := _make_screen()

	assert_eq(_find_buttons_prefix(screen, "Dismiss", []).size(), 0,
		"RestScreen has no Dismiss button")


func test_rest_screen_leave_emits_closed():
	var screen := _make_screen()
	watch_signals(screen)

	var leave_btns := _find_buttons(screen, "Leave", [])
	assert_eq(leave_btns.size(), 1, "RestScreen has exactly one Leave button")
	leave_btns[0].pressed.emit()

	assert_signal_emitted(screen, "closed", "Pressing Leave emits the closed signal")


func test_rest_screen_leave_does_not_free_itself():
	var screen := _make_screen()
	screen.closed.connect(func(): pass)

	_find_buttons(screen, "Leave", [])[0].pressed.emit()

	# If it self-freed, is_instance_valid would return false.
	assert_true(is_instance_valid(screen),
		"RestScreen does not self-free on Leave — caller is responsible")
