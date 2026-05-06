extends GutTest

## MovementSystem must consume pilot_*_factor crew_modifiers in its hot path.
## Tests that effective turn rate, acceleration, lateral thrust, and
## dampening all order strictly by pilot skill. Behavior-only.

const SIM_TICK: float = 1.0 / 60.0
const SIM_DURATION: float = 1.5  # 1.5 sec of simulated flight


func _make_ship(turn_factor: float, accel_factor: float, lateral_factor: float, damp_factor: float) -> Dictionary:
	return {
		"ship_id": "ship",
		"team": 0,
		"position": Vector2.ZERO,
		"velocity": Vector2.ZERO,
		"rotation": 0.0,
		"angular_velocity": 0.0,
		"status": "operational",
		"stats": {
			"max_speed": 400.0,
			"acceleration": 100.0,
			"turn_rate": 3.0,
			"turn_rate_falloff": 0.0,
			"lateral_acceleration": 0.6,
			"reverse_acceleration": 0.4,
			"brake_acceleration": 1.0,
			"inertial_dampening": 4.0,
			"size": 16.0,
			"mass": 50.0,
		},
		"crew_modifiers": {
			"pilot_turn_factor": turn_factor,
			"pilot_accel_factor": accel_factor,
			"pilot_lateral_factor": lateral_factor,
			"pilot_damp_factor": damp_factor,
		},
	}


func _step(ship: Dictionary, control: Dictionary, dt: float) -> Dictionary:
	return MovementSystem.apply_space_physics(ship, control, dt)


## Simulate a forward-thrust burn. Higher accel factor -> higher final speed.
func _burn_forward(accel_factor: float, ticks: int) -> float:
	var ship: Dictionary = _make_ship(1.0, accel_factor, 1.0, 1.0)
	var control: Dictionary = {
		"desired_heading": 0.0,
		"throttle": 1.0,
		"thrust_active": true,
		"is_braking": false,
	}
	for _i in ticks:
		ship = _step(ship, control, SIM_TICK)
	return ship.velocity.length()


## Simulate a turn from rotation 0 toward heading PI. Higher turn factor ->
## more rotation accumulated in the same time.
func _turn(turn_factor: float, ticks: int) -> float:
	var ship: Dictionary = _make_ship(turn_factor, 1.0, 1.0, 1.0)
	var control: Dictionary = {
		"desired_heading": PI,
		"throttle": 0.0,
		"thrust_active": false,
		"is_braking": false,
	}
	for _i in ticks:
		ship = _step(ship, control, SIM_TICK)
	return abs(ship.rotation)


## Simulate a one-tick lateral burst. Lateral velocity component should grow
## with lateral factor.
func _lateral_kick(lateral_factor: float, ticks: int) -> float:
	var ship: Dictionary = _make_ship(1.0, 1.0, lateral_factor, 1.0)
	var control: Dictionary = {
		"desired_heading": 0.0,
		"throttle": 0.0,
		"lateral_thrust": 1,
		"is_braking": false,
	}
	for _i in ticks:
		ship = _step(ship, control, SIM_TICK)
	return ship.velocity.length()


## Dampening removes perpendicular drift. Inject sideways velocity and
## measure how much remains after coasting; higher damp factor -> less
## remaining perpendicular velocity.
func _residual_perpendicular(damp_factor: float, ticks: int) -> float:
	var ship: Dictionary = _make_ship(1.0, 1.0, 1.0, damp_factor)
	# Ship rotation 0 visually faces UP; perpendicular = X axis.
	ship.velocity = Vector2(50.0, 0.0)
	var control: Dictionary = {
		"desired_heading": 0.0,
		"throttle": 0.0,
		"thrust_active": false,
		"is_braking": false,
	}
	for _i in ticks:
		ship = _step(ship, control, SIM_TICK)
	return abs(ship.velocity.x)


func test_turn_rate_scales_with_pilot_turn_factor():
	var ticks: int = int(SIM_DURATION / SIM_TICK)
	var slow: float = _turn(0.5, ticks)
	var fast: float = _turn(1.3, ticks)
	assert_gt(fast, slow, "Higher turn factor accumulates more rotation per second")


func test_acceleration_scales_with_pilot_accel_factor():
	var ticks: int = int(SIM_DURATION / SIM_TICK)
	var slow: float = _burn_forward(0.6, ticks)
	var fast: float = _burn_forward(1.2, ticks)
	assert_gt(fast, slow, "Higher accel factor reaches higher speed in fixed time")


func test_lateral_thrust_scales_with_pilot_lateral_factor():
	# Short burst — lateral cap is what matters here, not equilibrium.
	var weak: float = _lateral_kick(0.2, 8)
	var strong: float = _lateral_kick(1.0, 8)
	assert_gt(strong, weak, "Higher lateral factor delivers more sideways velocity")


func test_dampening_scales_with_pilot_damp_factor():
	var ticks: int = int(0.5 / SIM_TICK)
	var loose: float = _residual_perpendicular(0.4, ticks)
	var tight: float = _residual_perpendicular(1.2, ticks)
	assert_lt(tight, loose, "Higher damp factor kills perpendicular drift faster")


func test_default_modifiers_yield_baseline_stats():
	# A ship with empty crew_modifiers should behave at base spec.
	var ship: Dictionary = _make_ship(1.0, 1.0, 1.0, 1.0)
	ship.crew_modifiers = {}
	# Verify the helpers return base values.
	assert_eq(MovementSystem._read_modified_turn_rate(ship), ship.stats.turn_rate)
	assert_eq(MovementSystem._read_modified_acceleration(ship), ship.stats.acceleration)
	assert_eq(MovementSystem._read_modified_lateral_factor(ship), 1.0)
	assert_eq(MovementSystem._read_modified_dampening(ship), ship.stats.inertial_dampening)
