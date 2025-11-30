class_name MovementSystem
extends RefCounted

## Pure functional movement system - IMMUTABLE DATA
## Processes ship movement with realistic space physics
## Ships have momentum, thrust-based acceleration, and decoupled rotation
## Following functional programming principles

# ============================================================================
# COORDINATE SYSTEM NOTES
# ============================================================================
# Ship sprites are drawn pointing UP (Y-negative) at rotation 0.
# Godot's standard rotation 0 = facing RIGHT (X-positive).
#
# To make ships visually face a direction, we need:
#   heading = direction.angle() + PI/2
#
# To get the direction a ship is visually facing:
#   visual_forward = Vector2(sin(rotation), -cos(rotation))
#
# This offset (PI/2) is applied throughout this file.

## Convert a direction vector to a heading angle that makes the ship VISUALLY face that direction
static func direction_to_heading(direction: Vector2) -> float:
	return direction.angle() + PI / 2

## Get the visual forward direction of a ship from its rotation
static func get_visual_forward(rotation: float) -> Vector2:
	return Vector2(sin(rotation), -cos(rotation))

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

	if ship_data.get("type") == "corvette":
		print("[MovementSystem] Corvette %s order: '%s', target: %s" % [
			ship_data.get("ship_id", "?"),
			current_order,
			ship_data.get("orders", {}).get("target_id", "none")
		])

	if current_order == "evade":
		# Evade mode - retreat from threats
		var threat_id = ship_data.get("orders", {}).get("threat_id", "")
		var threat = find_ship_by_id(targets, threat_id) if threat_id else find_nearest_enemy(ship_data, targets)
		if threat.is_empty():
			return apply_space_drift(ship_data, delta)
		pilot_control = calculate_evasion_control(ship_data, threat, nearby_ships, obstacles)

	elif current_order == "retreat":
		# Retreat mode - flee from threat at maximum speed
		var threat_id = ship_data.get("orders", {}).get("threat_id", "")
		var threat = find_ship_by_id(targets, threat_id) if threat_id else find_nearest_enemy(ship_data, targets)
		if threat.is_empty():
			return apply_space_drift(ship_data, delta)
		pilot_control = calculate_retreat_control(ship_data, threat, nearby_ships, obstacles)

	elif current_order == "fighter_engage":
		# FighterPilotAI engage mode - specialized fighter maneuvers
		var target_id = ship_data.get("orders", {}).get("target_id", "")
		var target = find_ship_by_id(targets, target_id) if target_id else find_nearest_enemy(ship_data, targets)
		if target.is_empty():
			return apply_space_drift(ship_data, delta)
		pilot_control = calculate_fighter_pilot_control(ship_data, target, nearby_ships, obstacles)

	elif current_order == "broadside":
		# Broadside mode - maintain optimal distance for broadside fire
		var target_id = ship_data.get("orders", {}).get("target_id", "")
		var target = find_ship_by_id(targets, target_id) if target_id else find_nearest_enemy(ship_data, targets)
		if target.is_empty():
			return apply_space_drift(ship_data, delta)
		var optimal_distance = ship_data.get("orders", {}).get("optimal_distance", 1200.0)
		pilot_control = calculate_broadside_control(ship_data, target, optimal_distance, nearby_ships, obstacles)

	elif current_order == "kite":
		# Kite mode - maintain distance while firing
		var target_id = ship_data.get("orders", {}).get("target_id", "")
		var target = find_ship_by_id(targets, target_id) if target_id else find_nearest_enemy(ship_data, targets)
		if target.is_empty():
			return apply_space_drift(ship_data, delta)
		var maintain_distance = ship_data.get("orders", {}).get("maintain_distance", 1500.0)
		pilot_control = calculate_kite_control(ship_data, target, maintain_distance, nearby_ships, obstacles)

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

	if ship_data.get("type") == "corvette":
		print("[MovementSystem] Corvette %s pilot_control: thrust=%s, heading=%.1f" % [
			ship_data.get("ship_id", "?"),
			pilot_control.get("thrust_active", false),
			rad_to_deg(pilot_control.get("desired_heading", 0.0))
		])

	var result = apply_space_physics(ship_data, pilot_control, delta)

	if ship_data.get("type") == "corvette":
		print("[MovementSystem] Corvette %s velocity: (%.1f, %.1f), speed: %.1f" % [
			ship_data.get("ship_id", "?"),
			result.velocity.x,
			result.velocity.y,
			result.velocity.length()
		])

	return result

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
		desired_heading = direction_to_heading(-ship_data.velocity.normalized())
	elif has_collision_threat and distance > min_safe_distance:
		# Point toward avoidance direction
		desired_heading = direction_to_heading(to_desired)
		should_thrust = true
	else:
		# Point toward desired position for maneuvering
		if to_desired.length() > 10.0:
			desired_heading = direction_to_heading(to_desired)
		else:
			# At desired position, face the target
			desired_heading = direction_to_heading(to_target)

	# Check if we're going too fast toward target
	var closing_speed = velocity_toward_target
	var safe_approach_speed = min(ship_data.stats.max_speed * 0.5, (distance - min_safe_distance) * 0.4)

	if closing_speed > safe_approach_speed and distance < engagement_range:
		is_braking = true
		should_thrust = false
		if ship_data.velocity.length() > 10.0:
			desired_heading = direction_to_heading(-ship_data.velocity.normalized())

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

		desired_heading = direction_to_heading(retreat_direction)
		should_thrust = true
	else:
		# At safe distance - maintain position with evasive drift
		var drift_position = ship_data.position + direction_from_threat * safe_distance
		var to_drift = drift_position - ship_data.position

		if to_drift.length() > 10.0:
			desired_heading = direction_to_heading(to_drift)
			should_thrust = ship_data.velocity.length() < ship_data.stats.max_speed * 0.5
		else:
			# At good position, face away from threat
			desired_heading = direction_to_heading(direction_from_threat)
			should_thrust = false

	return {
		"desired_heading": desired_heading,
		"thrust_active": should_thrust,
		"is_braking": is_braking,
		"engagement_range": safe_distance,
		"current_distance": distance
	}

