extends GutTest

## Tests for AttributeModifierSystem and the close-range weapon cooldown path.
## Behaviour-focused: asserts observable outcomes, not specific values.

func before_each() -> void:
	AttributeLibrary.invalidate_cache()


# HELPERS

## Build a minimal ship_data with crew_modifiers zeroed, at the given position.
func _make_ship(pos: Vector2 = Vector2.ZERO) -> Dictionary:
	return {
		"ship_id": "test_ship",
		"position": pos,
		"crew_modifiers": {
			"lead_accuracy": 0.0,
			"gunner_panicking": false,
			"pilot_turn_factor": 1.0,
			"pilot_aggression": 0.5,
			"pilot_accel_factor": 1.0,
		},
	}


## Build a crew dict with the given attribute ids and composure skill.
func _make_crew(attributes: Array, composure: float = 0.8, stress: float = 0.0) -> Dictionary:
	return {
		"crew_id": "test_crew",
		"attributes": attributes,
		"stats": {
			"stress": stress,
			"skills": {
				"composure": composure,
				"aim": 0.7,
				"piloting": 0.7,
				"awareness": 0.7,
				"tactics": 0.7,
				"aggression": 0.5,
				"machinery": 0.7,
			},
		},
	}


## Build a weapon dict at the given range (with rate_of_fire=2 → base cooldown 0.5).
func _make_weapon(weapon_range: float = 1000.0, rate_of_fire: float = 2.0) -> Dictionary:
	return {
		"weapon_id": "w1",
		"stats": {"range": weapon_range, "rate_of_fire": rate_of_fire},
		"cooldown_remaining": 0.0,
	}


# PURITY

func test_apply_for_crew_does_not_mutate_input():
	var ship := _make_ship()
	var ship_before := ship.duplicate(true)
	var crew := _make_crew(["dead_eye"])
	AttributeModifierSystem.apply_for_crew(ship, crew)
	assert_eq(ship, ship_before, "apply_for_crew must not mutate the input ship_data")


func test_apply_for_crew_returns_new_dict():
	var ship := _make_ship()
	var crew := _make_crew(["dead_eye"])
	var result := AttributeModifierSystem.apply_for_crew(ship, crew)
	assert_true(result != ship, "apply_for_crew returns a different dictionary instance")


# UNKNOWN ATTRIBUTE

func test_unknown_attribute_id_produces_no_modifier_and_no_crash():
	var ship := _make_ship()
	var lead_before: float = float(ship.crew_modifiers.lead_accuracy)
	var crew := _make_crew(["this_id_definitely_does_not_exist_xyz"])
	var result := AttributeModifierSystem.apply_for_crew(ship, crew)
	assert_eq(float(result.crew_modifiers.lead_accuracy), lead_before,
		"Unknown attribute id leaves lead_accuracy unchanged")


# LEAD ACCURACY

func test_lead_accuracy_attribute_raises_lead_accuracy():
	var ship := _make_ship()
	ship.crew_modifiers.lead_accuracy = 0.5
	var crew_with := _make_crew(["dead_eye"])
	var crew_without := _make_crew([])
	var result_with := AttributeModifierSystem.apply_for_crew(ship, crew_with)
	var result_without := AttributeModifierSystem.apply_for_crew(ship, crew_without)
	assert_gt(
		float(result_with.crew_modifiers.lead_accuracy),
		float(result_without.crew_modifiers.lead_accuracy),
		"dead_eye (lead_accuracy kind) raises lead_accuracy above the un-attributed twin"
	)


# COMPOSURE FACTOR

func test_negative_composure_factor_causes_panic_where_unmodified_twin_does_not():
	# shaken has combat.kind=composure_factor, value=-0.15.
	# AttributeModifierSystem applies: effective_composure = composure * (1 + value) * (1 - stress*0.5)
	# We need: composure > threshold (no panic without shaken)
	#       AND composure * (1 - 0.15) < threshold (panics with shaken), at stress=0.
	# threshold = GUNNER_PANIC_COMPOSURE = 0.3. Window: (0.3, 0.3/0.85 ≈ 0.353).
	# Use 0.32: without shaken → 0.32 > 0.3 (safe); with shaken → 0.32*0.85=0.272 < 0.3 (panic).
	var threshold: float = WingConstants.GUNNER_PANIC_COMPOSURE
	var composure: float = threshold + (threshold / 0.85 - threshold) * 0.5  # midpoint of window

	var ship := _make_ship()
	ship.crew_modifiers.gunner_panicking = false

	var crew_with_shaken := _make_crew(["shaken"], composure, 0.0)
	var crew_without := _make_crew([], composure, 0.0)

	var result_shaken := AttributeModifierSystem.apply_for_crew(ship, crew_with_shaken)
	var result_clean := AttributeModifierSystem.apply_for_crew(ship, crew_without)

	assert_true(result_shaken.crew_modifiers.gunner_panicking,
		"Negative composure_factor (shaken) triggers panic for composure just above threshold")
	assert_false(result_clean.crew_modifiers.gunner_panicking,
		"Un-attributed twin does not panic at the same composure")


