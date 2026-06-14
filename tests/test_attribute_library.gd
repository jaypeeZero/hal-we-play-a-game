extends GutTest

## Tests for AttributeLibrary — FUNCTIONALITY ONLY. Asserts library behaviours
## and invariants; never asserts specific shipped data values or exact counts.

func before_each() -> void:
	AttributeLibrary.invalidate_cache()


# LOADING

func test_library_loads_a_non_empty_set():
	var lib := AttributeLibrary.all()
	assert_gt(lib.size(), 0, "The attribute library contains at least one definition")


func test_all_returns_dictionary():
	var lib := AttributeLibrary.all()
	assert_true(lib is Dictionary, "all() returns a Dictionary")


# get_def

func test_get_def_returns_definition_for_known_id():
	var defn := AttributeLibrary.get_def("close_range_killer")
	assert_false(defn.is_empty(), "get_def returns a non-empty dict for a known id")


func test_get_def_has_required_fields_for_known_id():
	var defn := AttributeLibrary.get_def("close_range_killer")
	for field in ["display_name", "blurb", "category", "polarity", "roles", "rarity", "combat", "event_weights"]:
		assert_true(defn.has(field), "Definition has required field '%s'" % field)


func test_get_def_returns_empty_dict_for_unknown_id():
	var defn := AttributeLibrary.get_def("this_id_does_not_exist_xyz")
	assert_true(defn.is_empty(), "An unknown id returns an empty dict, not an error")


func test_shaken_is_grantable_by_events_only():
	var defn := AttributeLibrary.get_def("shaken")
	assert_false(defn.is_empty(), "shaken is in the library")
	assert_true(defn.get("grantable_by_events_only", false), "shaken is grantable_by_events_only")
	assert_eq(defn.rarity, 0.0, "shaken has rarity 0 so it is never rolled at generation")


func test_battle_hardened_is_grantable_by_events_only():
	var defn := AttributeLibrary.get_def("battle_hardened")
	assert_false(defn.is_empty(), "battle_hardened is in the library")
	assert_true(defn.get("grantable_by_events_only", false), "battle_hardened is grantable_by_events_only")


# SCHEMA INTEGRITY

func test_every_definition_has_valid_category():
	var valid_categories := ["combat", "personality", "mixed"]
	for id in AttributeLibrary.all():
		var defn: Dictionary = AttributeLibrary.get_def(id)
		assert_true(valid_categories.has(defn.category),
			"Definition '%s' has a valid category" % id)


func test_every_definition_has_valid_polarity():
	var valid_polarities := ["positive", "negative", "neutral"]
	for id in AttributeLibrary.all():
		var defn: Dictionary = AttributeLibrary.get_def(id)
		assert_true(valid_polarities.has(defn.polarity),
			"Definition '%s' has a valid polarity" % id)


func test_every_combat_block_uses_a_known_kind():
	for id in AttributeLibrary.all():
		var defn: Dictionary = AttributeLibrary.get_def(id)
		var combat = defn.get("combat")
		if combat == null:
			continue
		assert_true(AttributeLibrary.VALID_COMBAT_KINDS.has(combat["kind"]),
			"Definition '%s' combat.kind is in the valid set" % id)


func test_library_covers_all_required_combat_kinds():
	# Every kind named in the plan must appear at least once in the shipped data.
	var found_kinds := {}
	for id in AttributeLibrary.all():
		var combat = AttributeLibrary.get_def(id).get("combat")
		if combat != null:
			found_kinds[combat["kind"]] = true

	for kind in AttributeLibrary.VALID_COMBAT_KINDS:
		assert_true(found_kinds.has(kind),
			"At least one attribute uses combat kind '%s'" % kind)


# combat_attributes_for

func test_combat_attributes_for_gunner_excludes_pilot_only_traits():
	var gunner_attrs := AttributeLibrary.combat_attributes_for(CrewData.Role.GUNNER)
	for defn in gunner_attrs:
		var roles: Array = defn.roles
		# A trait is included only if roles is empty (universal) or contains "gunner"
		assert_true(roles.is_empty() or roles.has("gunner"),
			"'%s' included for gunner has gunner in roles (or is universal)" % defn.display_name)


func test_combat_attributes_for_returns_only_combat_bearing_entries():
	for role in CrewData.ROLE_NAMES:
		var attrs := AttributeLibrary.combat_attributes_for(role)
		for defn in attrs:
			assert_not_null(defn.get("combat"),
				"combat_attributes_for only returns entries with a non-null combat block")


func test_combat_attributes_for_pilot_excludes_gunner_only_traits():
	var pilot_attrs := AttributeLibrary.combat_attributes_for(CrewData.Role.PILOT)
	for defn in pilot_attrs:
		var roles: Array = defn.roles
		assert_true(roles.is_empty() or roles.has("pilot"),
			"'%s' included for pilot has pilot in roles (or is universal)" % defn.display_name)


# CACHE

func test_all_is_stable_across_repeated_calls():
	var first := AttributeLibrary.all()
	var second := AttributeLibrary.all()
	assert_eq(first.size(), second.size(), "Repeated calls return the same library size")


func test_invalidate_cache_forces_reload():
	var before := AttributeLibrary.all().size()
	AttributeLibrary.invalidate_cache()
	var after := AttributeLibrary.all().size()
	assert_eq(before, after, "After invalidation the library reloads to the same size")
