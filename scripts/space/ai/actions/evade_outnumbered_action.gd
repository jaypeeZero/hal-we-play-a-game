class_name EvadeOutnumberedAction
extends FighterAction

## Tactical disengagement when outnumbered without support.
## Different from the survival reflex (which fires regardless of skill and is
## unconditional). This action is skill-gated: low-skill pilots don't recognise
## they're outnumbered until it's very bad; elite pilots break proactively.

func action_id() -> String: return "evade_outnumbered"
func cost(_ws: FighterWorldState) -> float: return 0.4


func precondition(ws: FighterWorldState) -> bool:
	if not ws.am_outnumbered:
		return false
	# Skill gates how early the pilot recognises and responds:
	#   < 0.4 (display 0–7): only bail when nearly dead
	#   < 0.7 (display 8–13): bail at 50% armor
	#   ≥ 0.7 (display 14–20): bail proactively when outgunned OR at 70% armor
	if ws.skill < 0.4:
		return ws.armor_ratio < 0.3
	elif ws.skill < 0.7:
		return ws.armor_ratio < 0.5
	else:
		return ws.armor_ratio < 0.7 or ws.nearby_friends == 0


func execute(ws: FighterWorldState) -> Dictionary:
	var threat_id := FighterAction.closest_enemy_id(ws.my_ship, ws.all_ships)
	var threat: Dictionary = FighterWorldState.get_ship(threat_id, ws.all_ships)
	var evasion_dir := 0
	if not threat.is_empty():
		evasion_dir = FighterAction.evasion_direction(ws.my_ship, threat)
	return {
		"type": "maneuver",
		"subtype": "fight_defensive_break",
		"crew_id": ws.crew_data.get("crew_id", ""),
		"entity_id": ws.my_ship.get("ship_id", ""),
		"target_id": threat_id,
		"skill_factor": ws.skill,
		"delay": 0.3,
		"timestamp": ws.game_time,
		"evasion_direction": evasion_dir,
	}
