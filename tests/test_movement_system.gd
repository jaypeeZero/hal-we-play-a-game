extends GutTest

const TurningConstraint = preload("res://scripts/core/movement/constraints/turning_constraint.gd")
const AccelerationConstraint = preload("res://scripts/core/movement/constraints/acceleration_constraint.gd")
const LocomotionSystem = preload("res://scripts/core/movement/locomotion_system.gd")
const BehaviorModulator = preload("res://scripts/core/movement/behavior_modulator.gd")
const MovementController = preload("res://scripts/core/movement/movement_controller.gd")
const MovementTraits = preload("res://scripts/core/movement/movement_traits.gd")

var _nodes_to_free: Array[Node] = []

func after_each():
	# Free any nodes created during tests
	for node in _nodes_to_free:
		if is_instance_valid(node):
			node.free()
	_nodes_to_free.clear()

# TurningConstraint tests
func test_turning_constraint_cannot_instant_turn():
	var constraint = TurningConstraint.new()
	constraint.max_angular_velocity = 1.0  # 1 rad/sec
	constraint.speed_affects_turning = false  # Disable speed penalty for this test

	var current = Vector2.RIGHT * 100.0  # Moving right
	var desired = Vector2.UP  # Want to go up (90° turn)
	var delta = 0.1  # 0.1 seconds

	var result = constraint.constrain_direction(current, desired, delta)

	# Should turn at most 0.1 radians (max_angular_velocity * delta)
	var actual_turn = abs(result.angle())
	assert_almost_eq(actual_turn, 0.1, 0.01, "Should turn at max rate")

func test_turning_constraint_can_turn_freely_when_stopped():
	var constraint = TurningConstraint.new()
	constraint.max_angular_velocity = 1.0

	var current = Vector2.ZERO  # Stopped
	var desired = Vector2.UP
	var delta = 0.1

	var result = constraint.constrain_direction(current, desired, delta)

	# Should be able to turn to desired direction immediately
	assert_almost_eq(result.angle(), desired.angle(), 0.1, "Can turn freely when stopped")

func test_high_speed_reduces_turn_rate():
	var constraint = TurningConstraint.new()
	constraint.max_angular_velocity = 4.0
	constraint.speed_affects_turning = true

	var slow_velocity = Vector2.RIGHT * 10.0
	var fast_velocity = Vector2.RIGHT * 200.0
	var desired = Vector2.UP

	var slow_turn = constraint.constrain_direction(slow_velocity, desired, 0.1)
	var fast_turn = constraint.constrain_direction(fast_velocity, desired, 0.1)

	# Faster should turn less
	assert_gt(abs(slow_turn.angle()), abs(fast_turn.angle()), "Slow should turn sharper")

# AccelerationConstraint tests
func test_acceleration_constraint_cannot_instant_accelerate():
	var constraint = AccelerationConstraint.new()
	constraint.max_acceleration = 100.0  # units/sec^2

	var current = Vector2.ZERO
	var desired = Vector2.RIGHT * 100.0
	var delta = 0.1

	var result = constraint.apply(current, desired, delta)

	# Max change: 100 * 0.1 = 10 units/sec
	assert_almost_eq(result.length(), 10.0, 0.1, "Should accelerate at max rate")

func test_acceleration_constraint_inertia_reduces_acceleration():
	var low_inertia = AccelerationConstraint.new()
	low_inertia.max_acceleration = 100.0
	low_inertia.inertia = 1.0

	var high_inertia = AccelerationConstraint.new()
	high_inertia.max_acceleration = 100.0
	high_inertia.inertia = 5.0

	var current = Vector2.ZERO
	var desired = Vector2.RIGHT * 100.0

	var low_result = low_inertia.apply(current, desired, 0.1)
	var high_result = high_inertia.apply(current, desired, 0.1)

	assert_gt(low_result.length(), high_result.length(), "Low inertia accelerates faster")

# LocomotionSystem tests
func test_locomotion_gait_transitions():
	var system = LocomotionSystem.new()
	_nodes_to_free.append(system)
	system.walk_threshold = 20.0
	system.trot_threshold = 60.0
	system.run_threshold = 100.0

	system.update(10.0, 0.1)  # Below walk threshold
	assert_eq(system.current_gait, LocomotionSystem.Gait.WALK, "Should be walking")

	system.update(70.0, 0.1)  # Above trot threshold, below run threshold
	assert_eq(system.current_gait, LocomotionSystem.Gait.RUN, "Should be running")

	system.update(120.0, 0.1)  # Above run threshold
	assert_eq(system.current_gait, LocomotionSystem.Gait.GALLOP, "Should be galloping")

	system.update(0.5, 0.1)  # Almost stopped
	assert_eq(system.current_gait, LocomotionSystem.Gait.IDLE, "Should be idle")

# BehaviorModulator tests
func test_hopping_pattern_creates_pauses():
	var modulator = BehaviorModulator.new()
	_nodes_to_free.append(modulator)
	modulator.pattern = BehaviorModulator.MovementPattern.HOPPING
	modulator.is_paused = true
	modulator.pause_timer = 0.5

	var speed = modulator.modulate_speed(100.0, 0.1)

	assert_eq(speed, 0.0, "Should have zero speed during pause")
	assert_almost_eq(modulator.pause_timer, 0.4, 0.01, "Should decrement pause timer")

func test_fleeing_overrides_hopping():
	var modulator = BehaviorModulator.new()
	_nodes_to_free.append(modulator)
	modulator.pattern = BehaviorModulator.MovementPattern.HOPPING
	modulator.is_fleeing = true
	modulator.is_paused = true

	var speed = modulator.modulate_speed(100.0, 0.1)

	assert_eq(speed, 100.0, "Fleeing should ignore pause")
	assert_false(modulator.is_paused, "Fleeing should cancel pause")

# MovementController integration tests
func test_movement_controller_applies_constraints():
	var controller = MovementController.new()
	_nodes_to_free.append(controller)
	controller.kinematic_constraints.acceleration_constraint.max_acceleration = 100.0

	# Set steering
	controller.steering_system.set_steering_force(Vector2.RIGHT * 50.0)
	controller.steering_system.set_desired_speed(100.0)

	# Start from stopped
	controller.velocity = Vector2.ZERO

	# Update one frame
	var motion = controller.update(0.1)

	# Should not instantly reach desired speed
	assert_lt(controller.velocity.length(), 100.0, "Should not reach full speed instantly")
	assert_gt(controller.velocity.length(), 0.0, "Should start accelerating")

func test_movement_controller_loads_traits():
	var controller = MovementController.new()
	_nodes_to_free.append(controller)
	var traits = MovementTraits.new()
	traits.walk_speed = 30.0
	traits.max_acceleration = 200.0
	traits.base_turn_rate = 5.0

	controller.load_traits(traits)

	assert_eq(controller.locomotion_system.walk_threshold, 30.0, "Should load walk speed")
	assert_eq(controller.kinematic_constraints.acceleration_constraint.max_acceleration, 200.0,
		"Should load acceleration")
	assert_eq(controller.kinematic_constraints.turning_constraint.max_angular_velocity, 5.0,
		"Should load turn rate")
