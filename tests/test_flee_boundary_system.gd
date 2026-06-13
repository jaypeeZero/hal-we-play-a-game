extends GutTest

## Behavior tests for the escape-boundary geometry: where the ovoid sits, how
## big it is relative to the spawn distance, and when the gating predicates fire.

const SIZE := Vector2(5000, 3500)


func test_center_is_battlefield_midpoint():
	assert_eq(FleeBoundarySystem.center(SIZE), SIZE * 0.5,
		"boundary center must be the battlefield midpoint")


func test_point_on_axis_at_semi_axis_is_on_the_boundary():
	var c := FleeBoundarySystem.center(SIZE)
	var ax := FleeBoundarySystem.semi_axes(SIZE)
	var on_edge := c + Vector2(ax.x, 0.0)
	assert_almost_eq(FleeBoundarySystem.normalized_distance(on_edge, SIZE), 1.0, 0.001,
		"a point at the horizontal semi-axis has normalized distance ~1")


func test_horizontal_span_is_the_spawn_multiple_of_spawn_distance():
	var spawn_distance: float = SIZE.x - 2.0 * BattlePlanner.MARGIN
	var span: float = FleeBoundarySystem.semi_axes(SIZE).x * 2.0
	assert_almost_eq(span, FleeBoundarySystem.BOUNDARY_SPAWN_MULTIPLE * spawn_distance, 1.0,
		"horizontal span must be ~the spawn multiple times the spawn distance")


func test_near_edge_fires_past_the_near_fraction_only():
	var c := FleeBoundarySystem.center(SIZE)
	var ax := FleeBoundarySystem.semi_axes(SIZE)
	var inside := c + Vector2(ax.x * (FleeBoundarySystem.NEAR_EDGE_FRACTION - 0.1), 0.0)
	var near := c + Vector2(ax.x * (FleeBoundarySystem.NEAR_EDGE_FRACTION + 0.05), 0.0)
	assert_false(FleeBoundarySystem.is_near_edge(inside, SIZE),
		"well inside the near fraction must not read as near the edge")
	assert_true(FleeBoundarySystem.is_near_edge(near, SIZE),
		"past the near fraction must read as near the edge")


func test_is_outside_only_past_the_boundary():
	var c := FleeBoundarySystem.center(SIZE)
	var ax := FleeBoundarySystem.semi_axes(SIZE)
	var inside := c + Vector2(ax.x * 0.9, 0.0)
	var outside := c + Vector2(ax.x * 1.1, 0.0)
	assert_false(FleeBoundarySystem.is_outside(inside, SIZE),
		"a point inside the ovoid is not outside")
	assert_true(FleeBoundarySystem.is_outside(outside, SIZE),
		"a point past the ovoid is outside")


func test_clear_inside_true_near_center_false_near_edge():
	var c := FleeBoundarySystem.center(SIZE)
	var ax := FleeBoundarySystem.semi_axes(SIZE)
	var near_edge := c + Vector2(ax.x * 0.9, 0.0)
	assert_true(FleeBoundarySystem.is_clear_inside(c, SIZE),
		"the center is clear inside")
	assert_false(FleeBoundarySystem.is_clear_inside(near_edge, SIZE),
		"a point near the edge is not clear inside")


func test_outward_exit_point_is_outside_for_an_interior_point():
	var c := FleeBoundarySystem.center(SIZE)
	var ax := FleeBoundarySystem.semi_axes(SIZE)
	var interior := c + Vector2(ax.x * 0.5, ax.y * 0.3)
	var exit := FleeBoundarySystem.outward_exit_point(interior, SIZE)
	assert_true(FleeBoundarySystem.is_outside(exit, SIZE),
		"the outward exit point must lie outside the ovoid")


func test_inward_point_is_clear_inside():
	var inward := FleeBoundarySystem.inward_point(SIZE)
	assert_true(FleeBoundarySystem.is_clear_inside(inward, SIZE),
		"the inward steer point (center) must be clear inside")
