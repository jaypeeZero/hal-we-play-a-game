class_name CrewData
extends RefCounted

## Pure data container and factory for crew members
## Creates crew with different roles and stats for hierarchical AI system

static var _next_crew_id: int = 0

## Crew roles in command hierarchy
enum Role {
	PILOT,        # Flies the ship, responds to immediate threats
	GUNNER,       # Operates weapons, picks targets within orders
	CAPTAIN,      # Commands ship-level decisions, coordinates crew
	SQUADRON_LEADER,  # Commands multiple ships, prioritizes squadron targets
	FLEET_COMMANDER   # Strategic decisions for entire fleet
}

## Create a crew member with given role and skill level
static func create_crew_member(role: Role, skill_level: float = 0.5) -> Dictionary:
	var crew_id = "crew_" + str(_next_crew_id)
	_next_crew_id += 1

	var base_crew = {
		"crew_id": crew_id,
		"role": role,
		"assigned_to": null,  # entity_id they're assigned to
		"stats": _generate_stats_for_role(role, skill_level),
		"awareness": {
			"known_entities": [],  # entities they're aware of
			"last_update": 0.0,
			"threats": [],  # prioritized threat list
			"opportunities": [],  # potential targets or actions
			"tactical_memory": {
				"recent_events": [],  # Last N events this crew witnessed
				"successful_tactics": {},  # tactic_id -> success_count
				"failed_tactics": {},  # tactic_id -> fail_count
				"current_situation": ""  # Text summary for knowledge queries
			}
		},
		"orders": {
			"received": null,  # order from superior
			"current": null,  # what they're doing now
			"issued": []  # orders to subordinates
		},
		"command_chain": {
			"superior": null,  # crew_id of superior
			"subordinates": []  # crew_ids of subordinates
		},
		# EVENT-DRIVEN: When to think next (not every frame!)
		"next_decision_time": 0.0,  # Wake up at this time
		"current_action": null  # What they're doing now
	}

	return base_crew

## Generate stats based on role and skill level
static func _generate_stats_for_role(role: Role, skill_level: float) -> Dictionary:
	# Base stats that vary by role
	var role_modifiers = _get_role_modifiers(role)

	return {
		"skill": clamp(skill_level, 0.0, 1.0),  # Base competency
		"reaction_time": _calculate_reaction_time(skill_level, role_modifiers.reaction_base),
		"awareness_range": role_modifiers.awareness_range,
		"decision_time": _calculate_decision_time(skill_level, role_modifiers.decision_base),
		"stress": 0.0,  # Increases in combat, reduces performance
		"fatigue": 0.0  # Increases over time
	}

## Get role-specific modifiers
static func _get_role_modifiers(role: Role) -> Dictionary:
	match role:
		Role.PILOT:
			return {
				"reaction_base": 0.15,  # Fast reactions needed
				"decision_base": 0.2,  # Quick tactical decisions
				"awareness_range": 800.0  # Medium range awareness
			}
		Role.GUNNER:
			return {
				"reaction_base": 0.2,  # Moderate reactions
				"decision_base": 0.3,  # Target selection time
				"awareness_range": 1000.0  # Focus on weapon range
			}
		Role.CAPTAIN:
			return {
				"reaction_base": 0.3,  # Don't need twitch reflexes
				"decision_base": 0.5,  # More complex decisions
				"awareness_range": 1200.0  # Broader tactical view
			}
		Role.SQUADRON_LEADER:
			return {
				"reaction_base": 0.4,  # Strategic not tactical
				"decision_base": 1.0,  # Complex squadron coordination
				"awareness_range": 2000.0  # Squadron-level awareness
			}
		Role.FLEET_COMMANDER:
			return {
				"reaction_base": 0.5,  # High-level decisions
				"decision_base": 2.0,  # Very complex decisions
				"awareness_range": 3000.0  # Strategic view
			}
		_:
			return {
				"reaction_base": 0.3,
				"decision_base": 0.5,
				"awareness_range": 1000.0
			}

## Calculate reaction time based on skill (higher skill = faster)
static func _calculate_reaction_time(skill: float, base: float) -> float:
	# Skill reduces reaction time: 0.5 skill = base, 1.0 skill = base*0.5
	return base * (1.5 - skill)

## Calculate decision time based on skill (higher skill = faster decisions)
static func _calculate_decision_time(skill: float, base: float) -> float:
	# Similar to reaction time but for complex decisions
	return base * (1.5 - skill)

## Create a solo fighter crew (pilot who does everything)
static func create_solo_fighter_crew(skill_level: float = 0.5) -> Array:
	var pilot = create_crew_member(Role.PILOT, skill_level)
	# Solo pilot makes their own decisions (no superior)
	return [pilot]

