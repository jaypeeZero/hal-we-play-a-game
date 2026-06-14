extends GutTest

## Tests for AttributeLibrary.roll_attributes — behaviour-focused.
## Asserts structural invariants (count band, role filter, kind uniqueness,
## determinism) without hard-coding specific shipped attribute ids or values.

const FIXED_SEED := 42

func before_each() -> void:
	AttributeLibrary.invalidate_cache()


func _seeded_rng(seed: int = FIXED_SEED) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return rng


# COUNT BAND

func test_roll_count_is_within_expected_band():
	var rng := _seeded_rng()
	for _i in range(20):
		var attrs := AttributeLibrary.roll_attributes(CrewData.Role.GUNNER, rng)
		assert_gte(attrs.size(), WingConstants.ATTRIBUTES_PER_CREW_MIN,
			"Rolled count must be at least ATTRIBUTES_PER_CREW_MIN")
		assert_lte(attrs.size(), WingConstants.ATTRIBUTES_PER_CREW_MAX,
			"Rolled count must be at most ATTRIBUTES_PER_CREW_MAX (pool may cap earlier)")


# ROLE FILTER

func test_gunner_roll_never_returns_pilot_only_attribute():
	# A pilot-only attribute has "pilot" in roles but NOT "gunner".
	# Roll many times to stress-test the filter.
	var rng := _seeded_rng()
	for _trial in range(50):
		var attrs := AttributeLibrary.roll_attributes(CrewData.Role.GUNNER, rng)
		for attr_id in attrs:
			var defn: Dictionary = AttributeLibrary.get_def(str(attr_id))
			var roles: Array = defn.get("roles", [])
			if not roles.is_empty():
				assert_true(roles.has("gunner"),
					"Attribute '%s' returned for gunner but is not universal or gunner-eligible" % attr_id)


func test_pilot_roll_never_returns_gunner_only_attribute():
	var rng := _seeded_rng(99)
	for _trial in range(50):
		var attrs := AttributeLibrary.roll_attributes(CrewData.Role.PILOT, rng)
		for attr_id in attrs:
			var defn: Dictionary = AttributeLibrary.get_def(str(attr_id))
			var roles: Array = defn.get("roles", [])
			if not roles.is_empty():
				assert_true(roles.has("pilot"),
					"Attribute '%s' returned for pilot but is not universal or pilot-eligible" % attr_id)


# KIND UNIQUENESS

func test_rolled_attributes_never_share_the_same_combat_kind():
	var rng := _seeded_rng()
	for _trial in range(50):
		var attrs := AttributeLibrary.roll_attributes(CrewData.Role.GUNNER, rng)
		var seen_kinds: Dictionary = {}
		for attr_id in attrs:
			var defn: Dictionary = AttributeLibrary.get_def(str(attr_id))
			var combat = defn.get("combat")
			if combat == null:
				continue
			var kind: String = str(combat.get("kind", ""))
			if kind.is_empty():
				continue
			assert_false(seen_kinds.has(kind),
				"Two attributes with the same combat.kind '%s' were rolled together" % kind)
			seen_kinds[kind] = true


# EVENTS-ONLY EXCLUDED

func test_grantable_by_events_only_attributes_are_never_rolled():
	var rng := _seeded_rng()
	for _trial in range(100):
		var attrs := AttributeLibrary.roll_attributes(CrewData.Role.GUNNER, rng)
		for attr_id in attrs:
			var defn: Dictionary = AttributeLibrary.get_def(str(attr_id))
			assert_false(defn.get("grantable_by_events_only", false),
				"Attribute '%s' is grantable_by_events_only and must never be rolled" % attr_id)


# DETERMINISM

func test_same_seed_produces_same_result():
	var rng_a := _seeded_rng(FIXED_SEED)
	var rng_b := _seeded_rng(FIXED_SEED)
	var result_a := AttributeLibrary.roll_attributes(CrewData.Role.GUNNER, rng_a)
	var result_b := AttributeLibrary.roll_attributes(CrewData.Role.GUNNER, rng_b)
	assert_eq(result_a, result_b, "Identical seeds produce identical roll_attributes output")


func test_different_seeds_typically_produce_different_results():
	# Statistical: two different seeds are extremely unlikely to produce identical
	# results across 10 rolls. If they always match, the rng isn't being consumed.
	var rng_a := _seeded_rng(FIXED_SEED)
	var rng_b := _seeded_rng(FIXED_SEED + 1)
	var any_different := false
	for _i in range(10):
		var a := AttributeLibrary.roll_attributes(CrewData.Role.PILOT, rng_a)
		var b := AttributeLibrary.roll_attributes(CrewData.Role.PILOT, rng_b)
		if a != b:
			any_different = true
			break
	assert_true(any_different, "Different seeds should produce at least one differing roll result")


# ZERO-RARITY EXCLUDED

func test_zero_rarity_attributes_are_never_rolled():
	var rng := _seeded_rng()
	for _trial in range(100):
		var attrs := AttributeLibrary.roll_attributes(CrewData.Role.GUNNER, rng)
		for attr_id in attrs:
			var defn: Dictionary = AttributeLibrary.get_def(str(attr_id))
			assert_gt(float(defn.get("rarity", 0.0)), 0.0,
				"Attribute '%s' has rarity 0 and must never be rolled" % attr_id)
