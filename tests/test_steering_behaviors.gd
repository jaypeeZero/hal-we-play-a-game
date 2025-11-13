extends GutTest

const SteeringBehaviors = preload("res://scripts/core/ai/steering_behaviors.gd")

# Helper class for mock neighbors
class MockNeighbor:
	var global_position: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO
	var direction: Vector2 = Vector2.ZERO
	var speed: float = 100.0

func _make_mock_neighbor(pos: Vector2, vel: Vector2 = Vector2.ZERO) -> MockNeighbor:
	var mock = MockNeighbor.new()
	mock.global_position = pos
	mock.velocity = vel
	if vel.length() > 0:
		mock.direction = vel.normalized()
	return mock

# Seek behavior tests
func test_seek_returns_force_toward_target():
	var pos = Vector2(0, 0)
	var target = Vector2(100, 0)
	var force = SteeringBehaviors.seek(pos, target, 50.0)
	assert_eq(force, Vector2(50, 0), "Should seek right at max speed")

func test_seek_with_zero_distance_returns_zero():
	var pos = Vector2(100, 100)
	var target = Vector2(100, 100)
	var force = SteeringBehaviors.seek(pos, target, 50.0)
	assert_eq(force, Vector2.ZERO, "Should return zero when at target")

func test_seek_respects_max_speed():
	var pos = Vector2(0, 0)
	var target = Vector2(1000, 1000)
	var force = SteeringBehaviors.seek(pos, target, 100.0)
	assert_almost_eq(force.length(), 100.0, 0.1, "Should respect max speed")

# Flee behavior tests
func test_flee_returns_force_away_from_threat():
	var pos = Vector2(100, 0)
	var threat = Vector2(0, 0)
	var force = SteeringBehaviors.flee(pos, threat, 50.0)
	assert_eq(force, Vector2(50, 0), "Should flee away from threat")

func test_flee_respects_max_speed():
	var pos = Vector2(100, 100)
	var threat = Vector2(0, 0)
	var force = SteeringBehaviors.flee(pos, threat, 75.0)
	assert_almost_eq(force.length(), 75.0, 0.1, "Should respect max speed")

# Arrive behavior tests
func test_arrive_full_speed_when_far():
	var pos = Vector2(0, 0)
	var target = Vector2(1000, 0)
	var max_speed = 100.0
	var slowdown_radius = 50.0
	var force = SteeringBehaviors.arrive(pos, target, max_speed, slowdown_radius)
	assert_almost_eq(force.length(), max_speed, 0.1, "Should travel at max speed when far")

func test_arrive_slows_down_near_target():
	var pos = Vector2(0, 0)
	var target = Vector2(25, 0)
	var max_speed = 100.0
	var slowdown_radius = 50.0
	var force = SteeringBehaviors.arrive(pos, target, max_speed, slowdown_radius)
	assert_lt(force.length(), max_speed, "Should slow down when approaching target")

func test_arrive_zero_at_target():
	var pos = Vector2(100, 100)
	var target = Vector2(100, 100)
	var force = SteeringBehaviors.arrive(pos, target, 100.0, 50.0)
	assert_eq(force, Vector2.ZERO, "Should have zero velocity at target")

# Separate behavior tests
func test_separate_returns_zero_with_no_neighbors():
	var pos = Vector2(0, 0)
	var force = SteeringBehaviors.separate(pos, [], 50.0, 100.0)
	assert_eq(force, Vector2.ZERO, "Should return zero with no neighbors")

func test_separate_pushes_away_from_neighbor():
	var pos = Vector2(0, 0)
	var neighbor = _make_mock_neighbor(Vector2(10, 0))
	var force = SteeringBehaviors.separate(pos, [neighbor], 50.0, 100.0)
	assert_lt(force.x, 0.0, "Should push left away from neighbor on right")

func test_separate_ignores_distant_neighbors():
	var pos = Vector2(0, 0)
	var neighbor = _make_mock_neighbor(Vector2(100, 0))
	var force = SteeringBehaviors.separate(pos, [neighbor], 50.0, 100.0)
	assert_eq(force, Vector2.ZERO, "Should ignore neighbors outside radius")

func test_separate_respects_max_force():
	var pos = Vector2(0, 0)
	var neighbor = _make_mock_neighbor(Vector2(5, 0))
	var max_force = 50.0
	var force = SteeringBehaviors.separate(pos, [neighbor], 50.0, max_force)
	assert_almost_eq(force.length(), max_force, 0.1, "Should respect max force")

func test_separate_with_multiple_neighbors():
	var pos = Vector2(0, 0)
	var n1 = _make_mock_neighbor(Vector2(10, 0))
	var n2 = _make_mock_neighbor(Vector2(-10, 0))
	var force = SteeringBehaviors.separate(pos, [n1, n2], 50.0, 100.0)
	assert_almost_eq(force.x, 0.0, 0.1, "Should average between neighbors")

