class_name SteeringSystem
extends Node

## Wrapper for existing SteeringBehaviors to integrate with MovementController

# Input from AI
var steering_force: Vector2 = Vector2.ZERO
var desired_speed: float = 0.0

func set_steering_force(force: Vector2) -> void:
	steering_force = force

func set_desired_speed(speed: float) -> void:
	desired_speed = speed

func get_steering_force() -> Vector2:
	return steering_force

func get_desired_speed() -> float:
	return desired_speed
