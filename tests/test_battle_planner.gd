extends GutTest

## Tests for BattlePlanner.build_default_plan - FUNCTIONALITY ONLY.
## Validates the planner's contract (one entry per ship, distinct quadrants
## per squadron, sides separated, large ships get larger patrol radius)
## without depending on specific data values.

const BATTLEFIELD_SIZE := Vector2(5000.0, 3500.0)


func _make_fleet(counts: Dictionary) -> Dictionary:
	var fleet := {}
	for ship_type in FleetDataManager.SHIP_TYPES:
		fleet[ship_type] = counts.get(ship_type, 0)
	return fleet


func _entries_for_team(entries: Array, team: int) -> Array:
	var out: Array = []
	for entry in entries:
		if int(entry["team"]) == team:
			out.append(entry)
	return out


func _ship_count(fleet: Dictionary) -> int:
	var total := 0
	for ship_type in fleet.keys():
		total += int(fleet[ship_type])
	return total


# ============================================================================
# Entry count
# ============================================================================

func test_one_entry_per_ship_in_fleets():
	var team0 := _make_fleet({"fighter": 2, "corvette": 1})
	var team1 := _make_fleet({"fighter": 1, "capital": 1})
	var entries := BattlePlanner.build_default_plan(team0, team1, BATTLEFIELD_SIZE)
	assert_eq(entries.size(), _ship_count(team0) + _ship_count(team1),
		"Plan should have one entry per ship across both fleets")


func test_empty_fleets_produce_empty_plan():
	var team0 := _make_fleet({})
	var team1 := _make_fleet({})
	var entries := BattlePlanner.build_default_plan(team0, team1, BATTLEFIELD_SIZE)
	assert_eq(entries.size(), 0, "Empty fleets should yield an empty plan")


# ============================================================================
# Quadrant assignment per squadron
# ============================================================================

func test_each_squadron_gets_distinct_patrol_quadrant_within_team():
	# Up to two squadrons per team fit into distinct quadrants (the planner
	# steps by QUADRANT_STEP across PATROL_QUADRANT_DIRS).
	var team0 := _make_fleet({"fighter": 2, "corvette": 1})
	var entries := BattlePlanner.build_default_plan(team0, _make_fleet({}), BATTLEFIELD_SIZE)
	var team0_entries := _entries_for_team(entries, 0)

	# Group entries by ship_type (each ship_type === one squadron) and check
	# that distinct squadrons land on distinct patrol_centers.
	var squadron_centers: Dictionary = {}
	for entry in team0_entries:
		var ship_type: String = entry["ship_type"]
		var center: Vector2 = entry["patrol_center"]
		if squadron_centers.has(ship_type):
			assert_eq(squadron_centers[ship_type], center,
				"All ships of one squadron should share a patrol center")
		else:
			squadron_centers[ship_type] = center

	var unique_centers: Dictionary = {}
	for ship_type in squadron_centers.keys():
		unique_centers[squadron_centers[ship_type]] = true
	assert_eq(unique_centers.size(), squadron_centers.size(),
		"Distinct squadrons should patrol distinct quadrants")


# ============================================================================
# Position bounds
# ============================================================================

func test_all_positions_within_battlefield_x_margin():
	# The planner pins x to the team's edge; y is bounded by the fleet
	# spawn calculator. Positions should never escape the battlefield.
	var team0 := _make_fleet({"fighter": 3, "capital": 1})
	var team1 := _make_fleet({"corvette": 2, "fighter": 1})
	var entries := BattlePlanner.build_default_plan(team0, team1, BATTLEFIELD_SIZE)

	for entry in entries:
		var pos: Vector2 = entry["position"]
		assert_gte(pos.x, 0.0, "x should be non-negative")
		assert_lte(pos.x, BATTLEFIELD_SIZE.x, "x should not exceed battlefield width")
		assert_gte(pos.y, 0.0, "y should be non-negative")
		assert_lte(pos.y, BATTLEFIELD_SIZE.y, "y should not exceed battlefield height")


# ============================================================================
# Team separation
# ============================================================================

func test_team_zero_spawns_left_of_team_one():
	var team0 := _make_fleet({"fighter": 2, "corvette": 1})
	var team1 := _make_fleet({"fighter": 2, "capital": 1})
	var entries := BattlePlanner.build_default_plan(team0, team1, BATTLEFIELD_SIZE)

	var max_team0_x: float = -INF
	var min_team1_x: float = INF
	for entry in entries:
		var x: float = float(entry["position"].x)
		if int(entry["team"]) == 0:
			max_team0_x = max(max_team0_x, x)
		else:
			min_team1_x = min(min_team1_x, x)

	assert_lt(max_team0_x, min_team1_x,
		"Team 0 ships should spawn to the left of team 1 ships")


# ============================================================================
# Patrol radius scales with ship class
# ============================================================================

func test_large_ships_have_larger_patrol_radius_than_small_ships():
	var team0 := _make_fleet({"fighter": 1, "capital": 1})
	var entries := BattlePlanner.build_default_plan(team0, _make_fleet({}), BATTLEFIELD_SIZE)

	var small_radius: float = -1.0
	var large_radius: float = -1.0
	for entry in entries:
		var ship_type: String = entry["ship_type"]
		if FleetDataManager.is_large_ship(ship_type):
			large_radius = float(entry["patrol_radius"])
		else:
			small_radius = float(entry["patrol_radius"])

	assert_gt(large_radius, small_radius,
		"Large ships should patrol a larger zone than small ships")


# ============================================================================
# Entry shape
# ============================================================================

func test_entries_carry_all_required_keys():
	var team0 := _make_fleet({"fighter": 1})
	var entries := BattlePlanner.build_default_plan(team0, _make_fleet({}), BATTLEFIELD_SIZE)
	assert_eq(entries.size(), 1)
	var entry: Dictionary = entries[0]
	for key in ["ship_type", "team", "position", "patrol_center", "patrol_radius", "hull_length"]:
		assert_true(entry.has(key), "Entry should expose `%s`" % key)
	assert_gt(float(entry["hull_length"]), 0.0,
		"hull_length should be a positive size used for hit-testing")
