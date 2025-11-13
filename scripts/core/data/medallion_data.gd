class_name MedallionData

const MEDALLION_DIR = "res://data/medallions/"

var medallions: Dictionary = {}  # id (String) → data (Dictionary)

func _init() -> void:
	load_all_medallions()

func load_all_medallions() -> void:
	medallions.clear()
	var dir: DirAccess = DirAccess.open(MEDALLION_DIR)
	if not dir:
		push_error("Cannot open medallions directory: %s" % MEDALLION_DIR)
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()

	while file_name != "":
		if file_name.ends_with(".json"):
			var file_path: String = MEDALLION_DIR + file_name
			var data: Dictionary = _load_json_file(file_path)
			if data and data.has("id"):
				medallions[data.id] = data
		file_name = dir.get_next()

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

# String-based API (new)
func get_medallion(id: String) -> Dictionary:
	return medallions.get(id, {})

func get_all_medallions() -> Array:
	return medallions.values()

func get_by_category(category: String) -> Array:
	var result: Array = []
	for m: Dictionary in medallions.values():
		if m.get("category") == category:
			result.append(m)
	return result

func get_spell_class(id: String) -> Variant:
	var data: Dictionary = get_medallion(id)
	var spell_class_name: String = data.get("spell_class", "")
	return _get_class_by_name(spell_class_name, true)

func get_entity_class(id: String) -> Variant:
	var data: Dictionary = get_medallion(id)
	var entity_class_name: String = data.get("entity_class", "")
	return _get_class_by_name(entity_class_name, false)

func _get_class_by_name(klass_name: String, spell_mode: bool) -> Variant:
	if not klass_name:
		return null

	var registry: Variant = _get_class_registry()
	if not registry:
		return null

	if spell_mode:
		@warning_ignore("unsafe_method_access")
		return registry.get_spell_class(klass_name)
	else:
		@warning_ignore("unsafe_method_access")
		return registry.get_entity_class(klass_name)

func _get_class_registry() -> Variant:
	# Get ClassRegistry autoload dynamically at runtime
	# This allows tests to load MedallionData without triggering ClassRegistry load
	if Engine.is_editor_hint():
		return null
	var main_loop: Variant = Engine.get_main_loop()
	var root: Variant = main_loop.root if main_loop else null
	if root:
		@warning_ignore("unsafe_method_access")
		return root.get_node_or_null("/root/ClassRegistry")
	return null

