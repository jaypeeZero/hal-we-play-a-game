extends GutTest

## Tests for RepairSystem - FUNCTIONALITY ONLY
## Repair restores armor/components and re-derives stats; it never
## exceeds maximums and never mutates its input.

const TEST_FRACTION := 0.5


func _ship_with_damaged_armor() -> Dictionary:
	var ship = TestFactories.make_ship("repair_ship", "corvette", 0, Vector2.ZERO, {
		"armor_sections": [TestFactories.make_armor_section("front", TestFactories.DEFAULT_ARMOR)],
		"internals": []
	})
	ship.armor_sections[0].current_armor = 1
	return ship


func _ship_with_engine(engine_status: String = "operational") -> Dictionary:
	var ship = TestFactories.make_ship("repair_ship", "corvette", 0, Vector2.ZERO, {
		"armor_sections": [TestFactories.make_armor_section("front", TestFactories.DEFAULT_ARMOR, 0.0, 360.0)],
		"internals": [TestFactories.make_component("engine", "engine", Vector2.ZERO,
			TestFactories.DEFAULT_COMPONENT_HEALTH, TestFactories.ENGINE_DAMAGE_EFFECTS)]
	})
	match engine_status:
		"damaged":
			ship.internals[0].current_health = 1
			ship.internals[0].status = "damaged"
			ship = DamageResolver.recompute_stats_from_components(ship)
		"destroyed":
			ship.internals[0].current_health = 0
			ship.internals[0].status = "destroyed"
			ship = DamageResolver.recompute_stats_from_components(ship)
	return ship


# ============================================================================
# ARMOR REPAIR
# ============================================================================

func test_repair_restores_armor():
	var ship = _ship_with_damaged_armor()
	var repaired = RepairSystem.repair_armor_section(ship, "front", 5)

	assert_gt(repaired.armor_sections[0].current_armor, ship.armor_sections[0].current_armor,
		"Repair should increase armor")


func test_repair_clamps_armor_at_max():
	var ship = _ship_with_damaged_armor()
	var repaired = RepairSystem.repair_armor_section(ship, "front", 999999)

	assert_eq(repaired.armor_sections[0].current_armor, repaired.armor_sections[0].max_armor,
		"Repair should never exceed max armor")


func test_repair_does_not_mutate_input():
	var ship = _ship_with_damaged_armor()
	var original_armor = ship.armor_sections[0].current_armor

	var _repaired = RepairSystem.repair_armor_section(ship, "front", 5)

	assert_eq(ship.armor_sections[0].current_armor, original_armor,
		"Original ship data should not be mutated")


# ============================================================================
# COMPONENT REPAIR
# ============================================================================

func test_full_component_repair_restores_max_speed():
	var ship = _ship_with_engine("damaged")
	assert_lt(ship.stats.max_speed, ship.base_stats.max_speed,
		"Precondition: damaged engine should reduce max_speed")

	var repaired = RepairSystem.repair_component(ship, "engine", 999999)

	assert_eq(repaired.internals[0].status, "operational",
		"Fully repaired component should be operational")
	assert_almost_eq(repaired.stats.max_speed, repaired.base_stats.max_speed, 0.01,
		"Repairing the engine should restore max_speed")


func test_partial_repair_keeps_damaged_effects():
	var ship = _ship_with_engine("damaged")
	var repaired = RepairSystem.repair_component(ship, "engine", 1)

	assert_eq(repaired.internals[0].status, "damaged",
		"Partially repaired component should stay damaged")
	assert_lt(repaired.stats.max_speed, repaired.base_stats.max_speed,
		"Damaged-engine speed penalty should persist until fully repaired")


func test_destroyed_component_not_field_repairable():
	var ship = _ship_with_engine("destroyed")
	var repaired = RepairSystem.repair_component(ship, "engine", 999999)

	assert_eq(repaired.internals[0].status, "destroyed",
		"Destroyed components should not be repairable in battle")
	assert_eq(repaired.internals[0].current_health, 0,
		"Destroyed component health should be unchanged")


