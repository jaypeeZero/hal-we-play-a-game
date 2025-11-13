extends GutTest

# Data validation test for medallion JSON files
# Ensures all medallion data is valid and can be instantiated

const MEDALLION_DIR = "res://data/medallions/"

var class_registry: ClassRegistryService
var medallion_data: MedallionData

func before_all():
	# Initialize ClassRegistry to load all spell and entity classes
	class_registry = ClassRegistryService.new()
	class_registry.initialize()

	# Initialize MedallionData to load all medallion JSONs
	medallion_data = MedallionData.new()

func test_all_medallion_files_are_valid_json():
	var dir = DirAccess.open(MEDALLION_DIR)
	assert_not_null(dir, "Should be able to open medallions directory")

	dir.list_dir_begin()
	var file_name = dir.get_next()
	var files_tested = 0

	while file_name != "":
		if file_name.ends_with(".json"):
			var file_path = MEDALLION_DIR + file_name
			var data = _load_json_file(file_path)

			assert_false(data.is_empty(), "JSON file should parse successfully: %s" % file_name)
			files_tested += 1

		file_name = dir.get_next()

	dir.list_dir_end()
	assert_gt(files_tested, 0, "Should have tested at least one medallion file")

func test_all_medallions_have_required_fields():
	var required_fields = ["id", "name", "icon", "visual_emoji", "description",
		"category", "mana_cost", "casting_range", "spell_class", "entity_class", "properties"]

	var all_medallions = medallion_data.get_all_medallions()
	assert_gt(all_medallions.size(), 0, "Should have loaded at least one medallion")

	for medallion in all_medallions:
		var id = medallion.get("id", "UNKNOWN")

		for field in required_fields:
			assert_true(medallion.has(field),
				"Medallion '%s' should have required field '%s'" % [id, field])

func test_all_medallions_have_valid_categories():
	var valid_categories = ["spell", "creature", "terrain"]

	var all_medallions = medallion_data.get_all_medallions()

	for medallion in all_medallions:
		var id = medallion.get("id", "UNKNOWN")
		var category = medallion.get("category", "")

		assert_true(category in valid_categories,
			"Medallion '%s' should have valid category (got: %s)" % [id, category])

func test_all_spell_classes_exist_and_can_instantiate():
	var all_medallions = medallion_data.get_all_medallions()

	for medallion in all_medallions:
		var id = medallion.get("id", "UNKNOWN")
		var spell_class_name = medallion.get("spell_class", "")

		assert_ne(spell_class_name, "",
			"Medallion '%s' should have spell_class defined" % id)

		var spell_class = class_registry.get_spell_class(spell_class_name)
		assert_not_null(spell_class,
			"Medallion '%s' spell_class '%s' should be registered" % [id, spell_class_name])

		# Try to instantiate the spell class
		var spell_instance = spell_class.new()
		assert_not_null(spell_instance,
			"Should be able to instantiate spell class '%s' for medallion '%s'" % [spell_class_name, id])

		# Spells are RefCounted objects and will be cleaned up automatically

func test_all_entity_classes_exist_and_can_instantiate():
	var all_medallions = medallion_data.get_all_medallions()

	for medallion in all_medallions:
		var id = medallion.get("id", "UNKNOWN")
		var entity_class_name = medallion.get("entity_class", "")

		assert_ne(entity_class_name, "",
			"Medallion '%s' should have entity_class defined" % id)

		var entity_class = class_registry.get_entity_class(entity_class_name)
		assert_not_null(entity_class,
			"Medallion '%s' entity_class '%s' should be registered" % [id, entity_class_name])

		# Try to instantiate the entity class
		var entity_instance = entity_class.new()
		assert_not_null(entity_instance,
			"Should be able to instantiate entity class '%s' for medallion '%s'" % [entity_class_name, id])

		# Clean up - add to autofree so GUT handles cleanup
		add_child_autofree(entity_instance)

func test_all_entity_instances_can_call_ready():
	# Test that entity instances can go through their ready() lifecycle
	var all_medallions = medallion_data.get_all_medallions()
	var test_scene = Node2D.new()
	add_child_autofree(test_scene)

	for medallion in all_medallions:
		var id = medallion.get("id", "UNKNOWN")
		var entity_class_name = medallion.get("entity_class", "")
		var entity_class = class_registry.get_entity_class(entity_class_name)

		if entity_class:
			var entity_instance = entity_class.new()
			test_scene.add_child(entity_instance)

			# Wait for ready to be called
			await wait_physics_frames(1)

			assert_not_null(entity_instance,
				"Entity '%s' for medallion '%s' should survive ready() call" % [entity_class_name, id])

			# Clean up
			entity_instance.queue_free()
			await wait_physics_frames(1)

func test_all_medallions_have_valid_numeric_fields():
	var all_medallions = medallion_data.get_all_medallions()

	for medallion in all_medallions:
		var id = medallion.get("id", "UNKNOWN")

		# Validate mana_cost
		var mana_cost = medallion.get("mana_cost", -1)
		assert_typeof(mana_cost, TYPE_FLOAT,
			"Medallion '%s' mana_cost should be a number" % id)
		assert_gt(mana_cost, 0.0,
			"Medallion '%s' mana_cost should be positive" % id)

		# Validate casting_range
		var casting_range = medallion.get("casting_range", -1)
		assert_typeof(casting_range, TYPE_FLOAT,
			"Medallion '%s' casting_range should be a number" % id)
		assert_gt(casting_range, 0.0,
			"Medallion '%s' casting_range should be positive" % id)

func test_all_medallions_have_properties_dict():
	var all_medallions = medallion_data.get_all_medallions()

	for medallion in all_medallions:
		var id = medallion.get("id", "UNKNOWN")
		var properties = medallion.get("properties", null)

		assert_not_null(properties,
			"Medallion '%s' should have properties field" % id)
		assert_typeof(properties, TYPE_DICTIONARY,
			"Medallion '%s' properties should be a dictionary" % id)

func test_medallion_data_loads_all_files():
	# Verify MedallionData loaded the same number of files as exist
	var dir = DirAccess.open(MEDALLION_DIR)
	var json_file_count = 0

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			json_file_count += 1
		file_name = dir.get_next()
	dir.list_dir_end()

	var loaded_medallions = medallion_data.get_all_medallions()
	assert_eq(loaded_medallions.size(), json_file_count,
		"MedallionData should load all JSON files from directory")

# Helper method to load and parse JSON files
func _load_json_file(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}

	var json = JSON.new()
	var parse_result = json.parse(file.get_as_text())
	if parse_result != OK:
		return {}

	return json.data
