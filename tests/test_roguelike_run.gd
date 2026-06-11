extends GutTest

## Tests for RoguelikeRun state management - FUNCTIONALITY ONLY
## Verifies fleet persistence, damage carry-over, and enemy fleet independence

var _saved_fleet: Dictionary
var _saved_fleet_ships: Array
var _saved_enemy_fleet: Dictionary
var _saved_active: bool
var _saved_started_first_battle: bool
var _saved_star_date: int
var _saved_repair_summary: Dictionary


func before_each() -> void:
	_saved_fleet = RoguelikeRun.fleet.duplicate(true)
	_saved_fleet_ships = RoguelikeRun.fleet_ships.duplicate(true)
	_saved_enemy_fleet = RoguelikeRun.enemy_fleet.duplicate(true)
	_saved_active = RoguelikeRun.active
	_saved_started_first_battle = RoguelikeRun.started_first_battle
	_saved_star_date = RoguelikeRun.current_star_date
	_saved_repair_summary = RoguelikeRun.last_jump_repair_summary.duplicate(true)


func after_each() -> void:
	RoguelikeRun.fleet = _saved_fleet
	RoguelikeRun.fleet_ships = _saved_fleet_ships
	RoguelikeRun.enemy_fleet = _saved_enemy_fleet
	RoguelikeRun.active = _saved_active
	RoguelikeRun.started_first_battle = _saved_started_first_battle
	RoguelikeRun.current_star_date = _saved_star_date
	RoguelikeRun.last_jump_repair_summary = _saved_repair_summary


func _make_ship(ship_type: String) -> Dictionary:
	return ShipData.create_ship_instance(ship_type, 0, Vector2.ZERO)


# ============================================================================
# FLEET TRACKING AFTER BATTLE
# ============================================================================

func test_update_fleet_stores_surviving_ships():
	var ship1 = _make_ship("fighter")
	var ship2 = _make_ship("corvette")

	RoguelikeRun.update_fleet_after_battle([ship1, ship2])

	assert_eq(RoguelikeRun.fleet_ships.size(), 2, "Both surviving ships should be stored")


func test_update_fleet_rebuilds_count_dict():
	var ships := [_make_ship("fighter"), _make_ship("fighter"), _make_ship("corvette")]

	RoguelikeRun.update_fleet_after_battle(ships)

	assert_eq(RoguelikeRun.fleet.get("fighter", 0), 2, "Fleet count should reflect 2 fighters")
	assert_eq(RoguelikeRun.fleet.get("corvette", 0), 1, "Fleet count should reflect 1 corvette")


func test_update_fleet_zeroes_lost_ship_types():
	var ships := [_make_ship("fighter")]
	RoguelikeRun.fleet = {"fighter": 2, "corvette": 3, "capital": 1,
		"heavy_fighter": 0, "torpedo_boat": 0}

	RoguelikeRun.update_fleet_after_battle(ships)

	assert_eq(RoguelikeRun.fleet.get("corvette", -1), 0,
		"Lost ship types should be zeroed in fleet count")
	assert_eq(RoguelikeRun.fleet.get("capital", -1), 0,
		"Lost ship types should be zeroed in fleet count")


# ============================================================================
# FLEET EMPTY CHECK
# ============================================================================

func test_fleet_is_empty_when_no_survivors():
	RoguelikeRun.update_fleet_after_battle([])

	assert_true(RoguelikeRun.is_fleet_empty(), "Fleet should be empty with no survivors")


func test_fleet_is_not_empty_when_any_ship_survives():
	RoguelikeRun.update_fleet_after_battle([_make_ship("fighter")])

	assert_false(RoguelikeRun.is_fleet_empty(), "Fleet should not be empty with a surviving ship")


# ============================================================================
# DAMAGE STATE PERSISTENCE
# ============================================================================

func test_surviving_ship_armor_damage_is_preserved():
	var ship = _make_ship("fighter")
	ship["armor_sections"][0]["current_armor"] = 0

	RoguelikeRun.update_fleet_after_battle([ship])

	assert_eq(RoguelikeRun.fleet_ships[0]["armor_sections"][0]["current_armor"], 0,
		"Depleted armor should carry over to next battle")


func test_surviving_ship_internal_damage_is_preserved():
	var ship = _make_ship("corvette")
	ship["internals"][0]["status"] = "destroyed"
	ship["internals"][0]["current_health"] = 0

	RoguelikeRun.update_fleet_after_battle([ship])

	assert_eq(RoguelikeRun.fleet_ships[0]["internals"][0]["status"], "destroyed",
		"Destroyed internal component should carry over to next battle")


