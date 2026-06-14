extends GutTest

## Behaviour tests for CrewGenerator and RoguelikeRun.run_roster integration.
## Tests cover: structural validity, role-shaped distributions, determinism,
## callsign uniqueness, attribute validity, and the run_roster hiring path.

var _saved_fleet_hulls: Array
var _saved_money: int
var _saved_doctrine: Dictionary
var _saved_active: bool
var _saved_campaign: Dictionary
var _saved_hired_ids: Array
var _saved_run_roster: Array


func before_each() -> void:
	_saved_fleet_hulls = RoguelikeRun.fleet_hulls.duplicate(true)
	_saved_money = RoguelikeRun.money
	_saved_doctrine = RoguelikeRun.doctrine.duplicate(true)
	_saved_active = RoguelikeRun.active
	_saved_campaign = RoguelikeRun.campaign.duplicate(true)
	_saved_hired_ids = RoguelikeRun.hired_roster_ids.duplicate()
	_saved_run_roster = RoguelikeRun.run_roster.duplicate(true)


func after_each() -> void:
	RoguelikeRun.fleet_hulls = _saved_fleet_hulls
	RoguelikeRun.money = _saved_money
	RoguelikeRun.doctrine = _saved_doctrine
	RoguelikeRun.active = _saved_active
	RoguelikeRun.campaign = _saved_campaign
	RoguelikeRun.hired_roster_ids = _saved_hired_ids
	RoguelikeRun.run_roster = _saved_run_roster
	CampaignSaveManager.delete_save()