## Calculate retreat control - full speed retreat from threat
static func calculate_retreat_control(ship_data: Dictionary, threat: Dictionary, nearby_ships: Array, obstacles: Array = []) -> Dictionary:
	var to_threat = threat.position - ship_data.position
	var distance = to_threat.length()
	var direction_from_threat = -to_threat.normalized()  # Run AWAY from threat

	# Check for collision threats
	var ship_avoidance = calculate_collision_avoidance(ship_data, nearby_ships)
	var obstacle_avoidance = calculate_obstacle_avoidance(ship_data, obstacles)
	var avoidance_vector = ship_avoidance + obstacle_avoidance
	var has_collision_threat = avoidance_vector.length() > 0.1

	# Always retreat at full speed
	var retreat_direction = direction_from_threat

	# Apply avoidance if needed
	if has_collision_threat:
		if obstacle_avoidance.length() > 0.1:
			retreat_direction = (retreat_direction + obstacle_avoidance.normalized()).normalized()
		else:
			retreat_direction = (retreat_direction + ship_avoidance.normalized()).normalized()

	var desired_heading = direction_to_heading(retreat_direction)

	return {
		"desired_heading": desired_heading,
		"thrust_active": true,  # Always thrust when retreating
		"is_braking": false,
		"engagement_range": 0.0,  # No engagement, just flee
		"current_distance": distance
	}

## Calculate broadside control - maintain optimal distance for broadside fire
static func calculate_broadside_control(ship_data: Dictionary, target: Dictionary, optimal_distance: float, nearby_ships: Array, obstacles: Array = []) -> Dictionary:
	var to_target = target.position - ship_data.position
	var distance = to_target.length()
	var direction_to_target = to_target.normalized()

	# Check for collision threats
	var ship_avoidance = calculate_collision_avoidance(ship_data, nearby_ships)
	var obstacle_avoidance = calculate_obstacle_avoidance(ship_data, obstacles)
	var avoidance_vector = ship_avoidance + obstacle_avoidance
	var has_collision_threat = avoidance_vector.length() > 0.1

	var desired_heading: float
	var should_thrust: bool
	var is_braking: bool = false

	var distance_error = distance - optimal_distance
	var tolerance = optimal_distance * 0.15  # 15% tolerance

	if abs(distance_error) > tolerance:
		# Need to adjust distance
		if distance_error > 0:
			# Too far - close in slowly
			desired_heading = direction_to_heading(direction_to_target)
			should_thrust = true
		else:
			# Too close - back off
			desired_heading = direction_to_heading(-direction_to_target)
			should_thrust = true
	else:
		# At optimal distance - maintain broadside orientation
		# For broadside, we want to be perpendicular to the target
		var perpendicular = Vector2(-direction_to_target.y, direction_to_target.x)

		# Orbit to maintain broadside
		var orbit_position = ship_data.position + perpendicular * 100.0
		var to_orbit = orbit_position - ship_data.position

		if to_orbit.length() > 10.0:
			desired_heading = direction_to_heading(to_orbit)
			should_thrust = ship_data.velocity.length() < ship_data.stats.max_speed * 0.3
		else:
			# Face perpendicular to target for broadside
			desired_heading = direction_to_heading(perpendicular)
			should_thrust = false

	# Apply collision avoidance
	if has_collision_threat:
		if obstacle_avoidance.length() > 0.1:
			var avoid_dir = (direction_to_target + obstacle_avoidance.normalized()).normalized()
			desired_heading = direction_to_heading(avoid_dir)
		else:
			var avoid_dir = (direction_to_target + ship_avoidance.normalized()).normalized()
			desired_heading = direction_to_heading(avoid_dir)
		should_thrust = true

	return {
		"desired_heading": desired_heading,
		"thrust_active": should_thrust,
		"is_braking": is_braking,
		"engagement_range": optimal_distance,
		"current_distance": distance
	}