func test_surviving_ship_stat_penalties_are_preserved():
	var ship = _make_ship("corvette")
	var base_speed: float = ship["stats"]["max_speed"]
	ship["stats"]["max_speed"] = base_speed * 0.5

	RoguelikeRun.update_fleet_after_battle([ship])

	assert_almost_eq(
		RoguelikeRun.fleet_ships[0]["stats"]["max_speed"],
		base_speed * 0.5,
		0.01,
		"Speed penalty from engine damage should carry over to next battle"
	)


func test_fleet_ships_are_deep_copied():
	var ship = _make_ship("fighter")
	RoguelikeRun.update_fleet_after_battle([ship])

	# Modify the original after storing
	ship["armor_sections"][0]["current_armor"] = 999.0

	assert_ne(RoguelikeRun.fleet_ships[0]["armor_sections"][0]["current_armor"], 999.0,
		"fleet_ships should be a deep copy, not a reference")


# ============================================================================
# ENEMY FLEET INDEPENDENCE
# ============================================================================

func test_enemy_fleet_is_not_affected_by_player_battle_results():
	RoguelikeRun.enemy_fleet = {
		"fighter": 3, "corvette": 2, "heavy_fighter": 0, "torpedo_boat": 0, "capital": 0
	}

	RoguelikeRun.update_fleet_after_battle([_make_ship("fighter")])

	assert_eq(RoguelikeRun.enemy_fleet.get("fighter", 0), 3,
		"Enemy fighter count should not change after player battle")
	assert_eq(RoguelikeRun.enemy_fleet.get("corvette", 0), 2,
		"Enemy corvette count should not change after player battle")


func test_enemy_fleet_survives_multiple_battles():
	RoguelikeRun.enemy_fleet = {
		"fighter": 2, "corvette": 1, "heavy_fighter": 0, "torpedo_boat": 0, "capital": 0
	}
	var enemy_fighter_count: int = RoguelikeRun.enemy_fleet["fighter"]

	RoguelikeRun.update_fleet_after_battle([_make_ship("fighter")])
	RoguelikeRun.update_fleet_after_battle([_make_ship("fighter")])

	assert_eq(RoguelikeRun.enemy_fleet.get("fighter", 0), enemy_fighter_count,
		"Enemy fleet should be identical before and after multiple battles")


# ============================================================================
# RUN LIFECYCLE
# ============================================================================

func test_end_run_clears_fleet_ships():
	RoguelikeRun.update_fleet_after_battle([_make_ship("fighter")])

	RoguelikeRun.end_run()

	assert_true(RoguelikeRun.fleet_ships.is_empty(),
		"fleet_ships should be cleared when run ends")


func test_end_run_clears_enemy_fleet():
	RoguelikeRun.enemy_fleet = {"fighter": 3, "corvette": 1,
		"heavy_fighter": 0, "torpedo_boat": 0, "capital": 0}

	RoguelikeRun.end_run()

	assert_true(RoguelikeRun.enemy_fleet.is_empty(),
		"enemy_fleet should be cleared when run ends")


# ============================================================================
# JUMP REPAIRS (Engineers + star dates)
# ============================================================================

const JUMP_DATE_DELTA := 5

func _make_damaged_ship_with_crew(engineer_count: int) -> Dictionary:
	var ship = _make_ship("corvette")
	ship["armor_sections"][0]["current_armor"] = 1
	ship["crew"] = []
	for i in engineer_count:
		ship["crew"].append(TestFactories.make_crew_engineer(1.0, ship.ship_id))
	return ship


func _total_armor(ship: Dictionary) -> int:
	return DamageResolver.calculate_total_armor(ship)


func test_jump_repairs_heal_ship_with_engineers():
	RoguelikeRun.fleet_ships = [_make_damaged_ship_with_crew(1)]
	var before = _total_armor(RoguelikeRun.fleet_ships[0])

	var summary = RoguelikeRun.apply_jump_repairs(RoguelikeRun.current_star_date + JUMP_DATE_DELTA, false)

	assert_gt(_total_armor(RoguelikeRun.fleet_ships[0]), before,
		"Ship with an engineer should heal during the jump")
	assert_eq(summary.ships_repaired, 1, "Summary should count the repaired ship")
	assert_eq(summary.date_delta, JUMP_DATE_DELTA, "Summary should report the star-date gap")


