extends GutTest

## Tests for TacticsTelemetry — BEHAVIOR ONLY.
##
## Each test establishes a synthetic geometric scenario and asserts that the
## metric responds in the expected direction. Tests never assert exact float
## values (those would break if CENTER_SECTOR_HALF_WIDTH or other constants
## changed); they assert ordering and boundary properties.

# ---------------------------------------------------------------------------
# HELPERS — minimal ship dicts (only the fields TacticsTelemetry reads)
# ---------------------------------------------------------------------------

## Build a bare ship dict. `target_id` is what goes in orders.target_id.
func _ship(id: String, team: int, pos: Vector2, target_id: String = "") -> Dictionary:
	return {
		"ship_id": id,
		"team": team,
		"position": pos,
		"status": "operational",
		"orders": {"target_id": target_id, "current_order": ""},
	}

func _destroyed_ship(id: String, team: int, pos: Vector2) -> Dictionary:
	var s := _ship(id, team, pos)
	s["status"] = "destroyed"
	return s

# ---------------------------------------------------------------------------
# CENTROID HELPERS
# ---------------------------------------------------------------------------

func test_team_centroid_is_mean_position_of_team():
	var ships := [
		_ship("a", 0, Vector2(0, 0)),
		_ship("b", 0, Vector2(100, 0)),
		_ship("c", 1, Vector2(9999, 9999)),  # enemy — must not affect result
	]
	var c := TacticsTelemetry.team_centroid(ships, 0)
	assert_eq(c, Vector2(50, 0), "Centroid should be mean of team 0 positions")

func test_team_centroid_ignores_destroyed_ships():
	var ships := [
		_ship("a", 0, Vector2(0, 0)),
		_destroyed_ship("b", 0, Vector2(9999, 9999)),
	]
	var c := TacticsTelemetry.team_centroid(ships, 0)
	assert_eq(c, Vector2(0, 0), "Destroyed ships should not skew centroid")

func test_team_centroid_returns_zero_when_team_empty():
	var ships := [_ship("e", 1, Vector2(100, 100))]
	var c := TacticsTelemetry.team_centroid(ships, 0)
	assert_eq(c, Vector2.ZERO, "Empty team centroid should be Vector2.ZERO")

func test_enemy_centroid_excludes_own_team():
	var ships := [
		_ship("a", 0, Vector2(0, 0)),
		_ship("b", 1, Vector2(200, 0)),
		_ship("c", 1, Vector2(400, 0)),
	]
	var c := TacticsTelemetry.enemy_centroid(ships, 0)
	assert_eq(c, Vector2(300, 0), "Enemy centroid should be mean of team 1 positions")

# ---------------------------------------------------------------------------
# MEAN ENGAGEMENT RANGE
# ---------------------------------------------------------------------------

func test_engagement_range_rises_when_ships_farther_from_targets():
	# Close scenario: team 0 ships adjacent to their targets.
	var close_ships := [
		_ship("a0", 0, Vector2(10, 0), "e1"),
		_ship("e1", 1, Vector2(20, 0)),
	]
	# Far scenario: same pairing but 1000 units apart.
	var far_ships := [
		_ship("a0", 0, Vector2(0, 0), "e1"),
		_ship("e1", 1, Vector2(1000, 0)),
	]
	var close_range := TacticsTelemetry.mean_engagement_range(close_ships, 0)
	var far_range   := TacticsTelemetry.mean_engagement_range(far_ships, 0)
	assert_lt(close_range, far_range,
		"Engagement range should be greater when ships are farther from their targets")

func test_engagement_range_falls_back_to_nearest_enemy_when_no_target_id():
	# Ship has no target_id; nearest enemy is 50 units away.
	var ships := [
		_ship("a0", 0, Vector2(0, 0)),   # no target_id
		_ship("e1", 1, Vector2(50, 0)),
	]
	var r := TacticsTelemetry.mean_engagement_range(ships, 0)
	assert_almost_eq(r, 50.0, 0.1,
		"Fallback to nearest enemy: range should equal the distance to that enemy")

func test_engagement_range_is_zero_when_no_enemies():
	var ships := [_ship("a0", 0, Vector2(0, 0)), _ship("a1", 0, Vector2(100, 0))]
	var r := TacticsTelemetry.mean_engagement_range(ships, 0)
	assert_eq(r, 0.0, "No enemies means no engagement range")

# ---------------------------------------------------------------------------
# FORMATION DISPERSION
# ---------------------------------------------------------------------------

