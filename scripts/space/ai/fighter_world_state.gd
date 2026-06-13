class_name FighterWorldState
extends RefCounted

## Snapshot of a fighter's tactical situation, built once per decision tick.
## Centralises all the per-decision lookups that were scattered across the old
## 1 800-line fighter_pilot_ai.  Actions read from this; they never rebuild it.

# Raw inputs (held by reference — actions may write to crew_data.combat_state)
var crew_data: Dictionary
var my_ship: Dictionary
var all_ships: Array
var all_crew: Array
var game_time: float
var wings: Array

# Skills
var skill: float       # piloting  (0–1, display × 20)
var aggression: float
var aim: float
var tactics: float

# Target
var target_id: String
var target_ship: Dictionary   # empty dict when no target
var target_is_capital: bool

# Tactical position
var position_advantage: String   # "behind" | "disadvantaged" | "neutral"
var threat_on_six: Dictionary    # empty dict when clear
var behind_position: Vector2
var armor_ratio: float           # 0–1 hull health

# Group situation
var allies_engaging_target: int         # friendlies currently on the same target
var ally_approach_angles: Array         # Vector2[] — direction from target → each ally
var nearby_enemies: int                 # fighter-class enemies within detection range
var nearby_friends: int
var am_outnumbered: bool

# Wing situation
var in_wing: bool
var wing_role: String      # "lead" | "wingman" | ""
var wing_info: Dictionary
var lead_ship: Dictionary
var lead_crew: Dictionary
var is_in_formation: bool  # wingman only
var lead_phase: String     # lead's engagement phase, wingman only

# Area
var is_far_outside_area: bool

# Combat posture (Layer A/B/C)
var press_attack: bool          # true while a valid press_attack posture is active
var posture_target_id: String   # concentrate-fire target from posture; "" if none


