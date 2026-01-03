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
		"fight_dogfight_maneuver", "fight_tight_pursuit":
			return randf_range(0.2, 0.4)  # Very frequent updates for close combat
		"fight_flank_behind", "fight_pursue_tactical":
			return randf_range(0.4, 0.7)  # Moderate updates for tactical maneuvers
		"fight_group_run_attack", "fight_dodge_and_weave":
			return randf_range(0.3, 0.6)  # Quick updates for dynamic maneuvers
		"fight_pursue_full_speed", "fight_group_run_approach":
			return randf_range(0.7, 1.0)  # Less frequent for straightforward approach
		"fight_wing_rejoin":
			return randf_range(0.2, 0.4)  # Frequent updates when rejoining lead
		"fight_wing_follow":
			return randf_range(0.4, 0.7)  # Moderate updates when following lead
		"fight_wing_engage":
			return randf_range(0.2, 0.4)  # Frequent updates when engaging with wing
		"idle":
			return randf_range(2.0, 4.0)  # Slow when idle
		_:
			return randf_range(0.5, 0.8)  # Default

## Get decision delay for large ship maneuvers
static func _get_large_ship_decision_delay(maneuver_subtype: String) -> float:
	match maneuver_subtype:
		"large_ship_kite":
			return randf_range(0.5, 0.8)  # Moderate updates for defensive kiting
		"large_ship_broadside":
			return randf_range(0.6, 0.9)  # Measured updates for tactical positioning
		"large_ship_approach":
			return randf_range(0.7, 1.0)  # Less frequent for straightforward approach
		"large_ship_orbit":
			return randf_range(0.5, 0.8)  # Moderate updates for orbital positioning
		"idle":
			return randf_range(2.0, 4.0)  # Slow when idle
		_:
			return randf_range(0.5, 1.0)  # Default

## Helper to find ship by ID
static func _find_ship_by_id(ship_id: String, all_ships: Array) -> Dictionary:
	for ship in all_ships:
		if ship != null and ship.get("ship_id", "") == ship_id:
			return ship
	return {}

## Corvette pilot decision - uses LargeShipPilotAI for knowledge-driven tactics
static func make_corvette_pilot_decision(crew_data: Dictionary, context: Dictionary, game_time: float) -> Dictionary:
	var ship_data = context.get("ship_data", {})
	var all_ships = context.get("all_ships", [])

	# Use LargeShipPilotAI to make knowledge-driven decision
	var decision = LargeShipPilotAI.make_decision(crew_data, ship_data, all_ships, game_time)

	# Wrap decision in standard format
	var updated = crew_data.duplicate(true)
	updated.orders.current = decision
	updated.current_action = decision.get("subtype", "idle")

	# Set next decision time based on maneuver type
	var next_delay = _get_large_ship_decision_delay(decision.get("subtype", "idle"))
	updated.next_decision_time = game_time + next_delay

	return {"crew_data": updated, "decision": decision}

## Capital ship pilot decision - uses LargeShipPilotAI for knowledge-driven tactics
static func make_capital_pilot_decision(crew_data: Dictionary, context: Dictionary, game_time: float) -> Dictionary:
	var ship_data = context.get("ship_data", {})
	var all_ships = context.get("all_ships", [])

	# Use LargeShipPilotAI to make knowledge-driven decision
	var decision = LargeShipPilotAI.make_decision(crew_data, ship_data, all_ships, game_time)

	# Wrap decision in standard format
	var updated = crew_data.duplicate(true)
	updated.orders.current = decision
	updated.current_action = decision.get("subtype", "idle")

	# Set next decision time based on maneuver type
	var next_delay = _get_large_ship_decision_delay(decision.get("subtype", "idle"))
	updated.next_decision_time = game_time + next_delay

	return {"crew_data": updated, "decision": decision}

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
# GUNNER DECISIONS - KNOWLEDGE-DRIVEN with expanded actions
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

	# Determine fire mode based on order
	var fire_subtype = order.get("subtype", "fire")
	var decision = create_fire_decision_with_mode(updated, order.get("target_id", ""), fire_subtype, game_time)

	# Re-decide frequency based on fire mode
	match fire_subtype:
		"suppressive_fire":
			updated.next_decision_time = game_time + 0.05  # Very rapid fire
		"precision_shot":
			updated.next_decision_time = game_time + randf_range(0.8, 1.2)  # Careful aim
		_:
			updated.next_decision_time = game_time + 0.1

	return {"crew_data": updated, "decision": decision}

