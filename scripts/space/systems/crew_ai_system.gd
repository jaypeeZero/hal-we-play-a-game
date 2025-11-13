class_name CrewAISystem
extends RefCounted

## Pure functional crew AI system
## Handles role-based decision making for hierarchical command structure
## Following functional programming principles - all data is immutable

# ============================================================================
# MAIN API - Process crew decisions
# ============================================================================

## Update all crew members and generate their decisions
static func update_all_crew(crew_list: Array, delta: float, game_time: float) -> Dictionary:
	var updated_crew = []
	var decisions = []

	for crew in crew_list:
		var result = update_crew_member(crew, delta, game_time)
		updated_crew.append(result.crew_data)
		if result.has("decision"):
			decisions.append(result.decision)

	return {
		"crew_list": updated_crew,
		"decisions": decisions
	}

## Update single crew member and generate decision
static func update_crew_member(crew_data: Dictionary, delta: float, game_time: float) -> Dictionary:
	# Update stress/fatigue
	var updated = update_crew_state(crew_data, delta)

	# Check if crew can make decisions
	if not can_make_decisions(updated):
		return {"crew_data": updated}

	# Make role-based decision
	match updated.role:
		CrewData.Role.PILOT:
			return make_pilot_decision(updated, game_time)
		CrewData.Role.GUNNER:
			return make_gunner_decision(updated, game_time)
		CrewData.Role.CAPTAIN:
			return make_captain_decision(updated, game_time)
		CrewData.Role.SQUADRON_LEADER:
			return make_squadron_leader_decision(updated, game_time)
		CrewData.Role.FLEET_COMMANDER:
			return make_commander_decision(updated, game_time)
		_:
			return {"crew_data": updated}

# ============================================================================
# CREW STATE MANAGEMENT
# ============================================================================

## Update crew stress and fatigue
static func update_crew_state(crew_data: Dictionary, delta: float) -> Dictionary:
	var updated = crew_data.duplicate(true)

	# Stress decays over time when not in immediate danger
	var has_threats = not crew_data.awareness.threats.is_empty()
	if has_threats:
		updated.stats.stress = min(1.0, updated.stats.stress + delta * 0.1)
	else:
		updated.stats.stress = max(0.0, updated.stats.stress - delta * 0.05)

	# Fatigue increases slowly over time
	updated.stats.fatigue = min(1.0, updated.stats.fatigue + delta * 0.001)

	return updated

## Check if crew member can make decisions
static func can_make_decisions(crew_data: Dictionary) -> bool:
	# High stress/fatigue slows decisions but doesn't stop them
	return crew_data.assigned_to != null

## Calculate effective skill with stress/fatigue penalties
static func calculate_effective_skill(crew_data: Dictionary) -> float:
	var base_skill = crew_data.stats.skill
	var stress_penalty = crew_data.stats.stress * 0.3  # Up to 30% penalty
	var fatigue_penalty = crew_data.stats.fatigue * 0.2  # Up to 20% penalty
	return max(0.1, base_skill - stress_penalty - fatigue_penalty)

## Calculate decision delay based on stats
static func calculate_decision_delay(crew_data: Dictionary) -> float:
	var base_time = crew_data.stats.decision_time
	var stress_multiplier = 1.0 + (crew_data.stats.stress * 0.5)  # Stress slows decisions
	return base_time * stress_multiplier

# ============================================================================
# PILOT DECISIONS
# ============================================================================

## Pilot makes tactical maneuvering decisions
static func make_pilot_decision(crew_data: Dictionary, game_time: float) -> Dictionary:
	# Check for orders from captain
	if crew_data.orders.received != null:
		return execute_pilot_order(crew_data, game_time)

	# Autonomous decision - evaluate threats and opportunities
	if not crew_data.awareness.threats.is_empty():
		return make_evasive_decision(crew_data, game_time)

	if not crew_data.awareness.opportunities.is_empty():
		return make_pursuit_decision(crew_data, game_time)

	# No immediate action needed
	return {"crew_data": crew_data}

## Execute order from captain
static func execute_pilot_order(crew_data: Dictionary, game_time: float) -> Dictionary:
	var order = crew_data.orders.received
	var updated = crew_data.duplicate(true)

	# Clear order once acknowledged
	updated.orders.current = order
	updated.orders.received = null

	return {
		"crew_data": updated,
		"decision": create_movement_decision(updated, order, game_time)
	}

