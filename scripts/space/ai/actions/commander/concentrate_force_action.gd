class_name ConcentrateForceAction
extends CommanderAction

## Focus all squadrons on the best target.

func action_id() -> String: return "concentrate_force"
func cost(_ws: CommanderWorldState) -> float: return CommanderAction.COST_CONCENTRATE

func precondition(ws: CommanderWorldState) -> bool:
	return "concentrate_force" in ws.knowledge_actions and ws.has_opportunities

func execute(ws: CommanderWorldState) -> Dictionary:
	var target_id: String = ws.best_target.get("id", "")
	var orders := CommanderAction.orders_to_subordinates(ws, {
		"type": "engage",
		"target_id": target_id,
		"priority": "concentrate",
	})
	return {
		"decision": CommanderAction.make_strategic_decision(ws, "concentrate_force"),
		"issued_orders": orders,
	}
