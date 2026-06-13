extends GutTest

## Tests for the Layer D repair parts pool.
## Asserts BEHAVIOR: pool depletes, healing stops when empty, pool scales by
## ship class, between-battle repair is unaffected.

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_ship_with_pool(armor: int, pool: int) -> Dictionary:
	var ship := TestFactories.make_ship("s1", "corvette", 0, Vector2.ZERO, {
		"armor_sections": [TestFactories.make_armor_section("front", armor)],
		"internals": [],
		"repair_pool": pool,
		"repair_pool_max": pool,
	})
	# Start with half armor so there is something to repair.
	ship.armor_sections[0].current_armor = armor / 2
	return ship


func _make_repair_decision(ship_id: String, section_id: String, skill: float = 0.8) -> Dictionary:
	return {
		"type": "repair",
		"subtype": "fix_armor",
		"crew_id": "eng1",
		"entity_id": ship_id,
		"section_id": section_id,
		"skill_factor": skill,
		"timestamp": 0.0,
	}


func _make_component_repair_decision(ship_id: String, component_id: String, skill: float = 0.8) -> Dictionary:
	return {
		"type": "repair",
		"subtype": "fix_engine",
		"crew_id": "eng1",
		"entity_id": ship_id,
		"component_id": component_id,
		"skill_factor": skill,
		"timestamp": 0.0,
	}


# ---------------------------------------------------------------------------
# Pool depletion stops healing
# ---------------------------------------------------------------------------

func test_repair_reduces_pool():
	var ship := _make_ship_with_pool(100, 50)
	var before_pool: int = ship["repair_pool"]

	var result := CrewIntegrationSystem.apply_repair_decision(
		ship, _make_repair_decision(ship.ship_id, "front"), {}
	)

	assert_lt(result.get("repair_pool", before_pool), before_pool,
		"A repair should reduce the repair pool")


func test_repair_pool_exhausted_leaves_health_unchanged():
	var ship := _make_ship_with_pool(100, 0)  # pool already empty
	var armor_before: int = ship.armor_sections[0].current_armor

	var result := CrewIntegrationSystem.apply_repair_decision(
		ship, _make_repair_decision(ship.ship_id, "front"), {}
	)

	assert_eq(result.armor_sections[0].current_armor, armor_before,
		"With an exhausted pool, repair must not change armor")


func test_repair_amount_clamped_to_pool():
	# Pool smaller than what the skill-fraction would normally repair.
	var ship := _make_ship_with_pool(200, 1)  # only 1 part left
	var armor_before: int = ship.armor_sections[0].current_armor

	var result := CrewIntegrationSystem.apply_repair_decision(
		ship, _make_repair_decision(ship.ship_id, "front"), {}
	)

	var healed: int = result.armor_sections[0].current_armor - armor_before
	assert_lte(healed, 1,
		"Repair amount must not exceed the remaining pool")
	assert_eq(result.get("repair_pool", 999), 0,
		"Pool should reach zero after a clamped repair")


# ---------------------------------------------------------------------------
# Pool scales by ship class
# ---------------------------------------------------------------------------

func test_capital_has_larger_pool_than_corvette():
	var capital := TestFactories.make_capital("cap1")
	var corvette := TestFactories.make_corvette("cor1")
	var capital_pool := ShipData.compute_repair_pool(capital)
	var corvette_pool := ShipData.compute_repair_pool(corvette)

	assert_gt(capital_pool, corvette_pool,
		"A capital's repair pool must be larger than a corvette's")


func test_repair_pool_positive_for_armed_ship():
	var ship := TestFactories.make_capital("cap2")
	var pool := ShipData.compute_repair_pool(ship)

	assert_gt(pool, 0,
		"Any ship with armor/internals must start with a positive repair pool")


# ---------------------------------------------------------------------------
# Between-battle repair does not consume the battle pool
# ---------------------------------------------------------------------------

func test_between_battle_repair_does_not_touch_pool():
	# RepairSystem.apply_engineer_repairs is the between-battle path.
	var ship := TestFactories.make_ship("s2", "corvette", 0, Vector2.ZERO, {
		"armor_sections": [TestFactories.make_armor_section("front", 100)],
		"internals": [],
		"repair_pool": 30,
		"repair_pool_max": 30,
	})
	ship.armor_sections[0].current_armor = 50
	ship["crew"] = [TestFactories.make_crew_engineer(1.0, ship.ship_id)]

	var repaired := RepairSystem.apply_engineer_repairs(ship, 0.5)

	# Pool should be untouched by the between-battle path.
	assert_eq(repaired.get("repair_pool", 30), 30,
		"Between-battle engineer repairs must not consume the battle repair pool")


# ---------------------------------------------------------------------------
# Engineer world-state: no repair action when pool is empty
# ---------------------------------------------------------------------------

func test_engineer_produces_no_action_when_pool_empty():
	var ship := TestFactories.make_ship("s3", "corvette", 0, Vector2.ZERO, {
		"armor_sections": [TestFactories.make_armor_section("front", 100)],
		"internals": [],
		"repair_pool": 0,
		"repair_pool_max": 30,
	})
	ship.armor_sections[0].current_armor = 10  # heavily damaged

	var engineer := TestFactories.make_crew_engineer(0.8, ship.ship_id)
	var ws := EngineerWorldState.build(engineer, 0.0, [ship])

	var armor_action := RepairArmorAction.new()
	assert_false(armor_action.precondition(ws),
		"RepairArmorAction must not fire when the repair pool is empty")

	var internal_action := RepairInternalAction.new()
	assert_false(internal_action.precondition(ws),
		"RepairInternalAction must not fire when the repair pool is empty")
