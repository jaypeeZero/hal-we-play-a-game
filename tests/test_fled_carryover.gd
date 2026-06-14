extends GutTest

## Behavior tests for the Roguelike fled-ship carryover (record_battle_result):
## - Victory: a fled hull survives carrying its flee-time damage.
## - Defeat with some fled: exactly the fled hulls carry forward, the rest gone.
## - Defeat with none fled: a total loss empties the fleet and stashes its final state.
## - Crew on a lost (non-fled) hull are pruned from doctrine.

var _saved_fleet_hulls: Array
var _saved_doctrine: Dictionary
var _saved_active: bool
var _saved_started_first_battle: bool
var _saved_battle_result: String
var _saved_battle_fled: bool
var _saved_lost_ships: Array
var _saved_lost_crew: Array
var _saved_money: int
var _saved_squadrons: Array
var _saved_battle_summary: Dictionary


func before_each() -> void:
	_saved_fleet_hulls = RoguelikeRun.fleet_hulls.duplicate(true)
	_saved_doctrine = RoguelikeRun.doctrine.duplicate(true)
	_saved_active = RoguelikeRun.active
	_saved_started_first_battle = RoguelikeRun.started_first_battle
	_saved_battle_result = RoguelikeRun.pending_battle_result
	_saved_battle_fled = RoguelikeRun.pending_battle_fled
	_saved_lost_ships = RoguelikeRun.lost_fleet_final_ships.duplicate(true)
	_saved_lost_crew = RoguelikeRun.lost_fleet_final_crew.duplicate(true)
	_saved_money = RoguelikeRun.money
	_saved_squadrons = RoguelikeRun.squadrons.duplicate(true)
	_saved_battle_summary = RoguelikeRun.last_battle_summary.duplicate(true)


func after_each() -> void:
	RoguelikeRun.fleet_hulls = _saved_fleet_hulls
	RoguelikeRun.doctrine = _saved_doctrine
	RoguelikeRun.active = _saved_active
	RoguelikeRun.started_first_battle = _saved_started_first_battle
	RoguelikeRun.pending_battle_result = _saved_battle_result
	RoguelikeRun.pending_battle_fled = _saved_battle_fled
	RoguelikeRun.lost_fleet_final_ships = _saved_lost_ships
	RoguelikeRun.lost_fleet_final_crew = _saved_lost_crew
	RoguelikeRun.money = _saved_money
	RoguelikeRun.squadrons = _saved_squadrons
	RoguelikeRun.last_battle_summary = _saved_battle_summary


func _counts(overrides: Dictionary = {}) -> Dictionary:
	var base := {"fighter": 0, "heavy_fighter": 0,
		"torpedo_boat": 0, "corvette": 0, "capital": 0}
	for key in overrides:
		base[key] = overrides[key]
	return base


func _hull_ids() -> Array:
	return RoguelikeRun.fleet_hulls.map(func(h): return h.get("hull_id", ""))


## A ship dict the battle scene hands back for `hull`. `fled` flags an escape;
## `damaged` knocks a section's armor down so the carried state isn't pristine.
func _ship_for(hull: Dictionary, fled: bool, damaged := false) -> Dictionary:
	var ship := ShipData.create_ship_instance(hull.ship_type, 0, Vector2.ZERO)
	ship["hull_id"] = hull.hull_id
	ship["crew"] = hull.crew.duplicate(true)
	ship["status"] = "operational"
	ship["fled"] = fled
	if damaged and not ship["armor_sections"].is_empty():
		ship["armor_sections"][0]["current_armor"] = 1
	return ship


func _total_armor(ship: Dictionary) -> int:
	var total := 0
	for section in ship.get("armor_sections", []):
		total += int(section.get("current_armor", 0))
	return total


# ============================================================================
# VICTORY: fled ships recovered with flee-time damage
# ============================================================================