func test_destroyed_component_repairable_with_downtime():
	var ship = _ship_with_engine("destroyed")
	var destroyed_speed = ship.stats.max_speed

	var repaired = RepairSystem.repair_component(ship, "engine", 999999, true)

	assert_eq(repaired.internals[0].status, "operational",
		"Downtime repair should restore destroyed components")
	assert_gt(repaired.stats.max_speed, destroyed_speed,
		"Restoring the engine should lift the destroyed-engine speed penalty")


func test_damage_then_repair_then_damage_does_not_compound_penalties():
	var ship = _ship_with_engine("damaged")
	var damaged_speed = ship.stats.max_speed

	var repaired = RepairSystem.repair_component(ship, "engine", 999999)
	repaired.internals[0].current_health = 1
	repaired.internals[0].status = "damaged"
	var redamaged = DamageResolver.recompute_stats_from_components(repaired)

	assert_almost_eq(redamaged.stats.max_speed, damaged_speed, 0.01,
		"Damage→repair→damage should land on the same penalty, not compound")


# ============================================================================
# FRACTIONAL / FLEET REPAIR
# ============================================================================

func test_repair_ship_fraction_heals_armor_and_components():
	var ship = _ship_with_engine("damaged")
	ship.armor_sections[0].current_armor = 1

	var repaired = RepairSystem.repair_ship_fraction(ship, TEST_FRACTION)

	assert_gt(repaired.armor_sections[0].current_armor, ship.armor_sections[0].current_armor,
		"Fractional repair should heal armor")
	assert_gt(repaired.internals[0].current_health, ship.internals[0].current_health,
		"Fractional repair should heal components")


func test_apply_engineer_repairs_heals_ship_with_engineer():
	var ship = _ship_with_damaged_armor()
	ship["crew"] = [TestFactories.make_crew_engineer(1.0, ship.ship_id)]

	var repaired = RepairSystem.apply_engineer_repairs(ship, TEST_FRACTION)

	assert_gt(repaired.armor_sections[0].current_armor, ship.armor_sections[0].current_armor,
		"A ship with an engineer should heal")


func test_apply_engineer_repairs_skips_ship_without_engineer():
	var ship = _ship_with_damaged_armor()
	ship["crew"] = [TestFactories.make_crew_pilot(1.0, ship.ship_id)]

	var repaired = RepairSystem.apply_engineer_repairs(ship, TEST_FRACTION)

	assert_eq(repaired.armor_sections[0].current_armor, ship.armor_sections[0].current_armor,
		"A ship without an engineer should not heal, whatever other crew's machinery skill")


func test_more_engineers_heal_more():
	var one = _ship_with_damaged_armor()
	one["crew"] = [TestFactories.make_crew_engineer(0.5, one.ship_id)]
	var two = _ship_with_damaged_armor()
	two["crew"] = [
		TestFactories.make_crew_engineer(0.5, two.ship_id),
		TestFactories.make_crew_engineer(0.5, two.ship_id),
	]
	# Large enough that the per-engineer contribution clears the 1-point
	# repair floor, small enough that two engineers don't clamp at max.
	var fraction := 0.2

	var healed_one = RepairSystem.apply_engineer_repairs(one, fraction)
	var healed_two = RepairSystem.apply_engineer_repairs(two, fraction)

	assert_gt(healed_two.armor_sections[0].current_armor, healed_one.armor_sections[0].current_armor,
		"Two engineers should repair more than one")


func test_disabled_ship_recovers_when_disabling_component_restored():
	var ship = TestFactories.make_ship("disabled_ship", "corvette", 0, Vector2.ZERO, {
		"armor_sections": [],
		"internals": [TestFactories.make_component("reactor", "reactor", Vector2.ZERO,
			TestFactories.DEFAULT_COMPONENT_HEALTH, {"on_destroyed": {"disabled": true}})],
		"status": "disabled",
	})
	ship.internals[0].current_health = 0
	ship.internals[0].status = "destroyed"

	var repaired = RepairSystem.repair_ship_fraction(ship, 1.0, true)

	assert_eq(repaired.status, "operational",
		"Restoring the disabling component should bring the ship back online")
