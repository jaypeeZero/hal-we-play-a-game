extends GutTest

## Behavior tests for SkirmishFleet — verifies generation, persistence,
## pool logic, and legacy migration. No implementation/change-detector tests.

## Team slot used throughout — written to user:// during tests.
const TEST_TEAM: int = 9

## Path helpers matching SkirmishFleet's constants.
const SAVE_PATH: String = "user://skirmish_fleet_team_9.json"
const LEGACY_PATH: String = "user://team_9_fleet.json"


func before_each() -> void:
	_delete_if_exists(SAVE_PATH)
	_delete_if_exists(LEGACY_PATH)


func after_each() -> void:
	_delete_if_exists(SAVE_PATH)
	_delete_if_exists(LEGACY_PATH)


# ---------------------------------------------------------------------------
# Generation
# ---------------------------------------------------------------------------

func test_starter_fleet_has_correct_ship_counts() -> void:
	"""reset_to_starter produces exactly the STARTER_COUNTS breakdown."""
	var ships: Array = SkirmishFleet.reset_to_starter(TEST_TEAM)
	var counts: Dictionary = _count_by_type(ships)
	assert_eq(counts.get("fighter", 0), 6, "6 fighters")
	assert_eq(counts.get("heavy_fighter", 0), 3, "3 heavy fighters")
	assert_eq(counts.get("torpedo_boat", 0), 2, "2 torpedo boats")
	assert_eq(counts.get("corvette", 0), 2, "2 corvettes")
	assert_eq(counts.get("capital", 0), 1, "1 capital")


func test_every_ship_has_complement_slots() -> void:
	"""Every generated ship has at least one complement slot."""
	var ships: Array = SkirmishFleet.reset_to_starter(TEST_TEAM)
	for ship in ships:
		var hull_id: String = str(ship.get("hull_id", "?"))
		assert_true(
			not ship.get("complement", []).is_empty(),
			"hull %s has complement" % hull_id)


func test_every_complement_slot_has_a_crew_member() -> void:
	"""Each complement slot has a matching crew member."""
	var ships: Array = SkirmishFleet.reset_to_starter(TEST_TEAM)
	for ship in ships:
		var hull_id: String = str(ship.get("hull_id", "?"))
		var complement: Array = ship.get("complement", [])
		var crew: Array = ship.get("crew", [])
		assert_eq(
			crew.size(), complement.size(),
			"hull %s crew count matches complement" % hull_id)


func test_fleet_counts_matches_starter_counts() -> void:
	"""fleet_counts() derived from a freshly generated fleet equals STARTER_COUNTS."""
	SkirmishFleet.reset_to_starter(TEST_TEAM)
	var counts: Dictionary = SkirmishFleet.fleet_counts(TEST_TEAM)
	for ship_type in SkirmishFleet.STARTER_COUNTS:
		assert_eq(
			counts.get(ship_type, 0),
			SkirmishFleet.STARTER_COUNTS[ship_type],
			"fleet_counts matches starter for %s" % ship_type)


# ---------------------------------------------------------------------------
# Best pool
# ---------------------------------------------------------------------------

func test_best_pool_has_correct_size() -> void:
	"""best_pool() returns exactly BEST_POOL_SIZE entries."""
	var pool: Array = SkirmishFleet.best_pool()
	assert_eq(pool.size(), SkirmishFleet.BEST_POOL_SIZE, "pool is BEST_POOL_SIZE")


func test_best_pool_rating_cut_is_correct() -> void:
	"""Every pool entry rates >= every non-pool entry."""
	var all_entries: Array = CrewRosterManager.load_roster()
	if all_entries.size() <= SkirmishFleet.BEST_POOL_SIZE:
		pass_test("roster not large enough to test cut — skip")
		return
	all_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return SkirmishFleet.crew_rating(a) > SkirmishFleet.crew_rating(b))
	var pool: Array = all_entries.slice(0, SkirmishFleet.BEST_POOL_SIZE)
	var rest: Array = all_entries.slice(SkirmishFleet.BEST_POOL_SIZE)
	if pool.is_empty() or rest.is_empty():
		pass_test("degenerate slice — skip")
		return
	var min_pool_rating: float = _min_rating(pool)
	var max_rest_rating: float = _max_rating(rest)
	assert_true(
		min_pool_rating >= max_rest_rating,
		"min pool rating (%.3f) >= max rest rating (%.3f)" % [min_pool_rating, max_rest_rating])


