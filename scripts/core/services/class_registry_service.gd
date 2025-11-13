class_name ClassRegistryService

## Auto-scans directories for GDScript classes and registers them by class_name
## Testable service that can be used independently of autoload

var spell_classes: Dictionary = {}
var entity_classes: Dictionary = {}

func initialize() -> void:
	_scan_and_register("res://scripts/spells/", spell_classes)
	_scan_and_register("res://scripts/entities/", entity_classes)
	print("ClassRegistry: Registered %d spell classes, %d entity classes" % [spell_classes.size(), entity_classes.size()])

func _scan_and_register(directory: String, registry: Dictionary) -> void:
	var dir: DirAccess = DirAccess.open(directory)
	if not dir:
		push_warning("ClassRegistry: Could not open directory: " + directory)
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()

	while file_name != "":
		if not file_name.begins_with("."):
			var full_path: String = directory + file_name

			# Recursively scan subdirectories
			if dir.current_is_dir():
				_scan_and_register(full_path + "/", registry)
			# Register .gd files with class_name
			elif file_name.ends_with(".gd"):
				var script: GDScript = load(full_path)
				if script:
					var extracted_name: String = _extract_class_name(script)
					if extracted_name:
						registry[extracted_name] = script
		file_name = dir.get_next()

	dir.list_dir_end()

func _extract_class_name(script: GDScript) -> String:
	var source: String = script.source_code
	if not source:
		return ""

	var regex: RegEx = RegEx.new()
	regex.compile("^\\s*class_name\\s+(\\w+)")

	# Check each line for class_name declaration
	var lines: PackedStringArray = source.split("\n")
	for line: String in lines:
		var result: RegExMatch = regex.search(line)
		if result:
			return result.get_string(1)

	return ""

func get_spell_class(name: String) -> Variant:
	return spell_classes.get(name, null)

func get_entity_class(name: String) -> Variant:
	return entity_classes.get(name, null)

func get_class_by_name(name: String) -> Variant:
	# Search both registries
	if spell_classes.has(name):
		return spell_classes[name]
	if entity_classes.has(name):
		return entity_classes[name]
	return null
