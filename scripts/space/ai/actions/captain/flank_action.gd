class_name CaptainFlankAction
extends CaptainAction

## Maneuver to enemy's weak arc — TACTICAL+ captains, limited threats.

func action_id() -> String: return "flank"

func cost(_ws: CaptainWorldState) -> float: return CaptainAction.COST_CARE

func precondition(ws: CaptainWorldState) -> bool:
	return ws.command_style >= CrewIntegrationSystem.CommandStyle.TACTICAL \
		and ws.has_opportunities \
		and ws.threat_count <= CaptainAction.FLANK_MAX_THREATS

func execute(ws: CaptainWorldState) -> Dictionary:
	var target_id: String = ws.mission_target.get("id", "")
	var orders := CaptainAction.orders_to_subordinates(ws, {
		"type": "engage",
		"subtype": "flank",
		"target_id": target_id,
		"maneuver": "lateral",
	})
	return {
		"decision": CaptainAction.make_captain_decision(ws, "flank", target_id),
		"issued_orders": orders,
	}
