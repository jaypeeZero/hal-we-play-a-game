extends RefCounted
class_name FighterPilotAI

## FighterPilotAI - Fighter pilot behavior with dynamic wing system
##
## Wing Formation System:
## - Fighters dynamically form Wing-Pairs (2) or Wing-Threes (3) based on proximity
## - Highest-skilled pilot in proximity becomes Lead
## - Lead makes ALL targeting and movement decisions
## - Wingmen's job: stick with Lead (behind & to side), fire at Lead's target
##
## Skill Impact:
## - Lead skill affects: target selection, maneuver quality, prediction accuracy
## - Wingman skill affects: formation tightness, reaction speed, anticipation
##
## Distance-based speed control:
## - Far away (>5000): full speed approach
## - Mid range (1500-5000): slow approach, try to get behind enemy
## - Close range (<800): tight maneuvering (orbits, weaves, loops)
##
## Combat behavior:
## - vs Fighters: get behind enemy, adjust for movement, formation flying
## - vs Corvettes/Capitals: stay at distance, dodge/weave, pot-shots
## - vs Corvettes/Capitals (many fighters): coordinated group runs

## Configuration constants
const GROUP_RUN_THRESHOLD = 4  # Number of fighters needed for coordinated runs
const FORMATION_SPACING = 80.0  # Distance to maintain from wingmates
const BEHIND_ANGLE_TOLERANCE = 20.0  # Degrees - "behind" the enemy
const COLLISION_DETECTION_RANGE = 2000.0

## Wingmate formation constants
const FORMATION_DISTANCE = 80.0  # Ideal distance between wingmates
const FORMATION_BROKEN_DISTANCE = 150.0  # Distance at which formation is considered broken
const FORMATION_ANGLE_OFFSET = 45.0  # Degrees - wingman stays at 45° behind and to the side

## Main decision function - called by CrewAISystem
## Now uses dynamic wing formation system
static func make_decision(crew_data: Dictionary, ship_data: Dictionary, all_ships: Array, all_crew: Array, game_time: float, wings: Array = []) -> Dictionary:
	# DYNAMIC WING SYSTEM: Check if we're in a wing and what role
	var wing_info = WingFormationSystem.get_wing_info(crew_data.get("crew_id", ""), wings)

	if not wing_info.is_empty():
		var role = wing_info.get("role", "")

		if role == "wingman":
			# WINGMAN: Primary job is stick with Lead, secondary is fire at Lead's target
			return _make_wingman_decision(crew_data, ship_data, wing_info, all_ships, all_crew, game_time)
		elif role == "lead":
			# LEAD: Make all tactical decisions for the wing
			return _make_lead_decision(crew_data, ship_data, wing_info, all_ships, all_crew, game_time)

	# NOT IN A WING: Fall back to solo/squadron behavior
	# WINGMATE FORMATION (legacy): Check formation status FIRST - TOP PRIORITY
	# If we're a wingman and formation is broken, rejoin before engaging targets
	var is_wingman = _is_wingman_role(crew_data, all_crew)
	if is_wingman:
		var partner = _find_wingman_partner(crew_data, all_crew, all_ships)
		if not partner.is_empty():
			var partner_ship = partner.get("ship", {})
			if _is_formation_broken(ship_data, partner_ship):
				# Formation broken! Priority #1 is to rejoin
				return _make_rejoin_wingman_decision(crew_data, ship_data, partner_ship, game_time)

	# SQUADRON STRUCTURE: Check if we have a squadron leader to follow
	var target_id = ""
	var is_leader = crew_data.get("is_squadron_leader", false)

	if is_leader:
		# Squadron Leader picks target for the whole squadron
		target_id = _find_best_target(crew_data, all_ships)
	else:
		# Non-leaders follow squadron leader's target
		target_id = _get_squadron_leader_target(crew_data, all_crew)

		# Fallback to own target if leader has no target
		if target_id == "":
			target_id = _find_best_target(crew_data, all_ships)

	if target_id == "":
		return _make_idle_decision(crew_data, game_time)

	var target_ship = _get_ship_by_id(target_id, all_ships)
	if target_ship == null:
		return _make_idle_decision(crew_data, game_time)

	# Determine combat behavior based on target type
	var target_type = target_ship.get("type", "fighter")
	var decision = {}

	if target_type == "fighter" or target_type == "heavy_fighter":
		decision = _make_fighter_vs_fighter_decision(crew_data, ship_data, target_ship, all_ships, all_crew, game_time)
	elif target_type == "corvette" or target_type == "capital":
		decision = _make_fighter_vs_capital_decision(crew_data, ship_data, target_ship, all_ships, all_crew, game_time)
	else:
		decision = _make_pursuit_decision(crew_data, ship_data, target_ship, game_time)

	return decision

# ============================================================================
# DYNAMIC WING SYSTEM - LEAD DECISIONS
# ============================================================================

