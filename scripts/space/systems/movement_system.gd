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
	var collision_awareness_range = 800.0  # Pilots watch for collisions within this range (4x scaled)
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
## Uses intuitive throttle for smooth speed control
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
	var throttle: float
	var is_braking: bool = false

	if distance < min_safe_distance:
		# Too close! Back off while keeping target in arc
		desired_position = calculate_retreat_position(ship_data, target, engagement_range)
		is_braking = true
		throttle = 0.0
	elif distance > max_engagement_distance:
		# Too far, close distance - use tactical approach
		desired_position = calculate_approach_position(ship_data, target, engagement_range)
		throttle = calculate_intuitive_throttle(ship_data, distance, "pursuit_tactical")
	else:
		# At good range - maintain position and orbit/strafe with combat throttle
		desired_position = calculate_combat_orbit_position(ship_data, target, engagement_range)
		throttle = calculate_intuitive_throttle(ship_data, distance, "combat")

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
		throttle = calculate_intuitive_throttle(ship_data, distance, "evasion")
	else:
		# Point toward desired position for maneuvering
		if to_desired.length() > 10.0:
			desired_heading = direction_to_heading(to_desired)
		else:
			# At desired position, face the target
			desired_heading = direction_to_heading(to_target)

	# Check if we're going too fast toward target - use safe approach throttle
	var closing_speed = velocity_toward_target
	var safe_throttle = calculate_safe_approach_throttle(ship_data, distance, closing_speed, min_safe_distance)
	throttle = min(throttle, safe_throttle)

	if closing_speed > ship_data.stats.max_speed * 0.4 and distance < engagement_range:
		is_braking = true
		throttle = 0.0
		if ship_data.velocity.length() > 10.0:
			desired_heading = direction_to_heading(-ship_data.velocity.normalized())

	return {
		"desired_heading": desired_heading,
		"throttle": throttle,
		"thrust_active": throttle > 0.1,
		"is_braking": is_braking,
		"engagement_range": engagement_range,
		"current_distance": distance
	}

