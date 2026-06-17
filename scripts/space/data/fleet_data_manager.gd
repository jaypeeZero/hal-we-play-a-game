class_name FleetDataManager
extends RefCounted

## Manages saving and loading fleet configurations to/from JSON files.
## Fleet data is stored in user:// directory for persistence between game sessions.

const TEAM_0_FILE := "user://team_0_fleet.json"
const TEAM_1_FILE := "user://team_1_fleet.json"

const SHIP_TYPES := [
	"fighter", "heavy_fighter", "torpedo_boat", "corvette", "capital",
	"gunboat_medic", "gunboat_pepperbox", "gunboat_firecracker",
]

## Ship type categories - SINGLE SOURCE OF TRUTH
## All systems should use these instead of hardcoding ship type checks
const GUNBOAT_TYPES := ["gunboat_medic", "gunboat_pepperbox", "gunboat_firecracker"]
## Fighter-class: small/medium hulls using Fighter Pilot AI with no captain.
## Gunboats are fighter-class even though they have destroyable mounts.
const FIGHTER_CLASS_TYPES := ["fighter", "heavy_fighter", "torpedo_boat",
	"gunboat_medic", "gunboat_pepperbox", "gunboat_firecracker"]
const LARGE_SHIP_TYPES := ["corvette", "capital"]

## Check if a ship type is fighter-class (small, agile craft)
static func is_fighter_class(ship_type: String) -> bool:
	return ship_type in FIGHTER_CLASS_TYPES

## Check if a ship type is a large ship (corvette or capital)
static func is_large_ship(ship_type: String) -> bool:
	return ship_type in LARGE_SHIP_TYPES

## Check if a ship type is a gunboat variant.
static func is_gunboat(ship_type: String) -> bool:
	return ship_type in GUNBOAT_TYPES

## Check if a ship type is the medical gunboat variant.
static func is_gunboat_medic(ship_type: String) -> bool:
	return ship_type == "gunboat_medic"

## Check if a ship type has individually destroyable weapon mounts.
## Large ships and gunboats both carry destroyable turret mounts;
## fighter-class (non-gunboat) weapons are integral to the hull.
static func has_destroyable_mounts(ship_type: String) -> bool:
	return is_large_ship(ship_type) or is_gunboat(ship_type)

## Default fleet when no save file exists
static func get_default_fleet() -> Dictionary:
	return {
		"fighter": 1,
		"heavy_fighter": 0,
		"torpedo_boat": 0,
		"corvette": 0,
		"capital": 0,
		"gunboat_medic": 0,
		"gunboat_pepperbox": 0,
		"gunboat_firecracker": 0,
	}


## Save a fleet configuration to disk
static func save_fleet(team: int, fleet_data: Dictionary) -> bool:
	var file_path := TEAM_0_FILE if team == 0 else TEAM_1_FILE
	var json_string := JSON.stringify(fleet_data, "\t")

	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to open file for writing: " + file_path)
		return false

	file.store_string(json_string)
	file.close()
	return true


## Load a fleet configuration from disk
static func load_fleet(team: int) -> Dictionary:
	var file_path := TEAM_0_FILE if team == 0 else TEAM_1_FILE

	if not FileAccess.file_exists(file_path):
		return get_default_fleet()

	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("Failed to open file for reading: " + file_path)
		return get_default_fleet()

	var json_string := file.get_as_text()
	file.close()

	var json := JSON.new()
	var parse_result := json.parse(json_string)
	if parse_result != OK:
		push_error("Failed to parse fleet JSON: " + json.get_error_message())
		return get_default_fleet()

	var data = json.get_data()
	if data is Dictionary:
		return _validate_fleet_data(data)

	return get_default_fleet()


## Validate and sanitize fleet data
static func _validate_fleet_data(data: Dictionary) -> Dictionary:
	var validated := {}
	for ship_type in SHIP_TYPES:
		if data.has(ship_type) and data[ship_type] is float:
			validated[ship_type] = int(max(0, data[ship_type]))
		elif data.has(ship_type) and data[ship_type] is int:
			validated[ship_type] = max(0, data[ship_type])
		else:
			validated[ship_type] = 0
	return validated


## Check if a fleet save file exists
static func fleet_exists(team: int) -> bool:
	var file_path := TEAM_0_FILE if team == 0 else TEAM_1_FILE
	return FileAccess.file_exists(file_path)
