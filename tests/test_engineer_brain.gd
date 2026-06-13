extends GutTest

## Tests for EngineerBrain GOAP planner — behavior only, no specific data values.

const GAME_TIME := 100.0
const HIGH_SKILL := 1.0


func _make_engineer(ship_id: String = "ship_1") -> Dictionary:
	return TestFactories.make_crew_engineer(HIGH_SKILL, ship_id)


func _ship_with_damage() -> Dictionary:
	return TestFactories.make_ship("eng_ship", "corvette", 0, Vector2.ZERO, {
		"armor_sections": [TestFactories.make_armor_section("front", TestFactories.DEFAULT_ARMOR, 0.0, 360.0)],
		"internals": [
			TestFactories.make_component("engine", "engine", Vector2.ZERO,
				TestFactories.DEFAULT_COMPONENT_HEALTH, TestFactories.ENGINE_DAMAGE_EFFECTS),
			TestFactories.make_component("reactor", "reactor", Vector2(0, 5)),
		]
	})


func _damage_component(ship: Dictionary, index: int, remaining_health: int) -> void:
	ship.internals[index].current_health = remaining_health
	ship.internals[index].status = "damaged" if remaining_health > 0 else "destroyed"


# TRIAGE ORDERING

func test_damaged_internal_chosen_over_more_damaged_armor():
	var ship := _ship_with_damage()
	_damage_component(ship, 0, 1)          # nearly destroyed internal
	ship.armor_sections[0].current_armor = 0   # fully stripped armor

	var engineer := _make_engineer(ship.ship_id)
	var result := EngineerAI.make_decision(engineer, GAME_TIME, [ship])

	assert_true(result.has("decision"), "Should produce a repair decision")
	assert_true(result.decision.has("component_id"),
		"Damaged internal should outrank armor in triage regardless of damage depth")


func test_worst_ratio_internal_chosen_among_several():
	var ship := _ship_with_damage()
	_damage_component(ship, 0, ship.internals[0].max_health - 1)  # lightly damaged
	_damage_component(ship, 1, 1)                                  # nearly destroyed

	var engineer := _make_engineer(ship.ship_id)
	var result := EngineerAI.make_decision(engineer, GAME_TIME, [ship])

	assert_eq(result.decision.get("component_id", ""), "reactor",
		"Should choose the internal with the lowest health ratio")


func test_destroyed_internals_never_selected():
	var ship := _ship_with_damage()
	_damage_component(ship, 0, 0)   # destroyed — beyond field repair
	# reactor is intact, armor is full

	var engineer := _make_engineer(ship.ship_id)
	var result := EngineerAI.make_decision(engineer, GAME_TIME, [ship])

	assert_false(result.has("decision"),
		"Destroyed components cannot be field-repaired; nothing to repair")


func test_undamaged_ship_produces_no_decision():
	var ship := _ship_with_damage()
	# Both internals intact (default), armor full (default)

	var engineer := _make_engineer(ship.ship_id)
	var result := EngineerAI.make_decision(engineer, GAME_TIME, [ship])

	assert_false(result.has("decision"), "Nothing to repair on an undamaged ship")
	assert_gt(result.crew_data.next_decision_time, GAME_TIME,
		"Idle engineer should advance next_decision_time")


func test_decision_carries_component_id_for_internals():
	var ship := _ship_with_damage()
	_damage_component(ship, 0, 5)

	var engineer := _make_engineer(ship.ship_id)
	var result := EngineerAI.make_decision(engineer, GAME_TIME, [ship])

	assert_true(result.has("decision"), "Should decide to repair")
	assert_true(result.decision.has("component_id"),
		"Internal repair decision must include component_id")
	assert_false(result.decision.has("section_id"),
		"Internal repair decision must not include section_id")


func test_decision_carries_section_id_for_armor():
	var ship := _ship_with_damage()
	ship.armor_sections[0].current_armor = 1   # damaged armor, internals intact

	var engineer := _make_engineer(ship.ship_id)
	var result := EngineerAI.make_decision(engineer, GAME_TIME, [ship])

	assert_true(result.has("decision"), "Should decide to repair armor")
	assert_eq(result.decision.get("subtype", ""), EngineerAI.ARMOR_REPAIR_SUBTYPE,
		"Armor repair should use the armor subtype constant")
	assert_true(result.decision.has("section_id"),
		"Armor repair decision must include section_id")
	assert_false(result.decision.has("component_id"),
		"Armor repair decision must not include component_id")
