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
	FLEET_COMMANDER,  # Strategic decisions for entire fleet
	ENGINEER      # Repairs the ship; machinery skill sets repair size
}

## Canonical skill order — single source of truth for roster entries,
## radar chart axes, editor rows, and validation. Physical skills lead so
## they cluster on the radar chart's top-right arc (axis 0 points up,
## winding clockwise); the mental skills fill the bottom-left arc.
const SKILL_NAMES := [
	"aim", "piloting", "machinery", "awareness", "tactics", "composure", "aggression",
]

## Skill groupings for chart clustering and UI labelling. Together they are
## exactly SKILL_NAMES; each skill belongs to one group.
const PHYSICAL_SKILLS := ["aim", "piloting", "machinery"]
const MENTAL_SKILLS := ["awareness", "tactics", "composure", "aggression"]

## Aggression is personality, not competence — excluded from the derived
## reaction/decision scalar and distributed independently by generators.
const PERSONALITY_SKILL := "aggression"

## Stable snake_case role names for human-editable data files. Roster JSON
## stores these strings, never enum ints, so files survive enum reordering.
const ROLE_NAMES := {
	Role.PILOT: "pilot",
	Role.GUNNER: "gunner",
	Role.CAPTAIN: "captain",
	Role.SQUADRON_LEADER: "squadron_leader",
	Role.FLEET_COMMANDER: "fleet_commander",
	Role.ENGINEER: "engineer",
}

static func role_to_name(role: int) -> String:
	return ROLE_NAMES.get(role, ROLE_NAMES[Role.PILOT])

## Resolve a snake_case role name to a Role value; unknown names default
## to PILOT (validation backfill, never an error).
static func role_from_name(name: String) -> int:
	for role in ROLE_NAMES:
		if ROLE_NAMES[role] == name:
			return role
	return Role.PILOT

## Resolve a roster entry's `roles` array (snake_case names, first entry is
## the default/primary role) into Role ints, deduplicated. An empty or
## missing array backfills to PILOT, matching role_from_name's policy.
static func qualified_roles_from_entry(entry: Dictionary) -> Array:
	var roles: Array = []
	for role_name in entry.get("roles", []):
		var role := role_from_name(str(role_name))
		if not roles.has(role):
			roles.append(role)
	if roles.is_empty():
		roles.append(Role.PILOT)
	return roles

## The serving role of any crew-ish dict, as a Role int — the ONE place role is
## read off a dict. Handles every shape that has bitten us:
##   • a live crew dict   → its `role` int
##   • a JSON-loaded crew → `role` as a float (2.0) — int()-coerced
##   • a roster entry     → first of its `roles` name array (no `role` key)
## Never returns an out-of-range value: an unknown/missing role falls back to
## PILOT, so callers never render "Unknown" or compare against a stray -1.
## Prefer this over `int(member.get("role", -1))` everywhere.
static func role_of(member: Dictionary) -> int:
	if member.has("role") and member["role"] != null:
		var role := int(member["role"])
		return role if ROLE_NAMES.has(role) else Role.PILOT
	var roles: Array = member.get("roles", [])
	if not roles.is_empty():
		return role_from_name(str(roles[0]))
	return Role.PILOT

## The qualified roles of any crew-ish dict, as Role ints. Reads `qualified_roles`
## (live crew) or `roles` names (roster entry); defaults to [serving role].
static func roles_of(member: Dictionary) -> Array:
	if member.has("qualified_roles") and not member["qualified_roles"].is_empty():
		var ints: Array = []
		for q in member["qualified_roles"]:
			ints.append(int(q))
		return ints
	if not member.get("roles", []).is_empty():
		return qualified_roles_from_entry(member)
	return [role_of(member)]

## Whether the crew member is qualified to serve in `role`.
static func is_qualified_for(crew: Dictionary, role: int) -> bool:
	return crew.get("qualified_roles", []).has(role)

## Crew assigned to a role outside their qualifications operate at 70%
## performance in all areas: every effective skill read and the derived
## reaction/decision speeds degrade by 30%.
const OFF_ROLE_PERFORMANCE_MULTIPLIER := 0.7