static func build(
	p_crew: Dictionary,
	p_ship: Dictionary,
	p_all_ships: Array,
	p_all_crew: Array,
	p_game_time: float,
	p_wings: Array
) -> FighterWorldState:
	var ws := FighterWorldState.new()
	ws.crew_data  = p_crew
	ws.my_ship    = p_ship
	ws.all_ships  = p_all_ships
	ws.all_crew   = p_all_crew
	ws.game_time  = p_game_time
	ws.wings      = p_wings

	var skills: Dictionary = p_crew.get("stats", {}).get("skills", {})
	ws.skill      = skills.get("piloting", 0.5)
	ws.aggression = skills.get("aggression", 0.5)
	ws.aim        = skills.get("aim", ws.skill)
	ws.tactics    = skills.get("tactics", 0.5)

	# Wing info — must come before target resolution so wingmen follow lead's target
	ws.wing_info      = WingFormationSystem.get_wing_info(p_crew.get("crew_id", ""), p_wings)
	ws.in_wing        = not ws.wing_info.is_empty()
	ws.wing_role      = ws.wing_info.get("role", "")
	ws.lead_ship      = {}
	ws.lead_crew      = {}
	ws.is_in_formation = false
	ws.lead_phase     = "approach"
	if ws.wing_role == "wingman":
		var wing: Dictionary = ws.wing_info.get("wing", {})
		ws.lead_ship = get_ship(wing.get("lead_ship_id", ""), p_all_ships)
		var lead_crew_id: String = wing.get("lead_crew_id", "")
		for c in p_all_crew:
			if c.get("crew_id", "") != lead_crew_id: continue
			ws.lead_crew  = c
			ws.lead_phase = c.get("combat_state", {}).get("engagement_phase", "approach")
			break
		if not ws.lead_ship.is_empty():
			ws.is_in_formation = WingFormationSystem.is_in_formation(p_ship, ws.lead_ship, ws.skill)

	# Target — wingmen follow lead's target; others pick their own
	if ws.wing_role == "wingman" and not ws.wing_info.is_empty():
		var lead_tgt := WingFormationSystem.get_lead_target(ws.wing_info.get("wing", {}), p_all_crew)
		if lead_tgt != "" and _ship_valid(lead_tgt, p_all_ships):
			ws.target_id = lead_tgt
		else:
			ws.target_id = _resolve_target(p_crew, p_all_ships, p_all_crew, p_game_time)
	else:
		ws.target_id = _resolve_target(p_crew, p_all_ships, p_all_crew, p_game_time)

	ws.target_ship = get_ship(ws.target_id, p_all_ships)
	ws.target_is_capital = (
		not ws.target_ship.is_empty()
		and FleetDataManager.is_large_ship(ws.target_ship.get("type", ""))
	)

	# Position advantage & behind-position
	if not ws.target_ship.is_empty():
		ws.position_advantage = _position_advantage(p_ship, ws.target_ship)
		ws.behind_position    = _behind_position(ws.target_ship, ws.aim)
	else:
		ws.position_advantage = "neutral"
		ws.behind_position    = Vector2.ZERO

	# Threats
	ws.threat_on_six = _threat_on_six(p_ship, p_all_ships)

	# Hull health
	ws.armor_ratio = _armor_ratio(p_ship)

	# Nearby combatants (fighter-class only)
	var my_team: int    = p_ship.get("team", -1)
	var my_pos: Vector2 = p_ship.get("position", Vector2.ZERO)
	var my_id: String   = p_ship.get("ship_id", "")
	ws.nearby_enemies = 0
	ws.nearby_friends = 0
	for s in p_all_ships:
		if s.get("ship_id", "") == my_id: continue
		if s.get("status", "") != "operational": continue
		if not FleetDataManager.is_fighter_class(s.get("type", "")): continue
		var d: float = my_pos.distance_to(s.get("position", Vector2.ZERO))
		if s.get("team", -1) == my_team:
			if d < 2000.0: ws.nearby_friends += 1
		else:
			if d < 2500.0: ws.nearby_enemies += 1
	ws.am_outnumbered = ws.nearby_enemies > ws.nearby_friends + 1

	# Allies engaging the same target
	ws.allies_engaging_target = 0
	ws.ally_approach_angles   = []
	if ws.target_id != "":
		var t_pos: Vector2 = ws.target_ship.get("position", Vector2.ZERO)
		for c in p_all_crew:
			if c.get("crew_id", "") == p_crew.get("crew_id", ""): continue
			# Read target from the crew member's active decision
			var c_orders  = c.get("orders", {})
			var c_target: String = c_orders.get("target_id", "")
			var c_current = c_orders.get("current")
			if c_current is Dictionary:
				c_target = c_current.get("target_id", c_target)
			if c_target != ws.target_id: continue
			ws.allies_engaging_target += 1
			var ally_ship: Dictionary = get_ship(c.get("assigned_to", ""), p_all_ships)
			if not ally_ship.is_empty():
				var a_pos: Vector2 = ally_ship.get("position", Vector2.ZERO)
				ws.ally_approach_angles.append((a_pos - t_pos).normalized())

	# Area leash
	ws.is_far_outside_area = _far_outside_area(p_ship)

	# Combat posture (Layer A/B/C) — read from persistent crew_data.combat_posture slot.
	var posture: Dictionary = p_crew.get("combat_posture", {})
	var posture_subtype: String = posture.get("subtype", "")
	var player_override: bool   = posture.get("player_override", false)
	ws.press_attack = (
		posture_subtype == "press_attack"
		and (player_override or p_game_time < posture.get("expires_at", 0.0))
	)
	ws.posture_target_id = posture.get("target_id", "") if ws.press_attack else ""

	# Honor posture concentrate-fire target: override the resolved target when the
	# posture specifies one and the ship is still valid.
	if ws.press_attack and ws.posture_target_id != "" \
			and _ship_valid(ws.posture_target_id, p_all_ships):
		ws.target_id   = ws.posture_target_id
		ws.target_ship = get_ship(ws.target_id, p_all_ships)
		ws.target_is_capital = (
			not ws.target_ship.is_empty()
			and FleetDataManager.is_large_ship(ws.target_ship.get("type", ""))
		)

	return ws


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

static func _resolve_target(
	crew_data: Dictionary, all_ships: Array, all_crew: Array, game_time: float
) -> String:
	if not crew_data.get("is_squadron_leader", false):
		var leader_target := _squadron_leader_target(crew_data, all_crew)
		if leader_target != "" and _ship_valid(leader_target, all_ships):
			return leader_target
	return _best_target_with_crew(crew_data, all_ships, all_crew, game_time)


