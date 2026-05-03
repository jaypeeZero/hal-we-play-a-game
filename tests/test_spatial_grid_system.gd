extends GutTest

## Behavior tests for SpatialGridSystem
## Tests the contract: query_radius returns all entities within radius
## (a superset is allowed; misses are not).

const CELL_SIZE := 256.0

func _make_entity(id: String, pos: Vector2) -> Dictionary:
	return {"id": id, "position": pos}

# ============================================================================
# BUILD
# ============================================================================

func test_build_empty_returns_empty_grid():
	var grid = SpatialGridSystem.build([], CELL_SIZE)

	# An empty entity list still yields a queryable (empty-result) grid.
	var hits = SpatialGridSystem.query_radius(grid, Vector2.ZERO, 1000.0)
	assert_eq(hits.size(), 0)

func test_build_skips_null_entities():
	var entities = [_make_entity("a", Vector2(0, 0)), null, _make_entity("b", Vector2(10, 10))]
	var grid = SpatialGridSystem.build(entities, CELL_SIZE)

	var hits = SpatialGridSystem.query_radius(grid, Vector2.ZERO, 100.0)
	assert_eq(hits.size(), 2, "Null entities should be ignored")

func test_build_buckets_distant_entities_into_different_cells():
	var near = _make_entity("near", Vector2(0, 0))
	var far = _make_entity("far", Vector2(10000, 10000))
	var grid = SpatialGridSystem.build([near, far], CELL_SIZE)

	# Query near origin with a small radius — far entity must not appear.
	var hits = SpatialGridSystem.query_radius(grid, Vector2.ZERO, 10.0)
	var ids = hits.map(func(e): return e.id)
	assert_true(ids.has("near"))
	assert_false(ids.has("far"), "Far entity should not appear in tight near-origin query")

# ============================================================================
# QUERY: Correctness vs brute-force reference
# ============================================================================

func _brute_force_within(entities: Array, position: Vector2, radius: float) -> Array:
	var result: Array = []
	for entity in entities:
		if entity == null:
			continue
		if position.distance_to(entity.position) <= radius:
			result.append(entity)
	return result

func test_query_radius_returns_superset_of_brute_force():
	# Scattered entities; the grid result must contain every brute-force hit.
	var entities: Array = []
	var seed := 1337
	for i in range(50):
		seed = (seed * 1103515245 + 12345) & 0x7fffffff
		var x := float(seed % 2000) - 1000.0
		seed = (seed * 1103515245 + 12345) & 0x7fffffff
		var y := float(seed % 2000) - 1000.0
		entities.append(_make_entity("e%d" % i, Vector2(x, y)))

	var grid = SpatialGridSystem.build(entities, CELL_SIZE)

	# Probe several positions/radii.
	var probes := [
		{"pos": Vector2.ZERO, "r": 100.0},
		{"pos": Vector2(500, 500), "r": 300.0},
		{"pos": Vector2(-800, 200), "r": 600.0},
		{"pos": Vector2(0, 0), "r": 5000.0},
	]

	for probe in probes:
		var grid_hits = SpatialGridSystem.query_radius(grid, probe.pos, probe.r)
		var grid_ids := {}
		for e in grid_hits:
			grid_ids[e.id] = true

		var brute_hits = _brute_force_within(entities, probe.pos, probe.r)
		for e in brute_hits:
			assert_true(
				grid_ids.has(e.id),
				"query_radius missed entity %s at %s within radius %.1f from %s" % [
					e.id, str(e.position), probe.r, str(probe.pos)
				]
			)

func test_query_radius_does_not_return_far_outside_entities():
	# Entities clearly outside any plausible candidate cell should not appear.
	var inside = _make_entity("inside", Vector2(0, 0))
	var on_edge = _make_entity("edge", Vector2(50, 0))
	var far = _make_entity("far", Vector2(10000, 10000))

	var grid = SpatialGridSystem.build([inside, on_edge, far], CELL_SIZE)

	var hits = SpatialGridSystem.query_radius(grid, Vector2.ZERO, 100.0)
	var ids := {}
	for e in hits:
		ids[e.id] = true

	assert_true(ids.has("inside"))
	assert_true(ids.has("edge"))
	assert_false(ids.has("far"), "Entity far outside the query radius should not be returned")

func test_query_radius_handles_negative_coordinates():
	var a = _make_entity("a", Vector2(-500, -500))
	var b = _make_entity("b", Vector2(-510, -490))
	var c = _make_entity("c", Vector2(500, 500))
	var grid = SpatialGridSystem.build([a, b, c], CELL_SIZE)

	var hits = SpatialGridSystem.query_radius(grid, Vector2(-500, -500), 100.0)
	var ids := {}
	for e in hits:
		ids[e.id] = true
	assert_true(ids.has("a"))
	assert_true(ids.has("b"))
	assert_false(ids.has("c"))

func test_query_radius_single_entity_at_query_position():
	var solo = _make_entity("solo", Vector2(0, 0))
	var grid = SpatialGridSystem.build([solo], CELL_SIZE)

	var hits = SpatialGridSystem.query_radius(grid, Vector2.ZERO, 1.0)
	assert_eq(hits.size(), 1)
	assert_eq(hits[0].id, "solo")

func test_query_radius_zero_radius_includes_same_cell_entity():
	# Zero-radius queries still walk the home cell — caller does exact check.
	var entity = _make_entity("e", Vector2(10, 10))
	var grid = SpatialGridSystem.build([entity], CELL_SIZE)

	var hits = SpatialGridSystem.query_radius(grid, Vector2(10, 10), 0.0)
	assert_eq(hits.size(), 1)

# ============================================================================
# CELL BOUNDARIES
# ============================================================================

func test_query_radius_finds_entity_across_cell_boundary():
	# Entities just across a cell boundary must still be found within radius.
	var a = _make_entity("a", Vector2(CELL_SIZE - 5, 0))
	var b = _make_entity("b", Vector2(CELL_SIZE + 5, 0))
	var grid = SpatialGridSystem.build([a, b], CELL_SIZE)

	var hits = SpatialGridSystem.query_radius(grid, Vector2(CELL_SIZE - 5, 0), 20.0)
	var ids := {}
	for e in hits:
		ids[e.id] = true
	assert_true(ids.has("a"))
	assert_true(ids.has("b"), "Entity in adjacent cell within radius must be returned")
