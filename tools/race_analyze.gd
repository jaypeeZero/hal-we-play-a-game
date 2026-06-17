extends SceneTree

## Headless flight-line analyzer. Launches via the deferred-load pattern (so the
## crew-AI class graph resolves), runs one racer, and prints quantitative line
## quality — heading-rate over time, the post-gate "snap", and where each gate is
## crossed — so flight tuning can be judged from numbers, not just by eye.
##
## Usage:
##   godot --headless --script tools/race_analyze.gd -- --track=asteroid_sprint --piloting=0.7

var _started := false


func _init() -> void:
	process_frame.connect(_run)


func _run() -> void:
	if _started:
		return
	_started = true
	var core = load("res://tools/race_analyze_core.gd").new()
	quit(core.run(self, OS.get_cmdline_user_args()))
