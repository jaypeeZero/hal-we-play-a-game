class_name MovementSystem
extends RefCounted

## Pure functional movement system - IMMUTABLE DATA
## Processes ship movement with realistic space physics
## Ships have momentum, thrust-based acceleration, and decoupled rotation
## Following functional programming principles

# ============================================================================
# MAIN API - Returns new ship_data with updated position/velocity
# ============================================================================

## Update ship movement - returns new ship_data Dictionary
static func update_ship_movement(ship_data: Dictionary, targets: Array, delta: float) -> Dictionary:
	if is_ship_disabled(ship_data):
		return apply_disabled_drift(ship_data, delta)

	var target = find_nearest_enemy(ship_data, targets)
	if target.is_empty():
		return apply_space_drift(ship_data, delta)

	# Calculate pilot intentions based on target and current state
	var pilot_control = calculate_pilot_control(ship_data, target)

	return apply_space_physics(ship_data, pilot_control, delta)

## Update all ships - returns new Array of ship_data
static func update_all_ships(ships: Array, delta: float) -> Array:
	return ships \
		.filter(func(ship): return ship != null) \
		.map(func(ship): return update_ship_movement(ship, ships, delta))

# ============================================================================
# SHIP STATE PREDICATES
# ============================================================================

static func is_ship_disabled(ship_data: Dictionary) -> bool:
	return ship_data.status in ["disabled", "destroyed", "exploding"]

# ============================================================================
# TARGET FINDING
# ============================================================================

static func find_nearest_enemy(ship_data: Dictionary, all_ships: Array) -> Dictionary:
	var enemies = get_enemy_ships(all_ships, ship_data.team)
	if enemies.is_empty():
		return {}

	return enemies \
		.map(func(enemy): return add_distance_from(enemy, ship_data.position)) \
		.reduce(select_nearest, {})

static func get_enemy_ships(ships: Array, own_team: int) -> Array:
	return ships \
		.filter(func(s): return s != null) \
		.filter(func(s): return s.team != own_team) \
		.filter(func(s): return s.status != "destroyed")

static func add_distance_from(ship: Dictionary, position: Vector2) -> Dictionary:
	var distance = position.distance_to(ship.position)
	return merge_dict(ship, {_distance = distance})

static func select_nearest(nearest: Dictionary, current: Dictionary) -> Dictionary:
	if nearest.is_empty():
		return current
	return current if get_distance(current) < get_distance(nearest) else nearest

static func get_distance(ship: Dictionary) -> float:
	return ship.get("_distance", INF)

# ============================================================================
# PILOT CONTROL CALCULATION
# ============================================================================

## Calculate what the pilot wants to do based on target and current state
static func calculate_pilot_control(ship_data: Dictionary, target: Dictionary) -> Dictionary:
	var to_target = target.position - ship_data.position
	var distance = to_target.length()
	var direction_to_target = to_target.normalized()

	# Determine if we need to brake (going too fast toward target)
	var velocity_toward_target = ship_data.velocity.dot(direction_to_target)
	var closing_speed = velocity_toward_target

	# Calculate optimal approach speed based on distance
	# Closer targets = slower approach
	var desired_approach_speed = min(ship_data.stats.max_speed * 0.7, distance * 0.3)

	var should_brake = closing_speed > desired_approach_speed and distance < 500.0
	var should_thrust = not should_brake

	# Decide what heading to face
	var desired_heading: float

	if should_brake:
		# Point opposite to velocity to brake
		if ship_data.velocity.length() > 10.0:
			desired_heading = ship_data.velocity.angle() + PI
		else:
			# If nearly stopped, point at target
			desired_heading = to_target.angle()
	else:
		# Point toward target for intercept
		# Lead the target slightly based on current velocity
		var intercept_point = calculate_intercept_point(ship_data, target)
		desired_heading = (intercept_point - ship_data.position).angle()

	return {
		"desired_heading": desired_heading,
		"thrust_active": should_thrust,
		"is_braking": should_brake
	}

## Calculate where to aim to intercept target (basic lead calculation)
static func calculate_intercept_point(ship_data: Dictionary, target: Dictionary) -> Vector2:
	# For now, just aim at target position
	# Future: predict target movement and lead the shot
	return target.position

# ============================================================================
# SPACE PHYSICS MOVEMENT
# ============================================================================

## Apply realistic space physics - ships drift, thrust provides acceleration
static func apply_space_physics(ship_data: Dictionary, pilot_control: Dictionary, delta: float) -> Dictionary:
	# Rotate ship toward desired heading
	var new_rotation = rotate_toward_heading(
		ship_data.rotation,
		pilot_control.desired_heading,
		ship_data.stats.turn_rate,
		delta
	)

	# Apply thrust if pilot wants to thrust and ship is facing roughly the right direction
	var heading_error = angle_difference(new_rotation, pilot_control.desired_heading)
	var thrust_efficiency = 1.0 if abs(heading_error) < 0.5 else max(0.0, 1.0 - abs(heading_error) / PI)

	var thrust_vector = Vector2.ZERO
	if pilot_control.thrust_active and thrust_efficiency > 0.1:
		# Apply thrust in the direction ship is facing
		var thrust_direction = Vector2(cos(new_rotation), sin(new_rotation))
		thrust_vector = thrust_direction * ship_data.stats.acceleration * thrust_efficiency * delta

	# Update velocity with thrust (no drag in space!)
	var new_velocity = ship_data.velocity + thrust_vector

	# Clamp to max speed (engine limitation)
	if new_velocity.length() > ship_data.stats.max_speed:
		new_velocity = new_velocity.normalized() * ship_data.stats.max_speed

	# Update position based on velocity
	var new_position = ship_data.position + new_velocity * delta

	return merge_dict(ship_data, {
		velocity = new_velocity,
		position = new_position,
		rotation = new_rotation,
		_pilot_state = pilot_control  # Store for debugging/visualization
	})

## Ships in space maintain velocity (Newton's first law)
static func apply_space_drift(ship_data: Dictionary, delta: float) -> Dictionary:
	var new_position = ship_data.position + ship_data.velocity * delta
	return merge_dict(ship_data, {
		position = new_position
	})

## Disabled ships slowly lose velocity (damage/venting atmosphere)
static func apply_disabled_drift(ship_data: Dictionary, delta: float) -> Dictionary:
	var new_velocity = ship_data.velocity * 0.98  # Slow decay for disabled ships
	var new_position = ship_data.position + new_velocity * delta
	return merge_dict(ship_data, {
		velocity = new_velocity,
		position = new_position
	})

## Rotate toward desired heading at turn_rate speed
static func rotate_toward_heading(current_rotation: float, target_rotation: float, turn_rate: float, delta: float) -> float:
	# Smooth rotation using lerp_angle for shortest path
	var rotation_speed = clamp(turn_rate * delta, 0.0, 1.0)
	return lerp_angle(current_rotation, target_rotation, rotation_speed)

## Calculate the signed difference between two angles
static func angle_difference(angle1: float, angle2: float) -> float:
	var diff = angle2 - angle1
	# Normalize to -PI to PI range
	while diff > PI:
		diff -= TAU
	while diff < -PI:
		diff += TAU
	return diff

# ============================================================================
# UTILITY
# ============================================================================

static func merge_dict(base: Dictionary, override: Dictionary) -> Dictionary:
	var result = base.duplicate(true)
	for key in override:
		result[key] = override[key]
	return result
