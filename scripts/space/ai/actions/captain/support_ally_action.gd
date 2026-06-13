class_name SupportAllyAction
extends CaptainAction

## Escort and protect a damaged friendly — TACTICAL+ captains only.

func action_id() -> String: return "support_ally"

func cost(_ws: CaptainWorldState) -> float: return CaptainAction.COST_CARE

func precondition(ws: CaptainWorldState) -> bool:
	return ws.command_style >= CrewIntegrationSystem.CommandStyle.TACTICAL \
		and not ws.damaged_friendly.is_empty()

func execute(ws: CaptainWorldState) -> Dictionary:
	var ally_id: String = ws.damaged_friendly.get("id", "")
	var orders := CaptainAction.orders_to_subordinates(ws, {
		"type": "support_ally",
		"subtype": "escort",
		"ally_id": ally_id,
	})
	return {
		"decision": CaptainAction.make_captain_decision(ws, "support_ally", ally_id),
		"issued_orders": orders,
	}