## Lead makes all targeting and maneuvering decisions for the wing
## Skill heavily influences decision quality
static func _make_lead_decision(crew_data: Dictionary, ship_data: Dictionary, wing_info: Dictionary, all_ships: Array, all_crew: Array, game_time: float) -> Dictionary:
	var wing = wing_info.get("wing", {})
	var skill = crew_data.get("stats", {}).get("skill", 0.5)
	var skills = crew_data.get("stats", {}).get("skills", {})

	# LEAD TARGET SELECTION: Skill affects quality
	var target_id = _find_best_target_for_wing(crew_data, wing, all_ships, all_crew)

	if target_id == "":
		return _make_idle_decision(crew_data, game_time)

	var target_ship = _get_ship_by_id(target_id, all_ships)
	if target_ship.is_empty():
		return _make_idle_decision(crew_data, game_time)

	# Determine combat behavior based on target type
	var target_type = target_ship.get("type", "fighter")
	var decision = {}

	if target_type == "fighter" or target_type == "heavy_fighter":
		decision = _make_fighter_vs_fighter_decision(crew_data, ship_data, target_ship, all_ships, all_crew, game_time)
	elif target_type == "corvette" or target_type == "capital":
		decision = _make_fighter_vs_capital_decision(crew_data, ship_data, target_ship, all_ships, all_crew, game_time)
	else:
		decision = _make_pursuit_decision(crew_data, ship_data, target_ship, game_time)

	# Mark this as a lead decision so wingmen know to follow
	decision["is_wing_lead"] = true
	decision["wing_id"] = wing.get("lead_crew_id", "")

	return decision

## Find best target for the wing - Lead's skill affects selection quality
static func _find_best_target_for_wing(crew_data: Dictionary, wing: Dictionary, all_ships: Array, all_crew: Array) -> String:
	var skill = crew_data.get("stats", {}).get("skill", 0.5)
	var situational_awareness = crew_data.get("stats", {}).get("skills", {}).get("situational_awareness", skill)
	var aggression = crew_data.get("stats", {}).get("skills", {}).get("aggression", skill)

	var awareness = crew_data.get("awareness", {})
	var threats = awareness.get("threats", [])
	var opportunities = awareness.get("opportunities", [])

	# Low skill lead: Target fixation (stick with current target even if bad)
	if skill < WingConstants.LEAD_TARGET_FIXATION_SKILL:
		var locked_target = crew_data.get("combat_state", {}).get("locked_target_id", "")
		if locked_target != "" and _is_ship_valid(locked_target, all_ships):
			return locked_target

	# Build list of potential targets with scores
	var targets_with_scores = []

	for ship in all_ships:
		var ship_team = ship.get("team", -1)
		var my_team = wing.get("team", -1)
		if ship_team == my_team or ship_team < 0:
			continue  # Same team or invalid
		if ship.get("status", "") != "operational":
			continue

		var ship_id = ship.get("ship_id", "")
		var score = _calculate_target_score(crew_data, ship, all_ships, all_crew)
		targets_with_scores.append({"id": ship_id, "score": score})

	if targets_with_scores.is_empty():
		return ""

	# High skill lead: Pick best target
	# Low skill lead: Pick somewhat randomly (poor assessment)
	if skill >= WingConstants.LEAD_PICK_BEST_SKILL:
		# Sort by score, pick best
		targets_with_scores.sort_custom(func(a, b): return a.score > b.score)
		return targets_with_scores[0].id
	elif skill >= WingConstants.LEAD_PICK_TOP_THREE_SKILL:
		# Pick from top 3
		targets_with_scores.sort_custom(func(a, b): return a.score > b.score)
		var max_idx = mini(3, targets_with_scores.size())
		return targets_with_scores[randi() % max_idx].id
	else:
		# Low skill: Random target (poor assessment)
		return targets_with_scores[randi() % targets_with_scores.size()].id

## Calculate target score based on lead's skills
static func _calculate_target_score(crew_data: Dictionary, target_ship: Dictionary, all_ships: Array, all_crew: Array) -> float:
	var skill = crew_data.get("stats", {}).get("skill", 0.5)
	var my_ship_id = crew_data.get("assigned_ship_id", "")
	var my_ship = _get_ship_by_id(my_ship_id, all_ships)
	var my_pos = my_ship.get("position", Vector2.ZERO) if not my_ship.is_empty() else Vector2.ZERO

	var target_pos = target_ship.get("position", Vector2.ZERO)
	var distance = my_pos.distance_to(target_pos)

	var score = 0.0

	# Closer targets score higher (easier to engage)
	score += max(0, WingConstants.TARGET_SCORE_DISTANCE_MAX - distance) / WingConstants.TARGET_SCORE_DISTANCE_DIVISOR

	# Damaged targets score higher (easier kills) - only high skill leads notice this
	if skill >= WingConstants.LEAD_NOTICE_DAMAGED_SKILL:
		var hull = target_ship.get("stats", {}).get("hull", {})
		var hull_current = hull.get("current", 100)
		var hull_max = hull.get("max", 100)
		var damage_ratio = 1.0 - (float(hull_current) / float(hull_max))
		score += damage_ratio * WingConstants.TARGET_SCORE_DAMAGED_WEIGHT

	# Targets already engaged by friendlies score higher (concentrate fire)
	# Only medium+ skill leads coordinate this well
	if skill >= WingConstants.LEAD_COORDINATE_FIRE_SKILL:
		var friendly_count = _count_friendlies_engaging(target_ship.get("ship_id", ""), all_crew)
		score += friendly_count * WingConstants.TARGET_SCORE_FRIENDLY_ENGAGING_WEIGHT

	# Targets that are a threat (facing us) score higher - situational awareness
	var situational_awareness = crew_data.get("stats", {}).get("skills", {}).get("situational_awareness", skill)
	if situational_awareness >= WingConstants.LEAD_NOTICE_THREATS_SKILL:
		var target_rotation = target_ship.get("rotation", 0.0)
		var target_facing = Vector2(cos(target_rotation), sin(target_rotation))
		var to_me = (my_pos - target_pos).normalized()
		var facing_angle = abs(target_facing.angle_to(to_me))
		if facing_angle < deg_to_rad(WingConstants.TARGET_SCORE_THREAT_FACING_ANGLE):
			score += WingConstants.TARGET_SCORE_THREAT_FACING_WEIGHT

	return score

