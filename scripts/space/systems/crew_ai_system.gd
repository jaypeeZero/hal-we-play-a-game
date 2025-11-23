class_name CrewAISystem
extends RefCounted

## Pure functional crew AI system
## Handles role-based decision making for hierarchical command structure
## Following functional programming principles - all data is immutable

# ============================================================================
# MAIN API - Process crew decisions
# ============================================================================

## Update all crew members and generate their decisions
## EVENT-DRIVEN: Only processes crew when next_decision_time is reached
## Now includes dynamic wing formation for fighters
static func update_all_crew(crew_list: Array, delta: float, game_time: float, ships: Array = []) -> Dictionary:
	var updated_crew = []
	var decisions = []

	# DYNAMIC WING SYSTEM: Form wings once per update cycle
	# Wings are based on proximity - nearby same-team fighters form pairs/threes
	var wings = WingFormationSystem.form_wings(ships, crew_list)

	for crew in crew_list:
		# EVENT-DRIVEN: Only process if it's time to think!
		if game_time < crew.get("next_decision_time", 0.0):
			# Still "sleeping" - just update state, no decisions
			var updated = update_crew_state(crew, delta)
			updated_crew.append(updated)
			continue

		# Time to make a decision - pass wings for fighter coordination
		var result = update_crew_member(crew, delta, game_time, ships, crew_list, wings)
		updated_crew.append(result.crew_data)
		if result.has("decision"):
			decisions.append(result.decision)

	return {
		"crew_list": updated_crew,
		"decisions": decisions,
		"wings": wings  # Return wings for debugging/visualization
	}

## Update single crew member and generate decision
static func update_crew_member(crew_data: Dictionary, delta: float, game_time: float, ships: Array = [], crew_list: Array = [], wings: Array = []) -> Dictionary:
	# Update stress/fatigue
	var updated = update_crew_state(crew_data, delta)

	# Check if crew can make decisions
	if not can_make_decisions(updated):
		# Can't decide, but schedule next check soon
		updated.next_decision_time = game_time + 1.0
		return {"crew_data": updated}

	# Make role-based decision
	match updated.role:
		CrewData.Role.PILOT:
			return make_pilot_decision(updated, game_time, ships, crew_list, wings)
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
static func make_pilot_decision(crew_data: Dictionary, game_time: float, ships: Array = [], crew_list: Array = [], wings: Array = []) -> Dictionary:
	# Check for orders from captain - ALWAYS respect superior orders
	if crew_data.orders.received != null:
		return execute_pilot_order(crew_data, game_time)

	# Analyze tactical context (include wings for fighter coordination)
	var context = analyze_tactical_context(crew_data, ships, crew_list)
	context["wings"] = wings  # Add wings to context for fighter decisions

	# Make ship-type-specific decision
	# Note: We need to determine ship type from awareness or crew data
	# For now, use a heuristic based on role and command chain
	var ship_type = infer_ship_type(crew_data)

	match ship_type:
		"fighter":
			return make_fighter_pilot_decision(crew_data, context, game_time)
		"corvette":
			return make_corvette_pilot_decision(crew_data, context, game_time)
		"capital":
			return make_capital_pilot_decision(crew_data, context, game_time)
		_:
			# Default behavior - balanced approach
			return make_balanced_pilot_decision(crew_data, context, game_time)

