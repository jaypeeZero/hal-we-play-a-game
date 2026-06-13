class_name AssignTargetsAction
extends SquadronLeaderAction

## Assign targets to squadron ships with skill-tiered quality.
## INDIVIDUAL leaders may fail to coordinate at all (coordination_failed gate).

func action_id() -> String: return "assign_targets"
func cost(_ws: SquadronLeaderWorldState) -> float: return SquadronLeaderAction.COST_ASSIGN

func precondition(ws: SquadronLeaderWorldState) -> bool:
	if not ws.has_opportunities:
		return false
	# INDIVIDUAL leaders occasionally fail entirely
	if ws.coordination_style == CrewIntegrationSystem.CoordinationStyle.INDIVIDUAL:
		return not ws.coordination_failed
	return true

func execute(ws: SquadronLeaderWorldState) -> Dictionary:
	var skill: float       = CrewAISystem.calculate_effective_skill(ws.crew_data)
	var subordinates: Array = ws.crew_data.get("command_chain", {}).get("subordinates", [])
	var targets: Array     = ws.crew_data.get("awareness", {}).get("opportunities", []).duplicate()
	var mission: String    = ws.crew_data.get("squadron_mission", SquadronData.Mission.FREE)
	var params: Dictionary = ws.crew_data.get("squadron_mission_params", {})

	var quality: float = lerp(
		WingConstants.SQUADRON_ASSIGNMENT_QUALITY_MIN,
		WingConstants.SQUADRON_ASSIGNMENT_QUALITY_MAX,
		skill
	)

	if quality > SquadronLeaderAction.HIGH_SKILL_THRESHOLD:
		targets.sort_custom(func(a, b):
			return SquadronLeaderAction.calculate_target_priority_score(a, mission, params) \
				 > SquadronLeaderAction.calculate_target_priority_score(b, mission, params)
		)
	elif quality > SquadronLeaderAction.MEDIUM_SKILL_THRESHOLD:
		var half: int = targets.size() / 2
		if half > 0:
			var top := targets.slice(0, half)
			top.sort_custom(func(a, b):
				return SquadronLeaderAction.calculate_target_priority_score(a, mission, params) \
					 > SquadronLeaderAction.calculate_target_priority_score(b, mission, params)
			)
			for i in half:
				targets[i] = top[i]
	else:
		targets.shuffle()

	var orders: Array = []
	for i in subordinates.size():
		if i < targets.size():
			orders.append({
				"to": subordinates[i],
				"type": "engage",
				"target_id": targets[i].get("id", ""),
			})

	return {
		"decision": SquadronLeaderAction.make_squadron_decision(
			ws, "assign_targets", {"assignments": orders}
		),
		"issued_orders": orders,
	}