## Count how many friendlies are engaging a target
static func _count_friendlies_engaging(target_id: String, all_crew: Array) -> int:
	var count = 0
	for crew in all_crew:
		var orders = crew.get("orders", {}).get("current", {})
		if orders.get("target_id", "") == target_id:
			count += 1
	return count

# ============================================================================
# DYNAMIC WING SYSTEM - WINGMAN DECISIONS
# ============================================================================

## Wingman's primary job: stick with Lead, secondary: fire at Lead's target
## Skill affects how well they maintain formation
static func _make_wingman_decision(crew_data: Dictionary, ship_data: Dictionary, wing_info: Dictionary, all_ships: Array, all_crew: Array, game_time: float) -> Dictionary:
	var wing = wing_info.get("wing", {})
	var position_side = wing_info.get("position_side", 1)
	var skill = crew_data.get("stats", {}).get("skill", 0.5)

	var lead_ship_id = wing.get("lead_ship_id", "")
	var lead_ship = _get_ship_by_id(lead_ship_id, all_ships)

	if lead_ship.is_empty() or lead_ship.get("status", "") != "operational":
		# Lead is gone - fall back to solo behavior
		return _make_solo_fallback_decision(crew_data, ship_data, all_ships, all_crew, game_time)

	# Check if we're in formation with Lead
	var in_formation = WingFormationSystem.is_in_formation(ship_data, lead_ship, skill)

	if not in_formation:
		# PRIORITY #1: Rejoin Lead
		return _make_wing_rejoin_decision(crew_data, ship_data, lead_ship, position_side, skill, game_time)

	# In formation - follow Lead's target and maneuvers
	var lead_target_id = WingFormationSystem.get_lead_target(wing, all_crew)
	var lead_maneuver = WingFormationSystem.get_lead_maneuver(wing, all_crew)

	if lead_target_id == "":
		# Lead has no target - maintain formation while idle
		return _make_wing_follow_decision(crew_data, ship_data, lead_ship, position_side, skill, "", game_time)

	var target_ship = _get_ship_by_id(lead_target_id, all_ships)
	if target_ship.is_empty():
		return _make_wing_follow_decision(crew_data, ship_data, lead_ship, position_side, skill, "", game_time)

	# Engage Lead's target while maintaining formation
	return _make_wing_engage_decision(crew_data, ship_data, lead_ship, target_ship, position_side, skill, lead_maneuver, game_time)

## Wingman rejoins Lead when out of formation
static func _make_wing_rejoin_decision(crew_data: Dictionary, ship_data: Dictionary, lead_ship: Dictionary, position_side: int, skill: float, game_time: float) -> Dictionary:
	var formation_pos = WingFormationSystem.calculate_wing_position(lead_ship, position_side, skill)

	# Decision frequency based on skill - high skill checks more often
	var delay = lerp(0.5, 0.2, skill)

	return {
		"type": "maneuver",
		"subtype": "fight_wing_rejoin",
		"crew_id": crew_data.get("crew_id", ""),
		"entity_id": ship_data.get("ship_id", ""),
		"target_id": lead_ship.get("ship_id", ""),
		"formation_position": formation_pos,
		"position_side": position_side,
		"skill_factor": skill,
		"delay": delay,
		"timestamp": game_time,
		"is_wingman": true
	}

## Wingman follows Lead while idle (no target)
static func _make_wing_follow_decision(crew_data: Dictionary, ship_data: Dictionary, lead_ship: Dictionary, position_side: int, skill: float, lead_maneuver: String, game_time: float) -> Dictionary:
	var formation_pos = WingFormationSystem.calculate_wing_position(lead_ship, position_side, skill)

	# Delay based on skill
	var delay = lerp(0.8, 0.3, skill)

	return {
		"type": "maneuver",
		"subtype": "fight_wing_follow",
		"crew_id": crew_data.get("crew_id", ""),
		"entity_id": ship_data.get("ship_id", ""),
		"target_id": lead_ship.get("ship_id", ""),
		"formation_position": formation_pos,
		"position_side": position_side,
		"lead_maneuver": lead_maneuver,
		"skill_factor": skill,
		"delay": delay,
		"timestamp": game_time,
		"is_wingman": true
	}

## Wingman engages Lead's target while trying to maintain formation
static func _make_wing_engage_decision(crew_data: Dictionary, ship_data: Dictionary, lead_ship: Dictionary, target_ship: Dictionary, position_side: int, skill: float, lead_maneuver: String, game_time: float) -> Dictionary:
	var formation_pos = WingFormationSystem.calculate_wing_position(lead_ship, position_side, skill)
	var target_id = target_ship.get("ship_id", "")

	# High skill wingman balances formation with engagement
	# Low skill wingman may break formation to chase target
	var formation_priority = skill  # 0.0 = ignores formation, 1.0 = tight formation

	# Decision frequency - more frequent when engaging
	var delay = lerp(0.4, 0.2, skill)

	return {
		"type": "maneuver",
		"subtype": "fight_wing_engage",
		"crew_id": crew_data.get("crew_id", ""),
		"entity_id": ship_data.get("ship_id", ""),
		"target_id": target_id,
		"lead_ship_id": lead_ship.get("ship_id", ""),
		"formation_position": formation_pos,
		"position_side": position_side,
		"lead_maneuver": lead_maneuver,
		"formation_priority": formation_priority,
		"skill_factor": skill,
		"delay": delay,
		"timestamp": game_time,
		"is_wingman": true
	}

