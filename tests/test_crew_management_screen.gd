extends GutTest

## Behavior tests for CrewManagementScreen.
## Verifies: board present, show_ice enabled, close button emits closed,
## static open() self-frees on close, no Buy/Hire/Dismiss buttons.

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


func _make_screen() -> CrewManagementScreen:
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	var screen := CrewManagementScreen.new()
	add_child_autofree(screen)
	screen.setup()
	return screen


func test_setup_builds_an_assignment_board() -> void:
	var screen := _make_screen()
	assert_gt(_find_by_script(screen, CrewAssignmentBoard, []).size(), 0,
		"CrewManagementScreen contains a CrewAssignmentBoard")


func test_board_has_show_ice_enabled() -> void:
	var screen := _make_screen()
	var boards := _find_by_script(screen, CrewAssignmentBoard, [])
	assert_false(boards.is_empty(), "precondition: board present")
	assert_true(boards[0].show_ice, "Board has show_ice = true")


func test_close_button_emits_closed() -> void:
	var screen := _make_screen()
	watch_signals(screen)
	var close_btns := _find_buttons(screen, "Close", [])
	assert_eq(close_btns.size(), 1, "CrewManagementScreen has exactly one Close button")
	close_btns[0].pressed.emit()
	assert_signal_emitted(screen, "closed", "Pressing Close emits the closed signal")


func test_open_adds_screen_as_child_of_parent() -> void:
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	var host := Control.new()
	add_child_autofree(host)
	var screen := CrewManagementScreen.open(host)
	assert_true(screen.get_parent() == host,
		"open() adds the screen as a child of the given parent")
	# Clean up — close it so the autofree signal fires
	screen.emit_closed()


func test_open_screen_frees_itself_after_close() -> void:
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	var host := Control.new()
	add_child_autofree(host)
	var screen := CrewManagementScreen.open(host)
	screen.emit_closed()
	await get_tree().process_frame
	assert_false(is_instance_valid(screen),
		"Screen is freed after close when opened via CrewManagementScreen.open()")


func test_no_buy_button() -> void:
	var screen := _make_screen()
	assert_eq(_find_buttons(screen, "Buy", []).size(), 0,
		"No Buy button (ship purchases are Shop-only)")


func test_no_hire_button() -> void:
	var screen := _make_screen()
	assert_eq(_find_buttons_prefix(screen, "Hire", []).size(), 0,
		"No Hire button (hiring is Shop-only)")


func test_no_dismiss_button() -> void:
	var screen := _make_screen()
	assert_eq(_find_buttons_prefix(screen, "Dismiss", []).size(), 0,
		"No Dismiss button")
