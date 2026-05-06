class_name CrewAISystem
extends RefCounted

## Pure functional crew AI system.
## Dispatcher + crew-state + pilot-role decisions.
## Role-specific decision logic lives in scripts/space/ai/{gunner,captain,squadron_leader,commander}_ai.gd
## (pilot decisions remain here pending Phase 1/2 absorption into FighterPilotAI / LargeShipPilotAI).
## Following functional programming principles - all data is immutable.

# ============================================================================
# MAIN API - Process crew decisions
# ============================================================================

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
			return GunnerAI.make_decision(updated, game_time)
		CrewData.Role.CAPTAIN:
			return CaptainAI.make_decision(updated, game_time)
		CrewData.Role.SQUADRON_LEADER:
			return SquadronLeaderAI.make_decision(updated, game_time)
		CrewData.Role.FLEET_COMMANDER:
			return CommanderAI.make_decision(updated, game_time)
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

## Calculate effective skill with stress/fatigue penalties.
## Reads the role-appropriate primary stat (Phase 03 default).  Phase 07
## replaces this with per-stat decay rates.
static func calculate_effective_skill(crew_data: Dictionary) -> float:
	var skills: Dictionary = crew_data.get("stats", {}).get("skills", {})
	var role = crew_data.get("role", -1)
	var base_skill: float = 0.5
	match role:
		CrewData.Role.PILOT:
			base_skill = float(skills.get("piloting", 0.5))
		CrewData.Role.GUNNER:
			base_skill = float(skills.get("aim", 0.5))
		CrewData.Role.CAPTAIN, CrewData.Role.SQUADRON_LEADER, CrewData.Role.FLEET_COMMANDER:
			base_skill = float(skills.get("tactics", 0.5))
		_:
			base_skill = 0.5
	var stress_penalty = crew_data.stats.stress * 0.3  # Up to 30% penalty
	var fatigue_penalty = crew_data.stats.fatigue * 0.2  # Up to 20% penalty
	return max(0.1, base_skill - stress_penalty - fatigue_penalty)

## Calculate decision delay based on stats
## Now uses constants for captain-specific dramatic skill differences
static func calculate_decision_delay(crew_data: Dictionary) -> float:
	var base_time = crew_data.stats.decision_time
	var stress_multiplier = 1.0 + (crew_data.stats.stress * 0.5)  # Stress slows decisions
	var role = crew_data.get("role", -1)

	# Captains have dramatic skill-based decision delay
	if role == CrewData.Role.CAPTAIN:
		var skill = calculate_effective_skill(crew_data)
		# 1.5s (low skill) to 0.3s (high skill)
		base_time = lerp(WingConstants.CAPTAIN_DECISION_DELAY_MAX,
						 WingConstants.CAPTAIN_DECISION_DELAY_MIN, skill)

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
	# Evasion needs frequent re-evaluation as the threat geometry changes.
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
	# Pursuit re-evaluates less frequently than evasion (0.7-1.0s).
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
		"large_ship_hold_broadside":
			return randf_range(0.6, 0.9)  # Measured updates for tactical positioning
		"large_ship_close_to_broadside":
			return randf_range(0.7, 1.0)  # Less frequent for straightforward closing
		"large_ship_reposition_arc":
			return randf_range(0.4, 0.7)  # Tighter loop while turning for arc
		"large_ship_fighting_withdrawal":
			return randf_range(0.3, 0.5)  # Re-assess often when running
		"large_ship_present_thickest_armor":
			return randf_range(0.3, 0.5)  # Tactical break — quick re-check
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
	var ai_result = LargeShipPilotAI.make_decision(crew_data, ship_data, all_ships, game_time)

	# Check if we got an actual decision (has "decision" key with proper structure)
	if ai_result.has("decision") and ai_result.decision.has("type"):
		var decision = ai_result.decision
		var updated = ai_result.crew_data
		updated.orders.current = decision
		updated.current_action = decision.get("subtype", "idle")

		# Set next decision time based on maneuver type
		var next_delay = _get_large_ship_decision_delay(decision.get("subtype", "idle"))
		updated.next_decision_time = game_time + next_delay

		return {"crew_data": updated, "decision": decision}

	# No ship targets available - fall back to awareness-based decisions
	return make_balanced_pilot_decision(crew_data, context, game_time)

## Capital ship pilot decision - uses LargeShipPilotAI for knowledge-driven tactics
static func make_capital_pilot_decision(crew_data: Dictionary, context: Dictionary, game_time: float) -> Dictionary:
	var ship_data = context.get("ship_data", {})
	var all_ships = context.get("all_ships", [])

	# Use LargeShipPilotAI to make knowledge-driven decision
	var ai_result = LargeShipPilotAI.make_decision(crew_data, ship_data, all_ships, game_time)

	# Check if we got an actual decision (has "decision" key with proper structure)
	if ai_result.has("decision") and ai_result.decision.has("type"):
		var decision = ai_result.decision
		var updated = ai_result.crew_data
		updated.orders.current = decision
		updated.current_action = decision.get("subtype", "idle")

		# Set next decision time based on maneuver type
		var next_delay = _get_large_ship_decision_delay(decision.get("subtype", "idle"))
		updated.next_decision_time = game_time + next_delay

		return {"crew_data": updated, "decision": decision}

	# No ship targets available - fall back to awareness-based decisions
	return make_balanced_pilot_decision(crew_data, context, game_time)

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
	# Idle pilots check back every few seconds.
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
