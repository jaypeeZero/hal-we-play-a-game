extends GutTest

## Behavior tests for FormationSystem.assign_slots() and slot_offset().
##
## All tests build synthetic ship arrays; no game state is touched.
## Assertions are geometric / relational — not tied to specific const values
## so tuning FormationSystem's consts does not break the suite.

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Minimal operational ship for formation testing.
func _make_ship(
	ship_id: String,
	team: int,
	pos: Vector2,
	shape: String = "line_abreast",
	duty: String  = "support"
) -> Dictionary:
	return {
		"ship_id":  ship_id,
		"team":     team,
		"position": pos,
		"status":   "operational",
		"crew": [
			{
				"crew_id": "c_%s" % ship_id,
				"tactics": {
					"shape":   shape,
					"spacing": 0.5,
					"depth":   0.5,
					"duty":    duty,
					"role":    "brawler",
				},
			}
		],
		"orders": {
			"formation_slot":  Vector2.ZERO,
			"anchor_position": Vector2.ZERO,
		},
	}

## Build a two-team fleet: team 0 at own_center, team 1 at enemy_center.
## each team has `count` ships spaced 100 units apart along Y from their center.
func _make_fleet(
	own_center: Vector2,
	enemy_center: Vector2,
	count: int,
	own_shape: String  = "line_abreast",
	own_spacing: float = 0.5
) -> Array:
	var ships: Array = []
	for i in range(count):
		var offset := Vector2(0, float(i) * 100.0)
		var s := _make_ship("own_%d" % i, 0, own_center + offset, own_shape)
		# Override spacing in tactics
		s["crew"][0]["tactics"]["spacing"] = own_spacing
		ships.append(s)
	for i in range(count):
		var offset := Vector2(0, float(i) * 100.0)
		ships.append(_make_ship("enemy_%d" % i, 1, enemy_center + offset))
	return ships


## Extract the own-team (team 0) ships from an assign_slots() result.
func _own_ships(result: Array) -> Array:
	return result.filter(func(s): return s.get("team", -1) == 0)


## Vector2 spread of positions along a given axis direction.
## Returns the range (max - min) of the projection onto `axis`.
func _spread_along(ships: Array, axis: Vector2) -> float:
	if ships.is_empty():
		return 0.0
	var projections: Array = ships.map(
		func(s): return s["orders"]["formation_slot"].dot(axis)
	)
	return projections.max() - projections.min()


# ---------------------------------------------------------------------------
# 1. anchor_position == enemy centroid
# ---------------------------------------------------------------------------

func test_anchor_position_equals_enemy_centroid():
	# Enemy team (1) at known positions; anchor must be their average.
	var fleet := _make_fleet(Vector2.ZERO, Vector2(3000, 0), 3)
	var result := FormationSystem.assign_slots(fleet)
	var own := _own_ships(result)
	assert_false(own.is_empty(), "own ships must be present")

	# Enemy centroid: team 1 ships at (3000,0), (3000,100), (3000,200)
	var expected_anchor := Vector2(3000.0, 100.0)   # centroid of 3 ships
	for s in own:
		var anchor: Vector2 = s["orders"]["anchor_position"]
		assert_almost_eq(anchor.x, expected_anchor.x, 1.0, "anchor.x must match enemy centroid")
		assert_almost_eq(anchor.y, expected_anchor.y, 1.0, "anchor.y must match enemy centroid")


# ---------------------------------------------------------------------------
# 2. Wall / line_abreast: ships spread along perp, low spread along axis
# ---------------------------------------------------------------------------

func test_wall_ships_spread_along_perp_not_axis():
	# Team 0 at origin, team 1 far right → axis = +X, perp = +Y.
	# Wall formation: ships should spread along Y (perp), not along X (axis).
	var fleet := _make_fleet(Vector2.ZERO, Vector2(4000, 0), 5, "wall")
	var result := FormationSystem.assign_slots(fleet)
	var own := _own_ships(result)

	var axis := Vector2(1, 0)   # toward enemy
	var perp := Vector2(0, 1)   # perpendicular

	var spread_perp: float = _spread_along(own, perp)
	var spread_axis: float = _spread_along(own, axis)

	assert_gt(spread_perp, spread_axis,
		"Wall formation must spread more along perp than along the axis-to-enemy")


