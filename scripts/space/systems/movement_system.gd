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

	# Get nearby ships for collision avoidance
	var nearby_ships = get_nearby_friendly_ships(ship_data, targets)

	# Check crew AI orders first
	var current_order = ship_data.get("orders", {}).get("current_order", "")
	var pilot_control: Dictionary

	if current_order == "evade":
		# Evade mode - retreat from threats
		var threat_id = ship_data.get("orders", {}).get("threat_id", "")
		var threat = find_ship_by_id(targets, threat_id) if threat_id else find_nearest_enemy(ship_data, targets)
		if threat.is_empty():
			return apply_space_drift(ship_data, delta)
		pilot_control = calculate_evasion_control(ship_data, threat, nearby_ships, obstacles)

	elif current_order == "fighter_engage":
		# FighterPilotAI engage mode - specialized fighter maneuvers
		var target_id = ship_data.get("orders", {}).get("target_id", "")
		var target = find_ship_by_id(targets, target_id) if target_id else find_nearest_enemy(ship_data, targets)
		if target.is_empty():
			return apply_space_drift(ship_data, delta)
		pilot_control = calculate_fighter_pilot_control(ship_data, target, nearby_ships, obstacles)

	elif current_order == "engage":
		# Engage mode - pursue and attack target
		var target_id = ship_data.get("orders", {}).get("target_id", "")
		var target = find_ship_by_id(targets, target_id) if target_id else find_nearest_enemy(ship_data, targets)
		if target.is_empty():
			return apply_space_drift(ship_data, delta)
		pilot_control = calculate_pilot_control(ship_data, target, nearby_ships, obstacles)

	else:
		# No orders or unknown order - use default behavior (find nearest enemy)
		var target = find_nearest_enemy(ship_data, targets)
		if target.is_empty():
			return apply_space_drift(ship_data, delta)
		pilot_control = calculate_pilot_control(ship_data, target, nearby_ships, obstacles)

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

static func find_ship_by_id(ships: Array, ship_id: String) -> Dictionary:
	for ship in ships:
		if ship != null and ship.get("ship_id") == ship_id:
			return ship
	return {}

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

## Calculate evasion control - retreat from threat
static func calculate_evasion_control(ship_data: Dictionary, threat: Dictionary, nearby_ships: Array, obstacles: Array = []) -> Dictionary:
	var to_threat = threat.position - ship_data.position
	var distance = to_threat.length()
	var direction_from_threat = -to_threat.normalized()  # Run AWAY from threat

	# Try to get at least this far from threat
	var safe_distance = get_engagement_range(ship_data) * 2.0

	# Check for collision threats
	var ship_avoidance = calculate_collision_avoidance(ship_data, nearby_ships)
	var obstacle_avoidance = calculate_obstacle_avoidance(ship_data, obstacles)
	var avoidance_vector = ship_avoidance + obstacle_avoidance
	var has_collision_threat = avoidance_vector.length() > 0.1

	var desired_heading: float
	var should_thrust: bool
	var is_braking: bool = false

	if distance < safe_distance:
		# Too close! Retreat at full speed
		var retreat_direction = direction_from_threat

		# Apply avoidance if needed
		if has_collision_threat:
			if obstacle_avoidance.length() > 0.1:
				retreat_direction = (retreat_direction + obstacle_avoidance.normalized()).normalized()
			else:
				retreat_direction = (retreat_direction + ship_avoidance.normalized()).normalized()

		desired_heading = retreat_direction.angle()
		should_thrust = true
	else:
		# At safe distance - maintain position with evasive drift
		var drift_position = ship_data.position + direction_from_threat * safe_distance
		var to_drift = drift_position - ship_data.position

		if to_drift.length() > 10.0:
			desired_heading = to_drift.angle()
			should_thrust = ship_data.velocity.length() < ship_data.stats.max_speed * 0.5
		else:
			# At good position, face away from threat
			desired_heading = direction_from_threat.angle()
			should_thrust = false

	return {
		"desired_heading": desired_heading,
		"thrust_active": should_thrust,
		"is_braking": is_braking,
		"engagement_range": safe_distance,
		"current_distance": distance
	}

