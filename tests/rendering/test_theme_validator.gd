extends GutTest

func test_validate_valid_theme() -> void:
	var theme: JsonTheme = JsonTheme.load_from_file("res://themes/emoji_simple.json")
	var errors: Array[String] = ThemeValidator.validate_theme(theme)

	assert_eq(errors.size(), 0, "Valid theme should have no errors")

func test_validate_theme_missing_name() -> void:
	var theme: JsonTheme = JsonTheme.new()
	theme.theme_data = {
		"theme_version": "1.0.0",
		"renderer_type": "label",
		"entities": {},
		"ui_icons": {}
	}
	theme._parse_metadata()

	var errors: Array[String] = ThemeValidator.validate_theme(theme)

	assert_true(errors.size() > 0, "Should have errors for missing theme_name")
	assert_true("Missing 'theme_name'" in errors, "Should report missing theme_name")

func test_validate_theme_missing_entities_section() -> void:
	var theme: JsonTheme = JsonTheme.new()
	theme.theme_data = {
		"theme_name": "test_theme",
		"theme_version": "1.0.0",
		"renderer_type": "label",
		"ui_icons": {}
	}
	theme._parse_metadata()

	var errors: Array[String] = ThemeValidator.validate_theme(theme)

	assert_true(errors.size() > 0, "Should have errors for missing entities section")
	assert_true("Missing 'entities' section" in errors, "Should report missing entities")

func test_validate_label_entity_missing_emoji() -> void:
	var theme: JsonTheme = JsonTheme.new()
	theme.theme_data = {
		"theme_name": "test_theme",
		"theme_version": "1.0.0",
		"renderer_type": "label",
		"entities": {
			"test_entity": {
				"renderer_type": "label",
				"font_size": 32,
				"bounds": [48, 48]
			}
		},
		"ui_icons": {}
	}
	theme._parse_metadata()

	var errors: Array[String] = ThemeValidator.validate_theme(theme)

	assert_true(errors.size() > 0, "Should have errors for label entity without emoji")
	var has_emoji_error: bool = false
	for error in errors:
		if "missing 'emoji'" in error:
			has_emoji_error = true
			break
	assert_true(has_emoji_error, "Should report missing emoji field")

func test_validate_label_entity_missing_bounds() -> void:
	var theme: JsonTheme = JsonTheme.new()
	theme.theme_data = {
		"theme_name": "test_theme",
		"theme_version": "1.0.0",
		"renderer_type": "label",
		"entities": {
			"test_entity": {
				"renderer_type": "label",
				"emoji": "🎮",
				"font_size": 32
			}
		},
		"ui_icons": {}
	}
	theme._parse_metadata()

	var errors: Array[String] = ThemeValidator.validate_theme(theme)

	assert_true(errors.size() > 0, "Should have errors for label entity without bounds")
	var has_bounds_error: bool = false
	for error in errors:
		if "missing 'bounds'" in error:
			has_bounds_error = true
			break
	assert_true(has_bounds_error, "Should report missing bounds field")
