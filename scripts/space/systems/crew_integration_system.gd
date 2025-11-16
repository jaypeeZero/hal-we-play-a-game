class_name CrewIntegrationSystem
extends RefCounted

## Integrates crew AI decisions with ship systems (movement, weapons)
## Translates crew decisions into ship_data modifications
## Following functional programming principles - all data is immutable

# ============================================================================
# MAIN API - Apply crew decisions to ships
# ============================================================================

## Apply all crew decisions to ships
static func apply_crew_decisions_to_ships(ships: Array, crew_list: Array, decisions: Array) -> Dictionary:
	var updated_ships = ships.duplicate(true)

	for decision in decisions:
		var ship_id = decision.get("entity_id")
		if ship_id:
			var ship_index = find_ship_index(updated_ships, ship_id)
			if ship_index >= 0:
				var crew = find_crew_by_id(crew_list, decision.get("crew_id"))
				updated_ships[ship_index] = apply_decision_to_ship(updated_ships[ship_index], decision, crew)

	return {
		"ships": updated_ships,
		"actions": extract_immediate_actions(decisions)
	}

## Apply single decision to ship
static func apply_decision_to_ship(ship_data: Dictionary, decision: Dictionary, crew_data: Dictionary) -> Dictionary:
	match decision.get("type"):
		"maneuver":
			return apply_maneuver_decision(ship_data, decision, crew_data)
		"fire":
			return apply_fire_decision(ship_data, decision, crew_data)
		"tactical":
			return apply_tactical_decision(ship_data, decision, crew_data)
		_:
			return ship_data

# ============================================================================
# MANEUVER DECISIONS (Pilot)
# ============================================================================

## Apply pilot's maneuver decision
static func apply_maneuver_decision(ship_data: Dictionary, decision: Dictionary, crew_data: Dictionary) -> Dictionary:
	var updated = ship_data.duplicate(true)

	# Update ship's orders based on pilot decision
	match decision.get("subtype"):
		"evade":
			updated.orders.current_order = "evade"
			updated.orders.threat_id = decision.get("target_id")
		"pursue":
			updated.orders.current_order = "engage"
			updated.orders.target_id = decision.get("target_id")
		# FighterPilotAI maneuver types - all treated as specialized engage orders
		"pursue_full_speed", "pursue_tactical", "flank_behind", "tight_pursuit", "dogfight_maneuver":
			updated.orders.current_order = "fighter_engage"
			updated.orders.target_id = decision.get("target_id")
			updated.orders.maneuver_subtype = decision.get("subtype")
			updated.orders.formation_offset = decision.get("formation_offset", Vector2.ZERO)
			updated.orders.behind_position = decision.get("behind_position", Vector2.ZERO)
		"group_run_approach", "group_run_attack", "group_run_swing_around":
			updated.orders.current_order = "fighter_engage"
			updated.orders.target_id = decision.get("target_id")
			updated.orders.maneuver_subtype = decision.get("subtype")
			updated.orders.nearby_fighters = decision.get("nearby_fighters", 0)
		"evasive_retreat", "cautious_approach", "dodge_and_weave":
			updated.orders.current_order = "fighter_engage"
			updated.orders.target_id = decision.get("target_id")
			updated.orders.maneuver_subtype = decision.get("subtype")
			updated.orders.nearby_fighters = decision.get("nearby_fighters", 0)
		"rejoin_wingman":
			updated.orders.current_order = "fighter_engage"
			updated.orders.target_id = decision.get("target_id")  # Lead ship ID
			updated.orders.maneuver_subtype = decision.get("subtype")
			updated.orders.formation_position = decision.get("formation_position", Vector2.ZERO)
		"idle":
			updated.orders.current_order = ""
			updated.orders.target_id = ""
		_:
			pass

	# Apply crew skill modifiers to ship stats
	if crew_data and crew_data.has("stats"):
		updated = apply_pilot_skill_modifiers(updated, crew_data)

	return updated