## Calculate fighter pilot control - specialized FighterPilotAI maneuvers
static func calculate_fighter_pilot_control(ship_data: Dictionary, target: Dictionary, nearby_ships: Array, obstacles: Array = []) -> Dictionary:
	var maneuver_subtype = ship_data.get("orders", {}).get("maneuver_subtype", "pursue")

	# Route to appropriate maneuver calculation
	match maneuver_subtype:
		"pursue_full_speed":
			return calculate_pursue_full_speed(ship_data, target, nearby_ships, obstacles)
		"pursue_tactical":
			return calculate_pursue_tactical(ship_data, target, nearby_ships, obstacles)
		"flank_behind":
			return calculate_flank_behind(ship_data, target, nearby_ships, obstacles)
		"tight_pursuit":
			return calculate_tight_pursuit(ship_data, target, nearby_ships, obstacles)
		"dogfight_maneuver":
			return calculate_dogfight_maneuver(ship_data, target, nearby_ships, obstacles)
		"group_run_approach":
			return calculate_group_run_approach(ship_data, target, nearby_ships, obstacles)
		"group_run_attack":
			return calculate_group_run_attack(ship_data, target, nearby_ships, obstacles)
		"group_run_swing_around":
			return calculate_group_run_swing_around(ship_data, target, nearby_ships, obstacles)
		"evasive_retreat":
			return calculate_evasive_retreat(ship_data, target, nearby_ships, obstacles)
		"cautious_approach":
			return calculate_cautious_approach(ship_data, target, nearby_ships, obstacles)
		"dodge_and_weave":
			return calculate_dodge_and_weave(ship_data, target, nearby_ships, obstacles)
		_:
			# Fallback to standard pilot control
			return calculate_pilot_control(ship_data, target, nearby_ships, obstacles)

## Pursue at full speed - far away approach
static func calculate_pursue_full_speed(ship_data: Dictionary, target: Dictionary, nearby_ships: Array, obstacles: Array) -> Dictionary:
	var to_target = target.position - ship_data.position
	var desired_heading = to_target.angle()

	# DART AND DASH: Check if we need to brake and change direction
	var needs_course_correction = check_needs_braking(ship_data, desired_heading)

	if needs_course_correction:
		# Brake hard, then we'll dart in the new direction
		return create_braking_control(ship_data, desired_heading, to_target.length())

	return {
		"desired_heading": desired_heading,
		"thrust_active": true,
		"is_braking": false,
		"engagement_range": 250.0,
		"current_distance": to_target.length()
	}

## Tactical pursuit - mid range, slowing approach
static func calculate_pursue_tactical(ship_data: Dictionary, target: Dictionary, nearby_ships: Array, obstacles: Array) -> Dictionary:
	var to_target = target.position - ship_data.position
	var distance = to_target.length()
	var direction = to_target.normalized()

	# Predict target position
	var target_velocity = target.get("velocity", Vector2.ZERO)
	var predicted_pos = target.position + target_velocity * 0.5

	var to_predicted = predicted_pos - ship_data.position
	var desired_heading = to_predicted.angle()

	# DART AND DASH: Brake if changing direction significantly
	var needs_course_correction = check_needs_braking(ship_data, desired_heading)
	if needs_course_correction:
		return create_braking_control(ship_data, desired_heading, distance)

	# Slow down if going too fast toward target
	var closing_speed = ship_data.velocity.dot(direction)
	var should_brake = closing_speed > ship_data.stats.max_speed * 0.5

	return {
		"desired_heading": desired_heading,
		"thrust_active": not should_brake,
		"is_braking": should_brake,
		"engagement_range": 250.0,
		"current_distance": distance
	}

## Flank behind - try to get behind target
static func calculate_flank_behind(ship_data: Dictionary, target: Dictionary, nearby_ships: Array, obstacles: Array) -> Dictionary:
	var behind_position = ship_data.get("orders", {}).get("behind_position", Vector2.ZERO)
	if behind_position == Vector2.ZERO:
		# Calculate behind position
		var target_rotation = target.get("rotation", 0.0)
		var behind_offset = Vector2(cos(target_rotation + PI), sin(target_rotation + PI)) * 150.0
		behind_position = target.position + behind_offset

	var to_behind = behind_position - ship_data.position
	var desired_heading = to_behind.angle()

	# DART AND DASH: Sharp turns to get behind enemy
	var needs_course_correction = check_needs_braking(ship_data, desired_heading)
	if needs_course_correction:
		return create_braking_control(ship_data, desired_heading, to_behind.length())

	return {
		"desired_heading": desired_heading,
		"thrust_active": true,
		"is_braking": false,
		"engagement_range": 250.0,
		"current_distance": to_behind.length()
	}

