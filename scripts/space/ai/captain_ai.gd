extends RefCounted
class_name CaptainAI

## Pure functional captain role AI.
## Knowledge-driven ship-level tactical decisions, command-style modulated.
## Issues subordinate orders for engage/withdraw/flank/etc.

const REDECIDE_MIN = 1.0
const REDECIDE_MAX = 2.0

# Critical-damage heuristic
const CRITICAL_STRESS_THRESHOLD = 0.7
const CRITICAL_THREAT_COUNT = 3

# Captain knowledge thresholds
const WITHDRAW_THREAT_PRIORITY = 200.0
const DEFENSIVE_THREAT_COUNT = 2
const STANDARD_DEFENSIVE_THREAT_COUNT = 3
const FLANK_MAX_THREATS = 1

# REACTIVE captain probabilities (low-skill panic / hesitation)
const REACTIVE_PANIC_WITHDRAW_CHANCE = 0.4
const REACTIVE_HOLD_INSTEAD_OF_ENGAGE_CHANCE = 0.3
const REACTIVE_HESITATE_ON_OPPORTUNITY_CHANCE = 0.3


## Public entry point - called by CrewAISystem dispatcher.
static func make_decision(crew_data: Dictionary, game_time: float) -> Dictionary:
	# Check for orders from squadron leader
	if crew_data.orders.received != null:
		return _execute_order(crew_data, game_time)

	# Make tactical decision and issue orders to crew
	return _make_ship_tactical_decision(crew_data, game_time)


## Execute order from squadron leader
static func _execute_order(crew_data: Dictionary, game_time: float) -> Dictionary:
	var order = crew_data.orders.received
	var updated = crew_data.duplicate(true)

	# Process order and break it down for subordinates
	updated.orders.current = order
	updated.orders.received = null

	# Issue orders to subordinates (will be processed by CommandChainSystem)
	var subordinate_orders = _break_down_order(order, updated)
	updated.orders.issued = subordinate_orders

	return {
		"crew_data": updated,
		"decision": _create_captain_decision(updated, order, game_time)
	}


## Make ship-level tactical decision - KNOWLEDGE-DRIVEN with expanded actions
static func _make_ship_tactical_decision(crew_data: Dictionary, game_time: float) -> Dictionary:
	var updated = crew_data.duplicate(true)

	# Query knowledge for tactical guidance
	var situation = TacticalMemorySystem.generate_situation_summary(crew_data)
	var knowledge = TacticalKnowledgeSystem.query_captain_knowledge(situation, 3, crew_data.get("known_patterns", []))

	# Analyze situation
	var has_threats = not crew_data.awareness.threats.is_empty()
	var has_opportunities = not crew_data.awareness.opportunities.is_empty()

	# Check for damaged friendlies that need support
	var damaged_friendly = _find_damaged_friendly(crew_data)

	var decision = null
	var subordinate_orders = []

	# Use knowledge to select tactical action
	var tactical_action = _select_action_from_knowledge(knowledge, crew_data, has_threats, has_opportunities, damaged_friendly != null)

	# Execute selected action
	match tactical_action:
		"withdraw":
			subordinate_orders = _create_withdraw_orders(crew_data)
			decision = _create_captain_decision(updated, {"type": "withdraw"}, game_time)

		"defensive_posture":
			subordinate_orders = _create_defensive_posture_orders(crew_data)
			decision = _create_captain_decision(updated, {"type": "defensive_posture"}, game_time)

		"concentrate_fire":
			var target = _select_damaged_target(crew_data)
			if target.is_empty():
				target = CrewAIShared.select_best_tactical_target(crew_data)
			subordinate_orders = _create_concentrate_fire_orders(crew_data, target)
			decision = _create_captain_decision(updated, {"type": "concentrate_fire", "target_id": target.get("id", "")}, game_time)

		"aggressive_pursuit":
			var target = CrewAIShared.select_best_tactical_target(crew_data)
			subordinate_orders = _create_aggressive_pursuit_orders(crew_data, target)
			decision = _create_captain_decision(updated, {"type": "aggressive_pursuit", "target_id": target.get("id", "")}, game_time)

		"support_ally":
			if damaged_friendly != null:
				subordinate_orders = _create_support_ally_orders(crew_data, damaged_friendly)
				decision = _create_captain_decision(updated, {"type": "support_ally", "target_id": damaged_friendly.get("id", "")}, game_time)
			else:
				# Fallback to engage
				var target = CrewAIShared.select_best_tactical_target(crew_data)
				subordinate_orders = _create_engage_orders(crew_data, target)
				decision = _create_captain_decision(updated, {"type": "engage", "target_id": target.get("id", "")}, game_time)

		"flank":
			var target = CrewAIShared.select_best_tactical_target(crew_data)
			subordinate_orders = _create_flank_orders(crew_data, target)
			decision = _create_captain_decision(updated, {"type": "flank", "target_id": target.get("id", "")}, game_time)

		"hold":
			subordinate_orders = _create_hold_orders(crew_data)
			decision = _create_captain_decision(updated, {"type": "hold"}, game_time)

		"engage", _:
			if has_threats or has_opportunities:
				var target = CrewAIShared.select_best_tactical_target(crew_data)
				subordinate_orders = _create_engage_orders(crew_data, target)
				decision = _create_captain_decision(updated, {"type": "engage", "target_id": target.get("id", "")}, game_time)

	updated.orders.current = decision
	updated.orders.issued = subordinate_orders

	# Set next decision time
	updated.next_decision_time = game_time + randf_range(REDECIDE_MIN, REDECIDE_MAX)

	if decision:
		return {"crew_data": updated, "decision": decision}
	return {"crew_data": updated}