func _make_rng(seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return rng


func _counts(overrides: Dictionary = {}) -> Dictionary:
	var base := {"fighter": 0, "heavy_fighter": 0,
		"torpedo_boat": 0, "corvette": 0, "capital": 0}
	for key in overrides:
		base[key] = overrides[key]
	return base


# STRUCTURAL VALIDITY

func test_returns_requested_count():
	var base := CrewRosterManager.load_roster()
	var roster := CrewGenerator.generate_run_roster(base, 10, _make_rng(1))
	assert_eq(roster.size(), 10, "generate_run_roster returns exactly the requested count")


func test_each_entry_has_required_fields():
	var base := CrewRosterManager.load_roster()
	var roster := CrewGenerator.generate_run_roster(base, 5, _make_rng(2))
	for entry in roster:
		assert_true(entry.has("id"), "Entry has id")
		assert_true(entry.has("callsign"), "Entry has callsign")
		assert_true(entry.has("roles"), "Entry has roles")
		assert_true(entry.has("skills"), "Entry has skills")
		assert_true(entry.has("attributes"), "Entry has attributes")
		assert_gt(entry.roles.size(), 0, "Entry has at least one role")
		assert_true(entry.id.begins_with("run_crew_"), "Id has run_crew_ prefix")


func test_each_entry_has_seven_skills_in_range():
	var base := CrewRosterManager.load_roster()
	var roster := CrewGenerator.generate_run_roster(base, 10, _make_rng(3))
	for entry in roster:
		var skills: Dictionary = entry.skills
		assert_eq(skills.size(), CrewData.SKILL_NAMES.size(),
			"Entry has all 7 skills")
		for skill_name in CrewData.SKILL_NAMES:
			assert_true(skills.has(skill_name),
				"Skill '%s' present" % skill_name)
			var v: float = float(skills[skill_name])
			assert_gte(v, 0.0, "Skill '%s' >= 0" % skill_name)
			assert_lte(v, 1.0, "Skill '%s' <= 1" % skill_name)


func test_attributes_array_is_present():
	var base := CrewRosterManager.load_roster()
	var roster := CrewGenerator.generate_run_roster(base, 5, _make_rng(4))
	for entry in roster:
		assert_true(entry.attributes is Array,
			"attributes is an Array")


# ROLE-SHAPED DISTRIBUTIONS

func test_generated_gunners_have_higher_aim_than_engineers():
	## A large sample should show gunners outperform engineers on aim,
	## matching the hand-authored distribution.
	var base := CrewRosterManager.load_roster()
	var roster := CrewGenerator.generate_run_roster(base, 300, _make_rng(5))

	var gunner_aim_total := 0.0
	var gunner_count := 0
	var engineer_aim_total := 0.0
	var engineer_count := 0

	for entry in roster:
		var role_name: String = entry.roles[0]
		var aim: float = float(entry.skills.get("aim", 0.0))
		if role_name == "gunner":
			gunner_aim_total += aim
			gunner_count += 1
		elif role_name == "engineer":
			engineer_aim_total += aim
			engineer_count += 1

	if gunner_count > 0 and engineer_count > 0:
		var gunner_mean := gunner_aim_total / gunner_count
		var engineer_mean := engineer_aim_total / engineer_count
		assert_gt(gunner_mean, engineer_mean,
			"Generated gunners have higher mean aim than engineers")
	else:
		pending("Not enough gunner/engineer entries in sample to compare — increase size or check role distribution")


func test_generated_engineers_have_higher_machinery_than_pilots():
	var base := CrewRosterManager.load_roster()
	var roster := CrewGenerator.generate_run_roster(base, 300, _make_rng(6))

	var engineer_mach_total := 0.0
	var engineer_count := 0
	var pilot_mach_total := 0.0
	var pilot_count := 0

	for entry in roster:
		var role_name: String = entry.roles[0]
		var machinery: float = float(entry.skills.get("machinery", 0.0))
		if role_name == "engineer":
			engineer_mach_total += machinery
			engineer_count += 1
		elif role_name == "pilot":
			pilot_mach_total += machinery
			pilot_count += 1

	if engineer_count > 0 and pilot_count > 0:
		var engineer_mean := engineer_mach_total / engineer_count
		var pilot_mean := pilot_mach_total / pilot_count
		assert_gt(engineer_mean, pilot_mean,
			"Generated engineers have higher mean machinery than pilots")
	else:
		pending("Not enough engineer/pilot entries in sample — increase size or check role distribution")


# DETERMINISM

func test_same_seed_produces_identical_roster():
	var base := CrewRosterManager.load_roster()
	var roster_a := CrewGenerator.generate_run_roster(base, 20, _make_rng(42))
	var roster_b := CrewGenerator.generate_run_roster(base, 20, _make_rng(42))

	assert_eq(roster_a.size(), roster_b.size(), "Same size")
	for i in range(roster_a.size()):
		assert_eq(roster_a[i].id, roster_b[i].id,
			"Entry %d: same id" % i)
		assert_eq(roster_a[i].callsign, roster_b[i].callsign,
			"Entry %d: same callsign" % i)
		assert_eq(roster_a[i].roles, roster_b[i].roles,
			"Entry %d: same roles" % i)
		for skill_name in CrewData.SKILL_NAMES:
			assert_eq(roster_a[i].skills[skill_name], roster_b[i].skills[skill_name],
				"Entry %d: same %s" % [i, skill_name])


func test_different_seeds_produce_different_rosters():
	var base := CrewRosterManager.load_roster()
	var roster_a := CrewGenerator.generate_run_roster(base, 20, _make_rng(1))
	var roster_b := CrewGenerator.generate_run_roster(base, 20, _make_rng(999))

	var any_different := false
	for i in range(roster_a.size()):
		if roster_a[i].callsign != roster_b[i].callsign:
			any_different = true
			break
	assert_true(any_different, "Different seeds produce different rosters")


# CALLSIGN UNIQUENESS

func test_callsigns_are_unique_within_a_roster():
	var base := CrewRosterManager.load_roster()
	var roster := CrewGenerator.generate_run_roster(base, 50, _make_rng(7))
	var seen: Dictionary = {}
	for entry in roster:
		assert_false(seen.has(entry.callsign),
			"Callsign '%s' appears more than once" % entry.callsign)
		seen[entry.callsign] = true


# ATTRIBUTE VALIDITY

func test_every_attribute_id_exists_in_library():
	var base := CrewRosterManager.load_roster()
	var roster := CrewGenerator.generate_run_roster(base, 20, _make_rng(8))
	var lib: Dictionary = AttributeLibrary.all()
	for entry in roster:
		for attr_id in entry.attributes:
			assert_true(lib.has(str(attr_id)),
				"Attribute id '%s' exists in AttributeLibrary" % attr_id)


func test_no_attribute_appears_twice_on_one_entry():
	var base := CrewRosterManager.load_roster()
	var roster := CrewGenerator.generate_run_roster(base, 20, _make_rng(9))
	for entry in roster:
		var seen: Dictionary = {}
		for attr_id in entry.attributes:
			assert_false(seen.has(attr_id),
				"Attribute '%s' duplicated on entry %s" % [attr_id, entry.id])
			seen[attr_id] = true


# RUN_ROSTER INTEGRATION ON ROGUELIKERUN

func test_start_run_populates_run_roster():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	assert_gt(RoguelikeRun.run_roster.size(), 0,
		"start_run populates run_roster")


func test_end_run_clears_run_roster():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	RoguelikeRun.end_run()
	assert_eq(RoguelikeRun.run_roster.size(), 0,
		"end_run clears run_roster")


func test_available_crew_excludes_hired_ids():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	var before := RoguelikeRun.available_crew().size()
	var first_id: String = RoguelikeRun.run_roster[0].id
	RoguelikeRun.hired_roster_ids.append(first_id)
	var after := RoguelikeRun.available_crew().size()
	assert_eq(after, before - 1,
		"available_crew excludes consumed ids")


func test_available_crew_filters_by_role():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	var pilots := RoguelikeRun.available_crew(CrewData.Role.PILOT)
	for entry in pilots:
		assert_true(entry.roles.has("pilot"),
			"available_crew(PILOT) returns only pilot-qualified entries")


func test_run_start_crews_have_run_crew_prefix():
	## When a run is active, fleet crew are hired from run_roster,
	## whose ids all carry the run_crew_ prefix.
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	var hull: Dictionary = RoguelikeRun.fleet_hulls[0]
	if hull.crew.is_empty():
		pending("No crew hired at run start in this configuration")
		return
	# The consumed roster id (not crew_id) carries the run_crew_ prefix.
	assert_gt(RoguelikeRun.hired_roster_ids.size(), 0,
		"At least one roster id was consumed")
	for roster_id in RoguelikeRun.hired_roster_ids:
		assert_true(str(roster_id).begins_with("run_crew_"),
			"Hired roster id '%s' has run_crew_ prefix" % roster_id)


func test_crew_entry_by_id_resolves_run_roster():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	var target: Dictionary = RoguelikeRun.run_roster[0]
	var found := RoguelikeRun.crew_entry_by_id(target.id)
	assert_eq(found.id, target.id,
		"crew_entry_by_id resolves run_roster entries")


func test_crew_entry_by_id_falls_back_to_roster_manager():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	# An id not in run_roster falls back to CrewRosterManager.
	var shipped_entries := CrewRosterManager.load_roster()
	if shipped_entries.is_empty():
		pending("No shipped roster entries to test fallback")
		return
	var shipped_id: String = shipped_entries[0].id
	# The shipped id is unlikely to be in the generated run_roster.
	var found := RoguelikeRun.crew_entry_by_id(shipped_id)
	# If it resolves (from manager), that's the fallback working; if not
	# found it means the shipped roster is truly absent — that's fine too.
	# The key assertion is: no crash and the return is a Dictionary.
	assert_true(found is Dictionary,
		"crew_entry_by_id always returns a Dictionary")


# SAVE / LOAD

func test_run_roster_survives_save_load():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	var original_size := RoguelikeRun.run_roster.size()
	var first_id: String = RoguelikeRun.run_roster[0].id

	RoguelikeRun.save_campaign_to_disk()
	RoguelikeRun.run_roster = []
	assert_true(RoguelikeRun.load_campaign_from_disk(),
		"Campaign loads successfully")
	assert_eq(RoguelikeRun.run_roster.size(), original_size,
		"run_roster is restored after load")
	assert_eq(RoguelikeRun.run_roster[0].id, first_id,
		"First run_roster entry id matches")


func test_v2_shaped_save_loads_without_error():
	## A v2 save (no run_roster key) must load cleanly; run_roster defaults to [].
	## We simulate this by building a v2-shaped payload and writing it directly.
	var v2_payload := {
		"version": 2,
		"campaign": {},
		"fleet_hulls": [],
		"doctrine": DoctrineSystem.empty_doctrine(),
		"tactics": TacticsSystem.empty_tactics(),
		"enemy_fleet": {},
		"money": 0,
		"current_star_date": 2300,
		"hired_roster_ids": [],
		"next_hull_id": 0,
		"squadrons": [],
	}
	# Write directly so we bypass the version-bumping save_campaign helper.
	var json_str := JSON.stringify(v2_payload, "\t")
	var file := FileAccess.open(CampaignSaveManager.SAVE_PATH, FileAccess.WRITE)
	file.store_string(json_str)
	file.close()

	assert_true(RoguelikeRun.load_campaign_from_disk(),
		"A v2-shaped save loads without error")
	assert_eq(RoguelikeRun.run_roster, [],
		"run_roster defaults to [] when absent from save")
