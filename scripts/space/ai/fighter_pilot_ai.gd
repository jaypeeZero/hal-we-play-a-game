class_name FighterPilotAI
extends RefCounted

## Fighter pilot decision-making — GOAP-based tactical planner.
##
## Priority cascade:
##   1. Survival reflex (hull critical / outnumbered)      — unconditional
##   2. Medic avoid-enemy reflex (gunboat_medic only)      — unconditional
##   3. Area-leash hard return (outside zone, no target)   — unconditional
##   4. Pre-commit evasion (elite skill gate)              — unconditional
##   5. Friendly collision avoidance (elite skill gate)    — unconditional
##   6. Squadron-play waypoint (if play assigned)          — unconditional
##   7. GOAP brain (FighterBrain.decide)                   — handles all tactics:
##        EvadeOutnumbered, RejoinWing, PatrolReturn,
##        SupportUnderFire, CutOff, Flank, Attack

# Constants referenced by tests — match FighterAction values
const FAR_RANGE              = 5000.0
const MID_RANGE              = 1500.0
const CLOSE_RANGE            = 800.0
const MIN_COMBAT_RANGE       = 300.0
const SAFE_DISTANCE_VS_CAPITAL = 2500.0
const GROUP_RUN_THRESHOLD    = 4
const FORMATION_SPACING      = 80.0
const TACTICAL_BREAK_RANGE   = 700.0

# Approach style enum — mirrors FighterAction.ApproachStyle (same ordinals)
enum ApproachStyle { DIRECT, ANGLED, PURSUIT_CURVE, DEFENSIVE_SPIRAL, ATTACK_RUN }

const SURVIVAL_HULL_CRITICAL_RATIO       = 0.30
const SURVIVAL_HULL_AGGRESSION_TOLERANCE = 0.5
const SURVIVAL_NEARBY_ENEMY_RANGE        = 1800.0
const SURVIVAL_NEARBY_FRIEND_RANGE       = 1200.0
const SURVIVAL_MIN_ENEMIES_TO_PANIC      = 2
const SURVIVAL_OUTNUMBERED_SUPPORT_RATIO = 0.5
const SURVIVAL_AGGRESSION_TOLERANCE      = 0.6
const AREA_HARD_RETURN_MULTIPLIER        = 1.5
const PLAY_WAYPOINT_REACHED_DISTANCE     = 250.0
const COLLISION_DETECTION_RANGE          = 2000.0
## Decision delay (s) for flee maneuvers — slow cadence; the steer target is stable.
const FLEE_DECISION_DELAY                = 0.3
## Medic: radius within which an enemy triggers the keep-distance reflex.
const MEDIC_DANGER_RADIUS                = 1800.0
## Medic: decision delay for avoid maneuvers — same cadence as survival reflexes.
const MEDIC_AVOID_DECISION_DELAY         = 0.3


## Entry point — called by CrewAISystem every decision tick.
static func make_decision(
	crew_data: Dictionary,
	ship_data: Dictionary,
	all_ships: Array,
	all_crew: Array,
	game_time: float,
	wings: Array = []
) -> Dictionary:
	if not FleetDataManager.is_fighter_class(ship_data.get("type", "")):
		return {}

	# The escape boundary is a harder bound than the patrol leash or survival
	# running-outward, so the edge reflex is evaluated FIRST.
	var decision := _reflex_edge_boundary(crew_data, ship_data, all_ships, game_time)
	if not decision.is_empty(): return decision

	decision = _reflex_survival(crew_data, ship_data, all_ships, game_time)
	if not decision.is_empty(): return decision

	decision = _reflex_medic_avoid(crew_data, ship_data, all_ships, game_time)
	if not decision.is_empty(): return decision

	decision = _reflex_area_leash(crew_data, ship_data, all_ships, game_time)
	if not decision.is_empty(): return decision

	decision = _reflex_pre_commit_evasion(crew_data, ship_data, all_ships, game_time)
	if not decision.is_empty(): return decision

	decision = _reflex_friendly_collision(crew_data, ship_data, all_ships, game_time)
	if not decision.is_empty(): return decision

	decision = _reflex_enemy_collision(crew_data, ship_data, all_ships, game_time)
	if not decision.is_empty(): return decision

	decision = _reflex_play_waypoint(crew_data, ship_data, game_time)
	if not decision.is_empty(): return decision

	var ws := FighterWorldState.build(crew_data, ship_data, all_ships, all_crew, game_time, wings)
	return FighterBrain.decide(ws, game_time)


