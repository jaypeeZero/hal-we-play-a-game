class_name CutOffAction
extends FighterAction

## Intercept a fleeing target before it escapes.
## Requires display skill ≥ 15 (internal 0.75): the pilot needs the tactical
## awareness to read the target's escape vector and calculate intercept geometry.

const MIN_SKILL      = 0.75   # display 15
const BASE_COST      = 0.6
const FLEEING_SPEED  = 80.0   # target must be moving at least this fast away
const FLEE_DOT       = -0.5   # target velocity must be heading away from me


func action_id() -> String: return "cut_off"
func cost(_ws: FighterWorldState) -> float: return BASE_COST


func precondition(ws: FighterWorldState) -> bool:
	if ws.skill < MIN_SKILL: return false
	if ws.target_ship.is_empty(): return false
	if not _target_is_fleeing(ws): return false
	# Need at least one ally also pursuing the target (cut-off is pointless alone)
	return ws.allies_engaging_target >= 1


func execute(ws: FighterWorldState) -> Dictionary:
	var intercept := _predict_intercept(ws)
	return {
		"type": "maneuver",
		"subtype": "fight_pursue_full_speed",
		"crew_id": ws.crew_data.get("crew_id", ""),
		"entity_id": ws.my_ship.get("ship_id", ""),
		"target_id": ws.target_id,
		"skill_factor": ws.skill,
		"delay": ws.crew_data.get("stats", {}).get("reaction_time", 0.1),
		"timestamp": ws.game_time,
		"formation_position": intercept,
		"behind_position": intercept,
	}


func _target_is_fleeing(ws: FighterWorldState) -> bool:
	var t_vel: Vector2 = ws.target_ship.get("velocity", Vector2.ZERO)
	if t_vel.length() < FLEEING_SPEED: return false
	var t_pos: Vector2 = ws.target_ship.get("position", Vector2.ZERO)
	var my_pos: Vector2 = ws.my_ship.get("position", Vector2.ZERO)
	var away: Vector2 = (t_pos - my_pos).normalized()
	return t_vel.normalized().dot(away) >= abs(FLEE_DOT)


func _predict_intercept(ws: FighterWorldState) -> Vector2:
	var my_pos: Vector2  = ws.my_ship.get("position", Vector2.ZERO)
	var my_spd: float    = ws.my_ship.get("stats", {}).get("max_speed", 200.0)
	var t_pos: Vector2   = ws.target_ship.get("position", Vector2.ZERO)
	var t_vel: Vector2   = ws.target_ship.get("velocity", Vector2.ZERO)

	# Simple linear intercept: guess time to reach target, predict target position
	var dist: float = my_pos.distance_to(t_pos)
	var time_est: float = max(0.1, dist / max(my_spd, 1.0))
	# Scale by aim quality: high aim → accurate prediction; low aim → crude guess
	time_est *= lerp(0.3, 1.0, ws.aim)

	var predicted := t_pos + t_vel * time_est
	# Apply aim error
	var err := Vector2(cos(randf_range(0.0, TAU)), sin(randf_range(0.0, TAU))) * ((1.0 - ws.aim) * 200.0)
	return predicted + err
