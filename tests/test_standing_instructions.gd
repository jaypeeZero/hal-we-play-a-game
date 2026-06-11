extends GutTest

## Player standing instructions (plan 06, increment 2): a player-authored
## pattern saved per crew member is injected into their knowledge set with
## priority and measurably changes their behavior in battle.

const INSTRUCTION_ID := "charge_dont_flank"
const INSTRUCTION_MANEUVER := "fight_pursue_full_speed"
const FLANK_SITUATION := "fighter mid range flank behind position tactical"

var _crew_ids_to_cleanup: Array = []
var _saved_fleet: Dictionary
var _saved_fleet_ships: Array
var _saved_fleet_crew: Array


func before_each() -> void:
	_saved_fleet = RoguelikeRun.fleet.duplicate(true)
	_saved_fleet_ships = RoguelikeRun.fleet_ships.duplicate(true)
	_saved_fleet_crew = RoguelikeRun.fleet_crew.duplicate(true)


func after_each() -> void:
	RoguelikeRun.fleet = _saved_fleet
	RoguelikeRun.fleet_ships = _saved_fleet_ships
	RoguelikeRun.fleet_crew = _saved_fleet_crew
	for crew_id in _crew_ids_to_cleanup:
		var path = StandingInstructionsSystem.instruction_file_path(crew_id)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		TacticalKnowledgeSystem.knowledge_base.erase(
			StandingInstructionsSystem.registered_pattern_id(crew_id, INSTRUCTION_ID))
	TacticalKnowledgeSystem._query_cache.clear()
	_crew_ids_to_cleanup = []


func _make_pilot() -> Dictionary:
	var crew = CrewData.create_crew_member(CrewData.Role.PILOT, 1.0)
	_crew_ids_to_cleanup.append(crew.crew_id)
	return crew


## The player order used across tests: "never flank at mid range — charge".
func _charge_instruction() -> Dictionary:
	return {INSTRUCTION_ID: {
		"tags": ["fighter", "mid"],
		"text": "fighter mid range flank behind position tactical charge straight",
		"content": {
			"context": "Player order: never flank, charge straight in",
			"maneuvers": [INSTRUCTION_MANEUVER],
			"skill_requirements": {INSTRUCTION_MANEUVER: 0.0}
		}
	}}


func test_instructions_roundtrip_through_saved_file():
	var crew = _make_pilot()
	StandingInstructionsSystem.save_instructions(crew.crew_id, _charge_instruction())

	var loaded = StandingInstructionsSystem.load_instructions(crew.crew_id)

	assert_true(loaded.has(INSTRUCTION_ID), "Saved instruction should load back")
	assert_eq(loaded[INSTRUCTION_ID]["content"]["maneuvers"], [INSTRUCTION_MANEUVER],
		"Instruction content should survive the save/load roundtrip")


func test_crew_without_saved_file_is_unchanged():
	var crew = _make_pilot()
	var applied = StandingInstructionsSystem.load_and_apply(crew)
	assert_eq(applied.known_patterns, [],
		"A crew member with no instruction file keeps the role baseline (empty set)")


func test_relevant_instruction_outranks_role_doctrine():
	var crew = StandingInstructionsSystem.apply_instructions(_make_pilot(), _charge_instruction())

	var results = TacticalKnowledgeSystem.query_pilot_knowledge(FLANK_SITUATION, 3, crew.known_patterns)

	assert_gt(results.size(), 0, "Query should match patterns")
	assert_eq(results[0].pattern_id,
		StandingInstructionsSystem.registered_pattern_id(crew.crew_id, INSTRUCTION_ID),
		"A relevant standing instruction must rank above all role doctrine")


func test_irrelevant_instruction_stays_silent():
	var instruction = {INSTRUCTION_ID: {
		"tags": ["capital", "torpedo"],
		"text": "capital torpedo run approach",
		"content": {"maneuvers": [INSTRUCTION_MANEUVER]}
	}}
	var crew = StandingInstructionsSystem.apply_instructions(_make_pilot(), instruction)

	var results = TacticalKnowledgeSystem.query_pilot_knowledge(
		"fighter close range behind advantage dogfight", 5, crew.known_patterns)

	assert_gt(results.size(), 0, "Doctrine should still answer the situation")
	var registered = StandingInstructionsSystem.registered_pattern_id(crew.crew_id, INSTRUCTION_ID)
	for r in results:
		assert_ne(r.pattern_id, registered,
			"An instruction irrelevant to the situation must not be retrieved despite priority")