## Apply pilot skill modifiers to ship performance
static func apply_pilot_skill_modifiers(ship_data: Dictionary, crew_data: Dictionary) -> Dictionary:
	var updated = ship_data.duplicate(true)
	var skill_factor = CrewAISystem.calculate_effective_skill(crew_data)

	# Skilled pilots get better ship performance
	# Store as temporary modifiers (would be applied by MovementSystem)
	if not updated.has("crew_modifiers"):
		updated.crew_modifiers = {}

	updated.crew_modifiers.pilot_skill = skill_factor
	updated.crew_modifiers.pilot_reaction = crew_data.stats.reaction_time

	return updated

# ============================================================================
# FIRE DECISIONS (Gunner)
# ============================================================================

## Apply gunner's fire decision
static func apply_fire_decision(ship_data: Dictionary, decision: Dictionary, crew_data: Dictionary) -> Dictionary:
	var updated = ship_data.duplicate(true)

	# Set target for weapon system
	updated.orders.target_id = decision.get("target_id")

	# Apply gunner skill to weapon accuracy
	if crew_data and crew_data.has("stats"):
		updated = apply_gunner_skill_modifiers(updated, crew_data)

	return updated

## Apply gunner skill modifiers to weapons
static func apply_gunner_skill_modifiers(ship_data: Dictionary, crew_data: Dictionary) -> Dictionary:
	var updated = ship_data.duplicate(true)
	var skill_factor = CrewAISystem.calculate_effective_skill(crew_data)

	if not updated.has("crew_modifiers"):
		updated.crew_modifiers = {}

	updated.crew_modifiers.gunner_skill = skill_factor
	updated.crew_modifiers.gunner_reaction = crew_data.stats.reaction_time

	return updated

# ============================================================================
# TACTICAL DECISIONS (Captain)
# ============================================================================

## Apply captain's tactical decision
static func apply_tactical_decision(ship_data: Dictionary, decision: Dictionary, crew_data: Dictionary) -> Dictionary:
	var updated = ship_data.duplicate(true)

	match decision.get("subtype"):
		"engage":
			updated.orders.current_order = "engage"
			updated.orders.target_id = decision.get("target_id")
		"hold":
			updated.orders.current_order = "hold"
		"withdraw":
			updated.orders.current_order = "withdraw"
		_:
			pass

	# Captain's skill affects overall ship coordination
	if crew_data and crew_data.has("stats"):
		updated = apply_captain_skill_modifiers(updated, crew_data)

	return updated

## Apply captain skill modifiers
static func apply_captain_skill_modifiers(ship_data: Dictionary, crew_data: Dictionary) -> Dictionary:
	var updated = ship_data.duplicate(true)
	var skill_factor = CrewAISystem.calculate_effective_skill(crew_data)

	if not updated.has("crew_modifiers"):
		updated.crew_modifiers = {}

	updated.crew_modifiers.captain_skill = skill_factor
	updated.crew_modifiers.captain_coordination = 1.0 + (skill_factor * 0.2)  # Up to 20% bonus

	return updated

# ============================================================================
# CREW-MODIFIED SHIP STATS
# ============================================================================

## Get movement stats modified by crew skill
static func get_crew_modified_movement_stats(ship_data: Dictionary) -> Dictionary:
	var stats = ship_data.stats.duplicate()

	if not ship_data.has("crew_modifiers"):
		return stats

	var modifiers = ship_data.crew_modifiers

	# Pilot skill affects turn rate and acceleration
	if modifiers.has("pilot_skill"):
		var skill = modifiers.pilot_skill
		stats.turn_rate *= (0.8 + skill * 0.4)  # 80% to 120% based on skill
		stats.acceleration *= (0.9 + skill * 0.2)  # 90% to 110%

	# Captain coordination affects overall performance
	if modifiers.has("captain_coordination"):
		stats.max_speed *= modifiers.captain_coordination
		stats.turn_rate *= modifiers.captain_coordination

	return stats

