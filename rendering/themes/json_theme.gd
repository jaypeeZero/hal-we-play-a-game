class_name JsonTheme extends IVisualTheme

var theme_data: Dictionary = {}
var theme_name: String = ""
var theme_version: String = ""
var renderer_type: String = ""

var _visual_cache: Dictionary = {}  # entity_type -> VisualData
var _icon_cache: Dictionary = {}    # medallion_id -> Variant

## Load theme from JSON file
static func load_from_file(json_path: String) -> JsonTheme:
	var theme: JsonTheme = JsonTheme.new()

	if not FileAccess.file_exists(json_path):
		push_error("Theme file not found: %s" % json_path)
		return theme

	var file: FileAccess = FileAccess.open(json_path, FileAccess.READ)
	if not file:
		push_error("Failed to open theme file: %s" % json_path)
		return theme

	var json_string: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	var parse_result: int = json.parse(json_string)

	if parse_result != OK:
		push_error("Failed to parse theme JSON: %s (line %d)" % [json_path, json.get_error_line()])
		return theme

	theme.theme_data = json.data
	theme._parse_metadata()
	theme._validate_schema()

	return theme

func _parse_metadata() -> void:
	theme_name = theme_data.get("theme_name", "unknown")
	theme_version = theme_data.get("theme_version", "0.0.0")
	renderer_type = theme_data.get("renderer_type", "label")

	print("Loaded theme: %s v%s (renderer: %s)" % [theme_name, theme_version, renderer_type])

func _validate_schema() -> void:
	if not theme_data.has("entities"):
		push_warning("Theme has no 'entities' section")

	if not theme_data.has("ui_icons"):
		push_warning("Theme has no 'ui_icons' section")

	# Validate required fields per renderer type
	var entities: Dictionary = theme_data.get("entities", {})
	for entity_type in entities:
		var entity_data: Dictionary = entities[entity_type]
		var entity_renderer: String = entity_data.get("renderer_type", renderer_type)

		match entity_renderer:
			"label":
				if not entity_data.has("emoji"):
					push_warning("Entity '%s' is type 'label' but has no 'emoji' field" % entity_type)
			"sprite_2d":
				if not entity_data.has("sprite_sheet"):
					push_warning("Entity '%s' is type 'sprite_2d' but has no 'sprite_sheet' field" % entity_type)

## Implements IVisualTheme.get_visual_data()
func get_visual_data(entity_type: String) -> VisualData:
	# Check cache first
	if entity_type in _visual_cache:
		return _visual_cache[entity_type]

	# Load from JSON
	var entities: Dictionary = theme_data.get("entities", {})
	var entity_data: Dictionary = entities.get(entity_type, {})

	if entity_data.is_empty():
		push_warning("No visual data for entity type: %s (using default)" % entity_type)
		entity_data = _get_default_entity_data()

	# Parse and cache
	var visual_data: VisualData = VisualData.from_dict(entity_data)
	_visual_cache[entity_type] = visual_data

	return visual_data

func _get_default_entity_data() -> Dictionary:
	return {
		"renderer_type": "label",
		"emoji": "❓",
		"font_size": 16,
		"bounds": [20, 20]
	}

## Implements IVisualTheme.get_ui_icon()
func get_ui_icon(medallion_id: String) -> Variant:
	# Check cache
	if medallion_id in _icon_cache:
		return _icon_cache[medallion_id]

	var icons: Dictionary = theme_data.get("ui_icons", {})
	var icon_value: Variant = icons.get(medallion_id, "")

	if icon_value == "":
		push_warning("No UI icon for medallion: %s" % medallion_id)
		return "❓"

	# If it's a file path, load texture
	if icon_value is String and icon_value.ends_with(".png"):
		if ResourceLoader.exists(icon_value):
			var texture: Texture2D = load(icon_value) as Texture2D
			_icon_cache[medallion_id] = texture
			return texture
		else:
			push_error("Icon texture not found: %s" % icon_value)
			return "❓"

	# Otherwise it's an emoji string
	_icon_cache[medallion_id] = icon_value
	return icon_value

## Implements IVisualTheme.get_animation_spec()
func get_animation_spec(entity_type: String, anim_name: String) -> AnimationSpec:
	var visual_data: VisualData = get_visual_data(entity_type)

	if anim_name in visual_data.animations:
		return visual_data.animations[anim_name]

	push_warning("Animation '%s' not found for entity '%s'" % [anim_name, entity_type])
	return AnimationSpec.new()  # Empty fallback

## Hot-reload theme (clear cache and reload)
func reload() -> void:
	_visual_cache.clear()
	_icon_cache.clear()
	print("Theme cache cleared: %s" % theme_name)
