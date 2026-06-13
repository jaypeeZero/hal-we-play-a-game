class_name CoordinateAttackRunAction
extends SquadronLeaderAction

## Synchronized attack run — ORCHESTRATED leaders only with enough subordinates.

func action_id() -> String: return "coordinate_attack_run"
func cost(_ws: SquadronLeaderWorldState) -> float: return SquadronLeaderAction.COST_COORDINATE

func precondition(ws: SquadronLeaderWorldState) -> bool:
	return ws.coordination_style == CrewIntegrationSystem.CoordinationStyle.ORCHESTRATED \
		and ws.has_opportunities \
		and ws.subordinate_count >= SquadronLeaderAction.COORDINATED_ATTACK_MIN_SUBORDINATES

func execute(ws: SquadronLeaderWorldState) -> Dictionary:
	var target: Dictionary = CrewAIShared.select_best_tactical_target(ws.crew_data)
	var target_id: String  = target.get("id", "")
	var orders := SquadronLeaderAction.orders_to_subordinates(ws, {
		"type": "engage",
		"subtype": "coordinated_attack",
		"target_id": target_id,
		"timing": "synchronized",
	})
	return {
		"decision": SquadronLeaderAction.make_squadron_decision(
			ws, "coordinate_attack_run", {"target_id": target_id}
		),
		"issued_orders": orders,
	}
