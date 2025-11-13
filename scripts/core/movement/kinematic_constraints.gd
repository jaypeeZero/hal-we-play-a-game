class_name KinematicConstraints
extends Node

## Container for all physical constraints on movement

const TurningConstraint = preload("res://scripts/core/movement/constraints/turning_constraint.gd")
const AccelerationConstraint = preload("res://scripts/core/movement/constraints/acceleration_constraint.gd")
const MovementTraits = preload("res://scripts/core/movement/movement_traits.gd")

var turning_constraint: TurningConstraint
var acceleration_constraint: AccelerationConstraint

func _init() -> void:
	turning_constraint = TurningConstraint.new()
	acceleration_constraint = AccelerationConstraint.new()

func apply(
	current_velocity: Vector2,
	desired_direction: Vector2,
	desired_speed: float,
	delta: float
) -> Vector2:
	# 1. Apply turning constraint (can't instant turn)
	var feasible_direction: Vector2 = turning_constraint.constrain_direction(
		current_velocity, desired_direction, delta
	)

	# 2. Calculate desired velocity
	var desired_velocity: Vector2 = feasible_direction * desired_speed

	# 3. Apply acceleration constraint (momentum)
	var constrained_velocity: Vector2 = acceleration_constraint.apply(
		current_velocity, desired_velocity, delta
	)

	return constrained_velocity

func load_from_traits(traits: MovementTraits) -> void:
	# Configure turning
	turning_constraint.max_angular_velocity = traits.base_turn_rate
	turning_constraint.speed_affects_turning = true

	# Configure acceleration
	acceleration_constraint.max_acceleration = traits.max_acceleration
	acceleration_constraint.max_deceleration = traits.max_deceleration
	acceleration_constraint.inertia = traits.inertia
