extends GutTest

## Behavior tests for the standoff/torpedo firing fixes:
## 1. AOE weapons (torpedoes carry explosion_radius) are exempt from the
##    "hold fire until closer" min_range_factor rule, so a standoff platform
##    actually fires at long range.
## 2. diagnose_firing checks the SAME gates as try_fire_weapon and reports the
##    true blocker (holding_too_far / holding) instead of falsely saying "yes".

const FULL_ARC := {"min": -180.0, "max": 180.0}


func _ship_with_weapon(weapon: Dictionary, min_range_factor: float = 0.0) -> Dictionary:
	return {
		"ship_id": "s1", "team": 0, "position": Vector2.ZERO, "rotation": 0.0,
		"crew_modifiers": {"min_range_factor": min_range_factor},
		"weapons": [weapon],
	}


func _gun(explosion_radius: float = 0.0) -> Dictionary:
	var stats := {"range": 10000.0, "rate_of_fire": 1.0}
	if explosion_radius > 0.0:
		stats["explosion_radius"] = explosion_radius
	return {
		"weapon_id": "w1", "type": "test_gun", "facing": 0.0,
		"position_offset": Vector2.ZERO, "arc": FULL_ARC.duplicate(),
		"stats": stats, "cooldown_remaining": 0.0,
	}


# --- Fix 1: standoff exemption -------------------------------------------------

func test_torpedo_fires_at_standoff_despite_min_range_factor() -> void:
	"""An AOE weapon (explosion_radius>0) is within preferred range at long range
	even when a skilled gunner's min_range_factor would hold a cannon."""
	var ship := _ship_with_weapon(_gun(80.0), 0.9)
	var far_target := {"position": Vector2(0, -9000)}  # near max range
	assert_true(WeaponSystem.is_within_preferred_range(ship, ship.weapons[0], far_target),
		"Torpedo (AOE) must fire at standoff range despite high min_range_factor")


func test_direct_fire_gun_still_holds_until_closer() -> void:
	"""A non-AOE gun keeps the hold-until-closer behavior at long range."""
	var ship := _ship_with_weapon(_gun(0.0), 0.9)
	var far_target := {"position": Vector2(0, -9000)}
	assert_false(WeaponSystem.is_within_preferred_range(ship, ship.weapons[0], far_target),
		"Direct-fire gun should still hold until closer at long range")


# --- Fix 2: honest diagnose_firing ---------------------------------------------

func test_diagnose_reports_holding_too_far_not_can_fire() -> void:
	"""In range + arc but held by min_range_factor → reports holding_too_far,
	NOT 'can_fire' (the bug that made the overlay say FIRE: yes while holding)."""
	var ship := _ship_with_weapon(_gun(0.0), 0.9)
	var enemy := TestFactories.make_fighter("e1", Vector2(0, -9000), 1)
	var diag := WeaponSystem.diagnose_firing(ship, [enemy])
	assert_false(diag.firing, "should not be firing — gunner holds until closer")
	assert_eq(diag.reason, WeaponSystem.DIAG_TOO_FAR,
		"reason must be holding_too_far, not a false can_fire")


func test_diagnose_reports_holding_when_intent_false() -> void:
	"""A weapon with fire_intent=false but in range+arc reports holding, not can_fire."""
	var weapon := _gun(0.0)
	weapon["fire_intent"] = false
	var ship := _ship_with_weapon(weapon, 0.0)
	var enemy := TestFactories.make_fighter("e1", Vector2(0, -300), 1)
	var diag := WeaponSystem.diagnose_firing(ship, [enemy])
	assert_false(diag.firing, "fire_intent=false must read as not firing")
	assert_eq(diag.reason, WeaponSystem.DIAG_HOLDING, "reason must be holding")


func test_diagnose_can_fire_when_all_gates_pass() -> void:
	"""Sanity: a ready, engaged weapon with an in-range/arc/preferred target fires."""
	var ship := _ship_with_weapon(_gun(0.0), 0.0)
	var enemy := TestFactories.make_fighter("e1", Vector2(0, -300), 1)
	var diag := WeaponSystem.diagnose_firing(ship, [enemy])
	assert_true(diag.firing, "all gates pass → can_fire")
	assert_eq(diag.reason, WeaponSystem.DIAG_CAN_FIRE)
