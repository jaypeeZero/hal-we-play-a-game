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
static func update_ship_movement(ship_data: Dictionary, targets: Array, delta: float, obstacles: Array = []) -> Dictionary:
	if is_ship_disabled(ship_data):
		return apply_disabled_drift(ship_data, delta)

	var target = find_nearest_enemy(ship_data, targets)
	if target.is_empty():
		return apply_space_drift(ship_data, delta)

	# Get nearby ships for collision avoidance
	var nearby_ships = get_nearby_friendly_ships(ship_data, targets)

	# Calculate pilot intentions based on target, nearby ships, and obstacles
	var pilot_control = calculate_pilot_control(ship_data, target, nearby_ships, obstacles)

	return apply_space_physics(ship_data, pilot_control, delta)

## Update all ships - returns new Array of ship_data
static func update_all_ships(ships: Array, delta: float, obstacles: Array = []) -> Array:
	return ships \
		.filter(func(ship): return ship != null) \
		.map(func(ship): return update_ship_movement(ship, ships, delta, obstacles))

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
	return DictUtils.merge_dict(ship, {_distance = distance})

static func select_nearest(nearest: Dictionary, current: Dictionary) -> Dictionary:
	if nearest.is_empty():
		return current
	return current if get_distance(current) < get_distance(nearest) else nearest

static func get_distance(ship: Dictionary) -> float:
	return ship.get("_distance", INF)

## Get nearby friendly ships for collision avoidance
static func get_nearby_friendly_ships(ship_data: Dictionary, all_ships: Array) -> Array:
	var collision_awareness_range = 200.0  # Pilots watch for collisions within this range
	return all_ships \
		.filter(func(s): return s != null) \
		.filter(func(s): return s.ship_id != ship_data.ship_id) \
		.filter(func(s): return s.team == ship_data.team) \
		.filter(func(s): return s.status != "destroyed") \
		.filter(func(s): return ship_data.position.distance_to(s.position) < collision_awareness_range)

# ============================================================================
# PILOT CONTROL CALCULATION
# ============================================================================

## Calculate what the pilot wants to do based on target and current state
static func calculate_pilot_control(ship_data: Dictionary, target: Dictionary, nearby_ships: Array, obstacles: Array = []) -> Dictionary:
	var to_target = target.position - ship_data.position
	var distance = to_target.length()
	var direction_to_target = to_target.normalized()

	# Determine engagement range based on ship type (naval-style combat)
	var engagement_range = get_engagement_range(ship_data)
	var min_safe_distance = engagement_range * 0.7  # Don't get too close
	var max_engagement_distance = engagement_range * 1.3  # Don't get too far

	# Check for collision threats from ships and obstacles
	var ship_avoidance = calculate_collision_avoidance(ship_data, nearby_ships)
	var obstacle_avoidance = calculate_obstacle_avoidance(ship_data, obstacles)
	var avoidance_vector = ship_avoidance + obstacle_avoidance
	var has_collision_threat = avoidance_vector.length() > 0.1

	# Determine desired position relative to target
	var desired_position: Vector2
	var desired_heading: float
	var should_thrust: bool
	var is_braking: bool

	if distance < min_safe_distance:
		# Too close! Back off while keeping target in arc
		desired_position = calculate_retreat_position(ship_data, target, engagement_range)
		is_braking = true
		should_thrust = false
	elif distance > max_engagement_distance:
		# Too far, close distance
		desired_position = calculate_approach_position(ship_data, target, engagement_range)
		is_braking = false
		should_thrust = true
	else:
		# At good range - maintain position and orbit/strafe
		desired_position = calculate_combat_orbit_position(ship_data, target, engagement_range)
		# Only thrust if we're drifting away or need to maintain position
		var velocity_toward_desired = ship_data.velocity.dot((desired_position - ship_data.position).normalized())
		should_thrust = velocity_toward_desired < ship_data.stats.max_speed * 0.3
		is_braking = false

	# Apply collision avoidance if needed (obstacles have higher priority)
	if has_collision_threat:
		# Obstacles are more urgent than tactical positioning
		if obstacle_avoidance.length() > 0.1:
			desired_position += obstacle_avoidance * 200.0  # Strong obstacle avoidance
		else:
			desired_position += ship_avoidance * 100.0  # Normal ship avoidance

	# Calculate heading and movement
	var to_desired = desired_position - ship_data.position
	var velocity_toward_target = ship_data.velocity.dot(direction_to_target)

	# Determine heading based on what we're doing
	if is_braking and ship_data.velocity.length() > 10.0:
		# Point opposite to velocity to brake
		desired_heading = ship_data.velocity.angle() + PI
	elif has_collision_threat and distance > min_safe_distance:
		# Point toward avoidance direction
		desired_heading = to_desired.angle()
		should_thrust = true
	else:
		# Point toward desired position for maneuvering
		if to_desired.length() > 10.0:
			desired_heading = to_desired.angle()
		else:
			# At desired position, face the target
			desired_heading = to_target.angle()

	# Check if we're going too fast toward target
	var closing_speed = velocity_toward_target
	var safe_approach_speed = min(ship_data.stats.max_speed * 0.5, (distance - min_safe_distance) * 0.4)

	if closing_speed > safe_approach_speed and distance < engagement_range:
		is_braking = true
		should_thrust = false
		if ship_data.velocity.length() > 10.0:
			desired_heading = ship_data.velocity.angle() + PI

	return {
		"desired_heading": desired_heading,
		"thrust_active": should_thrust,
		"is_braking": is_braking,
		"engagement_range": engagement_range,
		"current_distance": distance
	}

