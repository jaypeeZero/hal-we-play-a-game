class_name CrewData
extends RefCounted

## Pure data container and factory for crew members
## Creates crew with different roles and stats for hierarchical AI system

static var _next_crew_id: int = 0

## Callsign pool for roster crew identity; cycles with a numeric suffix
## once exhausted ("Dash", ..., "Dash 2", ...).
const CALLSIGN_POOL := [
	"Dash", "Echo", "Frost", "Hawk", "Iris", "Jinx", "Koda", "Lark",
	"Moss", "Nova", "Onyx", "Pike", "Quill", "Rook", "Sable", "Tarn",
	"Umber", "Vesper", "Wren", "Zephyr",
]

static func callsign_for_index(index: int) -> String:
	var cycle: int = index / CALLSIGN_POOL.size()
	var name: String = CALLSIGN_POOL[index % CALLSIGN_POOL.size()]
	return name if cycle == 0 else "%s %d" % [name, cycle + 1]

## Crew roles in command hierarchy
enum Role {
	PILOT,        # Flies the ship, responds to immediate threats
	GUNNER,       # Operates weapons, picks targets within orders
	CAPTAIN,      # Commands ship-level decisions, coordinates crew
	SQUADRON_LEADER,  # Commands multiple ships, prioritizes squadron targets
	FLEET_COMMANDER,  # Strategic decisions for entire fleet
	ENGINEER      # Repairs the ship; machinery skill sets repair size
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
		# Tactical pattern ids this crew member knows (data/knowledge/*.json).
		# Empty = the full role baseline. Training and player instructions
		# grow this set; knowledge queries are filtered to it.
		"known_patterns": [],
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
		"combat_state": {
			"locked_target_id": "",  # For rookie target fixation
			"lock_start_time": 0.0
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
		"next_decision_time": 0.0,  # Scheduler wakes the crew at this game_time.
		"current_action": null  # What they're doing now
	}

	return base_crew

## Generate stats based on role and skill level
static func _generate_stats_for_role(role: Role, skill_level: float) -> Dictionary:
	# Base stats that vary by role
	var role_modifiers = _get_role_modifiers(role)

