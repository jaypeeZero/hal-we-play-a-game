class_name AccelerationConstraint
extends Resource

## Constrains acceleration and deceleration based on mass/inertia

@export var max_acceleration: float = 300.0  # units/sec^2
@export var max_deceleration: float = 400.0
@export var inertia: float = 1.0  # Higher = more momentum

func apply(
	current_velocity: Vector2,
	desired_velocity: Vector2,
	delta: float
) -> Vector2:
	var velocity_change: Vector2 = desired_velocity - current_velocity

	if velocity_change.length() < 0.1:
		return desired_velocity

	var acceleration_needed: Vector2 = velocity_change / delta

	# Determine if accelerating or decelerating
	var is_speeding_up: bool = velocity_change.length() > 0 and desired_velocity.length() > current_velocity.length()
	var max_accel: float = max_acceleration if is_speeding_up else max_deceleration
	max_accel = max_accel / inertia

	# Clamp acceleration magnitude
	if acceleration_needed.length() > max_accel:
		acceleration_needed = acceleration_needed.normalized() * max_accel

	return current_velocity + acceleration_needed * delta
