class_name HullShapes
extends RefCounted

## Hull shape definitions loaded from JSON
## Provides precise point-based hull geometries for all ship types

static var _hull_data: Dictionary = {}

## Load all hull shape definitions from JSON files
static func load_hull_shapes() -> void:
	_hull_data.clear()

	for ship_type in FleetDataManager.SHIP_TYPES:
		var path = "res://data/hull_shapes/" + ship_type + "_hull.json"
		var hull = _load_hull_json(path)
		if hull:
			_hull_data[ship_type] = hull
			print("Loaded hull shape: " + ship_type)
		else:
			push_error("Failed to load hull shape: " + ship_type)

## Load a single hull JSON file
static func _load_hull_json(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		push_error("Hull shape file not found: " + file_path)
		return {}

	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("Could not open hull shape file: " + file_path)
		return {}

	var json_text = file.get_as_text()
	file.close()

	var json = JSON.new()
	var error = json.parse(json_text)
	if error != OK:
		push_error("Failed to parse hull JSON: " + file_path + " at line " + str(json.get_error_line()))
		return {}

	var data = json.get_data()

	# Convert point dictionaries to Vector2
	if data.has("sections"):
		for section in data.sections:
			if section.has("points"):
				var points_array = []
				for point_dict in section.points:
					points_array.append(Vector2(point_dict.x, point_dict.y))
				section.points = points_array

	return data

## Get hull shape data for a ship type
static func get_hull(ship_type: String) -> Dictionary:
	if _hull_data.is_empty():
		load_hull_shapes()

	return _hull_data.get(ship_type, {})

## Get all section polygons for a ship type
static func get_sections(ship_type: String) -> Array:
	var hull = get_hull(ship_type)
	return hull.get("sections", [])

## Get a specific section polygon by section_id
static func get_section(ship_type: String, section_id: String) -> Array:
	var sections = get_sections(ship_type)
	for section in sections:
		if section.section_id == section_id:
			return section.get("points", [])
	return []

## Get base size for a ship type
static func get_base_size(ship_type: String) -> float:
	var hull = get_hull(ship_type)
	return hull.get("base_size", 15.0)

## Rotate a point 90 degrees clockwise (vertical -> horizontal)
static func rotate_90(point: Vector2) -> Vector2:
	return Vector2(-point.y, point.x)

## Get section points rotated for horizontal display
static func get_section_rotated(ship_type: String, section_id: String) -> Array:
	var points = get_section(ship_type, section_id)
	var rotated = []
	for point in points:
		rotated.append(rotate_90(point))
	return rotated
