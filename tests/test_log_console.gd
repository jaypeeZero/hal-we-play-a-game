extends GutTest

## Tests for the Battle-mode log console.
## Behavior-only: toggling, live tailing, filtering, and history seeding.

const LogConsoleScript = preload("res://scripts/space/log_console.gd")

var _console

func before_each():
	LogConsoleScript.capturing_input = false
	_console = LogConsoleScript.new()
	add_child_autofree(_console)

func _event(type: String, data: Dictionary = {}) -> Dictionary:
	return {"type": type, "timestamp": 1.0, "data": data}

func test_starts_closed_and_not_capturing():
	assert_false(_console.is_open(), "Console should start closed")
	assert_false(LogConsoleScript.capturing_input, "Closed console should not capture input")

func test_toggle_opens_and_closes():
	_console.toggle()
	assert_true(_console.is_open(), "Toggling a closed console opens it")
	assert_true(LogConsoleScript.capturing_input, "Open console captures input")

	_console.toggle()
	assert_false(_console.is_open(), "Toggling an open console closes it")
	assert_false(LogConsoleScript.capturing_input, "Closed console releases input capture")

func test_logged_event_appends_a_line():
	var before: int = _console.entry_count()
	_console.add_event(_event("damage_dealt", {"amount": 5}))
	assert_eq(_console.entry_count(), before + 1, "A new event adds an entry")

func test_filter_hides_non_matching_lines():
	_console.add_event(_event("damage_dealt", {"victim_id": "alpha"}))
	_console.add_event(_event("weapon_fired", {"shooter_id": "bravo"}))
	_console.add_event(_event("ship_spawned", {"ship_id": "charlie"}))

	_console.apply_filter("weapon")
	assert_eq(_console.visible_entry_count(), 1, "Filter shows only matching entries")

func test_filter_is_case_insensitive():
	_console.add_event(_event("weapon_fired", {"shooter_id": "Bravo"}))
	_console.apply_filter("WEAPON")
	assert_eq(_console.visible_entry_count(), 1, "Filter matches regardless of case")

func test_clearing_filter_restores_all_lines():
	_console.add_event(_event("damage_dealt"))
	_console.add_event(_event("weapon_fired"))
	var total: int = _console.entry_count()

	_console.apply_filter("weapon")
	assert_lt(_console.visible_entry_count(), total, "Filter narrows the visible set")

	_console.apply_filter("")
	assert_eq(_console.visible_entry_count(), total, "Clearing the filter restores all entries")

func test_entries_are_capped():
	var cap: int = LogConsoleScript.MAX_LOG_ENTRIES
	for i in range(cap + 50):
		_console.add_event(_event("ai_decision", {"n": i}))
	assert_true(_console.entry_count() <= cap, "Entry buffer never exceeds the cap")

func test_events_buffered_while_closed_appear_on_open():
	# Rendering is lazy: a closed console does no label work, but everything
	# buffered must show up once the console opens.
	_console.add_event(_event("damage_dealt", {"victim_id": "alpha"}))
	_console.toggle()
	await wait_process_frames(3)
	assert_string_contains(_console.get_label_text(), "damage_dealt")

func test_live_events_appear_while_open():
	_console.toggle()
	await wait_process_frames(3)
	_console.add_event(_event("weapon_fired", {"shooter_id": "bravo"}))
	await wait_process_frames(3)
	assert_string_contains(_console.get_label_text(), "weapon_fired")

func test_filter_change_rerenders_label():
	_console.add_event(_event("damage_dealt", {"victim_id": "alpha"}))
	_console.add_event(_event("weapon_fired", {"shooter_id": "bravo"}))
	_console.toggle()
	await wait_process_frames(3)
	_console.apply_filter("weapon")
	await wait_process_frames(3)
	var text: String = _console.get_label_text()
	assert_string_contains(text, "weapon_fired")
	assert_false(text.contains("damage_dealt"), "Filtered-out events leave the label")