## Fallback to solo behavior when Lead is lost
static func _make_solo_fallback_decision(crew_data: Dictionary, ship_data: Dictionary, all_ships: Array, all_crew: Array, game_time: float) -> Dictionary:
	var target_id = _find_best_target(crew_data, all_ships)

	if target_id == "":
		return _make_idle_decision(crew_data, game_time)

	var target_ship = _get_ship_by_id(target_id, all_ships)
	if target_ship.is_empty():
		return _make_idle_decision(crew_data, game_time)

	var target_type = target_ship.get("type", "fighter")

	if target_type == "fighter" or target_type == "heavy_fighter":
		return _make_fighter_vs_fighter_decision(crew_data, ship_data, target_ship, all_ships, all_crew, game_time)
	elif target_type == "corvette" or target_type == "capital":
		return _make_fighter_vs_capital_decision(crew_data, ship_data, target_ship, all_ships, all_crew, game_time)
	else:
		return _make_pursuit_decision(crew_data, ship_data, target_ship, game_time)

## Fighter vs Fighter combat
static func _make_fighter_vs_fighter_decision(crew_data: Dictionary, ship_data: Dictionary, target_ship: Dictionary, all_ships: Array, all_crew: Array, game_time: float) -> Dictionary:
	var my_pos = ship_data.get("position", Vector2.ZERO)
	var target_pos = target_ship.get("position", Vector2.ZERO)
	var distance = my_pos.distance_to(target_pos)

	# Get skill early - needed for prediction accuracy
	var skill = crew_data.get("stats", {}).get("skill", 0.5)
	var anticipation = crew_data.get("stats", {}).get("skills", {}).get("anticipation", skill)
	var aggression = crew_data.get("stats", {}).get("skills", {}).get("aggression", skill)

	# Dynamic distance thresholds based on aggression
	# Aggressive (1.0): closer thresholds (close faster)
	# Cautious (0.0): farther thresholds (stay distant)
	# Ranges derived from weapon data via CombatRangeCalculator
	var base_far = CombatRangeCalculator.get_fighter_far_range(ship_data)
	var base_close = CombatRangeCalculator.get_fighter_close_range(ship_data)

	var far_range = base_far * (1.4 - aggression * 0.8)
	# aggression 0.0 = 140% of base far range (hangs back)
	# aggression 0.5 = 100% of base far range (normal)
	# aggression 1.0 = 60% of base far range (charges in)

	var close_range = base_close * (1.2 - aggression * 0.4)
	# aggression 0.0 = 120% of base close range (stays distant)
	# aggression 0.5 = 100% of base close range (normal)
	# aggression 1.0 = 80% of base close range (presses in)

	# Try to get behind the enemy
	var behind_position = _calculate_behind_position(target_ship, anticipation, ship_data)
	var is_behind = _am_i_behind_target(ship_data, target_ship)

	# Check formation status with wingmates
	var wingmates = _find_wingmates(crew_data, all_crew, all_ships)
	var formation_offset = _calculate_formation_offset(crew_data, wingmates, all_ships)
	var maneuver_type = ""
	var target_id = target_ship.get("ship_id", "")

	# Check for incoming collision threat
	var on_collision_course = _is_on_collision_course(ship_data, target_ship)

	# Check if enemy is behind me (disadvantageous position)
	var enemy_behind_me = _am_i_in_front_of_target(ship_data, target_ship)

	if enemy_behind_me:
		# Panic behavior when disadvantaged - varies by composure and stress
		var composure = crew_data.get("stats", {}).get("skills", {}).get("composure", skill)
		var stress = crew_data.get("stats", {}).get("stress", 0.0)

		# Effective composure degrades under stress
		# At stress 0.5: composure is halved
		# At stress 1.0: composure is zero
		var effective_composure = composure * (1.0 - stress * 0.5)

		if effective_composure < 0.3:
			# Panic - fly straight (worst choice - easy target)
			maneuver_type = "fight_pursue_full_speed"
		elif effective_composure < 0.6:
			# Basic evasion - hard turn (predictable but better)
			maneuver_type = "fight_evasive_turn"
		else:
			# Skilled evasion - break and scissors (unpredictable)
			maneuver_type = "fight_defensive_break"
	elif skill < 0.3:
		# Rookie: only knows pursue_full_speed, ignores collision warnings
		maneuver_type = "fight_pursue_full_speed"
	elif skill < 0.6:
		# Average: pursue_full_speed + tight_pursuit, still ignores collision warnings
		if distance > far_range:
			maneuver_type = "fight_pursue_full_speed"
		elif is_behind:
			# Can do tight pursuit when already behind
			maneuver_type = "fight_pursue_tactical" if distance > close_range else "fight_tight_pursuit"
		else:
			# Can't flank, just chase
			maneuver_type = "fight_pursue_full_speed"
	else:
		# Skilled (>= 0.6): full tactical repertoire + collision awareness
		if on_collision_course and distance > close_range:
			# Detect head-on collision - break perpendicular and accelerate past
			# Don't try to orbit, just get out of the way fast
			maneuver_type = "fight_lateral_break"
		elif distance > far_range:
			maneuver_type = "fight_pursue_full_speed"
		elif distance > close_range:
			# Mid range - slow approach, try to get behind
			maneuver_type = "fight_pursue_tactical" if is_behind else "fight_flank_behind"
		else:
			# Close range - tight maneuvering
			maneuver_type = "fight_tight_pursuit" if is_behind else "fight_dogfight_maneuver"

	# Calculate evasion direction for dodge maneuvers
	var evasion_direction = 0
	if maneuver_type in ["fight_dodge_and_weave", "fight_lateral_break"]:
		evasion_direction = _calculate_evasion_direction(ship_data, target_ship)

	# Apply formation offset if we have wingmates
	var decision = {
		"type": "maneuver",
		"subtype": maneuver_type,
		"crew_id": crew_data.get("crew_id", ""),
		"entity_id": ship_data.get("ship_id", ""),
		"target_id": target_id,
		"skill_factor": crew_data.get("stats", {}).get("skill", 0.5),
		"delay": crew_data.get("stats", {}).get("reaction_time", 0.1),
		"timestamp": game_time,
		"formation_offset": formation_offset,
		"behind_position": behind_position,
		"evasion_direction": evasion_direction
	}

	return decision

