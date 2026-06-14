extends GutTest

## Energy-bleed flight model: swinging the nose costs speed,
## making speed an energy budget. Behavior-only — asserts the tradeoff
## exists and converges, not specific values.

const SIM_TICK := 1.0 / 60.0

## Dampening is disabled so the only thing changing speed in a coasting turn
## is the bleed itself.
func _make_ship(bleed: float, speed: float) -> Dictionary:
	return {
		"ship_id": "ship",
		"team": 0,
		"position": Vector2.ZERO,
		"velocity": Vector2(0, -speed),  # rotation 0 faces UP (Y-)
		"rotation": 0.0,
		"angular_velocity": 0.0,
		"status": "operational",
		"stats": {
			"max_speed": 400.0,
			"acceleration": 100.0,
			"turn_rate": 3.0,
			"turn_rate_falloff": 0.0,
			"lateral_acceleration": 0.6,
			"brake_acceleration": 1.0,
			"inertial_dampening": 0.0,
			"turn_speed_bleed": bleed,
			"size": 16.0,
			"mass": 50.0,
		},
	}


## Coasting 180° reversal: returns final speed after `ticks` of max-rate turn.
func _coasting_reversal(bleed: float, initial_speed: float, ticks: int) -> float:
	var ship := _make_ship(bleed, initial_speed)
	var control := {"desired_heading": PI, "throttle": 0.0, "is_braking": false}
	for _i in ticks:
		ship = MovementSystem.apply_space_physics(ship, control, SIM_TICK)
	return ship.velocity.length()


## Sustained max-rate turning under full throttle: the nose is held a constant
## offset ahead of the current rotation so the ship never stops turning.
func _sustained_turn_speed(bleed: float, seconds: float) -> float:
	var ship := _make_ship(bleed, 0.0)
	for _i in int(seconds / SIM_TICK):
		var control := {
			"desired_heading": ship.rotation + PI / 5.0,
			"throttle": 1.0,
			"thrust_active": true,
			"is_braking": false,
		}
		ship = MovementSystem.apply_space_physics(ship, control, SIM_TICK)
	return ship.velocity.length()


func test_turning_bleeds_speed():
	var final_speed := _coasting_reversal(0.15, 300.0, 60)
	assert_lt(final_speed, 300.0, "A hard turn must cost speed")


func test_straight_flight_retains_speed():
	var ship := _make_ship(0.15, 300.0)
	var control := {"desired_heading": 0.0, "throttle": 0.0, "is_braking": false}
	for _i in 60:
		ship = MovementSystem.apply_space_physics(ship, control, SIM_TICK)
	assert_almost_eq(ship.velocity.length(), 300.0, 0.1,
		"Flying straight must not bleed speed")


func test_zero_bleed_stat_preserves_speed_through_turns():
	var final_speed := _coasting_reversal(0.0, 300.0, 60)
	assert_almost_eq(final_speed, 300.0, 0.1,
		"Ships without turn_speed_bleed must turn without losing speed")


func test_same_turn_costs_more_absolute_speed_when_fast():
	var fast_loss := 300.0 - _coasting_reversal(0.15, 300.0, 60)
	var slow_loss := 100.0 - _coasting_reversal(0.15, 100.0, 60)
	assert_gt(fast_loss, slow_loss,
		"A reversal at high speed must cost more speed than the same reversal at low speed")


func test_sustained_turning_converges_below_max_speed():
	var bleeding := _sustained_turn_speed(0.15, 20.0)
	var bleed_free := _sustained_turn_speed(0.0, 20.0)
	assert_lt(bleeding, bleed_free,
		"Constant turning must hold a bleeding ship below a bleed-free one")
	assert_lt(bleeding, 0.9 * 400.0,
		"Corner speed must sit clearly below max_speed — turning forever can't be free")
	assert_gt(bleeding, 0.0, "Corner speed must still be positive — thrust balances bleed")
