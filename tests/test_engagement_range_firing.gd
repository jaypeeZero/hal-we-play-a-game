extends GutTest

## Empirical firing tests: prove that a fighter placed at its kite preferred_range
## can actually fire, and that one placed far beyond weapon range cannot.
##
## This is the key regression test for the engagement-range correctness bug where
## ships were positioned at 2.5× their weapon range by SteeringBlender, orbiting
## uselessly without ever firing.

# ---------------------------------------------------------------------------
# WeaponSystem.get_effective_range
# ---------------------------------------------------------------------------

func test_get_effective_range_returns_max_weapon_range():
	# A ship with a single weapon: effective range == that weapon's stats.range.
	var ship := TestFactories.make_armed_ship("light_cannon", 0.0, "s1", "fighter")
	var expected: float = float(TestFactories.WEAPON_CLASS_STATS["light_cannon"]["range"])
	assert_eq(WeaponSystem.get_effective_range(ship), expected,
		"get_effective_range must return the single weapon's stats.range")


func test_get_effective_range_returns_max_when_multiple_weapons():
	# Torpedo launcher has a longer range than gatling_gun; effective range = torpedo's.
	var ship := TestFactories.make_torpedo_boat("tp1")
	var torpedo_range: float = float(TestFactories.WEAPON_CLASS_STATS["torpedo_launcher"]["range"])
	var effective := WeaponSystem.get_effective_range(ship)
	assert_eq(effective, torpedo_range,
		"get_effective_range must return the longest-range operational weapon's range")


func test_get_effective_range_ignores_destroyed_weapon():
	# Give a ship two weapons: one destroyed (short range), one operational (long range).
	var short_weapon := TestFactories.make_weapon("gatling_gun", "w_short")
	short_weapon["status"] = "destroyed"
	var long_weapon  := TestFactories.make_weapon("light_cannon", "w_long")

	var ship := TestFactories.make_fighter("s1")
	ship["weapons"] = [short_weapon, long_weapon]

	var expected: float = float(TestFactories.WEAPON_CLASS_STATS["light_cannon"]["range"])
	assert_eq(WeaponSystem.get_effective_range(ship), expected,
		"get_effective_range must ignore destroyed weapons and return the surviving weapon's range")


func test_get_effective_range_falls_back_when_no_weapons():
	# A ship with no weapons at all should return the named fallback constant.
	var ship := TestFactories.make_fighter("s1")
	ship["weapons"] = []
	assert_eq(WeaponSystem.get_effective_range(ship), WeaponSystem.NO_WEAPONS_FALLBACK_RANGE,
		"get_effective_range must return NO_WEAPONS_FALLBACK_RANGE when ship has no weapons")


func test_get_effective_range_falls_back_when_all_weapons_destroyed():
	# All weapons destroyed → same fallback.
	var w := TestFactories.make_weapon("light_cannon", "w1")
	w["status"] = "destroyed"
	var ship := TestFactories.make_fighter("s1")
	ship["weapons"] = [w]
	assert_eq(WeaponSystem.get_effective_range(ship), WeaponSystem.NO_WEAPONS_FALLBACK_RANGE,
		"get_effective_range must return NO_WEAPONS_FALLBACK_RANGE when all weapons are destroyed")


# ---------------------------------------------------------------------------
# Empirical firing: kite-range fighter fires; 3×-range fighter does not
# ---------------------------------------------------------------------------

## Build the kite preferred_range a fighter would adopt via SteeringBlender
## using its real weapon range, with balanced tactics (range_scalar = 0.5 by
## default in the blender helpers).
func _kite_preferred_range(ship: Dictionary) -> float:
	var weapon_range := WeaponSystem.get_effective_range(ship)
	var kite_tactics := {"mentality_scalar": 0.5, "range_scalar": 1.0}
	var directive := SteeringBlender.build_directive(ship, kite_tactics, {}, [], weapon_range)
	return directive["preferred_range"]


func test_fighter_at_kite_preferred_range_can_fire():
	# EMPIRICAL INVARIANT: a fighter using kite tactics should be able to fire
	# when positioned exactly at its kite preferred_range.
	# Before the fix, preferred_range was 2.5× weapon range → ship was out of range.
	# After the fix, it's ≤ 0.9× weapon range → ship fires every pass.
	var fighter := TestFactories.make_armed_ship("light_cannon", 0.0, "f1", "fighter")
	fighter["velocity"] = Vector2.ZERO
	fighter["rotation"] = 0.0

	var kite_dist := _kite_preferred_range(fighter)

	# Place enemy directly in front (within forward arc: -45..+45 degrees)
	var enemy := TestFactories.make_fighter("e1", Vector2(kite_dist, 0.0), 1)
	enemy["velocity"] = Vector2.ZERO

	var result := WeaponSystem.update_weapons(fighter, [fighter, enemy], 1.0)
	var commands: Array = result["fire_commands"]
	assert_false(commands.is_empty(),
		"Fighter at kite preferred_range (%.0f) must fire — weapon range is %.0f" % [
			kite_dist, WeaponSystem.get_effective_range(fighter)])


func test_fighter_at_three_times_weapon_range_cannot_fire():
	# Sanity: a ship sitting at 3× its weapon range must NOT fire.
	var fighter := TestFactories.make_armed_ship("light_cannon", 0.0, "f1", "fighter")
	fighter["velocity"] = Vector2.ZERO
	fighter["rotation"] = 0.0

	var weapon_range := WeaponSystem.get_effective_range(fighter)
	var far_dist := weapon_range * 3.0

	var enemy := TestFactories.make_fighter("e1", Vector2(far_dist, 0.0), 1)
	enemy["velocity"] = Vector2.ZERO

	var result := WeaponSystem.update_weapons(fighter, [fighter, enemy], 1.0)
	var commands: Array = result["fire_commands"]
	assert_true(commands.is_empty(),
		"Fighter at 3× weapon range (%.0f) must NOT fire — enemy is out of range" % far_dist)


func test_kite_preferred_range_is_within_weapon_range():
	# Structural guard: kite preferred_range ≤ weapon's stats.range.
	# If this fails, the blender multiplier bug has regressed.
	var fighter := TestFactories.make_armed_ship("light_cannon", 0.0, "f1", "fighter")
	var weapon_range := WeaponSystem.get_effective_range(fighter)
	var kite_dist    := _kite_preferred_range(fighter)
	assert_lte(kite_dist, weapon_range,
		"Kite preferred_range (%.0f) must be ≤ weapon range (%.0f)" % [kite_dist, weapon_range])