# ---------------------------------------------------------------------------
# Reflexes
# ---------------------------------------------------------------------------

## Escape-boundary reflex. A locked-in flee decision keeps steering (out to the
## exit when committed, back inward when returning) regardless of distance; an
## unlocked ship only decides once it nears the edge.
static func _reflex_edge_boundary(
	crew_data: Dictionary, ship_data: Dictionary, all_ships: Array, game_time: float
) -> Dictionary:
	var pos: Vector2 = ship_data.get("position", Vector2.ZERO)
	var size: Vector2 = ship_data.get("battlefield_size", FleeBoundarySystem.DEFAULT_BATTLEFIELD_SIZE)
	var locked: String = ship_data.get("orders", {}).get("flee_decision", "")

	# Already committed: keep running for the exit regardless of distance.
	if locked == FleeDecisionSystem.COMMITTED:
		return _flee_maneuver(crew_data, ship_data, game_time, FleeDecisionSystem.COMMITTED,
			FleeBoundarySystem.outward_exit_point(pos, size))

	# Returning: keep heading inward until well clear, then release the lock.
	if locked == FleeDecisionSystem.RETURNING:
		if FleeBoundarySystem.is_clear_inside(pos, size):
			return _clear_flee_lock(crew_data, ship_data, game_time)
		return _flee_maneuver(crew_data, ship_data, game_time, FleeDecisionSystem.RETURNING,
			FleeBoundarySystem.inward_point(size))

	# No lock yet: only decide once near the edge.
	if not FleeBoundarySystem.is_near_edge(pos, size):
		return {}
	var choice := FleeDecisionSystem.decide(crew_data, ship_data, all_ships)
	var target: Vector2 = FleeBoundarySystem.outward_exit_point(pos, size) \
		if choice == FleeDecisionSystem.COMMITTED else FleeBoundarySystem.inward_point(size)
	return _flee_maneuver(crew_data, ship_data, game_time, choice, target)


## Build a flee maneuver decision carrying the locked flee_decision + target.
static func _flee_maneuver(
	crew_data: Dictionary, ship_data: Dictionary, game_time: float, choice: String, target: Vector2
) -> Dictionary:
	return {
		"type": "maneuver",
		"subtype": "flee_to_boundary" if choice == FleeDecisionSystem.COMMITTED else "flee_turn_back",
		"crew_id": crew_data.get("crew_id", ""),
		"entity_id": ship_data.get("ship_id", ""),
		"target_id": "",
		"skill_factor": crew_data.get("stats", {}).get("skills", {}).get("piloting", 0.5),
		"delay": FLEE_DECISION_DELAY,
		"timestamp": game_time,
		"flee_decision": choice,
		"flee_target": target,
	}


## Release the flee lock so normal AI resumes; a later edge approach re-decides.
static func _clear_flee_lock(
	crew_data: Dictionary, ship_data: Dictionary, game_time: float
) -> Dictionary:
	return {
		"type": "maneuver",
		"subtype": "flee_turn_back",
		"crew_id": crew_data.get("crew_id", ""),
		"entity_id": ship_data.get("ship_id", ""),
		"target_id": "",
		"skill_factor": crew_data.get("stats", {}).get("skills", {}).get("piloting", 0.5),
		"delay": FLEE_DECISION_DELAY,
		"timestamp": game_time,
		"flee_decision": "",
		"flee_target": ship_data.get("position", Vector2.ZERO),
	}


static func _reflex_survival(
	crew_data: Dictionary, ship_data: Dictionary, all_ships: Array, game_time: float
) -> Dictionary:
	var mode := _assess_survival(crew_data, ship_data, all_ships)
	if mode == "": return {}
	var skill: float = crew_data.get("stats", {}).get("skills", {}).get("piloting", 0.5)
	var threat_id := _closest_enemy(ship_data, all_ships)
	var threat: Dictionary = _ship_by_id(threat_id, all_ships)
	var ev_dir := 0
	if not threat.is_empty():
		ev_dir = _evasion_dir(ship_data, threat)
	return {
		"type": "maneuver",
		"subtype": "fight_evasive_retreat" if mode == "retreat" else "fight_defensive_break",
		"crew_id": crew_data.get("crew_id", ""),
		"entity_id": ship_data.get("ship_id", ""),
		"target_id": threat_id,
		"skill_factor": skill,
		"delay": 0.3,
		"timestamp": game_time,
		"evasion_direction": ev_dir,
		"survival_mode": mode,
	}


