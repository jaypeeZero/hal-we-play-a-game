class_name AggressivePursuitAction
extends CaptainAction

## Aggressive pursuit — ADAPTIVE captains only, when opportunities exist without threats.

func action_id() -> String: return "aggressive_pursuit"

func cost(_ws: CaptainWorldState) -> float: return CaptainAction.COST_KNOWLEDGE

func precondition(ws: CaptainWorldState) -> bool:
	# Only ADAPTIVE captains execute aggressive pursuit
	return ws.command_style == CrewIntegrationSystem.CommandStyle.ADAPTIVE \
		and ws.has_opportunities \
		and not ws.has_threats

func execute(ws: CaptainWorldState) -> Dictionary:
	var target_id: String = ws.mission_target.get("id", "")
	var orders := CaptainAction.orders_to_subordinates(ws, {
		"type": "engage",
		"subtype": "aggressive_pursuit",
		"target_id": target_id,
		"priority": "destroy",
	})
	return {
		"decision": CaptainAction.make_captain_decision(ws, "aggressive_pursuit", target_id),
		"issued_orders": orders,
	}
