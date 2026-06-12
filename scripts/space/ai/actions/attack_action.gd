class_name AttackAction
extends FighterAction

## Standard attack action. Handles fighter-vs-fighter and fighter-vs-capital.
## This is the fallback when no more specific tactic applies.
## Always available when a valid target exists (highest base cost = last choice).

const BASE_COST = 1.0


func action_id() -> String: return "attack"

func cost(ws: FighterWorldState) -> float:
	# Aggressive pilots slightly prefer attacking over any other option
	return BASE_COST - ws.aggression * 0.15

func precondition(ws: FighterWorldState) -> bool:
	return not ws.target_ship.is_empty()


func execute(ws: FighterWorldState) -> Dictionary:
	if ws.target_is_capital:
		return _vs_capital(ws)
	else:
		return _vs_fighter(ws)


func _vs_fighter(ws: FighterWorldState) -> Dictionary:
	var jink := FighterAction.jink_params(ws.skill)
	var astyle := FighterAction.approach_style_for(ws.skill, ws.position_advantage, ws.aggression)
	var aangle := FighterAction.approach_angle_for(ws.skill)

	var phase_info := FighterAction.step_engagement_phase(
		ws.crew_data, ws.my_ship, ws.target_ship, ws.game_time
	)
	var phase: String = phase_info.phase

	# Knowledge-system maneuver selection
	var ctx := {
		"behind": ws.position_advantage == "behind",
		"disadvantaged": ws.position_advantage == "disadvantaged",
		"nearby_fighters": ws.nearby_friends,
	}
	var maneuver := FighterAction.query_knowledge(ws.my_ship, ws.target_ship, ctx, ws.crew_data)
	if maneuver == "" or maneuver == "idle":
		maneuver = "fight_pursue_full_speed"

	# Threat on six overrides knowledge; then engagement phase overrides knowledge
	if not ws.threat_on_six.is_empty():
		maneuver = "fight_defensive_break"
	else:
		var phase_m := FighterAction.phase_to_maneuver(phase)
		if phase_m != "":
			maneuver = phase_m

	var evasion_dir := 0
	if maneuver in ["fight_dodge_and_weave", "fight_lateral_break", "fight_evasive_turn", "fight_defensive_break"]:
		var threat := ws.threat_on_six if not ws.threat_on_six.is_empty() else ws.target_ship
		evasion_dir = FighterAction.evasion_direction(ws.my_ship, threat)

	return {
		"type": "maneuver",
		"subtype": maneuver,
		"crew_id": ws.crew_data.get("crew_id", ""),
		"entity_id": ws.my_ship.get("ship_id", ""),
		"target_id": ws.target_id,
		"skill_factor": ws.skill,
		"delay": ws.crew_data.get("stats", {}).get("reaction_time", 0.1),
		"timestamp": ws.game_time,
		"behind_position": ws.behind_position,
		"evasion_direction": evasion_dir,
		"approach_style": astyle,
		"position_advantage": ws.position_advantage,
		"jink_amplitude": jink.amplitude,
		"jink_hold_ms": jink.hold_ms,
		"approach_angle": aangle,
		"formation_offset": _formation_offset(ws),
	}


func _vs_capital(ws: FighterWorldState) -> Dictionary:
	var dist: float = ws.my_ship.get("position", Vector2.ZERO).distance_to(
		ws.target_ship.get("position", Vector2.ZERO)
	)
	var ctx := {
		"behind": false,
		"disadvantaged": false,
		"nearby_fighters": ws.nearby_friends,
	}
	var maneuver := FighterAction.query_knowledge(ws.my_ship, ws.target_ship, ctx, ws.crew_data)

	if maneuver == "" or maneuver == "idle":
		if ws.nearby_friends >= FighterAction.GROUP_RUN_THRESHOLD:
			maneuver = "fight_group_run_approach"
		else:
			maneuver = "fight_dodge_and_weave"

	return {
		"type": "maneuver",
		"subtype": maneuver,
		"crew_id": ws.crew_data.get("crew_id", ""),
		"entity_id": ws.my_ship.get("ship_id", ""),
		"target_id": ws.target_id,
		"skill_factor": ws.skill,
		"delay": ws.crew_data.get("stats", {}).get("reaction_time", 0.1),
		"timestamp": ws.game_time,
		"nearby_fighters": ws.nearby_friends,
	}


func _formation_offset(ws: FighterWorldState) -> Vector2:
	# Preserve the existing formation offset calculation for wingmen
	if ws.wing_role != "wingman" or ws.lead_ship.is_empty():
		return Vector2.ZERO
	var pos_side: int = ws.wing_info.get("position_side", 1)
	var slot_rank: int = ws.wing_info.get("slot_rank", 0)
	return WingFormationSystem.calculate_wing_position(ws.lead_ship, pos_side, ws.skill, slot_rank) \
		- ws.my_ship.get("position", Vector2.ZERO)
