extends GutTest

## Tests for CrewRosterManager - FUNCTIONALITY ONLY. Loading the shipped
## roster, the user:// override lifecycle, per-entry validation/backfill,
## and the hiring-pool query. Asserts behaviors and invariants, never the
## shipped roster's specific values.

const LOW_BAND := 0.2
const HIGH_BAND := 0.8

var _saved_override: String = ""


func before_each() -> void:
	# Preserve any real user override so tests can't destroy player data.
	_saved_override = ""
	if FileAccess.file_exists(CrewRosterManager.USER_PATH):
		_saved_override = FileAccess.get_file_as_string(CrewRosterManager.USER_PATH)
	CrewRosterManager.reset_to_defaults()


func after_each() -> void:
	CrewRosterManager.reset_to_defaults()
	if _saved_override != "":
		var file := FileAccess.open(CrewRosterManager.USER_PATH, FileAccess.WRITE)
		file.store_string(_saved_override)
		file.close()


func _entry(id: String, role_names: Array = ["pilot"], skill: float = 0.5) -> Dictionary:
	var skills := {}
	for skill_name in CrewData.SKILL_NAMES:
		skills[skill_name] = skill
	return {"id": id, "callsign": id.capitalize(), "roles": role_names, "skills": skills}


# SHIPPED ROSTER

func test_shipped_roster_loads_valid_entries():
	var roster := CrewRosterManager.load_roster()

	assert_gt(roster.size(), 0, "The shipped roster has entries")
	var seen_ids := {}
	for entry in roster:
		assert_false(seen_ids.has(entry.id), "Entry ids are unique (%s)" % entry.id)
		seen_ids[entry.id] = true
		assert_gt(entry.roles.size(), 0, "Every entry has at least one role")
		for role_name in entry.roles:
			assert_true(CrewData.ROLE_NAMES.values().has(role_name),
				"Every role name is resolvable (%s)" % role_name)
		for skill_name in CrewData.SKILL_NAMES:
			assert_between(entry.skills[skill_name], 0.0, 1.0,
				"Skill '%s' is within 0..1" % skill_name)


func test_shipped_roster_spans_the_skill_range():
	var piloting: Array = CrewRosterManager.load_roster() \
		.filter(func(e): return e.roles.has("pilot")) \
		.map(func(e): return e.skills.piloting)

	assert_lt(piloting.min(), LOW_BAND, "The roster includes rookie pilots")
	assert_gt(piloting.max(), HIGH_BAND, "The roster includes ace pilots")


func test_shipped_roster_covers_every_role():
	var roster := CrewRosterManager.load_roster()
	for role in CrewData.ROLE_NAMES:
		var role_name: String = CrewData.ROLE_NAMES[role]
		assert_gt(roster.filter(func(e): return e.roles.has(role_name)).size(), 0,
			"The roster ships candidates for role '%s'" % role_name)


# OVERRIDE LIFECYCLE

func test_saved_override_wins_over_the_shipped_roster():
	assert_true(CrewRosterManager.save_roster([_entry("custom_1", ["gunner"])]),
		"Saving an override succeeds")
	assert_true(CrewRosterManager.has_user_override(), "The override file exists")

	var roster := CrewRosterManager.load_roster()
	assert_eq(roster.size(), 1, "The override replaces the shipped roster wholesale")
	assert_eq(roster[0].id, "custom_1", "...with the saved entries")


func test_reset_restores_the_shipped_roster():
	var shipped_size := CrewRosterManager.load_roster().size()
	CrewRosterManager.save_roster([_entry("custom_1")])

	CrewRosterManager.reset_to_defaults()

	assert_false(CrewRosterManager.has_user_override(), "Reset removes the override file")
	assert_eq(CrewRosterManager.load_roster().size(), shipped_size,
		"The shipped roster applies again")


# VALIDATION / BACKFILL