	var base = clamp(skill_level, 0.0, 1.0)
	return {
		"reaction_time": _calculate_reaction_time(skill_level, role_modifiers.reaction_base),
		"awareness_range": role_modifiers.awareness_range,
		"decision_time": _calculate_decision_time(skill_level, role_modifiers.decision_base),
		"stress": 0.0,  # Increases in combat, reduces performance
		"fatigue": 0.0,  # Increases over time
		# Seven-stat schema. Every stat is mechanically wired; what changes by
		# role is *which* stats are read.
		"skills": {
			"aim": base,        # Weapon accuracy, lead quality, prediction
			"piloting": base,   # Turn rate, accel, lateral, dampening, jink, evasion commit
			"awareness": base,  # Sensor range, detection latency, threat prioritization
			"tactics": base,    # Command-style, squadron coord, retreat, target prio
			"composure": base,  # Performance under stress; gates panic
			"aggression": randf(), # Engagement bias / persistence — personality, not skill
			"machinery": base   # Repair size — only exercised in the ENGINEER role
		}
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
				"decision_base": 1.0,  # More complex decisions
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
		Role.ENGINEER:
			return {
				"reaction_base": 0.4,  # Repairs aren't twitch reactions
				"decision_base": 1.5,  # Methodical triage
				"awareness_range": 600.0  # Focused inward on own ship
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

## Create a heavy fighter crew (pilot + gunner, pilot has higher skill)
## The pilot commands the ship and forward weapons
## The gunner operates the rear turret for defensive coverage
static func create_heavy_fighter_crew(skill_level: float = 0.5) -> Array:
	# Pilot gets the base skill level (they should be the better pilot)
	var pilot = create_crew_member(Role.PILOT, skill_level)

	# Gunner gets slightly lower skill (90% of pilot)
	var gunner = create_crew_member(Role.GUNNER, skill_level * 0.9)

	# Gunner reports to pilot (pilot is in command of this small craft)
	gunner.command_chain.superior = pilot.crew_id
	pilot.command_chain.subordinates.append(gunner.crew_id)

	return [pilot, gunner]

## Create a torpedo boat crew (pilot + torpedo operator)
## The pilot flies and operates the gatling gun
## The torpedo operator manages torpedo targeting and launch
static func create_torpedo_boat_crew(skill_level: float = 0.5) -> Array:
	var pilot = create_crew_member(Role.PILOT, skill_level)

	# Torpedo operator — slow projectiles reward strong aim/lead prediction.
	var torpedo_operator = create_crew_member(Role.GUNNER, skill_level * 0.95)

	# Torpedo operator reports to pilot
	torpedo_operator.command_chain.superior = pilot.crew_id
	pilot.command_chain.subordinates.append(torpedo_operator.crew_id)

	return [pilot, torpedo_operator]

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

## Create a ship crew (captain, pilot, gunners, engineers)
static func create_ship_crew(weapon_count: int, skill_level: float = 0.5, engineer_count: int = 0) -> Array:
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

	# Create engineers (report to captain)
	for i in engineer_count:
		var engineer = create_crew_member(Role.ENGINEER, skill_level * 0.9)
		engineer.command_chain.superior = captain.crew_id
		captain.command_chain.subordinates.append(engineer.crew_id)
		crew.append(engineer)

	return crew

## Roll how many engineers a hull carries.
static func roll_engineer_count(ship_type: String) -> int:
	match ship_type:
		"corvette":
			return randi_range(WingConstants.CORVETTE_ENGINEERS_MIN, WingConstants.CORVETTE_ENGINEERS_MAX)
		"capital":
			return randi_range(WingConstants.CAPITAL_ENGINEERS_MIN, WingConstants.CAPITAL_ENGINEERS_MAX)
		_:
			return 0

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

## Rebuild a saved crew member for a new battle. Persistent identity —
## crew_id, callsign, stats/skills, known_patterns, command chain —
## carries over; per-battle state (awareness, combat_state, orders,
## decision timing) starts fresh, and stress/fatigue recover between
## battles.
static func reset_for_battle(saved: Dictionary) -> Dictionary:
	var fresh = create_crew_member(saved.get("role", Role.PILOT))
	fresh.crew_id = saved.get("crew_id", fresh.crew_id)
	if saved.has("callsign"):
		fresh.callsign = saved.callsign
	fresh.stats = saved.get("stats", fresh.stats).duplicate(true)
	fresh.stats.stress = 0.0
	fresh.stats.fatigue = 0.0
	fresh.known_patterns = saved.get("known_patterns", []).duplicate()
	fresh.command_chain = saved.get("command_chain", fresh.command_chain).duplicate(true)
	return fresh

## Create the crew complement for one hull of the given ship type.
static func create_crew_for_ship_type(ship_type: String, weapon_count: int, skill_level: float) -> Array:
	match ship_type:
		"fighter":
			return create_solo_fighter_crew(skill_level)
		"heavy_fighter":
			return create_heavy_fighter_crew(skill_level)
		"torpedo_boat":
			return create_torpedo_boat_crew(skill_level)
		"corvette", "capital":
			return create_ship_crew(weapon_count, skill_level, roll_engineer_count(ship_type))
		_:
			return []

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
		Role.ENGINEER: return "Engineer"
		_: return "Unknown"

## Create crew member with varied discrete skills (±0.15 variance from base)
static func create_crew_member_with_varied_skills(role: Role, skill_level: float = 0.5) -> Dictionary:
	var crew = create_crew_member(role, skill_level)

	# Generate varied discrete skills around the base skill_level
	var skill_names = ["aim", "piloting", "awareness", "tactics", "composure", "machinery"]
	for skill_name in skill_names:
		var variance = randf_range(-0.15, 0.15)
		crew.stats.skills[skill_name] = clamp(skill_level + variance, 0.0, 1.0)
	# Aggression is personality, not skill — distribute independently
	crew.stats.skills["aggression"] = randf()

	return crew

## Create pilot archetype with specific skill profile
static func create_pilot_archetype(archetype: String, skill_level: float = 0.5) -> Dictionary:
	var crew = create_crew_member_with_varied_skills(Role.PILOT, skill_level)
	var skills = crew.stats.skills

	match archetype:
		"aggressive_ace":
			skills["aggression"] = 0.9
			skills["composure"] = 0.7
			skills["aim"] = clamp(skill_level + 0.1, 0.0, 1.0)
			skills["awareness"] = clamp(skill_level + 0.05, 0.0, 1.0)
		"calculating_ace":
			skills["aggression"] = 0.4
			skills["aim"] = 0.95
			skills["awareness"] = 0.9
			skills["tactics"] = 0.9
			skills["composure"] = clamp(skill_level + 0.1, 0.0, 1.0)
		"survivor":
			skills["composure"] = 0.95
			skills["awareness"] = 0.9
			skills["aggression"] = 0.3
			skills["piloting"] = clamp(skill_level + 0.1, 0.0, 1.0)
		"hot_head":
			skills["aggression"] = 0.95
			skills["composure"] = 0.2
			skills["tactics"] = 0.3
			skills["aim"] = clamp(skill_level + 0.15, 0.0, 1.0)
		_:
			pass  # Use varied skills as generated

	return crew

## Create a fighter squadron with varied pilot archetypes
static func create_fighter_squadron_with_archetypes(skill_level: float = 0.5) -> Array:
	var all_crew = []
	var ranks = ["Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta"]
	var archetypes = ["calculating_ace", "aggressive_ace", "survivor", "hot_head", "aggressive_ace", "survivor"]

	# Create 6 fighters with distinct archetypes
	for i in range(6):
		var pilot = create_pilot_archetype(archetypes[i], skill_level)
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
