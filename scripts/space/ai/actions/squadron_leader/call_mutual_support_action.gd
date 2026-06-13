class_name CallMutualSupportAction
extends SquadronLeaderAction

## Protect a damaged subordinate — LOOSE+ coordination style only.

func action_id() -> String: return "call_mutual_support"
func cost(_ws: SquadronLeaderWorldState) -> float: return SquadronLeaderAction.COST_MUTUAL_SUPPORT

func precondition(ws: SquadronLeaderWorldState) -> bool:
	return ws.coordination_style >= CrewIntegrationSystem.CoordinationStyle.LOOSE \
		and not ws.damaged_subordinate.is_empty()

func execute(ws: SquadronLeaderWorldState) -> Dictionary:
	var ship_id: String = ws.damaged_subordinate.get("id", "")
	var orders := SquadronLeaderAction.orders_to_subordinates(ws, {
		"type": "support_ally",
		"ally_id": ship_id,
		"priority": "protect",
	})
	return {
		"decision": SquadronLeaderAction.make_squadron_decision(
			ws, "call_mutual_support", {"protected_ship": ship_id}
		),
		"issued_orders": orders,
	}