## Calculate kite control - maintain distance while firing
static func calculate_kite_control(ship_data: Dictionary, target: Dictionary, maintain_distance: float, nearby_ships: Array, obstacles: Array = []) -> Dictionary:
	var to_target = target.position - ship_data.position
	var distance = to_target.length()
	var direction_to_target = to_target.normalized()

	# Check for collision threats
	var ship_avoidance = calculate_collision_avoidance(ship_data, nearby_ships)
	var obstacle_avoidance = calculate_obstacle_avoidance(ship_data, obstacles)
	var avoidance_vector = ship_avoidance + obstacle_avoidance
	var has_collision_threat = avoidance_vector.length() > 0.1

	var desired_heading: float
	var should_thrust: bool
	var is_braking: bool = false

	# Kiting: stay at distance, face target, back away if they close
	var distance_error = distance - maintain_distance
	var tolerance = maintain_distance * 0.1  # 10% tolerance

	if distance_error < -tolerance:
		# Target too close - back away while facing them
		desired_heading = direction_to_heading(direction_to_target)  # Face target

		# Check if we're already moving away
		var velocity_away = ship_data.velocity.dot(-direction_to_target)
		if velocity_away < ship_data.stats.max_speed * 0.5:
			# Not moving away fast enough - thrust backwards
			# Point engines at target, thrust backwards in practice
			should_thrust = true
		else:
			should_thrust = false
	elif distance_error > tolerance:
		# Target too far - close in slowly while facing them
		desired_heading = direction_to_heading(direction_to_target)
		should_thrust = true
	else:
		# At good distance - maintain position and face target
		desired_heading = direction_to_heading(direction_to_target)

		# Only thrust if drifting away
		var velocity_toward = ship_data.velocity.dot(direction_to_target)
		should_thrust = velocity_toward < -ship_data.stats.max_speed * 0.1

	# Apply collision avoidance
	if has_collision_threat:
		if obstacle_avoidance.length() > 0.1:
			var avoid_dir = (direction_to_target + obstacle_avoidance.normalized()).normalized()
			desired_heading = direction_to_heading(avoid_dir)
		else:
			var avoid_dir = (direction_to_target + ship_avoidance.normalized()).normalized()
			desired_heading = direction_to_heading(avoid_dir)
		should_thrust = true

	return {
		"desired_heading": desired_heading,
		"thrust_active": should_thrust,
		"is_braking": is_braking,
		"engagement_range": maintain_distance,
		"current_distance": distance
	}

## Calculate fighter pilot control - specialized FighterPilotAI maneuvers
static func calculate_fighter_pilot_control(ship_data: Dictionary, target: Dictionary, nearby_ships: Array, obstacles: Array = []) -> Dictionary:
	var maneuver_subtype = ship_data.get("orders", {}).get("maneuver_subtype", "pursue")

	# Route to appropriate maneuver calculation
	match maneuver_subtype:
		"fight_pursue_full_speed":
			return calculate_pursue_full_speed(ship_data, target, nearby_ships, obstacles)
		"fight_pursue_tactical":
			return calculate_pursue_tactical(ship_data, target, nearby_ships, obstacles)
		"fight_flank_behind":
			return calculate_flank_behind(ship_data, target, nearby_ships, obstacles)
		"fight_tight_pursuit":
			return calculate_tight_pursuit(ship_data, target, nearby_ships, obstacles)
		"fight_dogfight_maneuver":
			return calculate_dogfight_maneuver(ship_data, target, nearby_ships, obstacles)
		"fight_evasive_turn":
			return calculate_evasive_turn(ship_data, target, nearby_ships, obstacles)
		"fight_defensive_break":
			return calculate_defensive_break(ship_data, target, nearby_ships, obstacles)
		"fight_lateral_break":
			return calculate_lateral_break(ship_data, target, nearby_ships, obstacles)
		"fight_group_run_approach":
			return calculate_group_run_approach(ship_data, target, nearby_ships, obstacles)
		"fight_group_run_attack":
			return calculate_group_run_attack(ship_data, target, nearby_ships, obstacles)
		"fight_group_run_swing_around":
			return calculate_group_run_swing_around(ship_data, target, nearby_ships, obstacles)
		"fight_evasive_retreat":
			return calculate_evasive_retreat(ship_data, target, nearby_ships, obstacles)
		"fight_cautious_approach":
			return calculate_cautious_approach(ship_data, target, nearby_ships, obstacles)
		"fight_dodge_and_weave":
			return calculate_dodge_and_weave(ship_data, target, nearby_ships, obstacles)
		"fight_rejoin_wingman":
			return calculate_rejoin_wingman(ship_data, target, nearby_ships, obstacles)
		"fight_wing_rejoin":
			return calculate_wing_rejoin(ship_data, target, nearby_ships, obstacles)
		"fight_wing_follow":
			return calculate_wing_follow(ship_data, target, nearby_ships, obstacles)
		"fight_wing_engage":
			return calculate_wing_engage(ship_data, target, nearby_ships, obstacles)
		_:
			# Fallback to standard pilot control
			return calculate_pilot_control(ship_data, target, nearby_ships, obstacles)

## Pursue at full speed - far away approach
static func calculate_pursue_full_speed(ship_data: Dictionary, target: Dictionary, nearby_ships: Array, obstacles: Array) -> Dictionary:
	var to_target = target.position - ship_data.position
	var desired_heading = direction_to_heading(to_target)

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
	var desired_heading = direction_to_heading(to_predicted)

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
	var desired_heading = direction_to_heading(to_behind)

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

	# Stay behind target at weapons range - not too close!
	# 400 units is far enough to maneuver but close enough to hit
	var behind_offset = Vector2(cos(target_rotation + PI), sin(target_rotation + PI)) * 400.0
	var desired_pos = target.position + behind_offset + target_velocity * 0.3

	var to_desired = desired_pos - ship_data.position
	var distance = to_desired.length()
	var desired_heading = direction_to_heading(to_desired)

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

