extends GutTest

## Off-role assignment penalty - FUNCTIONALITY ONLY. Crew serving in a role
## outside their qualifications operate at reduced performance in all areas:
## effective skill (and through it movement, weapon, captain, and repair
## modifiers), the raw aim read, reaction commit delays, and the derived
## reaction/decision times. Qualified assignments are never penalized, and
## the penalty composes with stress.

const SKILL := 0.8
const STRESS := 0.5
const FLOAT_TOLERANCE := 0.0001


func _entry(role_names: Array) -> Dictionary:
	var skills := {}
	for skill_name in CrewData.SKILL_NAMES:
		skills[skill_name] = SKILL
	return {"id": "off_role_test", "callsign": "Swap", "roles": role_names, "skills": skills}


## A crew member qualified for `role_names`, serving as `assigned`.
func _member(role_names: Array, assigned: int) -> Dictionary:
	var member := CrewData.assign_role(CrewData.from_roster_entry(_entry(role_names)), assigned)
	member.assigned_to = "ship_1"
	return member


# QUALIFICATION CHECKS

func test_on_role_assignment_is_not_off_role():
	assert_false(CrewData.is_off_role(_member(["pilot"], CrewData.Role.PILOT)),
		"Serving in a qualified role is on-role")
	assert_eq(CrewData.role_performance_multiplier(_member(["pilot"], CrewData.Role.PILOT)), 1.0,
		"...and earns full performance")


func test_off_role_assignment_is_flagged_and_penalized():
	var member := _member(["engineer"], CrewData.Role.PILOT)
	assert_true(CrewData.is_off_role(member), "Serving outside qualifications is off-role")
	assert_eq(CrewData.role_performance_multiplier(member),
		CrewData.OFF_ROLE_PERFORMANCE_MULTIPLIER, "...and earns the reduced multiplier")


# EFFECTIVE SKILL

func test_on_role_effective_skill_is_unmodified():
	var on := _member(["pilot"], CrewData.Role.PILOT)
	var unqualified_dict := on.duplicate(true)
	unqualified_dict.erase("qualified_roles")

	assert_almost_eq(CrewAISystem.calculate_effective_skill(on),
		CrewAISystem.calculate_effective_skill(unqualified_dict), FLOAT_TOLERANCE,
		"A qualified assignment reads the same effective skill as before qualifications existed")


func test_off_role_effective_skill_drops_by_the_penalty():
	var on := CrewAISystem.calculate_effective_skill(_member(["pilot"], CrewData.Role.PILOT))
	var off := CrewAISystem.calculate_effective_skill(_member(["engineer"], CrewData.Role.PILOT))

	assert_almost_eq(off, on * CrewData.OFF_ROLE_PERFORMANCE_MULTIPLIER, FLOAT_TOLERANCE,
		"Off-role effective skill is the on-role value times the penalty multiplier")


func test_off_role_engineer_repairs_worse():
	var on := CrewAISystem.calculate_effective_skill(_member(["engineer"], CrewData.Role.ENGINEER))
	var off := CrewAISystem.calculate_effective_skill(_member(["pilot"], CrewData.Role.ENGINEER))

	assert_lt(off, on,
		"The machinery read behind repair size degrades for an off-role engineer")


# SHIP MODIFIERS

func test_off_role_pilot_modifiers_are_worse():
	var on: Dictionary = CrewIntegrationSystem.apply_pilot_skill_modifiers(
		{}, _member(["pilot"], CrewData.Role.PILOT)).crew_modifiers
	var off: Dictionary = CrewIntegrationSystem.apply_pilot_skill_modifiers(
		{}, _member(["engineer"], CrewData.Role.PILOT)).crew_modifiers

	assert_lt(off.pilot_turn_factor, on.pilot_turn_factor, "Turn rate suffers off-role")
	assert_lt(off.pilot_accel_factor, on.pilot_accel_factor, "Acceleration suffers off-role")
	assert_lt(off.pilot_lateral_factor, on.pilot_lateral_factor, "Lateral thrust suffers off-role")
	assert_lt(off.aim_skill, on.aim_skill, "The pilot-as-gunner aim cone suffers off-role")


func test_off_role_gunner_modifiers_are_worse():
	var on: Dictionary = CrewIntegrationSystem.apply_gunner_skill_modifiers(
		{}, _member(["gunner"], CrewData.Role.GUNNER)).crew_modifiers
	var off: Dictionary = CrewIntegrationSystem.apply_gunner_skill_modifiers(
		{}, _member(["engineer"], CrewData.Role.GUNNER)).crew_modifiers

	assert_lt(off.aim_skill, on.aim_skill, "The spread cone suffers off-role")
	assert_lt(off.lead_accuracy, on.lead_accuracy, "Lead prediction suffers off-role")


func test_off_role_captain_modifiers_are_worse():
	var on: Dictionary = CrewIntegrationSystem.apply_captain_skill_modifiers(
		{}, _member(["captain"], CrewData.Role.CAPTAIN)).crew_modifiers
	var off: Dictionary = CrewIntegrationSystem.apply_captain_skill_modifiers(
		{}, _member(["pilot"], CrewData.Role.CAPTAIN)).crew_modifiers

	assert_lt(off.captain_coordination, on.captain_coordination, "Coordination suffers off-role")
	assert_lt(off.order_clarity, on.order_clarity, "Order clarity suffers off-role")


# DERIVED STATS AND DELAYS

func test_off_role_reaction_and_decision_times_are_slower_never_faster():
	var on := _member(["pilot"], CrewData.Role.PILOT)
	var off := _member(["engineer"], CrewData.Role.PILOT)

	assert_gt(off.stats.reaction_time, on.stats.reaction_time,
		"Off-role reaction time is slower (greater)")
	assert_gt(off.stats.decision_time, on.stats.decision_time,
		"Off-role decision time is slower (greater)")


func test_off_role_reaction_commit_delay_is_longer():
	var on := _member(["pilot"], CrewData.Role.PILOT)
	var off := _member(["engineer"], CrewData.Role.PILOT)

	assert_gt(CrewAISystem.calculate_reaction_delay(off, "piloting"),
		CrewAISystem.calculate_reaction_delay(on, "piloting"),
		"Off-role pilots commit to reactive maneuvers later")


# MULTI-ROLE AND COMPOSITION

func test_multi_role_crew_suffer_no_penalty_in_either_role():
	for role in [CrewData.Role.PILOT, CrewData.Role.ENGINEER]:
		var dual := _member(["pilot", "engineer"], role)
		var native := _member([CrewData.role_to_name(role)], role)

		assert_false(CrewData.is_off_role(dual),
			"A pilot+engineer is on-role as %s" % CrewData.get_role_name(role))
		assert_almost_eq(CrewAISystem.calculate_effective_skill(dual),
			CrewAISystem.calculate_effective_skill(native), FLOAT_TOLERANCE,
			"...with the same effective skill as a native %s" % CrewData.get_role_name(role))


func test_penalty_composes_with_stress():
	var off_calm := _member(["engineer"], CrewData.Role.PILOT)
	var off_stressed := _member(["engineer"], CrewData.Role.PILOT)
	off_stressed.stats.stress = STRESS
	var on_stressed := _member(["pilot"], CrewData.Role.PILOT)
	on_stressed.stats.stress = STRESS

	var both := CrewAISystem.calculate_effective_skill(off_stressed)
	assert_lt(both, CrewAISystem.calculate_effective_skill(off_calm),
		"Off-role and stressed is worse than off-role alone")
	assert_lt(both, CrewAISystem.calculate_effective_skill(on_stressed),
		"...and worse than stressed alone")
