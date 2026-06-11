extends GutTest

## Tests for EngineerAI - FUNCTIONALITY ONLY
## Engineers triage their own ship and emit repair decisions; the machinery
## skill only acts through the ENGINEER role.

const GAME_TIME := 100.0
const HIGH_SKILL := 1.0
const LOW_SKILL := 0.1


func _ship_with_damage() -> Dictionary:
	var ship = TestFactories.make_ship("eng_ship", "corvette", 0, Vector2.ZERO, {
		"armor_sections": [TestFactories.make_armor_section("front", TestFactories.DEFAULT_ARMOR, 0.0, 360.0)],
		"internals": [
			TestFactories.make_component("engine", "engine", Vector2.ZERO,
				TestFactories.DEFAULT_COMPONENT_HEALTH, TestFactories.ENGINE_DAMAGE_EFFECTS),
			TestFactories.make_component("reactor", "reactor", Vector2(0, 5)),
		]
	})
	return ship


func _damage_component(ship: Dictionary, index: int, remaining_health: int) -> void:
	ship.internals[index].current_health = remaining_health
	ship.internals[index].status = "damaged" if remaining_health > 0 else "destroyed"


# ============================================================================
# REPAIR DECISIONS
# ============================================================================

func test_engineer_emits_repair_decision_for_damaged_component():
	var ship = _ship_with_damage()
	_damage_component(ship, 0, 5)
	var engineer = TestFactories.make_crew_engineer(HIGH_SKILL, ship.ship_id)

	var result = EngineerAI.make_decision(engineer, GAME_TIME, [ship])

	assert_true(result.has("decision"), "Engineer should decide to repair")
	assert_eq(result.decision.type, "repair", "Decision should be a repair")
	assert_true(result.decision.subtype.begins_with("fix_"), "Repair maneuvers are fix_* subtypes")
	assert_eq(result.decision.component_id, "engine", "Decision should target the damaged component")


func test_engineer_targets_worst_damaged_component():
	var ship = _ship_with_damage()
	_damage_component(ship, 0, ship.internals[0].max_health - 1)  # lightly damaged
	_damage_component(ship, 1, 1)  # nearly destroyed
	var engineer = TestFactories.make_crew_engineer(HIGH_SKILL, ship.ship_id)

	var result = EngineerAI.make_decision(engineer, GAME_TIME, [ship])

	assert_eq(result.decision.component_id, "reactor",
		"Engineer should triage the component with the lowest health ratio")


func test_engineer_prioritizes_internals_over_armor():
	var ship = _ship_with_damage()
	_damage_component(ship, 0, 5)
	ship.armor_sections[0].current_armor = 0
	var engineer = TestFactories.make_crew_engineer(HIGH_SKILL, ship.ship_id)

	var result = EngineerAI.make_decision(engineer, GAME_TIME, [ship])

	assert_true(result.decision.has("component_id"),
		"Damaged internals should outrank armor in triage")


func test_engineer_repairs_armor_when_internals_intact():
	var ship = _ship_with_damage()
	ship.armor_sections[0].current_armor = 1
	var engineer = TestFactories.make_crew_engineer(HIGH_SKILL, ship.ship_id)

	var result = EngineerAI.make_decision(engineer, GAME_TIME, [ship])

	assert_eq(result.decision.subtype, EngineerAI.ARMOR_REPAIR_SUBTYPE,
		"With internals intact, the engineer should patch armor")
	assert_eq(result.decision.section_id, "front", "Decision should target the damaged section")


func test_engineer_ignores_destroyed_components():
	var ship = _ship_with_damage()
	_damage_component(ship, 0, 0)  # destroyed — beyond field repair

	var engineer = TestFactories.make_crew_engineer(HIGH_SKILL, ship.ship_id)
	var result = EngineerAI.make_decision(engineer, GAME_TIME, [ship])

	assert_false(result.has("decision"),
		"Destroyed components (and undamaged armor) leave nothing to field-repair")


func test_engineer_idles_when_ship_undamaged():
	var ship = _ship_with_damage()
	var engineer = TestFactories.make_crew_engineer(HIGH_SKILL, ship.ship_id)

	var result = EngineerAI.make_decision(engineer, GAME_TIME, [ship])

	assert_false(result.has("decision"), "Nothing to repair, no decision")
	assert_gt(result.crew_data.next_decision_time, GAME_TIME,
		"Idle engineer should sleep until the next check")


# ============================================================================
# ROLE GATING AND SKILL SCALING
# ============================================================================

func test_non_engineer_with_machinery_never_repairs():
	var ship = _ship_with_damage()
	_damage_component(ship, 0, 5)
	var gunner = TestFactories.make_crew_gunner(HIGH_SKILL, ship.ship_id)
	gunner.stats.skills.machinery = HIGH_SKILL

	var result = CrewAISystem.update_crew_member(gunner, 0.1, GAME_TIME, [ship])

	if result.has("decision") and result.decision != null and not result.decision.is_empty():
		assert_ne(result.decision.get("type", ""), "repair",
			"machinery only acts through the ENGINEER role")
	else:
		pass_test("Gunner produced no decision — and certainly no repair")


func test_higher_machinery_heals_more():
	var ship = _ship_with_damage()
	ship.armor_sections[0].current_armor = 1
	var decision_template = {
		"type": "repair",
		"subtype": EngineerAI.ARMOR_REPAIR_SUBTYPE,
		"section_id": "front",
		"crew_id": "eng_1",
		"entity_id": ship.ship_id,
	}
	var low = decision_template.duplicate(true)
	low.skill_factor = LOW_SKILL
	var high = decision_template.duplicate(true)
	high.skill_factor = HIGH_SKILL

	var low_result = CrewIntegrationSystem.apply_repair_decision(ship, low, {})
	var high_result = CrewIntegrationSystem.apply_repair_decision(ship, high, {})

	assert_gt(high_result.armor_sections[0].current_armor, low_result.armor_sections[0].current_armor,
		"Higher machinery skill should repair more per action")


# ============================================================================
# CREW COMPOSITION
# ============================================================================

func test_create_ship_crew_includes_requested_engineers():
	var crew = CrewData.create_ship_crew(2, TestFactories.DEFAULT_CREW_SKILL, 3)

	var engineers = crew.filter(func(c): return c.role == CrewData.Role.ENGINEER)
	assert_eq(engineers.size(), 3, "Crew should include the requested engineers")
	for engineer in engineers:
		assert_eq(engineer.command_chain.superior, crew[0].crew_id,
			"Engineers should report to the captain")


func test_engineer_count_rolls_within_hull_bounds():
	for i in 20:
		var corvette_count = CrewData.roll_engineer_count("corvette")
		assert_between(corvette_count, WingConstants.CORVETTE_ENGINEERS_MIN,
			WingConstants.CORVETTE_ENGINEERS_MAX, "Corvette engineer roll should stay in bounds")

		var capital_count = CrewData.roll_engineer_count("capital")
		assert_between(capital_count, WingConstants.CAPITAL_ENGINEERS_MIN,
			WingConstants.CAPITAL_ENGINEERS_MAX, "Capital engineer roll should stay in bounds")

	assert_eq(CrewData.roll_engineer_count("fighter"), 0, "Fighters carry no engineers")
