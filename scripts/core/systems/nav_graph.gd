class_name NavGraph
extends RefCounted

## Pure navigation graph for the roguelike meta-layer.
## Holds screen hierarchy constants and testable helper functions only.
## No scene-tree access — safe to instantiate in unit tests.

enum Screen {
	FLEET_MANAGER,
	MAP,
	CREW,
	NEWS,
	PRE_BATTLE,
	POST_BATTLE,
}

const SCENE_PATHS: Dictionary = {
	Screen.FLEET_MANAGER: "res://scenes/fleet_management.tscn",
	Screen.MAP:           "res://scenes/campaign_map_3d.tscn",
	Screen.CREW:          "res://scenes/run_crew.tscn",
	Screen.NEWS:          "res://scenes/news.tscn",
	Screen.PRE_BATTLE:    "res://scenes/pre_battle.tscn",
	Screen.POST_BATTLE:   "res://scenes/post_battle.tscn",
}

## The bottom of the Back stack — Back never navigates past this.
const FLOOR: int = Screen.FLEET_MANAGER

## Fixed parent hierarchy: each screen's Back destination.
const PARENTS: Dictionary = {
	Screen.MAP:         Screen.FLEET_MANAGER,
	Screen.CREW:        Screen.MAP,
	Screen.NEWS:        Screen.MAP,
	Screen.PRE_BATTLE:  Screen.MAP,
	Screen.POST_BATTLE: Screen.MAP,
}


## Returns true if `screen` is the floor (no Back from here).
static func is_floor(screen: int) -> bool:
	"""Return true when screen has no parent (is the floor or unregistered)."""
	return screen == FLOOR or not PARENTS.has(screen)


## Returns the parent of `screen`, clamping to FLOOR for unknown inputs.
static func parent_of(screen: int) -> int:
	"""Return the Back-target of screen; clamps to FLOOR for unknown inputs."""
	return PARENTS.get(screen, FLOOR)


## Returns true when Back is available from `screen`.
static func can_go_back(screen: int) -> bool:
	"""Return true when there is a parent to navigate Back to."""
	return not is_floor(screen)
