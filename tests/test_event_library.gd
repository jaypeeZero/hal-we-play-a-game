extends GutTest

## Tests for EventLibrary — FUNCTIONALITY ONLY. Asserts library behaviours
## and invariants; never asserts specific shipped data values or exact counts.

func before_each() -> void:
	EventLibrary.invalidate_cache()
	AttributeLibrary.invalidate_cache()


# LOADING

func test_library_loads_a_non_empty_set():
	var lib := EventLibrary.all()
	assert_gt(lib.size(), 0, "The event library contains at least one template")


func test_all_returns_dictionary():
	var lib := EventLibrary.all()
	assert_true(lib is Dictionary, "all() returns a Dictionary")


# get_template

func test_get_template_returns_definition_for_known_id():
	var tmpl := EventLibrary.get_template("bar_fight")
	assert_false(tmpl.is_empty(), "get_template returns a non-empty dict for a known id")


func test_get_template_has_required_fields():
	var tmpl := EventLibrary.get_template("bar_fight")
	for field in ["category", "target", "weight", "polarity", "headline", "body", "effects"]:
		assert_true(tmpl.has(field), "Template has required field '%s'" % field)


func test_get_template_returns_empty_dict_for_unknown_id():
	var tmpl := EventLibrary.get_template("this_id_does_not_exist_xyz")
	assert_true(tmpl.is_empty(), "An unknown id returns an empty dict, not an error")


# SCHEMA INTEGRITY

func test_every_template_has_valid_target():
	for id in EventLibrary.all():
		var tmpl: Dictionary = EventLibrary.get_template(id)
		assert_true(EventLibrary.VALID_TARGETS.has(tmpl.target),
			"Template '%s' has a valid target field" % id)


func test_every_template_effects_is_array():
	for id in EventLibrary.all():
		var tmpl: Dictionary = EventLibrary.get_template(id)
		assert_true(tmpl.effects is Array,
			"Template '%s' effects field is an Array" % id)


func test_every_effect_has_a_kind():
	for id in EventLibrary.all():
		for effect in EventLibrary.get_template(id).effects:
			assert_true(effect.has("kind"),
				"Every effect in template '%s' has a kind field" % id)


func test_every_effect_kind_is_known():
	for id in EventLibrary.all():
		for effect in EventLibrary.get_template(id).effects:
			assert_true(EventLibrary.VALID_EFFECT_KINDS.has(effect["kind"]),
				"Effect kind '%s' in '%s' is in the valid set" % [effect["kind"], id])


func test_library_covers_all_effect_kinds():
	# Every kind named in the plan must appear at least once in shipped templates.
	var found_kinds := {}
	for id in EventLibrary.all():
		for effect in EventLibrary.get_template(id).effects:
			found_kinds[effect["kind"]] = true

	for kind in EventLibrary.VALID_EFFECT_KINDS:
		assert_true(found_kinds.has(kind),
			"At least one event template uses effect kind '%s'" % kind)


# CROSS-LIBRARY CONSISTENCY

func test_every_add_attribute_effect_references_an_existing_attribute():
	## An add_attribute event that references a non-existent attribute id
	## would silently grant nothing at runtime. Catch the mismatch early.
	for id in EventLibrary.all():
		for effect in EventLibrary.get_template(id).effects:
			if effect["kind"] != "add_attribute":
				continue
			var attr_id: String = effect.get("attribute", "")
			var defn := AttributeLibrary.get_def(attr_id)
			assert_false(defn.is_empty(),
				"add_attribute effect in '%s' references existing attribute id '%s'" % [id, attr_id])


func test_every_remove_attribute_effect_references_an_existing_attribute():
	for id in EventLibrary.all():
		for effect in EventLibrary.get_template(id).effects:
			if effect["kind"] != "remove_attribute":
				continue
			var attr_id: String = effect.get("attribute", "")
			var defn := AttributeLibrary.get_def(attr_id)
			assert_false(defn.is_empty(),
				"remove_attribute effect in '%s' references existing attribute id '%s'" % [id, attr_id])


# REQUIRED TEMPLATES

func test_engineers_botched_repair_template_exists():
	assert_false(EventLibrary.get_template("engineers_botched_repair").is_empty(),
		"engineers_botched_repair template is present")


func test_bar_fight_template_exists():
	assert_false(EventLibrary.get_template("bar_fight").is_empty(),
		"bar_fight template is present")


func test_battle_hardened_event_exists():
	assert_false(EventLibrary.get_template("battle_hardened").is_empty(),
		"battle_hardened event template is present")


func test_spies_report_template_exists():
	assert_false(EventLibrary.get_template("spies_report").is_empty(),
		"spies_report template is present")


# candidates stub

func test_candidates_returns_an_array():
	var result := EventLibrary.candidates({})
	assert_true(result is Array, "candidates() returns an Array")


func test_candidates_returns_all_templates_as_stub():
	var all_size := EventLibrary.all().size()
	var candidates_size := EventLibrary.candidates({}).size()
	assert_eq(candidates_size, all_size,
		"Phase-0 stub candidates() returns all templates regardless of run_state")


# CACHE

func test_all_is_stable_across_repeated_calls():
	var first := EventLibrary.all().size()
	var second := EventLibrary.all().size()
	assert_eq(first, second, "Repeated calls return the same library size")


func test_invalidate_cache_forces_reload():
	var before := EventLibrary.all().size()
	EventLibrary.invalidate_cache()
	var after := EventLibrary.all().size()
	assert_eq(before, after, "After invalidation the library reloads to the same size")