## Make target selection decision - KNOWLEDGE-DRIVEN
static func make_target_selection_decision(crew_data: Dictionary, game_time: float) -> Dictionary:
	var updated = crew_data.duplicate(true)

	# Query knowledge for firing guidance
	var situation = TacticalMemorySystem.generate_situation_summary(crew_data)
	var knowledge = TacticalKnowledgeSystem.query_gunner_knowledge(situation, 3)

	# Select fire action from knowledge
	var fire_action = _select_gunner_action_from_knowledge(knowledge, crew_data)

	# Default: pick first target
	var target = crew_data.awareness.opportunities[0]
	var decision = null

	match fire_action:
		"hold_fire":
			# Don't fire - wait for better opportunity
			decision = create_hold_fire_decision(updated, game_time)
			updated.next_decision_time = game_time + randf_range(0.5, 1.0)

		"suppressive_fire":
			# Rapid fire, cycle between targets
			decision = create_fire_decision_with_mode(updated, target.id, "suppressive_fire", game_time)
			updated.next_decision_time = game_time + 0.05

		"precision_shot":
			# Select best target and aim carefully
			target = _select_best_gunner_target(crew_data)
			decision = create_fire_decision_with_mode(updated, target.id, "precision_shot", game_time)
			updated.next_decision_time = game_time + randf_range(0.8, 1.2)

		"fire", _:
			# Standard fire mode
			# Use knowledge to inform target selection
			if knowledge.size() > 0:
				var priority_order = knowledge[0].get("content", {}).get("priority_order", [])
				if "damaged_enemies" in priority_order:
					for opp in crew_data.awareness.opportunities:
						if opp.get("status", "") in ["damaged", "disabled"]:
							target = opp
							break

			decision = create_fire_decision_with_mode(updated, target.id, "fire", game_time)

			# Gatling gun behavior: if multiple targets in range, fire frequently
			var target_count = crew_data.awareness.opportunities.size()
			if target_count >= 2:
				updated.next_decision_time = game_time + 0.1
			else:
				updated.next_decision_time = game_time + randf_range(0.5, 1.0)

	updated.orders.current = decision
	return {"crew_data": updated, "decision": decision}

## Select gunner action from knowledge
static func _select_gunner_action_from_knowledge(knowledge: Array, crew_data: Dictionary) -> String:
	var action = "fire"  # Default

	if knowledge.is_empty():
		return action

	# Check ammo status (TODO: get from ship data)
	var is_low_ammo = false

	# Check target count
	var target_count = crew_data.awareness.opportunities.size()

	for k in knowledge:
		var suggested_action = k.get("content", {}).get("action", "")
		var subtype = k.get("content", {}).get("subtype", "")

		if suggested_action == "hold_fire":
			if is_low_ammo:
				return "hold_fire"

		elif suggested_action == "fire":
			if subtype == "suppressive_fire" and target_count >= 3:
				return "suppressive_fire"
			elif subtype == "precision_shot":
				return "precision_shot"

	return action