## Make evasive maneuver decision
static func make_evasive_decision(crew_data: Dictionary, game_time: float) -> Dictionary:
	var top_threat = crew_data.awareness.threats[0]
	var updated = crew_data.duplicate(true)

	var decision = {
		"type": "maneuver",
		"subtype": "evade",
		"crew_id": crew_data.crew_id,
		"entity_id": crew_data.assigned_to,
		"target_id": top_threat.id,
		"urgency": calculate_threat_urgency(top_threat),
		"skill_factor": calculate_effective_skill(crew_data),
		"delay": crew_data.stats.reaction_time,
		"timestamp": game_time
	}

	updated.orders.current = decision
	return {"crew_data": updated, "decision": decision}

## Make pursuit decision
static func make_pursuit_decision(crew_data: Dictionary, game_time: float) -> Dictionary:
	var target = crew_data.awareness.opportunities[0]
	var updated = crew_data.duplicate(true)

	var decision = {
		"type": "maneuver",
		"subtype": "pursue",
		"crew_id": crew_data.crew_id,
		"entity_id": crew_data.assigned_to,
		"target_id": target.id,
		"skill_factor": calculate_effective_skill(crew_data),
		"delay": calculate_decision_delay(crew_data),
		"timestamp": game_time
	}

	updated.orders.current = decision
	return {"crew_data": updated, "decision": decision}

## Create movement decision from order
static func create_movement_decision(crew_data: Dictionary, order: Dictionary, game_time: float) -> Dictionary:
	return {
		"type": "maneuver",
		"subtype": order.get("subtype", "pursue"),
		"crew_id": crew_data.crew_id,
		"entity_id": crew_data.assigned_to,
		"target_id": order.get("target_id"),
		"skill_factor": calculate_effective_skill(crew_data),
		"delay": crew_data.stats.reaction_time,
		"timestamp": game_time
	}

## Calculate threat urgency
static func calculate_threat_urgency(threat: Dictionary) -> float:
	return threat.get("_threat_priority", 0.0) / 100.0

# ============================================================================
# GUNNER DECISIONS
# ============================================================================

## Gunner makes target selection decisions
static func make_gunner_decision(crew_data: Dictionary, game_time: float) -> Dictionary:
	# Check for specific target order from captain
	if crew_data.orders.received != null:
		return execute_gunner_order(crew_data, game_time)

	# Select target from opportunities
	if not crew_data.awareness.opportunities.is_empty():
		return make_target_selection_decision(crew_data, game_time)

	# No targets available
	return {"crew_data": crew_data}

## Execute target order from captain
static func execute_gunner_order(crew_data: Dictionary, game_time: float) -> Dictionary:
	var order = crew_data.orders.received
	var updated = crew_data.duplicate(true)

	updated.orders.current = order
	updated.orders.received = null

	return {
		"crew_data": updated,
		"decision": create_fire_decision(updated, order.get("target_id"), game_time)
	}

## Make target selection decision
static func make_target_selection_decision(crew_data: Dictionary, game_time: float) -> Dictionary:
	# Pick best target from opportunities
	var target = crew_data.awareness.opportunities[0]
	var updated = crew_data.duplicate(true)

	var decision = create_fire_decision(updated, target.id, game_time)
	updated.orders.current = decision

	return {"crew_data": updated, "decision": decision}

## Create fire decision
static func create_fire_decision(crew_data: Dictionary, target_id: String, game_time: float) -> Dictionary:
	return {
		"type": "fire",
		"crew_id": crew_data.crew_id,
		"entity_id": crew_data.assigned_to,
		"target_id": target_id,
		"skill_factor": calculate_effective_skill(crew_data),
		"delay": crew_data.stats.reaction_time,
		"timestamp": game_time
	}

# ============================================================================
# CAPTAIN DECISIONS
# ============================================================================

## Captain makes ship-level tactical decisions
static func make_captain_decision(crew_data: Dictionary, game_time: float) -> Dictionary:
	# Check for orders from squadron leader
	if crew_data.orders.received != null:
		return execute_captain_order(crew_data, game_time)

	# Make tactical decision and issue orders to crew
	return make_ship_tactical_decision(crew_data, game_time)

## Execute order from squadron leader
static func execute_captain_order(crew_data: Dictionary, game_time: float) -> Dictionary:
	var order = crew_data.orders.received
	var updated = crew_data.duplicate(true)

	# Process order and break it down for subordinates
	updated.orders.current = order
	updated.orders.received = null

	# Issue orders to subordinates (will be processed by CommandChainSystem)
	var subordinate_orders = break_down_captain_order(order, updated)
	updated.orders.issued = subordinate_orders

	return {
		"crew_data": updated,
		"decision": create_captain_decision(updated, order, game_time)
	}

