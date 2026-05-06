class_name CrewIntegrationSystem
extends RefCounted

## Integrates crew AI decisions with ship systems (movement, weapons)
## Translates crew decisions into ship_data modifications
## Following functional programming principles - all data is immutable

# =============================================================================
# TARGETING STYLE ENUM - Unlocked by gunner skill
# =============================================================================
enum TargetingStyle {
	SIMPLE,      # Aims at target center, no lead (low skill)
	LEADING,     # Basic velocity prediction (medium skill)
	PREDICTIVE,  # Full lead calculation, anticipates maneuvers (high skill)
	SUBSYSTEM    # Targets specific weak points (elite skill)
}

# =============================================================================
# COMMAND STYLE ENUM - Unlocked by captain skill
# =============================================================================
enum CommandStyle {
	REACTIVE,    # Only responds to immediate threats (low skill)
	STANDARD,    # Follows doctrine, reasonable priorities (medium skill)
	TACTICAL,    # Anticipates situations, coordinates crew (high skill)
	ADAPTIVE     # Reads battle, adjusts strategy dynamically (elite skill)
}

# =============================================================================
# COORDINATION STYLE ENUM - Unlocked by squadron leader skill
# =============================================================================
enum CoordinationStyle {
	INDIVIDUAL,   # Ships fight independently (low skill)
	PAIRED,       # Basic wingman pairing works (medium skill)
	COORDINATED,  # Focus fire, mutual support, timing (high skill)
	ORCHESTRATED  # Complex maneuvers, feints, traps (elite skill)
}

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
## All fighter maneuvers use "fight_" prefix and are handled generically
## This prevents bugs when adding new maneuvers
static func apply_maneuver_decision(ship_data: Dictionary, decision: Dictionary, crew_data: Dictionary) -> Dictionary:
	var updated = ship_data.duplicate(true)
	var subtype = decision.get("subtype", "")

	# Handle special non-fighter cases
	if subtype == "evade":
		updated.orders.current_order = "evade"
		updated.orders.threat_id = decision.get("target_id")
	elif subtype == "pursue":
		updated.orders.current_order = "engage"
		updated.orders.target_id = decision.get("target_id")
	elif subtype == "idle":
		updated.orders.current_order = ""
		updated.orders.target_id = ""
	elif subtype.begins_with("fight_"):
		# ALL fighter maneuvers (fight_*) - pass through everything automatically
		# This ensures new maneuvers don't get forgotten
		updated.orders.current_order = "fighter_engage"
		updated.orders.target_id = decision.get("target_id", "")
		updated.orders.maneuver_subtype = subtype
		# Copy ALL optional fields - new fields automatically pass through
		updated.orders.formation_offset = decision.get("formation_offset", Vector2.ZERO)
		updated.orders.behind_position = decision.get("behind_position", Vector2.ZERO)
		updated.orders.nearby_fighters = decision.get("nearby_fighters", 0)
		updated.orders.evasion_direction = decision.get("evasion_direction", 0)
		updated.orders.formation_position = decision.get("formation_position", Vector2.ZERO)
		updated.orders.lateral_thrust = decision.get("lateral_thrust", 0)
		updated.orders.position_side = decision.get("position_side", 0)
		updated.orders.skill_factor = decision.get("skill_factor", 0.5)
		# NEW: Skill-based approach data
		updated.orders.approach_style = decision.get("approach_style", 0)  # 0 = DIRECT
		updated.orders.position_advantage = decision.get("position_advantage", "neutral")
		updated.orders.jink_amplitude = decision.get("jink_amplitude", 0.0)
		updated.orders.jink_period = decision.get("jink_period", 1000.0)
		updated.orders.approach_angle = decision.get("approach_angle", 0.0)
	elif subtype.begins_with("large_ship_"):
		# ALL large ship maneuvers (large_ship_*) - corvettes and capitals
		updated.orders.current_order = "large_ship_engage"
		updated.orders.target_id = decision.get("target_id", "")
		updated.orders.maneuver_subtype = subtype
		updated.orders.skill_factor = decision.get("skill_factor", 0.5)

	# Apply crew skill modifiers to ship stats
	if crew_data and crew_data.has("stats"):
		updated = apply_pilot_skill_modifiers(updated, crew_data)

	return updated