func test_entries_without_an_id_are_dropped():
	var bad := _entry("keeper")
	var no_id := _entry("loser")
	no_id.erase("id")
	CrewRosterManager.save_roster([bad, no_id, "garbage", 42])

	var roster := CrewRosterManager.load_roster()
	assert_eq(roster.size(), 1, "Only the repairable entry survives")
	assert_eq(roster[0].id, "keeper", "Entries without ids and non-dict junk are dropped")


func test_duplicate_ids_keep_the_first_entry():
	var first := _entry("twin", ["pilot"])
	var second := _entry("twin", ["gunner"])
	CrewRosterManager.save_roster([first, second])

	var roster := CrewRosterManager.load_roster()
	assert_eq(roster.size(), 1, "Duplicate ids collapse to one entry")
	assert_eq(roster[0].roles, ["pilot"], "The first occurrence wins")


func test_malformed_fields_are_backfilled_not_fatal():
	var broken := {"id": "fixme", "roles": ["janitor"], "skills": {"aim": 7.0}}
	CrewRosterManager.save_roster([broken])

	var roster := CrewRosterManager.load_roster()
	var entry: Dictionary = roster[0]
	assert_eq(entry.roles, ["pilot"], "Unknown role names backfill to pilot")
	assert_ne(entry.callsign, "", "A missing callsign is backfilled")
	assert_eq(entry.skills.aim, 1.0, "Out-of-range skills clamp into 0..1")
	for skill_name in CrewData.SKILL_NAMES:
		assert_between(entry.skills[skill_name], 0.0, 1.0,
			"Missing skill '%s' is backfilled" % skill_name)


func test_an_override_with_zero_valid_entries_falls_back_to_shipped():
	var shipped_size := CrewRosterManager.load_roster().size()
	CrewRosterManager.save_roster(["junk", {"role": "pilot"}])

	assert_eq(CrewRosterManager.load_roster().size(), shipped_size,
		"An unusable override never leaves the game without crew")


# HIRING POOL

func test_available_entries_excludes_hired_ids():
	CrewRosterManager.save_roster([_entry("a", ["pilot"]), _entry("b", ["pilot"])])

	var pool := CrewRosterManager.available_entries(["a"])

	assert_eq(pool.size(), 1, "Hired entries leave the pool")
	assert_eq(pool[0].id, "b", "Unhired entries remain")


func test_available_entries_filters_by_role():
	CrewRosterManager.save_roster([_entry("p", ["pilot"]), _entry("g", ["gunner"])])

	var gunners := CrewRosterManager.available_entries([], CrewData.Role.GUNNER)

	assert_eq(gunners.size(), 1, "Role filtering keeps only matching entries")
	assert_eq(gunners[0].id, "g", "...the gunner")
	assert_eq(CrewRosterManager.available_entries([]).size(), 2,
		"No role filter returns the whole pool")


func test_multi_role_candidates_appear_in_each_qualified_pool():
	CrewRosterManager.save_roster([_entry("dual", ["pilot", "engineer"])])

	assert_eq(CrewRosterManager.available_entries([], CrewData.Role.PILOT).size(), 1,
		"A pilot+engineer qualifies for the pilot pool")
	assert_eq(CrewRosterManager.available_entries([], CrewData.Role.ENGINEER).size(), 1,
		"...and the engineer pool")
	assert_eq(CrewRosterManager.available_entries([], CrewData.Role.GUNNER).size(), 0,
		"...but not for pools they hold no qualification for")


func test_an_entry_without_roles_backfills_to_pilot():
	var no_roles := _entry("rookie")
	no_roles.erase("roles")
	CrewRosterManager.save_roster([no_roles])

	assert_eq(CrewRosterManager.load_roster()[0].roles, ["pilot"],
		"A missing roles array backfills to the pilot qualification")


func test_entry_by_id_finds_entries_and_misses_cleanly():
	CrewRosterManager.save_roster([_entry("findme", ["engineer"])])

	assert_eq(CrewRosterManager.entry_by_id("findme").roles, ["engineer"],
		"A present id resolves to its entry")
	assert_true(CrewRosterManager.entry_by_id("ghost").is_empty(),
		"An absent id returns an empty dict, not an error")