## Dogfight maneuver - weaving at combat range
static func calculate_dogfight_maneuver(ship_data: Dictionary, target: Dictionary, nearby_ships: Array, obstacles: Array) -> Dictionary:
	var to_target = target.position - ship_data.position
	var distance = to_target.length()

	# Weave pattern at medium-close range - don't get too close!
	var perpendicular = Vector2(-to_target.y, to_target.x).normalized()
	var weave_phase = fmod(Time.get_ticks_msec() / 800.0, 2.0)
	var weave_offset = perpendicular * sin(weave_phase * PI) * 150.0  # Wider weave

	# Maintain minimum combat range - orbit at ~400 units, not right on top of target
	var range_offset = to_target.normalized() * max(0, distance - 400.0)
	var desired_pos = target.position + weave_offset - range_offset * 0.5
	var to_desired = desired_pos - ship_data.position
	var desired_heading = direction_to_heading(to_desired)

	# DART AND DASH: Very aggressive direction changes for dogfighting
	# Use tighter threshold for course correction (30 degrees instead of 45)
	var current_velocity = ship_data.get("velocity", Vector2.ZERO)
	if current_velocity.length() > 40.0:
		var current_heading = direction_to_heading(current_velocity)
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

## Evasive turn - hard turn in one direction (predictable panic evasion)
static func calculate_evasive_turn(ship_data: Dictionary, target: Dictionary, nearby_ships: Array, obstacles: Array) -> Dictionary:
	var to_target = target.position - ship_data.position
	var distance = to_target.length()

	# Hard turn away from target - 30° turn rate is predictable
	var away_from_target = -to_target.normalized()
	var perpendicular = Vector2(-to_target.y, to_target.x).normalized()

	# Always turn the same direction (predictable) - use sign of time for consistency
	var turn_direction = 1 if fmod(Time.get_ticks_msec() / 500.0, 2.0) < 1.0 else -1
	var evasion_direction = (away_from_target + perpendicular * turn_direction * 0.5).normalized()

	var desired_heading = direction_to_heading(evasion_direction)

	# Full speed evasion
	return {
		"desired_heading": desired_heading,
		"thrust_active": true,
		"is_braking": false,
		"engagement_range": 300.0,
		"current_distance": distance
	}

## Defensive break - sharp alternating turns (skilled evasion)
static func calculate_defensive_break(ship_data: Dictionary, target: Dictionary, nearby_ships: Array, obstacles: Array) -> Dictionary:
	var to_target = target.position - ship_data.position
	var distance = to_target.length()

	# Alternating sharp turns in opposite directions - unpredictable
	var perpendicular = Vector2(-to_target.y, to_target.x).normalized()

	# Switch directions frequently (every 200ms) - hard to predict
	var break_phase = fmod(Time.get_ticks_msec() / 200.0, 2.0)
	var break_direction = 1 if break_phase < 1.0 else -1

	# Move away while turning
	var away_from_target = -to_target.normalized()
	var evasion_direction = (away_from_target + perpendicular * break_direction).normalized()

	var desired_heading = direction_to_heading(evasion_direction)

	# Aggressive evasion with bursts
	var should_thrust = ship_data.velocity.length() < ship_data.stats.max_speed * 0.8

	return {
		"desired_heading": desired_heading,
		"thrust_active": should_thrust,
		"is_braking": false,
		"engagement_range": 300.0,
		"current_distance": distance
	}

## Lateral break - for head-on collision avoidance
## Uses LATERAL THRUST to slide perpendicular to LOS while maintaining facing
## Based on optimal evasion math: maximize LOS rotation rate by accelerating perpendicular to LOS
static func calculate_lateral_break(ship_data: Dictionary, target: Dictionary, nearby_ships: Array, obstacles: Array) -> Dictionary:
	var to_target = target.position - ship_data.position
	var distance = to_target.length()

	# Get committed evasion direction from orders (1 = right, -1 = left)
	var evasion_dir = ship_data.get("orders", {}).get("evasion_direction", 0)
	if evasion_dir == 0:
		# Fallback: pick based on current lateral velocity relative to LOS
		var perpendicular = Vector2(-to_target.y, to_target.x).normalized()
		var lateral_vel = ship_data.get("velocity", Vector2.ZERO).dot(perpendicular)
		evasion_dir = 1 if lateral_vel >= 0 else -1

	# KEY INSIGHT: Keep facing the target (can still shoot), but SLIDE perpendicular
	# This maximizes LOS rotation rate while maintaining offensive capability
	var desired_heading = direction_to_heading(to_target)

	# Use lateral thrust to slide perpendicular to LOS
	# This is the physics-optimal evasion: perpendicular acceleration to LOS
	var lateral_thrust = evasion_dir

	# Maintain forward speed too - don't slow down
	var should_thrust = ship_data.velocity.length() < ship_data.stats.max_speed * 0.8

	return {
		"desired_heading": desired_heading,
		"thrust_active": should_thrust,
		"is_braking": false,
		"lateral_thrust": lateral_thrust,  # NEW: slide perpendicular while facing target
		"engagement_range": 400.0,
		"current_distance": distance
	}

