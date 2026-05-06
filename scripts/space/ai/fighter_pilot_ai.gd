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
## - Wingman skill affects: formation tightness, reaction speed, prediction
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
const FAR_RANGE = 5000.0  # Distance beyond which we use full speed approach
const MID_RANGE = 1500.0  # Mid range threshold for tactical maneuvering
const CLOSE_RANGE = 800.0  # Distance for tight maneuvering (ideal weapons range)
const MIN_COMBAT_RANGE = 300.0  # Minimum safe combat distance - don't get closer than this
const SAFE_DISTANCE_VS_CAPITAL = 2500.0  # Stay at distance vs big ships
const GROUP_RUN_THRESHOLD = 4  # Number of fighters needed for coordinated runs
const FORMATION_SPACING = 80.0  # Distance to maintain from wingmates
const BEHIND_ANGLE_TOLERANCE = 20.0  # Degrees - "behind" the enemy
const COLLISION_DETECTION_RANGE = 2000.0

## ENGAGEMENT-CYCLE FSM — emulates the hit-and-run rhythm of real dogfights.
## A pilot does NOT stay locked on a target; they make a firing pass, extend
## out, swing around, and re-engage from a new angle. Without this, fighters
## just grind on each other in place.
##
## Phases:
##   approach     — closing, target not yet in firing zone (default)
##   firing_pass  — target in arc + range; face & shoot
##   extending    — pass over: break briefly to re-cock the engagement
##   repositioning— turn back toward target for the next pass
##
## Aggression modulates timing so pilots have rhythm:
##   aggressive pilots stay on the trigger longer, extend less
##   cautious pilots break early, extend wider
const ENGAGE_FIRE_RANGE = 1800.0          # Within this, firing pass is viable
const ENGAGE_OVERSHOOT_RANGE = 350.0      # If we get this close, force break
const ENGAGE_ARC_DOT = 0.78               # cos(~39°) — "in my engagement zone"
const ENGAGE_FACING_DOT = 0.5             # cos(60°) — "I'm pointed back at target"
const ENGAGE_FIRING_PASS_BASE_DURATION = 2.5
const ENGAGE_EXTEND_BASE_DURATION = 1.4
const ENGAGE_EXTEND_DISTANCE = 1300.0
const ENGAGE_REPOSITION_TIMEOUT = 4.0
const ENGAGE_AGGRESSION_TIMING_SPREAD = 1.5  # x at agg=1.0, /x at agg=0.0

## TACTICAL BREAK — interrupt that fires regardless of phase.
## If an enemy has me in their close-range firing arc (i.e. they're behind me
## with their nose on my back), break sharply. This is the "stay out of enemy
## firing arcs" priority.
const TACTICAL_BREAK_RANGE = 700.0
const TACTICAL_BREAK_ARC_DOT = 0.85       # cos(~32°) — they have me in arc

## Approach style enum for skill-based maneuvering
enum ApproachStyle {
	DIRECT,            # Fly straight at target (low skill)
	ANGLED,            # Approach from offset angle (medium skill)
	PURSUIT_CURVE,     # Lead/lag pursuit with jinking (high skill)
	DEFENSIVE_SPIRAL,  # Break contact, reposition (high skill, disadvantaged)
	ATTACK_RUN         # Press advantage with evasion (high skill, advantaged)
}

# ============================================================================
# KNOWLEDGE-DRIVEN DECISION MAKING
# ============================================================================

## Generate situation string for knowledge query based on combat context
static func _generate_fighter_situation(ship_data: Dictionary, target_ship: Dictionary, context: Dictionary) -> String:
	var parts = ["fighter"]  # Always include role

	# Target type
	var target_type = target_ship.get("type", "fighter")
	if FleetDataManager.is_large_ship(target_type):
		parts.append("capital")
		parts.append(target_type)
	else:
		# All fighter-class ships treated the same for knowledge queries
		parts.append("fighter")

	# Calculate distance
	var my_pos = ship_data.get("position", Vector2.ZERO)
	var target_pos = target_ship.get("position", Vector2.ZERO)
	var distance = my_pos.distance_to(target_pos)

	# Distance category
	if distance > FAR_RANGE:
		parts.append("far")
		parts.append("approach")
	elif distance > MID_RANGE:
		parts.append("mid")
		parts.append("range")
	elif distance > CLOSE_RANGE:
		parts.append("close")
	else:
		parts.append("very_close")
		parts.append("dogfight")

	# Position advantage
	if _am_i_behind_target(ship_data, target_ship):
		parts.append("behind")
		parts.append("advantage")
	elif _am_i_in_front_of_target(ship_data, target_ship):
		parts.append("disadvantaged")
		parts.append("enemy")
		parts.append("behind")
	else:
		parts.append("neutral")

	# Collision detection
	if _is_on_collision_course(ship_data, target_ship):
		parts.append("collision")
		parts.append("head")
		parts.append("on")

	# Group context
	var nearby = context.get("nearby_fighters", 0)
	if nearby >= GROUP_RUN_THRESHOLD:
		parts.append("group")
		parts.append("coordinated")
	elif nearby >= 1:
		parts.append("wingman")
		parts.append("support")
	else:
		parts.append("solo")

	return " ".join(parts)

## Select best maneuver from knowledge based on crew skills
static func _select_maneuver_from_knowledge(knowledge: Dictionary, crew_data: Dictionary) -> String:
	var skill = crew_data.get("stats", {}).get("skills", {}).get("piloting", 0.5)
	var composure = crew_data.get("stats", {}).get("skills", {}).get("composure", skill)
	var stress = crew_data.get("stats", {}).get("stress", 0.0)

	# Effective composure degrades under stress
	var effective_composure = composure * (1.0 - stress * 0.5)

	var content = knowledge.get("content", {})
	var maneuvers = content.get("maneuvers", [])
	var skill_requirements = content.get("skill_requirements", {})
	var composure_requirements = content.get("composure_requirements", {})

	if maneuvers.is_empty():
		return "idle"

	# Filter to maneuvers this pilot can execute
	var available = []
	for m in maneuvers:
		var required_skill = skill_requirements.get(m, 0.0)
		var required_composure = composure_requirements.get(m, 0.0)

		if skill >= required_skill and effective_composure >= required_composure:
			available.append(m)

	# Pick best available (first in list is highest priority)
	if available.size() > 0:
		return available[0]

	# Fallback to simplest (last in list)
	return maneuvers[-1]

