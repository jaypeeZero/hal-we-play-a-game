class_name ThemeValidator extends RefCounted

static func validate_theme(theme: JsonTheme) -> Array[String]:
	var errors: Array[String] = []

	# Check required fields
	if theme.theme_name == "":
		errors.append("Missing 'theme_name'")

	if theme.renderer_type == "":
		errors.append("Missing 'renderer_type'")

	# Check entities
	if not theme.theme_data.has("entities"):
		errors.append("Missing 'entities' section")
		return errors

	var entities: Dictionary = theme.theme_data["entities"]
	for entity_type in entities:
		var entity_errors: Array[String] = _validate_entity(entity_type, entities[entity_type], theme.renderer_type)
		errors.append_array(entity_errors)

	return errors

static func _validate_entity(entity_type: String, data: Dictionary, default_renderer: String) -> Array[String]:
	var errors: Array[String] = []
	var renderer: String = data.get("renderer_type", default_renderer)

	match renderer:
		"label":
			if not data.has("emoji"):
				errors.append("Entity '%s': missing 'emoji'" % entity_type)
			if not data.has("bounds"):
				errors.append("Entity '%s': missing 'bounds'" % entity_type)

		"sprite_2d":
			if not data.has("sprite_sheet"):
				errors.append("Entity '%s': missing 'sprite_sheet'" % entity_type)
			if not data.has("frame_size"):
				errors.append("Entity '%s': missing 'frame_size'" % entity_type)

			# Validate sprite sheet exists
			var sprite_path: String = data.get("sprite_sheet", "")
			if not ResourceLoader.exists(sprite_path):
				errors.append("Entity '%s': sprite_sheet not found: %s" % [entity_type, sprite_path])

	return errors
