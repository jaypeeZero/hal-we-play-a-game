extends GutTest

## Fleet doctrine (plan 06, increment 2b): template-authored standing
## instructions assigned at fleet / class / individual scope, compiled
## into each crew member's known_patterns at battle spawn.

const CHARGE := "charge_head_on"
const CHARGE_MANEUVER := "fight_pursue_full_speed"
const KEEP_CLEAR := "keep_clear_of"
const GUNNER_TEMPLATE := "finish_damaged_targets"
const FLANK_SITUATION := "fighter mid range flank behind position tactical"

var _saved_run_state: Dictionary


func before_each() -> void:
	_saved_run_state = {
		"active": RoguelikeRun.active,
		"fleet": RoguelikeRun.fleet.duplicate(true),
		"fleet_ships": RoguelikeRun.fleet_ships.duplicate(true),
		"fleet_crew": RoguelikeRun.fleet_crew.duplicate(true),
		"doctrine": RoguelikeRun.doctrine.duplicate(true),
		"enemy_fleet": RoguelikeRun.enemy_fleet.duplicate(true),
	}


func after_each() -> void:
	RoguelikeRun.active = _saved_run_state.active
	RoguelikeRun.fleet = _saved_run_state.fleet
	RoguelikeRun.fleet_ships = _saved_run_state.fleet_ships
	RoguelikeRun.fleet_crew = _saved_run_state.fleet_crew
	RoguelikeRun.doctrine = _saved_run_state.doctrine
	RoguelikeRun.enemy_fleet = _saved_run_state.enemy_fleet
	# Unregister doctrine patterns compiled during the test
	for pattern_id in TacticalKnowledgeSystem.knowledge_base.keys():
		if str(pattern_id).begins_with(DoctrineSystem.DOCTRINE_PATTERN_PREFIX):
			TacticalKnowledgeSystem.knowledge_base.erase(pattern_id)
	TacticalKnowledgeSystem._query_cache.clear()


func _make_pilot() -> Dictionary:
	return CrewData.create_crew_member(CrewData.Role.PILOT, 1.0)


func _fleet_doctrine_with(template_id: String, params: Dictionary = {}) -> Dictionary:
	var doctrine = DoctrineSystem.empty_doctrine()
	DoctrineSystem.set_instruction_in_place(doctrine, DoctrineSystem.SCOPE_FLEET, "", template_id, params)
	return doctrine


func _doctrine_ids(crew: Dictionary) -> Array:
	var ids: Array = []
	for pattern_id in crew.known_patterns:
		if str(pattern_id).begins_with(DoctrineSystem.DOCTRINE_PATTERN_PREFIX):
			ids.append(pattern_id)
	return ids


# ============================================================================
# TEMPLATE CATALOG
# ============================================================================

func test_template_params_substitute_into_pattern():
	var pattern = DoctrineSystem.instantiate_template(KEEP_CLEAR, {"target_class": "corvette"})

	assert_true("corvette" in pattern.tags, "Param value should substitute into tags")
	assert_true("corvette" in pattern.text, "Param value should substitute into text")
	assert_true("corvette" in pattern.content.context, "Param value should substitute into content")
	assert_false("{target_class}" in pattern.text, "No raw placeholders should remain")


func test_template_params_fall_back_to_defaults():
	var pattern = DoctrineSystem.instantiate_template(KEEP_CLEAR)
	assert_false("{target_class}" in pattern.text,
		"Instantiating without params should use the template defaults")


# ============================================================================
# SCOPES
# ============================================================================

func test_fleet_scope_reaches_all_crew_of_matching_role():
	var doctrine = _fleet_doctrine_with(CHARGE)
	var pilot_a = DoctrineSystem.compile_for_crew(_make_pilot(), "fighter", doctrine)
	var pilot_b = DoctrineSystem.compile_for_crew(_make_pilot(), "corvette", doctrine)

	assert_eq(_doctrine_ids(pilot_a).size(), 1, "Fleet doctrine should reach a fighter pilot")
	assert_eq(_doctrine_ids(pilot_b).size(), 1, "Fleet doctrine should reach a corvette pilot")


func test_instructions_only_reach_their_role():
	var doctrine = _fleet_doctrine_with(CHARGE)
	DoctrineSystem.set_instruction_in_place(doctrine, DoctrineSystem.SCOPE_FLEET, "", GUNNER_TEMPLATE)

	var pilot = DoctrineSystem.compile_for_crew(_make_pilot(), "fighter", doctrine)
	var gunner = DoctrineSystem.compile_for_crew(
		CrewData.create_crew_member(CrewData.Role.GUNNER, 1.0), "corvette", doctrine)

	assert_eq(_doctrine_ids(pilot).size(), 1, "Pilot gets only the pilot instruction")
	assert_eq(_doctrine_ids(gunner).size(), 1, "Gunner gets only the gunner instruction")
	assert_ne(_doctrine_ids(pilot)[0], _doctrine_ids(gunner)[0],
		"Each crew member compiles their own namespaced pattern")


