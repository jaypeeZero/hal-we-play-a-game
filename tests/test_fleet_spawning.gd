extends GutTest

## Tests for fleet spawning - validates ships spawn with proper spacing
## Tests call ShipData.calculate_fleet_spawn_positions() - the REAL code

const BATTLEFIELD_HEIGHT := 1080.0
const BASE_X := 200.0


# ============================================================================
# HELPER - Check no ships overlap based on hull lengths
# ============================================================================

func _assert_no_overlaps(positions: Array, context: String) -> void:
	for i in range(positions.size()):
		for j in range(i + 1, positions.size()):
			var ship1 = positions[i]
			var ship2 = positions[j]
			var distance = abs(ship2["position"].y - ship1["position"].y)
			# size field now contains hull length, so min required is half of each
			var min_required = (ship1["size"] + ship2["size"]) / 2.0

			assert_gt(distance, min_required,
				"%s: %s and %s overlap! distance=%.0f, need=%.0f" % [
					context, ship1["type"], ship2["type"], distance, min_required
				])


# ============================================================================
# TESTS - Hull length extraction
# ============================================================================

func test_capital_hull_length_is_648():
	var length = ShipData.get_hull_length("capital")
	assert_almost_eq(length, 648.0, 1.0, "Capital hull length should be ~648 (y: -540 to +108)")


func test_corvette_hull_length_is_216():
	var length = ShipData.get_hull_length("corvette")
	assert_almost_eq(length, 216.0, 1.0, "Corvette hull length should be ~216 (y: -108 to +108)")


# ============================================================================
# TESTS - Ships must not overlap
# ============================================================================

func test_two_capitals_do_not_overlap():
	var fleet := {"fighter": 0, "heavy_fighter": 0, "corvette": 0, "capital": 2}
	var positions = ShipData.calculate_fleet_spawn_positions(fleet, BASE_X, BATTLEFIELD_HEIGHT)

	assert_eq(positions.size(), 2, "Should have 2 ships")
	_assert_no_overlaps(positions, "2 capitals")


func test_three_capitals_do_not_overlap():
	var fleet := {"fighter": 0, "heavy_fighter": 0, "corvette": 0, "capital": 3}
	var positions = ShipData.calculate_fleet_spawn_positions(fleet, BASE_X, BATTLEFIELD_HEIGHT)

	assert_eq(positions.size(), 3, "Should have 3 ships")
	_assert_no_overlaps(positions, "3 capitals")


func test_two_corvettes_do_not_overlap():
	var fleet := {"fighter": 0, "heavy_fighter": 0, "corvette": 2, "capital": 0}
	var positions = ShipData.calculate_fleet_spawn_positions(fleet, BASE_X, BATTLEFIELD_HEIGHT)

	assert_eq(positions.size(), 2, "Should have 2 ships")
	_assert_no_overlaps(positions, "2 corvettes")


func test_mixed_fleet_no_overlap():
	var fleet := {"fighter": 2, "heavy_fighter": 1, "corvette": 1, "capital": 2}
	var positions = ShipData.calculate_fleet_spawn_positions(fleet, BASE_X, BATTLEFIELD_HEIGHT)

	assert_eq(positions.size(), 6, "Should have 6 ships")
	_assert_no_overlaps(positions, "mixed fleet")


func test_large_fleet_no_overlap():
	var fleet := {"fighter": 4, "heavy_fighter": 2, "corvette": 2, "capital": 2}
	var positions = ShipData.calculate_fleet_spawn_positions(fleet, BASE_X, BATTLEFIELD_HEIGHT)

	assert_eq(positions.size(), 10, "Should have 10 ships")
	_assert_no_overlaps(positions, "large fleet")