# CLOSE-RANGE FIRE RATE

func test_close_range_killer_shortens_cooldown_inside_close_range():
	var weapon := _make_weapon(1000.0, 2.0)  # base cooldown = 0.5
	var close_threshold := 1000.0 * WingConstants.CLOSE_RANGE_OPTIMAL_FRACTION
	var close_pos := close_threshold * 0.5  # well inside close range

	var ship_with := _make_ship(Vector2.ZERO)
	ship_with.crew_modifiers["close_range_fire_bonus"] = 0.20
	var ship_without := _make_ship(Vector2.ZERO)

	var target := {"ship_id": "t", "position": Vector2(close_pos, 0.0)}

	var cd_with := WeaponSystem.calculate_cooldown_time(weapon, ship_with, target)
	var cd_without := WeaponSystem.calculate_cooldown_time(weapon, ship_without, target)

	assert_lt(cd_with, cd_without,
		"close_range_fire_bonus shortens cooldown when target is inside close range")


func test_close_range_fire_rate_does_not_apply_outside_close_range():
	var weapon := _make_weapon(1000.0, 2.0)
	var close_threshold := 1000.0 * WingConstants.CLOSE_RANGE_OPTIMAL_FRACTION
	var far_pos := close_threshold * 1.5  # outside close range

	var ship_with := _make_ship(Vector2.ZERO)
	ship_with.crew_modifiers["close_range_fire_bonus"] = 0.20
	var ship_without := _make_ship(Vector2.ZERO)

	var target := {"ship_id": "t", "position": Vector2(far_pos, 0.0)}

	var cd_with := WeaponSystem.calculate_cooldown_time(weapon, ship_with, target)
	var cd_without := WeaponSystem.calculate_cooldown_time(weapon, ship_without, target)

	assert_eq(cd_with, cd_without,
		"close_range_fire_bonus does not change cooldown when target is outside close range")


func test_close_range_killer_attribute_wires_through_apply_for_crew():
	# Verify the full pipeline: attribute → apply_for_crew → close_range_fire_bonus set.
	var ship := _make_ship()
	var crew := _make_crew(["close_range_killer"])
	var result := AttributeModifierSystem.apply_for_crew(ship, crew)
	assert_gt(float(result.crew_modifiers.get("close_range_fire_bonus", 0.0)), 0.0,
		"close_range_killer attribute sets a positive close_range_fire_bonus on crew_modifiers")


func _ship_with_hull(current_armor: int, max_armor: int) -> Dictionary:
	var ship := _make_ship()
	ship["armor_sections"] = [{"section": "body", "current_armor": current_armor, "max_armor": max_armor}]
	return ship


func test_last_stand_tightens_aim_only_when_hull_is_low():
	# last_stand (low_hp_aim_bonus): a wounded ship's gunners aim tighter; at
	# full hull the bonus does not fire. Smaller spread angle == tighter aim.
	var crew := _make_crew(["last_stand_fighter"])

	var low := AttributeModifierSystem.apply_for_crew(_ship_with_hull(5, 100), crew)
	var low_plain := _ship_with_hull(5, 100)                              # wounded, no attribute
	var full := AttributeModifierSystem.apply_for_crew(_ship_with_hull(100, 100), crew)

	var spread_low := WeaponSystem.calculate_aim_spread_angle(low)
	var spread_low_plain := WeaponSystem.calculate_aim_spread_angle(low_plain)
	var spread_full := WeaponSystem.calculate_aim_spread_angle(full)

	assert_lt(spread_low, spread_low_plain,
		"last_stand tightens the aim cone on a wounded hull")
	assert_almost_eq(spread_full, spread_low_plain, 0.0001,
		"last_stand gives no aim bonus while the hull is healthy")
