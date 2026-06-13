class_name HoldFireAction
extends GunnerAction

## Hold fire — knowledge said to hold (e.g. low ammo gate is folded into
## knowledge_action). Cheapest action so it wins when the precondition fires.

const BASE_COST = 0.2

func action_id() -> String: return "hold_fire"
func cost(_ws: GunnerWorldState) -> float: return BASE_COST

func precondition(ws: GunnerWorldState) -> bool:
	return ws.knowledge_action == "hold_fire"

func execute(ws: GunnerWorldState) -> Dictionary:
	return {
		"type": "fire",
		"subtype": "hold_fire",
		"crew_id": ws.crew_data.get("crew_id", ""),
		"entity_id": ws.crew_data.get("assigned_to", ""),
		"target_id": "",
		"skill_factor": ws.effective_skill,
		"delay": 0.0,
		"timestamp": ws.game_time,
	}