## Make ship-level tactical decision
static func make_ship_tactical_decision(crew_data: Dictionary, game_time: float) -> Dictionary:
	var updated = crew_data.duplicate(true)

	# Analyze situation
	var has_threats = not crew_data.awareness.threats.is_empty()
	var has_opportunities = not crew_data.awareness.opportunities.is_empty()

	var decision = null
	var subordinate_orders = []

	if has_threats:
		# Prioritize best target
		var target = select_best_tactical_target(crew_data)
		subordinate_orders = create_engage_orders(crew_data, target)
		decision = create_captain_decision(updated, {"type": "engage", "target_id": target.id}, game_time)
	elif has_opportunities:
		var target = crew_data.awareness.opportunities[0]
		subordinate_orders = create_engage_orders(crew_data, target)
		decision = create_captain_decision(updated, {"type": "engage", "target_id": target.id}, game_time)

	updated.orders.current = decision
	updated.orders.issued = subordinate_orders

	if decision:
		return {"crew_data": updated, "decision": decision}
	return {"crew_data": updated}

## Select best tactical target
static func select_best_tactical_target(crew_data: Dictionary) -> Dictionary:
	# Combine threats and opportunities, prioritize threats
	if not crew_data.awareness.threats.is_empty():
		return crew_data.awareness.threats[0]
	if not crew_data.awareness.opportunities.is_empty():
		return crew_data.awareness.opportunities[0]
	return {}

## Break down captain order for subordinates
static func break_down_captain_order(order: Dictionary, crew_data: Dictionary) -> Array:
	# Convert captain's order into specific orders for pilot and gunners
	match order.get("type"):
		"engage":
			return create_engage_orders(crew_data, {"id": order.get("target_id")})
		"withdraw":
			return create_withdraw_orders(crew_data)
		_:
			return []

## Create engage orders for subordinates
static func create_engage_orders(crew_data: Dictionary, target: Dictionary) -> Array:
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
static func create_withdraw_orders(crew_data: Dictionary) -> Array:
	var orders = []

	for sub_id in crew_data.command_chain.subordinates:
		orders.append({
			"to": sub_id,
			"type": "withdraw"
		})

	return orders

## Create captain decision
static func create_captain_decision(crew_data: Dictionary, order: Dictionary, game_time: float) -> Dictionary:
	return {
		"type": "tactical",
		"subtype": order.get("type", "hold"),
		"crew_id": crew_data.crew_id,
		"entity_id": crew_data.assigned_to,
		"target_id": order.get("target_id"),
		"delay": calculate_decision_delay(crew_data),
		"timestamp": game_time
	}

# ============================================================================
# SQUADRON LEADER DECISIONS
# ============================================================================

## Squadron leader coordinates multiple ships
static func make_squadron_leader_decision(crew_data: Dictionary, game_time: float) -> Dictionary:
	# Squadron leader prioritizes targets for the squadron
	var updated = crew_data.duplicate(true)

	if crew_data.awareness.opportunities.is_empty():
		return {"crew_data": updated}

	# Assign targets to subordinate ships (captains)
	var target_assignments = assign_squadron_targets(crew_data)
	updated.orders.issued = target_assignments

	var decision = {
		"type": "squadron_command",
		"subtype": "assign_targets",
		"crew_id": crew_data.crew_id,
		"assignments": target_assignments,
		"delay": calculate_decision_delay(crew_data),
		"timestamp": game_time
	}

	updated.orders.current = decision
	return {"crew_data": updated, "decision": decision}

## Assign targets to squadron ships
static func assign_squadron_targets(crew_data: Dictionary) -> Array:
	var orders = []
	var targets = crew_data.awareness.opportunities.slice(0, crew_data.command_chain.subordinates.size())

	for i in crew_data.command_chain.subordinates.size():
		if i < targets.size():
			orders.append({
				"to": crew_data.command_chain.subordinates[i],
				"type": "engage",
				"target_id": targets[i].id
			})

	return orders

# ============================================================================
# FLEET COMMANDER DECISIONS
# ============================================================================

## Fleet commander makes strategic decisions
static func make_commander_decision(crew_data: Dictionary, game_time: float) -> Dictionary:
	# High-level strategic decisions
	var updated = crew_data.duplicate(true)

	# For now, simple: assess overall tactical situation
	var decision = {
		"type": "strategic",
		"subtype": "assess",
		"crew_id": crew_data.crew_id,
		"delay": calculate_decision_delay(crew_data),
		"timestamp": game_time
	}

	updated.orders.current = decision
	return {"crew_data": updated, "decision": decision}
