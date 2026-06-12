extends GutTest

## Tests for CrewData's roster-entry support - FUNCTIONALITY ONLY.
## Role name round-trips, building battle-ready crew from roster entries,
## derived-stat recomputation, and the crew -> entry display adapter.

const HIGH_SKILL := 0.9
const LOW_SKILL := 0.1
const OUT_OF_RANGE_SKILL := 1.5


func _entry(role_names: Array = ["pilot"], skill: float = HIGH_SKILL, callsign: String = "Test Ace") -> Dictionary:
	var skills := {}
	for skill_name in CrewData.SKILL_NAMES:
		skills[skill_name] = skill
	return {"id": "roster_test", "callsign": callsign, "roles": role_names, "skills": skills}


# SKILL GROUPS

func test_skill_groups_partition_the_canonical_skill_list():
	var union: Array = CrewData.PHYSICAL_SKILLS + CrewData.MENTAL_SKILLS
	assert_eq(union.size(), CrewData.SKILL_NAMES.size(),
		"Physical + mental groups cover every skill exactly once")
	var seen := {}
	for skill_name in union:
		assert_false(seen.has(skill_name), "Skill '%s' appears in only one group" % skill_name)
		seen[skill_name] = true
		assert_true(CrewData.SKILL_NAMES.has(skill_name),
			"Group skill '%s' is a canonical skill" % skill_name)


func test_each_skill_group_occupies_contiguous_chart_axes():
	for group in [CrewData.PHYSICAL_SKILLS, CrewData.MENTAL_SKILLS]:
		var indices: Array = []
		for skill_name in group:
			indices.append(CrewData.SKILL_NAMES.find(skill_name))
		indices.sort()
		assert_eq(indices[indices.size() - 1] - indices[0], indices.size() - 1,
			"Group %s sits on contiguous radar axes, producing the chart clustering" % str(group))


# ROLE NAMES

func test_every_role_round_trips_through_its_name():
	for role in CrewData.ROLE_NAMES:
		var name: String = CrewData.role_to_name(role)
		assert_eq(CrewData.role_from_name(name), role,
			"Role '%s' survives a name round-trip" % name)


func test_unknown_role_name_defaults_to_pilot():
	assert_eq(CrewData.role_from_name("janitor"), CrewData.Role.PILOT,
		"An unrecognized role name backfills to pilot instead of erroring")


# FROM ROSTER ENTRY

func test_roster_entry_becomes_a_battle_ready_crew_dict():
	var member := CrewData.from_roster_entry(_entry(["gunner"]))

	assert_eq(member.role, CrewData.Role.GUNNER, "The entry's role is applied")
	assert_eq(member.callsign, "Test Ace", "The entry's callsign is applied")
	assert_true(member.has("awareness"), "Awareness scaffolding is present")
	assert_true(member.has("orders"), "Orders scaffolding is present")
	assert_true(member.has("command_chain"), "Command chain scaffolding is present")
	assert_eq(member.stats.stress, 0.0, "Stress starts fresh")
	assert_eq(member.stats.fatigue, 0.0, "Fatigue starts fresh")


func test_roster_entry_skills_are_applied_and_clamped():
	var entry := _entry(["pilot"], OUT_OF_RANGE_SKILL)
	var member := CrewData.from_roster_entry(entry)

	for skill_name in CrewData.SKILL_NAMES:
		assert_between(member.stats.skills[skill_name], 0.0, 1.0,
			"Skill '%s' is clamped into 0..1" % skill_name)

	var low := CrewData.from_roster_entry(_entry(["pilot"], LOW_SKILL))
	assert_eq(low.stats.skills.piloting, LOW_SKILL, "In-range skills carry over exactly")


func test_higher_skill_entry_reacts_and_decides_faster():
	var ace := CrewData.from_roster_entry(_entry(["pilot"], HIGH_SKILL))
	var rookie := CrewData.from_roster_entry(_entry(["pilot"], LOW_SKILL))

	assert_lt(ace.stats.reaction_time, rookie.stats.reaction_time,
		"Higher skills mean faster reactions")
	assert_lt(ace.stats.decision_time, rookie.stats.decision_time,
		"Higher skills mean faster decisions")


func test_derived_stats_respond_to_role():
	var pilot := CrewData.from_roster_entry(_entry(["pilot"], HIGH_SKILL))
	var commander := CrewData.from_roster_entry(_entry(["fleet_commander"], HIGH_SKILL))

	assert_lt(pilot.stats.decision_time, commander.stats.decision_time,
		"At equal skills a pilot decides faster than a fleet commander")
	assert_gt(commander.stats.awareness_range, pilot.stats.awareness_range,
		"A fleet commander has the wider awareness range")