## Fighter vs Corvette/Capital combat
static func _make_fighter_vs_capital_decision(crew_data: Dictionary, ship_data: Dictionary, target_ship: Dictionary, all_ships: Array, all_crew: Array, game_time: float) -> Dictionary:
	var my_pos = ship_data.get("position", Vector2.ZERO)
	var target_pos = target_ship.get("position", Vector2.ZERO)
	var distance = my_pos.distance_to(target_pos)

	# Count friendly fighters nearby
	var nearby_fighters = _count_nearby_friendly_fighters(ship_data, all_ships)

	var maneuver_type = ""
	var target_id = target_ship.get("ship_id", "")

	# Get ranges from weapon data
	var safe_distance = CombatRangeCalculator.get_safe_distance_vs_capital(ship_data)
	var close_range = CombatRangeCalculator.get_fighter_close_range(ship_data)

	# If we have enough fighters, coordinate group runs
	if nearby_fighters >= GROUP_RUN_THRESHOLD:
		# Group run tactics
		if distance > safe_distance:
			# Approach for run
			maneuver_type = "fight_group_run_approach"
		elif distance > close_range:
			# Execute attack run
			maneuver_type = "fight_group_run_attack"
		else:
			# Too close, swing around
			maneuver_type = "fight_group_run_swing_around"
	else:
		# Solo/small group tactics - stay at distance, pot-shots
		if distance < safe_distance * 0.7:
			# Too close, evade
			maneuver_type = "fight_evasive_retreat"
		elif distance > safe_distance * 1.3:
			# Too far, close in
			maneuver_type = "fight_cautious_approach"
		else:
			# Good range, dodge and weave
			maneuver_type = "fight_dodge_and_weave"

	var decision = {
		"type": "maneuver",
		"subtype": maneuver_type,
		"crew_id": crew_data.get("crew_id", ""),
		"entity_id": ship_data.get("ship_id", ""),
		"target_id": target_id,
		"skill_factor": crew_data.get("stats", {}).get("skill", 0.5),
		"delay": crew_data.get("stats", {}).get("reaction_time", 0.1),
		"timestamp": game_time,
		"nearby_fighters": nearby_fighters
	}

	return decision

## Check if we're behind the target
static func _am_i_behind_target(my_ship: Dictionary, target_ship: Dictionary) -> bool:
	var my_pos = my_ship.get("position", Vector2.ZERO)
	var target_pos = target_ship.get("position", Vector2.ZERO)
	var target_rotation = target_ship.get("rotation", 0.0)

	# Vector from target to me
	var to_me = (my_pos - target_pos).normalized()

	# Target's facing direction
	var target_facing = Vector2(cos(target_rotation), sin(target_rotation))

	# If I'm behind, angle between target's facing and vector to me should be ~180 degrees
	var angle_diff = rad_to_deg(target_facing.angle_to(to_me))

	# Behind is 180 degrees +/- tolerance
	return abs(abs(angle_diff) - 180.0) < BEHIND_ANGLE_TOLERANCE

## Check if target is behind me (I'm in front of target - disadvantageous position)
static func _am_i_in_front_of_target(my_ship: Dictionary, target_ship: Dictionary) -> bool:
	var my_pos = my_ship.get("position", Vector2.ZERO)
	var target_pos = target_ship.get("position", Vector2.ZERO)
	var my_rotation = my_ship.get("rotation", 0.0)

	# Vector from me to target
	var to_target = (target_pos - my_pos).normalized()

	# My facing direction
	var my_facing = Vector2(cos(my_rotation), sin(my_rotation))

	# If target is behind me, angle between my facing and vector to target should be ~180 degrees
	var angle_diff = rad_to_deg(my_facing.angle_to(to_target))

	# In front means target is behind (180 degrees +/- tolerance)
	return abs(abs(angle_diff) - 180.0) < BEHIND_ANGLE_TOLERANCE

