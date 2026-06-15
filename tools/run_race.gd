extends SceneTree

## Thin launcher for the ship-race debug harness — all logic lives in
## run_race_core.gd.
##
## The core is loaded at the first process frame rather than referenced
## statically: the race flight path reaches the crew-AI graph, which references
## autoload singletons (BattleEventLoggerAutoload) that don't exist yet when a
## --script main loop compiles. Deferring the load lets every dependency
## compile against a fully initialized project (same pattern as duel_sim.gd).
##
## Usage:
##   godot --headless --script tools/run_race.gd
##   godot --headless --script tools/run_race.gd -- \
##     --track=asteroid_sprint --seed=42 --field=fighter,fighter,corvette

var _started := false


func _init() -> void:
	process_frame.connect(_run)


func _run() -> void:
	if _started:
		return
	_started = true
	var core = load("res://tools/run_race_core.gd").new()
	quit(core.run(self, OS.get_cmdline_user_args()))
