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

# ============================================================================
# LATERAL THRUST PHILOSOPHY
# ============================================================================
# At close/combat range: Face target, use lateral thrust for all positioning
# At far range: Face movement direction, use main thrust to close distance

const LATERAL_THRUST_RANGE = 1500.0  # Use lateral thrust when closer than this to target

# ============================================================================
# COMBAT MOVEMENT TUNING
# ============================================================================
# All distances are 4-5x scaled for combat spacing.

## Pilots watch for collisions within this range.
const COLLISION_AWARENESS_RANGE = 800.0

## COMMITTED EVASION HOLDS (ms). Under momentum physics, displacement from an
## oscillating strafe of acceleration `a` at angular frequency `ω` is a/ω² —
## a fast sine weave moves a fighter less than its own hit radius and evades
## nothing. Effective evasion COMMITS to one direction long enough for
## displacement (a·t²/2) to clear the hit circle, then flips on a hash-random
## schedule so gunners can't metronome the rhythm
## (see committed_strafe_direction).
const DOGFIGHT_STRAFE_HOLD_MS = 900.0
const RETREAT_WEAVE_HOLD_MS = 1000.0
const DODGE_STRAFE_HOLD_MS = 1200.0
const DEFENSIVE_BREAK_HOLD_MS = 800.0

## Combat positioning distances.
const DOGFIGHT_COMBAT_RANGE = 2400.0       # Strafe-fight standoff distance
const RETREAT_TARGET_DISTANCE = 2000.0     # How far ahead retreat waypoints are set
const RETREAT_WEAVE_WIDTH = 600.0          # Side-to-side dodge width while retreating

# ============================================================================
# FRONT BRAKE THRUSTER HEAT SYSTEM
# ============================================================================
# Front brake thrusters are as powerful as main engines but generate heavy heat.
# When overheated, brakes are locked out until cooled to recovery threshold.

const BRAKE_OVERHEAT_THRESHOLD = 1.0  # 100% of capacity = overheat
const BRAKE_RECOVERY_THRESHOLD = 0.5  # Must cool to 50% before brakes work again

# ============================================================================
# CREW MODIFIER READS
# ============================================================================
# Pilot skill is baked onto ship_data.crew_modifiers by CrewIntegrationSystem
# (factor fields, not raw skill). MovementSystem just consumes — no callback,
# no recomputation. Defaults of 1.0 mean "no crew assigned" doesn't punish
# stats. Hot-path lookups; keep them O(1).

static func _read_modified_turn_rate(ship_data: Dictionary) -> float:
	var base: float = ship_data.stats.turn_rate
	var factor: float = ship_data.get("crew_modifiers", {}).get("pilot_turn_factor", 1.0)
	return base * factor

static func _read_modified_acceleration(ship_data: Dictionary) -> float:
	var base: float = ship_data.stats.acceleration
	var factor: float = ship_data.get("crew_modifiers", {}).get("pilot_accel_factor", 1.0)
	return base * factor

static func _read_modified_lateral_factor(ship_data: Dictionary) -> float:
	return ship_data.get("crew_modifiers", {}).get("pilot_lateral_factor", 1.0)

static func _read_modified_dampening(ship_data: Dictionary) -> float:
	var base: float = ship_data.stats.get("inertial_dampening", 0.0)
	var factor: float = ship_data.get("crew_modifiers", {}).get("pilot_damp_factor", 1.0)
	return base * factor

## Check if front brakes are currently overheated (locked out)
static func is_brake_overheated(ship_data: Dictionary) -> bool:
	return ship_data.get("brake_overheated", false)

## Check if front brakes can be used (not overheated, or recovered from overheat)
static func can_use_brakes(ship_data: Dictionary) -> bool:
	if not is_brake_overheated(ship_data):
		return true
	# If overheated, check if we've cooled enough to recover
	var current_heat = ship_data.get("brake_current_heat", 0.0)
	var capacity = ship_data.get("stats", {}).get("brake_heat_capacity", 100.0)
	return current_heat / capacity < BRAKE_RECOVERY_THRESHOLD

## Get current brake heat as a ratio (0.0 to 1.0+)
static func get_brake_heat_ratio(ship_data: Dictionary) -> float:
	var current_heat = ship_data.get("brake_current_heat", 0.0)
	var capacity = ship_data.get("stats", {}).get("brake_heat_capacity", 100.0)
	return current_heat / capacity if capacity > 0 else 0.0

## Convert a direction vector to a heading angle that makes the ship VISUALLY face that direction
static func direction_to_heading(direction: Vector2) -> float:
	return direction.angle() + PI / 2

## Get the visual forward direction of a ship from its rotation
static func get_visual_forward(rotation: float) -> Vector2:
	return Vector2(sin(rotation), -cos(rotation))

## Committed randomized strafe direction: -1.0 or +1.0, held for `hold_ms`
## and re-rolled from a per-ship hash at each window boundary. Stateless and
## deterministic in (ship_id, game_time) — no per-frame mutation, no wall
## clock. The per-ship phase offset desynchronizes the fleet so squadrons
## don't all flip on the same frame.
static func committed_strafe_direction(ship_data: Dictionary, hold_ms: float, game_time: float) -> float:
	var ship_id: String = ship_data.get("ship_id", "")
	var phase_offset: int = hash(ship_id) % int(hold_ms)
	var window: int = int((game_time * 1000.0 + phase_offset) / hold_ms)
	return 1.0 if hash("%s|%d" % [ship_id, window]) % 2 == 0 else -1.0

# Leash-vs-aggression dial. The pilot's aggression scales how hard the
# leash pulls when the ship has an enemy target:
#   aggression = 0.0  → 2× pull (hugs patrol area, won't chase past edge)
#   aggression = 0.5  → 1× pull (baseline; matches the original behavior)
#   aggression ≥ 0.95 → bypass (no leash; chase anywhere)
# Without a target the leash always applies normally — high-aggression
# pilots return to patrol when there's nothing to fight.
const LEASH_AGGRESSION_BYPASS_THRESHOLD: float = 0.95
const LEASH_PULL_SCALE_AT_AGGRESSION_ZERO: float = 2.0
const LEASH_PULL_SCALE_AT_AGGRESSION_FULL: float = 0.0

## Bias a desired heading back toward the ship's assigned operating area
## when the ship is outside it. Ramps from no effect at the edge of the
## leash radius to total override at 2x the radius. Ships without an
## `assigned_area` are unaffected. The pilot's aggression dial scales the
## pull when an enemy target is set; see constants above.
static func apply_area_leash(ship_data: Dictionary, desired_heading: float) -> float:
	# A committed flee runs for the boundary and must not be curved homeward by
	# the patrol leash — the boundary is the harder bound.
	if ship_data.get("orders", {}).get("flee_decision", "") == "committed":
		return desired_heading
	var assigned_area = ship_data.get("assigned_area")
	if assigned_area == null or not assigned_area is Dictionary:
		return desired_heading
	var area_radius: float = assigned_area.get("radius", 0.0)
	if area_radius <= 0.0:
		return desired_heading
	var area_center: Vector2 = assigned_area.get("center", Vector2.ZERO)
	var to_center: Vector2 = area_center - ship_data.get("position", Vector2.ZERO)
	var dist: float = to_center.length()
	if dist <= area_radius or dist < 1.0:
		return desired_heading

	var pull_scale: float = _leash_pull_scale(ship_data)
	if pull_scale <= 0.0:
		return desired_heading

	var return_heading: float = direction_to_heading(to_center)
	# Base ramp: pull = 0 at the edge, 1.0 at 2× radius. Aggression scales it.
	var raw_pull: float = clamp((dist - area_radius) / area_radius, 0.0, 1.0)
	var pull: float = clamp(raw_pull * pull_scale, 0.0, 1.0)
	return lerp_angle(desired_heading, return_heading, pull)

## Pull-scale dial. Returns 1.0 (baseline) when the ship has no target or no
## aggression configured; with a target, lerps from 2× (timid) at agg=0 to
## 0 (loose) at agg=1, with a hard bypass at LEASH_AGGRESSION_BYPASS_THRESHOLD.
static func _leash_pull_scale(ship_data: Dictionary) -> float:
	var orders: Dictionary = ship_data.get("orders", {})
	var target_id = orders.get("target_id", "")
	var has_target: bool = target_id != null and str(target_id) != ""
	if not has_target:
		return 1.0

	var modifiers: Dictionary = ship_data.get("crew_modifiers", {})
	if not modifiers.has("pilot_aggression"):
		return 1.0
	var aggression: float = float(modifiers.pilot_aggression)
	if aggression >= LEASH_AGGRESSION_BYPASS_THRESHOLD:
		return 0.0
	return lerp(LEASH_PULL_SCALE_AT_AGGRESSION_ZERO,
				LEASH_PULL_SCALE_AT_AGGRESSION_FULL,
				clamp(aggression, 0.0, 1.0))

# ============================================================================
# MAIN API - Returns new ship_data with updated position/velocity
# ============================================================================

