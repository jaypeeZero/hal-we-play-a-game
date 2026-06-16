extends Node

## Nav — roguelike screen navigation autoload.
## Thin scene-switch shim over NavGraph (the pure, testable graph).
## Register in project.godot autoloads as "Nav".

## Re-export the Screen enum so callers can write Nav.Screen.MAP etc.
const Screen = NavGraph.Screen
const SCENE_PATHS = NavGraph.SCENE_PATHS
const FLOOR = NavGraph.FLOOR
const PARENTS = NavGraph.PARENTS


## Navigate directly to `screen`, replacing the current scene.
func goto(screen: int) -> void:
	"""Switch to the scene mapped to `screen`."""
	get_tree().change_scene_to_file(NavGraph.SCENE_PATHS[screen])


## Navigate to the parent of `from_screen`. No-op at the floor.
func back(from_screen: int) -> void:
	"""Go to the parent of from_screen; no-op when already at the floor."""
	if NavGraph.is_floor(from_screen):
		return
	goto(NavGraph.parent_of(from_screen))


## Returns true if `screen` is the floor (Back is disabled).
func is_floor(screen: int) -> bool:
	"""Delegate to NavGraph.is_floor."""
	return NavGraph.is_floor(screen)


## Returns the parent of `screen`, clamping to FLOOR for unknown inputs.
func parent_of(screen: int) -> int:
	"""Delegate to NavGraph.parent_of."""
	return NavGraph.parent_of(screen)


## Returns true when Back is available from `screen`.
func can_go_back(screen: int) -> bool:
	"""Delegate to NavGraph.can_go_back."""
	return NavGraph.can_go_back(screen)