## Group run approach - approach with other fighters
static func calculate_group_run_approach(ship_data: Dictionary, target: Dictionary, nearby_ships: Array, obstacles: Array) -> Dictionary:
	var formation_offset = ship_data.get("orders", {}).get("formation_offset", Vector2.ZERO)
	var to_target = target.position - ship_data.position + formation_offset
	var desired_heading = direction_to_heading(to_target)

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
	var desired_heading = direction_to_heading(to_target)

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
	var desired_heading = direction_to_heading(to_swing)

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
	var desired_heading = direction_to_heading(away_from_target)

	# Add weave to dodge - quick darts side to side
	var perpendicular = Vector2(-away_from_target.y, away_from_target.x)
	var weave_phase = fmod(Time.get_ticks_msec() / 600.0, 2.0)  # Faster weaving
	var weave_offset = perpendicular * sin(weave_phase * PI) * 80.0  # Tighter weave

	var desired_pos = ship_data.position + away_from_target * 300.0 + weave_offset
	var to_desired = desired_pos - ship_data.position
	desired_heading = direction_to_heading(to_desired)

	# DART AND DASH: Sharp evasive maneuvers
	var current_velocity = ship_data.get("velocity", Vector2.ZERO)
	if current_velocity.length() > 40.0:
		var current_heading = direction_to_heading(current_velocity)
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
	var desired_heading = direction_to_heading(to_approach)

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

	# Get evasion direction from orders (1 = right, -1 = left, 0 = time-based fallback)
	var evasion_dir = ship_data.get("orders", {}).get("evasion_direction", 0)

	# Calculate perpendicular vector (right side of approach vector)
	var perpendicular = Vector2(-to_target.y, to_target.x).normalized()

	# Use deliberate evasion direction if set, otherwise fall back to time-based
	var orbit_offset: Vector2
	if evasion_dir != 0:
		# Deliberate evasion - skilled pilot picks a side and commits
		orbit_offset = perpendicular * evasion_dir * 400.0
	else:
		# Fallback to time-based oscillation (legacy behavior)
		var orbit_phase = fmod(Time.get_ticks_msec() / 1500.0, 2.0 * PI)
		orbit_offset = perpendicular * sin(orbit_phase) * 400.0

	# Weave pattern - slight in/out movement while orbiting
	var weave_phase = fmod(Time.get_ticks_msec() / 500.0, 2.0)
	var weave_offset = to_target.normalized() * sin(weave_phase * PI) * 80.0

	var desired_pos = target.position + orbit_offset + weave_offset
	var to_desired = desired_pos - ship_data.position
	var desired_heading = direction_to_heading(to_desired)

	# DART AND DASH: Quick direction changes while dodging
	var current_velocity = ship_data.get("velocity", Vector2.ZERO)
	if current_velocity.length() > 50.0:
		var current_heading = direction_to_heading(current_velocity)
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

## Rejoin wingman - return to formation position
static func calculate_rejoin_wingman(ship_data: Dictionary, target: Dictionary, nearby_ships: Array, obstacles: Array) -> Dictionary:
	# Get formation position from orders
	var formation_pos = ship_data.get("orders", {}).get("formation_position", Vector2.ZERO)

	# If no formation position specified, use target position as fallback
	if formation_pos == Vector2.ZERO:
		formation_pos = target.get("position", Vector2.ZERO)

	var my_pos = ship_data.get("position", Vector2.ZERO)
	var to_formation = formation_pos - my_pos
	var distance = to_formation.length()
	var desired_heading = direction_to_heading(to_formation)

	# Get lead's velocity to match when close
	var lead_velocity = target.get("velocity", Vector2.ZERO)

	# DART AND DASH: Brake if we need to change direction significantly
	var needs_course_correction = check_needs_braking(ship_data, desired_heading)
	if needs_course_correction and distance > 50.0:
		return create_braking_control(ship_data, desired_heading, distance)

	# Speed management based on distance
	var should_thrust: bool
	var should_brake: bool = false

	if distance > 120.0:
		# Far from formation - full speed approach
		should_thrust = true
	elif distance > 60.0:
		# Mid range - moderate speed
		var closing_speed = ship_data.velocity.dot(to_formation.normalized())
		var desired_speed = ship_data.stats.max_speed * 0.6
		should_thrust = closing_speed < desired_speed
		should_brake = closing_speed > desired_speed * 1.5
	else:
		# Close to formation position - match lead's velocity
		var speed_diff = ship_data.velocity.length() - lead_velocity.length()
		should_brake = speed_diff > 20.0
		should_thrust = speed_diff < -10.0 or distance > 40.0

		# If very close, try to match lead's heading too
		if distance < 40.0 and lead_velocity.length() > 10.0:
			desired_heading = direction_to_heading(lead_velocity)

	return {
		"desired_heading": desired_heading,
		"thrust_active": should_thrust,
		"is_braking": should_brake,
		"engagement_range": 80.0,
		"current_distance": distance
	}

# ============================================================================
# WING FORMATION MANEUVERS - Dynamic wing system
# ============================================================================