## Update ship movement - returns new ship_data Dictionary.
## `game_time` is elapsed battle time in seconds — the caller owns the clock
## (wall-derived in the game node, simulated in headless harnesses).
static func update_ship_movement(ship_data: Dictionary, targets: Array, delta: float, game_time: float, obstacles: Array = []) -> Dictionary:
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
		pilot_control = calculate_fighter_pilot_control(ship_data, target, nearby_ships, obstacles, game_time)

	elif current_order == "engage":
		# Engage mode - pursue and attack target
		var target_id = ship_data.get("orders", {}).get("target_id", "")
		var target = find_ship_by_id(targets, target_id) if target_id else find_nearest_enemy(ship_data, targets)
		if target.is_empty():
			return apply_space_drift(ship_data, delta)
		pilot_control = calculate_pilot_control(ship_data, target, nearby_ships, obstacles)

	elif current_order == "flee":
		# Escape-boundary flee — fighters and large ships alike steer to
		# orders.flee_target (outward exit when committed, battlefield center
		# when turning back). No target ship needed.
		pilot_control = calculate_steer_to_point(
			ship_data, ship_data.get("orders", {}).get("flee_target", ship_data.position))

	elif current_order == "large_ship_engage":
		# Large ship engage mode - corvette and capital maneuvers
		var target_id = ship_data.get("orders", {}).get("target_id", "")
		var target = find_ship_by_id(targets, target_id) if target_id else find_nearest_enemy(ship_data, targets)
		if target.is_empty():
			return apply_space_drift(ship_data, delta)
		var maneuver_subtype = ship_data.get("orders", {}).get("maneuver_subtype", "large_ship_close_to_broadside")
		pilot_control = _calculate_large_ship_control(ship_data, target, maneuver_subtype)

	elif current_order == "tactical":
		# Blended steering directive. The directive was stamped onto
		# ship.orders by CrewIntegrationSystem at decision time; re-blend each frame
		# from LIVE positions so the ship responds to movement between decisions.
		var tgt_id: String = ship_data.get("orders", {}).get("engagement_target", "")
		if tgt_id.is_empty():
			tgt_id = ship_data.get("orders", {}).get("target_id", "")
		var tactical_target: Dictionary = find_ship_by_id(targets, tgt_id) if tgt_id else {}
		if tactical_target.is_empty():
			tactical_target = find_nearest_enemy(ship_data, targets)
		# Build a lightweight threat list for the converter (position only is enough)
		var tactical_threats: Array = _gather_enemy_positions(ship_data, targets)
		# Pass nearby_ships + obstacles so blended steering can separate from friendlies
		pilot_control = calculate_blended_control(ship_data, tactical_target, tactical_threats, nearby_ships, obstacles, delta)

	else:
		# No orders or unknown order - use default behavior (find nearest enemy)
		var target = find_nearest_enemy(ship_data, targets)
		if target.is_empty():
			return apply_space_drift(ship_data, delta)
		pilot_control = calculate_pilot_control(ship_data, target, nearby_ships, obstacles)

	return apply_space_physics(ship_data, pilot_control, delta)

## Update all ships - returns new Array of ship_data
static func update_all_ships(ships: Array, delta: float, game_time: float, obstacles: Array = []) -> Array:
	return ships \
		.filter(func(ship): return ship != null) \
		.map(func(ship): return update_ship_movement(ship, ships, delta, game_time, obstacles))

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
	var collision_awareness_range = COLLISION_AWARENESS_RANGE
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
## Now uses SKILL-BASED APPROACH for pursuit maneuvers
static func calculate_fighter_pilot_control(ship_data: Dictionary, target: Dictionary, nearby_ships: Array, obstacles: Array, game_time: float) -> Dictionary:
	var maneuver_subtype = ship_data.get("orders", {}).get("maneuver_subtype", "pursue")

	# Route to appropriate maneuver calculation
	# PURSUIT MANEUVERS now use skill-aware approach system
	match maneuver_subtype:
		"fight_pursue_full_speed", "fight_pursue_tactical":
			# Use skill-aware approach - routes based on approach_style from AI
			return calculate_skill_aware_approach(ship_data, target, nearby_ships, obstacles, game_time)
		"fight_dogfight_maneuver":
			return calculate_dogfight_maneuver(ship_data, target, nearby_ships, obstacles, game_time)
		"fight_defensive_break":
			return calculate_defensive_break(ship_data, target, nearby_ships, obstacles, game_time)
		"fight_lateral_break":
			return calculate_lateral_break(ship_data, target, nearby_ships, obstacles)
		"fight_friendly_avoid":
			return calculate_friendly_avoid(ship_data, target, nearby_ships, obstacles)
		"fight_evasive_retreat":
			return calculate_evasive_retreat(ship_data, target, nearby_ships, obstacles, game_time)
		"fight_return_to_area":
			return calculate_return_to_area(ship_data)
		"fight_dodge_and_weave":
			return calculate_dodge_and_weave(ship_data, target, nearby_ships, obstacles, game_time)
		"fight_wing_rejoin":
			return calculate_wing_rejoin(ship_data, target, nearby_ships, obstacles)
		"fight_play_waypoint":
			return calculate_play_waypoint(ship_data, target, nearby_ships, obstacles)
		_:
			# Fallback to standard pilot control
			return calculate_pilot_control(ship_data, target, nearby_ships, obstacles)


## Dogfight maneuver - weaving at combat range
## Ship ALWAYS faces target for aiming
## Main thrust = distance control only (close in / back off)
## Lateral thrust = all positioning (strafing while aiming)
static func calculate_dogfight_maneuver(ship_data: Dictionary, target: Dictionary, nearby_ships: Array, obstacles: Array, game_time: float) -> Dictionary:
	var to_target = target.position - ship_data.position
	var distance = to_target.length()
	var direction_to_target = to_target.normalized()

	# ALWAYS face the target for aiming
	var desired_heading = direction_to_heading(to_target)

	# Committed strafe — full lateral burn one way, hash-random flip each hold
	var lateral_thrust = committed_strafe_direction(ship_data, DOGFIGHT_STRAFE_HOLD_MS, game_time)

	# Desired combat range
	var desired_combat_range = DOGFIGHT_COMBAT_RANGE
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

## Defensive break - sharp alternating turns (skilled evasion)
static func calculate_defensive_break(ship_data: Dictionary, target: Dictionary, nearby_ships: Array, obstacles: Array, game_time: float) -> Dictionary:
	var to_target = target.position - ship_data.position
	var distance = to_target.length()

	# Alternating sharp turns in opposite directions - unpredictable
	var perpendicular = Vector2(-to_target.y, to_target.x).normalized()

	# Committed randomized breaks — held long enough to actually displace,
	# flipped on a hash-random schedule so the rhythm can't be tracked
	var break_direction = committed_strafe_direction(ship_data, DEFENSIVE_BREAK_HOLD_MS, game_time)

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

## Friendly collision avoidance — slide sideways without facing the friendly.
## Maintains current velocity heading so the ship doesn't look like it's targeting a teammate.
static func calculate_friendly_avoid(ship_data: Dictionary, target: Dictionary, nearby_ships: Array, obstacles: Array) -> Dictionary:
	var to_target = target.position - ship_data.position
	var evasion_dir = ship_data.get("orders", {}).get("evasion_direction", 0)
	if evasion_dir == 0:
		var perpendicular = Vector2(-to_target.y, to_target.x).normalized()
		var lateral_vel = ship_data.get("velocity", Vector2.ZERO).dot(perpendicular)
		evasion_dir = 1 if lateral_vel >= 0 else -1

	var current_vel = ship_data.get("velocity", Vector2.ZERO)
	var desired_heading = direction_to_heading(current_vel) if current_vel.length() > 10.0 else direction_to_heading(-to_target)

	var throttle = calculate_intuitive_throttle(ship_data, to_target.length(), "evasion")

	return {
		"desired_heading": desired_heading,
		"throttle": throttle,
		"thrust_active": throttle > 0.1,
		"is_braking": false,
		"lateral_thrust": evasion_dir,
		"current_distance": to_target.length()
	}

## Return to assigned operating area — flies back into the patrol zone.
## Aims for a point INSIDE the zone (not the center) so 26 ships returning
## simultaneously don't all collide on the same spot. Each ship's return
## point is on the line from the zone center toward its current position,
## with a small tangential per-ship offset so they spread along the zone
## edge instead of stacking on a single entry point.
const RETURN_DEPTH_RATIO = 0.6   # Aim 60% of the way from edge toward center
const RETURN_TANGENT_SPREAD = 0.35  # Up to ~20° tangential spread per ship

static func calculate_return_to_area(ship_data: Dictionary) -> Dictionary:
	var area = ship_data.get("assigned_area")
	var my_pos: Vector2 = ship_data.get("position", Vector2.ZERO)
	var area_center: Vector2 = my_pos
	var area_radius: float = 0.0
	if area is Dictionary:
		area_center = area.get("center", area_center)
		area_radius = float(area.get("radius", 0.0))

	var to_center: Vector2 = area_center - my_pos
	var distance: float = to_center.length()

	# When essentially home, just coast — full throttle would push us through
	# and out the other side.
	if distance < 50.0:
		return {
			"desired_heading": ship_data.get("rotation", 0.0),
			"throttle": 0.0,
			"thrust_active": false,
			"is_braking": false,
			"engagement_range": 100.0,
			"current_distance": distance
		}

	# Pick an entry point on the zone edge nearest to me, then offset it
	# slightly inward and tangentially so 26 ships don't all aim for the
	# same point. Stable per-ship offset comes from ship_id hash.
	var return_target: Vector2 = area_center
	if area_radius > 0.0 and distance > area_radius:
		var inward: Vector2 = -to_center / distance  # unit vector from center toward me
		var tangent: Vector2 = Vector2(-inward.y, inward.x)
		var ship_id: String = ship_data.get("ship_id", "")
		# Hash to [-1, 1] for stable per-ship spread
		var spread: float = (float(hash(ship_id) % 2000) / 1000.0 - 1.0) * RETURN_TANGENT_SPREAD
		var entry_point: Vector2 = area_center + inward * area_radius * RETURN_DEPTH_RATIO
		return_target = entry_point + tangent * area_radius * spread

	var to_target: Vector2 = return_target - my_pos
	return {
		"desired_heading": direction_to_heading(to_target),
		"throttle": 1.0,
		"thrust_active": true,
		"is_braking": false,
		"engagement_range": 100.0,
		"current_distance": to_target.length()
	}

## Steer straight to a world point at full main thrust, facing the travel
## direction. Used by the escape-boundary flee (committed exit run / turn back).
## When essentially on the point, coast so the ship doesn't overshoot.
const STEER_ARRIVAL_DISTANCE = 50.0
static func calculate_steer_to_point(ship_data: Dictionary, point: Vector2) -> Dictionary:
	var my_pos: Vector2 = ship_data.get("position", Vector2.ZERO)
	var to_point: Vector2 = point - my_pos
	var distance: float = to_point.length()
	if distance < STEER_ARRIVAL_DISTANCE:
		return {
			"desired_heading": ship_data.get("rotation", 0.0),
			"throttle": 0.0,
			"thrust_active": false,
			"is_braking": false,
			"engagement_range": 100.0,
			"current_distance": distance,
		}
	return {
		"desired_heading": direction_to_heading(to_point),
		"throttle": 1.0,
		"thrust_active": true,
		"is_braking": false,
		"engagement_range": 100.0,
		"current_distance": distance,
	}