## Select captain action based on knowledge, situation, and COMMAND STYLE
## REACTIVE: Only responds to immediate threats, poor prioritization
## STANDARD: Follows doctrine, reasonable priorities
## TACTICAL: Anticipates situations, coordinates crew effectively
## ADAPTIVE: Reads the battle, adjusts strategy dynamically
static func _select_action_from_knowledge(knowledge: Array, crew_data: Dictionary, has_threats: bool, has_opportunities: bool, has_damaged_friendly: bool) -> String:
	var skill = CrewAISystem.calculate_effective_skill(crew_data)
	var command_style = CrewIntegrationSystem._select_command_style(skill)

	# Default action based on command style
	var action = "engage" if (has_threats or has_opportunities) else "hold"

	# REACTIVE captains (low skill) - poor decision making
	if command_style == CrewIntegrationSystem.CommandStyle.REACTIVE:
		# Often makes suboptimal choices
		if has_threats:
			# Low skill captains panic and may withdraw prematurely
			if crew_data.awareness.threats.size() >= DEFENSIVE_THREAT_COUNT and randf() < REACTIVE_PANIC_WITHDRAW_CHANCE:
				return "withdraw"
			# Or just hold when they should engage
			if randf() < REACTIVE_HOLD_INSTEAD_OF_ENGAGE_CHANCE:
				return "hold"
		# Miss opportunities
		if has_opportunities and randf() < REACTIVE_HESITATE_ON_OPPORTUNITY_CHANCE:
			return "hold"  # Hesitates instead of engaging
		return action

	# STANDARD captains follow doctrine
	if command_style == CrewIntegrationSystem.CommandStyle.STANDARD:
		if has_threats and crew_data.awareness.threats.size() > STANDARD_DEFENSIVE_THREAT_COUNT:
			return "defensive_posture"
		if has_opportunities:
			return "engage"
		return action

	# TACTICAL and ADAPTIVE captains use knowledge effectively
	if knowledge.is_empty():
		# Even without knowledge, tactical+ captains make good choices
		if command_style >= CrewIntegrationSystem.CommandStyle.TACTICAL:
			if has_damaged_friendly:
				return "support_ally"
			if has_opportunities and crew_data.awareness.threats.size() <= FLANK_MAX_THREATS:
				return "flank"
		return action

	# Check each knowledge result for tactical+ captains
	for k in knowledge:
		var suggested_action = k.get("content", {}).get("action", "")
		if suggested_action == "":
			continue

		# Validate action is appropriate for situation
		match suggested_action:
			"withdraw":
				if has_threats:
					var top_threat = crew_data.awareness.threats[0]
					var threat_priority = top_threat.get("_threat_priority", 0.0)
					if threat_priority > WITHDRAW_THREAT_PRIORITY or _is_ship_critically_damaged(crew_data):
						return "withdraw"

			"defensive_posture":
				if has_threats and crew_data.awareness.threats.size() > DEFENSIVE_THREAT_COUNT:
					return "defensive_posture"

			"concentrate_fire":
				if has_opportunities:
					return "concentrate_fire"

			"aggressive_pursuit":
				# Only ADAPTIVE captains use aggressive pursuit
				if command_style == CrewIntegrationSystem.CommandStyle.ADAPTIVE:
					if has_opportunities and not has_threats:
						return "aggressive_pursuit"

			"support_ally":
				if has_damaged_friendly:
					return "support_ally"

			"flank":
				# Tactical+ captains can execute flanking maneuvers
				if command_style >= CrewIntegrationSystem.CommandStyle.TACTICAL:
					if has_opportunities and crew_data.awareness.threats.size() <= FLANK_MAX_THREATS:
						return "flank"

			"hold":
				if not has_threats and not has_opportunities:
					return "hold"

			"engage":
				if has_threats or has_opportunities:
					return "engage"

	return action