# Cohesion behavior tests
func test_cohesion_returns_zero_with_no_neighbors():
	var pos = Vector2(0, 0)
	var force = SteeringBehaviors.cohesion(pos, [], 100.0)
	assert_eq(force, Vector2.ZERO, "Should return zero with no neighbors")

func test_cohesion_seeks_toward_center_of_mass():
	var pos = Vector2(0, 0)
	var n1 = _make_mock_neighbor(Vector2(100, 0))
	var n2 = _make_mock_neighbor(Vector2(100, 0))
	var force = SteeringBehaviors.cohesion(pos, [n1, n2], 100.0)
	assert_gt(force.x, 0.0, "Should move toward positive X (neighbors)")

func test_cohesion_respects_max_speed():
	var pos = Vector2(0, 0)
	var n1 = _make_mock_neighbor(Vector2(100, 100))
	var max_speed = 75.0
	var force = SteeringBehaviors.cohesion(pos, [n1], max_speed)
	assert_almost_eq(force.length(), max_speed, 0.1, "Should respect max speed")

# Alignment behavior tests
func test_alignment_returns_zero_with_no_neighbors():
	var force = SteeringBehaviors.alignment([], 100.0)
	assert_eq(force, Vector2.ZERO, "Should return zero with no neighbors")

func test_alignment_matches_neighbor_direction():
	var n1 = _make_mock_neighbor(Vector2(0, 0), Vector2(100, 0))
	var force = SteeringBehaviors.alignment([n1], 100.0)
	assert_gt(force.x, 0.0, "Should have positive X to match neighbor direction")

func test_alignment_respects_max_speed():
	var n1 = _make_mock_neighbor(Vector2(0, 0), Vector2(200, 200))
	var max_speed = 50.0
	var force = SteeringBehaviors.alignment([n1], max_speed)
	assert_almost_eq(force.length(), max_speed, 0.1, "Should respect max speed")

func test_alignment_with_multiple_neighbors():
	var n1 = _make_mock_neighbor(Vector2(0, 0), Vector2(100, 0))
	var n2 = _make_mock_neighbor(Vector2(0, 0), Vector2(-100, 0))
	var force = SteeringBehaviors.alignment([n1, n2], 100.0)
	assert_almost_eq(force.length(), 0.0, 1.0, "Should average opposing velocities near zero")

# Force blending test
func test_force_blending_combines_behaviors():
	var pos = Vector2(0, 0)
	var target = Vector2(100, 0)
	var neighbor = _make_mock_neighbor(Vector2(10, 0))

	var seek_force = SteeringBehaviors.seek(pos, target, 50.0) * 0.8
	var separate_force = SteeringBehaviors.separate(pos, [neighbor], 50.0, 100.0) * 0.5
	var final_force = seek_force + separate_force

	# Final force should be combination of both
	assert_gt(final_force.length(), 0.0, "Combined force should be non-zero")
	assert_lt(final_force.x, seek_force.x, "Separation should reduce forward movement")

# Pursue behavior tests
func test_pursue_seeks_toward_target():
	var pos = Vector2(0, 0)
	var target = _make_mock_neighbor(Vector2(100, 0))
	target.direction = Vector2.RIGHT
	target.speed = 50.0
	var force = SteeringBehaviors.pursue(pos, target, 100.0)
	assert_gt(force.x, 0.0, "Should pursue toward target")

func test_pursue_with_null_target_returns_zero():
	var pos = Vector2(0, 0)
	var force = SteeringBehaviors.pursue(pos, null, 100.0)
	assert_eq(force, Vector2.ZERO, "Should return zero for null target")

func test_pursue_predicts_future_position():
	var pos = Vector2(0, 0)
	var target = _make_mock_neighbor(Vector2(100, 0), Vector2(50, 0))
	var force = SteeringBehaviors.pursue(pos, target, 100.0, 1.0)
	# Predicted position is (100 + 50*1.0, 0) = (150, 0)
	assert_gt(force.x, 0.0, "Should pursue toward predicted position")

# Evade behavior tests
func test_evade_flees_from_threat():
	var pos = Vector2(100, 0)
	var threat = _make_mock_neighbor(Vector2(0, 0))
	threat.direction = Vector2.RIGHT
	threat.speed = 50.0
	var force = SteeringBehaviors.evade(pos, threat, 100.0)
	assert_gt(force.x, 0.0, "Should evade away from threat")

func test_evade_with_null_threat_returns_zero():
	var pos = Vector2(0, 0)
	var force = SteeringBehaviors.evade(pos, null, 100.0)
	assert_eq(force, Vector2.ZERO, "Should return zero for null threat")

func test_evade_predicts_future_position():
	var pos = Vector2(200, 0)
	var threat = _make_mock_neighbor(Vector2(0, 0), Vector2(50, 0))
	var force = SteeringBehaviors.evade(pos, threat, 100.0, 1.0)
	# Threat predicted position is (0 + 50*1.0, 0) = (50, 0)
	# Should flee away from (50, 0), so positive X force
	assert_gt(force.x, 0.0, "Should evade away from predicted threat position")
