extends GutTest

## Tests for the roster hiring pool on RoguelikeRun - FUNCTIONALITY ONLY.
## Run-start crews drawn from the pool, consumption semantics (no double
## hires, exhaustion leaves vacancies), and campaign-save persistence of
## the consumed ids.

var _saved_fleet_hulls: Array
var _saved_money: int
var _saved_doctrine: Dictionary
var _saved_active: bool
var _saved_campaign: Dictionary
var _saved_hired_ids: Array
var _saved_override: String = ""


func before_each() -> void:
	_saved_fleet_hulls = RoguelikeRun.fleet_hulls.duplicate(true)
	_saved_money = RoguelikeRun.money
	_saved_doctrine = RoguelikeRun.doctrine.duplicate(true)
	_saved_active = RoguelikeRun.active
	_saved_campaign = RoguelikeRun.campaign.duplicate(true)
	_saved_hired_ids = RoguelikeRun.hired_roster_ids.duplicate()
	# Preserve any real user roster override; exhaustion tests install their own.
	_saved_override = ""
	if FileAccess.file_exists(CrewRosterManager.USER_PATH):
		_saved_override = FileAccess.get_file_as_string(CrewRosterManager.USER_PATH)
	CrewRosterManager.reset_to_defaults()


func after_each() -> void:
	RoguelikeRun.fleet_hulls = _saved_fleet_hulls
	RoguelikeRun.money = _saved_money
	RoguelikeRun.doctrine = _saved_doctrine
	RoguelikeRun.active = _saved_active
	RoguelikeRun.campaign = _saved_campaign
	RoguelikeRun.hired_roster_ids = _saved_hired_ids
	CrewRosterManager.reset_to_defaults()
	if _saved_override != "":
		var file := FileAccess.open(CrewRosterManager.USER_PATH, FileAccess.WRITE)
		file.store_string(_saved_override)
		file.close()


func _counts(overrides: Dictionary = {}) -> Dictionary:
	var base := {"fighter": 0, "heavy_fighter": 0,
		"torpedo_boat": 0, "corvette": 0, "capital": 0}
	for key in overrides:
		base[key] = overrides[key]
	return base


func _entry(id: String, role_names: Array, skill: float = 0.5) -> Dictionary:
	var skills := {}
	for skill_name in CrewData.SKILL_NAMES:
		skills[skill_name] = skill
	return {"id": id, "callsign": id.capitalize(), "roles": role_names, "skills": skills}


func _entry_by_id(roster_id: String) -> Dictionary:
	return RoguelikeRun.crew_entry_by_id(roster_id)


# RUN-START CREWS COME FROM THE POOL

func test_run_start_crews_are_drawn_from_the_roster_pool():
	RoguelikeRun.start_run(_counts({"fighter": 1}))

	assert_gt(RoguelikeRun.hired_roster_ids.size(), 0,
		"Starting a run consumes roster entries")
	var pilot: Dictionary = RoguelikeRun.fleet_hulls[0].crew[0]
	var consumed := _entry_by_id(RoguelikeRun.hired_roster_ids[0])
	assert_eq(pilot.callsign, consumed.callsign,
		"The starting pilot carries the consumed entry's identity")
	assert_eq(pilot.stats.skills.piloting, consumed.skills.piloting,
		"...and its skills")


func test_starting_a_new_run_resets_the_pool():
	RoguelikeRun.start_run(_counts({"fighter": 2}))
	var first_run_consumed := RoguelikeRun.hired_roster_ids.size()

	RoguelikeRun.start_run(_counts({"fighter": 2}))

	assert_eq(RoguelikeRun.hired_roster_ids.size(), first_run_consumed,
		"A new run starts from a full pool instead of accumulating consumption")


func test_pool_exhaustion_leaves_vacancies_instead_of_crashing():
	# When the run_roster holds only one pilot-qualified entry, two fighters
	# cannot both be fully crewed — the second stays vacant rather than crashing.
	RoguelikeRun.start_run(_counts())  # Empty fleet: initializes run_roster.
	RoguelikeRun.run_roster = [_entry("only_pilot", ["pilot"])]
	RoguelikeRun.hired_roster_ids = []
	RoguelikeRun.reconcile_roster_to_counts(_counts({"fighter": 2}))

	var crewed := 0
	for hull in RoguelikeRun.fleet_hulls:
		crewed += hull.crew.size()
	assert_eq(crewed, 1, "Only as many crew as the pool holds are fielded")
	assert_eq(RoguelikeRun.benched_hulls().size(), 1,
		"The uncrewed hull is benched with an open vacancy, not broken")


