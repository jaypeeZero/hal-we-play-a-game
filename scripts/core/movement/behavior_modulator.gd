class_name BehaviorModulator
extends Node

## Adds creature personality (hesitation, erratic movement, cautious behavior)

const MovementTraits = preload("res://scripts/core/movement/movement_traits.gd")

enum MovementPattern {
	CONTINUOUS,   # Standard movement (bear, wolf)
	HOPPING,      # Discrete hops with pauses (rat, rabbit)
	CAUTIOUS,     # Frequent stops and direction changes
	ERRATIC,      # Random speed/direction changes
	CHARGING      # Fixed direction, ignore obstacles
}

var pattern: MovementPattern = MovementPattern.CONTINUOUS
var is_fleeing: bool = false

# Hopping state
var hop_timer: float = 0.0
var pause_timer: float = 0.0
var is_paused: bool = false
var hop_duration_min: float = 0.2
var hop_duration_max: float = 0.4
var pause_duration_min: float = 0.3
var pause_duration_max: float = 0.8

# Cautious state
var movement_timer: float = 0.0
var next_pause_time: float = 1.0

func modulate_speed(desired_speed: float, delta: float) -> float:
	match pattern:
		MovementPattern.HOPPING:
			return _modulate_hopping(desired_speed, delta)
		MovementPattern.CAUTIOUS:
			return _modulate_cautious(desired_speed, delta)
		_:
			return desired_speed

func _modulate_hopping(speed: float, delta: float) -> float:
	if is_fleeing:
		# When fleeing, switch to continuous movement
		is_paused = false
		return speed

	# Hopping pattern: move → pause → move → pause
	if is_paused:
		pause_timer -= delta
		if pause_timer <= 0:
			is_paused = false
			hop_timer = randf_range(hop_duration_min, hop_duration_max)
		else:
			# Override to zero speed during pause
			return 0.0
	else:
		hop_timer -= delta
		if hop_timer <= 0:
			is_paused = true
			pause_timer = randf_range(pause_duration_min, pause_duration_max)

	return speed

func _modulate_cautious(speed: float, delta: float) -> float:
	if is_fleeing:
		return speed

	movement_timer += delta
	if movement_timer >= next_pause_time:
		# Brief pause
		movement_timer = 0.0
		next_pause_time = randf_range(0.8, 2.0)
		return speed * 0.3

	return speed

func load_from_traits(traits: MovementTraits) -> void:
	if traits.locomotion_type == "hopper":
		pattern = MovementPattern.HOPPING
		hop_duration_min = traits.hop_duration * 0.7
		hop_duration_max = traits.hop_duration * 1.3
		pause_duration_min = traits.pause_between_hops_min
		pause_duration_max = traits.pause_between_hops_max