## Select best target for precision shooting
static func _select_best_gunner_target(crew_data: Dictionary) -> Dictionary:
	var best_target = {}
	var best_score = -1.0

	for opp in crew_data.awareness.opportunities:
		var score = 0.0

		# Prefer damaged targets
		if opp.get("status", "") in ["damaged", "disabled", "critical"]:
			score += 50.0

		# Prefer closer targets
		var distance = opp.get("distance", 1000.0)
		score += max(0, 100.0 - distance / 10.0)

		# Prefer high-value targets
		var target_type = opp.get("type", "")
		if target_type in ["capital", "corvette"]:
			score += 30.0

		if score > best_score:
			best_score = score
			best_target = opp

	return best_target if not best_target.is_empty() else crew_data.awareness.opportunities[0]

## Create fire decision with mode
static func create_fire_decision_with_mode(crew_data: Dictionary, target_id: String, mode: String, game_time: float) -> Dictionary:
	return {
		"type": "fire",
		"subtype": mode,
		"crew_id": crew_data.crew_id,
		"entity_id": crew_data.assigned_to,
		"target_id": target_id,
		"skill_factor": calculate_effective_skill(crew_data),
		"delay": crew_data.stats.reaction_time,
		"timestamp": game_time
	}

## Create hold fire decision
static func create_hold_fire_decision(crew_data: Dictionary, game_time: float) -> Dictionary:
	return {
		"type": "fire",
		"subtype": "hold_fire",
		"crew_id": crew_data.crew_id,
		"entity_id": crew_data.assigned_to,
		"target_id": "",
		"skill_factor": calculate_effective_skill(crew_data),
		"delay": 0.0,
		"timestamp": game_time
	}

## Create fire decision (legacy compatibility)
static func create_fire_decision(crew_data: Dictionary, target_id: String, game_time: float) -> Dictionary:
	return create_fire_decision_with_mode(crew_data, target_id, "fire", game_time)

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

## Make ship-level tactical decision - KNOWLEDGE-DRIVEN with expanded actions
static func make_ship_tactical_decision(crew_data: Dictionary, game_time: float) -> Dictionary:
	var updated = crew_data.duplicate(true)

	# Query knowledge for tactical guidance
	var situation = TacticalMemorySystem.generate_situation_summary(crew_data)
	var knowledge = TacticalKnowledgeSystem.query_captain_knowledge(situation, 3)

	# Analyze situation
	var has_threats = not crew_data.awareness.threats.is_empty()
	var has_opportunities = not crew_data.awareness.opportunities.is_empty()
	var threat_count = crew_data.awareness.threats.size()
	var opportunity_count = crew_data.awareness.opportunities.size()

	# Check for damaged friendlies that need support
	var damaged_friendly = _find_damaged_friendly(crew_data)

	var decision = null
	var subordinate_orders = []

	# Use knowledge to select tactical action
	var tactical_action = _select_captain_action_from_knowledge(knowledge, crew_data, has_threats, has_opportunities, damaged_friendly != null)

	# Execute selected action
	match tactical_action:
		"withdraw":
			subordinate_orders = create_withdraw_orders(crew_data)
			decision = create_captain_decision(updated, {"type": "withdraw"}, game_time)

		"defensive_posture":
			subordinate_orders = create_defensive_posture_orders(crew_data)
			decision = create_captain_decision(updated, {"type": "defensive_posture"}, game_time)

		"concentrate_fire":
			var target = _select_damaged_target(crew_data)
			if target.is_empty():
				target = select_best_tactical_target(crew_data)
			subordinate_orders = create_concentrate_fire_orders(crew_data, target)
			decision = create_captain_decision(updated, {"type": "concentrate_fire", "target_id": target.get("id", "")}, game_time)

		"aggressive_pursuit":
			var target = select_best_tactical_target(crew_data)
			subordinate_orders = create_aggressive_pursuit_orders(crew_data, target)
			decision = create_captain_decision(updated, {"type": "aggressive_pursuit", "target_id": target.get("id", "")}, game_time)

		"support_ally":
			if damaged_friendly != null:
				subordinate_orders = create_support_ally_orders(crew_data, damaged_friendly)
				decision = create_captain_decision(updated, {"type": "support_ally", "target_id": damaged_friendly.get("id", "")}, game_time)
			else:
				# Fallback to engage
				var target = select_best_tactical_target(crew_data)
				subordinate_orders = create_engage_orders(crew_data, target)
				decision = create_captain_decision(updated, {"type": "engage", "target_id": target.get("id", "")}, game_time)

		"flank":
			var target = select_best_tactical_target(crew_data)
			subordinate_orders = create_flank_orders(crew_data, target)
			decision = create_captain_decision(updated, {"type": "flank", "target_id": target.get("id", "")}, game_time)

		"hold":
			subordinate_orders = create_hold_orders(crew_data)
			decision = create_captain_decision(updated, {"type": "hold"}, game_time)

		"engage", _:
			if has_threats or has_opportunities:
				var target = select_best_tactical_target(crew_data)
				subordinate_orders = create_engage_orders(crew_data, target)
				decision = create_captain_decision(updated, {"type": "engage", "target_id": target.get("id", "")}, game_time)

	updated.orders.current = decision
	updated.orders.issued = subordinate_orders

	# Set next decision time
	updated.next_decision_time = game_time + randf_range(1.0, 2.0)

	if decision:
		return {"crew_data": updated, "decision": decision}
	return {"crew_data": updated}

