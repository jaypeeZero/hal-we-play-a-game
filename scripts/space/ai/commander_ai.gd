extends RefCounted
class_name CommanderAI

## Pure functional fleet commander role AI.
## Strategic decisions across all squadrons - concentrate force, withdraw, shift focus.

const REDECIDE_MIN = 2.0
const REDECIDE_MAX = 4.0

# Strategic-withdrawal trigger: outnumbered by this multiple
const WITHDRAWAL_THREAT_MULTIPLIER = 2


## Public entry point - called by CrewAISystem dispatcher.
static func make_decision(crew_data: Dictionary, game_time: float) -> Dictionary:
	var updated = crew_data.duplicate(true)

	# Query knowledge for strategic guidance
	var situation = TacticalMemorySystem.generate_situation_summary(crew_data)
	var knowledge = TacticalKnowledgeSystem.query_commander_knowledge(situation, 3, crew_data.get("known_patterns", []))

	# Analyze strategic situation
	var has_threats = not crew_data.awareness.threats.is_empty()
	var has_opportunities = not crew_data.awareness.opportunities.is_empty()
	var total_threats = crew_data.awareness.threats.size()

	# Select action based on knowledge
	var strategic_action = _select_action_from_knowledge(knowledge, crew_data, has_threats, has_opportunities, total_threats)

	var decision = null
	var orders = []

	match strategic_action:
		"concentrate_force":
			orders = _create_concentrate_force_orders(crew_data)
			decision = {
				"type": "strategic",
				"subtype": "concentrate_force",
				"crew_id": crew_data.crew_id,
				"delay": CrewAISystem.calculate_decision_delay(crew_data),
				"timestamp": game_time
			}

		"strategic_withdrawal":
			orders = _create_strategic_withdrawal_orders(crew_data)
			decision = {
				"type": "strategic",
				"subtype": "strategic_withdrawal",
				"crew_id": crew_data.crew_id,
				"delay": CrewAISystem.calculate_decision_delay(crew_data),
				"timestamp": game_time
			}

		"commit_reserves":
			orders = _create_commit_reserves_orders(crew_data)
			decision = {
				"type": "strategic",
				"subtype": "commit_reserves",
				"crew_id": crew_data.crew_id,
				"delay": CrewAISystem.calculate_decision_delay(crew_data),
				"timestamp": game_time
			}

		"shift_focus":
			var new_target = CrewAIShared.select_best_tactical_target(crew_data)
			orders = _create_shift_focus_orders(crew_data, new_target)
			decision = {
				"type": "strategic",
				"subtype": "shift_focus",
				"crew_id": crew_data.crew_id,
				"new_focus": new_target.get("id", ""),
				"delay": CrewAISystem.calculate_decision_delay(crew_data),
				"timestamp": game_time
			}

		"hold_line":
			orders = _create_hold_line_orders(crew_data)
			decision = {
				"type": "strategic",
				"subtype": "hold_line",
				"crew_id": crew_data.crew_id,
				"delay": CrewAISystem.calculate_decision_delay(crew_data),
				"timestamp": game_time
			}

		"assess", _:
			decision = {
				"type": "strategic",
				"subtype": "assess",
				"crew_id": crew_data.crew_id,
				"delay": CrewAISystem.calculate_decision_delay(crew_data),
				"timestamp": game_time
			}

	if decision:
		updated.orders.issued = orders
		updated.orders.current = decision
		updated.next_decision_time = game_time + randf_range(REDECIDE_MIN, REDECIDE_MAX)
		return {"crew_data": updated, "decision": decision}

	return {"crew_data": updated}


## Select commander action from knowledge
static func _select_action_from_knowledge(knowledge: Array, crew_data: Dictionary, has_threats: bool, has_opportunities: bool, total_threats: int) -> String:
	var action = "assess"

	if knowledge.is_empty():
		return action

	for k in knowledge:
		var suggested_action = k.get("content", {}).get("action", "")
		if suggested_action == "":
			continue

		match suggested_action:
			"concentrate_force":
				if has_opportunities:
					return "concentrate_force"

			"strategic_withdrawal":
				if has_threats and total_threats > crew_data.command_chain.subordinates.size() * WITHDRAWAL_THREAT_MULTIPLIER:
					return "strategic_withdrawal"

			"commit_reserves":
				# TODO: Check if we have reserves
				pass

			"shift_focus":
				if has_opportunities:
					return "shift_focus"

			"hold_line":
				if has_threats and not has_opportunities:
					return "hold_line"

	return action


## Create concentrate force orders
static func _create_concentrate_force_orders(crew_data: Dictionary) -> Array:
	var orders = []
	var target = CrewAIShared.select_best_tactical_target(crew_data)

	for sub_id in crew_data.command_chain.subordinates:
		orders.append({
			"to": sub_id,
			"type": "engage",
			"target_id": target.get("id", ""),
			"priority": "concentrate"
		})

	return orders


## Create strategic withdrawal orders
static func _create_strategic_withdrawal_orders(crew_data: Dictionary) -> Array:
	var orders = []

	for sub_id in crew_data.command_chain.subordinates:
		orders.append({
			"to": sub_id,
			"type": "withdraw",
			"subtype": "strategic",
			"priority": "preserve_force"
		})

	return orders


## Create commit reserves orders
static func _create_commit_reserves_orders(crew_data: Dictionary) -> Array:
	var orders = []

	for sub_id in crew_data.command_chain.subordinates:
		orders.append({
			"to": sub_id,
			"type": "engage",
			"subtype": "all_forces",
			"priority": "decisive"
		})

	return orders


## Create shift focus orders
static func _create_shift_focus_orders(crew_data: Dictionary, new_target: Dictionary) -> Array:
	var orders = []

	for sub_id in crew_data.command_chain.subordinates:
		orders.append({
			"to": sub_id,
			"type": "engage",
			"target_id": new_target.get("id", ""),
			"subtype": "redirect"
		})

	return orders


## Create hold line orders
static func _create_hold_line_orders(crew_data: Dictionary) -> Array:
	var orders = []

	for sub_id in crew_data.command_chain.subordinates:
		orders.append({
			"to": sub_id,
			"type": "hold",
			"subtype": "defensive_line",
			"stance": "no_retreat"
		})

	return orders
