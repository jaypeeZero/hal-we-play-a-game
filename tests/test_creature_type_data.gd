extends GutTest

# Data validation test for creature type JSON files
# Ensures all creature type data is valid and can be loaded

const CREATURE_DIR = "res://data/creatures/"

var class_registry: ClassRegistryService
var creature_type_data: CreatureTypeData

func before_all():
	# Initialize ClassRegistry to load all entity classes
	class_registry = ClassRegistryService.new()
	class_registry.initialize()

	# Initialize CreatureTypeData to load all creature type JSONs
	creature_type_data = CreatureTypeData.new()

func test_loads_creature_types():
	var wolf = creature_type_data.get_creature("wolf")

	assert_false(wolf.is_empty(), "Should load wolf creature type")
	assert_eq(wolf.get("id"), "wolf", "Wolf should have correct id")
	assert_eq(wolf.get("entity_class"), "WolfUnit", "Wolf should have correct entity_class")

func test_gets_entity_class():
	var entity_class = creature_type_data.get_entity_class("wolf")

	assert_not_null(entity_class, "Should get WolfUnit entity class")

	# Should be able to instantiate it
	var instance = entity_class.new()
	assert_not_null(instance, "Should be able to instantiate WolfUnit")
	add_child_autofree(instance)

func test_creature_has_stats():
	var wolf = creature_type_data.get_creature("wolf")
	var stats = wolf.get("stats", {})

	assert_false(stats.is_empty(), "Wolf should have stats")
	assert_true(stats.has("damage"), "Wolf should have damage")
	assert_true(stats.has("speed"), "Wolf should have correct speed")
	assert_true(stats.has("max_health"), "Wolf should have correct max_health")

func test_creature_has_ai_config():
	var wolf = creature_type_data.get_creature("wolf")
	var ai_config = wolf.get("ai_config", {})

	assert_false(ai_config.is_empty(), "Wolf should have ai_config")
	assert_true(ai_config.has("personality"), "Wolf should have personality config")
	assert_true(ai_config.has("awareness_radius"), "Wolf should have awareness_radius")

func test_all_creature_files_are_valid_json():
	var dir = DirAccess.open(CREATURE_DIR)
	assert_not_null(dir, "Should be able to open creatures directory")

	dir.list_dir_begin()
	var file_name = dir.get_next()
	var files_tested = 0

	while file_name != "":
		if file_name.ends_with(".json"):
			var file_path = CREATURE_DIR + file_name
			var data = _load_json_file(file_path)

			assert_false(data.is_empty(), "JSON file should parse successfully: %s" % file_name)
			files_tested += 1

		file_name = dir.get_next()

	dir.list_dir_end()
	assert_gt(files_tested, 0, "Should have tested at least one creature file")

func test_all_creature_types_have_required_fields():
	var required_fields = ["id", "name", "entity_class", "stats"]

	var dir = DirAccess.open(CREATURE_DIR)
	dir.list_dir_begin()
	var file_name = dir.get_next()

	while file_name != "":
		if file_name.ends_with(".json"):
			var file_path = CREATURE_DIR + file_name
			var creature_data = _load_json_file(file_path)
			var id = creature_data.get("id", "UNKNOWN")

			for field in required_fields:
				assert_true(creature_data.has(field),
					"Creature '%s' should have required field '%s'" % [id, field])

		file_name = dir.get_next()
	dir.list_dir_end()

func test_all_creature_entity_classes_exist():
	var dir = DirAccess.open(CREATURE_DIR)
	dir.list_dir_begin()
	var file_name = dir.get_next()

	while file_name != "":
		if file_name.ends_with(".json"):
			var file_path = CREATURE_DIR + file_name
			var creature_data = _load_json_file(file_path)
			var id = creature_data.get("id", "UNKNOWN")
			var entity_class_name = creature_data.get("entity_class", "")

			assert_ne(entity_class_name, "",
				"Creature '%s' should have entity_class defined" % id)

			var entity_class = class_registry.get_entity_class(entity_class_name)
			assert_not_null(entity_class,
				"Creature '%s' entity_class '%s' should be registered" % [id, entity_class_name])

		file_name = dir.get_next()
	dir.list_dir_end()

func test_all_creature_types_can_be_instantiated():
	var dir = DirAccess.open(CREATURE_DIR)
	dir.list_dir_begin()
	var file_name = dir.get_next()

	while file_name != "":
		if file_name.ends_with(".json"):
			var file_path = CREATURE_DIR + file_name
			var creature_data = _load_json_file(file_path)
			var id = creature_data.get("id", "UNKNOWN")

			# Get entity class
			var entity_class = creature_type_data.get_entity_class(id)
			assert_not_null(entity_class, "Should get entity class for creature '%s'" % id)

			# Try to instantiate
			var creature = entity_class.new()
			assert_not_null(creature, "Should instantiate creature '%s'" % id)
			add_child_autofree(creature)

		file_name = dir.get_next()
	dir.list_dir_end()

func test_creature_types_have_visual_field():
	# All creature types should have visual field for rendering
	var all_types = ["wolf", "bear", "rat_swarm", "charging_knight", "olophant"]

	for type_id in all_types:
		var creature_data = creature_type_data.get_creature(type_id)
		assert_false(creature_data.is_empty(), "Creature type '%s' should exist" % type_id)

		var stats = creature_data.get("stats", {})
		assert_true(stats.has("visual"), "Creature '%s' should have visual field" % type_id)

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
