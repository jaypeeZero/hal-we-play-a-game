class_name ShipData
extends RefCounted

## Pure data container and factory for ship instances
## Templates loaded from JSON files in data/ship_templates/

static var _next_ship_id: int = 0
static var _templates: Dictionary = {}

const TEMPLATES_PATH = "res://data/ship_templates/"

## Get ship template by type (loads from JSON)
static func get_ship_template(ship_type: String) -> Dictionary:
	# Load templates if not already loaded
	if _templates.is_empty():
		_load_all_templates()

	if not _templates.has(ship_type):
		return {}

	# Return a deep copy so modifications don't affect the cached template
	return _templates[ship_type].duplicate(true)

## Load all ship templates from JSON files
static func _load_all_templates() -> void:
	_templates.clear()

	for ship_type in FleetDataManager.SHIP_TYPES:
		var path = TEMPLATES_PATH + ship_type + ".json"
		var template = _load_template_json(path)
		if not template.is_empty():
			_templates[ship_type] = template

## Load a single template from JSON file
static func _load_template_json(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		push_error("Ship template file not found: " + file_path)
		return {}

	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("Could not open ship template file: " + file_path)
		return {}

	var json_text = file.get_as_text()
	file.close()

	var json = JSON.new()
	var error = json.parse(json_text)
	if error != OK:
		push_error("Failed to parse ship template JSON: " + file_path + " at line " + str(json.get_error_line()))
		return {}

	var data = json.get_data()

	# Convert all position_offset dictionaries to Vector2
	return _convert_vectors(data)

## Recursively convert {x, y} dictionaries to Vector2
static func _convert_vectors(data: Variant) -> Variant:
	if data is Dictionary:
		# Check if this is a position_offset dict (has x and y, no other keys)
		if data.has("x") and data.has("y") and data.size() == 2:
			return Vector2(data.x, data.y)

		# Otherwise recurse into dictionary
		var result = {}
		for key in data.keys():
			result[key] = _convert_vectors(data[key])
		return result
	elif data is Array:
		var result = []
		for item in data:
			result.append(_convert_vectors(item))
		return result
	else:
		return data

## Force reload templates (useful after Ship Editor saves)
static func reload_templates() -> void:
	_templates.clear()
	_load_all_templates()

## Create a ship instance from template with crew
static func create_ship_instance(ship_type: String, team: int, position: Vector2, create_crew: bool = false, crew_skill: float = 0.5) -> Dictionary:
	var template = get_ship_template(ship_type)
	if template.is_empty():
		return {}

	var instance = template.duplicate(true)
	instance.ship_id = "ship_" + str(_next_ship_id)
	_next_ship_id += 1
	instance.team = team
	instance.position = position
	instance.rotation = 0.0 if team == 0 else PI  # Face opposing directions
	instance.velocity = Vector2.ZERO
	instance.angular_velocity = 0.0
	instance.status = "operational"

	# Create crew for ship if requested
	if create_crew:
		var crew = create_crew_for_ship(instance, crew_skill)
		instance.crew = crew

	return instance

## Create crew for ship based on type
static func create_crew_for_ship(ship_data: Dictionary, skill_level: float = 0.5) -> Array:
	match ship_data.type:
		"fighter":
			# Solo pilot for fighters
			var crew = CrewData.create_solo_fighter_crew(skill_level)
			for member in crew:
				member.assigned_to = ship_data.ship_id
			return crew
		"heavy_fighter":
			# Pilot + gunner for heavy fighters (rear turret defense)
			var crew = CrewData.create_heavy_fighter_crew(skill_level)
			for member in crew:
				member.assigned_to = ship_data.ship_id
			return crew
		"corvette":
			# Captain, pilot, and gunners for corvette
			var weapon_count = ship_data.weapons.size()
			var crew = CrewData.create_ship_crew(weapon_count, skill_level)
			for member in crew:
				member.assigned_to = ship_data.ship_id
			return crew
		"capital":
			# Full crew for capital ships
			var weapon_count = ship_data.weapons.size()
			var crew = CrewData.create_ship_crew(weapon_count, skill_level)
			for member in crew:
				member.assigned_to = ship_data.ship_id
			return crew
		_:
			return []

## Validate ship data structure
static func validate_ship_data(data: Dictionary) -> bool:
	if not data.has("ship_id"): return false
	if not data.has("type"): return false
	if not data.has("team"): return false
	if not data.has("position"): return false
	if not data.has("stats"): return false
	if not data.has("armor_sections"): return false
	if not data.has("internals"): return false
	if not data.has("weapons"): return false
	return true