func test_line_abreast_ships_spread_along_perp_not_axis():
	var fleet := _make_fleet(Vector2.ZERO, Vector2(4000, 0), 4, "line_abreast")
	var result := FormationSystem.assign_slots(fleet)
	var own := _own_ships(result)

	var axis := Vector2(1, 0)
	var perp := Vector2(0, 1)
	var spread_perp: float = _spread_along(own, perp)
	var spread_axis: float = _spread_along(own, axis)

	assert_gt(spread_perp, spread_axis,
		"line_abreast must spread more along perp than axis")


# ---------------------------------------------------------------------------
# 3. Wedge: V-shape — lead ship furthest forward; spread along both axis + perp
# ---------------------------------------------------------------------------

func test_wedge_lead_ship_is_furthest_toward_enemy():
	# Team 0 at origin, enemy far right → axis = +X. Ship "own_0" is sorted first
	# alphabetically and gets index 0 (the lead slot).
	var fleet := _make_fleet(Vector2.ZERO, Vector2(4000, 0), 5, "wedge")
	var result := FormationSystem.assign_slots(fleet)
	var own := _own_ships(result)

	var axis := Vector2(1, 0)

	# Find the slot with the maximum projection onto axis (furthest forward)
	var max_proj: float = -INF
	var max_ship: Dictionary = {}
	for s in own:
		var proj: float = s["orders"]["formation_slot"].dot(axis)
		if proj > max_proj:
			max_proj = proj
			max_ship = s

	# The lead ship (index 0 in sorted order = "own_0") must be furthest forward
	assert_eq(max_ship.get("ship_id", ""), "own_0",
		"Wedge lead ship (own_0, sorted first) must be furthest toward the enemy")


func test_wedge_spreads_along_both_axis_and_perp():
	# Wedge must have significant spread along both axis (depth of V)
	# and perp (width of arms) — unlike wall which spreads only along perp.
	var fleet := _make_fleet(Vector2.ZERO, Vector2(4000, 0), 5, "wedge")
	var result := FormationSystem.assign_slots(fleet)
	var own := _own_ships(result)

	var axis := Vector2(1, 0)
	var perp := Vector2(0, 1)
	var spread_axis: float = _spread_along(own, axis)
	var spread_perp: float = _spread_along(own, perp)

	# Both spreads must be substantial — the V has arms in both directions
	assert_gt(spread_axis, 50.0,
		"Wedge must have significant depth (spread along axis)")
	assert_gt(spread_perp, 50.0,
		"Wedge must have significant width (spread along perp)")


func test_wedge_axis_spread_greater_than_wall_axis_spread():
	# A wedge's depth (spread along axis) must exceed a wall's depth
	# — that's the core geometric difference between the two shapes.
	var fleet_wall  := _make_fleet(Vector2.ZERO, Vector2(4000, 0), 5, "wall")
	var fleet_wedge := _make_fleet(Vector2.ZERO, Vector2(4000, 0), 5, "wedge")
	var own_wall  := _own_ships(FormationSystem.assign_slots(fleet_wall))
	var own_wedge := _own_ships(FormationSystem.assign_slots(fleet_wedge))

	var axis := Vector2(1, 0)
	assert_gt(
		_spread_along(own_wedge, axis),
		_spread_along(own_wall,  axis),
		"Wedge must have more depth along the enemy axis than a wall"
	)


# ---------------------------------------------------------------------------
# 4. Spacing dial increases inter-ship separation
# ---------------------------------------------------------------------------

func test_wider_spacing_increases_inter_ship_separation():
	var fleet_tight := _make_fleet(Vector2.ZERO, Vector2(4000, 0), 4, "wall", 0.0)
	var fleet_loose := _make_fleet(Vector2.ZERO, Vector2(4000, 0), 4, "wall", 1.0)
	var own_tight := _own_ships(FormationSystem.assign_slots(fleet_tight))
	var own_loose := _own_ships(FormationSystem.assign_slots(fleet_loose))

	var perp := Vector2(0, 1)
	assert_gt(
		_spread_along(own_loose, perp),
		_spread_along(own_tight, perp),
		"spacing=1 (loose) must produce wider inter-ship separation than spacing=0 (tight)"
	)


# ---------------------------------------------------------------------------
# 5. Slots rotate when enemy moves to a new bearing
# ---------------------------------------------------------------------------

