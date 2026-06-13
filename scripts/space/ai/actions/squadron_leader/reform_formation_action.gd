class_name ReformFormationAction
extends SquadronLeaderAction

## Reform scattered formation into wedge — LOOSE+ only, no active threats.

func action_id() -> String: return "reform_formation"
func cost(_ws: SquadronLeaderWorldState) -> float: return SquadronLeaderAction.COST_REFORM

func precondition(ws: SquadronLeaderWorldState) -> bool:
	return ws.coordination_style >= CrewIntegrationSystem.CoordinationStyle.LOOSE \
		and ws.is_scattered \
		and not ws.has_threats

func execute(ws: SquadronLeaderWorldState) -> Dictionary:
	var orders := SquadronLeaderAction.orders_to_subordinates(ws, {
		"type": "formation",
		"subtype": "reform",
		"formation": "wedge",
	})
	return {
		"decision": SquadronLeaderAction.make_squadron_decision(
			ws, "reform_formation", {"formation": "wedge"}
		),
		"issued_orders": orders,
	}
