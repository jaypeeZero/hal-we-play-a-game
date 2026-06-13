extends GutTest

## Tests for DestinationNamer - FUNCTIONALITY ONLY
## Names must be non-empty, unique when rolled in bulk, deterministic, and
## flavor-distinct between battle/shop/R&R types.

const TEST_SEED := 42


func _rng(seed_value: int = TEST_SEED) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func test_battle_name_is_non_empty():
	var used := {}
	var name := DestinationNamer.roll_name(CampaignSystem.NODE_TYPE_BATTLE, _rng(), used)
	assert_gt(name.length(), 0, "Battle node names must be non-empty")


func test_shop_name_is_non_empty():
	var used := {}
	var name := DestinationNamer.roll_name(CampaignSystem.NODE_TYPE_SHOP, _rng(), used)
	assert_gt(name.length(), 0, "Shop node names must be non-empty")


func test_randr_name_is_non_empty():
	var used := {}
	var name := DestinationNamer.roll_name(CampaignSystem.NODE_TYPE_RANDR, _rng(), used)
	assert_gt(name.length(), 0, "R&R node names must be non-empty")


func test_unknown_type_gets_a_name():
	var used := {}
	var name := DestinationNamer.roll_name("unknown_type", _rng(), used)
	assert_gt(name.length(), 0, "Unknown node types must still get a name")


func test_names_are_unique_when_rolled_in_bulk():
	## Roll well over pool sizes (SHOP_NAMES and RANDR_NAMES have 14 entries each)
	## to force collision handling into play.
	var used := {}
	var rng := _rng()
	var names := []

	for _i in 60:
		names.append(DestinationNamer.roll_name(CampaignSystem.NODE_TYPE_BATTLE, rng, used))
	for _i in 40:
		names.append(DestinationNamer.roll_name(CampaignSystem.NODE_TYPE_SHOP, rng, used))
	for _i in 40:
		names.append(DestinationNamer.roll_name(CampaignSystem.NODE_TYPE_RANDR, rng, used))

	var seen := {}
	for name in names:
		assert_false(seen.has(name), "Duplicate name found: '%s'" % name)
		seen[name] = true


func test_same_seed_produces_same_names():
	var used_a := {}
	var used_b := {}
	var rng_a := _rng()
	var rng_b := _rng()
	var types := [
		CampaignSystem.NODE_TYPE_BATTLE,
		CampaignSystem.NODE_TYPE_SHOP,
		CampaignSystem.NODE_TYPE_RANDR,
		CampaignSystem.NODE_TYPE_BATTLE,
	]
	for t in types:
		var name_a := DestinationNamer.roll_name(t, rng_a, used_a)
		var name_b := DestinationNamer.roll_name(t, rng_b, used_b)
		assert_eq(name_a, name_b,
			"Same seed and same call order must produce the same name for type '%s'" % t)


func test_battle_and_shop_names_are_disjoint():
	## Battle names are "<Greek prefix> <constellation root>".
	## Shop names are fixed phrases — they can never collide with battle names.
	## Roll without a shared `used` dict so suffixes don't interfere.
	var battle_names := {}
	var rng_b := _rng(1)
	for _i in 60:
		var bn := DestinationNamer.roll_name(CampaignSystem.NODE_TYPE_BATTLE, rng_b, {})
		battle_names[bn] = true

	var rng_s := _rng(2)
	for _i in 40:
		var shop_name := DestinationNamer.roll_name(CampaignSystem.NODE_TYPE_SHOP, rng_s, {})
		assert_false(battle_names.has(shop_name),
			"Shop name '%s' must not appear in battle name set" % shop_name)


func test_battle_and_randr_names_are_disjoint():
	var battle_names := {}
	var rng_b := _rng(10)
	for _i in 60:
		battle_names[DestinationNamer.roll_name(CampaignSystem.NODE_TYPE_BATTLE, rng_b, {})] = true

	var rng_r := _rng(20)
	for _i in 40:
		var rr_name := DestinationNamer.roll_name(CampaignSystem.NODE_TYPE_RANDR, rng_r, {})
		assert_false(battle_names.has(rr_name),
			"R&R name '%s' must not appear in battle name set" % rr_name)
