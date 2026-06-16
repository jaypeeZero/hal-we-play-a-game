extends GutTest

## Tests for NavGraph — the pure navigation graph for the roguelike meta-layer.
## All tests operate on NavGraph directly (no autoload, no scene switching).

# ─── Back navigation ──────────────────────────────────────────────────────────

func test_back_from_crew_returns_map() -> void:
	assert_eq(NavGraph.parent_of(NavGraph.Screen.CREW), NavGraph.Screen.MAP,
		"Back from CREW should lead to MAP")


func test_back_from_news_returns_map() -> void:
	assert_eq(NavGraph.parent_of(NavGraph.Screen.NEWS), NavGraph.Screen.MAP,
		"Back from NEWS should lead to MAP")


func test_back_from_pre_battle_returns_map() -> void:
	assert_eq(NavGraph.parent_of(NavGraph.Screen.PRE_BATTLE), NavGraph.Screen.MAP,
		"Back from PRE_BATTLE should lead to MAP")


func test_back_from_post_battle_returns_map() -> void:
	assert_eq(NavGraph.parent_of(NavGraph.Screen.POST_BATTLE), NavGraph.Screen.MAP,
		"Back from POST_BATTLE should lead to MAP")


func test_back_from_fleet_command_returns_map() -> void:
	assert_eq(NavGraph.parent_of(NavGraph.Screen.FLEET_COMMAND), NavGraph.Screen.MAP,
		"Back from FLEET_COMMAND should lead to MAP")


# ─── Floor behaviour ──────────────────────────────────────────────────────────

func test_map_is_the_floor() -> void:
	assert_true(NavGraph.is_floor(NavGraph.Screen.MAP),
		"MAP must be the floor (the roguelike home)")


func test_cannot_go_back_from_floor() -> void:
	assert_false(NavGraph.can_go_back(NavGraph.Screen.MAP),
		"can_go_back must be false at the floor")


func test_can_go_back_from_non_floor_screens() -> void:
	var non_floor: Array = [
		NavGraph.Screen.FLEET_COMMAND,
		NavGraph.Screen.CREW,
		NavGraph.Screen.NEWS,
		NavGraph.Screen.PRE_BATTLE,
		NavGraph.Screen.POST_BATTLE,
	]
	for screen in non_floor:
		assert_true(NavGraph.can_go_back(screen),
			"can_go_back must be true for screen %d" % screen)


func test_parent_of_floor_clamps_to_floor() -> void:
	assert_eq(NavGraph.parent_of(NavGraph.Screen.MAP), NavGraph.FLOOR,
		"parent_of(FLOOR) must clamp to FLOOR")


func test_parent_of_unknown_screen_clamps_to_floor() -> void:
	# Use an out-of-range int that is not a valid Screen value.
	var unknown_screen := 9999
	assert_eq(NavGraph.parent_of(unknown_screen), NavGraph.FLOOR,
		"parent_of(unknown) must clamp to FLOOR")


# ─── Scene path coverage ──────────────────────────────────────────────────────

func test_every_screen_has_a_non_empty_scene_path() -> void:
	for screen in NavGraph.SCENE_PATHS.keys():
		var path: String = NavGraph.SCENE_PATHS[screen]
		assert_true(path.length() > 0,
			"Screen %d must have a non-empty scene path" % screen)


func test_scene_paths_start_with_res() -> void:
	for screen in NavGraph.SCENE_PATHS.keys():
		var path: String = NavGraph.SCENE_PATHS[screen]
		assert_true(path.begins_with("res://"),
			"Scene path for screen %d must begin with res://: %s" % [screen, path])


# ─── Acyclicity + termination ─────────────────────────────────────────────────

func test_every_parent_chain_terminates_at_the_floor() -> void:
	# Walk the Back chain from every screen; must reach FLOOR within bounded steps.
	var max_depth: int = NavGraph.SCENE_PATHS.size() + 1
	for start_screen in NavGraph.SCENE_PATHS.keys():
		var current: int = start_screen
		var steps := 0
		while NavGraph.can_go_back(current):
			current = NavGraph.parent_of(current)
			steps += 1
			assert_true(steps <= max_depth,
				"Back chain from screen %d did not terminate within %d steps (cycle?)" % [
					start_screen, max_depth])
		assert_eq(current, NavGraph.FLOOR,
			"Back chain from screen %d must terminate at FLOOR, got %d" % [start_screen, current])
