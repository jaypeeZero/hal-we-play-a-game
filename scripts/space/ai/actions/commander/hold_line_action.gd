class_name HoldLineAction
extends CommanderAction

## Defensive hold — threats present, no opportunities.

func action_id() -> String: return "hold_line"
func cost(_ws: CommanderWorldState) -> float: return CommanderAction.COST_HOLD_LINE

func precondition(ws: CommanderWorldState) -> bool:
	return "hold_line" in ws.knowledge_actions and ws.has_threats and not ws.has_opportunities

func execute(ws: CommanderWorldState) -> Dictionary:
	var orders := CommanderAction.orders_to_subordinates(ws, {
		"type": "hold",
		"subtype": "defensive_line",
		"stance": "no_retreat",
	})
	return {
		"decision": CommanderAction.make_strategic_decision(ws, "hold_line"),
		"issued_orders": orders,
	}
