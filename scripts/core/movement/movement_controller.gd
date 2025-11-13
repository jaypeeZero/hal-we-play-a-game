class_name MovementController
extends Node

## Orchestrates all movement subsystems
## Replaces manual movement logic in CreatureObject

const LocomotionSystem = preload("res://scripts/core/movement/locomotion_system.gd")
const SteeringSystem = preload("res://scripts/core/movement/steering_system.gd")
const KinematicConstraints = preload("res://scripts/core/movement/kinematic_constraints.gd")
const BehaviorModulator = preload("res://scripts/core/movement/behavior_modulator.gd")
const MovementTraits = preload("res://scripts/core/movement/movement_traits.gd")

# Components
var locomotion_system: LocomotionSystem
var steering_system: SteeringSystem
var kinematic_constraints: KinematicConstraints
var behavior_modulator: BehaviorModulator

# Current state
var velocity: Vector2 = Vector2.ZERO
var facing_direction: float = 0.0  # radians

# Movement request (set by AI/steering)
var desired_direction: Vector2 = Vector2.ZERO
var desired_speed: float = 0.0

func _init() -> void:
	locomotion_system = LocomotionSystem.new()
	steering_system = SteeringSystem.new()
	kinematic_constraints = KinematicConstraints.new()
	behavior_modulator = BehaviorModulator.new()

	add_child(locomotion_system)
	add_child(steering_system)
	add_child(kinematic_constraints)
	add_child(behavior_modulator)

## Main update loop - called by creature each frame
func update(delta: float) -> Vector2:
	# 1. Get steering force from AI
	var steering_force: Vector2 = steering_system.get_steering_force()

	# 2. Convert steering to desired movement
	if steering_force.length() > 0.1:
		desired_direction = steering_force.normalized()
	desired_speed = steering_system.get_desired_speed()

	# 3. Apply behavior modulation (hesitation, pauses)
	desired_speed = behavior_modulator.modulate_speed(desired_speed, delta)

	# 4. Update locomotion state (gait transitions)
	locomotion_system.update(desired_speed, delta)

	# 5. Apply kinematic constraints (turning, acceleration)
	var constrained_velocity: Vector2 = kinematic_constraints.apply(
		velocity, desired_direction, desired_speed, delta
	)

	# 6. Update velocity and facing
	velocity = constrained_velocity
	facing_direction = _update_facing(delta)

	# 7. Return movement delta for this frame
	return velocity * delta

func _update_facing(delta: float) -> float:
	# Smooth rotation toward velocity direction
	if velocity.length() > 0.1:
		return velocity.angle()
	return facing_direction

## Load movement traits from resource
func load_traits(traits: MovementTraits) -> void:
	locomotion_system.load_from_traits(traits)
	kinematic_constraints.load_from_traits(traits)
	behavior_modulator.load_from_traits(traits)
