class_name LocomotionSystem
extends Node

## Manages movement gaits (walk/trot/gallop/hop) and transitions

const MovementTraits = preload("res://scripts/core/movement/movement_traits.gd")

enum Gait {
	IDLE,      # No movement, can rotate
	WALK,      # Slow, tight turns
	TROT,      # Medium speed, medium turns
	RUN,       # Fast, wide turns
	GALLOP,    # Very fast, very wide turns
	HOP,       # Discrete jumps with pauses
	SLITHER    # Continuous S-curve motion
}

signal gait_changed(gait: Gait)

var current_gait: Gait = Gait.IDLE

# Gait transition thresholds
var walk_threshold: float = 20.0
var trot_threshold: float = 60.0
var run_threshold: float = 100.0
var gallop_threshold: float = 150.0

# Current gait properties
var max_speed: float = 0.0
var acceleration_rate: float = 0.0
var turn_rate_multiplier: float = 1.0

# Locomotion type
var locomotion_type: String = "quadruped"

func update(desired_speed: float, delta: float) -> void:
	# Update gait based on desired speed
	var new_gait: Gait = _determine_gait(desired_speed)
	if new_gait != current_gait:
		_transition_to_gait(new_gait)

func _determine_gait(speed: float) -> Gait:
	if speed < 1.0:
		return Gait.IDLE
	elif speed < walk_threshold:
		return Gait.WALK
	elif speed < trot_threshold:
		return Gait.TROT
	elif speed < run_threshold:
		return Gait.RUN
	else:
		return Gait.GALLOP

func _transition_to_gait(new_gait: Gait) -> void:
	current_gait = new_gait
	gait_changed.emit(new_gait)

func load_from_traits(traits: MovementTraits) -> void:
	walk_threshold = traits.walk_speed
	trot_threshold = traits.trot_speed
	run_threshold = traits.run_speed
	gallop_threshold = traits.gallop_speed
	locomotion_type = traits.locomotion_type