## Select captain action based on knowledge and situation
static func _select_captain_action_from_knowledge(knowledge: Array, crew_data: Dictionary, has_threats: bool, has_opportunities: bool, has_damaged_friendly: bool) -> String:
	# Default action
	var action = "engage" if (has_threats or has_opportunities) else "hold"

	if knowledge.is_empty():
		return action

	# Check each knowledge result
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
					if threat_priority > 200.0 or _is_ship_critically_damaged(crew_data):
						return "withdraw"

			"defensive_posture":
				if has_threats and crew_data.awareness.threats.size() > 2:
					return "defensive_posture"

			"concentrate_fire":
				if has_opportunities:
					return "concentrate_fire"

			"aggressive_pursuit":
				if has_opportunities and not has_threats:
					return "aggressive_pursuit"

			"support_ally":
				if has_damaged_friendly:
					return "support_ally"

			"flank":
				if has_opportunities and crew_data.awareness.threats.size() <= 1:
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
	if stress > 0.7 and threat_count >= 3:
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
			"type": "withdraw",
			"subtype": "evade"
		})

	return orders

## Create defensive posture orders - angle armor, limit exposure
static func create_defensive_posture_orders(crew_data: Dictionary) -> Array:
	var orders = []

	for sub_id in crew_data.command_chain.subordinates:
		orders.append({
			"to": sub_id,
			"type": "defensive_posture",
			"subtype": "angle_armor"
		})

	return orders