static func _best_target_with_crew(
	crew_data: Dictionary, all_ships: Array, all_crew: Array, game_time: float
) -> String:
	var skill: float      = crew_data.get("stats", {}).get("skills", {}).get("piloting", 0.5)
	var aggression: float = crew_data.get("stats", {}).get("skills", {}).get("aggression", 0.5)
	var combat_state: Dictionary = crew_data.get("combat_state", {})
	var own_ship: Dictionary = get_ship(crew_data.get("assigned_to", ""), all_ships)
	var my_team: int = own_ship.get("team", -1)

	var locked: String = combat_state.get("locked_target_id", "")
	var locked_until: float = combat_state.get("target_locked_until", 0.0)
	if locked != "" and _ship_valid(locked, all_ships) and game_time < locked_until:
		# Elite pilots break lock when a significantly closer threat enters close range
		if skill >= WingConstants.CLOSE_TARGET_RELOCK_SKILL and not own_ship.is_empty():
			var my_pos: Vector2 = own_ship.get("position", Vector2.ZERO)
			for s in all_ships:
				if s.get("team", -1) == my_team or s.get("team", -1) < 0: continue
				if s.get("status", "") != "operational": continue
				if s.get("ship_id", "") == locked: continue
				if my_pos.distance_to(s.get("position", Vector2.ZERO)) < FighterAction.CLOSE_RANGE:
					locked = ""
					break
		if locked != "":
			return locked
	if skill < 0.3 and locked != "" and _ship_valid(locked, all_ships):
		return locked

	var candidates: Array = []
	for s in all_ships:
		if s.get("team", -1) == my_team or s.get("team", -1) < 0: continue
		if s.get("status", "") != "operational": continue
		candidates.append({ "id": s.get("ship_id", ""), "score": score_target(crew_data, s, all_ships, all_crew) })

	if candidates.is_empty():
		return ""

	var selected := ""
	if skill >= WingConstants.LEAD_PICK_BEST_SKILL:
		candidates.sort_custom(func(a, b): return a.score > b.score)
		selected = candidates[0].id
	elif skill >= WingConstants.LEAD_PICK_TOP_THREE_SKILL:
		candidates.sort_custom(func(a, b): return a.score > b.score)
		var top := mini(3, candidates.size())
		selected = candidates[randi() % top].id
	else:
		selected = candidates[randi() % candidates.size()].id

	if selected != "":
		var dur: float = lerp(4.0, 8.0, aggression) if skill >= 0.3 else 12.0
		combat_state["locked_target_id"]   = selected
		combat_state["target_locked_until"] = game_time + dur

	return selected


## Public: score a single target candidate for a crew member.
## Exposed so FighterPilotAI can delegate test calls to this.
static func score_target(
	crew_data: Dictionary, target_ship: Dictionary, all_ships: Array, all_crew: Array
) -> float:
	var skill: float       = crew_data.get("stats", {}).get("skills", {}).get("piloting", 0.5)
	var own_ship: Dictionary = get_ship(crew_data.get("assigned_to", ""), all_ships)
	var my_pos: Vector2    = own_ship.get("position", Vector2.ZERO) if not own_ship.is_empty() else Vector2.ZERO
	var t_pos: Vector2     = target_ship.get("position", Vector2.ZERO)
	var dist: float        = my_pos.distance_to(t_pos)
	var score := 0.0

	# Distance: closer is better
	score += max(0.0, WingConstants.TARGET_SCORE_DISTANCE_MAX - dist) / WingConstants.TARGET_SCORE_DISTANCE_DIVISOR

	# Damaged targets: only high-skill pilots notice
	if skill >= WingConstants.LEAD_NOTICE_DAMAGED_SKILL:
		var hull = target_ship.get("stats", {}).get("hull", {})
		var h_cur: float = float(hull.get("current", 100))
		var h_max: float = float(hull.get("max", 100))
		score += (1.0 - h_cur / h_max) * WingConstants.TARGET_SCORE_DAMAGED_WEIGHT

	# Deconfliction / concentrate fire
	var my_id: String      = crew_data.get("crew_id", "")
	var t_id: String       = target_ship.get("ship_id", "")
	var t_type: String     = target_ship.get("type", "")
	var engager_count: int = count_friendlies_engaging(t_id, all_crew, my_id)
	if FleetDataManager.is_large_ship(t_type):
		if skill >= WingConstants.LEAD_COORDINATE_FIRE_SKILL:
			score += engager_count * WingConstants.TARGET_SCORE_FRIENDLY_ENGAGING_WEIGHT
	elif skill >= WingConstants.LEAD_DECONFLICT_SKILL:
		score -= engager_count * WingConstants.TARGET_SCORE_DECONFLICTION_PENALTY

	# Threat facing: targets pointed at us score higher
	var awareness_skill: float = crew_data.get("stats", {}).get("skills", {}).get("awareness", skill)
	if awareness_skill >= WingConstants.LEAD_NOTICE_THREATS_SKILL:
		var t_rot: float    = target_ship.get("rotation", 0.0)
		var t_facing        := Vector2(cos(t_rot), sin(t_rot))
		var to_me           := (my_pos - t_pos).normalized()
		if abs(t_facing.angle_to(to_me)) < deg_to_rad(WingConstants.TARGET_SCORE_THREAT_FACING_ANGLE):
			score += WingConstants.TARGET_SCORE_THREAT_FACING_WEIGHT

	# Squadron focus bonus
	var sq_focus := _squadron_leader_target(crew_data, all_crew)
	if sq_focus != "" and t_id == sq_focus:
		score += WingConstants.TARGET_SCORE_SQUADRON_FOCUS_BONUS

	return score