## Evasive retreat - get away from big ship
static func calculate_evasive_retreat(ship_data: Dictionary, target: Dictionary, nearby_ships: Array, obstacles: Array, game_time: float) -> Dictionary:
	var distance = ship_data.position.distance_to(target.position)
	var away_from_target = (ship_data.position - target.position).normalized()
	var desired_heading = direction_to_heading(away_from_target)

	# Add weave to dodge — committed darts side to side (4x scaled)
	var perpendicular = Vector2(-away_from_target.y, away_from_target.x)
	var weave_dir = committed_strafe_direction(ship_data, RETREAT_WEAVE_HOLD_MS, game_time)
	var weave_offset = perpendicular * weave_dir * RETREAT_WEAVE_WIDTH

	var desired_pos = ship_data.position + away_from_target * RETREAT_TARGET_DISTANCE + weave_offset
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

## Dodge and weave - stay at range, dodge
## Ship ALWAYS faces target for aiming
## Main thrust = distance control only (close in / back off)
## Lateral thrust = all positioning (strafing while aiming)
static func calculate_dodge_and_weave(ship_data: Dictionary, target: Dictionary, nearby_ships: Array, obstacles: Array, game_time: float) -> Dictionary:
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
		# Fallback: committed strafe with hash-random flips
		lateral_thrust = committed_strafe_direction(ship_data, DODGE_STRAFE_HOLD_MS, game_time)

	# Desired combat range - close enough to hit but far enough to evade
	# Fighter weapons have ~1000 range, corvette weapons have ~1500 range
	# Stay at 1200-1600 range to hit but avoid worst of enemy fire
	var desired_combat_range = 1400.0
	var range_tolerance = 300.0
	var distance_error = distance - desired_combat_range

	# Main thrust is ONLY for distance control along line of sight
	var throttle = 0.0
	var should_brake = false
	var current_velocity = ship_data.get("velocity", Vector2.ZERO)

	if distance_error > range_tolerance:
		# Too far - close in at moderate speed (more aggressive approach)
		throttle = 0.5
	elif distance_error < -range_tolerance:
		# Too close - back off
		should_brake = true
	# Otherwise at good range - no forward thrust, just strafe

	# Brake if going too fast
	var current_speed = current_velocity.length()
	var max_dodge_speed = ship_data.stats.max_speed * 0.4
	if current_speed > max_dodge_speed:
		should_brake = true
		throttle = 0.0

	return {
		"desired_heading": desired_heading,
		"throttle": throttle,
		"thrust_active": throttle > 0.1,
		"is_braking": should_brake,
		"lateral_thrust": lateral_thrust,  # Maneuvering jets for ALL positioning
		"engagement_range": 1400.0,
		"current_distance": distance
	}

## Squadron-play waypoint — fly toward a tactical offset assigned by the
## squadron leader's active play. The pilot aims at `formation_position` at
## tactical-pursuit throttle; once close, FighterPilotAI stops emitting this
## maneuver and engagement resumes.
static func calculate_play_waypoint(ship_data: Dictionary, target: Dictionary, nearby_ships: Array, obstacles: Array) -> Dictionary:
	var waypoint: Vector2 = ship_data.get("orders", {}).get("formation_position", Vector2.ZERO)
	var my_pos: Vector2 = ship_data.get("position", Vector2.ZERO)
	var to_waypoint := waypoint - my_pos
	var distance := to_waypoint.length()
	if distance < 1.0:
		return {
			"desired_heading": ship_data.get("rotation", 0.0),
			"throttle": 0.0,
			"thrust_active": false,
			"is_braking": false,
			"engagement_range": 0.0,
			"current_distance": 0.0,
		}
	var desired_heading := direction_to_heading(to_waypoint)
	var throttle := calculate_intuitive_throttle(ship_data, distance, "pursuit_tactical")
	return {
		"desired_heading": desired_heading,
		"throttle": throttle,
		"thrust_active": throttle > 0.1,
		"is_braking": false,
		"engagement_range": 0.0,
		"current_distance": distance,
	}


# ============================================================================
# LARGE SHIP MANEUVERS - Corvette and Capital tactics

## Shared broadside-heading helper used by calculate_blended_control (when facing_mode == "broadside").
##
## Returns the heading (radians) perpendicular to the bearing to `target_pos`,
## picking whichever of the two perpendicular options is closer to
## `current_rotation` — so the ship commits to one orbit side instead of
## flip-flopping every frame.
##
## Extracted here so the math lives once; callers get the heading and decide
## how to set throttle/lateral independently.
static func _broadside_heading_toward(
	my_pos: Vector2,
	target_pos: Vector2,
	current_rotation: float
) -> float:
	var to_target: Vector2 = (target_pos - my_pos).normalized()
	# Two perpendicular options (port / starboard)
	var perp_left:  Vector2 = Vector2(-to_target.y,  to_target.x)
	var perp_right: Vector2 = Vector2( to_target.y, -to_target.x)
	var heading_left:  float = direction_to_heading(perp_left)
	var heading_right: float = direction_to_heading(perp_right)
	# Pick the side closer to current rotation to avoid flip-flopping.
	if abs(angle_difference(current_rotation, heading_left)) <= abs(angle_difference(current_rotation, heading_right)):
		return heading_left
	return heading_right
# ============================================================================

## Calculate large ship pilot control - returns pilot_control dictionary for apply_space_physics
## These are simpler than fighter maneuvers - less aggressive turning, more lateral thrust.
## One arm per LargeShipPilotAI engagement-cycle phase, no fallback.
static func _calculate_large_ship_control(ship_data: Dictionary, target: Dictionary, maneuver: String) -> Dictionary:
	match maneuver:
		"large_ship_close_to_broadside":
			return _calculate_large_ship_close_to_broadside(ship_data, target)
		"large_ship_fighting_withdrawal":
			return _calculate_large_ship_fighting_withdrawal(ship_data, target)
		"large_ship_present_thickest_armor":
			return _calculate_large_ship_present_thickest_armor(ship_data, target)
		_:
			push_error("Unknown large ship maneuver: " + maneuver)
			return _calculate_large_ship_close_to_broadside(ship_data, target)

## CLOSING — full burn toward optimal broadside range, biased off-axis so we
## arrive on a broadside-ready heading instead of nose-on. Removes the
## "stop-and-pivot-90°" pause that made approach feel like a passive grind.
const LARGE_SHIP_CLOSE_THROTTLE = 1.0
const LARGE_SHIP_CLOSE_OFFSET_DEG = 25.0
static func _calculate_large_ship_close_to_broadside(ship_data: Dictionary, target: Dictionary) -> Dictionary:
	var my_pos = ship_data.get("position", Vector2.ZERO)
	var target_pos = target.get("position", Vector2.ZERO)

	var to_target = (target_pos - my_pos).normalized()
	var distance = my_pos.distance_to(target_pos)

	# Pick the off-axis side closer to current rotation so we don't flip-flop.
	var current_rotation = ship_data.get("rotation", 0.0)
	var base_angle = to_target.angle()
	var offset = deg_to_rad(LARGE_SHIP_CLOSE_OFFSET_DEG)
	var dir_left = Vector2(cos(base_angle + offset), sin(base_angle + offset))
	var dir_right = Vector2(cos(base_angle - offset), sin(base_angle - offset))
	var heading_left = direction_to_heading(dir_left)
	var heading_right = direction_to_heading(dir_right)
	var desired_heading: float
	if abs(angle_difference(current_rotation, heading_left)) < abs(angle_difference(current_rotation, heading_right)):
		desired_heading = heading_left
	else:
		desired_heading = heading_right

	return {
		"desired_heading": desired_heading,
		"throttle": LARGE_SHIP_CLOSE_THROTTLE,
		"thrust_active": true,
		"is_braking": false,
		"lateral_thrust": 0.0,
		"current_distance": distance
	}

## FIGHTING WITHDRAWAL — disengage along the line away from the target while
## still facing roughly toward them, so working turrets keep firing as we go.
static func _calculate_large_ship_fighting_withdrawal(ship_data: Dictionary, target: Dictionary) -> Dictionary:
	var my_pos = ship_data.get("position", Vector2.ZERO)
	var target_pos = target.get("position", Vector2.ZERO)

	var to_target = (target_pos - my_pos).normalized()
	var distance = my_pos.distance_to(target_pos)
	var away_heading = direction_to_heading(-to_target)

	return {
		"desired_heading": away_heading,
		"throttle": 1.0,
		"thrust_active": true,
		"is_braking": false,
		"lateral_thrust": 0.0,
		"current_distance": distance
	}

## TACTICAL BREAK — present thickest (front) armor toward the threat. Hard
## turn to face them, light forward thrust to drive the bow on.
static func _calculate_large_ship_present_thickest_armor(ship_data: Dictionary, target: Dictionary) -> Dictionary:
	var my_pos = ship_data.get("position", Vector2.ZERO)
	var target_pos = target.get("position", Vector2.ZERO)

	var to_target = (target_pos - my_pos).normalized()
	var distance = my_pos.distance_to(target_pos)
	var desired_heading = direction_to_heading(to_target)

	return {
		"desired_heading": desired_heading,
		"throttle": 0.4,
		"thrust_active": true,
		"is_braking": false,
		"lateral_thrust": 0.0,
		"current_distance": distance
	}

# ============================================================================
# WING FORMATION MANEUVERS - Dynamic wing system
# ============================================================================