## Calculate position behind target (for pursuit)
## Now uses anticipation skill with error margin for low-skill pilots
static func _calculate_behind_position(target_ship: Dictionary, anticipation: float = 0.5, own_ship: Dictionary = {}) -> Vector2:
	var target_pos = target_ship.get("position", Vector2.ZERO)
	var target_rotation = target_ship.get("rotation", 0.0)
	var target_velocity = target_ship.get("velocity", Vector2.ZERO)

	# Position behind target at ideal weapons range (not too close!)
	# Use halfway between MIN_COMBAT_RANGE and CLOSE_RANGE for good firing position
	var min_range = CombatRangeCalculator.get_fighter_min_combat_range(own_ship) if not own_ship.is_empty() else 300.0
	var close_range = CombatRangeCalculator.get_fighter_close_range(own_ship) if not own_ship.is_empty() else 800.0
	var ideal_distance = (min_range + close_range) / 2.0
	var behind_offset = Vector2(cos(target_rotation + PI), sin(target_rotation + PI)) * ideal_distance

	# Prediction lookahead scales with anticipation skill
	# 0.0 anticipation = 0.1s ahead
	# 0.5 anticipation = 0.3s ahead
	# 1.0 anticipation = 0.8s ahead
	var prediction_time = lerp(0.1, 0.8, anticipation)

	var predicted_pos = target_pos + target_velocity * prediction_time

	# Low anticipation adds prediction error (missing where target actually is)
	var error_magnitude = (1.0 - anticipation) * 100.0  # 0-100 units of error
	var error_angle = randf_range(0, TAU)
	var error_offset = Vector2(cos(error_angle), sin(error_angle)) * error_magnitude

	return predicted_pos + behind_offset + error_offset

## Get squadron leader's target
static func _get_squadron_leader_target(crew_data: Dictionary, all_crew: Array) -> String:
	# Find squadron leader via command chain
	var leader_id = crew_data.get("command_chain", {}).get("superior", "")
	if leader_id == "":
		return ""

	# Find leader in crew list
	for crew in all_crew:
		if crew.get("crew_id", "") == leader_id:
			# Get leader's current target from their orders
			var leader_orders = crew.get("orders", {}).get("current", {})
			return leader_orders.get("target_id", "")

	return ""

## Find wingmates (other fighters on same team)
static func _find_wingmates(crew_data: Dictionary, all_crew: Array, all_ships: Array) -> Array:
	var wingmates = []
	var my_ship_id = crew_data.get("assigned_ship_id", "")
	var my_ship = _get_ship_by_id(my_ship_id, all_ships)
	if my_ship == null:
		return wingmates

	var my_team = my_ship.get("team", -1)
	var my_pair = crew_data.get("wingman_pair", -1)

	# Prioritize wingman pair first
	if my_pair >= 0:
		# Find specific wingman in same pair
		for crew in all_crew:
			if crew.get("crew_id", "") == crew_data.get("crew_id", ""):
				continue
			if crew.get("wingman_pair", -1) != my_pair:
				continue

			var crew_ship_id = crew.get("assigned_ship_id", "")
			var crew_ship = _get_ship_by_id(crew_ship_id, all_ships)
			if crew_ship != null and crew_ship.get("status", "") == "operational":
				wingmates.append(crew_ship)

	# Then add other squadron members
	for ship in all_ships:
		if ship.get("ship_id", "") == my_ship_id:
			continue
		if ship.get("team", -1) != my_team:
			continue
		var ship_type = ship.get("type", "")
		if ship_type != "fighter" and ship_type != "heavy_fighter":
			continue
		if ship.get("status", "") != "operational":
			continue

		# Don't duplicate wingman pair
		var already_added = false
		for wingmate in wingmates:
			if wingmate.get("ship_id", "") == ship.get("ship_id", ""):
				already_added = true
				break

		if not already_added:
			wingmates.append(ship)

	return wingmates

## Calculate formation offset to maintain spacing
static func _calculate_formation_offset(crew_data: Dictionary, wingmates: Array, all_ships: Array) -> Vector2:
	if wingmates.is_empty():
		return Vector2.ZERO

	var my_ship_id = crew_data.get("assigned_ship_id", "")
	var my_ship = _get_ship_by_id(my_ship_id, all_ships)
	if my_ship == null:
		return Vector2.ZERO

	var my_pos = my_ship.get("position", Vector2.ZERO)
	var my_pair = crew_data.get("wingman_pair", -1)
	var offset = Vector2.ZERO

	# WINGMAN PAIR FORMATION: Maintain tight spacing with your wingman
	# wingmates[0] is your wingman pair partner (if they exist)
	# Others are squadron members to avoid

	for i in range(wingmates.size()):
		var wingmate = wingmates[i]
		var wingmate_pos = wingmate.get("position", Vector2.ZERO)
		var distance = my_pos.distance_to(wingmate_pos)

		# First wingmate is your pair partner - maintain closer formation
		if i == 0 and my_pair >= 0:
			# Maintain 80 unit spacing with wingman (tighter than others)
			var desired_spacing = 80.0
			if distance > desired_spacing * 1.3:
				# Too far from wingman, pull closer
				var direction = (wingmate_pos - my_pos).normalized()
				var strength = (distance - desired_spacing) / desired_spacing
				offset += direction * strength * 50.0
			elif distance < desired_spacing * 0.7 and distance > 0:
				# Too close to wingman, push away slightly
				var direction = (my_pos - wingmate_pos).normalized()
				var strength = (desired_spacing - distance) / desired_spacing
				offset += direction * strength * 30.0
		else:
			# Other squadron members - maintain standard spacing
			if distance < FORMATION_SPACING and distance > 0:
				# Push away from other fighters
				var direction = (my_pos - wingmate_pos).normalized()
				var strength = (FORMATION_SPACING - distance) / FORMATION_SPACING
				offset += direction * strength * 100.0

	return offset

