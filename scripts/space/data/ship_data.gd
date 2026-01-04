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
	# Collision radius derived from hull shape (matches visual exactly)
	instance.collision_radius = HullShapes.get_collision_radius(ship_type)

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


## Get hull length (Y extent) for a ship type - used for spawn spacing
static func get_hull_length(ship_type: String) -> float:
	var hull = HullShapes.get_hull(ship_type)
	var sections = hull.get("sections", [])
	if sections.is_empty():
		# Fallback to stats.size * 2 if no hull data
		var template = get_ship_template(ship_type)
		return template.stats.size * 2.0 if not template.is_empty() else 40.0

	var min_y := 0.0
	var max_y := 0.0
	for section in sections:
		for point in section.get("points", []):
			if point.y < min_y:
				min_y = point.y
			if point.y > max_y:
				max_y = point.y
	return max_y - min_y


## Calculate spawn positions for a fleet - pure function for testability
## Returns array of {type: String, position: Vector2, size: float}
static func calculate_fleet_spawn_positions(fleet: Dictionary, base_x: float, battlefield_height: float) -> Array:
	var results := []

	# Build list of ships with their hull lengths (not collision radius)
	var ships_to_spawn := []
	for ship_type in FleetDataManager.SHIP_TYPES:
		var count: int = fleet.get(ship_type, 0)
		if count > 0:
			var hull_length: float = get_hull_length(ship_type)
			for i in range(count):
				ships_to_spawn.append({"type": ship_type, "length": hull_length})

	if ships_to_spawn.is_empty():
		return results

	# Calculate minimum spacing needed - ships CANNOT overlap
	var min_gap := 50.0  # Extra gap between ship edges
	var total_required := 0.0
	for ship in ships_to_spawn:
		total_required += ship["length"] + min_gap

	# Available space
	var margin := 100.0
	var available := battlefield_height - margin * 2.0

	# Distribute extra space as additional gap if we have room
	var extra_gap := 0.0
	if total_required < available:
		extra_gap = (available - total_required) / float(ships_to_spawn.size())

	# Position each ship - use half-length to find center
	var current_y := margin
	for ship in ships_to_spawn:
		var half_length: float = ship["length"] / 2.0
		current_y += half_length  # Move to ship center
		results.append({
			"type": ship["type"],
			"position": Vector2(base_x, current_y),
			"size": ship["length"]
		})
		current_y += half_length + min_gap + extra_gap  # Move past ship

	return results