## Infer ship type from crew context
static func infer_ship_type(crew_data: Dictionary) -> String:
	# If crew has a superior, they're likely on a multi-crew ship
	if crew_data.command_chain.superior != null:
		# Pilot with captain = likely corvette or capital
		# TODO: Could check subordinate count on captain to determine size
		return "corvette"  # Default to corvette for multi-crew
	else:
		# Solo pilot = fighter
		return "fighter"

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

	# Query knowledge for best evasion tactic
	var situation = TacticalMemorySystem.generate_situation_summary(crew_data)
	var knowledge = TacticalKnowledgeSystem.query_pilot_knowledge(situation, 1)

	# Default evasion subtype
	var evasion_subtype = "evade"

	# Use knowledge to inform maneuver choice
	if knowledge.size() > 0:
		var action = knowledge[0].content.get("action", "")
		if action == "evasive_maneuver":
			# Check if this crew has experience with different maneuvers
			var maneuver_types = knowledge[0].content.get("maneuver_types", [])
			for maneuver in maneuver_types:
				var tactic_id = "maneuver_" + maneuver
				var success_rate = TacticalMemorySystem.get_tactic_success_rate(crew_data, tactic_id)
				# If crew has tried this and it works well, use it
				if TacticalMemorySystem.has_tried_tactic(crew_data, tactic_id) and success_rate > 0.6:
					evasion_subtype = maneuver
					break

	var decision = {
		"type": "maneuver",
		"subtype": evasion_subtype,
		"crew_id": crew_data.crew_id,
		"entity_id": crew_data.assigned_to,
		"target_id": top_threat.id,
		"urgency": calculate_threat_urgency(top_threat),
		"skill_factor": calculate_effective_skill(crew_data),
		"delay": crew_data.stats.reaction_time,
		"timestamp": game_time
	}

	updated.orders.current = decision
	updated.current_action = "evading"
	# EVENT-DRIVEN: Evasion requires frequent re-evaluation (0.3-0.5s)
	updated.next_decision_time = game_time + randf_range(0.3, 0.5)
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
	updated.current_action = "pursuing"
	# EVENT-DRIVEN: Pursuit needs updates, but less frequent than evasion (0.7-1.0s)
	updated.next_decision_time = game_time + randf_range(0.7, 1.0)
	return {"crew_data": updated, "decision": decision}

## Fighter pilot decision - uses FighterPilotAI for advanced tactics
## Now uses dynamic wing formation system for coordinated flight
static func make_fighter_pilot_decision(crew_data: Dictionary, context: Dictionary, game_time: float) -> Dictionary:
	# Get all ships, crew, and wings from context
	var all_ships = context.get("all_ships", [])
	var all_crew = context.get("all_crew", [])
	var wings = context.get("wings", [])  # Dynamic wing formations

	# Get the ship this crew is assigned to
	var ship_id = crew_data.get("assigned_to", "")
	var ship_data = _find_ship_by_id(ship_id, all_ships)

	if ship_data.is_empty():
		# Fallback to balanced decision if no ship data available
		return make_balanced_pilot_decision(crew_data, context, game_time)

	# Use FighterPilotAI to make decision - now with wing formations!
	# Wings enable Lead/Wingman coordination based on proximity
	var decision = FighterPilotAI.make_decision(crew_data, ship_data, all_ships, all_crew, game_time, wings)

	# Wrap decision in standard format
	var updated = crew_data.duplicate(true)
	updated.orders.current = decision
	updated.current_action = decision.get("subtype", "idle")

	# Set next decision time based on maneuver type
	var next_delay = _get_fighter_decision_delay(decision.get("subtype", "idle"))
	updated.next_decision_time = game_time + next_delay

	return {"crew_data": updated, "decision": decision}

## Get decision delay for fighter maneuvers
static func _get_fighter_decision_delay(maneuver_subtype: String) -> float:
	match maneuver_subtype:
		"dogfight_maneuver", "tight_pursuit":
			return randf_range(0.2, 0.4)  # Very frequent updates for close combat
		"flank_behind", "pursue_tactical":
			return randf_range(0.4, 0.7)  # Moderate updates for tactical maneuvers
		"group_run_attack", "dodge_and_weave":
			return randf_range(0.3, 0.6)  # Quick updates for dynamic maneuvers
		"pursue_full_speed", "group_run_approach":
			return randf_range(0.7, 1.0)  # Less frequent for straightforward approach
		"wing_rejoin":
			return randf_range(0.2, 0.4)  # Frequent updates when rejoining lead
		"wing_follow":
			return randf_range(0.4, 0.7)  # Moderate updates when following lead
		"wing_engage":
			return randf_range(0.2, 0.4)  # Frequent updates when engaging with wing
		"idle":
			return randf_range(2.0, 4.0)  # Slow when idle
		_:
			return randf_range(0.5, 0.8)  # Default

## Helper to find ship by ID
static func _find_ship_by_id(ship_id: String, all_ships: Array) -> Dictionary:
	for ship in all_ships:
		if ship != null and ship.get("ship_id", "") == ship_id:
			return ship
	return {}

## Corvette pilot decision - balanced, tactical positioning
static func make_corvette_pilot_decision(crew_data: Dictionary, context: Dictionary, game_time: float) -> Dictionary:
	var awareness = crew_data.awareness

	# Corvettes evade if:
	# 1. Damaged, OR
	# 2. Outnumbered without squadron support
	var should_evade = context.is_outnumbered and not context.has_squadron_support

	if should_evade and not awareness.threats.is_empty():
		return make_evasive_decision(crew_data, game_time)

	# Engage if have targets and not heavily outnumbered
	if not awareness.opportunities.is_empty():
		return make_pursuit_decision(crew_data, game_time)

	# Idle otherwise
	return make_idle_decision(crew_data, game_time)