## Wing rejoin - Wingman returns to formation position with Lead
## Skill affects how tightly and quickly they rejoin
## Distance-aware: Far uses main thrust, close uses lateral to slide into formation
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

	# High skill wingman approaches faster but brakes earlier
	var far_threshold = lerp(WingConstants.REJOIN_FAR_THRESHOLD_LOW_SKILL, WingConstants.REJOIN_FAR_THRESHOLD_HIGH_SKILL, skill_factor)
	var close_threshold = lerp(WingConstants.REJOIN_CLOSE_THRESHOLD_LOW_SKILL, WingConstants.REJOIN_CLOSE_THRESHOLD_HIGH_SKILL, skill_factor)

	if distance > close_threshold:
		return _calculate_wing_rejoin_far(ship_data, to_formation, distance, far_threshold, close_threshold, skill_factor)
	else:
		return _calculate_wing_rejoin_close(ship_data, target, to_formation, distance, skill_factor)

## Wing rejoin FAR/MID arm: Use main thrust to approach formation position
static func _calculate_wing_rejoin_far(ship_data: Dictionary, to_formation: Vector2, distance: float, far_threshold: float, close_threshold: float, skill_factor: float) -> Dictionary:
	var current_velocity = ship_data.get("velocity", Vector2.ZERO)
	var desired_heading = direction_to_heading(to_formation)

	# Skill affects how aggressively they course correct
	var brake_threshold = lerp(WingConstants.REJOIN_BRAKE_ANGLE_LOW_SKILL, WingConstants.REJOIN_BRAKE_ANGLE_HIGH_SKILL, skill_factor)

	# DART AND DASH: Brake if we need to change direction significantly
	if current_velocity.length() > 30.0:
		var current_heading = direction_to_heading(current_velocity)
		var heading_diff = abs(angle_difference(current_heading, desired_heading))
		if heading_diff > brake_threshold and distance > 50.0:
			return create_braking_control(ship_data, desired_heading, distance)

	var throttle: float
	var should_brake = false
	if distance > far_threshold:
		throttle = calculate_intuitive_throttle(ship_data, distance, "pursuit_tactical")
	else:
		var closing_speed = current_velocity.dot(to_formation.normalized())
		var safe_throttle = calculate_safe_approach_throttle(ship_data, distance, closing_speed, close_threshold * 0.8)
		throttle = min(calculate_intuitive_throttle(ship_data, distance, "formation"), safe_throttle)
		should_brake = closing_speed > ship_data.stats.max_speed * 0.4

	return {
		"desired_heading": desired_heading,
		"throttle": throttle if not should_brake else 0.0,
		"thrust_active": throttle > 0.1 and not should_brake,
		"is_braking": should_brake,
		"engagement_range": WingConstants.REJOIN_MATCH_HEADING_DISTANCE,
		"current_distance": distance
	}

## Wing rejoin CLOSE arm: Face lead's direction, use lateral thrust to slide into formation
static func _calculate_wing_rejoin_close(ship_data: Dictionary, target: Dictionary, to_formation: Vector2, distance: float, skill_factor: float) -> Dictionary:
	var my_pos = ship_data.get("position", Vector2.ZERO)
	var lead_velocity = target.get("velocity", Vector2.ZERO)
	var current_velocity = ship_data.get("velocity", Vector2.ZERO)

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
	# Skill affects responsiveness
	var lateral_divisor = lerp(200.0, 100.0, skill_factor)
	var lateral_thrust = clamp(lateral_offset / lateral_divisor, -1.0, 1.0)

	# Main thrust controls forward/back in formation
	var forward_offset = to_formation.dot(forward_dir)
	var throttle = 0.0
	var should_brake = false

	if forward_offset > 30.0:
		throttle = 0.2
	elif forward_offset < -30.0:
		should_brake = true

	# Match lead's speed
	var speed_diff = current_velocity.length() - lead_velocity.length()
	if speed_diff > 15.0:
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

# ============================================================================
# SKILL-BASED APPROACH MANEUVERS
# ============================================================================
# These functions implement dramatically different flight patterns based on
# pilot skill. Low skill pilots fly straight at targets, high skill pilots
# use angles, jinking, and complex maneuvers.

## Skill-aware approach router - selects maneuver based on approach_style
static func calculate_skill_aware_approach(ship_data: Dictionary, target: Dictionary, nearby_ships: Array, obstacles: Array, game_time: float) -> Dictionary:
	var orders = ship_data.get("orders", {})
	var approach_style = orders.get("approach_style", 0)  # 0 = DIRECT
	var skill = orders.get("skill_factor", 0.5)

	# Route to appropriate skill-based maneuver
	match approach_style:
		0:  # DIRECT - low skill, fly straight at target
			return calculate_direct_approach(ship_data, target)
		1:  # ANGLED - medium skill, approach from offset angle
			return calculate_angled_approach(ship_data, target, skill)
		2:  # PURSUIT_CURVE - high skill, lead pursuit with jinking
			return calculate_pursuit_curve(ship_data, target, skill, orders, game_time)
		3:  # DEFENSIVE_SPIRAL - high skill, break and reposition
			return calculate_defensive_spiral(ship_data, target, skill, orders, game_time)
		4:  # ATTACK_RUN - high skill, press advantage with jinking
			return calculate_attack_run(ship_data, target, skill, orders, game_time)
		_:
			return calculate_direct_approach(ship_data, target)

## DIRECT APPROACH - Low skill pilots fly straight at target
## No lateral movement, no prediction, no angles - just point and burn.
## Pass-by offset still applies even to "direct" approaches — even the
## sloppiest pilot doesn't fly straight into another ship's nose at full
## throttle. Without this, two head-on direct approaches converge to a
## perfect collision on every first pass.
static func calculate_direct_approach(ship_data: Dictionary, target: Dictionary) -> Dictionary:
	var to_target = target.position - ship_data.position
	var distance = to_target.length()
	var desired_heading = apply_pass_by_offset(ship_data, target, direction_to_heading(to_target))

	# Low skill pilots don't brake and adjust - they commit and hope
	# Only brake if going WAY too fast
	var current_velocity = ship_data.get("velocity", Vector2.ZERO)
	var current_speed = current_velocity.length()
	var max_speed = ship_data.get("stats", {}).get("max_speed", 500.0)
	var should_brake = current_speed > max_speed * 1.2

	# Full throttle approach - no subtlety
	var throttle = 1.0 if not should_brake else 0.0

	return {
		"desired_heading": desired_heading,
		"throttle": throttle,
		"thrust_active": throttle > 0.1,
		"is_braking": should_brake,
		"lateral_thrust": 0.0,  # NO LATERAL - key characteristic of low skill
		"engagement_range": 400.0,
		"current_distance": distance
	}

## ANGLED APPROACH - Medium skill pilots approach from offset angle
## Tries to come in from the side rather than head-on
static func calculate_angled_approach(ship_data: Dictionary, target: Dictionary, skill: float) -> Dictionary:
	var to_target = target.position - ship_data.position
	var distance = to_target.length()

	# Calculate approach angle offset based on skill
	var angle_skill = (skill - WingConstants.PILOT_APPROACH_ANGLE_SKILL) / (1.0 - WingConstants.PILOT_APPROACH_ANGLE_SKILL)
	var offset_angle = lerp(WingConstants.PILOT_APPROACH_ANGLE_MIN,
							WingConstants.PILOT_APPROACH_ANGLE_MAX, angle_skill)

	# Consistent side selection per ship (based on ship_id hash)
	var ship_id = ship_data.get("ship_id", "")
	var approach_side = 1 if hash(ship_id) % 2 == 0 else -1

	# Offset the approach direction (skill-based bias toward one side)
	var offset_direction = to_target.rotated(offset_angle * approach_side).normalized()
	# Layer in pass-by deflection on top — keeps pilots from merging head-on
	# even if their angled bias happens to point them at the enemy.
	var desired_heading = apply_pass_by_offset(ship_data, target, direction_to_heading(offset_direction))

	# DART AND DASH check
	var needs_brake = check_needs_braking(ship_data, desired_heading)
	if needs_brake:
		return create_braking_control(ship_data, desired_heading, distance)

	# Some lateral movement for repositioning (scales with skill)
	var lateral_thrust = lerp(0.0, 0.4, angle_skill) * approach_side

	# Tactical throttle - not full speed
	var throttle = calculate_intuitive_throttle(ship_data, distance, "pursuit_tactical")

	return {
		"desired_heading": desired_heading,
		"throttle": throttle,
		"thrust_active": throttle > 0.1,
		"is_braking": false,
		"lateral_thrust": lateral_thrust,
		"engagement_range": 400.0,
		"current_distance": distance
	}

## PURSUIT CURVE - High skill pilots use lead pursuit with constant jinking
## Predicts target movement and constantly adjusts with lateral thrust
static func calculate_pursuit_curve(ship_data: Dictionary, target: Dictionary, skill: float, orders: Dictionary, game_time: float) -> Dictionary:
	var to_target = target.position - ship_data.position
	var distance = to_target.length()
	var target_velocity = target.get("velocity", Vector2.ZERO)

	# Lead pursuit: aim ahead of target based on skill
	var prediction_time = lerp(0.3, 1.2, skill)
	var predicted_pos = target.position + target_velocity * prediction_time
	var to_predicted = predicted_pos - ship_data.position

	# Pass-by offset prevents head-on merges even on a lead-pursuit aim point
	var desired_heading = apply_pass_by_offset(ship_data, target, direction_to_heading(to_predicted))

	# DART AND DASH check
	var needs_brake = check_needs_braking(ship_data, desired_heading)
	if needs_brake:
		return create_braking_control(ship_data, desired_heading, distance)

	# Jinking during approach — committed strafe bursts; amplitude and hold
	# duration come from the pilot's skill-scaled jink params
	var jink_amplitude = orders.get("jink_amplitude", 0.0)
	var jink_hold_ms = orders.get("jink_hold_ms", WingConstants.PILOT_JINK_HOLD_LOW_SKILL_MS)
	var lateral_thrust = committed_strafe_direction(ship_data, jink_hold_ms, game_time) * jink_amplitude

	# Tactical throttle with distance awareness
	var throttle = calculate_intuitive_throttle(ship_data, distance, "pursuit_tactical")

	return {
		"desired_heading": desired_heading,
		"throttle": throttle,
		"thrust_active": throttle > 0.1,
		"is_braking": false,
		"lateral_thrust": lateral_thrust,
		"engagement_range": 400.0,
		"current_distance": distance
	}