## Query knowledge system for fighter situation and return best maneuver
static func _query_fighter_knowledge(situation: String, crew_data: Dictionary) -> String:
	var knowledge_results = TacticalKnowledgeSystem.query_pilot_knowledge(situation, 3)

	if knowledge_results.is_empty():
		return ""

	# Try each knowledge result in order of relevance
	for knowledge in knowledge_results:
		var maneuver = _select_maneuver_from_knowledge(knowledge, crew_data)
		if maneuver != "" and maneuver != "idle":
			return maneuver

	# Check first result even if it returned idle
	if knowledge_results.size() > 0:
		return _select_maneuver_from_knowledge(knowledge_results[0], crew_data)

	return ""

## Wingmate formation constants
const FORMATION_DISTANCE = 80.0  # Ideal distance between wingmates
const FORMATION_BROKEN_DISTANCE = 150.0  # Distance at which formation is considered broken
const FORMATION_ANGLE_OFFSET = 45.0  # Degrees - wingman stays at 45° behind and to the side

## Main decision function - called by CrewAISystem
## Now uses dynamic wing formation system
static func make_decision(crew_data: Dictionary, ship_data: Dictionary, all_ships: Array, all_crew: Array, game_time: float, wings: Array = []) -> Dictionary:
	# SELF-PRESERVATION OVERLAY (highest background priority).
	# Every pilot's mental thread is "stay alive" — they'll throw their life
	# away only when there's no better option. Modulated by aggression so
	# personalities show: heroic pilots hold the line through bad odds, timid
	# ones break off the moment the local picture turns sour. Squadron orders,
	# wing duties, and individual targeting all defer to this.
	var survival_mode = _assess_survival_state(crew_data, ship_data, all_ships)
	if survival_mode != "":
		return _make_survival_decision(crew_data, ship_data, all_ships, survival_mode, game_time)

	# AREA LEASH (hard override). The physics layer applies a gentle heading
	# pull when a ship drifts outside its assigned area. That's enough for
	# pilots in maneuvers that already thrust (approach, repositioning), but
	# combat-orbit maneuvers run at ~zero throttle, so without an AI-level
	# kick, a ship stuck dogfighting at the edge of the zone never actually
	# returns. When a pilot is well outside their leash, they drop the fight
	# and burn home until they're back in zone.
	if _is_far_outside_area(ship_data):
		return _make_return_to_area_decision(crew_data, ship_data, game_time)

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

	if FleetDataManager.is_fighter_class(target_type):
		decision = _make_fighter_vs_fighter_decision(crew_data, ship_data, target_ship, all_ships, all_crew, game_time)
	elif FleetDataManager.is_large_ship(target_type):
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
	var skill = crew_data.get("stats", {}).get("skills", {}).get("piloting", 0.5)
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

	if FleetDataManager.is_fighter_class(target_type):
		decision = _make_fighter_vs_fighter_decision(crew_data, ship_data, target_ship, all_ships, all_crew, game_time)
	elif FleetDataManager.is_large_ship(target_type):
		decision = _make_fighter_vs_capital_decision(crew_data, ship_data, target_ship, all_ships, all_crew, game_time)
	else:
		decision = _make_pursuit_decision(crew_data, ship_data, target_ship, game_time)

	# Mark this as a lead decision so wingmen know to follow
	decision["is_wing_lead"] = true
	decision["wing_id"] = wing.get("lead_crew_id", "")

	return decision

## Find best target for the wing - Lead's skill affects selection quality.
##
## ENGAGEMENT COMMITMENT — once a lead picks a target, they stick with it for
## several seconds. Without this, every decision tick the scoring shifts (as
## friendlies move and the deconfliction penalty changes), the lead picks a
## different "best" target, and the engagement-cycle FSM keeps resetting to
## the approach phase. Pilots end up grinding on whatever's closest forever.
##
## Aggression scales the lock duration so personalities show: aggressive
## pilots commit longer to a kill, cautious ones reassess sooner.
static func _find_best_target_for_wing(crew_data: Dictionary, wing: Dictionary, all_ships: Array, all_crew: Array) -> String:
	var skill = crew_data.get("stats", {}).get("skills", {}).get("piloting", 0.5)
	var aggression = crew_data.get("stats", {}).get("skills", {}).get("aggression", skill)
	var combat_state: Dictionary = crew_data.get("combat_state", {})

	var awareness = crew_data.get("awareness", {})
	var threats = awareness.get("threats", [])
	var opportunities = awareness.get("opportunities", [])

	# Engagement commitment — keep the locked target unless it's invalid.
	# Lock expiry is implicit: cleared when the locked ship dies or escapes.
	var locked_target: String = combat_state.get("locked_target_id", "")
	var locked_until: float = combat_state.get("target_locked_until", 0.0)
	var current_game_time: float = Time.get_ticks_msec() / 1000.0
	if locked_target != "" and _is_ship_valid(locked_target, all_ships) and current_game_time < locked_until:
		return locked_target
	# Low skill lead: extreme target fixation (stick with current target even
	# if "stale") — they don't reassess at all once committed.
	if skill < WingConstants.LEAD_TARGET_FIXATION_SKILL:
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
	var picked: String = ""
	if skill >= WingConstants.LEAD_PICK_BEST_SKILL:
		targets_with_scores.sort_custom(func(a, b): return a.score > b.score)
		picked = targets_with_scores[0].id
	elif skill >= WingConstants.LEAD_PICK_TOP_THREE_SKILL:
		targets_with_scores.sort_custom(func(a, b): return a.score > b.score)
		var max_idx = mini(3, targets_with_scores.size())
		picked = targets_with_scores[randi() % max_idx].id
	else:
		picked = targets_with_scores[randi() % targets_with_scores.size()].id

	# Lock the newly picked target — duration scales with aggression.
	if picked != "":
		var lock_duration: float = lerp(4.0, 8.0, aggression)
		combat_state["locked_target_id"] = picked
		combat_state["target_locked_until"] = current_game_time + lock_duration
	return picked

