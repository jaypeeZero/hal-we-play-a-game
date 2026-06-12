extends GutTest

## Tests for SkillRadarChart's pure polygon geometry - FUNCTIONALITY ONLY.
## Rendering is not tested (headless); the math that places vertices is.

const CENTER := Vector2(100, 100)
const RADIUS := 50.0
const AXES := 7
const DISTANCE_TOLERANCE := 0.0001


func _flat_values(value: float, count: int = AXES) -> Array:
	var values: Array = []
	for _i in count:
		values.append(value)
	return values


func test_one_vertex_per_value():
	var points := SkillRadarChart.polygon_points(_flat_values(0.5), CENTER, RADIUS)
	assert_eq(points.size(), AXES, "The polygon has one vertex per value")


func test_zero_values_collapse_to_the_center():
	for point in SkillRadarChart.polygon_points(_flat_values(0.0), CENTER, RADIUS):
		assert_almost_eq(point.distance_to(CENTER), 0.0, DISTANCE_TOLERANCE,
			"A zero value sits at the center")


func test_full_values_reach_the_radius():
	for point in SkillRadarChart.polygon_points(_flat_values(1.0), CENTER, RADIUS):
		assert_almost_eq(point.distance_to(CENTER), RADIUS, DISTANCE_TOLERANCE,
			"A 1.0 value sits exactly on the outer ring")


func test_values_are_clamped_into_unit_range():
	var points := SkillRadarChart.polygon_points([2.0, -1.0, 0.5], CENTER, RADIUS)
	assert_almost_eq(points[0].distance_to(CENTER), RADIUS, DISTANCE_TOLERANCE,
		"Overshooting values clamp to the outer ring")
	assert_almost_eq(points[1].distance_to(CENTER), 0.0, DISTANCE_TOLERANCE,
		"Negative values clamp to the center")


func test_first_axis_points_straight_up():
	var points := SkillRadarChart.polygon_points(_flat_values(1.0), CENTER, RADIUS)
	assert_almost_eq(points[0].x, CENTER.x, DISTANCE_TOLERANCE,
		"The first axis is vertical")
	assert_lt(points[0].y, CENTER.y, "...pointing up (smaller y)")


func test_axis_points_are_equidistant_from_the_center():
	for point in SkillRadarChart.axis_points(AXES, CENTER, RADIUS):
		assert_almost_eq(point.distance_to(CENTER), RADIUS, DISTANCE_TOLERANCE,
			"Every grid-ring vertex sits at full radius")


func test_axes_are_evenly_spaced():
	var points := SkillRadarChart.axis_points(AXES, CENTER, RADIUS)
	var expected_step := TAU / AXES
	for i in AXES:
		var a := points[i] - CENTER
		var b := points[(i + 1) % AXES] - CENTER
		assert_almost_eq(absf(a.angle_to(b)), expected_step, DISTANCE_TOLERANCE,
			"Adjacent axes are separated by the same angle")