## Count nearby friendly fighters
static func _count_nearby_friendly_fighters(my_ship: Dictionary, all_ships: Array) -> int:
	var my_pos = my_ship.get("position", Vector2.ZERO)
	var my_team = my_ship.get("team", -1)
	var my_id = my_ship.get("ship_id", "")
	var count = 0

	# Count nearby fighters within 1.5x safe distance from capitals
	var safe_distance = CombatRangeCalculator.get_safe_distance_vs_capital(my_ship)
	var nearby_range = safe_distance * 1.5

	for ship in all_ships:
		if ship.get("ship_id", "") == my_id:
			continue
		if ship.get("team", -1) != my_team:
			continue
		var ship_type = ship.get("type", "")
		if ship_type != "fighter" and ship_type != "heavy_fighter":
			continue
		if ship.get("status", "") != "operational":
			continue

		var distance = my_pos.distance_to(ship.get("position", Vector2.ZERO))
		if distance < nearby_range:
			count += 1

	return count

## Find best target from awareness
static func _find_best_target(crew_data: Dictionary, all_ships: Array) -> String:
	var skill = crew_data.get("stats", {}).get("skill", 0.5)
	var awareness = crew_data.get("awareness", {})
	var threats = awareness.get("threats", [])
	var opportunities = awareness.get("opportunities", [])

	# Rookie: stick with current target if valid and alive (target fixation)
	if skill < 0.3:
		var locked_target = crew_data.get("combat_state", {}).get("locked_target_id", "")
		if locked_target != "" and _is_ship_valid(locked_target, all_ships):
			return locked_target  # Tunnel vision - don't re-evaluate

	# Normal target selection for average+ pilots
	var selected_target = ""

	# Prefer threats (enemy fighters)
	if not threats.is_empty():
		var threat = threats[0]
		if threat is Dictionary:
			selected_target = threat.get("id", "")
		else:
			selected_target = threat

	# Fall back to opportunities
	if selected_target == "" and not opportunities.is_empty():
		var opportunity = opportunities[0]
		if opportunity is Dictionary:
			selected_target = opportunity.get("id", "")
		else:
			selected_target = opportunity

	# Lock in target for rookies (for next decision cycle)
	if skill < 0.3 and selected_target != "":
		crew_data.get("combat_state", {})["locked_target_id"] = selected_target

	return selected_target

## Get ship by ID
static func _get_ship_by_id(ship_id: String, all_ships: Array) -> Dictionary:
	for ship in all_ships:
		if ship.get("ship_id", "") == ship_id:
			return ship
	return {}

## Check if a ship is valid (exists and is alive)
static func _is_ship_valid(ship_id: String, all_ships: Array) -> bool:
	var ship = _get_ship_by_id(ship_id, all_ships)
	return not ship.is_empty() and ship.get("status", "") != "destroyed"

## Make idle decision
static func _make_idle_decision(crew_data: Dictionary, game_time: float) -> Dictionary:
	return {
		"type": "maneuver",
		"subtype": "idle",
		"crew_id": crew_data.get("crew_id", ""),
		"entity_id": crew_data.get("assigned_ship_id", ""),
		"target_id": "",
		"skill_factor": crew_data.get("stats", {}).get("skill", 0.5),
		"delay": 2.0,  # Check again in 2 seconds
		"timestamp": game_time
	}

## Make basic pursuit decision
static func _make_pursuit_decision(crew_data: Dictionary, ship_data: Dictionary, target_ship: Dictionary, game_time: float) -> Dictionary:
	return {
		"type": "maneuver",
		"subtype": "pursue",
		"crew_id": crew_data.get("crew_id", ""),
		"entity_id": ship_data.get("ship_id", ""),
		"target_id": target_ship.get("ship_id", ""),
		"skill_factor": crew_data.get("stats", {}).get("skill", 0.5),
		"delay": crew_data.get("stats", {}).get("reaction_time", 0.1),
		"timestamp": game_time
	}

# ============================================================================
# WINGMATE FORMATION SYSTEM
# ============================================================================

## Find wingman partner (the other member of the wingman pair)
static func _find_wingman_partner(crew_data: Dictionary, all_crew: Array, all_ships: Array) -> Dictionary:
	var my_pair = crew_data.get("wingman_pair", -1)
	if my_pair < 0:
		return {}  # Not in a wingman pair

	var my_crew_id = crew_data.get("crew_id", "")

	# Find the other pilot in the same wingman pair
	for crew in all_crew:
		if crew.get("crew_id", "") == my_crew_id:
			continue
		if crew.get("wingman_pair", -1) != my_pair:
			continue

		# Found our wingman partner - get their ship
		var partner_ship_id = crew.get("assigned_ship_id", "")
		var partner_ship = _get_ship_by_id(partner_ship_id, all_ships)

		if partner_ship != null and partner_ship.get("status", "") == "operational":
			return {
				"crew": crew,
				"ship": partner_ship
			}

	return {}  # Partner not found or not operational