## Calculate target score based on lead's skills
static func _calculate_target_score(crew_data: Dictionary, target_ship: Dictionary, all_ships: Array, all_crew: Array) -> float:
	var skill = crew_data.get("stats", {}).get("skills", {}).get("piloting", 0.5)
	var my_ship_id = crew_data.get("assigned_to", "")
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

	# COORDINATION DOCTRINE — depends on target type:
	#   Fighter target  → DECONFLICT (split targets across wings; WW2 doctrine).
	#   Large-ship target → CONCENTRATE FIRE (pile on; capitals need overwhelming force).
	# Without deconfliction, every wing scores the same closest fighter
	# highest and combat degenerates into a swarm. With it, wings naturally
	# pair off against distinct enemies — 3 dogfights instead of one scrum.
	var my_crew_id: String = crew_data.get("crew_id", "")
	var other_engager_count: int = _count_friendlies_engaging(target_ship.get("ship_id", ""), all_crew, my_crew_id)
	var target_type: String = target_ship.get("type", "")
	if FleetDataManager.is_large_ship(target_type):
		# Concentrate fire on big ships — only mid+ skill leads coordinate this
		if skill >= WingConstants.LEAD_COORDINATE_FIRE_SKILL:
			score += other_engager_count * WingConstants.TARGET_SCORE_FRIENDLY_ENGAGING_WEIGHT
	elif skill >= WingConstants.LEAD_DECONFLICT_SKILL:
		# Spread engagement across enemy fighters — penalty per existing engager
		score -= other_engager_count * WingConstants.TARGET_SCORE_DECONFLICTION_PENALTY

	# Targets that are a threat (facing us) score higher - situational awareness
	var awareness_skill = crew_data.get("stats", {}).get("skills", {}).get("awareness", skill)
	if awareness_skill >= WingConstants.LEAD_NOTICE_THREATS_SKILL:
		var target_rotation = target_ship.get("rotation", 0.0)
		var target_facing = Vector2(cos(target_rotation), sin(target_rotation))
		var to_me = (my_pos - target_pos).normalized()
		var facing_angle = abs(target_facing.angle_to(to_me))
		if facing_angle < deg_to_rad(WingConstants.TARGET_SCORE_THREAT_FACING_ANGLE):
			score += WingConstants.TARGET_SCORE_THREAT_FACING_WEIGHT

	# SQUADRON COMMAND BIAS — when this lead's squadron commander has a focus
	# target, prefer it. This is what makes "squadron leader's orders" matter:
	# wings in a squadron converge on the commander's call instead of each
	# picking independently. The bonus is tunable so it competes with — but
	# doesn't dominate — distance and deconfliction; survival still trumps it
	# (the survival overlay short-circuits before scoring).
	var squadron_focus_id: String = _get_squadron_leader_target(crew_data, all_crew)
	if squadron_focus_id != "" and target_ship.get("ship_id", "") == squadron_focus_id:
		score += WingConstants.TARGET_SCORE_SQUADRON_FOCUS_BONUS

	return score

## Count how many friendlies are engaging a target. Pass `exclude_crew_id`
## to skip a specific crew (typically the one doing the scoring) so the
## evaluator doesn't double-count themselves.
static func _count_friendlies_engaging(target_id: String, all_crew: Array, exclude_crew_id: String = "") -> int:
	var count = 0
	for crew in all_crew:
		if exclude_crew_id != "" and crew.get("crew_id", "") == exclude_crew_id:
			continue
		var crew_orders = crew.get("orders")
		if crew_orders == null:
			continue
		var current = crew_orders.get("current")
		if current == null or not current is Dictionary:
			continue
		if current.get("target_id", "") == target_id:
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
	var slot_rank = wing_info.get("slot_rank", 0)
	var skill = crew_data.get("stats", {}).get("skills", {}).get("piloting", 0.5)

	var lead_ship_id = wing.get("lead_ship_id", "")
	var lead_ship = _get_ship_by_id(lead_ship_id, all_ships)

	if lead_ship.is_empty() or lead_ship.get("status", "") != "operational":
		# Lead is gone - fall back to solo behavior
		return _make_solo_fallback_decision(crew_data, ship_data, all_ships, all_crew, game_time)

	# Check if we're in formation with Lead
	var in_formation = WingFormationSystem.is_in_formation(ship_data, lead_ship, skill)

	if not in_formation:
		# PRIORITY #1: Rejoin Lead
		return _make_wing_rejoin_decision(crew_data, ship_data, lead_ship, position_side, slot_rank, skill, game_time)

	# In formation - follow Lead's target and maneuvers
	var lead_target_id = WingFormationSystem.get_lead_target(wing, all_crew)
	var lead_maneuver = WingFormationSystem.get_lead_maneuver(wing, all_crew)

	if lead_target_id == "":
		# Lead has no target - maintain formation while idle
		return _make_wing_follow_decision(crew_data, ship_data, lead_ship, position_side, slot_rank, skill, "", game_time)

	var target_ship = _get_ship_by_id(lead_target_id, all_ships)
	if target_ship.is_empty():
		return _make_wing_follow_decision(crew_data, ship_data, lead_ship, position_side, slot_rank, skill, "", game_time)

	# WING-LEVEL ENGAGEMENT CYCLE — wingmen follow the lead's phase so the
	# whole wing makes a firing pass, extends, repositions, and re-engages
	# together. Without this, only the lead cycles while the wingmen grind
	# on the target indefinitely.
	var lead_phase: String = _get_lead_engagement_phase(wing, all_crew)
	if lead_phase == "extending":
		# Break with the lead — extend away from the engagement
		return _make_wing_extend_decision(crew_data, ship_data, target_ship, lead_ship, skill, game_time)
	if lead_phase == "repositioning":
		# Turn back toward target with the lead
		return _make_wing_reposition_decision(crew_data, ship_data, target_ship, lead_ship, skill, game_time)

	# Default: engage the lead's target while maintaining formation
	return _make_wing_engage_decision(crew_data, ship_data, lead_ship, target_ship, position_side, slot_rank, skill, lead_maneuver, game_time)

## Read the lead's current engagement phase so the wing can fly the cycle as a unit.
static func _get_lead_engagement_phase(wing: Dictionary, all_crew: Array) -> String:
	var lead_crew_id: String = wing.get("lead_crew_id", "")
	if lead_crew_id == "":
		return "approach"
	for crew in all_crew:
		if crew.get("crew_id", "") == lead_crew_id:
			return crew.get("combat_state", {}).get("engagement_phase", "approach")
	return "approach"

## Wingman follows the lead through the EXTEND phase — break briefly from the target.
static func _make_wing_extend_decision(crew_data: Dictionary, ship_data: Dictionary, target_ship: Dictionary, lead_ship: Dictionary, skill: float, game_time: float) -> Dictionary:
	return {
		"type": "maneuver",
		"subtype": "fight_evasive_retreat",
		"crew_id": crew_data.get("crew_id", ""),
		"entity_id": ship_data.get("ship_id", ""),
		"target_id": target_ship.get("ship_id", ""),
		"lead_ship_id": lead_ship.get("ship_id", ""),
		"skill_factor": skill,
		"delay": 0.3,
		"timestamp": game_time,
		"is_wingman": true
	}