## Tight pursuit - close range, stay behind
static func calculate_tight_pursuit(ship_data: Dictionary, target: Dictionary, nearby_ships: Array, obstacles: Array) -> Dictionary:
	var target_rotation = target.get("rotation", 0.0)
	var target_velocity = target.get("velocity", Vector2.ZERO)

	# Stay behind target at close range
	var behind_offset = Vector2(cos(target_rotation + PI), sin(target_rotation + PI)) * 120.0
	var desired_pos = target.position + behind_offset + target_velocity * 0.3

	var to_desired = desired_pos - ship_data.position
	var distance = to_desired.length()
	var desired_heading = to_desired.angle()

	# DART AND DASH: Quick corrections to stay on target's tail
	var needs_course_correction = check_needs_braking(ship_data, desired_heading)
	if needs_course_correction:
		return create_braking_control(ship_data, desired_heading, distance)

	# Match target speed - brake if too fast, thrust if too slow
	var speed_diff = ship_data.velocity.length() - target_velocity.length()
	var should_brake = speed_diff > 30.0  # More aggressive braking
	var should_thrust = speed_diff < -10.0 or distance > 150.0

	return {
		"desired_heading": desired_heading,
		"thrust_active": should_thrust,
		"is_braking": should_brake,
		"engagement_range": 120.0,
		"current_distance": distance
	}

## Dogfight maneuver - tight weaving and loops
static func calculate_dogfight_maneuver(ship_data: Dictionary, target: Dictionary, nearby_ships: Array, obstacles: Array) -> Dictionary:
	var to_target = target.position - ship_data.position
	var distance = to_target.length()

	# Weave pattern - add perpendicular offset
	var perpendicular = Vector2(-to_target.y, to_target.x).normalized()
	var weave_phase = fmod(Time.get_ticks_msec() / 800.0, 2.0)  # Faster weaving
	var weave_offset = perpendicular * sin(weave_phase * PI) * 60.0  # Tighter weave

	var desired_pos = target.position + weave_offset
	var to_desired = desired_pos - ship_data.position
	var desired_heading = to_desired.angle()

	# DART AND DASH: Very aggressive direction changes for dogfighting
	# Use tighter threshold for course correction (30 degrees instead of 45)
	var current_velocity = ship_data.get("velocity", Vector2.ZERO)
	if current_velocity.length() > 40.0:
		var current_heading = current_velocity.angle()
		var heading_diff = abs(angle_difference(current_heading, desired_heading))
		if heading_diff > PI / 6.0:  # 30 degrees - tighter for dogfighting
			return create_braking_control(ship_data, desired_heading, distance)

	# Quick bursts - not constant thrust
	var should_thrust = ship_data.velocity.length() < ship_data.stats.max_speed * 0.6
	var should_brake = ship_data.velocity.length() > ship_data.stats.max_speed * 0.8

	return {
		"desired_heading": desired_heading,
		"thrust_active": should_thrust,
		"is_braking": should_brake,
		"engagement_range": 150.0,
		"current_distance": distance
	}

## Group run approach - approach with other fighters
static func calculate_group_run_approach(ship_data: Dictionary, target: Dictionary, nearby_ships: Array, obstacles: Array) -> Dictionary:
	var formation_offset = ship_data.get("orders", {}).get("formation_offset", Vector2.ZERO)
	var to_target = target.position - ship_data.position + formation_offset
	var desired_heading = to_target.angle()

	# DART AND DASH: Brake for formation adjustments
	var needs_course_correction = check_needs_braking(ship_data, desired_heading)
	if needs_course_correction:
		return create_braking_control(ship_data, desired_heading, to_target.length())

	return {
		"desired_heading": desired_heading,
		"thrust_active": true,
		"is_braking": false,
		"engagement_range": 400.0,
		"current_distance": to_target.length()
	}

## Group run attack - execute attack run
static func calculate_group_run_attack(ship_data: Dictionary, target: Dictionary, nearby_ships: Array, obstacles: Array) -> Dictionary:
	var to_target = target.position - ship_data.position
	var distance = to_target.length()
	var desired_heading = to_target.angle()

	# DART AND DASH: Line up the attack run
	var needs_course_correction = check_needs_braking(ship_data, desired_heading)
	if needs_course_correction:
		return create_braking_control(ship_data, desired_heading, distance)

	# Full speed attack run once lined up
	var should_thrust = distance > 150.0

	return {
		"desired_heading": desired_heading,
		"thrust_active": should_thrust,
		"is_braking": false,
		"engagement_range": 300.0,
		"current_distance": distance
	}

