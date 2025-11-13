class_name Satchel

const Medallion = preload("res://scripts/core/game_systems/medallion.gd")

var _deck: Array[Medallion] = []
var _loadout_path: String

func _init(loadout_path: String = "") -> void:
	_loadout_path = loadout_path
	_initialize_deck()
	_shuffle()

func _initialize_deck() -> void:
	var loadout: Dictionary = _load_loadout()
	_build_deck_from_loadout(loadout)

func _load_loadout() -> Dictionary:
	if not FileAccess.file_exists(_loadout_path) or _loadout_path == "":
		# No warning needed - using default is expected when no file specified
		return _get_default_loadout()

	var file: FileAccess = FileAccess.open(_loadout_path, FileAccess.READ)
	if not file:
		push_error("Failed to open loadout file")
		return _get_default_loadout()

	var json_string: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	var error: Error = json.parse(json_string)
	if error != OK:
		push_error("Failed to parse loadout JSON: " + str(error))
		return _get_default_loadout()

	return json.data

func _build_deck_from_loadout(loadout: Dictionary) -> void:
	var medallions: Dictionary = loadout.get("medallions", {})

	for medallion_id: String in medallions.keys():
		var count: int = medallions[medallion_id]

		# Support both old uppercase enum names and new lowercase IDs
		var normalized_id: String = _normalize_medallion_id(medallion_id)

		if not normalized_id:
			push_warning("Unknown medallion type: " + medallion_id)
			continue

		for i: int in range(count):
			_deck.append(Medallion.new(normalized_id))

func _normalize_medallion_id(id_str: String) -> String:
	# Convert to lowercase and handle legacy uppercase enum names
	var lowercase_id: String = id_str.to_lower()

	# Valid medallion IDs (from JSON files)
	var valid_ids: Array[String] = [
		"lightning_bolt", "fireball", "olophant", "rat_swarm",
		"bear", "wolf_pack", "charging_knight", "chasm", "wall_of_trees"
	]

	if lowercase_id in valid_ids:
		return lowercase_id

	# Legacy: if not found, it might be an uppercase enum name
	# Try converting: "LIGHTNING_BOLT" -> "lightning_bolt"
	if lowercase_id in valid_ids:
		return lowercase_id

	return ""

func _get_default_loadout() -> Dictionary:
	# Load default loadout from JSON file
	# No need to manually update medallion counts here
	const DEFAULT_PATH = "res://default_loadout.json"

	if not FileAccess.file_exists(DEFAULT_PATH):
		push_error("Default loadout file not found: " + DEFAULT_PATH)
		return {"loadout_name": "Empty", "medallions": {}}

	var file: FileAccess = FileAccess.open(DEFAULT_PATH, FileAccess.READ)
	if not file:
		push_error("Failed to open default loadout file")
		return {"loadout_name": "Empty", "medallions": {}}

	var json_string: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	var error: Error = json.parse(json_string)
	if error != OK:
		push_error("Failed to parse default loadout JSON: " + str(error))
		return {"loadout_name": "Empty", "medallions": {}}

	return json.data

func _shuffle() -> void:
	_deck.shuffle()

func draw() -> Medallion:
	if _deck.is_empty():
		return null
	return _deck.pop_back()

func get_remaining_count() -> int:
	return _deck.size()