func test_instructions_extend_doctrine_rather_than_replace_it():
	var crew = StandingInstructionsSystem.apply_instructions(_make_pilot(), _charge_instruction())
	var registered = StandingInstructionsSystem.registered_pattern_id(crew.crew_id, INSTRUCTION_ID)

	var results = TacticalKnowledgeSystem.query_pilot_knowledge(
		"fighter close range behind advantage dogfight", 3, crew.known_patterns)

	var has_doctrine = false
	for r in results:
		if r.pattern_id != registered:
			has_doctrine = true
	assert_true(has_doctrine,
		"Applying an instruction to a baseline crew member must keep role doctrine retrievable")


func test_instructions_do_not_leak_to_other_crew():
	var crew = StandingInstructionsSystem.apply_instructions(_make_pilot(), _charge_instruction())
	var registered = StandingInstructionsSystem.registered_pattern_id(crew.crew_id, INSTRUCTION_ID)

	# A baseline crew member (empty known_patterns) queries the same situation
	var baseline_results = TacticalKnowledgeSystem.query_pilot_knowledge(FLANK_SITUATION, 5)

	for r in baseline_results:
		assert_ne(r.pattern_id, registered,
			"One crew member's standing instruction must never reach baseline crew")


func test_applying_instructions_twice_does_not_duplicate():
	var crew = StandingInstructionsSystem.apply_instructions(_make_pilot(), _charge_instruction())
	var size_after_first = crew.known_patterns.size()

	crew = StandingInstructionsSystem.apply_instructions(crew, _charge_instruction())

	assert_eq(crew.known_patterns.size(), size_after_first,
		"Re-applying across battles must not duplicate pattern ids")


func test_saved_crew_identity_persists_through_battle_transition():
	var crew = _make_pilot()
	crew.known_patterns = ["fighter_flank_mid"]
	crew.stats.stress = 0.8

	RoguelikeRun.update_fleet_after_battle([], [{"ship_type": "fighter", "crew": [crew]}])
	var saved = RoguelikeRun.take_saved_crew("fighter")

	assert_eq(saved.size(), 1, "Surviving crew should be saved into the run")
	var restored = CrewData.reset_for_battle(saved[0])
	assert_eq(restored.crew_id, crew.crew_id, "Crew identity must persist across battles")
	assert_eq(restored.known_patterns, ["fighter_flank_mid"], "Learned patterns must persist")
	assert_eq(restored.stats.skills.piloting, crew.stats.skills.piloting, "Skills must persist")
	assert_eq(restored.stats.stress, 0.0, "Stress recovers between battles")


func test_taking_saved_crew_consumes_the_group():
	var crew = _make_pilot()
	RoguelikeRun.update_fleet_after_battle([], [{"ship_type": "fighter", "crew": [crew]}])

	RoguelikeRun.take_saved_crew("fighter")

	assert_eq(RoguelikeRun.take_saved_crew("fighter"), [],
		"A saved crew group must be attached to only one hull")


func test_saved_crew_member_with_instruction_changes_battle_behavior():
	# BEHAVIOR (plan 06 increment-2 done-criterion): a saved roguelike crew
	# member carries a player-authored pattern that measurably changes their
	# behavior in battle.
	var crew = _make_pilot()
	var control = _make_pilot()  # identical pilot, no instructions

	# The player authors a standing instruction file for the saved crew member
	StandingInstructionsSystem.save_instructions(crew.crew_id, _charge_instruction())

	# The crew member survives a battle, is saved into the run, and is
	# restored for the next battle with their instructions applied — the
	# same path _create_crew_for_ship takes in a roguelike battle.
	RoguelikeRun.update_fleet_after_battle([], [{"ship_type": "fighter", "crew": [crew]}])
	var saved = RoguelikeRun.take_saved_crew("fighter")
	var restored = StandingInstructionsSystem.load_and_apply(CrewData.reset_for_battle(saved[0]))

	var instructed_maneuver = FighterPilotAI._query_fighter_knowledge(FLANK_SITUATION, restored)
	var baseline_maneuver = FighterPilotAI._query_fighter_knowledge(FLANK_SITUATION, control)

	assert_eq(instructed_maneuver, INSTRUCTION_MANEUVER,
		"The pilot must follow the player's standing instruction when it is relevant")
	assert_ne(instructed_maneuver, baseline_maneuver,
		"The instruction must measurably change behavior vs an identical uninstructed pilot")
