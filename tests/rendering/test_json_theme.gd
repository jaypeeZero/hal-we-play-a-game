extends GutTest

var theme: JsonTheme

func before_each() -> void:
	theme = null

func test_load_emoji_theme() -> void:
	theme = JsonTheme.load_from_file("res://themes/emoji_simple.json")

	assert_not_null(theme, "Theme should load")
	assert_eq(theme.theme_name, "emoji_simple", "Theme name should match")
	assert_eq(theme.theme_version, "1.0.0", "Theme version should match")
	assert_eq(theme.renderer_type, "label", "Renderer type should be label")

func test_get_visual_data_wizard() -> void:
	theme = JsonTheme.load_from_file("res://themes/emoji_simple.json")
	var visual_data: VisualData = theme.get_visual_data("wizard_player")

	assert_not_null(visual_data, "Should return visual data")
	assert_eq(visual_data.emoji, "🧙", "Should have wizard emoji")
	assert_eq(visual_data.font_size, 32, "Should have correct font size")
	assert_eq(visual_data.renderer_type, "label", "Should be label renderer")
	assert_eq(visual_data.bounds, Vector2(48, 48), "Should have correct bounds")

func test_get_visual_data_olophant() -> void:
	theme = JsonTheme.load_from_file("res://themes/emoji_simple.json")
	var visual_data: VisualData = theme.get_visual_data("creature_olophant")

	assert_not_null(visual_data, "Should return visual data")
	assert_eq(visual_data.emoji, "🐘", "Should have elephant emoji")
	assert_eq(visual_data.font_size, 56, "Should have correct font size")
	assert_eq(visual_data.bounds, Vector2(72, 72), "Should have correct bounds")

func test_get_visual_data_projectile() -> void:
	theme = JsonTheme.load_from_file("res://themes/emoji_simple.json")
	var visual_data: VisualData = theme.get_visual_data("projectile_fireball")

	assert_not_null(visual_data, "Should return visual data")
	assert_eq(visual_data.emoji, "🔥", "Should have fire emoji")
	assert_eq(visual_data.font_size, 16, "Should have correct font size")
	assert_eq(visual_data.bounds, Vector2(20, 20), "Should have correct bounds")

func test_missing_entity_returns_default() -> void:
	theme = JsonTheme.load_from_file("res://themes/emoji_simple.json")
	var visual_data: VisualData = theme.get_visual_data("nonexistent_entity")

	assert_not_null(visual_data, "Should return default visual data")
	assert_eq(visual_data.emoji, "❓", "Should have question mark emoji as default")
	assert_eq(visual_data.font_size, 16, "Should have default font size")
	assert_eq(visual_data.bounds, Vector2(20, 20), "Should have default bounds")

func test_caching_returns_same_instance() -> void:
	theme = JsonTheme.load_from_file("res://themes/emoji_simple.json")

	var data1: VisualData = theme.get_visual_data("wizard_player")
	var data2: VisualData = theme.get_visual_data("wizard_player")

	assert_same(data1, data2, "Should return cached instance")

func test_get_ui_icon_emoji() -> void:
	theme = JsonTheme.load_from_file("res://themes/emoji_simple.json")
	var icon: Variant = theme.get_ui_icon("fireball")

	assert_eq(icon, "🔥", "Should return emoji string for UI icon")

func test_get_ui_icon_missing() -> void:
	theme = JsonTheme.load_from_file("res://themes/emoji_simple.json")
	var icon: Variant = theme.get_ui_icon("nonexistent_medallion")

	assert_eq(icon, "❓", "Should return question mark for missing icon")

func test_reload_clears_cache() -> void:
	theme = JsonTheme.load_from_file("res://themes/emoji_simple.json")

	var data1: VisualData = theme.get_visual_data("wizard_player")
	theme.reload()
	var data2: VisualData = theme.get_visual_data("wizard_player")

	assert_ne(data1, data2, "Should return new instance after reload")

func test_get_animation_spec_for_missing_animation() -> void:
	theme = JsonTheme.load_from_file("res://themes/emoji_simple.json")
	var anim_spec: AnimationSpec = theme.get_animation_spec("wizard_player", "nonexistent_animation")

	assert_not_null(anim_spec, "Should return empty AnimationSpec")
	assert_eq(anim_spec.frames.size(), 0, "Should have no frames")
	assert_eq(anim_spec.fps, 10, "Should have default FPS")
	assert_true(anim_spec.loop, "Should default to loop")

func test_load_invalid_json_returns_empty_theme() -> void:
	theme = JsonTheme.load_from_file("res://nonexistent.json")

	assert_not_null(theme, "Should return theme object even if file doesn't exist")
	assert_eq(theme.theme_name, "unknown", "Should have default name")
