class_name FighterAction
extends RefCounted

## Base class for GOAP fighter actions.
## Subclasses override action_id(), cost(), precondition(), and execute().
## Static helpers here are shared by all action subclasses.

# ---------------------------------------------------------------------------
# Virtual interface
# ---------------------------------------------------------------------------

func action_id() -> String:
	return ""

func cost(_ws: FighterWorldState) -> float:
	return 1.0

func precondition(_ws: FighterWorldState) -> bool:
	return false

func execute(_ws: FighterWorldState) -> Dictionary:
	return {}

# ---------------------------------------------------------------------------
# Engagement-cycle constants (matches fighter_pilot_ai)
# ---------------------------------------------------------------------------
const ENGAGE_FIRE_RANGE              = 1800.0
const ENGAGE_OVERSHOOT_RANGE         = 350.0
const ENGAGE_ARC_DOT                 = 0.78
const ENGAGE_FACING_DOT              = 0.5
const ENGAGE_FIRING_PASS_BASE_DURATION = 2.5
const ENGAGE_EXTEND_BASE_DURATION    = 1.4
const ENGAGE_EXTEND_DISTANCE         = 1300.0
const ENGAGE_REPOSITION_TIMEOUT      = 4.0
const ENGAGE_AGGRESSION_TIMING_SPREAD = 1.5

const TACTICAL_BREAK_RANGE   = 700.0
const TACTICAL_BREAK_ARC_DOT = 0.85
const CLOSE_RANGE            = 800.0
const MIN_COMBAT_RANGE       = 300.0
const FAR_RANGE              = 5000.0
const MID_RANGE              = 1500.0
const SAFE_DISTANCE_VS_CAPITAL = 2500.0
const GROUP_RUN_THRESHOLD    = 4

# ApproachStyle enum (mirrors FighterPilotAI.ApproachStyle)
enum ApproachStyle { DIRECT, ANGLED, PURSUIT_CURVE, DEFENSIVE_SPIRAL, ATTACK_RUN }

# ---------------------------------------------------------------------------
# Shared static utilities
# ---------------------------------------------------------------------------

static func jink_params(skill: float) -> Dictionary:
	if skill < WingConstants.PILOT_JINKING_SKILL:
		return { "amplitude": 0.0, "hold_ms": WingConstants.PILOT_JINK_HOLD_LOW_SKILL_MS }
	var t := (skill - WingConstants.PILOT_JINKING_SKILL) / (1.0 - WingConstants.PILOT_JINKING_SKILL)
	return {
		"amplitude": lerp(WingConstants.PILOT_JINK_AMPLITUDE_MIN, WingConstants.PILOT_JINK_AMPLITUDE_MAX, t),
		"hold_ms":   lerp(WingConstants.PILOT_JINK_HOLD_LOW_SKILL_MS, WingConstants.PILOT_JINK_HOLD_HIGH_SKILL_MS, t)
	}


static func approach_style_for(skill: float, position_advantage: String, aggression: float) -> int:
	if skill < WingConstants.PILOT_APPROACH_ANGLE_SKILL:
		return ApproachStyle.DIRECT

	if aggression >= WingConstants.LEAD_DOCTRINE_RUSH_AGGRESSION:
		if position_advantage == "disadvantaged" and skill >= WingConstants.PILOT_DEFENSIVE_MANEUVER_SKILL:
			return ApproachStyle.DEFENSIVE_SPIRAL
		return ApproachStyle.DIRECT
	if aggression <= WingConstants.LEAD_DOCTRINE_FLANK_AGGRESSION:
		if position_advantage == "disadvantaged":
			return ApproachStyle.DEFENSIVE_SPIRAL if skill >= WingConstants.PILOT_DEFENSIVE_MANEUVER_SKILL else ApproachStyle.ANGLED
		if position_advantage == "behind" and skill >= WingConstants.PILOT_PURSUIT_CURVE_SKILL:
			return ApproachStyle.ATTACK_RUN
		return ApproachStyle.ANGLED

	if skill < WingConstants.PILOT_PURSUIT_CURVE_SKILL:
		return ApproachStyle.DIRECT if position_advantage == "behind" else ApproachStyle.ANGLED

	if position_advantage == "disadvantaged":
		return ApproachStyle.DEFENSIVE_SPIRAL if skill >= WingConstants.PILOT_DEFENSIVE_MANEUVER_SKILL else ApproachStyle.ANGLED
	elif position_advantage == "behind":
		return ApproachStyle.ATTACK_RUN
	return ApproachStyle.PURSUIT_CURVE


static func approach_angle_for(skill: float) -> float:
	if skill < WingConstants.PILOT_APPROACH_ANGLE_SKILL:
		return 0.0
	var t := (skill - WingConstants.PILOT_APPROACH_ANGLE_SKILL) / (1.0 - WingConstants.PILOT_APPROACH_ANGLE_SKILL)
	return lerp(WingConstants.PILOT_APPROACH_ANGLE_MIN, WingConstants.PILOT_APPROACH_ANGLE_MAX, t)


static func step_engagement_phase(
	crew_data: Dictionary, ship: Dictionary, target: Dictionary, game_time: float
) -> Dictionary:
	var cs: Dictionary        = crew_data.get("combat_state", {})
	var target_id: String     = target.get("ship_id", "")
	var prev_target: String   = cs.get("phase_target_id", "")
	var phase: String         = cs.get("engagement_phase", "approach")
	var phase_started: float  = cs.get("phase_started_at", game_time)

	if target_id != prev_target:
		phase = "approach"
		phase_started = game_time

	var aggression: float   = crew_data.get("stats", {}).get("skills", {}).get("aggression", 0.5)
	var phase_age: float    = max(0.0, game_time - phase_started)
	var next: String        = _compute_phase(phase, phase_age, ship, target, aggression)
	if next != phase:
		phase_started = game_time
		phase = next

	cs["engagement_phase"] = phase
	cs["phase_started_at"] = phase_started
	cs["phase_target_id"]  = target_id
	return { "phase": phase, "phase_age": max(0.0, game_time - phase_started) }