## Group run swing around - swing around for another pass
static func calculate_group_run_swing_around(ship_data: Dictionary, target: Dictionary, nearby_ships: Array, obstacles: Array) -> Dictionary:
	var to_target = target.position - ship_data.position
	var distance = to_target.length()

	# Swing out to the side then come back around
	var perpendicular = Vector2(-to_target.y, to_target.x).normalized()
	var swing_out_pos = target.position + perpendicular * 500.0

	var to_swing = swing_out_pos - ship_data.position
	var desired_heading = to_swing.angle()

	# DART AND DASH: Hard brake to swing around quickly
	var needs_course_correction = check_needs_braking(ship_data, desired_heading)
	if needs_course_correction:
		return create_braking_control(ship_data, desired_heading, distance)

	return {
		"desired_heading": desired_heading,
		"thrust_active": true,
		"is_braking": false,
		"engagement_range": 500.0,
		"current_distance": distance
	}

## Evasive retreat - get away from big ship
static func calculate_evasive_retreat(ship_data: Dictionary, target: Dictionary, nearby_ships: Array, obstacles: Array) -> Dictionary:
	var away_from_target = (ship_data.position - target.position).normalized()
	var desired_heading = away_from_target.angle()

	# Add weave to dodge - quick darts side to side
	var perpendicular = Vector2(-away_from_target.y, away_from_target.x)
	var weave_phase = fmod(Time.get_ticks_msec() / 600.0, 2.0)  # Faster weaving
	var weave_offset = perpendicular * sin(weave_phase * PI) * 80.0  # Tighter weave

	var desired_pos = ship_data.position + away_from_target * 300.0 + weave_offset
	var to_desired = desired_pos - ship_data.position
	desired_heading = to_desired.angle()

	# DART AND DASH: Sharp evasive maneuvers
	var current_velocity = ship_data.get("velocity", Vector2.ZERO)
	if current_velocity.length() > 40.0:
		var current_heading = current_velocity.angle()
		var heading_diff = abs(angle_difference(current_heading, desired_heading))
		if heading_diff > PI / 5.0:  # 36 degrees - quick evasion threshold
			return create_braking_control(ship_data, desired_heading, to_desired.length())

	return {
		"desired_heading": desired_heading,
		"thrust_active": true,
		"is_braking": false,
		"engagement_range": 500.0,
		"current_distance": ship_data.position.distance_to(target.position)
	}

## Cautious approach - close in slowly
static func calculate_cautious_approach(ship_data: Dictionary, target: Dictionary, nearby_ships: Array, obstacles: Array) -> Dictionary:
	var to_target = target.position - ship_data.position
	var distance = to_target.length()

	# Approach at an angle, not directly
	var perpendicular = Vector2(-to_target.y, to_target.x).normalized()
	var approach_pos = target.position + perpendicular * 200.0

	var to_approach = approach_pos - ship_data.position
	var desired_heading = to_approach.angle()

	# Half speed approach
	var should_thrust = ship_data.velocity.length() < ship_data.stats.max_speed * 0.5

	return {
		"desired_heading": desired_heading,
		"thrust_active": should_thrust,
		"is_braking": false,
		"engagement_range": 400.0,
		"current_distance": distance
	}

## Dodge and weave - stay at range, dodge
static func calculate_dodge_and_weave(ship_data: Dictionary, target: Dictionary, nearby_ships: Array, obstacles: Array) -> Dictionary:
	var to_target = target.position - ship_data.position
	var distance = to_target.length()

	# Orbit around target with weave pattern - quick darts
	var perpendicular = Vector2(-to_target.y, to_target.x).normalized()
	var orbit_phase = fmod(Time.get_ticks_msec() / 1500.0, 2.0 * PI)  # Faster orbit
	var weave_phase = fmod(Time.get_ticks_msec() / 500.0, 2.0)  # Faster weave

	var orbit_offset = perpendicular * 400.0
	var weave_offset = to_target.normalized() * sin(weave_phase * PI) * 80.0  # Tighter weave

	var desired_pos = target.position + orbit_offset + weave_offset
	var to_desired = desired_pos - ship_data.position
	var desired_heading = to_desired.angle()

	# DART AND DASH: Quick direction changes while dodging
	var current_velocity = ship_data.get("velocity", Vector2.ZERO)
	if current_velocity.length() > 50.0:
		var current_heading = current_velocity.angle()
		var heading_diff = abs(angle_difference(current_heading, desired_heading))
		if heading_diff > PI / 4.5:  # ~40 degrees
			return create_braking_control(ship_data, desired_heading, distance)

	# Burst thrust pattern - not constant
	var should_thrust = ship_data.velocity.length() < ship_data.stats.max_speed * 0.6
	var should_brake = ship_data.velocity.length() > ship_data.stats.max_speed * 0.8

	return {
		"desired_heading": desired_heading,
		"thrust_active": should_thrust,
		"is_braking": should_brake,
		"engagement_range": 400.0,
		"current_distance": distance
	}

