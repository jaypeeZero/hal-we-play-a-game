extends RefCounted
class_name CorvettePilotAI

## CorvettePilotAI - Corvette pilot behavior
##
## Corvettes are medium combat ships with:
## - Moderate firepower (multiple turrets)
## - Better armor/hull than fighters
## - Slower than fighters but more survivable
## - Multi-crew (captain gives orders to pilot)
##
## Core Skills (0.0-1.0):
## - aggression: How close they want to get. High = charges in, Low = stays back
## - composure: How well they perform under fire. Degrades with stress
## - helmsmanship: Ship handling. Affects maneuver variety and evasion quality
##
## Skill Thresholds:
## - Low (< 0.3): Basic pursue only, no evasion, panics when damaged
## - Medium (0.3-0.6): Can evade, adjusts range, basic threat response
## - High (>= 0.6): Complex evasion, optimal positioning, anticipates threats
##
## Maneuver types: pursue, evade, broadside, kite, retreat

## Configuration constants
const SAFE_DISTANCE_VS_FIGHTERS = 1000.0  # Keep away from fighter swarms
const PANIC_THRESHOLD_BASE = 0.6       # Hull % at which to panic
const FORMATION_SPACING = 150.0        # Distance to maintain from wingmates

## Main decision function
static func make_decision(crew_data: Dictionary, ship_data: Dictionary, all_ships: Array, all_crew: Array, game_time: float) -> Dictionary:
	var awareness = crew_data.awareness

	# If no targets at all, idle
	if awareness.opportunities.is_empty() and awareness.threats.is_empty():
		return _make_idle_decision(crew_data, game_time)

	# Extract skills with fallback defaults
	var skills = crew_data.stats.get("skills", {})
	var aggression = skills.get("aggression", 0.5)
	var composure = skills.get("composure", 0.5)
	var helmsmanship = skills.get("helmsmanship", 0.5)

	# Determine panic state based on ship damage and composure
	var hull_integrity = _get_hull_integrity(ship_data)
	var panic_threshold = _calculate_panic_threshold(composure)
	var is_panicked = hull_integrity < panic_threshold

	# Threat assessment
	var top_threat = awareness.threats[0] if not awareness.threats.is_empty() else null
	var top_opportunity = awareness.opportunities[0] if not awareness.opportunities.is_empty() else null

	# Decision priority:
	# 1. If panicked, retreat
	# 2. If damaged and under fire, evaluate evasion vs stand-and-fight
	# 3. If have targets, decide on range and positioning
	# 4. Otherwise idle

	if is_panicked and top_threat != null:
		return _make_retreat_decision(crew_data, ship_data, top_threat, helmsmanship, game_time)

	# Under fire but not panicked - choose between evade and fight
	if top_threat != null:
		var threat_distance = _get_distance_to_target(ship_data, top_threat)
		var threat_is_fighter = _is_fighter_type(top_threat)

		# Fighters are more dangerous at close range - prioritize evasion vs fighters
		if threat_is_fighter:
			var evasion_threshold = SAFE_DISTANCE_VS_FIGHTERS + (aggression * 500.0)
			if threat_distance < evasion_threshold and composure < 0.7:
				return _make_evade_decision(crew_data, ship_data, top_threat, helmsmanship, game_time)

		# Under fire from non-fighters - if low composure, evade
		if composure < 0.4:
			return _make_evade_decision(crew_data, ship_data, top_threat, helmsmanship, game_time)

	# Have targets - decide on engagement
	if top_opportunity != null:
		var opportunity_distance = _get_distance_to_target(ship_data, top_opportunity)

		# Decide on maneuver based on distance and skills
		var broadside_distance = CombatRangeCalculator.get_broadside_optimal_distance(ship_data)
		if opportunity_distance < broadside_distance + (helmsmanship * 500.0):
			# Close enough for broadside
			if helmsmanship >= 0.6:
				return _make_broadside_decision(crew_data, ship_data, top_opportunity, game_time)
			else:
				return _make_pursue_decision(crew_data, ship_data, top_opportunity, aggression, game_time)
		else:
			# Too far - approach based on aggression
			return _make_pursue_decision(crew_data, ship_data, top_opportunity, aggression, game_time)

	return _make_idle_decision(crew_data, game_time)

## Pursue target with distance scaling by aggression
static func _make_pursue_decision(crew_data: Dictionary, ship_data: Dictionary, target: Dictionary, aggression: float, game_time: float) -> Dictionary:
	var effective_skill = _calculate_effective_skill(crew_data)
	var base_engage_range = CombatRangeCalculator.get_base_engagement_range(ship_data)
	var engage_range = base_engage_range * (0.5 + aggression)  # scales with aggression

	# Aggressive pilots want closer engagement
	var subtype = "pursue"

	var decision = {
		"type": "maneuver",
		"subtype": subtype,
		"crew_id": crew_data.crew_id,
		"entity_id": crew_data.assigned_to,
		"target_id": target.id,
		"skill_factor": effective_skill,
		"engage_range": engage_range,
		"delay": _calculate_decision_delay(crew_data, "pursuit"),
		"timestamp": game_time
	}

	return _finalize_decision(crew_data, decision)

## Evade incoming threats
static func _make_evade_decision(crew_data: Dictionary, ship_data: Dictionary, threat: Dictionary, helmsmanship: float, game_time: float) -> Dictionary:
	var effective_skill = _calculate_effective_skill(crew_data)

	# Helmsmanship determines evasion quality (stored in decision data, subtype is always "evade")
	var subtype = "evade"

	var decision = {
		"type": "maneuver",
		"subtype": subtype,
		"crew_id": crew_data.crew_id,
		"entity_id": crew_data.assigned_to,
		"threat_id": threat.id,
		"skill_factor": effective_skill,
		"evasion_quality": helmsmanship,
		"delay": _calculate_decision_delay(crew_data, "evasion"),
		"timestamp": game_time
	}

	return _finalize_decision(crew_data, decision)

