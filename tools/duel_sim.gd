extends SceneTree

## Thin launcher for the duel harness — all logic lives in duel_sim_core.gd.
##
## The core is loaded at the first process frame rather than referenced
## statically: game scripts reference autoload singletons
## (BattleEventLoggerAutoload), which don't exist yet when a --script main
## loop compiles. Deferring the load lets every dependency compile against a
## fully initialized project.
##
## Usage:
##   godot --headless --script tools/duel_sim.gd
##   godot --headless --script tools/duel_sim.gd -- --duels 50 --skill-a 0.9 --skill-b 0.2 --seed 7

var _started := false

func _init() -> void:
	process_frame.connect(_run)

func _run() -> void:
	if _started:
		return
	_started = true
	var core = load("res://tools/duel_sim_core.gd").new()
	quit(core.run(self, OS.get_cmdline_user_args()))
