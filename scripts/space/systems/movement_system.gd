class_name MovementSystem
extends RefCounted

## Pure functional movement system - IMMUTABLE DATA
## Processes ship movement and basic AI behaviors
## Following functional programming principles

# ============================================================================
# MAIN API - Returns new ship_data with updated position/velocity
# ============================================================================

## Update ship movement - returns new ship_data Dictionary
static func update_ship_movement(ship_data: Dictionary, targets: Array, delta: float) -> Dictionary:
	if is_ship_disabled(ship_data):
		return apply_drift(ship_data, delta)

	var target = find_nearest_enemy(ship_data, targets)
	if target.is_empty():
		return apply_drift(ship_data, delta)

	return apply_seek_behavior(ship_data, target, delta)

## Update all ships - returns new Array of ship_data
static func update_all_ships(ships: Array, delta: float) -> Array:
	return ships.map(func(ship): return update_ship_movement(ship, ships, delta))

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
# MOVEMENT BEHAVIORS
# ============================================================================

static func apply_drift(ship_data: Dictionary, delta: float) -> Dictionary:
	var new_velocity = ship_data.velocity * 0.95
	var new_position = ship_data.position + new_velocity * delta
	return merge_dict(ship_data, {
		velocity = new_velocity,
		position = new_position
	})

static func apply_seek_behavior(ship_data: Dictionary, target: Dictionary, delta: float) -> Dictionary:
	var to_target = (target.position - ship_data.position).normalized()
	var desired_velocity = to_target * ship_data.stats.max_speed

	var steering = calculate_steering(ship_data.velocity, desired_velocity, ship_data.stats.acceleration, delta)
	var new_velocity = clamp_velocity(ship_data.velocity + steering, ship_data.stats.max_speed)
	var new_position = ship_data.position + new_velocity * delta
	var new_rotation = calculate_rotation_toward_velocity(ship_data.rotation, new_velocity, ship_data.stats.turn_rate, delta)

	return merge_dict(ship_data, {
		velocity = new_velocity,
		position = new_position,
		rotation = new_rotation
	})

static func calculate_steering(current_velocity: Vector2, desired_velocity: Vector2, acceleration: float, delta: float) -> Vector2:
	var steering = desired_velocity - current_velocity
	var max_force = acceleration * delta

	if steering.length() > max_force:
		return steering.normalized() * max_force
	return steering

static func clamp_velocity(velocity: Vector2, max_speed: float) -> Vector2:
	if velocity.length() > max_speed:
		return velocity.normalized() * max_speed
	return velocity

static func calculate_rotation_toward_velocity(current_rotation: float, velocity: Vector2, turn_rate: float, delta: float) -> float:
	if velocity.length() < 0.1:
		return current_rotation

	var target_rotation = velocity.angle()
	return lerp_angle(current_rotation, target_rotation, turn_rate * delta)

# ============================================================================
# UTILITY
# ============================================================================

static func merge_dict(base: Dictionary, override: Dictionary) -> Dictionary:
	var result = base.duplicate(true)
	for key in override:
		result[key] = override[key]
	return result
