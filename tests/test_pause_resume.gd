extends GutTest

## Tests for pause/resume functionality in SpaceBattleGame

var _game: SpaceBattleGame


func before_each() -> void:
	_game = SpaceBattleGame.new()
	add_child(_game)
	# Wait for _ready to complete
	await get_tree().process_frame


func after_each() -> void:
	_game.queue_free()


func _create_space_key_event(pressed: bool, echo: bool = false) -> InputEventKey:
	var event = InputEventKey.new()
	event.keycode = KEY_SPACE
	event.pressed = pressed
	event.echo = echo
	return event


# ============================================================================
# PROCESS MODE TESTS
# ============================================================================

func test_game_has_process_mode_when_paused():
	assert_eq(_game.process_mode, Node.PROCESS_MODE_WHEN_PAUSED,
		"SpaceBattleGame must have PROCESS_MODE_WHEN_PAUSED to receive input when paused")


# ============================================================================
# INITIAL STATE TESTS
# ============================================================================

func test_game_starts_paused():
	assert_true(get_tree().paused, "Game should start paused")


# ============================================================================
# PAUSE TOGGLE TESTS
# ============================================================================

func test_space_key_unpauses_game():
	# Game starts paused
	assert_true(get_tree().paused, "Precondition: game is paused")

	# Press space
	var event = _create_space_key_event(true)
	_game._input(event)

	assert_false(get_tree().paused, "Space key should unpause the game")


func test_space_key_pauses_running_game():
	# First unpause
	get_tree().paused = false
	assert_false(get_tree().paused, "Precondition: game is running")

	# Press space
	var event = _create_space_key_event(true)
	_game._input(event)

	assert_true(get_tree().paused, "Space key should pause the running game")


func test_space_key_toggles_pause_state():
	# Start paused
	get_tree().paused = true

	# First press - should unpause
	var event1 = _create_space_key_event(true)
	_game._input(event1)
	assert_false(get_tree().paused, "First space press should unpause")

	# Second press - should pause
	var event2 = _create_space_key_event(true)
	_game._input(event2)
	assert_true(get_tree().paused, "Second space press should pause")

	# Third press - should unpause again
	var event3 = _create_space_key_event(true)
	_game._input(event3)
	assert_false(get_tree().paused, "Third space press should unpause again")


# ============================================================================
# INPUT FILTERING TESTS
# ============================================================================

func test_space_key_release_does_not_toggle():
	get_tree().paused = true

	# Release space (pressed = false)
	var event = _create_space_key_event(false)
	_game._input(event)

	assert_true(get_tree().paused, "Space key release should NOT toggle pause")


func test_space_echo_does_not_toggle():
	get_tree().paused = true

	# Echo event (key repeat)
	var event = _create_space_key_event(true, true)
	_game._input(event)

	assert_true(get_tree().paused, "Space key echo/repeat should NOT toggle pause")


func test_other_keys_do_not_toggle():
	get_tree().paused = true

	# Press Enter key instead of Space
	var event = InputEventKey.new()
	event.keycode = KEY_ENTER
	event.pressed = true
	event.echo = false
	_game._input(event)

	assert_true(get_tree().paused, "Other keys should NOT toggle pause")


# ============================================================================
# PROCESS BEHAVIOR TESTS
# ============================================================================

func test_process_skips_when_paused():
	# Get initial ship positions
	var ships_before = _game.get_ships().duplicate(true)

	# Ensure game is paused
	get_tree().paused = true

	# Run a frame of processing
	_game._process(0.1)

	# Ships should not have moved
	var ships_after = _game.get_ships()
	for i in range(min(ships_before.size(), ships_after.size())):
		assert_eq(ships_after[i].position, ships_before[i].position,
			"Ships should not move when paused")