## Check if ship is critically damaged
static func _is_ship_critically_damaged(crew_data: Dictionary) -> bool:
	var threats = crew_data.get("awareness", {}).get("threats", [])
	var threat_count = threats.size()
	var stress = crew_data.get("stats", {}).get("stress", 0.0)

	# Consider critically damaged if high stress and many threats
	if stress > CRITICAL_STRESS_THRESHOLD and threat_count >= CRITICAL_THREAT_COUNT:
		return true

	return false


## Find damaged friendly in awareness
static func _find_damaged_friendly(crew_data: Dictionary) -> Variant:
	var known = crew_data.awareness.get("known_entities", [])
	if typeof(known) == TYPE_ARRAY:
		for entity in known:
			if typeof(entity) == TYPE_DICTIONARY:
				if entity.get("is_friendly", false) and entity.get("status", "") in ["damaged", "critical"]:
					return entity
	return null


## Select a damaged target for concentrate fire
static func _select_damaged_target(crew_data: Dictionary) -> Dictionary:
	for opp in crew_data.awareness.opportunities:
		if opp.get("status", "") in ["damaged", "disabled", "critical"]:
			return opp
	return {}


## Break down captain order for subordinates
static func _break_down_order(order: Dictionary, crew_data: Dictionary) -> Array:
	# Convert captain's order into specific orders for pilot and gunners
	match order.get("type"):
		"engage":
			return _create_engage_orders(crew_data, {"id": order.get("target_id")})
		"withdraw":
			return _create_withdraw_orders(crew_data)
		_:
			return []


## Create engage orders for subordinates
static func _create_engage_orders(crew_data: Dictionary, target: Dictionary) -> Array:
	var orders = []

	# Order pilot to pursue
	for sub_id in crew_data.command_chain.subordinates:
		orders.append({
			"to": sub_id,
			"type": "engage",
			"subtype": "pursue",
			"target_id": target.id
		})

	return orders


## Create withdraw orders
static func _create_withdraw_orders(crew_data: Dictionary) -> Array:
	var orders = []

	for sub_id in crew_data.command_chain.subordinates:
		orders.append({
			"to": sub_id,
			"type": "withdraw",
			"subtype": "evade"
		})

	return orders


## Create defensive posture orders - angle armor, limit exposure
static func _create_defensive_posture_orders(crew_data: Dictionary) -> Array:
	var orders = []

	for sub_id in crew_data.command_chain.subordinates:
		orders.append({
			"to": sub_id,
			"type": "defensive_posture",
			"subtype": "angle_armor"
		})

	return orders


## Create concentrate fire orders - all weapons on one target
static func _create_concentrate_fire_orders(crew_data: Dictionary, target: Dictionary) -> Array:
	var orders = []

	for sub_id in crew_data.command_chain.subordinates:
		orders.append({
			"to": sub_id,
			"type": "engage",
			"subtype": "concentrate_fire",
			"target_id": target.get("id", ""),
			"priority": "focus"
		})

	return orders


## Create aggressive pursuit orders - press the attack
static func _create_aggressive_pursuit_orders(crew_data: Dictionary, target: Dictionary) -> Array:
	var orders = []

	for sub_id in crew_data.command_chain.subordinates:
		orders.append({
			"to": sub_id,
			"type": "engage",
			"subtype": "aggressive_pursuit",
			"target_id": target.get("id", ""),
			"priority": "destroy"
		})

	return orders


## Create support ally orders - protect damaged friendly
static func _create_support_ally_orders(crew_data: Dictionary, ally: Variant) -> Array:
	var orders = []
	var ally_id = ally.get("id", "") if ally is Dictionary else ""

	for sub_id in crew_data.command_chain.subordinates:
		orders.append({
			"to": sub_id,
			"type": "support_ally",
			"subtype": "escort",
			"ally_id": ally_id
		})

	return orders


## Create flank orders - maneuver to enemy's weak arc
static func _create_flank_orders(crew_data: Dictionary, target: Dictionary) -> Array:
	var orders = []

	for sub_id in crew_data.command_chain.subordinates:
		orders.append({
			"to": sub_id,
			"type": "engage",
			"subtype": "flank",
			"target_id": target.get("id", ""),
			"maneuver": "lateral"
		})

	return orders


## Create hold orders - maintain position
static func _create_hold_orders(crew_data: Dictionary) -> Array:
	var orders = []

	for sub_id in crew_data.command_chain.subordinates:
		orders.append({
			"to": sub_id,
			"type": "hold",
			"subtype": "maintain_position"
		})

	return orders


## Create captain decision
static func _create_captain_decision(crew_data: Dictionary, order: Dictionary, game_time: float) -> Dictionary:
	return {
		"type": "tactical",
		"subtype": order.get("type", "hold"),
		"crew_id": crew_data.crew_id,
		"entity_id": crew_data.assigned_to,
		"target_id": order.get("target_id"),
		"delay": CrewAISystem.calculate_decision_delay(crew_data),
		"timestamp": game_time
	}