## True when the crew member's assigned role is outside their qualifications.
## Crew carrying no qualification data (hand-assembled battle crew) count as
## qualified for whatever they are assigned to.
static func is_off_role(crew: Dictionary) -> bool:
	var qualified: Array = crew.get("qualified_roles", [])
	if qualified.is_empty():
		return false
	# Compare as ints: JSON-loaded crew encode role ids as floats (2.0), so a
	# raw Array.has(int) membership test would spuriously report off-role.
	var role: int = int(crew.get("role", -1))
	for q in qualified:
		if int(q) == role:
			return false
	return true

## The performance multiplier this crew member's assignment earns: the
## off-role penalty, or full performance when serving in a qualified role.
static func role_performance_multiplier(crew: Dictionary) -> float:
	return OFF_ROLE_PERFORMANCE_MULTIPLIER if is_off_role(crew) else 1.0

## Human-readable, comma-joined display names for a roster `roles` array.
static func display_role_names(roles: Array) -> String:
	var names: Array = []
	for role_name in roles:
		names.append(get_role_name(role_from_name(str(role_name))))
	return ", ".join(names)

## Create a crew member with given role and skill level
static func create_crew_member(role: Role, skill_level: float = 0.5) -> Dictionary:
	var crew_id = "crew_" + str(_next_crew_id)
	_next_crew_id += 1

	var base_crew = {
		"crew_id": crew_id,
		"role": role,  # the role they are assigned to serve in
		"qualified_roles": [role],  # roles they are trained for (>= 1)
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
		"current_action": null,  # What they're doing now
		"attributes": [],  # Array of attribute id strings (see AttributeLibrary)
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

## Overall competence scalar for a heterogeneous skill set: mean of all
## skills except aggression (personality). Drives reaction/decision time.
static func derived_skill_scalar(skills: Dictionary) -> float:
	var total := 0.0
	var count := 0
	for skill_name in SKILL_NAMES:
		if skill_name == PERSONALITY_SKILL:
			continue
		total += clampf(float(skills.get(skill_name, 0.0)), 0.0, 1.0)
		count += 1
	return total / float(count)

## Recompute the derived stats (reaction_time, decision_time,
## awareness_range) from role + skills. The only place these are ever
## computed for skill-edited crew — callers must never set them directly.
## `performance_multiplier` scales the skill scalar DOWN (off-role crew pass
## OFF_ROLE_PERFORMANCE_MULTIPLIER), so the derived times worsen — never
## multiply the times themselves, which would improve them.
static func recompute_derived_stats(stats: Dictionary, role: int, performance_multiplier: float = 1.0) -> Dictionary:
	var updated: Dictionary = stats.duplicate(true)
	var modifiers := _get_role_modifiers(role)
	var scalar := derived_skill_scalar(updated.get("skills", {})) * performance_multiplier
	updated["reaction_time"] = _calculate_reaction_time(scalar, modifiers.reaction_base)
	updated["decision_time"] = _calculate_decision_time(scalar, modifiers.decision_base)
	updated["awareness_range"] = modifiers.awareness_range
	return updated

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
	fresh.qualified_roles = saved.get("qualified_roles", fresh.qualified_roles).duplicate()
	fresh.known_patterns = saved.get("known_patterns", []).duplicate()
	fresh.attributes = saved.get("attributes", []).duplicate()
	fresh.command_chain = saved.get("command_chain", fresh.command_chain).duplicate(true)
	# A gunner's weapon binding is persistent identity: it decides which weapon
	# they man and, if its mount is shot off, whether they become a casualty.
	if saved.has("weapon_id"):
		fresh.weapon_id = saved.weapon_id
	return fresh

## Build a full battle-ready crew dict from a roster entry
## ({id, callsign, roles: Array[String], skills: {...}}). The first listed
## role becomes the assigned role. Pure with respect to the roster —
## consuming the entry from the hiring pool is the caller's job.
static func from_roster_entry(entry: Dictionary) -> Dictionary:
	var roles := qualified_roles_from_entry(entry)
	return apply_roster_entry(create_crew_member(roles[0]), entry)

## Give an existing crew dict a roster entry's identity: callsign, skills,
## and qualified roles carry over, derived stats recompute for the member's
## assigned role. Structure (crew_id, command chain, weapon binding) is
## untouched — used both to build fresh hires and to crew run-start
## complements in place.
static func apply_roster_entry(member: Dictionary, entry: Dictionary) -> Dictionary:
	member["callsign"] = str(entry.get("callsign", member.crew_id))
	member["qualified_roles"] = qualified_roles_from_entry(entry)
	member["attributes"] = entry.get("attributes", member.get("attributes", [])).duplicate()
	var entry_skills: Dictionary = entry.get("skills", {})
	var skills: Dictionary = member.stats.skills
	for skill_name in SKILL_NAMES:
		# Missing skills keep the canonical default from create_crew_member.
		skills[skill_name] = clampf(float(entry_skills.get(skill_name, skills[skill_name])), 0.0, 1.0)
	member["stats"] = recompute_derived_stats(
		member.stats, int(member.get("role", Role.PILOT)), role_performance_multiplier(member))
	return member

## Assign a crew member to serve in `role` — which may be outside their
## qualifications, in which case the off-role penalty lands on the derived
## stats — and recompute their derived stats for it. Mutates and returns
## the member.
static func assign_role(member: Dictionary, role: int) -> Dictionary:
	member["role"] = role
	member["stats"] = recompute_derived_stats(member.stats, role, role_performance_multiplier(member))
	return member

## Adapt a live crew dict to the roster-entry shape so fleet crew can feed
## the same CrewMemberView as roster candidates. Display use only.
static func entry_from_crew(member: Dictionary) -> Dictionary:
	var stats: Dictionary = member.get("stats", {})
	var member_skills: Dictionary = stats.get("skills", {})
	var skills := {}
	for skill_name in SKILL_NAMES:
		skills[skill_name] = clampf(float(member_skills.get(skill_name, 0.0)), 0.0, 1.0)
	var role_names: Array = []
	for role in member.get("qualified_roles", [int(member.get("role", Role.PILOT))]):
		role_names.append(role_to_name(int(role)))
	return {
		"id": str(member.get("crew_id", "")),
		"callsign": str(member.get("callsign", member.get("crew_id", ""))),
		"roles": role_names,
		"skills": skills,
		"attributes": member.get("attributes", []).duplicate(),
	}


## Bind each gunner to a weapon by id, assigning from the END of the weapons
## array backwards. This pairs partial complements correctly — a lone gunner
## takes the rear/secondary weapon (e.g. a heavy fighter's rear turret) while
## the pilot works the forward guns. Gunners with no weapon left stay unbound.
## Skips gunners that already carry a weapon_ids group (pepperbox binding) so
## callers do not need to guard against re-binding after create_gunboat_crew.
## Mutates the crew dicts in place and returns the array.
static func bind_gunners_to_weapons(crew: Array, weapons: Array) -> Array:
	var next := weapons.size() - 1
	for member in crew:
		if member.get("role", -1) != Role.GUNNER:
			continue
		if member.has("weapon_ids"):
			continue  # Already group-bound (pepperbox); do not overwrite with scalar.
		if next < 0:
			member.erase("weapon_id")
			continue
		member["weapon_id"] = weapons[next].get("weapon_id", "")
		next -= 1
	return crew


## Bind gunners to weapon *groups* (pepperbox mechanic). Each group is an Array
## of weapon dicts that fire together in sync. A gunner carries `weapon_ids`
## (Array[String]) instead of a scalar `weapon_id`. The 1:1 path is untouched.
## `weapon_groups` is an Array of Arrays — outer index = gunner slot (0..n-1).
## Mutates the gunner dicts in place and returns the crew array.
static func bind_gunner_groups(crew: Array, weapon_groups: Array) -> Array:
	var group_idx := 0
	for member in crew:
		if member.get("role", -1) != Role.GUNNER:
			continue
		if group_idx >= weapon_groups.size():
			push_error("bind_gunner_groups: more gunners than weapon groups — gunner '%s' has no group; erasing binding" % member.get("crew_id", "?"))
			member.erase("weapon_ids")
			continue
		var group: Array = weapon_groups[group_idx]
		var ids: Array[String] = []
		for w in group:
			ids.append(str(w.get("weapon_id", "")))
		member["weapon_ids"] = ids
		group_idx += 1
	return crew


## Create a gunboat crew (pilot-led, no captain). Composition depends on variant:
##   gunboat_medic:       1 pilot + MEDIC_GUNNER_COUNT gunners (1:1 turrets) + MEDIC_ENGINEER_COUNT engineers
##   gunboat_pepperbox:   1 pilot + (weapons.size() / PEPPERBOX_GUNS_PER_GUNNER) gunners, each
##                        controlling PEPPERBOX_GUNS_PER_GUNNER guns in sync
##   gunboat_firecracker: 1 pilot + FIRECRACKER_GUNNER_COUNT gunners (1:1 tubes)
## Caller passes the template weapons array so gunner binding is correct.
## Returns the crew array WITHOUT ship assignment — caller calls assign_crew_to_entity.
static func create_gunboat_crew(ship_type: String, weapons: Array, skill_level: float) -> Array:
	const MEDIC_GUNNER_COUNT: int = 2
	const MEDIC_ENGINEER_COUNT: int = 2
	const PEPPERBOX_GUNS_PER_GUNNER: int = 2
	const FIRECRACKER_GUNNER_COUNT: int = 5

	var crew: Array = []
	var pilot := create_crew_member(Role.PILOT, skill_level)
	crew.append(pilot)

	match ship_type:
		"gunboat_medic":
			# 2 defensive turrets → 2 gunners (1:1); 2 engineers for hull repair
			for _i in MEDIC_GUNNER_COUNT:
				crew.append(create_crew_member(Role.GUNNER, skill_level * 0.9))
			for _i in MEDIC_ENGINEER_COUNT:
				crew.append(create_crew_member(Role.ENGINEER, skill_level * 0.9))
			bind_gunners_to_weapons(crew, weapons)

		"gunboat_pepperbox":
			# Derive gunner count from the actual weapons array; each gunner controls
			# PEPPERBOX_GUNS_PER_GUNNER guns in sync.
			if weapons.is_empty():
				push_error("create_gunboat_crew: pepperbox requires a non-empty weapons array")
				return crew
			if weapons.size() % PEPPERBOX_GUNS_PER_GUNNER != 0:
				push_error("create_gunboat_crew: pepperbox weapon count (%d) must be divisible by PEPPERBOX_GUNS_PER_GUNNER (%d)" % [weapons.size(), PEPPERBOX_GUNS_PER_GUNNER])
			var gunner_count: int = weapons.size() / PEPPERBOX_GUNS_PER_GUNNER
			for _i in gunner_count:
				crew.append(create_crew_member(Role.GUNNER, skill_level * 0.9))
			# Build groups: [[w0,w1], [w2,w3], ...]
			var groups: Array = []
			for gi in gunner_count:
				var start: int = gi * PEPPERBOX_GUNS_PER_GUNNER
				var group: Array = []
				for wi in PEPPERBOX_GUNS_PER_GUNNER:
					var idx: int = start + wi
					if idx < weapons.size():
						group.append(weapons[idx])
				groups.append(group)
			bind_gunner_groups(crew, groups)

		"gunboat_firecracker":
			# 5 torpedo tubes → 5 gunners (1:1)
			for _i in FIRECRACKER_GUNNER_COUNT:
				crew.append(create_crew_member(Role.GUNNER, skill_level * 0.9))
			bind_gunners_to_weapons(crew, weapons)

	return crew


## Create the crew complement for one hull of the given ship type.
## For gunboat variants, fetches the ship template weapons and delegates to
## create_gunboat_crew — all call sites can use this single function.
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
		"gunboat_medic", "gunboat_pepperbox", "gunboat_firecracker":
			# Fetch template weapons so create_gunboat_crew can bind gunners correctly.
			# weapon_count alone is insufficient for grouped/pepperbox binding.
			var template_weapons: Array = ShipData.get_ship_template(ship_type).get("weapons", [])
			if template_weapons.is_empty():
				push_error("create_crew_for_ship_type: no template weapons for %s" % ship_type)
				return []
			return create_gunboat_crew(ship_type, template_weapons, skill_level)
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
	for skill_name in SKILL_NAMES:
		if skill_name == PERSONALITY_SKILL:
			continue
		var variance = randf_range(-0.15, 0.15)
		crew.stats.skills[skill_name] = clamp(skill_level + variance, 0.0, 1.0)
	# Aggression is personality, not skill — distribute independently
	crew.stats.skills[PERSONALITY_SKILL] = randf()

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
