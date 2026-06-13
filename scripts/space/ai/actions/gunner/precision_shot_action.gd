class_name PrecisionShotAction
extends GunnerAction

## Precision shot — careful aim at the highest-value target.

const BASE_COST = 0.3

func action_id() -> String: return "precision_shot"
func cost(_ws: GunnerWorldState) -> float: return BASE_COST

func precondition(ws: GunnerWorldState) -> bool:
	return ws.knowledge_action == "precision_shot" and not ws.opportunities.is_empty()

func execute(ws: GunnerWorldState) -> Dictionary:
	var target_id: String = ws.best_target.get("id", "") if not ws.best_target.is_empty() else ""
	return GunnerAction.make_fire_decision(ws, target_id, "precision_shot")