## Wing rejoin - Wingman returns to formation position with Lead
## Skill affects how tightly and quickly they rejoin
static func calculate_wing_rejoin(ship_data: Dictionary, target: Dictionary, nearby_ships: Array, obstacles: Array) -> Dictionary:
	# Get formation position from orders
	var formation_pos = ship_data.get("orders", {}).get("formation_position", Vector2.ZERO)
	var skill_factor = ship_data.get("orders", {}).get("skill_factor", 0.5)

	# If no formation position specified, calculate one based on lead position
	if formation_pos == Vector2.ZERO:
		formation_pos = _calculate_default_wing_position(target, 1, skill_factor)

	var my_pos = ship_data.get("position", Vector2.ZERO)
	var to_formation = formation_pos - my_pos
	var distance = to_formation.length()
	var desired_heading = direction_to_heading(to_formation)

	# Get lead's velocity to match when close
	var lead_velocity = target.get("velocity", Vector2.ZERO)

	# Skill affects how aggressively they course correct
	var brake_threshold = lerp(WingConstants.REJOIN_BRAKE_ANGLE_LOW_SKILL, WingConstants.REJOIN_BRAKE_ANGLE_HIGH_SKILL, skill_factor)

	# DART AND DASH: Brake if we need to change direction significantly
	var current_velocity = ship_data.get("velocity", Vector2.ZERO)
	if current_velocity.length() > 30.0:
		var current_heading = direction_to_heading(current_velocity)
		var heading_diff = abs(angle_difference(current_heading, desired_heading))
		if heading_diff > brake_threshold and distance > 50.0:
			return create_braking_control(ship_data, desired_heading, distance)

	# Speed management based on distance and skill
	var should_thrust: bool
	var should_brake: bool = false

	# High skill wingman approaches faster but brakes earlier
	var far_threshold = lerp(WingConstants.REJOIN_FAR_THRESHOLD_LOW_SKILL, WingConstants.REJOIN_FAR_THRESHOLD_HIGH_SKILL, skill_factor)
	var close_threshold = lerp(WingConstants.REJOIN_CLOSE_THRESHOLD_LOW_SKILL, WingConstants.REJOIN_CLOSE_THRESHOLD_HIGH_SKILL, skill_factor)

	if distance > far_threshold:
		# Far from formation - full speed approach
		should_thrust = true
	elif distance > close_threshold:
		# Mid range - moderate speed
		var closing_speed = current_velocity.dot(to_formation.normalized())
		var desired_speed = ship_data.stats.max_speed * lerp(0.5, 0.7, skill_factor)
		should_thrust = closing_speed < desired_speed
		should_brake = closing_speed > desired_speed * 1.5
	else:
		# Close to formation position - match lead's velocity
		var speed_diff = current_velocity.length() - lead_velocity.length()
		should_brake = speed_diff > 20.0
		should_thrust = speed_diff < -10.0 or distance > WingConstants.REJOIN_MATCH_HEADING_DISTANCE / 2.0

		# If very close, match lead's heading
		if distance < WingConstants.REJOIN_MATCH_HEADING_DISTANCE / 2.0 and lead_velocity.length() > 10.0:
			desired_heading = direction_to_heading(lead_velocity)

	return {
		"desired_heading": desired_heading,
		"thrust_active": should_thrust,
		"is_braking": should_brake,
		"engagement_range": WingConstants.REJOIN_MATCH_HEADING_DISTANCE,
		"current_distance": distance
	}

## Wing follow - Wingman maintains formation while Lead is idle/cruising
static func calculate_wing_follow(ship_data: Dictionary, target: Dictionary, nearby_ships: Array, obstacles: Array) -> Dictionary:
	var formation_pos = ship_data.get("orders", {}).get("formation_position", Vector2.ZERO)
	var skill_factor = ship_data.get("orders", {}).get("skill_factor", 0.5)
	var position_side = ship_data.get("orders", {}).get("position_side", 1)

	if formation_pos == Vector2.ZERO:
		formation_pos = _calculate_default_wing_position(target, position_side, skill_factor)

	var my_pos = ship_data.get("position", Vector2.ZERO)
	var to_formation = formation_pos - my_pos
	var distance = to_formation.length()
	var lead_velocity = target.get("velocity", Vector2.ZERO)

	# When following, primarily match lead's velocity and heading
	var desired_heading: float

	if distance > WingConstants.FOLLOW_HEAD_TOWARD_DISTANCE:
		# Too far - head toward formation position
		desired_heading = direction_to_heading(to_formation)
	elif lead_velocity.length() > 10.0:
		# Close enough - match lead's heading
		desired_heading = direction_to_heading(lead_velocity)
	else:
		# Lead is stopped/slow - face formation position
		desired_heading = direction_to_heading(to_formation) if distance > WingConstants.FOLLOW_FACE_FORMATION_DISTANCE else ship_data.get("rotation", 0.0)

	# Speed matching - stay with lead
	var my_velocity = ship_data.get("velocity", Vector2.ZERO)
	var speed_diff = my_velocity.length() - lead_velocity.length()

	var should_thrust = false
	var should_brake = false

	if distance > WingConstants.FOLLOW_TOO_FAR_DISTANCE:
		# Too far behind - speed up
		should_thrust = true
	elif distance < WingConstants.FOLLOW_TOO_CLOSE_DISTANCE and speed_diff > 20.0:
		# Too close and going faster - slow down
		should_brake = true
	else:
		# Maintain formation speed
		should_thrust = speed_diff < WingConstants.FOLLOW_SPEED_DIFF_THRUST
		should_brake = speed_diff > WingConstants.FOLLOW_SPEED_DIFF_BRAKE

	return {
		"desired_heading": desired_heading,
		"thrust_active": should_thrust,
		"is_braking": should_brake,
		"engagement_range": WingConstants.FOLLOW_HEAD_TOWARD_DISTANCE,
		"current_distance": distance
	}

