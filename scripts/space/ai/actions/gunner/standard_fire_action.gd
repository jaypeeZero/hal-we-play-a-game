class_name StandardFireAction
extends GunnerAction

## Standard fire — the default when opportunities exist and no specific mode
## was suggested by knowledge. Highest base cost so knowledge-driven actions win.

const BASE_COST = 1.0

func action_id() -> String: return "standard_fire"
func cost(_ws: GunnerWorldState) -> float: return BASE_COST

func precondition(ws: GunnerWorldState) -> bool:
	return not ws.opportunities.is_empty()

func execute(ws: GunnerWorldState) -> Dictionary:
	var target_id: String = ws.priority_target.get("id", "") if not ws.priority_target.is_empty() else ""
	return GunnerAction.make_fire_decision(ws, target_id, "fire")