func test_jump_repairs_skip_ship_without_engineers():
	RoguelikeRun.fleet_ships = [_make_damaged_ship_with_crew(0)]
	var before = _total_armor(RoguelikeRun.fleet_ships[0])

	RoguelikeRun.apply_jump_repairs(RoguelikeRun.current_star_date + JUMP_DATE_DELTA, false)

	assert_eq(_total_armor(RoguelikeRun.fleet_ships[0]), before,
		"Ship without engineers should not heal during the jump")


func test_wider_date_gap_heals_more():
	var start_date = RoguelikeRun.current_star_date

	RoguelikeRun.fleet_ships = [_make_damaged_ship_with_crew(1)]
	RoguelikeRun.apply_jump_repairs(start_date + 2, false)
	var narrow_gap_armor = _total_armor(RoguelikeRun.fleet_ships[0])

	RoguelikeRun.current_star_date = start_date
	RoguelikeRun.fleet_ships = [_make_damaged_ship_with_crew(1)]
	RoguelikeRun.apply_jump_repairs(start_date + 9, false)
	var wide_gap_armor = _total_armor(RoguelikeRun.fleet_ships[0])

	assert_gt(wide_gap_armor, narrow_gap_armor,
		"A longer jump (more downtime) should repair more")


func test_rnr_heals_more_than_battle_jump_at_equal_gap():
	var start_date = RoguelikeRun.current_star_date

	RoguelikeRun.fleet_ships = [_make_damaged_ship_with_crew(1)]
	RoguelikeRun.apply_jump_repairs(start_date + JUMP_DATE_DELTA, false)
	var battle_jump_armor = _total_armor(RoguelikeRun.fleet_ships[0])

	RoguelikeRun.current_star_date = start_date
	RoguelikeRun.fleet_ships = [_make_damaged_ship_with_crew(1)]
	RoguelikeRun.apply_jump_repairs(start_date + JUMP_DATE_DELTA, true)
	var rnr_armor = _total_armor(RoguelikeRun.fleet_ships[0])

	assert_gt(rnr_armor, battle_jump_armor,
		"R&R downtime should repair more than a battle jump of the same gap")


func test_jump_repairs_restore_destroyed_components():
	var ship = _make_damaged_ship_with_crew(1)
	ship["internals"][0]["status"] = "destroyed"
	ship["internals"][0]["current_health"] = 0
	RoguelikeRun.fleet_ships = [ship]

	RoguelikeRun.apply_jump_repairs(RoguelikeRun.current_star_date + JUMP_DATE_DELTA, true)

	assert_gt(RoguelikeRun.fleet_ships[0]["internals"][0]["current_health"], 0,
		"Downtime repairs should restore destroyed components")
	assert_ne(RoguelikeRun.fleet_ships[0]["internals"][0]["status"], "destroyed",
		"Restored component should no longer be destroyed")


func test_jump_advances_current_star_date():
	var destination = RoguelikeRun.current_star_date + JUMP_DATE_DELTA

	RoguelikeRun.apply_jump_repairs(destination, false)

	assert_eq(RoguelikeRun.current_star_date, destination,
		"The jump should move the run to the destination star date")


func test_jump_repair_summary_persists_for_the_map():
	RoguelikeRun.fleet_ships = [_make_damaged_ship_with_crew(1)]

	RoguelikeRun.apply_jump_repairs(RoguelikeRun.current_star_date + JUMP_DATE_DELTA, false)

	assert_gt(RoguelikeRun.last_jump_repair_summary.get("ships_repaired", 0), 0,
		"The map reports repairs after a battle from the persisted summary")


func test_fleet_ships_empty_at_run_start():
	# start_run reads team1 fleet from disk which may not exist in test env;
	# we verify fleet_ships is reset regardless of that side-effect
	RoguelikeRun.fleet_ships = [_make_ship("fighter")]
	RoguelikeRun.active = true

	var dummy_fleet := {"fighter": 1, "heavy_fighter": 0,
		"torpedo_boat": 0, "corvette": 0, "capital": 0}
	RoguelikeRun.start_run(dummy_fleet)

	assert_true(RoguelikeRun.fleet_ships.is_empty(),
		"fleet_ships should be empty at the start of a new run (first battle spawns fresh ships)")