## Apply pilot skill modifiers to ship performance.
## Writes factor fields directly onto ship_data.crew_modifiers; MovementSystem
## reads these in its hot path. No intermediate aggregate (e.g. raw skill)
## is kept around — that just begs to be ignored downstream.
static func apply_pilot_skill_modifiers(ship_data: Dictionary, crew_data: Dictionary) -> Dictionary:
	var updated = ship_data.duplicate(true)
	var skill_factor = CrewAISystem.calculate_effective_skill(crew_data)

	if not updated.has("crew_modifiers"):
		updated.crew_modifiers = {}

	updated.crew_modifiers.pilot_turn_factor = lerp(WingConstants.PILOT_TURN_RATE_MIN,
													WingConstants.PILOT_TURN_RATE_MAX, skill_factor)
	updated.crew_modifiers.pilot_accel_factor = lerp(WingConstants.PILOT_ACCEL_MIN,
													 WingConstants.PILOT_ACCEL_MAX, skill_factor)
	updated.crew_modifiers.pilot_lateral_factor = lerp(WingConstants.PILOT_LATERAL_MIN,
													   WingConstants.PILOT_LATERAL_MAX, skill_factor)
	updated.crew_modifiers.pilot_damp_factor = lerp(WingConstants.PILOT_DAMPENING_MIN,
													WingConstants.PILOT_DAMPENING_MAX, skill_factor)
	updated.crew_modifiers.pilot_reaction = crew_data.stats.reaction_time

	# Aggression is the leash dial: low aggression hugs the patrol area,
	# high aggression chases targets anywhere. MovementSystem.apply_area_leash
	# reads this. Falls back to the legacy aggregate skill so unconfigured
	# crew get baseline behavior.
	var skills: Dictionary = crew_data.get("stats", {}).get("skills", {})
	updated.crew_modifiers.pilot_aggression = float(skills.get("aggression", skill_factor))

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

## Apply gunner skill modifiers to weapons.
## Writes factor fields directly onto ship_data.crew_modifiers; WeaponSystem
## consumes aim_accuracy_factor in calculate_final_accuracy. The same field
## is also written by fighter pilots whose forward-fixed weapons aim with
## piloting+aim — caller picks crew based on weapon type.
## DRAMATIC skill differences: 0-skill sprays wildly, 1.0-skill lands precise shots.
static func apply_gunner_skill_modifiers(ship_data: Dictionary, crew_data: Dictionary) -> Dictionary:
	var updated = ship_data.duplicate(true)
	var skill_factor = CrewAISystem.calculate_effective_skill(crew_data)

	if not updated.has("crew_modifiers"):
		updated.crew_modifiers = {}

	# Check for panic state (low composure under stress) before computing
	# the accuracy factor — panic overrides the skill curve.
	var composure = crew_data.get("stats", {}).get("skills", {}).get("composure", skill_factor)
	var stress = crew_data.get("stats", {}).get("stress", 0.0)
	var effective_composure = composure * (1.0 - stress * 0.5)
	var is_panicking = effective_composure < WingConstants.GUNNER_PANIC_COMPOSURE

	if is_panicking:
		updated.crew_modifiers.aim_accuracy_factor = WingConstants.GUNNER_PANIC_ACCURACY_PENALTY
	else:
		updated.crew_modifiers.aim_accuracy_factor = lerp(WingConstants.GUNNER_ACCURACY_MIN,
														  WingConstants.GUNNER_ACCURACY_MAX, skill_factor)

	updated.crew_modifiers.gunner_panicking = is_panicking
	updated.crew_modifiers.gunner_reaction = crew_data.stats.reaction_time

	# Select targeting style based on skill
	updated.crew_modifiers.targeting_style = _select_targeting_style(skill_factor)

	# Calculate lead accuracy (how well gunner predicts target position)
	updated.crew_modifiers.lead_accuracy = lerp(WingConstants.GUNNER_LEAD_MIN,
												WingConstants.GUNNER_LEAD_MAX, skill_factor)

	return updated

