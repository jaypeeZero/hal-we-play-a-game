extends GutTest

## WeaponSystem must consume aim_accuracy_factor from crew_modifiers and the
## downstream hit-rate must order strictly with that factor. Behavior-only:
## we do not assert specific accuracies, just that better aim hits more.

const ACCURACY_TRIALS: int = 400
const TARGET_DISTANCE: float = 600.0
const MUZZLE_HIT_BAND: float = 8.0  # half-width of "near-target" cone in deg


func _make_ship_with_aim(aim_factor: float) -> Dictionary:
	return {
		"ship_id": "shooter",
		"type": "fighter",
		"team": 0,
		"position": Vector2.ZERO,
		"rotation": 0.0,
		"status": "operational",
		"stats": {"max_speed": 0.0},
		"crew_modifiers": {
			"aim_accuracy_factor": aim_factor,
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
				"range": 1500.0,
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
		"position": Vector2(0, -TARGET_DISTANCE),  # ship faces UP
		"velocity": Vector2.ZERO,
		"status": "operational",
	}


## Count fire commands whose direction lands inside a tight cone toward the
## target. We're testing the spread/accuracy step end-to-end, not picking
## apart the function.
func _hit_count(aim_factor: float, trials: int) -> int:
	var hits := 0
	for _i in trials:
		var ship: Dictionary = _make_ship_with_aim(aim_factor)
		var target: Dictionary = _make_static_target()
		var result: Dictionary = WeaponSystem.update_weapons(ship, [target], 0.1)
		if result.fire_commands.is_empty():
			continue
		var cmd: Dictionary = result.fire_commands[0]
		var dir: Vector2 = cmd.direction
		var perfect_dir: Vector2 = (target.position - ship.position).normalized()
		var deviation_deg: float = abs(rad_to_deg(dir.angle_to(perfect_dir)))
		if deviation_deg <= MUZZLE_HIT_BAND:
			hits += 1
	return hits


func test_hit_rate_strictly_increases_with_aim_factor():
	var low: int = _hit_count(0.4, ACCURACY_TRIALS)
	var mid: int = _hit_count(0.85, ACCURACY_TRIALS)
	var high: int = _hit_count(1.3, ACCURACY_TRIALS)

	assert_lt(low, mid, "Mid aim factor lands more shots than low")
	assert_lt(mid, high, "High aim factor lands more shots than mid")


func test_default_modifiers_do_not_change_accuracy():
	var base: float = 0.6
	var ship_no_mod: Dictionary = _make_ship_with_aim(1.0)
	ship_no_mod.crew_modifiers = {}
	var passthrough: float = WeaponSystem.calculate_final_accuracy(base, ship_no_mod)
	assert_eq(passthrough, base, "No crew modifiers means no accuracy change")


func test_captain_coordination_compounds_with_aim():
	var ship: Dictionary = _make_ship_with_aim(1.0)
	var base: float = 0.6
	var only_aim: float = WeaponSystem.calculate_final_accuracy(base, ship)
	ship.crew_modifiers["captain_coordination"] = 1.2
	var with_captain: float = WeaponSystem.calculate_final_accuracy(base, ship)
	assert_gt(with_captain, only_aim, "Captain coordination multiplies accuracy on top of aim")
