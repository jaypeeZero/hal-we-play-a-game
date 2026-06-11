extends GutTest

## Tests for DemotionFleetBuilder - FUNCTIONALITY ONLY
## A wiped fleet yields a bounded random remnant: operational ships in a
## damaged-but-flyable state with their crews carried over intact.

const TEST_SEED := 4242


func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = TEST_SEED
	return rng


func _make_lost_ship(ship_type: String) -> Dictionary:
	var ship: Dictionary = ShipData.create_ship_instance(ship_type, 0, Vector2.ZERO)
	ship["status"] = "destroyed"
	for section in ship["armor_sections"]:
		section["current_armor"] = 0
	for component in ship["internals"]:
		component["current_health"] = 0
		component["status"] = "destroyed"
	return ship


func _make_crew_group(ship_type: String, crew_id: String) -> Dictionary:
	return {"ship_type": ship_type, "crew": [{
		"crew_id": crew_id,
		"callsign": "CALLSIGN_" + crew_id,
		"role": CrewData.Role.PILOT,
		"known_patterns": ["pattern_a"],
	}]}


func _lost_fleet(types: Array) -> Dictionary:
	var ships: Array = []
	var groups: Array = []
	for i in types.size():
		ships.append(_make_lost_ship(types[i]))
		groups.append(_make_crew_group(types[i], "crew_%d" % i))
	return {"ships": ships, "groups": groups}


func test_empty_loss_yields_empty_remnant():
	var survivors := DemotionFleetBuilder.pick_survivors([], [], _rng())

	assert_eq(survivors["ships"], [], "No lost ships means no survivors")
	assert_eq(survivors["crew_groups"], [], "No lost crew means no carried crew")


func test_survivors_are_a_bounded_nonempty_subset():
	var lost := _lost_fleet(["fighter", "fighter", "corvette", "capital"])

	var survivors := DemotionFleetBuilder.pick_survivors(lost.ships, lost.groups, _rng())

	var max_share := ceili(lost.ships.size() * DemotionFleetBuilder.MAX_SURVIVOR_FRACTION)
	assert_between(survivors["ships"].size(), 1, max_share,
		"At least one ship survives, but never more than the maximum share")
	var lost_types: Array = lost.ships.map(func(s): return s["type"])
	for ship in survivors["ships"]:
		assert_has(lost_types, ship["type"],
			"Survivors must come from the lost fleet")


func test_survivors_come_back_operational_and_damaged():
	var lost := _lost_fleet(["fighter", "corvette"])

	var survivors := DemotionFleetBuilder.pick_survivors(lost.ships, lost.groups, _rng())

	for ship in survivors["ships"]:
		assert_eq(ship["status"], "operational", "Survivors fly again")
		for section in ship["armor_sections"]:
			assert_gt(int(section["current_armor"]), 0, "Survivor armor is not zeroed")
			assert_lt(int(section["current_armor"]), int(section["max_armor"]),
				"Survivor armor stays below maximum")
		for component in ship["internals"]:
			assert_gt(int(component["current_health"]), 0,
				"Survivor components are not destroyed")
			assert_lt(int(component["current_health"]), int(component["max_health"]),
				"Survivor components stay below maximum")
			assert_ne(component["status"], "destroyed",
				"No survivor component remains destroyed")


func test_survivor_crews_match_ship_types_and_keep_identity():
	var lost := _lost_fleet(["fighter", "fighter", "corvette"])
	var lost_crew_ids: Array = []
	for group in lost.groups:
		for member in group["crew"]:
			lost_crew_ids.append(member["crew_id"])

	var survivors := DemotionFleetBuilder.pick_survivors(lost.ships, lost.groups, _rng())

	var survivor_types: Array = survivors["ships"].map(func(s): return s["type"])
	for group in survivors["crew_groups"]:
		assert_has(survivor_types, group["ship_type"],
			"Carried crew groups match a surviving ship's type")
		for member in group["crew"]:
			assert_has(lost_crew_ids, member["crew_id"],
				"Carried crew keep their crew_id")
			assert_true(member["callsign"].begins_with("CALLSIGN_"),
				"Carried crew keep their callsign")
			assert_has(member["known_patterns"], "pattern_a",
				"Carried crew keep their learned patterns")


func test_inputs_are_not_mutated():
	var lost := _lost_fleet(["fighter"])
	var groups_before: String = JSON.stringify(lost.groups)

	DemotionFleetBuilder.pick_survivors(lost.ships, lost.groups, _rng())

	assert_eq(lost.ships[0]["status"], "destroyed",
		"The lost fleet's final state is left untouched")
	assert_eq(JSON.stringify(lost.groups), groups_before,
		"The lost crew groups are left untouched")
