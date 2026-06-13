class_name SuppressiveFireAction
extends GunnerAction

## Suppressive fire — rapid cycle across multiple targets.
## Precondition implies target_count >= SUPPRESSIVE_TARGET_COUNT_THRESHOLD
## (that gate is folded into knowledge_action).

const BASE_COST = 0.3

func action_id() -> String: return "suppressive_fire"
func cost(_ws: GunnerWorldState) -> float: return BASE_COST

func precondition(ws: GunnerWorldState) -> bool:
	# knowledge_action already gates on target_count >= SUPPRESSIVE_TARGET_COUNT_THRESHOLD
	return ws.knowledge_action == "suppressive_fire" and not ws.opportunities.is_empty()

func execute(ws: GunnerWorldState) -> Dictionary:
	var target_id: String = ws.opportunities[0].get("id", "") if not ws.opportunities.is_empty() else ""
	return GunnerAction.make_fire_decision(ws, target_id, "suppressive_fire")