## Broadside positioning for optimal fire
static func _make_broadside_decision(crew_data: Dictionary, ship_data: Dictionary, target: Dictionary, game_time: float) -> Dictionary:
	var effective_skill = _calculate_effective_skill(crew_data)

	var decision = {
		"type": "maneuver",
		"subtype": "broadside",
		"crew_id": crew_data.crew_id,
		"entity_id": crew_data.assigned_to,
		"target_id": target.id,
		"optimal_distance": CombatRangeCalculator.get_broadside_optimal_distance(ship_data),
		"skill_factor": effective_skill,
		"delay": _calculate_decision_delay(crew_data, "broadside"),
		"timestamp": game_time
	}

	return _finalize_decision(crew_data, decision)

## Kite enemy - keep distance and fire
static func _make_kite_decision(crew_data: Dictionary, ship_data: Dictionary, target: Dictionary, helmsmanship: float, game_time: float) -> Dictionary:
	var effective_skill = _calculate_effective_skill(crew_data)

	var decision = {
		"type": "maneuver",
		"subtype": "kite",
		"crew_id": crew_data.crew_id,
		"entity_id": crew_data.assigned_to,
		"target_id": target.id,
		"maintain_distance": CombatRangeCalculator.get_evasion_range(ship_data),
		"skill_factor": effective_skill,
		"maneuver_quality": helmsmanship,
		"delay": _calculate_decision_delay(crew_data, "kite"),
		"timestamp": game_time
	}

	return _finalize_decision(crew_data, decision)

## Retreat from overwhelming threats
static func _make_retreat_decision(crew_data: Dictionary, ship_data: Dictionary, threat: Dictionary, helmsmanship: float, game_time: float) -> Dictionary:
	var effective_skill = _calculate_effective_skill(crew_data)

	var decision = {
		"type": "maneuver",
		"subtype": "retreat",
		"crew_id": crew_data.crew_id,
		"entity_id": crew_data.assigned_to,
		"threat_id": threat.id,
		"skill_factor": effective_skill,
		"retreat_quality": helmsmanship,
		"delay": _calculate_decision_delay(crew_data, "retreat"),
		"timestamp": game_time
	}

	return _finalize_decision(crew_data, decision)

## Idle - no targets
static func _make_idle_decision(crew_data: Dictionary, game_time: float) -> Dictionary:
	var decision = {
		"type": "maneuver",
		"subtype": "idle",
		"crew_id": crew_data.crew_id,
		"entity_id": crew_data.assigned_to,
		"skill_factor": 0.5,
		"delay": 2.0,  # Check less frequently when idle
		"timestamp": game_time
	}

	return _finalize_decision(crew_data, decision)

## Finalize decision with updated crew state
static func _finalize_decision(crew_data: Dictionary, decision: Dictionary) -> Dictionary:
	var updated = crew_data.duplicate(true)
	updated.next_decision_time = decision.timestamp + decision.delay
	updated.orders.current = decision

	return {
		"crew_data": updated,
		"decision": decision
	}

## Helper: Get hull integrity (0.0-1.0)
static func _get_hull_integrity(ship_data: Dictionary) -> float:
	if ship_data.is_empty():
		return 1.0

	var current_hp = ship_data.get("current_hp", 100.0)
	var max_hp = ship_data.get("max_hp", 100.0)

	return clamp(current_hp / max_hp, 0.0, 1.0) if max_hp > 0 else 1.0

## Helper: Calculate panic threshold based on composure
static func _calculate_panic_threshold(composure: float) -> float:
	# High composure pilots stay calm, low composure pilots panic easily
	# composure 0.0 -> panic at 60% damage (40% hull)
	# composure 0.5 -> panic at 30% damage (70% hull)
	# composure 1.0 -> panic at 10% damage (90% hull)
	return max(0.1, PANIC_THRESHOLD_BASE * (1.0 - composure))

## Helper: Get distance to target (returns large value if no target)
static func _get_distance_to_target(ship_data: Dictionary, target: Dictionary) -> float:
	if ship_data.is_empty() or target.is_empty():
		return 10000.0

	var ship_pos = ship_data.get("position", Vector2.ZERO)
	var target_pos = target.get("position", Vector2.ZERO)

	return ship_pos.distance_to(target_pos)

## Helper: Check if target is a fighter type
static func _is_fighter_type(target: Dictionary) -> bool:
	var target_type = target.get("type", "unknown")
	return target_type in ["fighter", "heavy_fighter"]

## Helper: Calculate effective skill with stress/fatigue penalties
static func _calculate_effective_skill(crew_data: Dictionary) -> float:
	var base_skill = crew_data.stats.get("skill", 0.5)
	var stress = crew_data.stats.get("stress", 0.0)
	var fatigue = crew_data.stats.get("fatigue", 0.0)

	var stress_penalty = stress * 0.3
	var fatigue_penalty = fatigue * 0.2

	return max(0.1, base_skill - stress_penalty - fatigue_penalty)

## Helper: Calculate decision delay based on action type and crew state
static func _calculate_decision_delay(crew_data: Dictionary, action_type: String) -> float:
	var base_delay: float
	match action_type:
		"pursuit":
			base_delay = 0.5
		"evasion":
			base_delay = 0.3
		"broadside":
			base_delay = 0.4
		"kite":
			base_delay = 0.6
		"retreat":
			base_delay = 0.2
		_:
			base_delay = 1.0

	# Stress increases decision delay
	var stress = crew_data.stats.get("stress", 0.0)
	var stress_multiplier = 1.0 + (stress * 0.5)

	return base_delay * stress_multiplier