## Create concentrate fire orders - all weapons on one target
static func create_concentrate_fire_orders(crew_data: Dictionary, target: Dictionary) -> Array:
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
static func create_aggressive_pursuit_orders(crew_data: Dictionary, target: Dictionary) -> Array:
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
static func create_support_ally_orders(crew_data: Dictionary, ally: Variant) -> Array:
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
static func create_flank_orders(crew_data: Dictionary, target: Dictionary) -> Array:
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
static func create_hold_orders(crew_data: Dictionary) -> Array:
	var orders = []

	for sub_id in crew_data.command_chain.subordinates:
		orders.append({
			"to": sub_id,
			"type": "hold",
			"subtype": "maintain_position"
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
# SQUADRON LEADER DECISIONS - KNOWLEDGE-DRIVEN with expanded actions
# ============================================================================

## Squadron leader coordinates multiple ships
static func make_squadron_leader_decision(crew_data: Dictionary, game_time: float) -> Dictionary:
	var updated = crew_data.duplicate(true)

	# Query knowledge for squadron guidance
	var situation = TacticalMemorySystem.generate_situation_summary(crew_data)
	var knowledge = TacticalKnowledgeSystem.query_squadron_knowledge(situation, 3)

	# Analyze squadron situation
	var has_threats = not crew_data.awareness.threats.is_empty()
	var has_opportunities = not crew_data.awareness.opportunities.is_empty()
	var damaged_subordinate = _find_damaged_subordinate(crew_data)
	var is_scattered = _is_squadron_scattered(crew_data)

	# Select action based on knowledge
	var squadron_action = _select_squadron_action_from_knowledge(knowledge, crew_data, has_threats, has_opportunities, damaged_subordinate != null, is_scattered)

	var decision = null
	var orders = []

	match squadron_action:
		"assign_targets":
			orders = assign_squadron_targets(crew_data)
			decision = {
				"type": "squadron_command",
				"subtype": "assign_targets",
				"crew_id": crew_data.crew_id,
				"assignments": orders,
				"delay": calculate_decision_delay(crew_data),
				"timestamp": game_time
			}

		"call_mutual_support":
			orders = create_mutual_support_orders(crew_data, damaged_subordinate)
			decision = {
				"type": "squadron_command",
				"subtype": "call_mutual_support",
				"crew_id": crew_data.crew_id,
				"protected_ship": damaged_subordinate.get("id", "") if damaged_subordinate else "",
				"delay": calculate_decision_delay(crew_data),
				"timestamp": game_time
			}

		"reform_formation":
			orders = create_reform_formation_orders(crew_data)
			decision = {
				"type": "squadron_command",
				"subtype": "reform_formation",
				"crew_id": crew_data.crew_id,
				"formation": "wedge",
				"delay": calculate_decision_delay(crew_data),
				"timestamp": game_time
			}

		"coordinate_attack_run":
			var target = select_best_tactical_target(crew_data)
			orders = create_coordinated_attack_orders(crew_data, target)
			decision = {
				"type": "squadron_command",
				"subtype": "coordinate_attack_run",
				"crew_id": crew_data.crew_id,
				"target_id": target.get("id", ""),
				"delay": calculate_decision_delay(crew_data),
				"timestamp": game_time
			}

		"screen_withdrawal":
			orders = create_screen_withdrawal_orders(crew_data)
			decision = {
				"type": "squadron_command",
				"subtype": "screen_withdrawal",
				"crew_id": crew_data.crew_id,
				"delay": calculate_decision_delay(crew_data),
				"timestamp": game_time
			}

	if decision:
		updated.orders.issued = orders
		updated.orders.current = decision
		updated.next_decision_time = game_time + randf_range(1.5, 3.0)
		return {"crew_data": updated, "decision": decision}

	return {"crew_data": updated}

## Select squadron action from knowledge
static func _select_squadron_action_from_knowledge(knowledge: Array, crew_data: Dictionary, has_threats: bool, has_opportunities: bool, has_damaged_subordinate: bool, is_scattered: bool) -> String:
	# Default action
	var action = "assign_targets" if has_opportunities else ""

	if knowledge.is_empty():
		return action

	for k in knowledge:
		var suggested_action = k.get("content", {}).get("action", "")
		if suggested_action == "":
			continue

		match suggested_action:
			"call_mutual_support":
				if has_damaged_subordinate:
					return "call_mutual_support"

			"reform_formation":
				if is_scattered and not has_threats:
					return "reform_formation"

			"coordinate_attack_run":
				if has_opportunities and crew_data.command_chain.subordinates.size() >= 3:
					return "coordinate_attack_run"

			"screen_withdrawal":
				if has_threats and crew_data.awareness.threats.size() > crew_data.command_chain.subordinates.size():
					return "screen_withdrawal"

			"assign_targets":
				if has_opportunities:
					return "assign_targets"

	return action

## Find damaged subordinate ship
static func _find_damaged_subordinate(crew_data: Dictionary) -> Variant:
	var subordinates = crew_data.get("command_chain", {}).get("subordinates", [])
	var known_entities = crew_data.get("awareness", {}).get("known_entities", [])

	for sub_id in subordinates:
		for entity in known_entities:
			if entity.get("id", "") == sub_id:
				var status = entity.get("status", "")
				if status in ["damaged", "critical", "disabled"]:
					return entity

	return null

## Check if squadron is scattered
const SCATTERED_THRESHOLD = 2000.0  # Units

static func _is_squadron_scattered(crew_data: Dictionary) -> bool:
	var subordinates = crew_data.get("command_chain", {}).get("subordinates", [])
	if subordinates.size() < 2:
		return false

	var known_entities = crew_data.get("awareness", {}).get("known_entities", [])
	var positions = []

	for sub_id in subordinates:
		for entity in known_entities:
			if entity.get("id", "") == sub_id:
				positions.append(entity.get("position", Vector2.ZERO))
				break

	if positions.size() < 2:
		return false

	# Check if any pair is too far apart
	for i in range(positions.size()):
		for j in range(i + 1, positions.size()):
			if positions[i].distance_to(positions[j]) > SCATTERED_THRESHOLD:
				return true

	return false

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

## Create mutual support orders - protect damaged ship
static func create_mutual_support_orders(crew_data: Dictionary, damaged_ship: Variant) -> Array:
	var orders = []
	var ship_id = damaged_ship.get("id", "") if damaged_ship is Dictionary else ""

	for sub_id in crew_data.command_chain.subordinates:
		orders.append({
			"to": sub_id,
			"type": "support_ally",
			"ally_id": ship_id,
			"priority": "protect"
		})

	return orders

## Create reform formation orders
static func create_reform_formation_orders(crew_data: Dictionary) -> Array:
	var orders = []

	for sub_id in crew_data.command_chain.subordinates:
		orders.append({
			"to": sub_id,
			"type": "formation",
			"subtype": "reform",
			"formation": "wedge"
		})

	return orders

## Create coordinated attack orders
static func create_coordinated_attack_orders(crew_data: Dictionary, target: Dictionary) -> Array:
	var orders = []
	var target_id = target.get("id", "")

	for sub_id in crew_data.command_chain.subordinates:
		orders.append({
			"to": sub_id,
			"type": "engage",
			"subtype": "coordinated_attack",
			"target_id": target_id,
			"timing": "synchronized"
		})

	return orders

## Create screen withdrawal orders - rearguard action
static func create_screen_withdrawal_orders(crew_data: Dictionary) -> Array:
	var orders = []
	var subordinates = crew_data.command_chain.subordinates

	for i in subordinates.size():
		var role = "rearguard" if i < subordinates.size() / 2 else "withdraw"
		orders.append({
			"to": subordinates[i],
			"type": "withdraw" if role == "withdraw" else "engage",
			"subtype": role,
			"priority": "cover_retreat"
		})

	return orders

# ============================================================================
# FLEET COMMANDER DECISIONS - KNOWLEDGE-DRIVEN with expanded actions
# ============================================================================

## Fleet commander makes strategic decisions
static func make_commander_decision(crew_data: Dictionary, game_time: float) -> Dictionary:
	var updated = crew_data.duplicate(true)

	# Query knowledge for strategic guidance
	var situation = TacticalMemorySystem.generate_situation_summary(crew_data)
	var knowledge = TacticalKnowledgeSystem.query_commander_knowledge(situation, 3)

	# Analyze strategic situation
	var has_threats = not crew_data.awareness.threats.is_empty()
	var has_opportunities = not crew_data.awareness.opportunities.is_empty()
	var total_threats = crew_data.awareness.threats.size()
	var total_opportunities = crew_data.awareness.opportunities.size()

	# Select action based on knowledge
	var strategic_action = _select_commander_action_from_knowledge(knowledge, crew_data, has_threats, has_opportunities, total_threats)

	var decision = null
	var orders = []

	match strategic_action:
		"concentrate_force":
			orders = create_concentrate_force_orders(crew_data)
			decision = {
				"type": "strategic",
				"subtype": "concentrate_force",
				"crew_id": crew_data.crew_id,
				"delay": calculate_decision_delay(crew_data),
				"timestamp": game_time
			}

		"strategic_withdrawal":
			orders = create_strategic_withdrawal_orders(crew_data)
			decision = {
				"type": "strategic",
				"subtype": "strategic_withdrawal",
				"crew_id": crew_data.crew_id,
				"delay": calculate_decision_delay(crew_data),
				"timestamp": game_time
			}

		"commit_reserves":
			orders = create_commit_reserves_orders(crew_data)
			decision = {
				"type": "strategic",
				"subtype": "commit_reserves",
				"crew_id": crew_data.crew_id,
				"delay": calculate_decision_delay(crew_data),
				"timestamp": game_time
			}

		"shift_focus":
			var new_target = select_best_tactical_target(crew_data)
			orders = create_shift_focus_orders(crew_data, new_target)
			decision = {
				"type": "strategic",
				"subtype": "shift_focus",
				"crew_id": crew_data.crew_id,
				"new_focus": new_target.get("id", ""),
				"delay": calculate_decision_delay(crew_data),
				"timestamp": game_time
			}

		"hold_line":
			orders = create_hold_line_orders(crew_data)
			decision = {
				"type": "strategic",
				"subtype": "hold_line",
				"crew_id": crew_data.crew_id,
				"delay": calculate_decision_delay(crew_data),
				"timestamp": game_time
			}

		"assess", _:
			decision = {
				"type": "strategic",
				"subtype": "assess",
				"crew_id": crew_data.crew_id,
				"delay": calculate_decision_delay(crew_data),
				"timestamp": game_time
			}

	if decision:
		updated.orders.issued = orders
		updated.orders.current = decision
		updated.next_decision_time = game_time + randf_range(2.0, 4.0)
		return {"crew_data": updated, "decision": decision}

	return {"crew_data": updated}

## Select commander action from knowledge
static func _select_commander_action_from_knowledge(knowledge: Array, crew_data: Dictionary, has_threats: bool, has_opportunities: bool, total_threats: int) -> String:
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
				if has_threats and total_threats > crew_data.command_chain.subordinates.size() * 2:
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
static func create_concentrate_force_orders(crew_data: Dictionary) -> Array:
	var orders = []
	var target = select_best_tactical_target(crew_data)

	for sub_id in crew_data.command_chain.subordinates:
		orders.append({
			"to": sub_id,
			"type": "engage",
			"target_id": target.get("id", ""),
			"priority": "concentrate"
		})

	return orders

## Create strategic withdrawal orders
static func create_strategic_withdrawal_orders(crew_data: Dictionary) -> Array:
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
static func create_commit_reserves_orders(crew_data: Dictionary) -> Array:
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
static func create_shift_focus_orders(crew_data: Dictionary, new_target: Dictionary) -> Array:
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
static func create_hold_line_orders(crew_data: Dictionary) -> Array:
	var orders = []

	for sub_id in crew_data.command_chain.subordinates:
		orders.append({
			"to": sub_id,
			"type": "hold",
			"subtype": "defensive_line",
			"stance": "no_retreat"
		})

	return orders

# ============================================================================
# TACTICAL CONTEXT ANALYSIS
# ============================================================================

## Analyze tactical context for decision-making
static func analyze_tactical_context(crew_data: Dictionary, ships: Array = [], crew_list: Array = []) -> Dictionary:
	var awareness = crew_data.awareness
	var friendlies = count_friendlies(awareness.known_entities)
	var enemies = count_enemies(awareness.known_entities, awareness.threats)

	# Get the ship this crew is assigned to
	var ship_id = crew_data.get("assigned_to", "")
	var ship_data = _find_ship_by_id(ship_id, ships)

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
		"all_crew": crew_list,
		"ship_data": ship_data
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