## DART AND DASH HELPERS - Make fighters fly with sharp movements, not sliding

## Check if ship needs to brake before changing direction
static func check_needs_braking(ship_data: Dictionary, desired_heading: float) -> bool:
	var current_velocity = ship_data.get("velocity", Vector2.ZERO)

	# If moving very slowly, no need to brake
	if current_velocity.length() < 30.0:
		return false

	# Calculate angle difference between current velocity and desired heading
	var current_heading = current_velocity.angle()
	var heading_diff = abs(angle_difference(current_heading, desired_heading))

	# If we need to turn more than 45 degrees and we're moving fast, brake first
	if heading_diff > PI / 4.0:  # 45 degrees
		return true

	return false

## Create braking control - hard brake to prepare for direction change
static func create_braking_control(ship_data: Dictionary, desired_heading: float, distance: float) -> Dictionary:
	var current_velocity = ship_data.get("velocity", Vector2.ZERO)

	# Point opposite to current velocity for maximum braking
	var brake_heading = current_velocity.angle() + PI

	return {
		"desired_heading": brake_heading,
		"thrust_active": true,  # Thrust in opposite direction = hard brake
		"is_braking": true,
		"engagement_range": 250.0,
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

	# Apply thrust if pilot wants to thrust
	var thrust_vector = Vector2.ZERO
	if pilot_control.thrust_active:
		# Calculate thrust direction (where the ship wants to go)
		var desired_thrust_direction = Vector2(cos(pilot_control.desired_heading), sin(pilot_control.desired_heading))
		var ship_facing = Vector2(cos(new_rotation), sin(new_rotation))

		# Calculate angle between ship facing and desired thrust direction
		var thrust_angle_diff = abs(ship_facing.angle_to(desired_thrust_direction))

		# Determine which thrusters to use based on angle
		# Forward arc (±45°): main engines at full power
		# Lateral arc (45°-135°): maneuvering thrusters
		# Reverse arc (135°-180°): reverse thrusters (also maneuvering)
		var acceleration_to_use: float
		if thrust_angle_diff < PI / 4:  # Within 45° of forward
			acceleration_to_use = ship_data.stats.acceleration
		else:  # Lateral or reverse
			acceleration_to_use = ship_data.stats.get("lateral_acceleration", ship_data.stats.acceleration * 0.3)

		thrust_vector = desired_thrust_direction * acceleration_to_use * delta

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

# ============================================================================
# OBSTACLE MOVEMENT
# ============================================================================

## Update obstacle position based on velocity (Newton's first law - objects in motion stay in motion)
static func update_obstacle_movement(obstacle_data: Dictionary, delta: float) -> Dictionary:
	if obstacle_data == null:
		return obstacle_data

	# Skip destroyed obstacles
	if obstacle_data.get("status", "operational") == "destroyed":
		return obstacle_data

	var velocity = obstacle_data.get("velocity", Vector2.ZERO)
	var angular_velocity = obstacle_data.get("angular_velocity", 0.0)

	# No movement needed if stationary
	if velocity.length() < 0.01 and abs(angular_velocity) < 0.001:
		return obstacle_data

	# Update position and rotation based on velocity
	var updated_obstacle = obstacle_data.duplicate(true)
	updated_obstacle.position += velocity * delta
	updated_obstacle.rotation += angular_velocity * delta

	return updated_obstacle

## Update all obstacles - returns new Array of obstacle_data
static func update_all_obstacles(obstacles: Array, delta: float) -> Array:
	return obstacles \
		.filter(func(obstacle): return obstacle != null) \
		.map(func(obstacle): return update_obstacle_movement(obstacle, delta))
