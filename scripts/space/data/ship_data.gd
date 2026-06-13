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
	data = _convert_vectors(data)

	# Apply base stats to weapons and internals (JSON values override base stats)
	data = _apply_base_stats(data)

	return data

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

## Apply base stats from BaseStats to weapons and internals
## JSON data acts as overrides on top of base stats
static func _apply_base_stats(data: Dictionary) -> Dictionary:
	# Apply base stats to weapons
	if data.has("weapons"):
		var weapons := []
		for weapon in data.weapons:
			weapons.append(BaseStats.apply_weapon_base_stats(weapon))
		data.weapons = weapons

	# Apply base stats to internals (engines), then synthesize one destroyable
	# weapon mount per weapon. Mounts are derived from the weapons array (not
	# authored in the template) so weapon placement data is never duplicated;
	# the step is idempotent, skipping any mount already present.
	if data.has("internals"):
		var internals := []
		for internal in data.internals:
			internals.append(BaseStats.apply_internal_base_stats(internal))
		for weapon in data.get("weapons", []):
			var mount := _weapon_mount_for(weapon)
			if not _has_component(internals, mount.component_id):
				internals.append(BaseStats.apply_internal_base_stats(mount))
		data.internals = internals

	return data


## A destroyable internal mount carrying one weapon, placed where the weapon
## is. Destroying it stops the weapon firing and kills its gunner.
static func _weapon_mount_for(weapon: Dictionary) -> Dictionary:
	var weapon_id: String = weapon.get("weapon_id", "")
	return {
		"component_id": "mount_%s" % weapon_id,
		"type": BaseStats.WEAPON_MOUNT_TYPE,
		"weapon_id": weapon_id,
		"section_id": weapon.get("section_id", ""),
		"position_offset": weapon.get("position_offset", Vector2.ZERO),
	}


static func _has_component(internals: Array, component_id: String) -> bool:
	for c in internals:
		if c.get("component_id", "") == component_id:
			return true
	return false


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

	# Pristine snapshots: DamageResolver.recompute_stats_from_components
	# derives effective stats from these as component statuses change.
	instance.base_stats = instance.stats.duplicate(true)
	for weapon in instance.get("weapons", []):
		weapon.base_stats = weapon.stats.duplicate(true)

	# Create crew for ship if requested
	if create_crew:
		var crew = create_crew_for_ship(instance, crew_skill)
		instance.crew = crew

	return instance

## Create crew for ship based on type
static func create_crew_for_ship(ship_data: Dictionary, skill_level: float = 0.5) -> Array:
	var weapon_count: int = ship_data.get("weapons", []).size()
	var crew := CrewData.create_crew_for_ship_type(ship_data.type, weapon_count, skill_level)
	for member in crew:
		member.assigned_to = ship_data.ship_id
	return crew

## Compute the battle-scoped repair pool for a freshly spawned ship.
## Derived from total max armor + total max internal health so it scales
## automatically with ship class. No per-template magic numbers needed.
static func compute_repair_pool(ship: Dictionary) -> int:
	var total: int = DamageResolver.calculate_total_armor(ship) \
		+ DamageResolver.calculate_total_internal_health(ship)
	return int(float(total) * WingConstants.REPAIR_POOL_FRACTION_OF_MAX_HEALTH)


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
## Ships of the same type spawn tightly grouped (within FORMATION_RANGE) so
## wings can form immediately. Extra space is distributed between type groups.
static func calculate_fleet_spawn_positions(fleet: Dictionary, base_x: float, battlefield_height: float) -> Array:
	var results := []

	# Build list of ships grouped by type (SHIP_TYPES order: fighters first)
	var ships_to_spawn := []
	for ship_type in FleetDataManager.SHIP_TYPES:
		var count: int = fleet.get(ship_type, 0)
		if count > 0:
			var hull_length: float = get_hull_length(ship_type)
			for i in range(count):
				ships_to_spawn.append({"type": ship_type, "length": hull_length})

	if ships_to_spawn.is_empty():
		return results

	var min_gap := 50.0
	var margin := 100.0
	var available := battlefield_height - margin * 2.0

	# Count type-group boundaries so extra space spreads between groups, not
	# within them. Keeping same-type ships tight means fighters stay within
	# FORMATION_RANGE of each other and wings form at battle start.
	var type_transitions := 0
	for i in range(1, ships_to_spawn.size()):
		if ships_to_spawn[i]["type"] != ships_to_spawn[i - 1]["type"]:
			type_transitions += 1

	var total_ship_space := 0.0
	for ship in ships_to_spawn:
		total_ship_space += ship["length"] + min_gap

	var inter_group_gap := 0.0
	if type_transitions > 0 and total_ship_space < available:
		inter_group_gap = (available - total_ship_space) / float(type_transitions + 1)

	var current_y := margin + inter_group_gap / 2.0
	for i in range(ships_to_spawn.size()):
		var ship = ships_to_spawn[i]
		var half_length: float = ship["length"] / 2.0
		current_y += half_length
		results.append({
			"type": ship["type"],
			"position": Vector2(base_x, current_y),
			"size": ship["length"]
		})
		current_y += half_length + min_gap
		if i + 1 < ships_to_spawn.size() and ships_to_spawn[i + 1]["type"] != ship["type"]:
			current_y += inter_group_gap

	return results