static func phase_to_maneuver(phase: String) -> String:
	match phase:
		"firing_pass":   return "fight_dogfight_maneuver"
		"extending":     return "fight_evasive_retreat"
		"repositioning": return "fight_pursue_tactical"
		_: return ""


static func evasion_direction(my_ship: Dictionary, threat: Dictionary) -> int:
	var to_t: Vector2  = threat.get("position", Vector2.ZERO) - my_ship.get("position", Vector2.ZERO)
	var perp_r: Vector2 = Vector2(-to_t.y, to_t.x).normalized()
	var lateral: float = threat.get("velocity", Vector2.ZERO).dot(perp_r)
	if lateral > 10.0: return -1
	elif lateral < -10.0: return 1
	return 1 if my_ship.get("velocity", Vector2.ZERO).dot(perp_r) >= 0 else -1


static func closest_enemy_id(ship: Dictionary, all_ships: Array) -> String:
	var my_team: int = ship.get("team", -1)
	var my_pos: Vector2 = ship.get("position", Vector2.ZERO)
	var best := ""; var best_d := INF
	for s in all_ships:
		if s.get("team", -1) == my_team or s.get("status", "") != "operational": continue
		var d: float = my_pos.distance_to(s.get("position", Vector2.ZERO))
		if d < best_d: best_d = d; best = s.get("ship_id", "")
	return best


static func ship_forward(ship: Dictionary) -> Vector2:
	var rot: float = ship.get("rotation", 0.0)
	return Vector2(sin(rot), -cos(rot))


static func nose_to_target_dot(ship: Dictionary, target: Dictionary) -> float:
	var to_t: Vector2 = target.get("position", Vector2.ZERO) - ship.get("position", Vector2.ZERO)
	if to_t.length() < 1.0: return 0.0
	return ship_forward(ship).dot(to_t.normalized())


static func query_knowledge(ship: Dictionary, target: Dictionary, context: Dictionary, crew_data: Dictionary) -> String:
	var parts := ["fighter"]
	var ttype: String = target.get("type", "fighter")
	if FleetDataManager.is_large_ship(ttype):
		parts.append("capital"); parts.append(ttype)
	else:
		parts.append("fighter")
	var dist: float = ship.get("position", Vector2.ZERO).distance_to(target.get("position", Vector2.ZERO))
	if dist > FAR_RANGE: parts.append("far approach")
	elif dist > MID_RANGE: parts.append("mid range")
	elif dist > CLOSE_RANGE: parts.append("close")
	else: parts.append("very_close dogfight")
	if context.get("behind", false): parts.append("behind advantage")
	elif context.get("disadvantaged", false): parts.append("disadvantaged enemy behind")
	if context.get("nearby_fighters", 0) >= GROUP_RUN_THRESHOLD: parts.append("group coordinated")
	elif context.get("nearby_fighters", 0) > 0: parts.append("wingman support")
	else: parts.append("solo")
	var situation := " ".join(parts)

	var results: Array = TacticalKnowledgeSystem.query_pilot_knowledge(situation, 3, crew_data.get("known_patterns", []))
	if results.is_empty(): return ""
	var skill: float = crew_data.get("stats", {}).get("skills", {}).get("piloting", 0.5)
	var composure: float = crew_data.get("stats", {}).get("skills", {}).get("composure", skill)
	for knowledge in results:
		var content = knowledge.get("content", {})
		var maneuvers: Array = content.get("maneuvers", [])
		var skill_req: Dictionary = content.get("skill_requirements", {})
		var comp_req: Dictionary = content.get("composure_requirements", {})
		for m in maneuvers:
			if skill >= skill_req.get(m, 0.0) and composure >= comp_req.get(m, 0.0):
				return m
	return ""


# ---------------------------------------------------------------------------
# Private phase computation (mirrors _compute_engagement_phase)
# ---------------------------------------------------------------------------

static func _compute_phase(
	current: String, age: float, ship: Dictionary, target: Dictionary, aggression: float
) -> String:
	var spread: float  = ENGAGE_AGGRESSION_TIMING_SPREAD
	var hot: float     = lerp(1.0 / spread, spread, aggression)
	var cold: float    = lerp(spread, 1.0 / spread, aggression)
	var dist: float    = ship.get("position", Vector2.ZERO).distance_to(target.get("position", Vector2.ZERO))
	var nd: float      = nose_to_target_dot(ship, target)
	var in_zone: bool  = dist <= ENGAGE_FIRE_RANGE and nd >= ENGAGE_ARC_DOT
	match current:
		"firing_pass":
			if age > ENGAGE_FIRING_PASS_BASE_DURATION * hot: return "extending"
			if not in_zone and age > 0.4: return "extending"
			if dist < ENGAGE_OVERSHOOT_RANGE: return "extending"
			return "firing_pass"
		"extending":
			if age > ENGAGE_EXTEND_BASE_DURATION * cold: return "repositioning"
			if dist > ENGAGE_EXTEND_DISTANCE: return "repositioning"
			return "extending"
		"repositioning":
			if nd >= ENGAGE_FACING_DOT and age > 0.3: return "approach"
			if age > ENGAGE_REPOSITION_TIMEOUT * hot: return "approach"
			return "repositioning"
		_:
			return "firing_pass" if in_zone else "approach"