## Wingman follows the lead through the REPOSITION phase — turn back to re-engage.
static func _make_wing_reposition_decision(crew_data: Dictionary, ship_data: Dictionary, target_ship: Dictionary, lead_ship: Dictionary, skill: float, game_time: float) -> Dictionary:
	return {
		"type": "maneuver",
		"subtype": "fight_pursue_tactical",
		"crew_id": crew_data.get("crew_id", ""),
		"entity_id": ship_data.get("ship_id", ""),
		"target_id": target_ship.get("ship_id", ""),
		"lead_ship_id": lead_ship.get("ship_id", ""),
		"skill_factor": skill,
		"delay": 0.3,
		"timestamp": game_time,
		"is_wingman": true
	}

## Wingman rejoins Lead when out of formation
static func _make_wing_rejoin_decision(crew_data: Dictionary, ship_data: Dictionary, lead_ship: Dictionary, position_side: int, slot_rank: int, skill: float, game_time: float) -> Dictionary:
	var formation_pos = WingFormationSystem.calculate_wing_position(lead_ship, position_side, skill, slot_rank)

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
static func _make_wing_follow_decision(crew_data: Dictionary, ship_data: Dictionary, lead_ship: Dictionary, position_side: int, slot_rank: int, skill: float, lead_maneuver: String, game_time: float) -> Dictionary:
	var formation_pos = WingFormationSystem.calculate_wing_position(lead_ship, position_side, skill, slot_rank)

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
static func _make_wing_engage_decision(crew_data: Dictionary, ship_data: Dictionary, lead_ship: Dictionary, target_ship: Dictionary, position_side: int, slot_rank: int, skill: float, lead_maneuver: String, game_time: float) -> Dictionary:
	var formation_pos = WingFormationSystem.calculate_wing_position(lead_ship, position_side, skill, slot_rank)
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

	if FleetDataManager.is_fighter_class(target_type):
		return _make_fighter_vs_fighter_decision(crew_data, ship_data, target_ship, all_ships, all_crew, game_time)
	elif FleetDataManager.is_large_ship(target_type):
		return _make_fighter_vs_capital_decision(crew_data, ship_data, target_ship, all_ships, all_crew, game_time)
	else:
		return _make_pursuit_decision(crew_data, ship_data, target_ship, game_time)

## Fighter vs Fighter combat - KNOWLEDGE-DRIVEN with SKILL-BASED APPROACH
static func _make_fighter_vs_fighter_decision(crew_data: Dictionary, ship_data: Dictionary, target_ship: Dictionary, all_ships: Array, all_crew: Array, game_time: float) -> Dictionary:
	var my_pos = ship_data.get("position", Vector2.ZERO)
	var target_pos = target_ship.get("position", Vector2.ZERO)
	var distance = my_pos.distance_to(target_pos)

	# Get skill for prediction accuracy
	var skill = crew_data.get("stats", {}).get("skills", {}).get("piloting", 0.5)
	var aim = crew_data.get("stats", {}).get("skills", {}).get("aim", skill)

	# Calculate behind position for pursuit maneuvers
	var behind_position = _calculate_behind_position(target_ship, aim)

	# Check formation status with wingmates
	var wingmates = _find_wingmates(crew_data, all_crew, all_ships)
	var formation_offset = _calculate_formation_offset(crew_data, wingmates, all_ships)

	# Determine position advantage for approach style selection
	var position_advantage = "neutral"
	if _am_i_behind_target(ship_data, target_ship):
		position_advantage = "behind"
	elif _am_i_in_front_of_target(ship_data, target_ship):
		position_advantage = "disadvantaged"

	# SKILL-BASED APPROACH: Select approach style and calculate jink params
	var aggression = crew_data.get("stats", {}).get("skills", {}).get("aggression", 0.5)
	var approach_style = _select_approach_style(skill, position_advantage, aggression)
	var jink_params = _calculate_jink_params(skill)
	var approach_angle = _calculate_approach_angle(skill)

	# Build context for knowledge query
	var context = {
		"nearby_fighters": wingmates.size()
	}

	# Generate situation string and query knowledge
	var situation = _generate_fighter_situation(ship_data, target_ship, context)
	var maneuver_type = _query_fighter_knowledge(situation, crew_data)

	# Fallback to basic pursuit if no knowledge match
	if maneuver_type == "" or maneuver_type == "idle":
		maneuver_type = "fight_pursue_full_speed"

	# ENGAGEMENT-CYCLE OVERRIDE — drive the firing-pass / extend / reposition
	# rhythm. The phase machine OVERRIDES the knowledge-driven maneuver pick
	# during firing_pass / extending / repositioning so pilots actually break
	# off and re-engage instead of grinding on a target.
	#
	# A tactical break (enemy on my six) takes priority over the cycle: drop
	# everything and shake them off.
	var phase_info: Dictionary = _step_engagement_phase(crew_data, ship_data, target_ship, game_time)
	var phase: String = phase_info.phase
	var threat_on_six: Dictionary = _check_threat_on_my_six(ship_data, all_ships)
	if not threat_on_six.is_empty():
		# Break sharply away from whoever's on my back; their ship_id becomes
		# the target of the evasion maneuver so the maneuver knows who to dodge.
		maneuver_type = "fight_defensive_break"
	else:
		var phase_maneuver: String = _phase_to_maneuver(phase)
		if phase_maneuver != "":
			maneuver_type = phase_maneuver

	var target_id = target_ship.get("ship_id", "")

	# Calculate evasion direction for dodge maneuvers
	var evasion_direction = 0
	if maneuver_type in ["fight_dodge_and_weave", "fight_lateral_break", "fight_evasive_turn", "fight_defensive_break"]:
		evasion_direction = _calculate_evasion_direction(ship_data, target_ship)

	# Build decision with skill-based approach data
	var decision = {
		"type": "maneuver",
		"subtype": maneuver_type,
		"crew_id": crew_data.get("crew_id", ""),
		"entity_id": ship_data.get("ship_id", ""),
		"target_id": target_id,
		"skill_factor": skill,
		"delay": crew_data.get("stats", {}).get("reaction_time", 0.1),
		"timestamp": game_time,
		"formation_offset": formation_offset,
		"behind_position": behind_position,
		"evasion_direction": evasion_direction,
		"knowledge_situation": situation,  # For debugging
		# NEW: Skill-based approach data
		"approach_style": approach_style,
		"position_advantage": position_advantage,
		"jink_amplitude": jink_params.amplitude,
		"jink_period": jink_params.period,
		"approach_angle": approach_angle,
	}

	return decision