## DEFENSIVE SPIRAL - High skill pilots break contact when disadvantaged
## Turns away sharply, builds speed, then comes back from better angle
static func calculate_defensive_spiral(ship_data: Dictionary, target: Dictionary, skill: float, orders: Dictionary, game_time: float) -> Dictionary:
	var to_target = target.position - ship_data.position
	var distance = to_target.length()

	# Break away - turn perpendicular to line of sight
	var perpendicular = Vector2(-to_target.y, to_target.x).normalized()

	# Consistent break direction per ship
	var ship_id = ship_data.get("ship_id", "")
	var break_side = 1 if hash(ship_id) % 2 == 0 else -1

	# Spiral out: initially break perpendicular, then curve away
	var away_from_target = -to_target.normalized()
	var spiral_blend = clamp(distance / 2000.0, 0.0, 1.0)  # More away at close range
	var spiral_direction = (perpendicular * break_side * (1.0 - spiral_blend) + away_from_target * spiral_blend).normalized()

	var desired_heading = direction_to_heading(spiral_direction)

	# Jinking while breaking - even harder to hit
	var jink_amplitude = orders.get("jink_amplitude", 0.0) * 1.2  # Extra jinking when defensive
	var jink_hold_ms = orders.get("jink_hold_ms", WingConstants.PILOT_JINK_HOLD_LOW_SKILL_MS)
	var lateral_thrust = committed_strafe_direction(ship_data, jink_hold_ms, game_time) * jink_amplitude

	# Full evasion throttle - get out fast
	var throttle = calculate_intuitive_throttle(ship_data, distance, "evasion")

	return {
		"desired_heading": desired_heading,
		"throttle": throttle,
		"thrust_active": throttle > 0.1,
		"is_braking": false,
		"lateral_thrust": lateral_thrust,
		"engagement_range": 600.0,  # Larger engagement range - we're repositioning
		"current_distance": distance
	}

## ATTACK RUN - High skill pilots press behind advantage with evasive jinking
## Maintains position advantage while being hard to hit
static func calculate_attack_run(ship_data: Dictionary, target: Dictionary, skill: float, orders: Dictionary, game_time: float) -> Dictionary:
	var to_target = target.position - ship_data.position
	var distance = to_target.length()
	var target_velocity = target.get("velocity", Vector2.ZERO)

	# Get behind position from orders or calculate
	var behind_position = orders.get("behind_position", Vector2.ZERO)
	if behind_position == Vector2.ZERO:
		var target_rotation = target.get("rotation", 0.0)
		var behind_offset = Vector2(cos(target_rotation + PI), sin(target_rotation + PI)) * 600.0
		behind_position = target.position + behind_offset

	# Predict where behind position will be
	var prediction_time = lerp(0.3, 0.8, skill)
	var predicted_behind = behind_position + target_velocity * prediction_time

	var to_behind = predicted_behind - ship_data.position
	var desired_heading = direction_to_heading(to_behind)

	# DART AND DASH check
	var needs_brake = check_needs_braking(ship_data, desired_heading)
	if needs_brake:
		return create_braking_control(ship_data, desired_heading, distance)

	# Jinking while attacking - stay hard to hit even with advantage
	var jink_amplitude = orders.get("jink_amplitude", 0.0) * 0.8  # Slightly less when attacking
	var jink_hold_ms = orders.get("jink_hold_ms", WingConstants.PILOT_JINK_HOLD_LOW_SKILL_MS)
	var lateral_thrust = committed_strafe_direction(ship_data, jink_hold_ms, game_time) * jink_amplitude

	# Tactical throttle - controlled approach to maintain advantage
	var throttle = calculate_intuitive_throttle(ship_data, distance, "pursuit_tactical")

	# Slow down when close to maintain position
	if distance < 800.0:
		throttle *= 0.5

	return {
		"desired_heading": desired_heading,
		"throttle": throttle,
		"thrust_active": throttle > 0.1,
		"is_braking": false,
		"lateral_thrust": lateral_thrust,
		"engagement_range": 350.0,
		"current_distance": distance
	}

## PASS-BY OFFSET — fighters never fly into an opponent's nose at high
## closure speed. Real pilots offset 15-30° to one side so they pass the
## enemy and live to bracket around for a second pass. Without this,
## both AI fighters compute desired_heading = direction_to_target and
## converge into a perfect head-on collision on every merge.
##
## Returns an offset heading. Side is stable per ship_id (one fighter
## habitually breaks right, another habitually breaks left), preventing
## flip-flop and producing personality.
const PASS_BY_RANGE = 1500.0           # Within this range, deflection ramps in
const PASS_BY_HEAD_ON_THRESHOLD = 0.85 # cos(~32°) — closer than this is "head-on"
const PASS_BY_MIN_CLOSING_SPEED_RATIO = 0.4  # Of max_speed — only deflect when committed
const PASS_BY_MIN_OFFSET = 0.10        # ~6° at edge of range
const PASS_BY_MAX_OFFSET = 0.50        # ~29° at point-blank

static func apply_pass_by_offset(ship_data: Dictionary, target: Dictionary, desired_heading: float) -> float:
	var to_target: Vector2 = target.position - ship_data.position
	var distance: float = to_target.length()
	if distance < 1.0 or distance > PASS_BY_RANGE:
		return desired_heading

	var to_target_dir: Vector2 = to_target / distance
	var relative_velocity: Vector2 = ship_data.get("velocity", Vector2.ZERO) - target.get("velocity", Vector2.ZERO)
	var rel_speed: float = relative_velocity.length()
	if rel_speed < 1.0:
		return desired_heading

	# Closing speed (component of relative velocity along the LOS)
	var closing_speed: float = relative_velocity.dot(to_target_dir)
	var max_speed: float = ship_data.stats.get("max_speed", 300.0)
	if closing_speed < max_speed * PASS_BY_MIN_CLOSING_SPEED_RATIO:
		return desired_heading

	# How head-on is the merge? 1.0 = perfectly nose-to-nose
	var head_on_factor: float = relative_velocity.dot(to_target_dir) / rel_speed
	if head_on_factor < PASS_BY_HEAD_ON_THRESHOLD:
		return desired_heading

	# Stable, SYMMETRIC side selection — both ships in a merge must agree to
	# offset to the same world-space side (their right vs. each other's right
	# point opposite in space, so they pass cleanly like cars on a road).
	# Use a sorted-ID hash so both ships compute the same key.
	var ship_id: String = ship_data.get("ship_id", "")
	var target_id: String = target.get("ship_id", "")
	var pair_key: String = ship_id + "|" + target_id if ship_id < target_id else target_id + "|" + ship_id
	var side: float = 1.0 if hash(pair_key) % 2 == 0 else -1.0

	# Offset grows as we close (more committed merge = more deflection)
	var proximity: float = clamp(1.0 - distance / PASS_BY_RANGE, 0.0, 1.0)
	var offset_angle: float = lerp(PASS_BY_MIN_OFFSET, PASS_BY_MAX_OFFSET, proximity) * side
	return desired_heading + offset_angle

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
		"torpedo_boat":
			return 3600.0  # Longer range for torpedo delivery (torpedo range is 1200)
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
	var detection_range = ship_data.collision_radius * 8.0  # Look ahead distance

	# Filter active obstacles that block movement
	var active_obstacles = obstacles \
		.filter(func(o): return o != null) \
		.filter(func(o): return o.get("status", "operational") != "destroyed") \
		.filter(func(o): return o.get("blocks_movement", true))

	for obstacle in active_obstacles:
		var to_obstacle = obstacle.position - ship_data.position
		var distance = to_obstacle.length()
		var combined_radius = ship_data.collision_radius + obstacle.radius

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
## Each physics step is a named helper so the pipeline reads as an ordered
## sequence: rotate, accumulate thrust, integrate velocity, integrate position.
static func apply_space_physics(ship_data: Dictionary, pilot_control: Dictionary, delta: float) -> Dictionary:
	var new_rotation = _compute_new_rotation(ship_data, pilot_control, delta)

	# Ship visual facing direction (where the nose points)
	var ship_facing = get_visual_forward(new_rotation)

	# Accumulate thrust from main engines, maneuvering jets, reverse thrusters
	# and front brakes
	var thrust_vector = _compute_main_thrust(ship_data, pilot_control, ship_facing, delta)
	var lateral = _compute_lateral_thrust(ship_data, pilot_control, ship_facing, delta)
	thrust_vector += lateral.thrust
	thrust_vector += _compute_reverse_thrust(ship_data, pilot_control, ship_facing, delta)
	var brake = _compute_front_brake_and_heat(ship_data, pilot_control, delta)
	thrust_vector += brake.thrust

	# Update velocity with thrust (no drag in space!)
	var new_velocity = ship_data.velocity + thrust_vector
	new_velocity = _apply_inertial_dampening(ship_data, pilot_control, new_velocity, ship_facing, delta)

	new_velocity = _apply_turn_speed_bleed(ship_data, new_velocity, ship_data.rotation, new_rotation)
	new_velocity = _apply_overspeed_decay(ship_data, new_velocity, delta)

	# Update position based on velocity
	var new_position = ship_data.position + new_velocity * delta

	return DictUtils.merge_dict(ship_data, {
		velocity = new_velocity,
		position = new_position,
		rotation = new_rotation,
		brake_current_heat = brake.heat,
		brake_overheated = brake.overheated,
		_pilot_state = pilot_control,  # Store for debugging/visualization
		_maneuvering_thrust_direction = lateral.direction,  # For thruster visualization
		_front_brake_direction = brake.direction  # For brake thruster visualization
	})

## SOFT SPEED CAP — thrust still works past rated max_speed, but the excess
## decays exponentially at this rate (1/sec). Equilibrium overspeed under a
## sustained burn is acceleration / OVERSPEED_DECAY_RATE, so a higher-thrust
## ship sustains a genuinely higher top speed. A hard clamp erased speed as a
## differentiator: once two ships hit the cap, neither thrust nor momentum
## mattered and every chase became pure geometry.
const OVERSPEED_DECAY_RATE = 1.2