## Select targeting style based on gunner skill
static func _select_targeting_style(skill: float) -> int:
	if skill >= WingConstants.GUNNER_SUBSYSTEM_SKILL:
		return TargetingStyle.SUBSYSTEM
	elif skill >= WingConstants.GUNNER_PREDICTIVE_SKILL:
		return TargetingStyle.PREDICTIVE
	elif skill >= WingConstants.GUNNER_LEADING_SKILL:
		return TargetingStyle.LEADING
	else:
		return TargetingStyle.SIMPLE

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
## DRAMATIC skill differences: 0-skill issues confused orders, 1.0-skill orchestrates perfectly
static func apply_captain_skill_modifiers(ship_data: Dictionary, crew_data: Dictionary) -> Dictionary:
	var updated = ship_data.duplicate(true)
	var skill_factor = CrewAISystem.calculate_effective_skill(crew_data)

	if not updated.has("crew_modifiers"):
		updated.crew_modifiers = {}

	updated.crew_modifiers.captain_skill = skill_factor

	# Coordination bonus: -10% to +30% (was 0-20%)
	updated.crew_modifiers.captain_coordination = lerp(WingConstants.CAPTAIN_COORDINATION_MIN,
													   WingConstants.CAPTAIN_COORDINATION_MAX, skill_factor)

	# Select command style based on skill
	updated.crew_modifiers.command_style = _select_command_style(skill_factor)

	# Decision delay: 1.5s (low skill) to 0.3s (high skill)
	updated.crew_modifiers.captain_decision_delay = lerp(WingConstants.CAPTAIN_DECISION_DELAY_MAX,
														 WingConstants.CAPTAIN_DECISION_DELAY_MIN, skill_factor)

	# Order clarity: 60% to 100% effectiveness
	updated.crew_modifiers.order_clarity = lerp(WingConstants.CAPTAIN_ORDER_CLARITY_MIN,
												WingConstants.CAPTAIN_ORDER_CLARITY_MAX, skill_factor)

	# Threat assessment accuracy: 40% to 100%
	updated.crew_modifiers.threat_assessment = lerp(WingConstants.CAPTAIN_THREAT_ASSESSMENT_MIN,
													WingConstants.CAPTAIN_THREAT_ASSESSMENT_MAX, skill_factor)

	# Damage control effectiveness: 50% to 120%
	updated.crew_modifiers.damage_control = lerp(WingConstants.CAPTAIN_DAMAGE_CONTROL_MIN,
												 WingConstants.CAPTAIN_DAMAGE_CONTROL_MAX, skill_factor)

	return updated

## Select command style based on captain skill
static func _select_command_style(skill: float) -> int:
	if skill >= WingConstants.CAPTAIN_ADAPTIVE_SKILL:
		return CommandStyle.ADAPTIVE
	elif skill >= WingConstants.CAPTAIN_TACTICAL_SKILL:
		return CommandStyle.TACTICAL
	elif skill >= WingConstants.CAPTAIN_STANDARD_SKILL:
		return CommandStyle.STANDARD
	else:
		return CommandStyle.REACTIVE

## Select coordination style based on squadron leader skill
static func _select_coordination_style(skill: float) -> int:
	if skill >= WingConstants.SQUADRON_ORCHESTRATED_SKILL:
		return CoordinationStyle.ORCHESTRATED
	elif skill >= WingConstants.SQUADRON_COORDINATED_SKILL:
		return CoordinationStyle.COORDINATED
	elif skill >= WingConstants.SQUADRON_PAIRED_SKILL:
		return CoordinationStyle.PAIRED
	else:
		return CoordinationStyle.INDIVIDUAL

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