func test_clustered_ships_yield_lower_dispersion_than_scattered():
	# Tight cluster: all within 10 units of each other.
	var tight := [
		_ship("a", 0, Vector2(0, 0)),
		_ship("b", 0, Vector2(5, 0)),
		_ship("c", 0, Vector2(-5, 0)),
	]
	# Scattered: same count but spread 500 units apart.
	var scattered := [
		_ship("a", 0, Vector2(0, 0)),
		_ship("b", 0, Vector2(500, 0)),
		_ship("c", 0, Vector2(-500, 0)),
	]
	var d_tight    := TacticsTelemetry.formation_dispersion(tight, 0)
	var d_scattered := TacticsTelemetry.formation_dispersion(scattered, 0)
	assert_lt(d_tight, d_scattered,
		"Tight cluster should have lower dispersion than scattered ships")

func test_single_ship_dispersion_is_zero():
	var ships := [_ship("a", 0, Vector2(100, 200))]
	assert_eq(TacticsTelemetry.formation_dispersion(ships, 0), 0.0,
		"A single ship is its own centroid: dispersion is 0")

func test_dispersion_ignores_destroyed_ships():
	# One active ship at origin, one destroyed ship far away.
	var ships := [
		_ship("a", 0, Vector2(0, 0)),
		_destroyed_ship("b", 0, Vector2(9999, 0)),
	]
	assert_eq(TacticsTelemetry.formation_dispersion(ships, 0), 0.0,
		"Destroyed ships must not inflate dispersion")

# ---------------------------------------------------------------------------
# FOCUS CONCENTRATION (HHI)
# ---------------------------------------------------------------------------

func test_all_targeting_same_enemy_yields_near_one_concentration():
	var ships := [
		_ship("a", 0, Vector2(0, 0), "e1"),
		_ship("b", 0, Vector2(0, 10), "e1"),
		_ship("c", 0, Vector2(0, 20), "e1"),
		_ship("e1", 1, Vector2(500, 0)),
	]
	var hhi := TacticsTelemetry.focus_concentration(ships, 0)
	assert_almost_eq(hhi, 1.0, 0.01,
		"All ships targeting one enemy should yield concentration ≈ 1.0")

func test_spread_targeting_yields_lower_concentration_than_focused():
	# Three ships each targeting a different enemy.
	var spread := [
		_ship("a", 0, Vector2(0, 0), "e1"),
		_ship("b", 0, Vector2(0, 10), "e2"),
		_ship("c", 0, Vector2(0, 20), "e3"),
		_ship("e1", 1, Vector2(500, 0)),
		_ship("e2", 1, Vector2(500, 100)),
		_ship("e3", 1, Vector2(500, 200)),
	]
	# Same three ships all on one target.
	var focused := [
		_ship("a", 0, Vector2(0, 0), "e1"),
		_ship("b", 0, Vector2(0, 10), "e1"),
		_ship("c", 0, Vector2(0, 20), "e1"),
		_ship("e1", 1, Vector2(500, 0)),
	]
	var hhi_spread  := TacticsTelemetry.focus_concentration(spread, 0)
	var hhi_focused := TacticsTelemetry.focus_concentration(focused, 0)
	assert_lt(hhi_spread, hhi_focused,
		"Spread targeting should yield lower concentration than focused fire")

func test_concentration_is_zero_when_no_targets_set():
	var ships := [
		_ship("a", 0, Vector2(0, 0)),  # no target_id
		_ship("b", 0, Vector2(0, 10)), # no target_id
		_ship("e1", 1, Vector2(500, 0)),
	]
	assert_eq(TacticsTelemetry.focus_concentration(ships, 0), 0.0,
		"No target ids set: concentration should be 0.0")

func test_two_targeting_same_two_targeting_different_is_between_extremes():
	# Two ships on e1, one on e2 → HHI = (2/3)² + (1/3)² = 4/9 + 1/9 = 5/9 ≈ 0.556
	var ships := [
		_ship("a", 0, Vector2(0, 0), "e1"),
		_ship("b", 0, Vector2(0, 10), "e1"),
		_ship("c", 0, Vector2(0, 20), "e2"),
		_ship("e1", 1, Vector2(500, 0)),
		_ship("e2", 1, Vector2(500, 100)),
	]
	var hhi := TacticsTelemetry.focus_concentration(ships, 0)
	# Must be strictly between equal-spread (1/3 per 3 targets = 1/3) and full focus (1.0).
	# Actually with 2 targets the minimum HHI is 0.5 (50/50 split).
	assert_gt(hhi, 0.0, "Partial focus should yield positive concentration")
	assert_lt(hhi, 1.0, "Partial focus should yield sub-1.0 concentration")

# ---------------------------------------------------------------------------
# SECTOR MASS DISTRIBUTION
# ---------------------------------------------------------------------------