static func _apply_overspeed_decay(ship_data: Dictionary, velocity: Vector2, delta: float) -> Vector2:
	var max_speed: float = ship_data.stats.max_speed
	var speed: float = velocity.length()
	if speed <= max_speed:
		return velocity
	var decayed_excess: float = (speed - max_speed) * exp(-OVERSPEED_DECAY_RATE * delta)
	return velocity / speed * (max_speed + decayed_excess)

## TURN BLEED (energy-fight model) — swinging the nose costs
## speed, proportional to how many radians were turned this frame. Per
## radian, a fraction `1 - exp(-turn_speed_bleed)` of speed is lost, so a
## 180° max-rate reversal at `turn_speed_bleed` 0.15 costs ~37% of current
## speed while a low-speed pivot costs almost nothing in absolute terms.
## Speed becomes an energy budget: yank the stick constantly and you end up
## slow and predictable; fly straight and you bank energy. Sustained
## max-rate turning settles at the "corner speed" where thrust regeneration
## balances bleed (~acceleration / (bleed × turn_rate)). Configured per
## ship via the `turn_speed_bleed` stat (0.0 = no bleed).
static func _apply_turn_speed_bleed(ship_data: Dictionary, velocity: Vector2, old_rotation: float, new_rotation: float) -> Vector2:
	var bleed_per_radian: float = ship_data.stats.get("turn_speed_bleed", 0.0)
	if bleed_per_radian <= 0.0:
		return velocity
	var radians_turned: float = abs(angle_difference(old_rotation, new_rotation))
	if radians_turned <= 0.0:
		return velocity
	return velocity * exp(-bleed_per_radian * radians_turned)

## Rotation step — turn toward the pilot's desired heading (biased by the
## area leash) at the ship's speed-dependent turn rate.
static func _compute_new_rotation(ship_data: Dictionary, pilot_control: Dictionary, delta: float) -> float:
	# SPEED-DEPENDENT TURN RATE (WW2 dogfight model): a fighter pivots
	# sharply at low speed but only sluggishly at top speed — its turn
	# radius widens with airspeed. This is the core dogfight tradeoff:
	# slow down to out-turn the enemy and you give up closure rate; stay
	# fast and you commit to flying past. Emergent behavior: boom-and-zoom
	# passes, turn fights at low speed, real meaning to "getting on
	# someone's six". Configured per ship via `turn_rate_falloff`
	# (0.0 = constant turn rate; 1.0 = freezes at top speed).
	var speed_ratio: float = 0.0
	var max_speed: float = ship_data.stats.max_speed
	if max_speed > 0.0:
		speed_ratio = clamp(ship_data.velocity.length() / max_speed, 0.0, 1.0)
	var turn_falloff: float = ship_data.stats.get("turn_rate_falloff", 0.0)
	var effective_turn_rate: float = _read_modified_turn_rate(ship_data) * (1.0 - turn_falloff * speed_ratio)

	# AREA LEASH — every ship has an assigned operating area. Outside it,
	# the pilot's heading is gradually pulled back toward the area center;
	# the further out, the stronger the pull. They keep doing whatever they
	# were doing (still maneuvering, still throttling) but the nose curves
	# back homeward. The pull becomes total at 2x the leash radius — past
	# that, the ship is just flying home regardless of what the pilot wanted.
	var effective_desired_heading: float = apply_area_leash(
		ship_data, pilot_control.desired_heading
	)

	# Rotate ship toward desired heading (already biased by area leash above)
	return rotate_toward_heading(
		ship_data.rotation,
		effective_desired_heading,
		effective_turn_rate,
		delta
	)

## Main thrust step — apply thrust based on throttle setting.
## CRITICAL: Main thrust is ALWAYS applied in the direction the ship VISUALLY FACES
## Engines are at the BACK of the ship, so they push the ship FORWARD
static func _compute_main_thrust(ship_data: Dictionary, pilot_control: Dictionary, ship_facing: Vector2, delta: float) -> Vector2:
	# Get throttle value (0.0-1.0) - backwards compatible with binary thrust_active
	var throttle: float = pilot_control.get("throttle", 0.0)
	if throttle == 0.0 and pilot_control.get("thrust_active", false):
		# Legacy compatibility: if no throttle set but thrust_active is true, use full throttle
		throttle = 1.0

	if throttle <= 0.0:
		return Vector2.ZERO

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
	var effective_acceleration = _read_modified_acceleration(ship_data) * throttle * alignment_factor

	# Thrust is ALWAYS in ship_facing direction (engines push from behind)
	return ship_facing * effective_acceleration * delta

## LATERAL THRUST step — maneuvering thrusters allow sliding perpendicular to
## facing. This is the key to skilled evasion - change LOS without rotating.
## Returns {thrust, direction}; direction feeds thruster visualization.
static func _compute_lateral_thrust(ship_data: Dictionary, pilot_control: Dictionary, ship_facing: Vector2, delta: float) -> Dictionary:
	var lateral_thrust_dir = pilot_control.get("lateral_thrust", 0)  # -1 left, +1 right
	if lateral_thrust_dir == 0:
		return {thrust = Vector2.ZERO, direction = Vector2.ZERO}

	# Perpendicular to ship facing (90° rotation)
	var perpendicular = Vector2(-ship_facing.y, ship_facing.x)
	# Lateral acceleration is weaker than main engines; pilot skill gates
	# how much of that base lateral capacity actually delivers.
	var lateral_accel = _read_modified_acceleration(ship_data) \
		* ship_data.stats.get("lateral_acceleration", 0.3) \
		* _read_modified_lateral_factor(ship_data)
	return {
		thrust = perpendicular * lateral_accel * lateral_thrust_dir * delta,
		direction = perpendicular * lateral_thrust_dir
	}

## REVERSE THRUST step — brake thrusters allow backing off without turning
## around. This lets ships maintain aim while adjusting distance.
static func _compute_reverse_thrust(ship_data: Dictionary, pilot_control: Dictionary, ship_facing: Vector2, delta: float) -> Vector2:
	var reverse_thrust_amount = pilot_control.get("reverse_thrust", 0.0)  # 0.0 to 1.0
	if reverse_thrust_amount <= 0.0:
		return Vector2.ZERO

	# Thrust opposite to ship facing direction
	var reverse_accel = _read_modified_acceleration(ship_data) * ship_data.stats.get("reverse_acceleration", 0.4)
	return -ship_facing * reverse_accel * reverse_thrust_amount * delta

## FRONT BRAKE THRUST step — emergency braking, powerful but heat-limited.
## Applies thrust opposite to current velocity (regardless of ship facing)
## Generates heavy heat - can only be used in short bursts
## Heat dissipation runs every frame, so this step also owns the brake heat
## bookkeeping. Returns {thrust, heat, overheated, direction}.
static func _compute_front_brake_and_heat(ship_data: Dictionary, pilot_control: Dictionary, delta: float) -> Dictionary:
	var brake_thrust_amount = pilot_control.get("brake_thrust", 0.0)  # 0.0 to 1.0
	var current_brake_heat = ship_data.get("brake_current_heat", 0.0)
	var brake_overheated = ship_data.get("brake_overheated", false)
	var brake_heat_generated = 0.0
	var front_brake_direction = Vector2.ZERO
	var brake_thrust = Vector2.ZERO

	# Check if brakes have recovered from overheat
	if brake_overheated and can_use_brakes(ship_data):
		brake_overheated = false

	if brake_thrust_amount > 0.0 and not brake_overheated:
		var current_speed = ship_data.velocity.length()
		if current_speed > 5.0:  # Only brake if moving
			# Brake direction is opposite to velocity (stops the ship regardless of facing)
			var brake_direction = -ship_data.velocity.normalized()
			# Brake acceleration is as powerful as main engines
			var brake_accel = _read_modified_acceleration(ship_data) * ship_data.stats.get("brake_acceleration", 1.0)
			var brake_force = brake_direction * brake_accel * brake_thrust_amount * delta

			# Don't overshoot - limit braking to not reverse direction
			var max_brake_magnitude = current_speed
			if brake_force.length() > max_brake_magnitude:
				brake_force = brake_direction * max_brake_magnitude

			brake_thrust = brake_force
			front_brake_direction = brake_direction

			# Generate heat based on brake usage
			var heat_per_second = ship_data.stats.get("brake_heat_per_second", 50.0)
			brake_heat_generated = heat_per_second * brake_thrust_amount * delta

	# Heat dissipation (always active, even when braking)
	var heat_dissipation = ship_data.stats.get("brake_heat_dissipation", 10.0)
	var new_brake_heat = max(0.0, current_brake_heat + brake_heat_generated - heat_dissipation * delta)

	# Check for overheat
	var heat_capacity = ship_data.stats.get("brake_heat_capacity", 100.0)
	if new_brake_heat >= heat_capacity:
		brake_overheated = true
		new_brake_heat = heat_capacity  # Cap at max

	return {
		thrust = brake_thrust,
		heat = new_brake_heat,
		overheated = brake_overheated,
		direction = front_brake_direction
	}

## INERTIAL DAMPENING step (a.k.a. flight assist): the ship's flight computer
## auto-fires lateral thrusters to kill velocity perpendicular to the
## nose. The ship is still Newtonian (mass, momentum, no global drag),
## but velocity rapidly aligns with facing — fighters curve through
## space instead of sliding like boats on ice. Disabled when the pilot
## is actively strafing (manual override) or braking (brakes handle
## their own deceleration). Tunable per ship via the
## `inertial_dampening` stat (1/sec): higher = tighter, 0 = pure
## Newtonian.
static func _apply_inertial_dampening(ship_data: Dictionary, pilot_control: Dictionary, velocity: Vector2, ship_facing: Vector2, delta: float) -> Vector2:
	var inertial_dampening: float = _read_modified_dampening(ship_data)
	var lateral_thrust_dir = pilot_control.get("lateral_thrust", 0)
	if inertial_dampening > 0.0 and lateral_thrust_dir == 0 and not pilot_control.get("is_braking", false):
		var v_along_facing: float = velocity.dot(ship_facing)
		var v_perpendicular: Vector2 = velocity - ship_facing * v_along_facing
		var perp_speed: float = v_perpendicular.length()
		if perp_speed > 0.1:
			# Exponential decay capped to not reverse the perpendicular component.
			var decay: float = min(perp_speed * inertial_dampening * delta, perp_speed)
			velocity -= v_perpendicular / perp_speed * decay
	return velocity

