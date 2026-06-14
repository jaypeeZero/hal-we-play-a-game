class_name SkirmishFleet
extends RefCounted

## Skirmish fleet provider: persists individual ship records (not counts)
## for each team. Generates from STARTER_COUNTS on first load, migrates
## legacy count saves automatically.

const SAVE_PATH_TEMPLATE := "user://skirmish_fleet_team_%d.json"
const LEGACY_PATH_TEMPLATE := "user://team_%d_fleet.json"
const DOCTRINE_SAVE_PATH := "user://skirmish_doctrine.json"

const STARTER_COUNTS: Dictionary = {
	"fighter": 6,
	"heavy_fighter": 3,
	"torpedo_boat": 2,
	"corvette": 2,
	"capital": 1,
}

const BEST_POOL_SIZE: int = 100

## Skills that measure crew competence (aggression is personality, excluded).
const RATING_SKILLS: Array = ["aim", "piloting", "machinery", "awareness", "tactics", "composure"]

## Default per-ship mission (SquadronData.Mission.FREE).
const DEFAULT_MISSION: String = "free"

const COMPLEMENT_TEMPLATE_SKILL: float = 0.5


## Load the saved fleet for team. Generates and persists on first call.
## Migrates legacy count saves when no new save exists.
static func get_fleet(team: int) -> Array:
	var save_path: String = SAVE_PATH_TEMPLATE % team
	if FileAccess.file_exists(save_path):
		var loaded: Array = _load_ships(save_path)
		if not loaded.is_empty():
			return loaded
	# No valid new save — check for legacy counts to migrate.
	var legacy_path: String = LEGACY_PATH_TEMPLATE % team
	if FileAccess.file_exists(legacy_path):
		var counts: Dictionary = _load_legacy_counts(legacy_path)
		if not counts.is_empty():
			var ships: Array = _materialize(counts, _new_rng())
			save_fleet(team, ships)
			return ships
	# No save at all — generate from starter counts.
	return reset_to_starter(team)


## Persist ship records for team. Returns true on success.
static func save_fleet(team: int, ships: Array) -> bool:
	var save_path: String = SAVE_PATH_TEMPLATE % team
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_error("SkirmishFleet: failed to open %s for writing" % save_path)
		return false
	file.store_string(JSON.stringify(ships, "\t"))
	file.close()
	return true


