class_name ShiftFocusAction
extends CommanderAction

## Redirect all squadrons to a new best target.

func action_id() -> String: return "shift_focus"
func cost(_ws: CommanderWorldState) -> float: return CommanderAction.COST_SHIFT

func precondition(ws: CommanderWorldState) -> bool:
	return "shift_focus" in ws.knowledge_actions and ws.has_opportunities

func execute(ws: CommanderWorldState) -> Dictionary:
	var target_id: String = ws.best_target.get("id", "")
	var orders := CommanderAction.orders_to_subordinates(ws, {
		"type": "engage",
		"target_id": target_id,
		"subtype": "redirect",
	})
	return {
		"decision": CommanderAction.make_strategic_decision(
			ws, "shift_focus", {"new_focus": target_id}
		),
		"issued_orders": orders,
	}
