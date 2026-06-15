class_name FleetCommandHost
extends Control

## Full-screen host that makes FleetCommandScreen a nav destination (the Fleet
## Command tab). Wraps the screen in "done" mode over the active run and adds
## the nav bar on top; finishing (Done) or Back returns to the Map.

var _nav_bar: NavBar


func _ready() -> void:
	"""Build the Fleet Command screen and the nav bar over the active run."""
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var screen := FleetCommandScreen.new()
	screen.setup(RunSource.new(), "done")
	screen.done.connect(_on_done)
	add_child(screen)
	# Nav bar added last so its Back/tabs stay above the fleet-command UI.
	_nav_bar = NavBar.attach(self, NavGraph.Screen.FLEET_COMMAND, true)


func _on_done() -> void:
	"""Finishing Fleet Command returns to the Map (the roguelike home)."""
	Nav.goto(NavGraph.Screen.MAP)