## Fighter vs Corvette/Capital combat - KNOWLEDGE-DRIVEN
static func _make_fighter_vs_capital_decision(crew_data: Dictionary, ship_data: Dictionary, target_ship: Dictionary, all_ships: Array, all_crew: Array, game_time: float) -> Dictionary:
	var my_pos = ship_data.get("position", Vector2.ZERO)
	var target_pos = target_ship.get("position", Vector2.ZERO)
	var distance = my_pos.distance_to(target_pos)
	var skill = crew_data.get("stats", {}).get("skills", {}).get("piloting", 0.5)

	# Count friendly fighters nearby
	var nearby_fighters = _count_nearby_friendly_fighters(ship_data, all_ships)

	# Build context for knowledge query
	var context = {
		"nearby_fighters": nearby_fighters
	}

	# Generate situation string and query knowledge
	var situation = _generate_fighter_situation(ship_data, target_ship, context)

	# Add distance-specific context for capital ships
	if distance < SAFE_DISTANCE_VS_CAPITAL * 0.7:
		situation += " too close retreat evade danger"
	elif distance > SAFE_DISTANCE_VS_CAPITAL * 1.3:
		situation += " far approach cautious"
	else:
		situation += " harass dodge weave range"

	# Add group context
	if nearby_fighters >= GROUP_RUN_THRESHOLD:
		if distance > SAFE_DISTANCE_VS_CAPITAL:
			situation += " approach run"
		elif distance > CLOSE_RANGE:
			situation += " attack run strike"
		else:
			situation += " swing around reposition"

	var maneuver_type = _query_fighter_knowledge(situation, crew_data)

	# Fallback to appropriate default if no knowledge match
	if maneuver_type == "" or maneuver_type == "idle":
		if nearby_fighters >= GROUP_RUN_THRESHOLD:
			maneuver_type = "fight_group_run_approach"
		else:
			maneuver_type = "fight_dodge_and_weave"

	var target_id = target_ship.get("ship_id", "")

	var decision = {
		"type": "maneuver",
		"subtype": maneuver_type,
		"crew_id": crew_data.get("crew_id", ""),
		"entity_id": ship_data.get("ship_id", ""),
		"target_id": target_id,
		"skill_factor": skill,
		"delay": crew_data.get("stats", {}).get("reaction_time", 0.1),
		"timestamp": game_time,
		"nearby_fighters": nearby_fighters,
		"knowledge_situation": situation  # For debugging
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

## Calculate position behind target (for pursuit). Uses the pilot's `aim`
## skill (which folds in lead-prediction quality) with an error margin for
## low-aim pilots.
static func _calculate_behind_position(target_ship: Dictionary, aim: float = 0.5) -> Vector2:
	var target_pos = target_ship.get("position", Vector2.ZERO)
	var target_rotation = target_ship.get("rotation", 0.0)
	var target_velocity = target_ship.get("velocity", Vector2.ZERO)

	# Position behind target at ideal weapons range (not too close!)
	# Use halfway between MIN_COMBAT_RANGE and CLOSE_RANGE for good firing position
	var ideal_distance = (MIN_COMBAT_RANGE + CLOSE_RANGE) / 2.0  # ~550 units
	var behind_offset = Vector2(cos(target_rotation + PI), sin(target_rotation + PI)) * ideal_distance

	# Prediction lookahead scales with aim: 0.0 → 0.1s, 0.5 → 0.3s, 1.0 → 0.8s
	var prediction_time = lerp(0.1, 0.8, aim)

	var predicted_pos = target_pos + target_velocity * prediction_time

	# Low aim adds prediction error (missing where target actually is)
	var error_magnitude = (1.0 - aim) * 100.0
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
			# orders.current is null before the leader's first decision; guard it
			var leader_orders = crew.get("orders", {}).get("current")
			if leader_orders == null or not leader_orders is Dictionary:
				return ""
			return leader_orders.get("target_id", "")

	return ""

## Find wingmates (other fighters on same team)
static func _find_wingmates(crew_data: Dictionary, all_crew: Array, all_ships: Array) -> Array:
	var wingmates = []
	var my_ship_id = crew_data.get("assigned_to", "")
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

			var crew_ship_id = crew.get("assigned_to", "")
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
		if not FleetDataManager.is_fighter_class(ship_type):
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

	var my_ship_id = crew_data.get("assigned_to", "")
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

	for ship in all_ships:
		if ship.get("ship_id", "") == my_id:
			continue
		if ship.get("team", -1) != my_team:
			continue
		var ship_type = ship.get("type", "")
		if not FleetDataManager.is_fighter_class(ship_type):
			continue
		if ship.get("status", "") != "operational":
			continue

		var distance = my_pos.distance_to(ship.get("position", Vector2.ZERO))
		if distance < SAFE_DISTANCE_VS_CAPITAL * 1.5:
			count += 1

	return count

## Find best target from awareness, with fallback to scanning all ships
static func _find_best_target(crew_data: Dictionary, all_ships: Array) -> String:
	var skill = crew_data.get("stats", {}).get("skills", {}).get("piloting", 0.5)
	var awareness = crew_data.get("awareness", {})
	var threats = awareness.get("threats", [])
	var opportunities = awareness.get("opportunities", [])
	var combat_state: Dictionary = crew_data.get("combat_state", {})

	# Get own ship to determine team
	var ship_id = crew_data.get("assigned_to", "")
	var own_ship = _get_ship_by_id(ship_id, all_ships)
	var my_team = own_ship.get("team", -1)

	# Engagement commitment: stick with our locked target while the lock is
	# live and the target is still valid. Without this, the engagement-cycle
	# FSM keeps resetting because awareness ranks keep shuffling.
	var locked_target = combat_state.get("locked_target_id", "")
	var locked_until: float = combat_state.get("target_locked_until", 0.0)
	var current_time: float = Time.get_ticks_msec() / 1000.0
	if locked_target != "" and _is_ship_valid(locked_target, all_ships) and current_time < locked_until:
		return locked_target

	# Rookie: extreme target fixation — stick even past lock expiry
	if skill < 0.3 and locked_target != "" and _is_ship_valid(locked_target, all_ships):
		return locked_target

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

	# FALLBACK: If awareness is empty, scan all_ships directly for enemies
	# This ensures fighters always find targets even if awareness system hasn't run
	if selected_target == "" and my_team >= 0:
		var my_pos = own_ship.get("position", Vector2.ZERO)
		var closest_distance = INF
		for ship in all_ships:
			var ship_team = ship.get("team", -1)
			if ship_team == my_team or ship_team < 0:
				continue  # Same team or invalid
			if ship.get("status", "") != "operational":
				continue
			var distance = my_pos.distance_to(ship.get("position", Vector2.ZERO))
			if distance < closest_distance:
				closest_distance = distance
				selected_target = ship.get("ship_id", "")

	# Lock the chosen target so the engagement-cycle FSM has stable footing.
	# Aggression scales lock duration so personalities show: aggressive pilots
	# commit longer to a kill, cautious ones reassess sooner. Rookies always
	# get the longest possible lock (tunnel vision).
	if selected_target != "":
		var aggression: float = crew_data.get("stats", {}).get("skills", {}).get("aggression", 0.5)
		var lock_duration: float = lerp(4.0, 8.0, aggression) if skill >= 0.3 else 12.0
		combat_state["locked_target_id"] = selected_target
		combat_state["target_locked_until"] = current_time + lock_duration

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
		"entity_id": crew_data.get("assigned_to", ""),
		"target_id": "",
		"skill_factor": crew_data.get("stats", {}).get("skills", {}).get("piloting", 0.5),
		"delay": 2.0,  # Check again in 2 seconds
		"timestamp": game_time
	}