func test_slots_rotate_when_enemy_bearing_changes():
	# Scenario A: enemy to the right (+X). Wall should spread along Y.
	# Scenario B: enemy above (+Y). Wall should spread along X.
	# The spread axis must rotate with the enemy bearing.
	var count := 4

	# Scenario A
	var fleet_a := _make_fleet(Vector2.ZERO, Vector2(4000, 0), count, "wall")
	var own_a   := _own_ships(FormationSystem.assign_slots(fleet_a))
	var spread_ax: float = _spread_along(own_a, Vector2(1, 0))
	var spread_ay: float = _spread_along(own_a, Vector2(0, 1))

	# Scenario B
	var fleet_b := _make_fleet(Vector2.ZERO, Vector2(0, 4000), count, "wall")
	var own_b   := _own_ships(FormationSystem.assign_slots(fleet_b))
	var spread_bx: float = _spread_along(own_b, Vector2(1, 0))
	var spread_by: float = _spread_along(own_b, Vector2(0, 1))

	# In scenario A: wall spreads along Y more than X
	assert_gt(spread_ay, spread_ax,
		"With enemy to the right, wall must spread more along Y (perp)")

	# In scenario B: wall spreads along X more than Y (rotated 90°)
	assert_gt(spread_bx, spread_by,
		"With enemy above, wall must spread more along X (perp to new axis)")


# ---------------------------------------------------------------------------
# 6. assign_slots returns a NEW array (inputs not mutated)
# ---------------------------------------------------------------------------

func test_assign_slots_does_not_mutate_input():
	var fleet: Array  = _make_fleet(Vector2.ZERO, Vector2(3000, 0), 3)
	var before: Vector2 = fleet[0]["orders"]["formation_slot"]
	FormationSystem.assign_slots(fleet)
	var after: Vector2 = fleet[0]["orders"]["formation_slot"]
	assert_eq(before, after,
		"assign_slots must not mutate input ships — it returns a copy")


# ---------------------------------------------------------------------------
# 7. Destroyed / non-operational ships are excluded from formation
# ---------------------------------------------------------------------------

func test_destroyed_ships_not_assigned_slots():
	var fleet := _make_fleet(Vector2.ZERO, Vector2(3000, 0), 3)
	# Mark one own-team ship as destroyed
	fleet[1]["status"] = "destroyed"
	var result := FormationSystem.assign_slots(fleet)
	# The destroyed ship's slot must remain ZERO (it was never assigned)
	var destroyed: Dictionary = result[1]
	assert_eq(destroyed["orders"]["formation_slot"], Vector2.ZERO,
		"Destroyed ships must not be assigned a formation slot")


# ---------------------------------------------------------------------------
# 8. slot_offset — wall vs wedge geometry (unit tests)
# ---------------------------------------------------------------------------

func test_wall_offset_is_flat_line():
	# All wall slots should have the same y (axis) component — it's a flat line.
	var count := 5
	var sep   := 300.0
	var ys: Array = []
	for i in range(count):
		var off: Vector2 = FormationSystem.slot_offset("wall", i, count, 0.5, 0.5, "brawler")
		ys.append(off.y)
	# All y values should be equal (the same rear offset)
	var min_y: float = ys.min()
	var max_y: float = ys.max()
	assert_almost_eq(min_y, max_y, 0.1,
		"Wall slots must all have the same y (axis) component — it's a flat line")


func test_wedge_index0_is_furthest_forward():
	# Index 0 (lead ship) must have a greater y than all other slots.
	var count := 5
	var lead: Vector2 = FormationSystem.slot_offset("wedge", 0, count, 0.5, 0.5, "brawler")
	for i in range(1, count):
		var arm: Vector2 = FormationSystem.slot_offset("wedge", i, count, 0.5, 0.5, "brawler")
		assert_gt(lead.y, arm.y,
			"Wedge index 0 (lead) must be further forward (higher y) than arm ship %d" % i)


func test_wall_perp_spread_is_symmetric():
	# Wall must be symmetric about the axis: lateral values mirror around 0.
	var count := 4
	var laterals: Array = []
	for i in range(count):
		var off: Vector2 = FormationSystem.slot_offset("wall", i, count, 0.5, 0.5, "brawler")
		laterals.append(off.x)
	var total: float = 0.0
	for v in laterals:
		total += v
	assert_almost_eq(total, 0.0, 1.0,
		"Wall lateral offsets must sum to ~0 (centered on the axis)")