## Check if this pilot is the wingman (not the lead) in their pair
## In each pair, the pilot with the lower squadron_rank is the lead
static func _is_wingman_role(crew_data: Dictionary, all_crew: Array) -> bool:
	var my_pair = crew_data.get("wingman_pair", -1)
	if my_pair < 0:
		return false  # Not in a wingman pair

	var my_rank = crew_data.get("squadron_rank", 999)
	var my_crew_id = crew_data.get("crew_id", "")

	# Find partner's rank
	for crew in all_crew:
		if crew.get("crew_id", "") == my_crew_id:
			continue
		if crew.get("wingman_pair", -1) != my_pair:
			continue

		var partner_rank = crew.get("squadron_rank", 999)
		# If partner has lower rank, they are the lead, so we are the wingman
		return partner_rank < my_rank

	return false  # No partner found, default to not wingman

## Check if formation with wingman is broken
static func _is_formation_broken(ship_data: Dictionary, partner_ship: Dictionary) -> bool:
	if partner_ship.is_empty():
		return false  # No partner, no formation to break

	var my_pos = ship_data.get("position", Vector2.ZERO)
	var partner_pos = partner_ship.get("position", Vector2.ZERO)
	var distance = my_pos.distance_to(partner_pos)

	return distance > FORMATION_BROKEN_DISTANCE

## Calculate ideal formation position relative to lead
## Wingman should be behind and to the side of the lead
static func _calculate_formation_position(lead_ship: Dictionary, offset_side: int = 1) -> Vector2:
	var lead_pos = lead_ship.get("position", Vector2.ZERO)
	var lead_velocity = lead_ship.get("velocity", Vector2.ZERO)

	# Use velocity direction if moving, otherwise use rotation
	var lead_heading: float
	if lead_velocity.length() > 10.0:
		lead_heading = lead_velocity.angle()
	else:
		lead_heading = lead_ship.get("rotation", 0.0)

	# Calculate position behind and to the side
	# offset_side: 1 = right, -1 = left
	var angle_offset = deg_to_rad(FORMATION_ANGLE_OFFSET) * offset_side
	var formation_angle = lead_heading + PI + angle_offset  # Behind and to the side

	var formation_offset = Vector2(cos(formation_angle), sin(formation_angle)) * FORMATION_DISTANCE

	# Predict lead's future position based on velocity
	var predicted_lead_pos = lead_pos + lead_velocity * 0.5

	return predicted_lead_pos + formation_offset

## Make rejoin wingman decision - TOP PRIORITY when formation is broken
static func _make_rejoin_wingman_decision(crew_data: Dictionary, ship_data: Dictionary, partner_ship: Dictionary, game_time: float) -> Dictionary:
	# Calculate formation position
	var formation_pos = _calculate_formation_position(partner_ship)

	return {
		"type": "maneuver",
		"subtype": "fight_rejoin_wingman",
		"crew_id": crew_data.get("crew_id", ""),
		"entity_id": ship_data.get("ship_id", ""),
		"target_id": partner_ship.get("ship_id", ""),  # Target is the lead ship
		"formation_position": formation_pos,
		"skill_factor": crew_data.get("stats", {}).get("skill", 0.5),
		"delay": 0.3,  # Check frequently when rejoining
		"timestamp": game_time
	}

# ============================================================================
# COLLISION DETECTION & EVASION
# ============================================================================

## Detect if we're on a collision course with target
## Returns true if closing distance and distance is short enough
static func _is_on_collision_course(my_ship: Dictionary, target_ship: Dictionary) -> bool:
	var my_pos = my_ship.get("position", Vector2.ZERO)
	var target_pos = target_ship.get("position", Vector2.ZERO)
	var my_velocity = my_ship.get("velocity", Vector2.ZERO)
	var target_velocity = target_ship.get("velocity", Vector2.ZERO)

	var to_target = target_pos - my_pos
	var distance = to_target.length()

	# If within collision detection range, check for closing velocity
	if distance > COLLISION_DETECTION_RANGE:
		return false  # Too far away to be a threat

	# Calculate relative velocity (how fast we're closing)
	# my_velocity - target_velocity gives positive dot product when approaching
	var relative_velocity = my_velocity - target_velocity
	var closing_speed = relative_velocity.dot(to_target.normalized())

	# Positive closing_speed means we're approaching each other
	if closing_speed > 50.0:  # Threshold to avoid false positives from slow drift
		return true

	return false

## Calculate which direction to evade (1 = right, -1 = left)
## Skilled pilots pick a deliberate side based on tactical advantage
static func _calculate_evasion_direction(my_ship: Dictionary, target_ship: Dictionary) -> int:
	var my_pos = my_ship.get("position", Vector2.ZERO)
	var target_pos = target_ship.get("position", Vector2.ZERO)
	var my_velocity = my_ship.get("velocity", Vector2.ZERO)
	var target_velocity = target_ship.get("velocity", Vector2.ZERO)

	var to_target = target_pos - my_pos

	# Calculate perpendicular vector (right side of approach vector)
	var perpendicular_right = Vector2(-to_target.y, to_target.x).normalized()

	# Check which side the target is moving toward
	# Evade to the OPPOSITE side to get behind them
	var target_lateral_movement = target_velocity.dot(perpendicular_right)

	# If target is drifting right, we go left (and vice versa)
	# This sets us up to end up behind them after the pass
	if target_lateral_movement > 10.0:
		return -1  # Go left
	elif target_lateral_movement < -10.0:
		return 1   # Go right
	else:
		# Target not drifting laterally - pick based on our own velocity
		# Evade in the direction we're already slightly moving
		var my_lateral = my_velocity.dot(perpendicular_right)
		return 1 if my_lateral >= 0 else -1