func test_victory_recovers_a_fled_hull_with_its_damage():
	RoguelikeRun.start_run(_counts({"fighter": 2}))
	var fled_hull: Dictionary = RoguelikeRun.fleet_hulls[0]
	var survivor_hull: Dictionary = RoguelikeRun.fleet_hulls[1]

	var fled_ship := _ship_for(fled_hull, true, true)
	var survivor_ship := _ship_for(survivor_hull, false)
	RoguelikeRun.record_battle_result(
		CampaignSystem.RESULT_VICTORY, [fled_ship, survivor_ship])

	assert_true(fled_hull.hull_id in _hull_ids(),
		"a fled hull must persist in the fleet after a victory")
	var carried := RoguelikeRun.hull_by_id(fled_hull.hull_id)
	assert_false(carried.ship.is_empty(),
		"the recovered hull must carry its flee-time damage state, not be pristine")


# ============================================================================
# DEFEAT WITH FLED: only the fled hulls carry forward
# ============================================================================

func test_defeat_with_some_fled_carries_only_those_hulls():
	RoguelikeRun.start_run(_counts({"fighter": 4}))
	var hulls: Array = RoguelikeRun.fleet_hulls
	var fled_ids := [hulls[0].hull_id, hulls[1].hull_id]

	var final_ships: Array = [
		_ship_for(hulls[0], true),
		_ship_for(hulls[1], true),
		_ship_for(hulls[2], false),
		_ship_for(hulls[3], false),
	]
	RoguelikeRun.record_battle_result(CampaignSystem.RESULT_DEFEAT, final_ships)

	var remaining := _hull_ids()
	assert_eq(remaining.size(), 2, "only the two fled hulls remain")
	assert_true(fled_ids[0] in remaining and fled_ids[1] in remaining,
		"the surviving hulls must be exactly the fled ones")
	assert_true(RoguelikeRun.pending_battle_fled,
		"a defeat with fled ships must flag pending_battle_fled")


func test_defeat_with_zero_fled_is_a_total_loss():
	RoguelikeRun.start_run(_counts({"fighter": 2}))
	var hulls: Array = RoguelikeRun.fleet_hulls
	var final_ships: Array = [
		_ship_for(hulls[0], false),
		_ship_for(hulls[1], false),
	]
	RoguelikeRun.record_battle_result(CampaignSystem.RESULT_DEFEAT, final_ships)

	assert_true(RoguelikeRun.fleet_hulls.is_empty(),
		"a total defeat empties the hull fleet")
	assert_false(RoguelikeRun.pending_battle_fled,
		"a defeat with no fled ships must not flag pending_battle_fled")
	assert_false(RoguelikeRun.lost_fleet_final_ships.is_empty(),
		"the lost fleet's final state is stashed for the post-battle summary")


# ============================================================================
# DOCTRINE PRUNING for crew lost with non-fled hulls
# ============================================================================

func test_doctrine_pruned_for_crew_on_lost_hulls():
	RoguelikeRun.start_run(_counts({"fighter": 2}))
	var fled_hull: Dictionary = RoguelikeRun.fleet_hulls[0]
	var lost_hull: Dictionary = RoguelikeRun.fleet_hulls[1]
	var lost_crew_id: String = lost_hull.crew[0].crew_id

	DoctrineSystem.set_instruction_in_place(
		RoguelikeRun.doctrine, DoctrineSystem.SCOPE_CREW, lost_crew_id, "charge_head_on")
	assert_true(RoguelikeRun.doctrine[DoctrineSystem.SCOPE_CREW].has(lost_crew_id),
		"precondition: the lost crew's doctrine is set")

	RoguelikeRun.record_battle_result(CampaignSystem.RESULT_DEFEAT, [
		_ship_for(fled_hull, true),
		_ship_for(lost_hull, false),
	])

	assert_false(RoguelikeRun.doctrine[DoctrineSystem.SCOPE_CREW].has(lost_crew_id),
		"doctrine for crew lost with a non-fled hull must be pruned")
