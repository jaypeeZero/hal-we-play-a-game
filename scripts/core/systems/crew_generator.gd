class_name CrewGenerator
extends RefCounted

## Pure procedural generator for per-run crew rosters.
## Given the shipped base roster as a distribution seed, produces a fresh
## pool of `size` entries with rolled names, role-shaped skills, and
## attributes. Same seed → identical roster; no global state touched.

const NAMES_PATH := "res://data/crew_names.json"

## Maximum reroll attempts when deduplicating callsigns.
const MAX_NAME_RETRIES := 20


## Build a run roster of `size` entries shaped like the base roster's
## per-role skill distributions, with rolled names and attributes.
## Returns Array of roster entry dicts (id, callsign, roles, skills, attributes).
## Roles are assigned via a shuffled-deck pattern so every role appears at
## least floor(size / num_roles) times — prevents a starved role on small pools.
static func generate_run_roster(base: Array, size: int, rng: RandomNumberGenerator) -> Array:
	var role_means := _role_skill_means(base)
	var name_banks := _load_name_banks()

	# Role mix mirrors fleet DEMAND: the base roster is weighted toward the roles
	# ships actually need (many pilots/gunners, few commanders), so a generated
	# pool stays craftable. An even split would starve pilots and leave hulls
	# unflyable.
	var role_sequence := _demand_weighted_role_sequence(base, size, rng)

	var used_callsigns: Dictionary = {}
	var result: Array = []

	for i in range(size):
		# Pick a primary role from the pre-shuffled sequence.
		var primary_role: int = role_sequence[i]

		# Roll skills from the role-cohort distribution.
		var skills := _roll_skills(primary_role, role_means, rng)

		# Roll attributes for this role.
		var attributes: Array = AttributeLibrary.roll_attributes(primary_role, rng)

		# Roll a unique callsign.
		var callsign := _roll_unique_callsign(name_banks, used_callsigns, rng)
		used_callsigns[callsign] = true

		var id := "run_crew_%03d" % i
		result.append({
			"id": id,
			"callsign": callsign,
			"roles": [CrewData.role_to_name(primary_role)],
			"skills": skills,
			"attributes": attributes,
		})

	return result


## Build a length-`size` sequence of role ints whose proportions mirror the
## base roster's primary-role frequencies (fleet demand). Shortfalls from
## rounding are padded with the most-needed role so a pool never under-crews
## the fleet's pilots. Shuffled so role order doesn't bias which hull gets whom.
static func _demand_weighted_role_sequence(base: Array, size: int, rng: RandomNumberGenerator) -> Array:
	# Count primary roles in the base; fall back to an even mix if base is empty.
	var counts: Dictionary = {}
	for role_int in CrewData.ROLE_NAMES.keys():
		counts[role_int] = 0
	var total: int = 0
	for entry in base:
		var roles: Array = entry.get("roles", [])
		if roles.is_empty():
			continue
		counts[CrewData.role_from_name(str(roles[0]))] += 1
		total += 1
	if total == 0:
		for role_int in CrewData.ROLE_NAMES.keys():
			counts[role_int] = 1
			total += 1

	# Allocate proportional slots, then pad any shortfall with the highest-demand
	# role (the one with the largest base share — pilots/gunners in practice).
	var sequence: Array = []
	var top_role: int = CrewData.Role.PILOT
	var top_count: int = -1
	for role_int in counts:
		if counts[role_int] > top_count:
			top_count = counts[role_int]
			top_role = role_int
		var allotment: int = int(round(float(counts[role_int]) / float(total) * float(size)))
		for _j in range(allotment):
			sequence.append(role_int)
	while sequence.size() < size:
		sequence.append(top_role)
	sequence = sequence.slice(0, size)

	# Fisher-Yates shuffle using the seeded rng.
	for j in range(sequence.size() - 1, 0, -1):
		var k: int = rng.randi_range(0, j)
		var tmp = sequence[j]
		sequence[j] = sequence[k]
		sequence[k] = tmp
	return sequence