static func _assess_survival(
	crew_data: Dictionary, ship_data: Dictionary, all_ships: Array
) -> String:
	var aggression: float   = crew_data.get("stats", {}).get("skills", {}).get("aggression", 0.5)
	var armor: float        = _armor_ratio(ship_data)
	var hull_thresh: float  = SURVIVAL_HULL_CRITICAL_RATIO * (1.0 - aggression * SURVIVAL_HULL_AGGRESSION_TOLERANCE)
	if armor < hull_thresh: return "retreat"

	var counts := _nearby_count(ship_data, all_ships)
	if counts.enemies < SURVIVAL_MIN_ENEMIES_TO_PANIC: return ""

	var tactics: float = crew_data.get("stats", {}).get("skills", {}).get("tactics", 0.0)
	if tactics >= WingConstants.SURVIVAL_TACTICAL_DISENGAGE_SKILL and counts.friends == 0:
		if armor < WingConstants.SURVIVAL_TACTICAL_HULL_RATIO:
			return "retreat"

	var support_ratio: float = float(counts.friends + 1) / float(counts.enemies + 1)
	var ratio_thresh: float  = SURVIVAL_OUTNUMBERED_SUPPORT_RATIO * (1.0 - aggression * SURVIVAL_AGGRESSION_TOLERANCE)
	if support_ratio < ratio_thresh: return "evade"
	return ""


## Medic avoid-enemy reflex — fires only for gunboat_medic ships.
## When enemies are within MEDIC_DANGER_RADIUS the medic steers away from the
## nearest threat. When no enemies are nearby it returns {} so the area-leash
## and GOAP brain can produce a loiter/patrol decision instead.
## This reflex fires BEFORE any attack/pursue logic, ensuring the medic never
## chases an enemy — it may still defend itself via its short-range turrets,
## which fire on whatever enters weapon range independently of this decision.
static func _reflex_medic_avoid(
	crew_data: Dictionary, ship_data: Dictionary, all_ships: Array, game_time: float
) -> Dictionary:
	if not FleetDataManager.is_gunboat_medic(ship_data.get("type", "")):
		return {}
	var threat_id := _closest_enemy_within(ship_data, all_ships, MEDIC_DANGER_RADIUS)
	if threat_id == "":
		return {}
	var threat: Dictionary = _ship_by_id(threat_id, all_ships)
	return {
		"type": "maneuver",
		"subtype": "fight_evasive_retreat",
		"crew_id": crew_data.get("crew_id", ""),
		"entity_id": ship_data.get("ship_id", ""),
		"target_id": threat_id,
		"skill_factor": crew_data.get("stats", {}).get("skills", {}).get("piloting", 0.5),
		"delay": MEDIC_AVOID_DECISION_DELAY,
		"timestamp": game_time,
		"evasion_direction": 0 if threat.is_empty() else _evasion_dir(ship_data, threat),
		"survival_mode": "retreat",
	}


## Return the ship_id of the closest operational enemy within `radius`, or "".
static func _closest_enemy_within(ship: Dictionary, all_ships: Array, radius: float) -> String:
	var my_team: int    = ship.get("team", -1)
	var my_pos: Vector2 = ship.get("position", Vector2.ZERO)
	var best := ""; var best_d := INF
	for s in all_ships:
		if s.get("team", -1) == my_team or s.get("status", "") != "operational": continue
		var d: float = my_pos.distance_to(s.get("position", Vector2.ZERO))
		if d < radius and d < best_d:
			best_d = d
			best = s.get("ship_id", "")
	return best


static func _reflex_area_leash(
	crew_data: Dictionary, ship_data: Dictionary, all_ships: Array, game_time: float
) -> Dictionary:
	if not _far_outside_area(ship_data): return {}
	if _has_any_enemy(ship_data, all_ships): return {}
	return {
		"type": "maneuver",
		"subtype": "fight_return_to_area",
		"crew_id": crew_data.get("crew_id", ""),
		"entity_id": ship_data.get("ship_id", ""),
		"target_id": "",
		"skill_factor": crew_data.get("stats", {}).get("skills", {}).get("piloting", 0.5),
		"delay": 0.4,
		"timestamp": game_time,
	}


