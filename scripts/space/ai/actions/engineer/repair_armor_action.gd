class_name RepairArmorAction
extends EngineerAction

## Repair the most-damaged armor section.
## Cost: ARMOR_COST_BASE + ratio — always higher than any RepairInternalAction,
## so internals win triage. Within the armor band, worst section is preferred.

func action_id() -> String: return "repair_armor"

func cost(ws: EngineerWorldState) -> float:
	return EngineerAction.ARMOR_COST_BASE + ws.worst_armor.get("ratio", 1.0)

func precondition(ws: EngineerWorldState) -> bool:
	return ws.repair_pool_remaining > 0 and not ws.worst_armor.is_empty()

func execute(ws: EngineerWorldState) -> Dictionary:
	return EngineerAction.make_repair_decision(
		ws,
		EngineerAction.ARMOR_REPAIR_SUBTYPE,
		"section_id",
		ws.worst_armor.get("section_id", "")
	)