## Capital ship pilot decision - cautious, maintains distance
static func make_capital_pilot_decision(crew_data: Dictionary, context: Dictionary, game_time: float) -> Dictionary:
	var awareness = crew_data.awareness

	# Capital ships are cautious - evade if threatened
	if not awareness.threats.is_empty():
		# Check if threats are close (would need distance data)
		# For now, evade if any significant threats
		if context.threat_count > 2:
			return make_evasive_decision(crew_data, game_time)

	# Engage only if have clear opportunities
	if not awareness.opportunities.is_empty() and not context.is_outnumbered:
		return make_pursuit_decision(crew_data, game_time)

	# Default: maintain position
	return make_idle_decision(crew_data, game_time)

## Balanced pilot decision - default behavior
static func make_balanced_pilot_decision(crew_data: Dictionary, context: Dictionary, game_time: float) -> Dictionary:
	var awareness = crew_data.awareness

	# Evade if threatened and outnumbered
	if not awareness.threats.is_empty() and context.is_outnumbered:
		return make_evasive_decision(crew_data, game_time)

	# Pursue opportunities
	if not awareness.opportunities.is_empty():
		return make_pursuit_decision(crew_data, game_time)

	# Idle
	return make_idle_decision(crew_data, game_time)

## Make idle/scanning decision
static func make_idle_decision(crew_data: Dictionary, game_time: float) -> Dictionary:
	var updated = crew_data.duplicate(true)
	updated.current_action = "idle_scan"
	# EVENT-DRIVEN: Idle = check back in a few seconds
	updated.next_decision_time = game_time + randf_range(2.0, 4.0)
	return {"crew_data": updated}

## Make pursuit decision from threat (treat threat as target)
static func make_pursuit_decision_from_threat(crew_data: Dictionary, game_time: float) -> Dictionary:
	var threat = crew_data.awareness.threats[0]
	var updated = crew_data.duplicate(true)

	var decision = {
		"type": "maneuver",
		"subtype": "pursue",
		"crew_id": crew_data.crew_id,
		"entity_id": crew_data.assigned_to,
		"target_id": threat.id,
		"skill_factor": calculate_effective_skill(crew_data),
		"delay": calculate_decision_delay(crew_data),
		"timestamp": game_time
	}

	updated.orders.current = decision
	updated.current_action = "pursuing"
	updated.next_decision_time = game_time + randf_range(0.7, 1.0)
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

	# No targets available - schedule next decision check
	var updated = crew_data.duplicate(true)
	updated.next_decision_time = game_time + randf_range(1.0, 2.0)
	return {"crew_data": updated}

## Execute target order from captain
static func execute_gunner_order(crew_data: Dictionary, game_time: float) -> Dictionary:
	var order = crew_data.orders.received
	var updated = crew_data.duplicate(true)

	updated.orders.current = order
	updated.orders.received = null
	# When executing captain's order, re-decide frequently (spray mode if captain ordered it)
	updated.next_decision_time = game_time + 0.1

	return {
		"crew_data": updated,
		"decision": create_fire_decision(updated, order.get("target_id"), game_time)
	}

