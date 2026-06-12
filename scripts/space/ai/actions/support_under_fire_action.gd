class_name SupportUnderFireAction
extends FighterAction

## Attack an enemy that is currently sitting on a friendly's six.
## Requires display skill ≥ 12 (internal 0.6): the pilot needs enough
## situational awareness to notice an ally being attacked.

const MIN_SKILL      = 0.6    # display 12
const BASE_COST      = 0.7
const SCAN_RANGE     = 2000.0
const SIX_RANGE      = 700.0
const SIX_NOSE_DOT   = 0.85   # attacker must be pointing at ally


func action_id() -> String: return "support_under_fire"

func cost(ws: FighterWorldState) -> float:
	# Cheaper when we already face the attacker (saves setup time)
	var attacker := _find_attacker(ws)
	if attacker.is_empty(): return BASE_COST
	var my_pos: Vector2 = ws.my_ship.get("position", Vector2.ZERO)
	var at_pos: Vector2 = attacker.get("position", Vector2.ZERO)
	var d: float = my_pos.distance_to(at_pos)
	return BASE_COST - clamp(0.15 * (1.0 - d / SCAN_RANGE), 0.0, 0.15)


func precondition(ws: FighterWorldState) -> bool:
	if ws.skill < MIN_SKILL: return false
	return not _find_attacker(ws).is_empty()


func execute(ws: FighterWorldState) -> Dictionary:
	var attacker := _find_attacker(ws)
	if attacker.is_empty():
		# Precondition should prevent this, but guard anyway
		return {}
	var phase_info := FighterAction.step_engagement_phase(
		ws.crew_data, ws.my_ship, attacker, ws.game_time
	)
	var phase: String = phase_info.phase
	var threat: Dictionary = FighterWorldState.get_ship(
		FighterAction.closest_enemy_id(ws.my_ship, ws.all_ships), ws.all_ships
	)
	var evasion_dir := 0
	if not threat.is_empty():
		evasion_dir = FighterAction.evasion_direction(ws.my_ship, attacker)
	var maneuver := FighterAction.phase_to_maneuver(phase)
	if maneuver == "": maneuver = "fight_pursue_tactical"
	return {
		"type": "maneuver",
		"subtype": maneuver,
		"crew_id": ws.crew_data.get("crew_id", ""),
		"entity_id": ws.my_ship.get("ship_id", ""),
		"target_id": attacker.get("ship_id", ""),
		"skill_factor": ws.skill,
		"delay": ws.crew_data.get("stats", {}).get("reaction_time", 0.1),
		"timestamp": ws.game_time,
		"evasion_direction": evasion_dir,
		"behind_position": _behind_pos(attacker, ws.aim),
	}


func _find_attacker(ws: FighterWorldState) -> Dictionary:
	var my_team: int    = ws.my_ship.get("team", -1)
	var my_pos: Vector2 = ws.my_ship.get("position", Vector2.ZERO)
	for ally in ws.all_ships:
		if ally.get("team", -1) != my_team: continue
		if ally.get("ship_id", "") == ws.my_ship.get("ship_id", ""): continue
		if ally.get("status", "") != "operational": continue
		if not FleetDataManager.is_fighter_class(ally.get("type", "")): continue
		for enemy in ws.all_ships:
			if enemy.get("team", -1) == my_team: continue
			if enemy.get("status", "") != "operational": continue
			if not FleetDataManager.is_fighter_class(enemy.get("type", "")): continue
			var d_enemy_ally: float = enemy.get("position", Vector2.ZERO).distance_to(ally.get("position", Vector2.ZERO))
			if d_enemy_ally > SIX_RANGE: continue
			if FighterAction.nose_to_target_dot(enemy, ally) < SIX_NOSE_DOT: continue
			# Enemy is on ally's six — is it close enough for me to help?
			var d_me_enemy: float = my_pos.distance_to(enemy.get("position", Vector2.ZERO))
			if d_me_enemy <= SCAN_RANGE:
				return enemy
	return {}


static func _behind_pos(target: Dictionary, aim: float) -> Vector2:
	var t_pos: Vector2  = target.get("position", Vector2.ZERO)
	var t_rot: float    = target.get("rotation", 0.0)
	var t_vel: Vector2  = target.get("velocity", Vector2.ZERO)
	var offset: Vector2 = Vector2(cos(t_rot + PI), sin(t_rot + PI)) * 550.0
	var pred: Vector2   = t_pos + t_vel * lerp(0.1, 0.8, aim)
	var err: Vector2    = Vector2(cos(randf_range(0.0, TAU)), sin(randf_range(0.0, TAU))) * ((1.0 - aim) * 100.0)
	return pred + offset + err
