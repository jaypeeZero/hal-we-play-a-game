class_name CreatureTypeData

const CREATURE_DIR = "res://data/creatures/"

var creatures: Dictionary = {}  # id (String) → data (Dictionary)

func _init() -> void:
	load_all_creatures()

func load_all_creatures() -> void:
	creatures.clear()
	var dir: DirAccess = DirAccess.open(CREATURE_DIR)
	if not dir:
		push_error("Cannot open creatures directory: %s" % CREATURE_DIR)
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()

	while file_name != "":
		if file_name.ends_with(".json"):
			var file_path: String = CREATURE_DIR + file_name
			var data: Dictionary = _load_json_file(file_path)
			if data and data.has("id"):
				creatures[data.id] = data
		file_name = dir.get_next()

	print("Loaded %d creature types total" % creatures.size())

func _load_json_file(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("Cannot open file: %s" % path)
		return {}

	var json: JSON = JSON.new()
	var parse_result: int = json.parse(file.get_as_text())
	if parse_result != OK:
		push_error("JSON parse error in %s: %s" % [path, json.get_error_message()])
		return {}

	return json.data

func get_creature(id: String) -> Dictionary:
	return creatures.get(id, {})

func get_entity_class(id: String) -> Variant:
	var data: Dictionary = get_creature(id)
	var entity_class_name: String = data.get("entity_class", "")
	if not entity_class_name:
		return null

	var registry: Variant = _get_class_registry()
	if not registry:
		return null

	@warning_ignore("unsafe_method_access")
	return registry.get_entity_class(entity_class_name)

func _get_class_registry() -> Variant:
	# Get ClassRegistry autoload dynamically at runtime
	# This allows tests to load CreatureTypeData without triggering ClassRegistry load
	if Engine.is_editor_hint():
		return null
	var main_loop: Variant = Engine.get_main_loop()
	var root: Variant = main_loop.root if main_loop else null
	if root:
		@warning_ignore("unsafe_method_access")
		return root.get_node_or_null("/root/ClassRegistry")
	return null