## Get engagement range based on ship type (naval-style combat distances)
static func get_engagement_range(ship_data: Dictionary) -> float:
	match ship_data.type:
		"fighter":
			return 250.0  # Fighters engage at closer range
		"corvette":
			return 350.0  # Corvettes at medium range
		"capital":
			return 500.0  # Capital ships engage from far away
		_:
			return 300.0  # Default

## Calculate collision avoidance vector from nearby ships
static func calculate_collision_avoidance(ship_data: Dictionary, nearby_ships: Array) -> Vector2:
	if nearby_ships.is_empty():
		return Vector2.ZERO

	var avoidance = Vector2.ZERO
	for other_ship in nearby_ships:
		var to_other = other_ship.position - ship_data.position
		var distance = to_other.length()

		# Stronger avoidance the closer they are
		var danger_distance = 150.0
		if distance < danger_distance and distance > 0.1:
			var avoidance_strength = (danger_distance - distance) / danger_distance
			# Point away from the other ship
			avoidance -= to_other.normalized() * avoidance_strength

	return avoidance.normalized() if avoidance.length() > 0.1 else Vector2.ZERO

## Calculate obstacle avoidance vector - returns normalized direction away from obstacles
static func calculate_obstacle_avoidance(ship_data: Dictionary, obstacles: Array) -> Vector2:
	if obstacles.is_empty():
		return Vector2.ZERO

	var avoidance = Vector2.ZERO
	var detection_range = ship_data.stats.size * 8.0  # Look ahead distance

	# Filter active obstacles that block movement
	var active_obstacles = obstacles \
		.filter(func(o): return o != null) \
		.filter(func(o): return o.get("status", "operational") != "destroyed") \
		.filter(func(o): return o.get("blocks_movement", true))

	for obstacle in active_obstacles:
		var to_obstacle = obstacle.position - ship_data.position
		var distance = to_obstacle.length()
		var combined_radius = ship_data.stats.size + obstacle.radius

		# Only avoid obstacles in detection range
		if distance > detection_range:
			continue

		# Emergency avoidance if already too close or colliding
		if distance < combined_radius * 1.5:
			var away_direction = -to_obstacle.normalized() if distance > 0.1 else Vector2(1, 0)
			# Very strong avoidance for close obstacles
			var urgency = max(2.0, (combined_radius * 1.5 - distance) / combined_radius)
			avoidance += away_direction * urgency
			continue

		# Calculate avoidance strength based on distance and whether obstacle is ahead
		var ahead_distance = to_obstacle.normalized().dot(ship_data.velocity.normalized()) if ship_data.velocity.length() > 0.1 else 0.0

		# Only avoid obstacles in front of the ship
		if ahead_distance > 0.3:
			var threat_level = 1.0 - ((distance - combined_radius) / detection_range)
			threat_level = clamp(threat_level, 0.0, 1.0)

			# Stronger avoidance for closer obstacles
			var away_direction = (ship_data.position - obstacle.position).normalized()
			avoidance += away_direction * threat_level

	return avoidance.normalized() if avoidance.length() > 0.1 else Vector2.ZERO

## Calculate position to retreat to when too close
static func calculate_retreat_position(ship_data: Dictionary, target: Dictionary, engagement_range: float) -> Vector2:
	# Back away from target to engagement range
	var away_from_target = (ship_data.position - target.position).normalized()
	return target.position + away_from_target * engagement_range

## Calculate position to approach when too far
static func calculate_approach_position(ship_data: Dictionary, target: Dictionary, engagement_range: float) -> Vector2:
	# Move toward target to engagement range
	var toward_target = (target.position - ship_data.position).normalized()
	return target.position - toward_target * engagement_range

## Calculate orbital combat position (circle strafe around target)
static func calculate_combat_orbit_position(ship_data: Dictionary, target: Dictionary, engagement_range: float) -> Vector2:
	# Calculate a position that orbits around the target
	var to_ship = ship_data.position - target.position
	var current_angle = to_ship.angle()

	# Orbit clockwise (could be randomized per ship for variety)
	var orbit_speed = 0.5  # radians per second worth of orbit
	var desired_angle = current_angle + orbit_speed

	# Position at engagement range, offset by orbit angle
	return target.position + Vector2(cos(desired_angle), sin(desired_angle)) * engagement_range

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

	return DictUtils.merge_dict(ship_data, {
		velocity = new_velocity,
		position = new_position,
		rotation = new_rotation,
		_pilot_state = pilot_control  # Store for debugging/visualization
	})

## Ships in space maintain velocity (Newton's first law)
static func apply_space_drift(ship_data: Dictionary, delta: float) -> Dictionary:
	var new_position = ship_data.position + ship_data.velocity * delta
	return DictUtils.merge_dict(ship_data, {
		position = new_position
	})

## Disabled/destroyed ships drift forever at constant velocity (Newton's first law)
static func apply_disabled_drift(ship_data: Dictionary, delta: float) -> Dictionary:
	# Dead ships keep drifting - no decay, this is space!
	var new_position = ship_data.position + ship_data.velocity * delta
	return DictUtils.merge_dict(ship_data, {
		position = new_position
		# velocity and rotation unchanged - they drift forever
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