func test_missing_skills_backfill_to_canonical_defaults():
	var member := CrewData.from_roster_entry(
		{"id": "roster_partial", "callsign": "Partial", "roles": ["pilot"], "skills": {}})

	for skill_name in CrewData.SKILL_NAMES:
		assert_between(member.stats.skills[skill_name], 0.0, 1.0,
			"Missing skill '%s' is backfilled with a valid value" % skill_name)


# RECOMPUTE DERIVED STATS

func test_recompute_tracks_skill_edits():
	var member := CrewData.from_roster_entry(_entry(["pilot"], LOW_SKILL))
	var before: float = member.stats.reaction_time

	for skill_name in CrewData.SKILL_NAMES:
		member.stats.skills[skill_name] = HIGH_SKILL
	var recomputed := CrewData.recompute_derived_stats(member.stats, member.role)

	assert_lt(recomputed.reaction_time, before,
		"Raising skills then recomputing lowers reaction time")
	assert_eq(member.stats.reaction_time, before,
		"recompute_derived_stats is pure - the input stats are untouched")


func test_aggression_does_not_drive_derived_stats():
	var calm := _entry(["pilot"], HIGH_SKILL)
	calm.skills[CrewData.PERSONALITY_SKILL] = 0.0
	var furious := _entry(["pilot"], HIGH_SKILL)
	furious.skills[CrewData.PERSONALITY_SKILL] = 1.0

	assert_eq(CrewData.from_roster_entry(calm).stats.reaction_time,
		CrewData.from_roster_entry(furious).stats.reaction_time,
		"Aggression is personality - it never changes reaction time")


# ENTRY FROM CREW (display adapter)

func test_crew_dict_adapts_back_to_the_entry_shape():
	var member := CrewData.from_roster_entry(_entry(["engineer"], HIGH_SKILL, "Wrench"))
	var entry := CrewData.entry_from_crew(member)

	assert_eq(entry.callsign, "Wrench", "Callsign survives the adaptation")
	assert_eq(entry.roles, ["engineer"], "Roles map back to their stable names")
	assert_eq(entry.id, member.crew_id, "The crew id becomes the entry id")
	for skill_name in CrewData.SKILL_NAMES:
		assert_eq(entry.skills[skill_name], member.stats.skills[skill_name],
			"Skill '%s' carries over unchanged" % skill_name)


# MULTI-ROLE QUALIFICATION

func test_multi_role_entry_round_trips_both_qualifications():
	var member := CrewData.from_roster_entry(_entry(["pilot", "engineer"]))
	var entry := CrewData.entry_from_crew(member)

	assert_eq(entry.roles, ["pilot", "engineer"],
		"Both qualifications survive the entry -> crew -> entry round-trip")


func test_is_qualified_for_matches_the_listed_roles_only():
	var member := CrewData.from_roster_entry(_entry(["pilot", "engineer"]))

	assert_true(CrewData.is_qualified_for(member, CrewData.Role.PILOT),
		"Qualified for each listed role")
	assert_true(CrewData.is_qualified_for(member, CrewData.Role.ENGINEER),
		"Qualified for each listed role")
	assert_false(CrewData.is_qualified_for(member, CrewData.Role.GUNNER),
		"Not qualified for an unlisted role")


func test_multi_role_entry_assigns_the_first_role():
	var member := CrewData.from_roster_entry(_entry(["engineer", "pilot"]))

	assert_eq(member.role, CrewData.Role.ENGINEER,
		"The first listed role is the assigned role")


func test_reset_for_battle_preserves_qualified_roles():
	var member := CrewData.from_roster_entry(_entry(["pilot", "gunner"]))

	var fresh := CrewData.reset_for_battle(member)

	assert_eq(fresh.qualified_roles, member.qualified_roles,
		"Qualifications are persistent identity and survive between battles")


func test_assign_role_changes_the_assigned_role_and_keeps_qualifications():
	var member := CrewData.from_roster_entry(_entry(["pilot"]))

	CrewData.assign_role(member, CrewData.Role.ENGINEER)

	assert_eq(member.role, CrewData.Role.ENGINEER, "The assigned role changes")
	assert_true(CrewData.is_qualified_for(member, CrewData.Role.PILOT),
		"Assignment never rewrites qualifications")