static func _reflex_pre_commit_evasion(
	crew_data: Dictionary, ship_data: Dictionary, all_ships: Array, game_time: float
) -> Dictionary:
	var skill: float = crew_data.get("stats", {}).get("skills", {}).get("piloting", 0.5)
	if skill < WingConstants.PILOT_PRE_COMMIT_EVASION_SKILL: return {}
	var threat_id := _find_enemy_targeting_me(ship_data, all_ships)
	if threat_id == "": return {}
	var threat: Dictionary = _ship_by_id(threat_id, all_ships)
	return {
		"type": "maneuver",
		"subtype": "fight_dodge_and_weave",
		"crew_id": crew_data.get("crew_id", ""),
		"entity_id": ship_data.get("ship_id", ""),
		"target_id": threat_id,
		"skill_factor": skill,
		"delay": 0.2,
		"timestamp": game_time,
		"evasion_direction": 0 if threat.is_empty() else _evasion_dir(ship_data, threat),
		"pre_commit_evasion": true,
	}


static func _reflex_friendly_collision(
	crew_data: Dictionary, ship_data: Dictionary, all_ships: Array, game_time: float
) -> Dictionary:
	var skill: float = crew_data.get("stats", {}).get("skills", {}).get("piloting", 0.5)
	if skill < WingConstants.PILOT_FRIENDLY_COLLISION_SKILL: return {}
	var my_id: String = ship_data.get("ship_id", "")
	var my_team: int  = ship_data.get("team", -1)
	for other in all_ships:
		if other.get("team", -1) != my_team or other.get("ship_id", "") == my_id: continue
		if not _on_collision_course(ship_data, other): continue
		return {
			"type": "maneuver",
			"subtype": "fight_friendly_avoid",
			"crew_id": crew_data.get("crew_id", ""),
			"entity_id": my_id,
			"target_id": other.get("ship_id", ""),
			"skill_factor": skill,
			"delay": 0.15,
			"timestamp": game_time,
			"evasion_direction": _evasion_dir(ship_data, other),
		}
	return {}


static func _reflex_enemy_collision(
	crew_data: Dictionary, ship_data: Dictionary, all_ships: Array, game_time: float
) -> Dictionary:
	var skill: float = crew_data.get("stats", {}).get("skills", {}).get("piloting", 0.5)
	if skill < WingConstants.PILOT_FRIENDLY_COLLISION_SKILL: return {}
	var my_team: int  = ship_data.get("team", -1)
	var my_id: String = ship_data.get("ship_id", "")
	for other in all_ships:
		if other.get("team", -1) == my_team or other.get("ship_id", "") == my_id: continue
		if not _on_collision_course(ship_data, other): continue
		return {
			"type": "maneuver",
			"subtype": "fight_lateral_break",
			"crew_id": crew_data.get("crew_id", ""),
			"entity_id": my_id,
			"target_id": other.get("ship_id", ""),
			"skill_factor": skill,
			"delay": 0.1,
			"timestamp": game_time,
			"evasion_direction": _evasion_dir(ship_data, other),
		}
	return {}


static func _reflex_play_waypoint(
	crew_data: Dictionary, ship_data: Dictionary, game_time: float
) -> Dictionary:
	var play: Dictionary = crew_data.get("play_assignment", {})
	if play.is_empty(): return {}
	var action: String = play.get("action", "merge_attack")
	if action == "" or action == "merge_attack": return {}
	var offset: Vector2 = play.get("target_offset", Vector2.ZERO)
	if ship_data.get("position", Vector2.ZERO).distance_to(offset) <= PLAY_WAYPOINT_REACHED_DISTANCE:
		return {}
	return {
		"type": "maneuver",
		"subtype": "fight_play_waypoint",
		"crew_id": crew_data.get("crew_id", ""),
		"entity_id": ship_data.get("ship_id", ""),
		"target_id": play.get("target_id", ""),
		"formation_position": offset,
		"skill_factor": crew_data.get("stats", {}).get("skills", {}).get("piloting", 0.5),
		"play_id": play.get("play_id", ""),
		"play_role": play.get("play_role", ""),
		"phase": play.get("phase", 0),
		"delay": 0.3,
		"timestamp": game_time,
	}


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

