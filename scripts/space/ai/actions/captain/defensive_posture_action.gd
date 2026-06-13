class_name DefensivePostureAction
extends CaptainAction

## Defensive posture — angle armor when outnumbered.

func action_id() -> String: return "defensive_posture"

func cost(_ws: CaptainWorldState) -> float: return CaptainAction.COST_REFLEX

func precondition(ws: CaptainWorldState) -> bool:
	if not ws.has_threats:
		return false
	if ws.command_style == CrewIntegrationSystem.CommandStyle.STANDARD:
		return ws.threat_count > CaptainAction.STANDARD_DEFENSIVE_THREAT_COUNT
	if ws.command_style >= CrewIntegrationSystem.CommandStyle.TACTICAL:
		return ws.threat_count > CaptainAction.DEFENSIVE_THREAT_COUNT
	return false

func execute(ws: CaptainWorldState) -> Dictionary:
	var orders := CaptainAction.orders_to_subordinates(ws, {"type": "defensive_posture", "subtype": "angle_armor"})
	return {
		"decision": CaptainAction.make_captain_decision(ws, "defensive_posture", null),
		"issued_orders": orders,
	}
