class_name CaptainWithdrawAction
extends CaptainAction

## Withdraw — triggered by extreme threat priority, critical damage, or REACTIVE panic.

func action_id() -> String: return "withdraw"

func cost(_ws: CaptainWorldState) -> float: return CaptainAction.COST_REFLEX

func precondition(ws: CaptainWorldState) -> bool:
	if not ws.has_threats:
		return false
	# Tactical/Adaptive: knowledge- or situation-driven withdraw
	if ws.command_style >= CrewIntegrationSystem.CommandStyle.TACTICAL:
		return ws.top_threat_priority > CaptainAction.WITHDRAW_THREAT_PRIORITY or ws.is_critically_damaged
	if ws.command_style == CrewIntegrationSystem.CommandStyle.STANDARD:
		return ws.is_critically_damaged
	# REACTIVE: panic-based
	return ws.threat_count >= CaptainAction.DEFENSIVE_THREAT_COUNT and ws.panic_withdraw_roll

func execute(ws: CaptainWorldState) -> Dictionary:
	var orders := CaptainAction.orders_to_subordinates(ws, {"type": "withdraw", "subtype": "evade"})
	return {
		"decision": CaptainAction.make_captain_decision(ws, "withdraw", null),
		"issued_orders": orders,
	}
