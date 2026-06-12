class_name PatrolReturnAction
extends FighterAction

## Return to assigned patrol area when well outside it and no target in sight.

func action_id() -> String: return "patrol_return"
func cost(_ws: FighterWorldState) -> float: return 0.7


func precondition(ws: FighterWorldState) -> bool:
	return ws.is_far_outside_area and ws.target_id == ""


func execute(ws: FighterWorldState) -> Dictionary:
	return {
		"type": "maneuver",
		"subtype": "fight_return_to_area",
		"crew_id": ws.crew_data.get("crew_id", ""),
		"entity_id": ws.my_ship.get("ship_id", ""),
		"target_id": "",
		"skill_factor": ws.skill,
		"delay": 0.4,
		"timestamp": ws.game_time,
	}