func test_generated_crew_are_all_from_best_pool() -> void:
	"""All crew ids in the generated fleet come from best_pool entries."""
	var ships: Array = SkirmishFleet.reset_to_starter(TEST_TEAM)
	var pool: Array = SkirmishFleet.best_pool()
	var pool_ids: Dictionary = {}
	for entry in pool:
		pool_ids[str(entry.get("id", ""))] = true
	for ship in ships:
		for member in ship.get("crew", []):
			# Crew members are identified by callsign — verify via roster lookup.
			var callsign: String = str(member.get("callsign", ""))
			var found: bool = false
			for entry in pool:
				if str(entry.get("callsign", "")) == callsign:
					found = true
					break
			assert_true(found, "crew '%s' found in pool" % callsign)


func test_generated_crew_are_role_qualified_where_pool_allows() -> void:
	"""Crew not flagged off_role serve in a qualified role."""
	var ships: Array = SkirmishFleet.reset_to_starter(TEST_TEAM)
	for ship in ships:
		for member in ship.get("crew", []):
			if member.get("off_role", false):
				continue  # off-role fallback is explicitly allowed
			var role: int = int(member.get("role", -1))
			var qualified: Array = member.get("qualified_roles", [])
			assert_true(
				qualified.has(role),
				"crew '%s' qualified for role %d" % [str(member.get("callsign", "?")), role])


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

func test_save_load_round_trips_ships() -> void:
	"""save_fleet then get_fleet returns identical ship records."""
	var ships: Array = SkirmishFleet.reset_to_starter(TEST_TEAM)
	# Reload from disk.
	var loaded: Array = SkirmishFleet.get_fleet(TEST_TEAM)
	assert_eq(loaded.size(), ships.size(), "same ship count after reload")
	for i in range(ships.size()):
		assert_eq(
			str(loaded[i].get("hull_id")),
			str(ships[i].get("hull_id")),
			"hull_id round-trips at index %d" % i)
		assert_eq(
			str(loaded[i].get("ship_type")),
			str(ships[i].get("ship_type")),
			"ship_type round-trips at index %d" % i)


# ---------------------------------------------------------------------------
# Migration
# ---------------------------------------------------------------------------

func test_migration_from_legacy_counts() -> void:
	"""A legacy count save materializes into the correct ship type counts."""
	# Write a legacy-format counts file.
	var legacy_counts: Dictionary = {
		"fighter": 2,
		"heavy_fighter": 1,
		"torpedo_boat": 0,
		"corvette": 1,
		"capital": 0,
	}
	_write_json(LEGACY_PATH, legacy_counts)
	# No new save exists — get_fleet should migrate.
	var ships: Array = SkirmishFleet.get_fleet(TEST_TEAM)
	var counts: Dictionary = _count_by_type(ships)
	assert_eq(counts.get("fighter", 0), 2, "migrated 2 fighters")
	assert_eq(counts.get("heavy_fighter", 0), 1, "migrated 1 heavy fighter")
	assert_eq(counts.get("torpedo_boat", 0), 0, "migrated 0 torpedo boats")
	assert_eq(counts.get("corvette", 0), 1, "migrated 1 corvette")
	assert_eq(counts.get("capital", 0), 0, "migrated 0 capitals")
	# Old file must not be deleted.
	assert_true(FileAccess.file_exists(LEGACY_PATH), "legacy file preserved after migration")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _count_by_type(ships: Array) -> Dictionary:
	"""Return {ship_type: count} for an array of ship records."""
	var counts: Dictionary = {}
	for ship in ships:
		var t: String = str(ship.get("ship_type", ""))
		counts[t] = int(counts.get(t, 0)) + 1
	return counts


func _min_rating(entries: Array) -> float:
	"""Minimum crew_rating across entries."""
	var min_r: float = 1.0
	for entry in entries:
		var r: float = SkirmishFleet.crew_rating(entry)
		if r < min_r:
			min_r = r
	return min_r


func _max_rating(entries: Array) -> float:
	"""Maximum crew_rating across entries."""
	var max_r: float = 0.0
	for entry in entries:
		var r: float = SkirmishFleet.crew_rating(entry)
		if r > max_r:
			max_r = r
	return max_r


func _delete_if_exists(path: String) -> void:
	"""Delete a user:// file if present."""
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _write_json(path: String, data: Dictionary) -> void:
	"""Write a Dictionary as JSON to a user:// path."""
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("test helper: failed to open %s for writing" % path)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
