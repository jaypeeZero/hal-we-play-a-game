class_name StrategicWithdrawalAction
extends CommanderAction

## Withdraw all forces when outnumbered beyond the threshold.

func action_id() -> String: return "strategic_withdrawal"
func cost(_ws: CommanderWorldState) -> float: return CommanderAction.COST_WITHDRAWAL

func precondition(ws: CommanderWorldState) -> bool:
	return "strategic_withdrawal" in ws.knowledge_actions \
		and ws.has_threats \
		and ws.threat_count > ws.subordinate_count * CommanderAction.WITHDRAWAL_THREAT_MULTIPLIER

func execute(ws: CommanderWorldState) -> Dictionary:
	var orders := CommanderAction.orders_to_subordinates(ws, {
		"type": "withdraw",
		"subtype": "strategic",
		"priority": "preserve_force",
	})
	return {
		"decision": CommanderAction.make_strategic_decision(ws, "strategic_withdrawal"),
		"issued_orders": orders,
	}