## Create a fighter squadron (6 fighters in 3 wingman pairs)
## Squadron Leader (Alpha) decides targets, others follow
## Leadership succession: Alpha -> Beta -> Gamma -> Delta -> Epsilon -> Zeta
static func create_fighter_squadron(skill_level: float = 0.5) -> Array:
	var all_crew = []
	var ranks = ["Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta"]

	# Create 6 fighters with rank structure
	for i in range(6):
		var pilot = create_crew_member(Role.PILOT, skill_level)
		pilot.squadron_rank = i  # 0 = Alpha (leader), 5 = Zeta (lowest)
		pilot.squadron_role = ranks[i]
		pilot.callsign = ranks[i]

		# Wingman pairs: (Alpha, Beta), (Gamma, Delta), (Epsilon, Zeta)
		pilot.wingman_pair = int(i / 2)  # 0, 0, 1, 1, 2, 2

		# Leader is the first pilot (Alpha)
		if i == 0:
			pilot.is_squadron_leader = true
		else:
			pilot.is_squadron_leader = false
			# All non-leaders report to the current leader (Alpha initially)
			pilot.command_chain.superior = all_crew[0].crew_id
			all_crew[0].command_chain.subordinates.append(pilot.crew_id)

		all_crew.append(pilot)

	return all_crew

## Promote next in line to squadron leader (on death/incapacitation)
static func promote_squadron_leader(squadron_crew: Array) -> Array:
	var updated_crew = squadron_crew.duplicate(true)

	# Find current leader and next in line
	var current_leader_idx = -1
	var next_leader_idx = -1
	var lowest_rank = 999

	for i in range(updated_crew.size()):
		var crew = updated_crew[i]
		if crew.get("is_squadron_leader", false):
			current_leader_idx = i

		# Find pilot with lowest squadron_rank (highest seniority) who's still alive
		if crew.has("squadron_rank"):
			var rank = crew.squadron_rank
			if rank < lowest_rank and not crew.get("is_squadron_leader", false):
				lowest_rank = rank
				next_leader_idx = i

	# No one to promote
	if next_leader_idx == -1:
		return updated_crew

	# Remove old leader's command links if they existed
	if current_leader_idx >= 0:
		updated_crew[current_leader_idx].is_squadron_leader = false
		updated_crew[current_leader_idx].command_chain.subordinates = []

	# Promote new leader
	updated_crew[next_leader_idx].is_squadron_leader = true
	updated_crew[next_leader_idx].command_chain.superior = null
	updated_crew[next_leader_idx].command_chain.subordinates = []

	# All other pilots report to new leader
	for i in range(updated_crew.size()):
		if i != next_leader_idx and updated_crew[i].has("squadron_rank"):
			updated_crew[i].command_chain.superior = updated_crew[next_leader_idx].crew_id
			updated_crew[next_leader_idx].command_chain.subordinates.append(updated_crew[i].crew_id)

	return updated_crew

## Create a ship crew (captain, pilot, gunners)
static func create_ship_crew(weapon_count: int, skill_level: float = 0.5) -> Array:
	var crew = []

	# Create captain
	var captain = create_crew_member(Role.CAPTAIN, skill_level)
	crew.append(captain)

	# Create pilot (reports to captain)
	var pilot = create_crew_member(Role.PILOT, skill_level * 0.9)
	pilot.command_chain.superior = captain.crew_id
	captain.command_chain.subordinates.append(pilot.crew_id)
	crew.append(pilot)

	# Create gunners for each weapon (report to captain)
	for i in weapon_count:
		var gunner = create_crew_member(Role.GUNNER, skill_level * 0.9)
		gunner.command_chain.superior = captain.crew_id
		captain.command_chain.subordinates.append(gunner.crew_id)
		crew.append(gunner)

	return crew

## Create a squadron with leader and ships
static func create_squadron(ship_count: int, weapons_per_ship: int, skill_level: float = 0.5) -> Array:
	var all_crew = []

	# Create squadron leader
	var leader = create_crew_member(Role.SQUADRON_LEADER, skill_level)
	all_crew.append(leader)

	# Create crews for each ship
	for i in ship_count:
		var ship_crew = create_ship_crew(weapons_per_ship, skill_level * 0.85)

		# Captain reports to squadron leader
		var captain = ship_crew[0]
		captain.command_chain.superior = leader.crew_id
		leader.command_chain.subordinates.append(captain.crew_id)

		all_crew.append_array(ship_crew)

	return all_crew

## Assign crew member to entity (ship, weapon, etc.)
static func assign_crew_to_entity(crew_data: Dictionary, entity_id: String) -> Dictionary:
	var updated = crew_data.duplicate(true)
	updated.assigned_to = entity_id
	return updated

## Link two crew members in command chain
static func establish_command_link(superior: Dictionary, subordinate: Dictionary) -> Array:
	var updated_superior = superior.duplicate(true)
	var updated_subordinate = subordinate.duplicate(true)

	updated_subordinate.command_chain.superior = superior.crew_id
	if not updated_superior.command_chain.subordinates.has(subordinate.crew_id):
		updated_superior.command_chain.subordinates.append(subordinate.crew_id)

	return [updated_superior, updated_subordinate]

## Get role name as string
static func get_role_name(role: Role) -> String:
	match role:
		Role.PILOT: return "Pilot"
		Role.GUNNER: return "Gunner"
		Role.CAPTAIN: return "Captain"
		Role.SQUADRON_LEADER: return "Squadron Leader"
		Role.FLEET_COMMANDER: return "Fleet Commander"
		_: return "Unknown"