## Make target selection decision
static func make_target_selection_decision(crew_data: Dictionary, game_time: float) -> Dictionary:
	var updated = crew_data.duplicate(true)

	# Query knowledge for target priority guidance
	var situation = TacticalMemorySystem.generate_situation_summary(crew_data)
	var knowledge = TacticalKnowledgeSystem.query_gunner_knowledge(situation, 1)

	# Default: pick first target
	var target = crew_data.awareness.opportunities[0]

	# Use knowledge to inform target selection
	if knowledge.size() > 0:
		var priority_order = knowledge[0].content.get("priority_order", [])
		if "damaged_enemies" in priority_order:
			# Prefer damaged targets if available
			for opp in crew_data.awareness.opportunities:
				if opp.get("status", "") in ["damaged", "disabled"]:
					target = opp
					break

	var decision = create_fire_decision(updated, target.id, game_time)
	updated.orders.current = decision

	# Gatling gun behavior: if multiple targets in range, fire frequently (spray-and-pray)
	# This creates continuous suppressive fire against multiple threats
	var target_count = crew_data.awareness.opportunities.size()
	if target_count >= 2:
		# Multiple targets = spray fire mode, re-decide very quickly
		updated.next_decision_time = game_time + 0.1  # Fire every 0.1s, cycling targets
	else:
		# Single target = deliberate targeting, normal decision cycle
		updated.next_decision_time = game_time + randf_range(0.5, 1.0)

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

	# Query knowledge for tactical guidance
	var situation = TacticalMemorySystem.generate_situation_summary(crew_data)
	var knowledge = TacticalKnowledgeSystem.query_captain_knowledge(situation, 1)

	# Analyze situation
	var has_threats = not crew_data.awareness.threats.is_empty()
	var has_opportunities = not crew_data.awareness.opportunities.is_empty()

	var decision = null
	var subordinate_orders = []

	# Use knowledge to inform tactical choice
	var tactical_action = "engage"  # default
	if knowledge.size() > 0:
		var action = knowledge[0].content.get("action", "")
		# Knowledge might suggest defensive stance, withdrawal, etc.
		if action == "tactical_withdrawal" and has_threats:
			# Check threat level
			var top_threat = crew_data.awareness.threats[0]
			if top_threat.get("_threat_priority", 0.0) > 200.0:
				tactical_action = "withdraw"
		elif action == "concentrate_fire" and has_opportunities:
			# Focus fire on damaged targets
			tactical_action = "concentrate_fire"

	if has_threats or has_opportunities:
		# Prioritize best target
		var target = select_best_tactical_target(crew_data)

		if tactical_action == "withdraw":
			subordinate_orders = create_withdraw_orders(crew_data)
			decision = create_captain_decision(updated, {"type": "withdraw"}, game_time)
		else:
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

# ============================================================================
# TACTICAL CONTEXT ANALYSIS
# ============================================================================

## Analyze tactical context for decision-making
static func analyze_tactical_context(crew_data: Dictionary, ships: Array = [], crew_list: Array = []) -> Dictionary:
	var awareness = crew_data.awareness
	var friendlies = count_friendlies(awareness.known_entities)
	var enemies = count_enemies(awareness.known_entities, awareness.threats)

	return {
		"friendly_count": friendlies,
		"enemy_count": enemies,
		"has_squadron_support": friendlies > 1,  # Other friendlies nearby
		"is_outnumbered": enemies > friendlies,
		"has_numerical_advantage": friendlies > enemies,
		"is_solo": friendlies == 0,
		"threat_count": awareness.threats.size(),
		"opportunity_count": awareness.opportunities.size(),
		"all_ships": ships,
		"all_crew": crew_list
	}

## Count friendly ships in awareness
static func count_friendlies(known_entities: Variant) -> int:
	var count = 0
	if typeof(known_entities) == TYPE_ARRAY:
		for entity in known_entities:
			if typeof(entity) == TYPE_DICTIONARY and entity.get("type") == "ship":
				# InformationSystem marks friendlies differently
				count += 1
	elif typeof(known_entities) == TYPE_DICTIONARY:
		count = known_entities.size()
	return count

## Count enemy ships
static func count_enemies(known_entities: Variant, threats: Array) -> int:
	# Threats array contains enemy ships
	return threats.filter(func(t): return t.get("type") == "ship").size()

## Check if ship is critically damaged
static func is_critically_damaged(crew_data: Dictionary, ship_data: Dictionary) -> bool:
	if ship_data.is_empty():
		return false

	# Check armor integrity
	var total_armor = 0
	var max_armor = 0
	for section in ship_data.get("armor_sections", []):
		total_armor += section.get("current_armor", 0)
		max_armor += section.get("max_armor", 0)

	if max_armor > 0:
		var armor_percent = float(total_armor) / float(max_armor)
		return armor_percent < 0.3  # Less than 30% armor

	return false

## Get ship the crew member is assigned to (requires ships array from awareness)
static func get_assigned_ship_from_awareness(crew_data: Dictionary) -> Dictionary:
	var ship_id = crew_data.assigned_to
	if ship_id == null:
		return {}

	# Try to find in known_entities
	var entities = crew_data.awareness.get("known_entities", [])
	if typeof(entities) == TYPE_ARRAY:
		for entity in entities:
			if typeof(entity) == TYPE_DICTIONARY and entity.get("id") == ship_id:
				return entity

	return {}