## Wing engage - Wingman engages target while trying to maintain formation with Lead
## This is the most complex maneuver - balance formation keeping with attacking
static func calculate_wing_engage(ship_data: Dictionary, target: Dictionary, nearby_ships: Array, obstacles: Array) -> Dictionary:
	var formation_pos = ship_data.get("orders", {}).get("formation_position", Vector2.ZERO)
	var skill_factor = ship_data.get("orders", {}).get("skill_factor", 0.5)
	var formation_priority = ship_data.get("orders", {}).get("formation_priority", 0.5)
	var lead_ship_id = ship_data.get("orders", {}).get("lead_ship_id", "")
	var position_side = ship_data.get("orders", {}).get("position_side", 1)

	# Find lead ship for formation reference
	var lead_ship = find_ship_by_id(nearby_ships, lead_ship_id)
	if lead_ship.is_empty():
		# Lead not in nearby ships, use target as lead (fallback)
		lead_ship = target

	if formation_pos == Vector2.ZERO:
		formation_pos = _calculate_default_wing_position(lead_ship, position_side, skill_factor)

	var my_pos = ship_data.get("position", Vector2.ZERO)
	var target_pos = target.get("position", Vector2.ZERO)
	var lead_pos = lead_ship.get("position", Vector2.ZERO)

	var to_formation = formation_pos - my_pos
	var to_target = target_pos - my_pos
	var formation_distance = to_formation.length()
	var target_distance = to_target.length()

	# Blend between formation position and attack position based on:
	# 1. Formation priority (skill-based)
	# 2. Current formation distance (if too far, prioritize rejoining)
	# 3. Target distance (if close enough to shoot, can break formation slightly)

	var effective_formation_priority = formation_priority

	# If way out of formation, increase formation priority
	if formation_distance > WingConstants.ENGAGE_FORMATION_PRIORITY_INCREASE_DISTANCE:
		effective_formation_priority = min(1.0, formation_priority + 0.3)

	# If target is very close, can reduce formation priority slightly
	if target_distance < WingConstants.ENGAGE_TARGET_CLOSE_DISTANCE and formation_distance < WingConstants.ENGAGE_FORMATION_CLOSE_DISTANCE:
		effective_formation_priority = max(0.3, formation_priority - 0.2)

	# Calculate blended desired position
	# High skill/priority: Stay closer to formation
	# Low skill/priority: Chase target more independently
	var attack_offset = to_target.normalized() * min(target_distance * 0.5, WingConstants.ENGAGE_ATTACK_OFFSET_MAX)
	var blended_target = formation_pos.lerp(my_pos + attack_offset, 1.0 - effective_formation_priority)

	var to_blended = blended_target - my_pos
	var desired_heading = direction_to_heading(to_blended) if to_blended.length() > 10.0 else direction_to_heading(to_target)

	# For targeting, face the actual target when close enough
	if target_distance < WingConstants.ENGAGE_FACE_TARGET_DISTANCE and formation_distance < WingConstants.ENGAGE_FACE_TARGET_FORMATION_DISTANCE:
		desired_heading = direction_to_heading(to_target)

	# Speed control
	var lead_velocity = lead_ship.get("velocity", Vector2.ZERO)
	var my_velocity = ship_data.get("velocity", Vector2.ZERO)

	var should_thrust = true
	var should_brake = false

	# Match lead's general speed when in formation
	if formation_distance < WingConstants.ENGAGE_SPEED_MATCH_FORMATION_DISTANCE:
		var speed_diff = my_velocity.length() - lead_velocity.length()
		should_brake = speed_diff > 40.0
		should_thrust = speed_diff < 0 or target_distance > 500.0

	# DART AND DASH: Course corrections
	if my_velocity.length() > 40.0:
		var current_heading = direction_to_heading(my_velocity)
		var heading_diff = abs(angle_difference(current_heading, desired_heading))
		var brake_threshold = lerp(WingConstants.ENGAGE_BRAKE_ANGLE_LOW_SKILL, WingConstants.ENGAGE_BRAKE_ANGLE_HIGH_SKILL, skill_factor)
		if heading_diff > brake_threshold:
			return create_braking_control(ship_data, desired_heading, target_distance)

	return {
		"desired_heading": desired_heading,
		"thrust_active": should_thrust,
		"is_braking": should_brake,
		"engagement_range": WingConstants.ENGAGE_ATTACK_OFFSET_MAX,
		"current_distance": target_distance,
		"formation_distance": formation_distance
	}