func test_class_scope_only_reaches_that_ship_class():
	var doctrine = DoctrineSystem.empty_doctrine()
	DoctrineSystem.set_instruction_in_place(doctrine, DoctrineSystem.SCOPE_CLASS, "fighter", CHARGE)

	var fighter_pilot = DoctrineSystem.compile_for_crew(_make_pilot(), "fighter", doctrine)
	var boat_pilot = DoctrineSystem.compile_for_crew(_make_pilot(), "torpedo_boat", doctrine)

	assert_eq(_doctrine_ids(fighter_pilot).size(), 1, "Class doctrine reaches its class")
	assert_eq(_doctrine_ids(boat_pilot).size(), 0, "Class doctrine must not reach other classes")


func test_crew_scope_only_reaches_that_crew_member():
	var target = _make_pilot()
	var other = _make_pilot()
	var doctrine = DoctrineSystem.empty_doctrine()
	DoctrineSystem.set_instruction_in_place(doctrine, DoctrineSystem.SCOPE_CREW, target.crew_id, CHARGE)

	target = DoctrineSystem.compile_for_crew(target, "fighter", doctrine)
	other = DoctrineSystem.compile_for_crew(other, "fighter", doctrine)

	assert_eq(_doctrine_ids(target).size(), 1, "Personal order reaches its crew member")
	assert_eq(_doctrine_ids(other).size(), 0, "Personal order must not reach anyone else")


func test_more_specific_scope_overrides_same_template():
	var pilot = _make_pilot()
	var doctrine = _fleet_doctrine_with(KEEP_CLEAR, {"target_class": "capital"})
	DoctrineSystem.set_instruction_in_place(
		doctrine, DoctrineSystem.SCOPE_CREW, pilot.crew_id, KEEP_CLEAR, {"target_class": "corvette"})

	var entries = DoctrineSystem.effective_instructions(doctrine, pilot, "fighter")
	var fleet_entry = entries[0]
	assert_eq(fleet_entry.scope, DoctrineSystem.SCOPE_FLEET, "Fleet layer listed first")
	assert_true(fleet_entry.overridden, "The fleet instance must show as overridden")

	pilot = DoctrineSystem.compile_for_crew(pilot, "fighter", doctrine)
	assert_eq(_doctrine_ids(pilot).size(), 1, "Only one instance of a template compiles")
	var pattern = TacticalKnowledgeSystem.get_pattern(_doctrine_ids(pilot)[0])
	assert_true("corvette" in pattern.text, "The personal (most specific) params must win")


func test_individual_can_disable_inherited_instruction():
	var pilot_a = _make_pilot()
	var pilot_b = _make_pilot()
	var doctrine = _fleet_doctrine_with(CHARGE)
	DoctrineSystem.set_disabled_in_place(doctrine, pilot_a.crew_id, CHARGE, true)

	pilot_a = DoctrineSystem.compile_for_crew(pilot_a, "fighter", doctrine)
	pilot_b = DoctrineSystem.compile_for_crew(pilot_b, "fighter", doctrine)

	assert_eq(_doctrine_ids(pilot_a).size(), 0, "Disabled inherited order must not compile")
	assert_eq(_doctrine_ids(pilot_b).size(), 1, "Other crew keep the fleet order")

	DoctrineSystem.set_disabled_in_place(doctrine, pilot_a.crew_id, CHARGE, false)
	pilot_a = DoctrineSystem.compile_for_crew(pilot_a, "fighter", doctrine)
	assert_eq(_doctrine_ids(pilot_a).size(), 1, "Re-enabling restores the order")


# ============================================================================
# COMPILATION LIFECYCLE
# ============================================================================

func test_doctrine_extends_role_baseline_rather_than_replacing_it():
	var pilot = DoctrineSystem.compile_for_crew(_make_pilot(), "fighter", _fleet_doctrine_with(CHARGE))

	assert_gt(pilot.known_patterns.size(), 1,
		"Baseline doctrine must be expanded alongside the standing order")
	assert_true("fighter_flank_mid" in pilot.known_patterns,
		"Role baseline patterns stay retrievable after compiling doctrine")


func test_removed_instruction_does_not_linger_after_recompile():
	var doctrine = _fleet_doctrine_with(CHARGE)
	var pilot = DoctrineSystem.compile_for_crew(_make_pilot(), "fighter", doctrine)
	assert_eq(_doctrine_ids(pilot).size(), 1, "Instruction compiles initially")

	DoctrineSystem.remove_instruction_in_place(doctrine, DoctrineSystem.SCOPE_FLEET, "", CHARGE)
	pilot = DoctrineSystem.compile_for_crew(pilot, "fighter", doctrine)

	assert_eq(_doctrine_ids(pilot).size(), 0,
		"An instruction removed between battles must not linger in known_patterns")


