class_name CaptainEngageAction
extends CaptainAction

## Standard engage — pursue when threats or opportunities exist.

func action_id() -> String: return "engage"

func cost(_ws: CaptainWorldState) -> float: return CaptainAction.COST_STANDARD

func precondition(ws: CaptainWorldState) -> bool:
	return ws.has_threats or ws.has_opportunities

func execute(ws: CaptainWorldState) -> Dictionary:
	var target_id: String = ws.mission_target.get("id", "")
	var orders := CaptainAction.orders_to_subordinates(ws, {
		"type": "engage",
		"subtype": "pursue",
		"target_id": target_id,
	})
	return {
		"decision": CaptainAction.make_captain_decision(ws, "engage", target_id),
		"issued_orders": orders,
	}
