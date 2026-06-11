class_name CampaignSaveManager
extends RefCounted

## Saves and loads the roguelike campaign to JSON in user://, following
## FleetDataManager's pattern. The payload is everything RoguelikeRun
## needs to resume: {version, campaign, fleet_hulls, doctrine, enemy_fleet,
## money, current_star_date, callsign_counter, next_hull_id}.

const SAVE_PATH := "user://campaign_save.json"
const SAVE_VERSION := 1

## Ship dicts carry Vector2s (positions, weapon mount offsets); JSON has
## no vector type, so they round-trip through a tagged single-key dict.
const VECTOR2_TAG := "__vector2"

## Payload fields that must come back as ints (JSON parses all numbers as
## floats); node row/col/star_date_gap are cast separately.
const INT_FIELDS := ["current_star_date", "callsign_counter", "money", "next_hull_id"]
const INT_NODE_FIELDS := ["row", "col", "star_date_gap"]
const INT_COUNT_DICTS := ["enemy_fleet"]


static func save_campaign(payload: Dictionary) -> bool:
	var data: Dictionary = payload.duplicate(true)
	data["version"] = SAVE_VERSION
	var json_string: String = JSON.stringify(_encode_value(data), "\t")

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Failed to open campaign save for writing: " + SAVE_PATH)
		return false
	file.store_string(json_string)
	file.close()
	return true


## The saved payload, or {} when no save exists or the file is corrupt.
static func load_campaign() -> Dictionary:
	if not has_save():
		return {}

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("Failed to open campaign save for reading: " + SAVE_PATH)
		return {}
	var json_string := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(json_string) != OK:
		push_error("Failed to parse campaign save JSON: " + json.get_error_message())
		return {}
	var data = json.get_data()
	if not data is Dictionary or int(data.get("version", -1)) != SAVE_VERSION:
		return {}
	return _cast_int_fields(_decode_value(data))


static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


static func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


static func _encode_value(value):
	match typeof(value):
		TYPE_VECTOR2:
			return {VECTOR2_TAG: [value.x, value.y]}
		TYPE_DICTIONARY:
			var encoded := {}
			for key in value:
				encoded[key] = _encode_value(value[key])
			return encoded
		TYPE_ARRAY:
			return value.map(_encode_value)
		_:
			return value


static func _decode_value(value):
	match typeof(value):
		TYPE_DICTIONARY:
			if value.size() == 1 and value.has(VECTOR2_TAG):
				return Vector2(value[VECTOR2_TAG][0], value[VECTOR2_TAG][1])
			var decoded := {}
			for key in value:
				decoded[key] = _decode_value(value[key])
			return decoded
		TYPE_ARRAY:
			return value.map(_decode_value)
		_:
			return value


## Restore integer typing where the rest of the game relies on it,
## mirroring FleetDataManager._validate_fleet_data.
static func _cast_int_fields(data: Dictionary) -> Dictionary:
	for field in INT_FIELDS:
		if data.has(field):
			data[field] = int(data[field])
	for dict_name in INT_COUNT_DICTS:
		var counts: Dictionary = data.get(dict_name, {})
		for ship_type in counts:
			counts[ship_type] = maxi(0, int(counts[ship_type]))
	for node in data.get("campaign", {}).get("nodes", {}).values():
		for field in INT_NODE_FIELDS:
			if node.has(field):
				node[field] = int(node[field])
	return data