## Make basic pursuit decision - uses valid movement system subtype
static func _make_pursuit_decision(crew_data: Dictionary, ship_data: Dictionary, target_ship: Dictionary, game_time: float) -> Dictionary:
	return {
		"type": "maneuver",
		"subtype": "fight_pursue_full_speed",
		"crew_id": crew_data.get("crew_id", ""),
		"entity_id": ship_data.get("ship_id", ""),
		"target_id": target_ship.get("ship_id", ""),
		"skill_factor": crew_data.get("stats", {}).get("skills", {}).get("piloting", 0.5),
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
		var partner_ship_id = crew.get("assigned_to", "")
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
		"skill_factor": crew_data.get("stats", {}).get("skills", {}).get("piloting", 0.5),
		"delay": 0.3,  # Check frequently when rejoining
		"timestamp": game_time
	}

# ============================================================================
# SELF-PRESERVATION — "stay alive" runs in every pilot's background
# ============================================================================
# Real fighter pilots constantly assess whether the situation has turned
# bad enough to break off. Two trigger conditions:
#
#   1. Hull/armor critical — too damaged to keep fighting; run.
#   2. Locally outnumbered without support — bail before being swarmed.
#
# Both thresholds soften with aggression: a heroic pilot tolerates damage
# and bad odds; a timid one breaks off early. Returns one of:
#   ""        — nothing wrong; carry on with squadron/wing/individual logic
#   "evade"   — bracket out of close combat and pick fights selectively
#   "retreat" — run hard; don't engage anyone

const SURVIVAL_HULL_CRITICAL_RATIO = 0.30
const SURVIVAL_HULL_AGGRESSION_TOLERANCE = 0.5  # at max aggression, threshold halves
const SURVIVAL_NEARBY_ENEMY_RANGE = 1800.0
const SURVIVAL_NEARBY_FRIEND_RANGE = 1200.0
const SURVIVAL_MIN_ENEMIES_TO_PANIC = 2
const SURVIVAL_OUTNUMBERED_SUPPORT_RATIO = 0.5  # below this, bail
const SURVIVAL_AGGRESSION_TOLERANCE = 0.6       # max aggression cuts threshold by 60%

static func _assess_survival_state(crew_data: Dictionary, ship_data: Dictionary, all_ships: Array) -> String:
	if not FleetDataManager.is_fighter_class(ship_data.get("type", "")):
		return ""  # Capitals/corvettes have their own (large_ship) AI

	var aggression: float = crew_data.get("stats", {}).get("skills", {}).get("aggression", 0.5)

	# 1. CRITICAL HULL — bug out
	var armor_ratio: float = _compute_total_armor_ratio(ship_data)
	var hull_threshold: float = SURVIVAL_HULL_CRITICAL_RATIO * (1.0 - aggression * SURVIVAL_HULL_AGGRESSION_TOLERANCE)
	if armor_ratio < hull_threshold:
		return "retreat"

	# 2. LOCAL THREAT BALANCE — only triggers when there are real enemies present
	var counts: Dictionary = _count_nearby_combatants(ship_data, all_ships)
	var enemies: int = counts.enemies
	if enemies < SURVIVAL_MIN_ENEMIES_TO_PANIC:
		return ""

	var support_ratio: float = float(counts.friends + 1) / float(enemies + 1)
	var ratio_threshold: float = SURVIVAL_OUTNUMBERED_SUPPORT_RATIO * (1.0 - aggression * SURVIVAL_AGGRESSION_TOLERANCE)
	if support_ratio < ratio_threshold:
		return "evade"

	return ""

static func _compute_total_armor_ratio(ship_data: Dictionary) -> float:
	var sections: Array = ship_data.get("armor_sections", [])
	if sections.is_empty():
		return 1.0
	var current_total: float = 0.0
	var max_total: float = 0.0
	for section in sections:
		current_total += float(section.get("current_armor", 0))
		max_total += float(section.get("max_armor", 0))
	return current_total / max_total if max_total > 0.0 else 1.0

static func _count_nearby_combatants(ship_data: Dictionary, all_ships: Array) -> Dictionary:
	var my_team: int = ship_data.get("team", -1)
	var my_id: String = ship_data.get("ship_id", "")
	var my_pos: Vector2 = ship_data.get("position", Vector2.ZERO)
	var enemies: int = 0
	var friends: int = 0
	for ship in all_ships:
		if ship.get("ship_id", "") == my_id:
			continue
		if ship.get("status", "") != "operational":
			continue
		# Only fighter-class threats count for outnumbered checks; a single
		# capital ship in the area shouldn't make a fighter bail.
		if not FleetDataManager.is_fighter_class(ship.get("type", "")):
			continue
		var d: float = my_pos.distance_to(ship.get("position", Vector2.ZERO))
		if ship.get("team", -1) == my_team:
			if d < SURVIVAL_NEARBY_FRIEND_RANGE:
				friends += 1
		else:
			if d < SURVIVAL_NEARBY_ENEMY_RANGE:
				enemies += 1
	return {"enemies": enemies, "friends": friends}

static func _make_survival_decision(crew_data: Dictionary, ship_data: Dictionary, all_ships: Array, mode: String, game_time: float) -> Dictionary:
	var skill: float = crew_data.get("stats", {}).get("skills", {}).get("piloting", 0.5)
	# Pick the closest enemy as the immediate threat to evade from / retreat from
	var threat_id: String = _find_closest_enemy_id(ship_data, all_ships)
	var threat_ship: Dictionary = _get_ship_by_id(threat_id, all_ships) if threat_id != "" else {}

	# "retreat" → run away (existing fight_evasive_retreat)
	# "evade"   → sharp evasive maneuvering near combat (fight_defensive_break)
	var subtype: String = "fight_evasive_retreat" if mode == "retreat" else "fight_defensive_break"
	var evasion_dir: int = 0
	if not threat_ship.is_empty():
		evasion_dir = _calculate_evasion_direction(ship_data, threat_ship)

	return {
		"type": "maneuver",
		"subtype": subtype,
		"crew_id": crew_data.get("crew_id", ""),
		"entity_id": ship_data.get("ship_id", ""),
		"target_id": threat_id,
		"skill_factor": skill,
		"delay": 0.3,  # Re-assess often when in trouble
		"timestamp": game_time,
		"evasion_direction": evasion_dir,
		"survival_mode": mode  # exposed for debugging / future telemetry
	}