## Public: count how many crew members (excluding exclude_id) are targeting
## a given ship. Used for deconfliction and concentrate-fire scoring.
static func count_friendlies_engaging(
	target_id: String, all_crew: Array, exclude_id: String
) -> int:
	var count := 0
	for c in all_crew:
		if c.get("crew_id", "") == exclude_id: continue
		var orders = c.get("orders", {}).get("current")
		if orders is Dictionary and orders.get("target_id", "") == target_id:
			count += 1
	return count


static func _squadron_leader_target(crew_data: Dictionary, all_crew: Array) -> String:
	var chain = crew_data.get("command_chain", {})
	if not chain is Dictionary: return ""
	var raw_leader = chain.get("superior", "")
	var leader_id: String = raw_leader if raw_leader is String else ""
	if leader_id == "": return ""
	for c in all_crew:
		if c.get("crew_id", "") != leader_id: continue
		var orders = c.get("orders", {}).get("current")
		if orders is Dictionary:
			var t_id = orders.get("target_id", "")
			return t_id if t_id is String else ""
	return ""


static func _position_advantage(my_ship: Dictionary, target: Dictionary) -> String:
	var t_pos: Vector2  = target.get("position", Vector2.ZERO)
	var t_rot: float    = target.get("rotation", 0.0)
	var my_pos: Vector2 = my_ship.get("position", Vector2.ZERO)
	var to_me: Vector2  = (my_pos - t_pos).normalized()
	var t_face: Vector2 = Vector2(cos(t_rot), sin(t_rot))
	if abs(abs(rad_to_deg(t_face.angle_to(to_me))) - 180.0) < 20.0:
		return "behind"
	var my_rot: float     = my_ship.get("rotation", 0.0)
	var to_tgt: Vector2   = (t_pos - my_pos).normalized()
	var my_face: Vector2  = Vector2(cos(my_rot), sin(my_rot))
	if abs(abs(rad_to_deg(my_face.angle_to(to_tgt))) - 180.0) < 20.0:
		return "disadvantaged"
	return "neutral"


static func _behind_position(target: Dictionary, aim: float) -> Vector2:
	var t_pos: Vector2 = target.get("position", Vector2.ZERO)
	var t_rot: float   = target.get("rotation", 0.0)
	var t_vel: Vector2 = target.get("velocity", Vector2.ZERO)
	var offset: Vector2 = Vector2(cos(t_rot + PI), sin(t_rot + PI)) * 550.0
	var pred: Vector2   = t_pos + t_vel * lerp(0.1, 0.8, aim)
	var err: Vector2    = Vector2(cos(randf_range(0.0, TAU)), sin(randf_range(0.0, TAU))) * ((1.0 - aim) * 100.0)
	return pred + offset + err


static func _threat_on_six(ship: Dictionary, all_ships: Array) -> Dictionary:
	var my_team: int    = ship.get("team", -1)
	var my_id: String   = ship.get("ship_id", "")
	var my_pos: Vector2 = ship.get("position", Vector2.ZERO)
	for s in all_ships:
		if s.get("ship_id", "") == my_id: continue
		if s.get("status", "") != "operational": continue
		if s.get("team", -1) == my_team: continue
		if not FleetDataManager.is_fighter_class(s.get("type", "")): continue
		var d: float = my_pos.distance_to(s.get("position", Vector2.ZERO))
		if d > 700.0 or d < 1.0: continue
		if _nose_dot(s, ship) >= 0.85:
			return s
	return {}


static func _armor_ratio(ship: Dictionary) -> float:
	var sections: Array = ship.get("armor_sections", [])
	if sections.is_empty(): return 1.0
	var cur := 0.0
	var mx  := 0.0
	for s in sections:
		cur += float(s.get("current_armor", 0))
		mx  += float(s.get("max_armor", 0))
	return cur / mx if mx > 0.0 else 1.0


static func _far_outside_area(ship: Dictionary) -> bool:
	var area = ship.get("assigned_area")
	if area == null or not area is Dictionary: return false
	var radius: float = area.get("radius", 0.0)
	if radius <= 0.0: return false
	return ship.get("position", Vector2.ZERO).distance_to(area.get("center", Vector2.ZERO)) > radius * 1.5


static func _nose_dot(ship: Dictionary, target: Dictionary) -> float:
	var rot: float     = ship.get("rotation", 0.0)
	var forward        := Vector2(sin(rot), -cos(rot))
	var to_tgt: Vector2 = (target.get("position", Vector2.ZERO) - ship.get("position", Vector2.ZERO)).normalized()
	return forward.dot(to_tgt)


# Public helpers used by action files
static func get_ship(ship_id: String, all_ships: Array) -> Dictionary:
	for s in all_ships:
		if s.get("ship_id", "") == ship_id:
			return s
	return {}


static func _ship_valid(ship_id: String, all_ships: Array) -> bool:
	var s := get_ship(ship_id, all_ships)
	return not s.is_empty() and s.get("status", "") != "destroyed"