## Load the persisted skirmish doctrine store. Returns empty_doctrine() on
## first call or if the file is absent/corrupt.
static func get_doctrine() -> Dictionary:
	if not FileAccess.file_exists(DOCTRINE_SAVE_PATH):
		return DoctrineSystem.empty_doctrine()
	var file := FileAccess.open(DOCTRINE_SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("SkirmishFleet: failed to open %s for reading" % DOCTRINE_SAVE_PATH)
		return DoctrineSystem.empty_doctrine()
	var json_string: String = file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(json_string) != OK:
		push_error("SkirmishFleet: JSON parse error in %s: %s" % [DOCTRINE_SAVE_PATH, json.get_error_message()])
		return DoctrineSystem.empty_doctrine()
	var data: Variant = json.get_data()
	if data is Dictionary:
		return data
	return DoctrineSystem.empty_doctrine()


## Persist the skirmish doctrine store to disk. Returns true on success.
static func set_doctrine(doctrine: Dictionary) -> bool:
	var file := FileAccess.open(DOCTRINE_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SkirmishFleet: failed to open %s for writing" % DOCTRINE_SAVE_PATH)
		return false
	file.store_string(JSON.stringify(doctrine, "\t"))
	file.close()
	return true


## The active doctrine store: run doctrine when a roguelite run is in
## progress, skirmish doctrine otherwise. Both the spawn compile and the
## UI use this so there is no scattered `if RoguelikeRun.active` logic.
static func current_doctrine() -> Dictionary:
	if RoguelikeRun.active:
		return RoguelikeRun.doctrine
	return get_doctrine()


## Regenerate fleet from STARTER_COUNTS, persist, and return the new ships.
static func reset_to_starter(team: int) -> Array:
	var ships: Array = _materialize(STARTER_COUNTS, _new_rng())
	save_fleet(team, ships)
	return ships


## Build a CREWLESS hull of ship_type (complement only, empty crew). Used by
## SkirmishSource.add_ship, which fills the complement from the existing crew
## pool — so no crew are drawn here (avoids double-drawing the same roster person
## into both the new hull and the bench).
static func empty_hull(ship_type: String, hull_index: int) -> Dictionary:
	var weapons: Array = ShipData.get_ship_template(ship_type).get("weapons", [])
	var template_crew: Array = CrewData.create_crew_for_ship_type(
		ship_type, weapons.size(), COMPLEMENT_TEMPLATE_SKILL)
	template_crew = CrewData.bind_gunners_to_weapons(template_crew, weapons)
	return {
		"hull_id": "hull_%d" % hull_index,
		"ship_type": ship_type,
		"name": "",
		"crew": [],
		"complement": _complement_from_crew(template_crew),
		"tactics": {"mission": DEFAULT_MISSION, "mission_params": {}},
		"iced": false,
		"ship": {},
	}


## Freshly randomized RNG, mirroring RoguelikeRun's convention so each
## generation/reset draws a different (random) crew from the best pool.
static func _new_rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng


## Derive {ship_type: count} for legacy consumers (pre-plan-04 callers).
static func fleet_counts(team: int) -> Dictionary:
	var ships: Array = get_fleet(team)
	var counts: Dictionary = {}
	for ship_type in FleetDataManager.SHIP_TYPES:
		counts[ship_type] = 0
	for ship in ships:
		var t: String = str(ship.get("ship_type", ""))
		if counts.has(t):
			counts[t] = int(counts[t]) + 1
	return counts


## Mean of RATING_SKILLS for a roster entry.
static func crew_rating(entry: Dictionary) -> float:
	var skills: Dictionary = entry.get("skills", {})
	var total: float = 0.0
	for skill_name in RATING_SKILLS:
		total += clampf(float(skills.get(skill_name, 0.0)), 0.0, 1.0)
	return total / float(RATING_SKILLS.size())


## Top BEST_POOL_SIZE roster entries by crew_rating, highest first.
static func best_pool() -> Array:
	var all_entries: Array = CrewRosterManager.load_roster()
	all_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return crew_rating(a) > crew_rating(b))
	return all_entries.slice(0, BEST_POOL_SIZE)


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

## Materialize a counts dict into individual ship records, crewing each hull
## from best_pool() with role-qualified picks where available.
static func _materialize(counts: Dictionary, rng: RandomNumberGenerator) -> Array:
	var pool: Array = best_pool()
	# Track which roster ids have been drawn so each member is used once.
	var used_ids: Dictionary = {}
	var ships: Array = []
	var hull_index: int = 0
	for ship_type in FleetDataManager.SHIP_TYPES:
		var count: int = int(counts.get(ship_type, 0))
		for _i in range(count):
			var hull: Dictionary = _make_hull(ship_type, hull_index, pool, used_ids, rng)
			ships.append(hull)
			hull_index += 1
	return ships


## Build one ship record. Draws crew from pool, role-qualified where possible.
static func _make_hull(
		ship_type: String,
		hull_index: int,
		pool: Array,
		used_ids: Dictionary,
		rng: RandomNumberGenerator) -> Dictionary:
	var weapons: Array = ShipData.get_ship_template(ship_type).get("weapons", [])
	var template_crew: Array = CrewData.create_crew_for_ship_type(
		ship_type, weapons.size(), COMPLEMENT_TEMPLATE_SKILL)
	template_crew = CrewData.bind_gunners_to_weapons(template_crew, weapons)
	var complement: Array = _complement_from_crew(template_crew)
	var crew: Array = _crew_from_pool(template_crew, pool, used_ids, rng)
	crew = _prune_command_chains(crew)
	return {
		"hull_id": "hull_%d" % hull_index,
		"ship_type": ship_type,
		"name": "",
		"crew": crew,
		"complement": complement,
		"tactics": {"mission": DEFAULT_MISSION, "mission_params": {}},
		"iced": false,
		"ship": {},
	}


## Build complement slots from template crew (role + optional weapon_id).
static func _complement_from_crew(template_crew: Array) -> Array:
	var complement: Array = []
	for member in template_crew:
		var slot: Dictionary = {"role": int(member.get("role", CrewData.Role.PILOT))}
		if member.has("weapon_id"):
			slot["weapon_id"] = str(member["weapon_id"])
		complement.append(slot)
	return complement


## Crew template slots from pool. Role-qualified draw first; falls back to
## best available if no qualified entry remains. Off-role fallback is flagged
## via `off_role: true`. Consumes each pool entry at most once across the fleet.
static func _crew_from_pool(
		template_crew: Array,
		pool: Array,
		used_ids: Dictionary,
		rng: RandomNumberGenerator) -> Array:
	var crew: Array = []
	for member in template_crew:
		var role: int = int(member.get("role", CrewData.Role.PILOT))
		var entry: Dictionary = _draw_entry(role, pool, used_ids, rng)
		if entry.is_empty():
			continue
		var hired: Dictionary = CrewData.apply_roster_entry(member.duplicate(true), entry)
		if not entry.get("roles", []).has(CrewData.role_to_name(role)):
			hired["off_role"] = true
		crew.append(hired)
	return crew


## Draw one unused pool entry qualified for role; fallback: best unused entry.
## Returns {} when the pool is exhausted entirely.
static func _draw_entry(
		role: int,
		pool: Array,
		used_ids: Dictionary,
		rng: RandomNumberGenerator) -> Dictionary:
	var role_name: String = CrewData.role_to_name(role)
	# Gather qualified candidates from the pool that haven't been used.
	var qualified: Array = []
	for entry in pool:
		if used_ids.has(str(entry.get("id", ""))):
			continue
		if entry.get("roles", []).has(role_name):
			qualified.append(entry)
	if not qualified.is_empty():
		var pick: Dictionary = qualified[rng.randi_range(0, qualified.size() - 1)]
		used_ids[str(pick.get("id", ""))] = true
		return pick
	# Fallback: best unused entry of any role.
	for entry in pool:
		var entry_id: String = str(entry.get("id", ""))
		if not used_ids.has(entry_id):
			used_ids[entry_id] = true
			return entry
	return {}


## Remove command-chain references to dropped crew (pool-exhausted vacancies).
static func _prune_command_chains(crew: Array) -> Array:
	var kept: Dictionary = {}
	for member in crew:
		kept[str(member.get("crew_id", ""))] = true
	for member in crew:
		var superior = member.get("command_chain", {}).get("superior", null)
		if superior != null and not kept.has(str(superior)):
			member["command_chain"]["superior"] = null
		var subs: Array = member.get("command_chain", {}).get("subordinates", [])
		member["command_chain"]["subordinates"] = subs.filter(
			func(cid: String) -> bool: return kept.has(cid))
	return crew


## Load ship records from a new-format save file.
static func _load_ships(path: String) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("SkirmishFleet: failed to open %s for reading" % path)
		return []
	var json_string: String = file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(json_string) != OK:
		push_error("SkirmishFleet: JSON parse error in %s: %s" % [path, json.get_error_message()])
		return []
	var data = json.get_data()
	if data is Array:
		return data
	return []


## Load legacy count save ({ship_type: int}).
static func _load_legacy_counts(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json_string: String = file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(json_string) != OK:
		return {}
	var data = json.get_data()
	if data is Dictionary:
		return data
	return {}