func test_exhausted_squad_slots_leave_no_dangling_command_links():
	# When the run_roster holds only a captain, a corvette's pilot/gunner/
	# engineer slots all stay vacant, and the captain must not command ghosts.
	RoguelikeRun.start_run(_counts())  # Empty fleet: initializes run_roster.
	RoguelikeRun.run_roster = [_entry("solo_captain", ["captain"])]
	RoguelikeRun.hired_roster_ids = []
	RoguelikeRun.reconcile_roster_to_counts(_counts({"corvette": 1}))

	var crew: Array = RoguelikeRun.fleet_hulls[0].crew
	assert_eq(crew.size(), 1, "Only the captain boards")
	assert_eq(crew[0].command_chain.subordinates, [],
		"No command links point at crew who never boarded")


# HIRING CONSUMES THE POOL

func test_hiring_the_same_candidate_twice_fails():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	RoguelikeRun.money = 100000
	var hull_a := RoguelikeRun.add_purchased_hull("fighter")
	var hull_b := RoguelikeRun.add_purchased_hull("fighter")
	var slot_a: Dictionary = RoguelikeRun.hull_vacancies(hull_a)[0]
	var slot_b: Dictionary = RoguelikeRun.hull_vacancies(hull_b)[0]
	var candidate: String = RoguelikeRun.available_crew(CrewData.Role.PILOT)[0].id

	assert_true(RoguelikeRun.fill_vacancy(hull_a.hull_id, slot_a, candidate),
		"The first hire succeeds")
	assert_false(RoguelikeRun.fill_vacancy(hull_b.hull_id, slot_b, candidate),
		"The same candidate cannot be hired twice in one run")
	assert_true(hull_b.crew.is_empty(), "The second hull stays uncrewed")


func test_hiring_an_unknown_candidate_fails():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	RoguelikeRun.money = 100000
	var hull := RoguelikeRun.add_purchased_hull("fighter")
	var slot: Dictionary = RoguelikeRun.hull_vacancies(hull)[0]

	assert_false(RoguelikeRun.fill_vacancy(hull.hull_id, slot, "no_such_entry"),
		"An id missing from the roster (e.g. removed by an override edit) is rejected")


func test_hiring_an_off_role_candidate_assigns_the_slot_role():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	RoguelikeRun.money = 100000
	var hull := RoguelikeRun.add_purchased_hull("fighter")
	var pilot_slot: Dictionary = RoguelikeRun.hull_vacancies(hull)[0]
	var engineer: Dictionary = RoguelikeRun.available_crew(CrewData.Role.ENGINEER)[0]

	assert_true(RoguelikeRun.fill_vacancy(hull.hull_id, pilot_slot, engineer.id),
		"Qualification is a soft penalty, not a hiring gate")
	var member: Dictionary = hull.crew[0]
	assert_eq(member.role, int(pilot_slot.get("role", -1)),
		"The hire serves in the slot's role, not their own")
	assert_eq(member.qualified_roles, CrewData.qualified_roles_from_entry(engineer),
		"Their qualifications come along unchanged")


func test_hired_crew_carry_the_candidate_entry_skills():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	RoguelikeRun.money = 100000
	var hull := RoguelikeRun.add_purchased_hull("fighter")
	var slot: Dictionary = RoguelikeRun.hull_vacancies(hull)[0]
	var candidate: Dictionary = RoguelikeRun.available_crew(CrewData.Role.PILOT)[0]

	RoguelikeRun.fill_vacancy(hull.hull_id, slot, candidate.id)

	var member: Dictionary = hull.crew[0]
	assert_eq(member.callsign, candidate.callsign, "The hire is the chosen candidate")
	for skill_name in CrewData.SKILL_NAMES:
		assert_eq(member.stats.skills[skill_name], candidate.skills[skill_name],
			"Skill '%s' comes from the candidate's entry" % skill_name)


# PERSISTENCE

func test_consumed_pool_survives_a_campaign_save_round_trip():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	var consumed := RoguelikeRun.hired_roster_ids.duplicate()
	assert_gt(consumed.size(), 0, "precondition: the run consumed entries")

	RoguelikeRun.save_campaign_to_disk()
	RoguelikeRun.hired_roster_ids = []
	assert_true(RoguelikeRun.load_campaign_from_disk(), "A saved campaign reloads")

	assert_eq(RoguelikeRun.hired_roster_ids, consumed,
		"Consumed roster ids persist across a campaign save/load")
	CampaignSaveManager.delete_save()