## Ships in space maintain velocity (Newton's first law)
static func apply_space_drift(ship_data: Dictionary, delta: float) -> Dictionary:
	var new_position = ship_data.position + ship_data.velocity * delta

	# Brake heat still dissipates during drift
	var current_brake_heat = ship_data.get("brake_current_heat", 0.0)
	var heat_dissipation = ship_data.stats.get("brake_heat_dissipation", 10.0)
	var new_brake_heat = max(0.0, current_brake_heat - heat_dissipation * delta)

	# Check for recovery from overheat
	var brake_overheated = ship_data.get("brake_overheated", false)
	if brake_overheated:
		var heat_capacity = ship_data.stats.get("brake_heat_capacity", 100.0)
		if new_brake_heat / heat_capacity < BRAKE_RECOVERY_THRESHOLD:
			brake_overheated = false

	return DictUtils.merge_dict(ship_data, {
		position = new_position,
		brake_current_heat = new_brake_heat,
		brake_overheated = brake_overheated
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
	# Turn at constant angular velocity (not percentage-based)
	var max_turn_this_frame = turn_rate * delta  # Radians we can turn this frame
	var diff = angle_difference(current_rotation, target_rotation)

	if abs(diff) <= max_turn_this_frame:
		# Close enough - snap to target
		return target_rotation
	else:
		# Turn at max rate toward target
		return current_rotation + sign(diff) * max_turn_this_frame

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


# ---------------------------------------------------------------------------
# BLENDED STEERING CONVERTER  (live tactical steering path for "tactical" orders)
# ---------------------------------------------------------------------------
#
# Reads the directive written by SteeringBlender onto ship_data.orders and
# converts it into a pilot_control struct each frame from LIVE positions.
#
# Directive fields consumed:
#   orders.goal_weights      : {pursue, keep_range, evade, formation}
#   orders.preferred_range   : float
#   orders.formation_slot    : Vector2  (formation goal target)
#   orders.anchor_position   : Vector2  (hold/anchor goal target)
#   orders.engagement_target : String   (ship_id; resolved by caller to target dict)

## Deadband around preferred_range — within this fraction of preferred_range
## the keep_range goal produces zero force (neither push nor pull).
## Avoids oscillation when the ship is already near its desired orbit radius.
const BLENDED_RANGE_DEADBAND_FRACTION := 0.15

## Throttle used when closing distance at far range (facing move direction).
const BLENDED_APPROACH_THROTTLE := 0.5

## Throttle used while in close-range combat (facing target, using lateral thrust).
const BLENDED_COMBAT_THROTTLE := 0.3

## When the blended move vector is this short we treat it as "no meaningful
## intent" and emit zero throttle rather than picking a random heading.
const BLENDED_MOVE_MIN_LENGTH := 0.01

## Convert a directive on ship_data.orders into a per-frame pilot_control struct.
##
## Parameters
##   ship_data : Dictionary — full ship dict; orders.goal_weights etc. must be set
##   target    : Dictionary — target ship_data (may be {} when no target)
##   threats   : Array      — threat dicts; each must carry .position for nearest-threat calc
##   delta     : float      — frame time (unused in geometry — kept for future speed hints)
##
## Returns
##   {desired_heading, throttle, thrust_active, is_braking, lateral_thrust}
##
## This is the live steering path for ships carrying a "tactical" order.
## Multiplier on combined_radii that defines the zone inside which separation
## becomes active. A ship reacts when friendlies are within this many × the
## summed hull sizes. Since ship-ship collisions are not physically resolved,
## separation steering is the ONLY thing keeping hulls apart, so the zone is
## wide enough to give a ship room to arrest its closing velocity by thrust
## alone before hulls would clip.
const SEPARATION_RADIUS_FACTOR    := 6.0

## Base weight of the separation goal in the blend.  At the edge of the
## separation zone the goal is effectively zero; it ramps steeply to
## SEPARATION_WEIGHT at contact (inverse-square curve).  With no collision
## physics as a backstop, this must dominate a full formation+pursue stack
## (0.7 + 0.8 = 1.5) well before contact so converging ships peel apart
## under thrust instead of interpenetrating.
const SEPARATION_WEIGHT           := 10.0

## Velocity damping for separation. The position-only push is an undamped
## spring: a ship accelerates into the gap, overshoots, and oscillates
## through its neighbour. Without collision physics to absorb that, we add a
## term proportional to the closing speed so the push brakes relative motion
## (a damped spring), letting crowded ships ease apart instead of ping-ponging.
const SEPARATION_DAMPING          := 0.22

## How strongly the separation push along the target-bearing axis modulates
## close-range throttle. Lets ships stacked in front of / behind each other on
## the run-in separate via throttle, the only axis available once they face the
## target (lateral thrust handles the perpendicular axis).
const SEPARATION_THROTTLE_FACTOR  := 0.22

## Detection lookahead distance for obstacle avoidance in blended mode.
## Ships start reacting to obstacles within this many pixels of their centre.
const OBSTACLE_AVOID_MARGIN       := 200.0

## Weight of the obstacle-avoidance goal when an obstacle is detected.
## Lower than SEPARATION_WEIGHT (5.0) because obstacles don't move — a ship
## steering away at moderate weight will clear them without jittering.
const OBSTACLE_AVOID_WEIGHT       := 2.0

static func calculate_blended_control(
	ship_data: Dictionary,
	target: Dictionary,
	threats: Array,
	nearby_ships: Array,
	obstacles: Array,
	_delta: float
) -> Dictionary:
	var orders: Dictionary  = ship_data.get("orders", {})
	var weights: Dictionary = orders.get("goal_weights", {})
	var preferred_range: float = orders.get("preferred_range", get_engagement_range(ship_data))

	var w_pursue: float    = weights.get("pursue",     0.0)
	var w_range: float     = weights.get("keep_range", 0.0)
	var w_evade: float     = weights.get("evade",      0.0)
	var w_form: float      = weights.get("formation",  0.0)

	var my_pos: Vector2    = ship_data.get("position", Vector2.ZERO)
	var has_target: bool   = not target.is_empty() and target.has("position")

	# --- 1. Build unit desired-vector per goal ---

	# pursue: toward target (zero when no target)
	var goal_pursue: Vector2 = Vector2.ZERO
	var dist_to_target: float = 0.0
	if has_target:
		var to_target: Vector2 = target.position - my_pos
		dist_to_target = to_target.length()
		if dist_to_target > BLENDED_MOVE_MIN_LENGTH:
			goal_pursue = to_target.normalized()

	# keep_range: radial in/out around preferred_range, deadband in the middle.
	# Combined with pursue this yields orbit-at-range:
	#   small preferred_range → constant inward push → brawl
	#   large preferred_range → outward push when close → kite
	var goal_keep_range: Vector2 = Vector2.ZERO
	if has_target and dist_to_target > BLENDED_MOVE_MIN_LENGTH:
		var deadband: float = preferred_range * BLENDED_RANGE_DEADBAND_FRACTION
		var radial_err: float = dist_to_target - preferred_range
		if abs(radial_err) > deadband:
			# Positive error → too far → move toward target (same direction as pursue)
			# Negative error → too close → move away from target
			var radial_dir: Vector2 = (target.position - my_pos).normalized()
			goal_keep_range = radial_dir if radial_err > 0.0 else -radial_dir

	# evade: away from nearest enemy threat
	var goal_evade: Vector2 = Vector2.ZERO
	if not threats.is_empty():
		var nearest: Dictionary = _nearest_threat(my_pos, threats)
		if nearest.has("position"):
			var away: Vector2 = my_pos - nearest.position
			if away.length() > BLENDED_MOVE_MIN_LENGTH:
				goal_evade = away.normalized()

	# separation: boids-style push away from nearby same-team ships.
	# Inverse-square curve: rises steeply near hull-touch, fades at zone edge
	# so ships form up normally at spacing > combined_radii but are strongly
	# repelled when about to clip.
	#
	# Each neighbor contributes a push vector scaled by (strength * SEPARATION_WEIGHT).
	# We accumulate WITHOUT normalizing so that N neighbors each push independently
	# and the total magnitude grows with crowd density.
	# separation_effective_weight is fixed at 1.0 because the scaling is already
	# baked into goal_separation's magnitude.
	var goal_separation: Vector2 = Vector2.ZERO
	var separation_effective_weight: float = 1.0
	var my_col_radius: float = ship_data.get("collision_radius", 15.0)
	var my_vel: Vector2 = ship_data.get("velocity", Vector2.ZERO)
	# Track the closest neighbor and how deep we are inside its safety margin
	# so we can suppress convergence goals that would pull us closer.
	var min_neighbor_dist: float = INF
	var min_neighbor_combined_radii: float = 0.0
	for other in nearby_ships:
		if other == null or other.get("ship_id","") == ship_data.get("ship_id",""):
			continue
		var to_other: Vector2 = other.get("position", Vector2.ZERO) - my_pos
		var dist: float = to_other.length()
		var other_col_radius: float = other.get("collision_radius", my_col_radius)
		var combined_radii: float = my_col_radius + other_col_radius
		var sep_radius: float = combined_radii * SEPARATION_RADIUS_FACTOR
		if dist < min_neighbor_dist:
			min_neighbor_dist = dist
			min_neighbor_combined_radii = combined_radii
		if dist < sep_radius and dist > BLENDED_MOVE_MIN_LENGTH:
			# t = 0 at zone edge, 1 at contact. Squared gives inverse-square curve.
			var away: Vector2 = -to_other.normalized()
			var t: float = 1.0 - (dist / sep_radius)
			var strength: float = t * t * SEPARATION_WEIGHT
			goal_separation += away * strength
			# Damping: brake the closing velocity so the push eases ships apart
			# rather than springing them through each other (no physics backstop).
			var rel_vel: Vector2 = my_vel - other.get("velocity", Vector2.ZERO)
			var closing: float = -rel_vel.dot(away)  # >0 when closing on this neighbor
			if closing > 0.0:
				goal_separation += away * (closing * SEPARATION_DAMPING * t)
	# No normalize: accumulated magnitude is the influence signal.

	# Convergence-goal suppression: when a neighbor is inside the SEPARATION zone
	# (closer than combined_radii × SEPARATION_RADIUS_FACTOR), scale down any goals
	# that would pull this ship TOWARD that neighbor (formation, pursue, keep_range
	# if pointing inward).  This prevents the vector-cancellation problem where
	# symmetric piles zero out separation and formation wins by default.
	# suppress_t = 0 at zone edge → 1 at contact; convergence goals are scaled by (1 - suppress_t).
	var convergence_suppress: float = 0.0
	if min_neighbor_dist < INF:
		var inner_sep_radius: float = min_neighbor_combined_radii * SEPARATION_RADIUS_FACTOR
		if min_neighbor_dist < inner_sep_radius:
			var t: float = 1.0 - (min_neighbor_dist / inner_sep_radius)
			convergence_suppress = t * t   # 0 at edge, 1 at contact — same curve as separation

	# Apply suppression: scale formation and pursuit down as neighbors get close.
	# At contact (suppress=1) formation is fully zeroed; at zone edge (suppress=0) it's unchanged.
	var effective_w_form: float   = w_form   * (1.0 - convergence_suppress)
	var effective_w_pursue: float = w_pursue * (1.0 - convergence_suppress)
	var effective_w_range: float  = w_range  * (1.0 - convergence_suppress)

	# formation: toward formation_slot, which is an ABSOLUTE world position
	# stamped by FormationSystem each frame (not an offset from anchor_position).
	var goal_formation: Vector2 = Vector2.ZERO
	var slot: Vector2    = orders.get("formation_slot",  Vector2.ZERO)
	if effective_w_form > 0.0:
		var to_slot: Vector2 = slot - my_pos
		if to_slot.length() > BLENDED_MOVE_MIN_LENGTH:
			goal_formation = to_slot.normalized()

	# obstacle avoidance: steer away from blocking obstacles within lookahead margin.
	# Works identically to separation but uses the obstacle's radius for the zone.
	var goal_obstacle: Vector2 = Vector2.ZERO
	var obstacle_effective_weight: float = 0.0
	for obs in obstacles:
		if obs == null or obs.get("status","operational") == "destroyed":
			continue
		if not obs.get("blocks_movement", true):
			continue
		var to_obs: Vector2 = obs.get("position", Vector2.ZERO) - my_pos
		var dist: float = to_obs.length()
		var combined: float = my_col_radius + obs.get("radius", 0.0)
		var detect_dist: float = combined + OBSTACLE_AVOID_MARGIN
		if dist < detect_dist and dist > BLENDED_MOVE_MIN_LENGTH:
			var strength: float = 1.0 - ((dist - combined) / OBSTACLE_AVOID_MARGIN)
			strength = clampf(strength, 0.0, 1.0)
			goal_obstacle -= to_obs.normalized() * strength
			obstacle_effective_weight += strength * OBSTACLE_AVOID_WEIGHT

	if goal_obstacle.length() > BLENDED_MOVE_MIN_LENGTH:
		goal_obstacle = goal_obstacle.normalized()

	# --- 2. Blend ---
	# Separation uses its accumulated magnitude directly (weight=1.0).
	# Convergence goals (pursue, keep_range, formation) use suppressed weights
	# so that proximity pressure fades them out as neighbors approach hull-touch.
	var move: Vector2 = (
		goal_pursue     * effective_w_pursue +
		goal_keep_range * effective_w_range  +
		goal_evade      * w_evade            +
		goal_formation  * effective_w_form   +
		goal_separation * separation_effective_weight +
		goal_obstacle   * obstacle_effective_weight
	)

	# Normalize to a unit direction; if effectively zero, hold current heading.
	if move.length() > BLENDED_MOVE_MIN_LENGTH:
		move = move.normalized()
	else:
		# No intent: hold heading, no thrust
		return {
			"desired_heading": ship_data.get("rotation", 0.0),
			"throttle": 0.0,
			"thrust_active": false,
			"is_braking": false,
			"lateral_thrust": 0.0,
		}

	# --- 3. Facing rule ---
	#
	# facing_mode decouples WHERE the ship POINTS from WHERE it MOVES.
	# Movement (throttle/lateral) always comes from the blended goal vector above.
	#
	# "auto"      — close → face target; far → face move direction.
	# "nose_on"   — always face the target (anchor/brawler/screen: bow armor forward).
	# "broadside" — always face perpendicular to the target bearing (artillery orbit).
	#
	# When no target exists, all modes fall back to facing the move direction.

	var facing_mode: String = ship_data.get("orders", {}).get("facing_mode", "auto")

	var desired_heading: float
	var throttle: float
	var is_braking: bool = false
	var lateral_thrust: float = 0.0

	var at_close_range: bool = has_target and dist_to_target < LATERAL_THRUST_RANGE

	if facing_mode == "broadside" and has_target:
		# Artillery orbit: face perpendicular to the target bearing so side
		# batteries bear. Movement (throttle/lateral) still comes from blended
		# goals, so the ship orbits at preferred_range with its side to the enemy.
		var current_rot: float = ship_data.get("rotation", 0.0)
		desired_heading = _broadside_heading_toward(my_pos, target.position, current_rot)
		# Express the blended move as lateral + throttle relative to the broadside facing.
		var facing_vec: Vector2 = get_visual_forward(desired_heading)
		var right_vec: Vector2  = Vector2(facing_vec.y, -facing_vec.x)
		lateral_thrust = clampf(move.dot(right_vec), -1.0, 1.0)
		# Forward component drives range-keeping (nose is perpendicular, so
		# forward motion is tangential — helps the orbit, not a charge).
		var fwd_component: float = move.dot(facing_vec)
		throttle = clampf(fwd_component, 0.0, 1.0)
		var deadband: float = preferred_range * BLENDED_RANGE_DEADBAND_FRACTION
		if has_target and dist_to_target < preferred_range - deadband:
			is_braking = true
			throttle   = 0.0

	elif facing_mode == "nose_on" and has_target:
		# Anchor/brawler/screen: always point bow at the target regardless of range.
		var to_target: Vector2 = target.position - my_pos
		desired_heading = direction_to_heading(to_target.normalized())
		throttle = BLENDED_COMBAT_THROTTLE
		var facing_vec: Vector2 = get_visual_forward(desired_heading)
		var right_vec: Vector2  = Vector2(facing_vec.y, -facing_vec.x)
		lateral_thrust = clampf(move.dot(right_vec), -1.0, 1.0)
		var deadband: float = preferred_range * BLENDED_RANGE_DEADBAND_FRACTION
		if dist_to_target < preferred_range - deadband:
			is_braking = true
			throttle   = 0.0

	elif at_close_range:
		# "auto" close-range: face the target, use lateral thrust for positioning.
		var to_target: Vector2 = target.position - my_pos
		desired_heading = direction_to_heading(to_target.normalized())

		# Project move direction onto the lateral axis (perpendicular to facing).
		var facing: Vector2 = get_visual_forward(desired_heading)
		var right: Vector2  = Vector2(facing.y, -facing.x)  # 90° clockwise = strafe right
		var lateral_component: float = move.dot(right)
		lateral_thrust = clampf(lateral_component, -1.0, 1.0)

		# Throttle is the combat press, modulated by separation along the facing
		# (bearing) axis. At close range lateral thrust can only separate ships
		# side-to-side; ships stacked along the bearing line must separate via
		# throttle. A friendly dead ahead (negative forward push) backs us off;
		# one behind (positive) pulls us ahead, so the column strings out instead
		# of piling onto the same point in front of the target.
		var fwd_sep: float = goal_separation.dot(facing)
		throttle = clampf(BLENDED_COMBAT_THROTTLE + fwd_sep * SEPARATION_THROTTLE_FACTOR, 0.0, 1.0)

		# Brake if inside preferred_range — keep_range is pushing us out but we
		# overshot; the physical brake stops the inward drift. Skip the brake
		# when separation is pushing us forward (a friendly behind) so we can
		# still pull ahead to clear them.
		var deadband: float = preferred_range * BLENDED_RANGE_DEADBAND_FRACTION
		if has_target and dist_to_target < preferred_range - deadband and fwd_sep <= 0.0:
			is_braking = true
			throttle = 0.0

	else:
		# "auto" far-range (or no target): face the blended move direction, main throttle.
		desired_heading = direction_to_heading(move)
		throttle = BLENDED_APPROACH_THROTTLE
		lateral_thrust = 0.0

	return {
		"desired_heading": desired_heading,
		"throttle":        throttle,
		"thrust_active":   throttle > 0.1,
		"is_braking":      is_braking,
		"lateral_thrust":  lateral_thrust,
	}


## Collect enemy ship positions as lightweight threat dicts for calculate_blended_control.
## Each entry carries .position; target_id is omitted because the is-targeted check
## inside SteeringBlender uses the threats built at decision time, not this per-frame list.
## This list only drives the evade-direction goal in the converter.
static func _gather_enemy_positions(ship_data: Dictionary, all_ships: Array) -> Array:
	var my_team: int = ship_data.get("team", -1)
	var result: Array = []
	for s in all_ships:
		if s.get("team", -1) == my_team: continue
		if s.get("status", "") != "operational": continue
		result.append({ "position": s.get("position", Vector2.ZERO) })
	return result


## Return the threat dict whose position is closest to pos.
## Skips threats without a position key.
static func _nearest_threat(pos: Vector2, threats: Array) -> Dictionary:
	var nearest: Dictionary = {}
	var best_dist: float = INF
	for t in threats:
		if not t.has("position"):
			continue
		var d: float = pos.distance_to(t.position)
		if d < best_dist:
			best_dist = d
			nearest = t
	return nearest