static func _find_closest_enemy_id(ship_data: Dictionary, all_ships: Array) -> String:
	var my_team: int = ship_data.get("team", -1)
	var my_id: String = ship_data.get("ship_id", "")
	var my_pos: Vector2 = ship_data.get("position", Vector2.ZERO)
	var best_id: String = ""
	var best_d: float = INF
	for ship in all_ships:
		if ship.get("ship_id", "") == my_id:
			continue
		if ship.get("status", "") != "operational":
			continue
		if ship.get("team", -1) == my_team:
			continue
		var d: float = my_pos.distance_to(ship.get("position", Vector2.ZERO))
		if d < best_d:
			best_d = d
			best_id = ship.get("ship_id", "")
	return best_id

# ============================================================================
# AREA LEASH (AI-LEVEL HARD OVERRIDE)
# ============================================================================
# The physics layer in MovementSystem.apply_area_leash gradually pulls a
# ship's nose toward home when it's outside its assigned area. That handles
# every maneuver that already thrusts. But combat maneuvers (dogfight, etc.)
# can sit at zero throttle, so a pilot stuck dogfighting on the edge would
# rotate to face home but never actually move. This AI override drops the
# fight and burns home when a pilot is well outside their leash.
const AREA_HARD_RETURN_MULTIPLIER = 1.5  # > 1.5x leash radius → drop everything and fly home

static func _is_far_outside_area(ship_data: Dictionary) -> bool:
	var assigned_area = ship_data.get("assigned_area")
	if assigned_area == null or not assigned_area is Dictionary:
		return false
	var radius: float = assigned_area.get("radius", 0.0)
	if radius <= 0.0:
		return false
	var center: Vector2 = assigned_area.get("center", Vector2.ZERO)
	var dist: float = ship_data.get("position", Vector2.ZERO).distance_to(center)
	return dist > radius * AREA_HARD_RETURN_MULTIPLIER

static func _make_return_to_area_decision(crew_data: Dictionary, ship_data: Dictionary, game_time: float) -> Dictionary:
	return {
		"type": "maneuver",
		"subtype": "fight_return_to_area",
		"crew_id": crew_data.get("crew_id", ""),
		"entity_id": ship_data.get("ship_id", ""),
		"target_id": "",
		"skill_factor": crew_data.get("stats", {}).get("skills", {}).get("piloting", 0.5),
		"delay": 0.4,
		"timestamp": game_time
	}

# ============================================================================
# ENGAGEMENT-CYCLE FSM — pass / extend / reposition / re-engage
# ============================================================================

## Visual forward unit vector (matches MovementSystem.get_visual_forward)
static func _ship_forward(ship: Dictionary) -> Vector2:
	var rot: float = ship.get("rotation", 0.0)
	return Vector2(sin(rot), -cos(rot))

## Alignment of my nose with the line to the target (1.0 = pointed straight at it)
static func _nose_to_target_dot(ship: Dictionary, target: Dictionary) -> float:
	var to_target: Vector2 = target.get("position", Vector2.ZERO) - ship.get("position", Vector2.ZERO)
	if to_target.length() < 1.0:
		return 0.0
	return _ship_forward(ship).dot(to_target.normalized())

## Is there an enemy within close range whose nose is pointing at me? — i.e.
## someone has me in their firing arc and is on my back. Used to interrupt the
## current engagement and break before they line up a shot.
static func _check_threat_on_my_six(ship_data: Dictionary, all_ships: Array) -> Dictionary:
	var my_team: int = ship_data.get("team", -1)
	var my_id: String = ship_data.get("ship_id", "")
	var my_pos: Vector2 = ship_data.get("position", Vector2.ZERO)
	for ship in all_ships:
		if ship.get("ship_id", "") == my_id:
			continue
		if ship.get("status", "") != "operational":
			continue
		if ship.get("team", -1) == my_team:
			continue
		if not FleetDataManager.is_fighter_class(ship.get("type", "")):
			continue
		var d: float = my_pos.distance_to(ship.get("position", Vector2.ZERO))
		if d > TACTICAL_BREAK_RANGE or d < 1.0:
			continue
		# Are they pointed at me? Use _nose_to_target_dot from THEIR perspective.
		if _nose_to_target_dot(ship, ship_data) >= TACTICAL_BREAK_ARC_DOT:
			return ship  # found a threat
	return {}

## Compute the new engagement phase given the current one and tactical state.
## Aggression spreads phase durations: hot pilots stay in firing_pass longer
## and extend briefly; cool pilots break early and extend wider.
static func _compute_engagement_phase(
	current_phase: String,
	phase_age: float,
	ship_data: Dictionary,
	target_ship: Dictionary,
	aggression: float
) -> String:
	# Aggression-scaled duration multiplier (range ~0.66x..1.5x at 0..1)
	var spread: float = ENGAGE_AGGRESSION_TIMING_SPREAD
	var hot_factor: float = lerp(1.0 / spread, spread, aggression)        # firing_pass + reposition
	var cold_factor: float = lerp(spread, 1.0 / spread, aggression)        # extend (timid extends longer)

	var distance: float = ship_data.get("position", Vector2.ZERO).distance_to(
		target_ship.get("position", Vector2.ZERO)
	)
	var nose_dot: float = _nose_to_target_dot(ship_data, target_ship)
	var in_engagement_zone: bool = distance <= ENGAGE_FIRE_RANGE and nose_dot >= ENGAGE_ARC_DOT

	match current_phase:
		"firing_pass":
			# End the pass when:
			# * stayed too long (force commit to the cycle), OR
			# * lost the angle (target slipped out of the front zone), OR
			# * about to overshoot / collide
			if phase_age > ENGAGE_FIRING_PASS_BASE_DURATION * hot_factor:
				return "extending"
			if not in_engagement_zone and phase_age > 0.4:
				return "extending"
			if distance < ENGAGE_OVERSHOOT_RANGE:
				return "extending"
			return "firing_pass"

		"extending":
			# Extend until time-up or we've opened to a useful repositioning distance.
			if phase_age > ENGAGE_EXTEND_BASE_DURATION * cold_factor:
				return "repositioning"
			if distance > ENGAGE_EXTEND_DISTANCE:
				return "repositioning"
			return "extending"

		"repositioning":
			# Turn back to target. Done when nose is back on target, or timeout.
			if nose_dot >= ENGAGE_FACING_DOT and phase_age > 0.3:
				return "approach"
			if phase_age > ENGAGE_REPOSITION_TIMEOUT * hot_factor:
				return "approach"
			return "repositioning"

		_:  # "approach" or unknown
			# Enter firing pass when target is in our zone at firing range
			if in_engagement_zone:
				return "firing_pass"
			return "approach"