## Helper: Calculate default wing position relative to lead
static func _calculate_default_wing_position(lead_ship: Dictionary, position_side: int, skill_factor: float) -> Vector2:
	var lead_pos = lead_ship.get("position", Vector2.ZERO)
	var lead_velocity = lead_ship.get("velocity", Vector2.ZERO)

	# Use velocity direction if moving, otherwise use rotation
	var lead_heading: float
	if lead_velocity.length() > 10.0:
		lead_heading = lead_velocity.angle()
	else:
		lead_heading = lead_ship.get("rotation", 0.0)

	# Position behind and to the side
	var angle_offset = deg_to_rad(WingConstants.POSITION_ANGLE) * position_side
	var formation_angle = lead_heading + PI + angle_offset

	# Distance varies by skill - high skill stays tighter
	var skill_modifier = lerp(WingConstants.POSITION_SKILL_FAR_MODIFIER, WingConstants.POSITION_SKILL_CLOSE_MODIFIER, skill_factor)
	var actual_distance = WingConstants.POSITION_DISTANCE * skill_modifier

	var formation_offset = Vector2(cos(formation_angle), sin(formation_angle)) * actual_distance

	# Predict lead's position
	var prediction_time = lerp(WingConstants.POSITION_PREDICTION_MIN, WingConstants.POSITION_PREDICTION_MAX, skill_factor)
	var predicted_lead_pos = lead_pos + lead_velocity * prediction_time

	return predicted_lead_pos + formation_offset

## DART AND DASH HELPERS - Make fighters fly with sharp movements, not sliding

## Check if ship needs to brake before changing direction
static func check_needs_braking(ship_data: Dictionary, desired_heading: float) -> bool:
	var current_velocity = ship_data.get("velocity", Vector2.ZERO)

	# If moving very slowly, no need to brake
	if current_velocity.length() < 30.0:
		return false

	# Calculate angle difference between current velocity and desired heading
	var current_heading = direction_to_heading(current_velocity)
	var heading_diff = abs(angle_difference(current_heading, desired_heading))

	# If we need to turn more than 45 degrees and we're moving fast, brake first
	if heading_diff > PI / 4.0:  # 45 degrees
		return true

	return false

## Create braking control - hard brake to prepare for direction change
static func create_braking_control(ship_data: Dictionary, desired_heading: float, distance: float) -> Dictionary:
	var current_velocity = ship_data.get("velocity", Vector2.ZERO)

	# Point opposite to current velocity for maximum braking
	var brake_heading = direction_to_heading(-current_velocity.normalized())

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
			return 600.0  # Fighters engage close for dogfighting
		"heavy_fighter":
			return 800.0  # Slightly longer range than regular fighter
		"corvette":
			return 1200.0  # Corvettes at close-medium range
		"capital":
			return 3000.0  # Capital ships engage from distance
		_:
			return 1000.0  # Default

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

	# Ship visual facing direction (where the nose points)
	var ship_facing = get_visual_forward(new_rotation)

	# Apply thrust if pilot wants to thrust
	# CRITICAL: Main thrust is ALWAYS applied in the direction the ship VISUALLY FACES
	# Engines are at the BACK of the ship, so they push the ship FORWARD
	var thrust_vector = Vector2.ZERO
	var maneuvering_direction = Vector2.ZERO

	if pilot_control.thrust_active:
		# Calculate angle between ship facing and desired visual direction
		var desired_thrust_direction = get_visual_forward(pilot_control.desired_heading)
		var thrust_angle_diff = abs(ship_facing.angle_to(desired_thrust_direction))

		# Only thrust when reasonably aligned with desired heading
		# Ships must turn to face their target before they can effectively thrust
		var acceleration_to_use: float = 0.0
		if pilot_control.get("is_braking", false):
			# BRAKING: Thrust opposite to velocity to slow down
			# Ship should be facing opposite to velocity direction
			acceleration_to_use = ship_data.stats.acceleration
		elif thrust_angle_diff < PI / 4:  # Within 45° of desired heading
			# Main engines at full power - ship is facing roughly the right way
			acceleration_to_use = ship_data.stats.acceleration
		elif thrust_angle_diff < PI / 2:  # Within 90° - partial thrust
			# Reduced thrust when not fully aligned
			acceleration_to_use = ship_data.stats.acceleration * 0.3
		# Beyond 90° - no thrust, ship needs to turn first

		# Thrust is ALWAYS in ship_facing direction (engines push from behind)
		thrust_vector = ship_facing * acceleration_to_use * delta

	# LATERAL THRUST: Maneuvering thrusters allow sliding perpendicular to facing
	# This is the key to skilled evasion - change LOS without rotating
	var lateral_thrust_dir = pilot_control.get("lateral_thrust", 0)  # -1 left, +1 right
	if lateral_thrust_dir != 0:
		# Perpendicular to ship facing (90° rotation)
		var perpendicular = Vector2(-ship_facing.y, ship_facing.x)
		# Lateral acceleration is weaker than main engines
		var lateral_accel = ship_data.stats.acceleration * ship_data.stats.get("lateral_acceleration", 0.3)
		thrust_vector += perpendicular * lateral_accel * lateral_thrust_dir * delta
		maneuvering_direction = perpendicular * lateral_thrust_dir

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
		_pilot_state = pilot_control,  # Store for debugging/visualization
		_maneuvering_thrust_direction = maneuvering_direction  # For thruster visualization
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