func test_recompiling_is_idempotent():
	var doctrine = _fleet_doctrine_with(CHARGE)
	var pilot = DoctrineSystem.compile_for_crew(_make_pilot(), "fighter", doctrine)
	var first = pilot.known_patterns.duplicate()

	pilot = DoctrineSystem.compile_for_crew(pilot, "fighter", doctrine)

	assert_eq(pilot.known_patterns, first, "Compiling every battle must not grow the set")


func test_compiled_doctrine_does_not_leak_to_baseline_crew():
	var pilot = DoctrineSystem.compile_for_crew(_make_pilot(), "fighter", _fleet_doctrine_with(CHARGE))
	var registered = _doctrine_ids(pilot)[0]

	var baseline_results = TacticalKnowledgeSystem.query_pilot_knowledge(FLANK_SITUATION, 5)
	for r in baseline_results:
		assert_ne(r.pattern_id, registered,
			"Doctrine patterns must never reach crew outside the compile (e.g. enemies)")


# ============================================================================
# UI SUPPORT
# ============================================================================

func test_capability_gap_reflects_skill_requirements():
	var rookie = CrewData.create_crew_member(CrewData.Role.PILOT, 0.0)
	var ace = _make_pilot()
	var flank_pattern = DoctrineSystem.instantiate_template("flank_attack_runs")

	assert_gt(DoctrineSystem.primary_maneuver_skill_gap(rookie, flank_pattern), 0.0,
		"A rookie should show a skill gap for a gated maneuver")
	assert_eq(DoctrineSystem.primary_maneuver_skill_gap(ace, flank_pattern), 0.0,
		"An ace should show no gap")


func test_entries_map_to_crew_groups_in_type_order():
	var entries = [
		{"team": 0, "ship_type": "fighter"},
		{"team": 1, "ship_type": "fighter"},
		{"team": 0, "ship_type": "corvette"},
		{"team": 0, "ship_type": "fighter"},
	]
	var fleet_crew = [
		{"ship_type": "fighter", "crew": []},
		{"ship_type": "fighter", "crew": []},
		{"ship_type": "corvette", "crew": []},
	]

	var mapping = DoctrineSystem.map_entries_to_crew_groups(entries, fleet_crew)

	assert_eq(mapping[0], 0, "First fighter entry gets the first fighter group")
	assert_eq(mapping[3], 1, "Second fighter entry gets the second fighter group")
	assert_eq(mapping[2], 2, "Corvette entry gets the corvette group")
	assert_false(mapping.has(1), "Enemy entries are not mapped")


# ============================================================================
# DONE-CRITERION (plan 06 increment 2b)
# ============================================================================

func test_doctrine_measurably_changes_saved_crew_behavior_in_battle():
	# A roster crew member saved in the run, with a fleet standing order
	# authored between battles, picks a different maneuver than an
	# identical pilot without the order — through the same save/restore/
	# compile path the battle scene uses.
	var crew = _make_pilot()
	var control = _make_pilot()
	DoctrineSystem.set_instruction_in_place(
		RoguelikeRun.doctrine, DoctrineSystem.SCOPE_FLEET, "", CHARGE)

	RoguelikeRun.update_fleet_after_battle([], [{"ship_type": "fighter", "crew": [crew]}])
	var saved = RoguelikeRun.take_saved_crew("fighter")
	var restored = DoctrineSystem.compile_for_crew(
		CrewData.reset_for_battle(saved[0]), "fighter", RoguelikeRun.doctrine)

	var instructed_maneuver = FighterPilotAI._query_fighter_knowledge(FLANK_SITUATION, restored)
	var baseline_maneuver = FighterPilotAI._query_fighter_knowledge(FLANK_SITUATION, control)

	assert_eq(instructed_maneuver, CHARGE_MANEUVER,
		"The pilot must follow the standing order when it is relevant")
	assert_ne(instructed_maneuver, baseline_maneuver,
		"The order must measurably change behavior vs an identical uninstructed pilot")


func test_doctrine_authored_before_a_fleet_edit_still_compiles_for_retained_crew():
	# Author doctrine at Edit Fleet, then change the fleet (reconcile keeps
	# the first fighter group). The retained crew must still receive the
	# standing order when the battle compiles their doctrine.
	RoguelikeRun.start_run({"fighter": 2, "heavy_fighter": 0,
		"torpedo_boat": 0, "corvette": 0, "capital": 0})
	DoctrineSystem.set_instruction_in_place(
		RoguelikeRun.doctrine, DoctrineSystem.SCOPE_FLEET, "", CHARGE)

	RoguelikeRun.reconcile_roster_to_counts({"fighter": 1, "heavy_fighter": 0,
		"torpedo_boat": 0, "corvette": 0, "capital": 0})

	var retained = RoguelikeRun.fleet_crew[0].crew[0]
	var compiled = DoctrineSystem.compile_for_crew(
		CrewData.reset_for_battle(retained), "fighter", RoguelikeRun.doctrine)

	assert_gt(_doctrine_ids(compiled).size(), 0,
		"Doctrine authored before a fleet edit must reach the retained crew at battle spawn")