## Update and read engagement phase. Mutates crew_data.combat_state in place
## (same pattern as the existing rookie target lock).
## Returns: { phase: String, phase_age: float }
static func _step_engagement_phase(
	crew_data: Dictionary,
	ship_data: Dictionary,
	target_ship: Dictionary,
	game_time: float
) -> Dictionary:
	var combat_state: Dictionary = crew_data.get("combat_state", {})
	var target_id: String = target_ship.get("ship_id", "")
	var prev_target: String = combat_state.get("phase_target_id", "")
	var phase: String = combat_state.get("engagement_phase", "approach")
	var phase_started_at: float = combat_state.get("phase_started_at", game_time)

	# New target → reset cycle
	if target_id != prev_target:
		phase = "approach"
		phase_started_at = game_time

	var aggression: float = crew_data.get("stats", {}).get("skills", {}).get("aggression", 0.5)
	var phase_age: float = max(0.0, game_time - phase_started_at)

	var next_phase: String = _compute_engagement_phase(phase, phase_age, ship_data, target_ship, aggression)
	if next_phase != phase:
		phase_started_at = game_time
		phase = next_phase

	combat_state["engagement_phase"] = phase
	combat_state["phase_started_at"] = phase_started_at
	combat_state["phase_target_id"] = target_id

	return {"phase": phase, "phase_age": max(0.0, game_time - phase_started_at)}

## Map an engagement phase to a fighter maneuver subtype.
## Approach delegates to the caller (returns "" so the existing skill/knowledge
## flow can pick a specific approach style).
static func _phase_to_maneuver(phase: String) -> String:
	match phase:
		"firing_pass":
			return "fight_dogfight_maneuver"
		"extending":
			return "fight_evasive_retreat"
		"repositioning":
			return "fight_pursue_tactical"
		_:
			return ""

# ============================================================================
# SKILL-BASED APPROACH STYLE SELECTION
# ============================================================================

## Select approach style based on pilot skill, tactical situation, AND aggression.
## Aggression is what gives wings personality — two leads with the same skill but
## different aggression pick different doctrines, so a 6v6 produces a mix of
## head-on rushers, flankers, and standoff harassers instead of one uniform charge.
##   high aggression  → bias toward DIRECT (commit head-on, full throttle)
##   low aggression   → bias toward ANGLED / DEFENSIVE_SPIRAL (flank, harass)
##   middling         → existing skill-based logic
static func _select_approach_style(skill: float, position_advantage: String, aggression: float = 0.5) -> int:
	# LOW SKILL (< 0.4): Always direct approach — rookies don't think in angles
	if skill < WingConstants.PILOT_APPROACH_ANGLE_SKILL:
		return ApproachStyle.DIRECT

	# AGGRESSION DOCTRINE (applies once skill is high enough to choose). High
	# aggression overrides "circle for advantage" thinking; low aggression
	# overrides "press the kill" thinking.
	if aggression >= WingConstants.LEAD_DOCTRINE_RUSH_AGGRESSION:
		# Hot pilot — commits to the merge regardless of position
		if position_advantage == "disadvantaged" and skill >= WingConstants.PILOT_DEFENSIVE_MANEUVER_SKILL:
			return ApproachStyle.DEFENSIVE_SPIRAL  # even rushers break when bounced
		return ApproachStyle.DIRECT
	if aggression <= WingConstants.LEAD_DOCTRINE_FLANK_AGGRESSION:
		# Cautious pilot — never rushes; favors angles and breakaways
		if position_advantage == "disadvantaged":
			return ApproachStyle.DEFENSIVE_SPIRAL if skill >= WingConstants.PILOT_DEFENSIVE_MANEUVER_SKILL else ApproachStyle.ANGLED
		if position_advantage == "behind" and skill >= WingConstants.PILOT_PURSUIT_CURVE_SKILL:
			return ApproachStyle.ATTACK_RUN  # behind is too good to refuse
		return ApproachStyle.ANGLED

	# MEDIUM SKILL (0.4-0.6) at moderate aggression: basic angle awareness
	if skill < WingConstants.PILOT_PURSUIT_CURVE_SKILL:
		if position_advantage == "behind":
			return ApproachStyle.DIRECT  # Have advantage, go straight in
		else:
			return ApproachStyle.ANGLED

	# HIGH SKILL (0.6+) at moderate aggression: full tactical selection
	if position_advantage == "disadvantaged":
		if skill >= WingConstants.PILOT_DEFENSIVE_MANEUVER_SKILL:
			return ApproachStyle.DEFENSIVE_SPIRAL
		return ApproachStyle.ANGLED
	elif position_advantage == "behind":
		return ApproachStyle.ATTACK_RUN
	else:
		return ApproachStyle.PURSUIT_CURVE

## Calculate jink parameters based on skill
## Returns: { amplitude: float, period: float }
static func _calculate_jink_params(skill: float) -> Dictionary:
	if skill < WingConstants.PILOT_JINKING_SKILL:
		# Below jinking threshold - no jinking
		return { "amplitude": 0.0, "period": 1000.0 }

	# Scale jinking with skill above threshold
	var jink_skill = (skill - WingConstants.PILOT_JINKING_SKILL) / (1.0 - WingConstants.PILOT_JINKING_SKILL)
	var amplitude = lerp(WingConstants.PILOT_JINK_AMPLITUDE_MIN,
						 WingConstants.PILOT_JINK_AMPLITUDE_MAX, jink_skill)
	var period = lerp(WingConstants.PILOT_JINK_PERIOD_LOW_SKILL,
					  WingConstants.PILOT_JINK_PERIOD_HIGH_SKILL, jink_skill)

	return { "amplitude": amplitude, "period": period }

## Calculate approach angle offset based on skill
## Returns angle in radians (0 for direct, up to ~0.7 for skilled)
static func _calculate_approach_angle(skill: float) -> float:
	if skill < WingConstants.PILOT_APPROACH_ANGLE_SKILL:
		return 0.0

	var angle_skill = (skill - WingConstants.PILOT_APPROACH_ANGLE_SKILL) / (1.0 - WingConstants.PILOT_APPROACH_ANGLE_SKILL)
	return lerp(WingConstants.PILOT_APPROACH_ANGLE_MIN,
				WingConstants.PILOT_APPROACH_ANGLE_MAX, angle_skill)

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