## Calculate evasion control - retreat from threat
## Uses full throttle for fleeing since this is an escape situation
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
	var throttle: float
	var is_braking: bool = false

	if distance < safe_distance:
		# Too close! Retreat at full speed - this is fleeing
		var retreat_direction = direction_from_threat

		# Apply avoidance if needed
		if has_collision_threat:
			if obstacle_avoidance.length() > 0.1:
				retreat_direction = (retreat_direction + obstacle_avoidance.normalized()).normalized()
			else:
				retreat_direction = (retreat_direction + ship_avoidance.normalized()).normalized()

		desired_heading = direction_to_heading(retreat_direction)
		throttle = calculate_intuitive_throttle(ship_data, distance, "fleeing")
	else:
		# At safe distance - maintain position with evasive drift
		var drift_position = ship_data.position + direction_from_threat * safe_distance
		var to_drift = drift_position - ship_data.position

		if to_drift.length() > 10.0:
			desired_heading = direction_to_heading(to_drift)
			throttle = calculate_intuitive_throttle(ship_data, distance, "evasion")
		else:
			# At good position, face away from threat
			desired_heading = direction_to_heading(direction_from_threat)
			throttle = 0.1  # Minimal throttle to maintain position

	return {
		"desired_heading": desired_heading,
		"throttle": throttle,
		"thrust_active": throttle > 0.1,
		"is_braking": is_braking,
		"engagement_range": safe_distance,
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
	var distance = to_target.length()
	var desired_heading = direction_to_heading(to_target)

	# DART AND DASH: Check if we need to brake and change direction
	var needs_course_correction = check_needs_braking(ship_data, desired_heading)

	if needs_course_correction:
		# Brake hard, then we'll dart in the new direction
		return create_braking_control(ship_data, desired_heading, distance)

	# Calculate intuitive throttle - even "full speed" pursuit uses physics-based throttle
	var throttle = calculate_intuitive_throttle(ship_data, distance, "pursuit_full")

	return {
		"desired_heading": desired_heading,
		"throttle": throttle,
		"thrust_active": throttle > 0.1,
		"is_braking": false,
		"engagement_range": 250.0,
		"current_distance": distance
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

	# Calculate intuitive throttle for tactical approach
	var closing_speed = ship_data.velocity.dot(direction)
	var context_throttle = calculate_intuitive_throttle(ship_data, distance, "pursuit_tactical")
	var safe_throttle = calculate_safe_approach_throttle(ship_data, distance, closing_speed, 1600.0)

	# Use the more conservative throttle
	var throttle = min(context_throttle, safe_throttle)
	var should_brake = closing_speed > ship_data.stats.max_speed * 0.4

	return {
		"desired_heading": desired_heading,
		"throttle": throttle if not should_brake else 0.0,
		"thrust_active": throttle > 0.1 and not should_brake,
		"is_braking": should_brake,
		"engagement_range": 250.0,
		"current_distance": distance
	}

## Flank behind - try to get behind target
## Ship faces target (can still shoot), uses lateral thrust to slide into position
static func calculate_flank_behind(ship_data: Dictionary, target: Dictionary, nearby_ships: Array, obstacles: Array) -> Dictionary:
	var behind_position = ship_data.get("orders", {}).get("behind_position", Vector2.ZERO)
	if behind_position == Vector2.ZERO:
		# Calculate behind position - further back for safety (4x scaled)
		var target_rotation = target.get("rotation", 0.0)
		var behind_offset = Vector2(cos(target_rotation + PI), sin(target_rotation + PI)) * 1600.0
		behind_position = target.position + behind_offset

	var to_target = target.position - ship_data.position
	var to_behind = behind_position - ship_data.position
	var distance_to_target = to_target.length()

	# Face the target - maintain offensive capability while repositioning
	var desired_heading = direction_to_heading(to_target)

	# Calculate lateral thrust to slide toward the behind position
	var perpendicular = Vector2(-to_target.y, to_target.x).normalized()
	var lateral_offset = to_behind.dot(perpendicular)
	var lateral_thrust = clamp(lateral_offset / 400.0, -1.0, 1.0)

	# Main thrust controls distance to target only
	var desired_flank_distance = 1600.0
	var distance_error = distance_to_target - desired_flank_distance
	var throttle = 0.0
	var should_brake = false

	if distance_error > 400.0:
		# Too far from target - close in
		throttle = 0.3
	elif distance_error < -400.0:
		# Too close to target - back off
		should_brake = true

	# Brake if going too fast
	var current_velocity = ship_data.get("velocity", Vector2.ZERO)
	var current_speed = current_velocity.length()
	var max_flank_speed = ship_data.stats.max_speed * 0.5
	if current_speed > max_flank_speed:
		should_brake = true
		throttle = 0.0

	return {
		"desired_heading": desired_heading,
		"throttle": throttle,
		"thrust_active": throttle > 0.1,
		"is_braking": should_brake,
		"lateral_thrust": lateral_thrust,
		"engagement_range": 250.0,
		"current_distance": distance_to_target
	}

## Tight pursuit - close range, stay behind
## Uses lateral thrust (maneuvering jets) to make fine aim adjustments
static func calculate_tight_pursuit(ship_data: Dictionary, target: Dictionary, nearby_ships: Array, obstacles: Array) -> Dictionary:
	var target_rotation = target.get("rotation", 0.0)
	var target_velocity = target.get("velocity", Vector2.ZERO)

	# Stay behind target at weapons range - not too close!
	# 2000 units is far enough to maneuver but close enough to hit (4x scaled)
	var behind_offset = Vector2(cos(target_rotation + PI), sin(target_rotation + PI)) * 2000.0
	var desired_pos = target.position + behind_offset + target_velocity * 0.3

	var to_desired = desired_pos - ship_data.position
	var distance = to_desired.length()
	var to_target = target.position - ship_data.position

	# Face the target for aiming
	var desired_heading = direction_to_heading(to_target)

	# Calculate lateral thrust to slide toward the desired position
	# This allows fine aim adjustment while facing target
	var perpendicular = Vector2(-to_target.y, to_target.x).normalized()
	var lateral_offset = to_desired.dot(perpendicular)
	var lateral_thrust = clamp(lateral_offset / 200.0, -1.0, 1.0)  # Proportional control

	# DART AND DASH: Quick corrections to stay on target's tail
	var current_velocity = ship_data.get("velocity", Vector2.ZERO)
	var needs_course_correction = check_needs_braking(ship_data, desired_heading)
	if needs_course_correction and distance > 500.0:
		return create_braking_control(ship_data, desired_heading, distance)

	# Use combat throttle - slow and precise
	var throttle = calculate_intuitive_throttle(ship_data, distance, "combat")

	# Match target speed - brake if too fast
	var speed_diff = current_velocity.length() - target_velocity.length()
	var should_brake = speed_diff > 20.0

	# Reduce throttle if already at or above target speed
	if speed_diff > 0:
		throttle = throttle * 0.3

	return {
		"desired_heading": desired_heading,
		"throttle": throttle if not should_brake else 0.0,
		"thrust_active": throttle > 0.1 and not should_brake,
		"is_braking": should_brake,
		"lateral_thrust": lateral_thrust,  # Maneuvering jets for aim adjustment
		"engagement_range": 480.0,
		"current_distance": distance
	}

## Dogfight maneuver - weaving at combat range
## Ship ALWAYS faces target for aiming
## Main thrust = distance control only (close in / back off)
## Lateral thrust = all positioning (strafing while aiming)
static func calculate_dogfight_maneuver(ship_data: Dictionary, target: Dictionary, nearby_ships: Array, obstacles: Array) -> Dictionary:
	var to_target = target.position - ship_data.position
	var distance = to_target.length()
	var direction_to_target = to_target.normalized()

	# ALWAYS face the target for aiming
	var desired_heading = direction_to_heading(to_target)

	# Perpendicular to line of sight - for lateral movement
	var perpendicular = Vector2(-to_target.y, to_target.x).normalized()

	# Weave using lateral thrust - strafe left/right while facing target
	var weave_phase = fmod(Time.get_ticks_msec() / 800.0, 2.0)
	var lateral_thrust = sin(weave_phase * PI)  # -1 to 1, oscillating strafe

	# Desired combat range
	var desired_combat_range = 2400.0
	var distance_error = distance - desired_combat_range

	# Main thrust is ONLY for distance control along line of sight
	# Positive throttle = close in (we're facing target, so forward = toward)
	# Braking = back off
	var throttle = 0.0
	var should_brake = false

	if distance_error > 800.0:
		# Too far - close in slowly
		throttle = 0.2
	elif distance_error < -800.0:
		# Too close - back off (brake, we're facing them)
		should_brake = true
	# Otherwise at good range - no forward thrust, just strafe

	# Also brake if going too fast
	var current_velocity = ship_data.get("velocity", Vector2.ZERO)
	var current_speed = current_velocity.length()
	var max_combat_speed = ship_data.stats.max_speed * 0.35
	if current_speed > max_combat_speed:
		should_brake = true
		throttle = 0.0

	return {
		"desired_heading": desired_heading,
		"throttle": throttle,
		"thrust_active": throttle > 0.1,
		"is_braking": should_brake,
		"lateral_thrust": lateral_thrust,  # Maneuvering jets for ALL positioning
		"engagement_range": 600.0,
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

	# Full throttle for evasion - this is fleeing
	var throttle = calculate_intuitive_throttle(ship_data, distance, "fleeing")

	return {
		"desired_heading": desired_heading,
		"throttle": throttle,
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

	# Evasion uses controlled bursts - not full speed (allows for direction changes)
	var throttle = calculate_intuitive_throttle(ship_data, distance, "evasion")

	return {
		"desired_heading": desired_heading,
		"throttle": throttle,
		"thrust_active": throttle > 0.1,
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

	# Use evasion throttle - controlled speed for maneuvering
	var throttle = calculate_intuitive_throttle(ship_data, distance, "evasion")

	return {
		"desired_heading": desired_heading,
		"throttle": throttle,
		"thrust_active": throttle > 0.1,
		"is_braking": false,
		"lateral_thrust": lateral_thrust,  # slide perpendicular while facing target
		"engagement_range": 400.0,
		"current_distance": distance
	}

## Group run approach - approach with other fighters
## Ship faces target, uses lateral thrust to maintain formation offset
static func calculate_group_run_approach(ship_data: Dictionary, target: Dictionary, nearby_ships: Array, obstacles: Array) -> Dictionary:
	var formation_offset = ship_data.get("orders", {}).get("formation_offset", Vector2.ZERO)
	var to_target = target.position - ship_data.position
	var distance = to_target.length()

	# Face the target - coordinated attack run
	var desired_heading = direction_to_heading(to_target)

	# Use lateral thrust to maintain formation offset while approaching
	var perpendicular = Vector2(-to_target.y, to_target.x).normalized()
	var lateral_offset = formation_offset.dot(perpendicular)
	var lateral_thrust = clamp(lateral_offset / 200.0, -1.0, 1.0)

	# Main thrust for distance control - approach the target
	var desired_approach_distance = 2000.0
	var distance_error = distance - desired_approach_distance
	var throttle = 0.0
	var should_brake = false

	if distance_error > 500.0:
		# Far away - close in at tactical speed
		throttle = calculate_intuitive_throttle(ship_data, distance, "pursuit_tactical")
	elif distance_error > 0:
		# Getting close - slow approach
		throttle = 0.3
	else:
		# At range or too close - hold position
		should_brake = distance_error < -300.0

	# Brake if going too fast
	var current_velocity = ship_data.get("velocity", Vector2.ZERO)
	var current_speed = current_velocity.length()
	var max_approach_speed = ship_data.stats.max_speed * 0.5
	if current_speed > max_approach_speed:
		should_brake = true
		throttle = 0.0

	return {
		"desired_heading": desired_heading,
		"throttle": throttle,
		"thrust_active": throttle > 0.1,
		"is_braking": should_brake,
		"lateral_thrust": lateral_thrust,
		"engagement_range": 400.0,
		"current_distance": distance
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

	# Attack run uses tactical throttle - controlled approach, not kamikaze
	var throttle = calculate_intuitive_throttle(ship_data, distance, "pursuit_tactical")

	# Reduce throttle when very close to avoid collision (4x scaled)
	if distance < 1600.0:
		throttle = throttle * 0.5

	return {
		"desired_heading": desired_heading,
		"throttle": throttle,
		"thrust_active": throttle > 0.1,
		"is_braking": false,
		"engagement_range": 300.0,
		"current_distance": distance
	}

## Group run swing around - swing around for another pass
## Ship faces target (keeps it in view), uses lateral thrust to swing out to the side
static func calculate_group_run_swing_around(ship_data: Dictionary, target: Dictionary, nearby_ships: Array, obstacles: Array) -> Dictionary:
	var to_target = target.position - ship_data.position
	var distance = to_target.length()

	# Face the target - keep it in view while repositioning
	var desired_heading = direction_to_heading(to_target)

	# Swing out to the side - use lateral thrust to slide perpendicular
	var perpendicular = Vector2(-to_target.y, to_target.x).normalized()
	var swing_out_pos = target.position + perpendicular * 4000.0
	var to_swing = swing_out_pos - ship_data.position

	# Calculate lateral thrust to slide toward swing position
	var lateral_offset = to_swing.dot(perpendicular)
	var lateral_thrust = clamp(lateral_offset / 600.0, -1.0, 1.0)

	# Main thrust controls distance - back off to safe repositioning distance
	var desired_swing_distance = 3000.0
	var distance_error = distance - desired_swing_distance
	var throttle = 0.0
	var should_brake = false

	if distance_error < -500.0:
		# Too close - back off (we're facing target, so brake)
		should_brake = true
	elif distance_error > 500.0:
		# Too far - close in slightly
		throttle = 0.2

	# Brake if going too fast
	var current_velocity = ship_data.get("velocity", Vector2.ZERO)
	var current_speed = current_velocity.length()
	var max_swing_speed = ship_data.stats.max_speed * 0.5
	if current_speed > max_swing_speed:
		should_brake = true
		throttle = 0.0

	return {
		"desired_heading": desired_heading,
		"throttle": throttle,
		"thrust_active": throttle > 0.1,
		"is_braking": should_brake,
		"lateral_thrust": lateral_thrust,
		"engagement_range": 500.0,
		"current_distance": distance
	}

## Evasive retreat - get away from big ship
static func calculate_evasive_retreat(ship_data: Dictionary, target: Dictionary, nearby_ships: Array, obstacles: Array) -> Dictionary:
	var distance = ship_data.position.distance_to(target.position)
	var away_from_target = (ship_data.position - target.position).normalized()
	var desired_heading = direction_to_heading(away_from_target)

	# Add weave to dodge - quick darts side to side (4x scaled)
	var perpendicular = Vector2(-away_from_target.y, away_from_target.x)
	var weave_phase = fmod(Time.get_ticks_msec() / 600.0, 2.0)  # Faster weaving
	var weave_offset = perpendicular * sin(weave_phase * PI) * 600.0  # Wider weave for safety

	var desired_pos = ship_data.position + away_from_target * 2000.0 + weave_offset
	var to_desired = desired_pos - ship_data.position
	desired_heading = direction_to_heading(to_desired)

	# DART AND DASH: Sharp evasive maneuvers
	var current_velocity = ship_data.get("velocity", Vector2.ZERO)
	if current_velocity.length() > 40.0:
		var current_heading = direction_to_heading(current_velocity)
		var heading_diff = abs(angle_difference(current_heading, desired_heading))
		if heading_diff > PI / 5.0:  # 36 degrees - quick evasion threshold
			return create_braking_control(ship_data, desired_heading, to_desired.length())

	# Full throttle for retreat - this is fleeing
	var throttle = calculate_intuitive_throttle(ship_data, distance, "retreat")

	return {
		"desired_heading": desired_heading,
		"throttle": throttle,
		"thrust_active": true,
		"is_braking": false,
		"engagement_range": 500.0,
		"current_distance": distance
	}

## Cautious approach - close in slowly at an angle
## Ship faces target (can still shoot), uses lateral thrust to approach at an angle
static func calculate_cautious_approach(ship_data: Dictionary, target: Dictionary, nearby_ships: Array, obstacles: Array) -> Dictionary:
	var to_target = target.position - ship_data.position
	var distance = to_target.length()
	var direction = to_target.normalized()

	# Face the target - maintain offensive capability
	var desired_heading = direction_to_heading(to_target)

	# Use lateral thrust to approach at an angle (not directly)
	# Slide to one side while closing distance
	var perpendicular = Vector2(-to_target.y, to_target.x).normalized()
	var approach_offset = perpendicular * 1600.0
	var to_approach = (target.position + approach_offset) - ship_data.position
	var lateral_offset = to_approach.dot(perpendicular)
	var lateral_thrust = clamp(lateral_offset / 400.0, -1.0, 1.0)

	# Main thrust controls distance - slow cautious approach
	var desired_approach_distance = 2000.0
	var distance_error = distance - desired_approach_distance
	var throttle = 0.0
	var should_brake = false

	if distance_error > 600.0:
		# Far away - close in slowly
		var closing_speed = ship_data.velocity.dot(direction)
		var context_throttle = calculate_intuitive_throttle(ship_data, distance, "pursuit_tactical")
		var safe_throttle = calculate_safe_approach_throttle(ship_data, distance, closing_speed, 2000.0)
		throttle = min(context_throttle, safe_throttle) * 0.5  # Extra cautious
	elif distance_error > 0:
		# Getting close - very slow
		throttle = 0.15
	else:
		# At range or too close
		should_brake = distance_error < -300.0

	# Brake if going too fast
	var current_velocity = ship_data.get("velocity", Vector2.ZERO)
	var current_speed = current_velocity.length()
	var max_cautious_speed = ship_data.stats.max_speed * 0.35
	if current_speed > max_cautious_speed:
		should_brake = true
		throttle = 0.0

	return {
		"desired_heading": desired_heading,
		"throttle": throttle,
		"thrust_active": throttle > 0.1,
		"is_braking": should_brake,
		"lateral_thrust": lateral_thrust,
		"engagement_range": 400.0,
		"current_distance": distance
	}

## Dodge and weave - stay at range, dodge
## Ship ALWAYS faces target for aiming
## Main thrust = distance control only (close in / back off)
## Lateral thrust = all positioning (strafing while aiming)
static func calculate_dodge_and_weave(ship_data: Dictionary, target: Dictionary, nearby_ships: Array, obstacles: Array) -> Dictionary:
	var to_target = target.position - ship_data.position
	var distance = to_target.length()

	# ALWAYS face the target for aiming
	var desired_heading = direction_to_heading(to_target)

	# Get evasion direction from orders (1 = right, -1 = left, 0 = time-based fallback)
	var evasion_dir = ship_data.get("orders", {}).get("evasion_direction", 0)

	# Lateral thrust for strafing - ALL positioning done here
	var lateral_thrust: float
	if evasion_dir != 0:
		# Deliberate evasion - skilled pilot picks a side and commits
		lateral_thrust = float(evasion_dir)
	else:
		# Fallback to time-based oscillation
		var orbit_phase = fmod(Time.get_ticks_msec() / 1500.0, 2.0 * PI)
		lateral_thrust = sin(orbit_phase)

	# Desired combat range
	var desired_combat_range = 2400.0
	var distance_error = distance - desired_combat_range

	# Main thrust is ONLY for distance control along line of sight
	var throttle = 0.0
	var should_brake = false
	var current_velocity = ship_data.get("velocity", Vector2.ZERO)

	if distance_error > 600.0:
		# Too far - close in slowly
		throttle = 0.2
	elif distance_error < -600.0:
		# Too close - back off
		should_brake = true
	# Otherwise at good range - no forward thrust, just strafe

	# Brake if going too fast
	var current_speed = current_velocity.length()
	var max_dodge_speed = ship_data.stats.max_speed * 0.35
	if current_speed > max_dodge_speed:
		should_brake = true
		throttle = 0.0

	return {
		"desired_heading": desired_heading,
		"throttle": throttle,
		"thrust_active": throttle > 0.1,
		"is_braking": should_brake,
		"lateral_thrust": lateral_thrust,  # Maneuvering jets for ALL positioning
		"engagement_range": 1600.0,
		"current_distance": distance
	}

## Rejoin wingman - return to formation position
## Ship faces lead's direction of travel, uses lateral thrust to slide into formation
static func calculate_rejoin_wingman(ship_data: Dictionary, target: Dictionary, nearby_ships: Array, obstacles: Array) -> Dictionary:
	# Get formation position from orders
	var formation_pos = ship_data.get("orders", {}).get("formation_position", Vector2.ZERO)

	# If no formation position specified, use target position as fallback
	if formation_pos == Vector2.ZERO:
		formation_pos = target.get("position", Vector2.ZERO)

	var my_pos = ship_data.get("position", Vector2.ZERO)
	var to_formation = formation_pos - my_pos
	var distance = to_formation.length()

	# Get lead's velocity to match heading
	var lead_velocity = target.get("velocity", Vector2.ZERO)

	# Face the same direction as lead (or toward lead if lead is stationary)
	var desired_heading: float
	if lead_velocity.length() > 10.0:
		desired_heading = direction_to_heading(lead_velocity)
	else:
		var to_lead = target.get("position", Vector2.ZERO) - my_pos
		desired_heading = direction_to_heading(to_lead)

	# Calculate lateral thrust to slide into formation position
	var forward_dir = get_visual_forward(desired_heading)
	var perpendicular = Vector2(-forward_dir.y, forward_dir.x)
	var lateral_offset = to_formation.dot(perpendicular)
	var lateral_thrust = clamp(lateral_offset / 150.0, -1.0, 1.0)

	# Main thrust controls forward/back relative to formation position
	var forward_offset = to_formation.dot(forward_dir)
	var throttle = 0.0
	var should_brake = false

	if distance > 200.0:
		# Far from formation - close in
		if forward_offset > 100.0:
			throttle = calculate_intuitive_throttle(ship_data, distance, "pursuit_tactical")
		elif forward_offset < -100.0:
			should_brake = true
	elif distance > 80.0:
		# Mid range - controlled approach
		if forward_offset > 50.0:
			throttle = 0.3
		elif forward_offset < -50.0:
			should_brake = true
	else:
		# Close to formation - match lead's velocity
		var speed_diff = ship_data.velocity.length() - lead_velocity.length()
		should_brake = speed_diff > 15.0
		throttle = 0.15 if forward_offset > 20.0 else 0.0

	# Brake if going too fast
	var current_velocity = ship_data.get("velocity", Vector2.ZERO)
	var current_speed = current_velocity.length()
	var lead_speed = lead_velocity.length()
	if current_speed > lead_speed + 30.0:
		should_brake = true
		throttle = 0.0

	return {
		"desired_heading": desired_heading,
		"throttle": throttle if not should_brake else 0.0,
		"thrust_active": throttle > 0.1 and not should_brake,
		"is_braking": should_brake,
		"lateral_thrust": lateral_thrust,
		"engagement_range": 80.0,
		"current_distance": distance
	}

# ============================================================================
# WING FORMATION MANEUVERS - Dynamic wing system
# ============================================================================

## Wing rejoin - Wingman returns to formation position with Lead
## Ship faces lead's direction, uses lateral thrust to slide into formation
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

	# Get lead's velocity to match heading
	var lead_velocity = target.get("velocity", Vector2.ZERO)
	var current_velocity = ship_data.get("velocity", Vector2.ZERO)

	# Face the same direction as lead (or toward lead if lead is stationary)
	var desired_heading: float
	if lead_velocity.length() > 10.0:
		desired_heading = direction_to_heading(lead_velocity)
	else:
		var to_lead = target.get("position", Vector2.ZERO) - my_pos
		desired_heading = direction_to_heading(to_lead)

	# Calculate lateral thrust to slide into formation position
	var forward_dir = get_visual_forward(desired_heading)
	var perpendicular = Vector2(-forward_dir.y, forward_dir.x)
	var lateral_offset = to_formation.dot(perpendicular)
	# Skill affects responsiveness - high skill uses tighter control
	var lateral_divisor = lerp(250.0, 100.0, skill_factor)
	var lateral_thrust = clamp(lateral_offset / lateral_divisor, -1.0, 1.0)

	# Main thrust controls forward/back relative to formation position
	var forward_offset = to_formation.dot(forward_dir)
	var throttle = 0.0
	var should_brake = false

	# High skill wingman approaches faster but more precisely
	var far_threshold = lerp(WingConstants.REJOIN_FAR_THRESHOLD_LOW_SKILL, WingConstants.REJOIN_FAR_THRESHOLD_HIGH_SKILL, skill_factor)
	var close_threshold = lerp(WingConstants.REJOIN_CLOSE_THRESHOLD_LOW_SKILL, WingConstants.REJOIN_CLOSE_THRESHOLD_HIGH_SKILL, skill_factor)

	if distance > far_threshold:
		# Far from formation - close in based on forward offset
		if forward_offset > 100.0:
			throttle = calculate_intuitive_throttle(ship_data, distance, "pursuit_tactical")
		elif forward_offset < -100.0:
			should_brake = true
	elif distance > close_threshold:
		# Mid range - controlled approach
		if forward_offset > 50.0:
			throttle = 0.3
		elif forward_offset < -50.0:
			should_brake = true
	else:
		# Close to formation position - match lead's velocity
		var speed_diff = current_velocity.length() - lead_velocity.length()
		should_brake = speed_diff > 15.0
		throttle = 0.15 if forward_offset > 20.0 else 0.0

	# Brake if going too fast relative to lead
	var lead_speed = lead_velocity.length()
	if current_velocity.length() > lead_speed + 30.0:
		should_brake = true
		throttle = 0.0

	return {
		"desired_heading": desired_heading,
		"throttle": throttle if not should_brake else 0.0,
		"thrust_active": throttle > 0.1 and not should_brake,
		"is_braking": should_brake,
		"lateral_thrust": lateral_thrust,
		"engagement_range": WingConstants.REJOIN_MATCH_HEADING_DISTANCE,
		"current_distance": distance
	}

## Wing follow - Wingman maintains formation while Lead is idle/cruising
## Ship matches lead's heading, uses lateral thrust to maintain formation position
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
	var my_velocity = ship_data.get("velocity", Vector2.ZERO)

	# Match lead's heading (or face lead if stationary)
	var desired_heading: float
	if lead_velocity.length() > 10.0:
		desired_heading = direction_to_heading(lead_velocity)
	else:
		var to_lead = target.get("position", Vector2.ZERO) - my_pos
		if to_lead.length() > WingConstants.FOLLOW_FACE_FORMATION_DISTANCE:
			desired_heading = direction_to_heading(to_lead)
		else:
			desired_heading = ship_data.get("rotation", 0.0)

	# Calculate lateral thrust to maintain formation position
	var forward_dir = get_visual_forward(desired_heading)
	var perpendicular = Vector2(-forward_dir.y, forward_dir.x)
	var lateral_offset = to_formation.dot(perpendicular)
	var lateral_divisor = lerp(200.0, 100.0, skill_factor)
	var lateral_thrust = clamp(lateral_offset / lateral_divisor, -1.0, 1.0)

	# Main thrust controls forward/back position in formation
	var forward_offset = to_formation.dot(forward_dir)
	var speed_diff = my_velocity.length() - lead_velocity.length()
	var throttle = 0.0
	var should_brake = false

	if distance > WingConstants.FOLLOW_TOO_FAR_DISTANCE:
		# Too far behind - close in
		if forward_offset > 50.0:
			throttle = calculate_intuitive_throttle(ship_data, distance, "pursuit_tactical")
		elif forward_offset < -50.0:
			should_brake = true
	elif distance < WingConstants.FOLLOW_TOO_CLOSE_DISTANCE and speed_diff > 15.0:
		# Too close and going faster - slow down
		should_brake = true
	else:
		# Maintain formation speed
		if forward_offset > 30.0 and speed_diff < 10.0:
			throttle = 0.2
		elif speed_diff > WingConstants.FOLLOW_SPEED_DIFF_BRAKE:
			should_brake = true
		else:
			throttle = 0.1  # Cruise throttle

	return {
		"desired_heading": desired_heading,
		"throttle": throttle,
		"thrust_active": throttle > 0.1,
		"is_braking": should_brake,
		"lateral_thrust": lateral_thrust,
		"engagement_range": WingConstants.FOLLOW_HEAD_TOWARD_DISTANCE,
		"current_distance": distance
	}

## Wing engage - Wingman engages target while trying to maintain formation with Lead
## Ship faces target (for aiming), uses lateral thrust to maintain formation position
## This balances formation keeping with attacking
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

	var to_formation = formation_pos - my_pos
	var to_target = target_pos - my_pos
	var formation_distance = to_formation.length()
	var target_distance = to_target.length()

	# ALWAYS face the target for aiming - this is combat
	var desired_heading = direction_to_heading(to_target)

	# Calculate effective formation priority
	var effective_formation_priority = formation_priority

	# If way out of formation, increase formation priority
	if formation_distance > WingConstants.ENGAGE_FORMATION_PRIORITY_INCREASE_DISTANCE:
		effective_formation_priority = min(1.0, formation_priority + 0.3)

	# If target is very close, can reduce formation priority slightly
	if target_distance < WingConstants.ENGAGE_TARGET_CLOSE_DISTANCE and formation_distance < WingConstants.ENGAGE_FORMATION_CLOSE_DISTANCE:
		effective_formation_priority = max(0.3, formation_priority - 0.2)

	# Use lateral thrust to maintain formation position while facing target
	var perpendicular = Vector2(-to_target.y, to_target.x).normalized()
	var lateral_offset = to_formation.dot(perpendicular)
	# Scale lateral thrust by formation priority - high priority = stronger formation pull
	var lateral_divisor = lerp(400.0, 150.0, effective_formation_priority)
	var lateral_thrust = clamp(lateral_offset / lateral_divisor, -1.0, 1.0)

	# Main thrust controls distance to target
	var lead_velocity = lead_ship.get("velocity", Vector2.ZERO)
	var my_velocity = ship_data.get("velocity", Vector2.ZERO)

	# Desired combat range
	var desired_combat_range = 2400.0
	var distance_error = target_distance - desired_combat_range
	var throttle = 0.0
	var should_brake = false

	if distance_error > 600.0:
		# Too far - close in
		throttle = calculate_intuitive_throttle(ship_data, target_distance, "combat")
	elif distance_error < -600.0:
		# Too close - back off
		should_brake = true

	# Match lead's general speed when in formation
	if formation_distance < WingConstants.ENGAGE_SPEED_MATCH_FORMATION_DISTANCE:
		var speed_diff = my_velocity.length() - lead_velocity.length()
		if speed_diff > 30.0:
			should_brake = true
			throttle = 0.0

	# Brake if going too fast
	var current_speed = my_velocity.length()
	var max_combat_speed = ship_data.stats.max_speed * 0.4
	if current_speed > max_combat_speed:
		should_brake = true
		throttle = 0.0

	return {
		"desired_heading": desired_heading,
		"throttle": throttle,
		"thrust_active": throttle > 0.1,
		"is_braking": should_brake,
		"lateral_thrust": lateral_thrust,
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
## NOTE: All distances scaled 4-5x for proper combat spacing
static func get_engagement_range(ship_data: Dictionary) -> float:
	match ship_data.type:
		"fighter":
			return 2400.0  # Fighters engage at weapons range, not point-blank (4x scaled)
		"heavy_fighter":
			return 2800.0  # Slightly longer range than regular fighter (4x scaled)
		"corvette":
			return 7000.0  # Corvettes at medium range (2x scaled, already larger)
		"capital":
			return 10000.0  # Capital ships engage from far away
		_:
			return 4000.0  # Default (4x scaled)

## Calculate collision avoidance vector from nearby ships
static func calculate_collision_avoidance(ship_data: Dictionary, nearby_ships: Array) -> Vector2:
	if nearby_ships.is_empty():
		return Vector2.ZERO

	var avoidance = Vector2.ZERO
	for other_ship in nearby_ships:
		var to_other = other_ship.position - ship_data.position
		var distance = to_other.length()

		# Stronger avoidance the closer they are
		var danger_distance = 600.0  # 4x scaled for proper spacing
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
# INTUITIVE THROTTLE CALCULATION
# ============================================================================
# Combat default: slow, precise movement for aiming
# Pursuit/closing: moderate throttle, increasing with distance
# Fleeing/retreat: full throttle to escape
# Key principle: Fighters should almost never go full speed unless fleeing

## Calculate intuitive throttle based on distance and context
## Returns 0.0-1.0 throttle value
## NOTE: All distances scaled 4-5x for proper combat spacing
static func calculate_intuitive_throttle(
	ship_data: Dictionary,
	distance_to_target: float,
	maneuver_context: String = "combat"
) -> float:
	var max_speed = ship_data.stats.max_speed
	var current_speed = ship_data.velocity.length()

	# Context-based throttle profiles
	# Distance constants scaled 4-5x from original for proper combat spacing
	match maneuver_context:
		"fleeing", "retreat", "escape":
			# Full throttle when running away
			return 1.0

		"pursuit_full":
			# Far away pursuit - scale with distance
			# At FAR_RANGE (20000+): full throttle
			# At MID_RANGE (6000): 60% throttle
			# Closer: taper down
			var far_range = 20000.0
			var mid_range = 6000.0
			if distance_to_target > far_range:
				return 1.0
			elif distance_to_target > mid_range:
				return lerp(0.6, 1.0, (distance_to_target - mid_range) / (far_range - mid_range))
			else:
				return lerp(0.3, 0.6, distance_to_target / mid_range)

		"pursuit_tactical":
			# Tactical approach - always controlled
			# Never exceed 50% throttle, scale with distance
			var mid_range = 6000.0
			var close_range = 3200.0
			if distance_to_target > mid_range:
				return 0.5
			elif distance_to_target > close_range:
				return lerp(0.3, 0.5, (distance_to_target - close_range) / (mid_range - close_range))
			else:
				return lerp(0.15, 0.3, distance_to_target / close_range)

		"combat", "dogfight":
			# Combat maneuvering - slow and precise
			# Max 40% throttle, usually much less
			var close_range = 3200.0
			var min_range = 1200.0
			if distance_to_target > close_range:
				return 0.4
			elif distance_to_target > min_range:
				return lerp(0.2, 0.4, (distance_to_target - min_range) / (close_range - min_range))
			else:
				# Very close - almost no throttle, rely on momentum
				return lerp(0.1, 0.2, distance_to_target / min_range)

		"flanking":
			# Flanking maneuver - moderate speed for positioning
			var mid_range = 6000.0
			if distance_to_target > mid_range:
				return 0.6
			else:
				return lerp(0.3, 0.6, distance_to_target / mid_range)

		"formation":
			# Formation flying - match speed, low throttle
			return 0.3

		"evasion":
			# Evasive maneuvers - bursts of speed, but controlled
			return 0.6

		_:
			# Default: conservative combat throttle
			var mid_range = 6000.0
			if distance_to_target > mid_range:
				return 0.5
			else:
				return lerp(0.25, 0.5, distance_to_target / mid_range)

## Calculate safe approach throttle that prevents overshooting
## Physics-based: considers stopping distance at current speed
static func calculate_safe_approach_throttle(
	ship_data: Dictionary,
	distance_to_target: float,
	closing_speed: float,
	desired_stop_distance: float = 1200.0
) -> float:
	var max_speed = ship_data.stats.max_speed
	var acceleration = ship_data.stats.acceleration

	# Calculate stopping distance at current closing speed
	# d = v² / (2 * a)  - basic kinematics
	var stopping_distance = (closing_speed * closing_speed) / (2.0 * acceleration) if acceleration > 0 else 0.0

	# How far until we need to start braking?
	var brake_start_distance = distance_to_target - desired_stop_distance

	# If we can't stop in time, return 0 (need to brake, not thrust)
	if stopping_distance >= brake_start_distance and closing_speed > 10.0:
		return 0.0

	# If we're closing too fast, reduce throttle proportionally
	var safe_closing_speed = sqrt(2.0 * acceleration * max(0.0, brake_start_distance))

	if closing_speed > safe_closing_speed * 0.8:
		# Already at or above safe approach speed
		return 0.1  # Minimal thrust, coasting
	elif closing_speed > safe_closing_speed * 0.5:
		# Approaching safe speed
		return 0.3
	else:
		# Well under safe speed, can accelerate more
		var distance_factor = clamp(distance_to_target / 6000.0, 0.2, 1.0)
		return distance_factor * 0.6

# ============================================================================
# SPACE PHYSICS MOVEMENT
# ============================================================================

## Apply realistic space physics - ships drift, thrust provides acceleration
## Now supports continuous throttle (0.0-1.0) for precise speed control
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

	# Apply thrust based on throttle setting
	# CRITICAL: Main thrust is ALWAYS applied in the direction the ship VISUALLY FACES
	# Engines are at the BACK of the ship, so they push the ship FORWARD
	var thrust_vector = Vector2.ZERO
	var maneuvering_direction = Vector2.ZERO

	# Get throttle value (0.0-1.0) - backwards compatible with binary thrust_active
	var throttle: float = pilot_control.get("throttle", 0.0)
	if throttle == 0.0 and pilot_control.get("thrust_active", false):
		# Legacy compatibility: if no throttle set but thrust_active is true, use full throttle
		throttle = 1.0

	if throttle > 0.0:
		# Calculate angle between ship facing and desired visual direction
		var desired_thrust_direction = get_visual_forward(pilot_control.desired_heading)
		var thrust_angle_diff = abs(ship_facing.angle_to(desired_thrust_direction))

		# Calculate effective throttle based on alignment
		# Ships must turn to face their target before they can effectively thrust
		var alignment_factor: float = 0.0
		if pilot_control.get("is_braking", false):
			# BRAKING: Full thrust opposite to velocity to slow down
			# Ship should be facing opposite to velocity direction
			alignment_factor = 1.0
		elif thrust_angle_diff < PI / 4:  # Within 45° of desired heading
			# Well aligned - full throttle effectiveness
			alignment_factor = 1.0
		elif thrust_angle_diff < PI / 2:  # Within 90° - partial effectiveness
			# Reduced effectiveness when not fully aligned
			alignment_factor = 0.3
		# Beyond 90° - no thrust, ship needs to turn first

		# Apply throttle and alignment to acceleration
		var effective_acceleration = ship_data.stats.acceleration * throttle * alignment_factor

		# Thrust is ALWAYS in ship_facing direction (engines push from behind)
		thrust_vector = ship_facing * effective_acceleration * delta

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

	# REVERSE THRUST: Brake thrusters allow backing off without turning around
	# This lets ships maintain aim while adjusting distance
	var reverse_thrust_amount = pilot_control.get("reverse_thrust", 0.0)  # 0.0 to 1.0
	if reverse_thrust_amount > 0.0:
		# Thrust opposite to ship facing direction
		var reverse_accel = ship_data.stats.acceleration * ship_data.stats.get("reverse_acceleration", 0.4)
		thrust_vector -= ship_facing * reverse_accel * reverse_thrust_amount * delta

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
