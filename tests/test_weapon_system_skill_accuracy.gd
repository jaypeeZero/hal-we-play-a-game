extends GutTest

## WeaponSystem's spread cone is driven by raw `aim_skill` from crew_modifiers
## and the shooter's patrol-area diameter. Behavior-only: we don't assert
## specific spreads, just that better aim hits more — and that an elite
## (1.0-aim) gunner reliably tags a fighter at one patrol diameter range.

const ACCURACY_TRIALS: int = 400
const PATROL_RADIUS: float = 700.0
const TARGET_DISTANCE: float = PATROL_RADIUS * 2.0  # one patrol diameter
const MUZZLE_HIT_BAND: float = 8.0  # half-width of "near-target" cone in deg
const ELITE_HIT_RATE: float = 0.95  # 1.0-aim should clear this comfortably


func _make_ship_with_aim(aim_skill: float) -> Dictionary:
	return {
		"ship_id": "shooter",
		"type": "fighter",
		"team": 0,
		"position": Vector2.ZERO,
		"rotation": 0.0,
		"status": "operational",
		"stats": {"max_speed": 0.0},
		"assigned_area": {"center": Vector2.ZERO, "radius": PATROL_RADIUS},
		"crew_modifiers": {
			"aim_skill": aim_skill,
			"targeting_style": CrewIntegrationSystem.TargetingStyle.LEADING,
			"lead_accuracy": 0.5,
		},
		"weapons": [{
			"weapon_id": "w",
			"type": "light_cannon",
			"position_offset": Vector2.ZERO,
			"facing": 0.0,
			"arc": {"min": -45.0, "max": 45.0},
			"stats": {
				"damage": 10,
				"rate_of_fire": 2.0,
				"projectile_speed": 800.0,
				"range": 4000.0,
				"accuracy": 0.5,
			},
			"cooldown_remaining": 0.0,
		}],
		"internals": [],
	}


func _make_static_target() -> Dictionary:
	return {
		"ship_id": "target",
		"type": "fighter",
		"team": 1,
		"position": Vector2(0, -TARGET_DISTANCE),
		"velocity": Vector2.ZERO,
		"status": "operational",
	}


## Count fire commands whose direction would actually land on a fighter-sized
## target at patrol-diameter range. End-to-end test of the spread step.
func _hit_count(aim_skill: float, trials: int) -> int:
	var hits := 0
	var target_radius: float = WingConstants.GUNNER_AIM_TARGET_RADIUS
	for _i in trials:
		var ship: Dictionary = _make_ship_with_aim(aim_skill)
		var target: Dictionary = _make_static_target()
		var result: Dictionary = WeaponSystem.update_weapons(ship, [target], 0.1)
		if result.fire_commands.is_empty():
			continue
		var cmd: Dictionary = result.fire_commands[0]
		var perfect_dir: Vector2 = (target.position - ship.position).normalized()
		var deviation_rad: float = abs(cmd.direction.angle_to(perfect_dir))
		var lateral_at_target: float = TARGET_DISTANCE * tan(deviation_rad)
		if lateral_at_target <= target_radius:
			hits += 1
	return hits


func test_hit_rate_strictly_increases_with_aim_skill():
	var low: int = _hit_count(0.0, ACCURACY_TRIALS)
	var mid: int = _hit_count(0.5, ACCURACY_TRIALS)
	var high: int = _hit_count(1.0, ACCURACY_TRIALS)

	assert_lt(low, mid, "Mid aim skill lands more shots than low")
	assert_lt(mid, high, "High aim skill lands more shots than mid")


func test_elite_aim_almost_never_misses_at_patrol_diameter():
	var hits: int = _hit_count(1.0, ACCURACY_TRIALS)
	var rate: float = float(hits) / float(ACCURACY_TRIALS)
	assert_gte(rate, ELITE_HIT_RATE,
		"1.0-aim crew should reliably hit fighters at one patrol diameter (got %.2f)" % rate)


func test_panic_widens_the_cone():
	# Even an elite gunner sprays when panicking.
	var ship_calm: Dictionary = _make_ship_with_aim(1.0)
	var ship_panic: Dictionary = _make_ship_with_aim(1.0)
	ship_panic.crew_modifiers["gunner_panicking"] = true

	var calm_spread: float = WeaponSystem.calculate_aim_spread_angle(ship_calm)
	var panic_spread: float = WeaponSystem.calculate_aim_spread_angle(ship_panic)
	assert_gt(panic_spread, calm_spread, "Panic produces a wider spread cone than calm aim")


func _make_ship_with_range_gate(aim_skill: float) -> Dictionary:
	var ship: Dictionary = _make_ship_with_aim(aim_skill)
	ship.crew_modifiers["min_range_factor"] = aim_skill * WingConstants.GUNNER_MIN_RANGE_FACTOR
	return ship


func _make_target_at_range_fraction(fraction: float) -> Dictionary:
	var weapon_range: float = 4000.0
	return {
		"ship_id": "target",
		"type": "fighter",
		"team": 1,
		"position": Vector2(0, -weapon_range * fraction),
		"velocity": Vector2.ZERO,
		"status": "operational",
	}


func test_skilled_gunner_holds_fire_at_max_range():
	var ship: Dictionary = _make_ship_with_range_gate(1.0)
	var target: Dictionary = _make_target_at_range_fraction(0.95)
	var result: Dictionary = WeaponSystem.update_weapons(ship, [target], 0.1)
	assert_true(result.fire_commands.is_empty(), "Skill-20 gunner should hold fire at 95% of max range")


func test_skilled_gunner_fires_within_preferred_range():
	var ship: Dictionary = _make_ship_with_range_gate(1.0)
	var target: Dictionary = _make_target_at_range_fraction(0.25)
	var result: Dictionary = WeaponSystem.update_weapons(ship, [target], 0.1)
	assert_false(result.fire_commands.is_empty(), "Skill-20 gunner should fire at 25% of max range")


func test_unskilled_gunner_fires_at_max_range():
	var ship: Dictionary = _make_ship_with_range_gate(0.0)
	var target: Dictionary = _make_target_at_range_fraction(0.95)
	var result: Dictionary = WeaponSystem.update_weapons(ship, [target], 0.1)
	assert_false(result.fire_commands.is_empty(), "Skill-0 gunner should fire at max range")