func test_ships_on_right_side_produce_right_weighted_distribution():
	# Geometry: team centroid = (0,0), anchor directly north at (0,1000).
	# axis = (0,1000), right-perp = (1,0) (east).
	# One ship far east (+600,0) → lateral = 600 > CENTER_SECTOR_HALF_WIDTH → "right".
	# One ship far west (-600,0) → lateral = -600 < -CENTER_SECTOR_HALF_WIDTH → "left".
	# Centroid of these two = (0,0) ✓.
	var ships := [
		_ship("r", 0, Vector2( 600, 0)),
		_ship("l", 0, Vector2(-600, 0)),
		_ship("e1", 1, Vector2(0, 1000)),
	]
	var anchor := Vector2(0, 1000)  # explicit, not computed from ships to stay clear
	var dist := TacticsTelemetry.sector_mass_distribution(ships, 0, anchor)
	assert_almost_eq(dist["right"],  0.5, 0.001, "East ship should be in right sector")
	assert_almost_eq(dist["left"],   0.5, 0.001, "West ship should be in left sector")
	assert_almost_eq(dist["center"], 0.0, 0.001, "No ship on the axis itself")
	assert_almost_eq(dist["left"] + dist["center"] + dist["right"], 1.0, 0.001,
		"Sector fractions must sum to 1.0")

func test_ships_on_axis_are_in_center_sector():
	# Team 0 ships sit exactly on the axis team→enemy (same X, varying Y).
	# Centroid = (0,0), anchor = (0,1000) → axis = (0,1000), right-perp = (1,0).
	# All ships have offset.dot(right_perp) = 0 → they fall in center.
	var ships := [
		_ship("a", 0, Vector2(0, -50)),
		_ship("b", 0, Vector2(0,  50)),
		_ship("e1", 1, Vector2(0, 1000)),
	]
	var anchor := TacticsTelemetry.enemy_centroid(ships, 0)
	var dist := TacticsTelemetry.sector_mass_distribution(ships, 0, anchor)
	assert_almost_eq(dist["center"], 1.0, 0.001,
		"Ships on the team→enemy axis should all be in the center sector")

func test_sector_fractions_always_sum_to_one():
	# Arbitrary asymmetric layout.
	var ships := [
		_ship("a", 0, Vector2(-200, 10)),
		_ship("b", 0, Vector2(300, -50)),
		_ship("c", 0, Vector2(0, 0)),
		_ship("e1", 1, Vector2(0, 800)),
		_ship("e2", 1, Vector2(100, 900)),
	]
	var anchor := TacticsTelemetry.enemy_centroid(ships, 0)
	var dist := TacticsTelemetry.sector_mass_distribution(ships, 0, anchor)
	assert_almost_eq(dist["left"] + dist["center"] + dist["right"], 1.0, 0.001,
		"Sector fractions must sum to 1.0 for any layout")

# ---------------------------------------------------------------------------
# SNAPSHOT
# ---------------------------------------------------------------------------

func test_snapshot_contains_all_required_keys():
	var ships := [
		_ship("a", 0, Vector2(0, 0), "e1"),
		_ship("e1", 1, Vector2(200, 0)),
	]
	var snap := TacticsTelemetry.snapshot(ships, 0)
	assert_has(snap, "team",                   "snapshot must have 'team'")
	assert_has(snap, "mean_engagement_range",  "snapshot must have 'mean_engagement_range'")
	assert_has(snap, "formation_dispersion",   "snapshot must have 'formation_dispersion'")
	assert_has(snap, "focus_concentration",    "snapshot must have 'focus_concentration'")
	assert_has(snap, "sector_mass_distribution", "snapshot must have 'sector_mass_distribution'")

func test_snapshot_sector_distribution_keys_present():
	var ships := [
		_ship("a", 0, Vector2(0, 0)),
		_ship("e1", 1, Vector2(200, 0)),
	]
	var snap := TacticsTelemetry.snapshot(ships, 0)
	var smd: Dictionary = snap["sector_mass_distribution"]
	assert_has(smd, "left",   "sector_mass_distribution must have 'left'")
	assert_has(smd, "center", "sector_mass_distribution must have 'center'")
	assert_has(smd, "right",  "sector_mass_distribution must have 'right'")

func test_snapshot_does_not_mutate_input():
	var ships := [
		_ship("a", 0, Vector2(0, 0), "e1"),
		_ship("e1", 1, Vector2(200, 0)),
	]
	var pos_before: Vector2 = ships[0].position
	TacticsTelemetry.snapshot(ships, 0)
	assert_eq(ships[0].position, pos_before,
		"snapshot() must not mutate the ships array")
