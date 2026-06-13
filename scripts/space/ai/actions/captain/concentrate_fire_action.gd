class_name ConcentrateFireAction
extends CaptainAction

## Concentrate all fire on the highest-value target.

func action_id() -> String: return "concentrate_fire"

func cost(_ws: CaptainWorldState) -> float: return CaptainAction.COST_KNOWLEDGE

func precondition(ws: CaptainWorldState) -> bool:
	if not ws.has_opportunities:
		return false
	# Requires TACTICAL+ or knowledge suggestion
	if ws.command_style < CrewIntegrationSystem.CommandStyle.TACTICAL:
		return "concentrate_fire" in ws.knowledge_actions
	return "concentrate_fire" in ws.knowledge_actions or ws.command_style >= CrewIntegrationSystem.CommandStyle.TACTICAL

func execute(ws: CaptainWorldState) -> Dictionary:
	var target: Dictionary = ws.damaged_target if not ws.damaged_target.is_empty() else ws.mission_target
	var target_id: String  = target.get("id", "")
	var orders := CaptainAction.orders_to_subordinates(ws, {
		"type": "engage",
		"subtype": "concentrate_fire",
		"target_id": target_id,
		"priority": "focus",
	})
	return {
		"decision": CaptainAction.make_captain_decision(ws, "concentrate_fire", target_id),
		"issued_orders": orders,
	}