static func _armor_ratio(ship: Dictionary) -> float:
	var sections: Array = ship.get("armor_sections", [])
	if sections.is_empty(): return 1.0
	var cur := 0.0; var mx := 0.0
	for s in sections:
		cur += float(s.get("current_armor", 0))
		mx  += float(s.get("max_armor", 0))
	return cur / mx if mx > 0.0 else 1.0


static func _nearby_count(ship: Dictionary, all_ships: Array) -> Dictionary:
	var my_team: int    = ship.get("team", -1)
	var my_id: String   = ship.get("ship_id", "")
	var my_pos: Vector2 = ship.get("position", Vector2.ZERO)
	var enemies := 0; var friends := 0
	for s in all_ships:
		if s.get("ship_id", "") == my_id or s.get("status", "") != "operational": continue
		if not FleetDataManager.is_fighter_class(s.get("type", "")): continue
		var d: float = my_pos.distance_to(s.get("position", Vector2.ZERO))
		if s.get("team", -1) == my_team:
			if d < SURVIVAL_NEARBY_FRIEND_RANGE: friends += 1
		else:
			if d < SURVIVAL_NEARBY_ENEMY_RANGE: enemies += 1
	return { "enemies": enemies, "friends": friends }


static func _far_outside_area(ship: Dictionary) -> bool:
	var area = ship.get("assigned_area")
	if area == null or not area is Dictionary: return false
	var r: float = area.get("radius", 0.0)
	if r <= 0.0: return false
	return ship.get("position", Vector2.ZERO).distance_to(area.get("center", Vector2.ZERO)) > r * AREA_HARD_RETURN_MULTIPLIER


static func _has_any_enemy(ship: Dictionary, all_ships: Array) -> bool:
	var my_team: int = ship.get("team", -1)
	for s in all_ships:
		if s.get("team", -1) != my_team and s.get("team", -1) >= 0 and s.get("status", "") == "operational":
			return true
	return false


static func _closest_enemy(ship: Dictionary, all_ships: Array) -> String:
	var my_team: int    = ship.get("team", -1)
	var my_pos: Vector2 = ship.get("position", Vector2.ZERO)
	var best := ""; var best_d := INF
	for s in all_ships:
		if s.get("team", -1) == my_team or s.get("status", "") != "operational": continue
		var d: float = my_pos.distance_to(s.get("position", Vector2.ZERO))
		if d < best_d: best_d = d; best = s.get("ship_id", "")
	return best


static func _ship_by_id(ship_id: String, all_ships: Array) -> Dictionary:
	for s in all_ships:
		if s.get("ship_id", "") == ship_id: return s
	return {}


static func _find_enemy_targeting_me(ship: Dictionary, all_ships: Array) -> String:
	var my_team: int    = ship.get("team", -1)
	var my_pos: Vector2 = ship.get("position", Vector2.ZERO)
	for s in all_ships:
		if s.get("team", -1) == my_team or s.get("status", "") != "operational": continue
		if not FleetDataManager.is_fighter_class(s.get("type", "")): continue
		if my_pos.distance_to(s.get("position", Vector2.ZERO)) > WingConstants.PRE_COMMIT_ENGAGEMENT_RANGE: continue
		var to_me: Vector2 = (my_pos - s.get("position", Vector2.ZERO)).normalized()
		var fwd: Vector2   = MovementSystem.get_visual_forward(s.get("rotation", 0.0))
		if to_me.dot(fwd) >= WingConstants.PRE_COMMIT_TARGETING_CONE_DOT:
			return s.get("ship_id", "")
	return ""


static func _on_collision_course(my_ship: Dictionary, other: Dictionary) -> bool:
	var to_other: Vector2 = other.get("position", Vector2.ZERO) - my_ship.get("position", Vector2.ZERO)
	if to_other.length() > COLLISION_DETECTION_RANGE: return false
	var rel_vel: Vector2 = my_ship.get("velocity", Vector2.ZERO) - other.get("velocity", Vector2.ZERO)
	return rel_vel.dot(to_other.normalized()) > 50.0