## Precompute role → {skill → mean} from the base roster entries.
## Entries with no matching cohort fall back to 0.5 for the missing skills.
static func _role_skill_means(base: Array) -> Dictionary:
	# role_name → {skill → [values]}
	var buckets: Dictionary = {}
	for role_int in CrewData.ROLE_NAMES.keys():
		buckets[CrewData.role_to_name(role_int)] = {}
		for skill_name in CrewData.SKILL_NAMES:
			buckets[CrewData.role_to_name(role_int)][skill_name] = []

	for entry in base:
		var roles: Array = entry.get("roles", [])
		if roles.is_empty():
			continue
		var primary_role_name: String = str(roles[0])
		if not buckets.has(primary_role_name):
			continue
		var entry_skills: Dictionary = entry.get("skills", {})
		for skill_name in CrewData.SKILL_NAMES:
			var v: float = clampf(float(entry_skills.get(skill_name, 0.5)), 0.0, 1.0)
			buckets[primary_role_name][skill_name].append(v)

	# Compute means; fall back to 0.5 when a cohort has no entries for a skill.
	var means: Dictionary = {}
	for role_name in buckets:
		means[role_name] = {}
		for skill_name in CrewData.SKILL_NAMES:
			var values: Array = buckets[role_name][skill_name]
			if values.is_empty():
				means[role_name][skill_name] = 0.5
			else:
				var total := 0.0
				for v in values:
					total += v
				means[role_name][skill_name] = total / float(values.size())

	return means


## Roll the 7 skills for a crew member of `primary_role`.
## Competence skills sample from the role-cohort mean ± gaussian noise.
## Aggression is personality: uniform random (mirrors CrewData._generate_stats_for_role).
static func _roll_skills(primary_role: int, role_means: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var role_name := CrewData.role_to_name(primary_role)
	var cohort_means: Dictionary = role_means.get(role_name, {})
	var skills := {}
	for skill_name in CrewData.SKILL_NAMES:
		if skill_name == CrewData.PERSONALITY_SKILL:
			skills[skill_name] = rng.randf()
		else:
			var mean: float = float(cohort_means.get(skill_name, 0.5))
			var noise: float = rng.randfn(0.0, WingConstants.GEN_SKILL_NOISE)
			skills[skill_name] = clampf(mean + noise, 0.0, 1.0)
	return skills


## Load the adjective/noun name banks from JSON, returning {adjectives, nouns}.
## Returns empty arrays on any load failure (generation degrades to numeric ids).
static func _load_name_banks() -> Dictionary:
	if not FileAccess.file_exists(NAMES_PATH):
		push_error("CrewGenerator: name bank missing: " + NAMES_PATH)
		return {"adjectives": [], "nouns": []}
	var file := FileAccess.open(NAMES_PATH, FileAccess.READ)
	if file == null:
		push_error("CrewGenerator: cannot open: " + NAMES_PATH)
		return {"adjectives": [], "nouns": []}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("CrewGenerator: JSON parse error in name banks")
		return {"adjectives": [], "nouns": []}
	file.close()
	var data = json.get_data()
	if not data is Dictionary:
		return {"adjectives": [], "nouns": []}
	return {
		"adjectives": data.get("adjectives", []),
		"nouns": data.get("nouns", []),
	}


## Roll one callsign ("Adjective Noun") not already in `used`, with capped retries.
## Falls back to a numeric suffix if the banks are exhausted or empty.
static func _roll_unique_callsign(banks: Dictionary, used: Dictionary, rng: RandomNumberGenerator) -> String:
	var adjs: Array = banks.get("adjectives", [])
	var nouns: Array = banks.get("nouns", [])
	if adjs.is_empty() or nouns.is_empty():
		return "Crew_%d" % used.size()

	for _attempt in range(MAX_NAME_RETRIES):
		var name := "%s %s" % [
			adjs[rng.randi_range(0, adjs.size() - 1)],
			nouns[rng.randi_range(0, nouns.size() - 1)],
		]
		if not used.has(name):
			return name

	# Banks exhausted within retries — append a suffix to guarantee uniqueness.
	var fallback := "%s %s_%d" % [
		adjs[rng.randi_range(0, adjs.size() - 1)],
		nouns[rng.randi_range(0, nouns.size() - 1)],
		used.size(),
	]
	return fallback