## Get weapon stats modified by crew skill
static func get_crew_modified_weapon_stats(weapon: Dictionary, ship_data: Dictionary) -> Dictionary:
	var stats = weapon.stats.duplicate()

	if not ship_data.has("crew_modifiers"):
		return stats

	var modifiers = ship_data.crew_modifiers

	# Gunner skill affects accuracy and rate of fire
	if modifiers.has("gunner_skill"):
		var skill = modifiers.gunner_skill
		stats.accuracy *= (0.7 + skill * 0.5)  # 70% to 120% based on skill
		stats.rate_of_fire *= (0.9 + skill * 0.2)  # Skilled gunners fire slightly faster

	return stats

# ============================================================================
# CREW AWARENESS TO TARGET SELECTION
# ============================================================================

## Get preferred targets from crew awareness
static func get_crew_preferred_targets(ship_id: String, crew_list: Array) -> Array:
	# Find captain or highest-ranking crew for this ship
	var ship_commander = find_ship_commander(ship_id, crew_list)
	if ship_commander.is_empty():
		return []

	# Return their prioritized opportunities
	return ship_commander.awareness.opportunities

## Find the commanding crew member for a ship
static func find_ship_commander(ship_id: String, crew_list: Array) -> Dictionary:
	# Look for captain first, then pilot
	var captain = find_crew_by_role_and_ship(CrewData.Role.CAPTAIN, ship_id, crew_list)
	if not captain.is_empty():
		return captain

	var pilot = find_crew_by_role_and_ship(CrewData.Role.PILOT, ship_id, crew_list)
	return pilot

## Find crew by role assigned to specific ship
static func find_crew_by_role_and_ship(role: int, ship_id: String, crew_list: Array) -> Dictionary:
	for crew in crew_list:
		if crew.role == role and crew.assigned_to == ship_id:
			return crew
	return {}

# ============================================================================
# IMMEDIATE ACTIONS EXTRACTION
# ============================================================================

## Extract actions that need immediate processing
static func extract_immediate_actions(decisions: Array) -> Array:
	var actions = []

	for decision in decisions:
		match decision.get("type"):
			"fire":
				# Convert to fire command for weapon system
				actions.append(create_fire_action(decision))
			_:
				pass  # Other decisions modify ship state

	return actions

## Create fire action from decision
static func create_fire_action(decision: Dictionary) -> Dictionary:
	return {
		"type": "crew_fire_command",
		"entity_id": decision.get("entity_id"),
		"target_id": decision.get("target_id"),
		"crew_id": decision.get("crew_id"),
		"skill_factor": decision.get("skill_factor", 0.5),
		"delay": decision.get("delay", 0.2)
	}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

## Find ship index by ID
static func find_ship_index(ships: Array, ship_id: String) -> int:
	for i in ships.size():
		if ships[i].ship_id == ship_id:
			return i
	return -1

## Find crew by ID
static func find_crew_by_id(crew_list: Array, crew_id: String) -> Dictionary:
	for crew in crew_list:
		if crew.crew_id == crew_id:
			return crew
	return {}

## Check if ship has crew assigned
static func has_crew_assigned(ship_data: Dictionary, crew_list: Array) -> bool:
	return not get_ship_crew(ship_data.ship_id, crew_list).is_empty()

## Get all crew assigned to a ship
static func get_ship_crew(ship_id: String, crew_list: Array) -> Array:
	return crew_list.filter(func(crew): return crew.assigned_to == ship_id)

## Create crew assignments for ship
static func assign_crew_to_ship(ship_data: Dictionary, crew: Array) -> Dictionary:
	var updated = ship_data.duplicate(true)

	if not updated.has("crew_assignments"):
		updated.crew_assignments = {}

	for crew_member in crew:
		var role_name = CrewData.get_role_name(crew_member.role)
		updated.crew_assignments[role_name] = crew_member.crew_id

	return updated
