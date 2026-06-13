class_name ScreenWithdrawalAction
extends SquadronLeaderAction

## Rearguard screen while survivors withdraw — LOOSE+ only, threats > subordinates.

func action_id() -> String: return "screen_withdrawal"
func cost(_ws: SquadronLeaderWorldState) -> float: return SquadronLeaderAction.COST_SCREEN

func precondition(ws: SquadronLeaderWorldState) -> bool:
	return ws.coordination_style >= CrewIntegrationSystem.CoordinationStyle.LOOSE \
		and ws.threat_count > ws.subordinate_count

func execute(ws: SquadronLeaderWorldState) -> Dictionary:
	var subordinates: Array = ws.crew_data.get("command_chain", {}).get("subordinates", [])
	var orders: Array = []
	for i in subordinates.size():
		var role := "rearguard" if i < subordinates.size() / 2 else "withdraw"
		orders.append({
			"to": subordinates[i],
			"type": "withdraw" if role == "withdraw" else "engage",
			"subtype": role,
			"priority": "cover_retreat",
		})
	return {
		"decision": SquadronLeaderAction.make_squadron_decision(ws, "screen_withdrawal"),
		"issued_orders": orders,
	}
