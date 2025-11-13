class_name TurningConstraint
extends Resource

## Constrains turning rate based on current speed and physical limits

@export var max_angular_velocity: float = 3.0  # radians per second
@export var speed_affects_turning: bool = true

func constrain_direction(
	current_velocity: Vector2,
	desired_direction: Vector2,
	delta: float
) -> Vector2:
	# Can turn freely when stopped
	if current_velocity.length() < 0.1:
		return desired_direction

	var current_angle: float = current_velocity.angle()
	var desired_angle: float = desired_direction.angle()
	var angle_diff: float = angle_difference(current_angle, desired_angle)

	# Calculate max turn based on speed
	var max_turn: float = max_angular_velocity * delta
	if speed_affects_turning:
		var speed_factor: float = current_velocity.length() / 100.0
		max_turn = max_turn / (1.0 + speed_factor * 0.5)

	# Clamp turn angle
	var actual_turn: float = clamp(angle_diff, -max_turn, max_turn)
	var actual_angle: float = current_angle + actual_turn

	return Vector2.RIGHT.rotated(actual_angle)
