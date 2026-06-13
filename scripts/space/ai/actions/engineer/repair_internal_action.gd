class_name RepairInternalAction
extends EngineerAction

## Repair the most-damaged internal component.
## Cost: INTERNAL_COST_BASE + ratio — worst internals (low ratio) cost less,
## so the most-damaged item is always preferred within the band.

func action_id() -> String: return "repair_internal"

func cost(ws: EngineerWorldState) -> float:
	return EngineerAction.INTERNAL_COST_BASE + ws.worst_internal.get("ratio", 1.0)

func precondition(ws: EngineerWorldState) -> bool:
	return not ws.worst_internal.is_empty()

func execute(ws: EngineerWorldState) -> Dictionary:
	return EngineerAction.make_repair_decision(
		ws,
		ws.worst_internal.get("subtype", EngineerAction.REPAIR_SUBTYPE_PREFIX + "component"),
		"component_id",
		ws.worst_internal.get("component_id", "")
	)