static func _evasion_dir(my_ship: Dictionary, threat: Dictionary) -> int:
	var to_t: Vector2   = threat.get("position", Vector2.ZERO) - my_ship.get("position", Vector2.ZERO)
	var perp_r: Vector2 = Vector2(-to_t.y, to_t.x).normalized()
	var lat: float      = threat.get("velocity", Vector2.ZERO).dot(perp_r)
	if lat > 10.0: return -1
	elif lat < -10.0: return 1
	return 1 if my_ship.get("velocity", Vector2.ZERO).dot(perp_r) >= 0 else -1


# ---------------------------------------------------------------------------
# Compatibility shims — preserve old method names so existing tests pass
# ---------------------------------------------------------------------------

static func _assess_survival_state(
	crew_data: Dictionary, ship_data: Dictionary, all_ships: Array
) -> String:
	return _assess_survival(crew_data, ship_data, all_ships)


static func _is_on_collision_course(my_ship: Dictionary, other: Dictionary) -> bool:
	return _on_collision_course(my_ship, other)


static func _is_far_outside_area(ship_data: Dictionary) -> bool:
	return _far_outside_area(ship_data)


static func _select_approach_style(
	skill: float, position_advantage: String, aggression: float = 0.5
) -> int:
	return FighterAction.approach_style_for(skill, position_advantage, aggression)


static func _calculate_target_score(
	crew_data: Dictionary, target_ship: Dictionary, all_ships: Array, all_crew: Array
) -> float:
	return FighterWorldState.score_target(crew_data, target_ship, all_ships, all_crew)


static func _count_friendlies_engaging(
	target_id: String, all_crew: Array, exclude_id: String
) -> int:
	return FighterWorldState.count_friendlies_engaging(target_id, all_crew, exclude_id)


static func _query_fighter_knowledge(situation: String, crew_data: Dictionary) -> String:
	var results: Array = TacticalKnowledgeSystem.query_pilot_knowledge(
		situation, 3, crew_data.get("known_patterns", [])
	)
	if results.is_empty(): return ""
	var skill: float     = crew_data.get("stats", {}).get("skills", {}).get("piloting", 0.5)
	var composure: float = crew_data.get("stats", {}).get("skills", {}).get("composure", skill)
	for knowledge in results:
		var content = knowledge.get("content", {})
		var maneuvers: Array = content.get("maneuvers", [])
		var skill_req: Dictionary  = content.get("skill_requirements", {})
		var comp_req: Dictionary   = content.get("composure_requirements", {})
		for m in maneuvers:
			if skill >= skill_req.get(m, 0.0) and composure >= comp_req.get(m, 0.0):
				return m
	return ""


static func _find_best_target(crew_data: Dictionary, all_ships: Array, game_time: float) -> String:
	return FighterWorldState._best_target_with_crew(crew_data, all_ships, [], game_time)


static func _find_best_target_for_wing(
	crew_data: Dictionary, _wing: Dictionary, all_ships: Array, all_crew: Array, game_time: float
) -> String:
	return FighterWorldState._best_target_with_crew(crew_data, all_ships, all_crew, game_time)


static func _step_engagement_phase(
	crew_data: Dictionary, ship_data: Dictionary, target_ship: Dictionary, game_time: float
) -> Dictionary:
	return FighterAction.step_engagement_phase(crew_data, ship_data, target_ship, game_time)


static func _check_threat_on_my_six(ship_data: Dictionary, all_ships: Array) -> Dictionary:
	# Replicated from FighterWorldState logic
	var my_team: int    = ship_data.get("team", -1)
	var my_id: String   = ship_data.get("ship_id", "")
	var my_pos: Vector2 = ship_data.get("position", Vector2.ZERO)
	for s in all_ships:
		if s.get("ship_id", "") == my_id or s.get("status", "") != "operational": continue
		if s.get("team", -1) == my_team: continue
		if not FleetDataManager.is_fighter_class(s.get("type", "")): continue
		var d: float = my_pos.distance_to(s.get("position", Vector2.ZERO))
		if d > TACTICAL_BREAK_RANGE or d < 1.0: continue
		var rot: float     = s.get("rotation", 0.0)
		var forward: Vector2 = Vector2(sin(rot), -cos(rot))
		var to_me: Vector2   = (my_pos - s.get("position", Vector2.ZERO)).normalized()
		if forward.dot(to_me) >= 0.85:
			return s
	return {}


static func _calculate_jink_params(skill: float) -> Dictionary:
	return FighterAction.jink_params(skill)
