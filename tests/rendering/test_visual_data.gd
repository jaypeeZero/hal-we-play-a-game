extends GutTest

func test_visual_data_default_values():
	var vd = VisualData.new()

	assert_eq(vd.renderer_type, "label", "Renderer type should default to label")
	assert_eq(vd.sprite_sheet_path, "", "Sprite sheet path should be empty")
	assert_eq(vd.frame_size, Vector2.ZERO, "Frame size should be ZERO")
	assert_eq(vd.sprite_offset, Vector2.ZERO, "Sprite offset should be ZERO")
	assert_eq(vd.bounds, Vector2.ZERO, "Bounds should be ZERO")
	assert_false(vd.shadow_enabled, "Shadow should be disabled")
	assert_eq(vd.shadow_texture_path, "", "Shadow texture path should be empty")
	assert_eq(vd.shadow_opacity, 0.3, "Shadow opacity should default to 0.3")
	assert_eq(vd.emoji, "", "Emoji should be empty")
	assert_eq(vd.font_size, 16, "Font size should default to 16")
	assert_eq(vd.animations.size(), 0, "Animations should be empty")

func test_from_dict_emoji_configuration():
	var dict = {
		"renderer_type": "label",
		"emoji": "🧙",
		"font_size": 24
	}

	var vd = VisualData.from_dict(dict)

	assert_eq(vd.renderer_type, "label", "Should set renderer type")
	assert_eq(vd.emoji, "🧙", "Should set emoji")
	assert_eq(vd.font_size, 24, "Should set font size")

func test_from_dict_sprite_configuration():
	var dict = {
		"renderer_type": "sprite_2d",
		"sprite_sheet": "res://assets/wizard.png",
		"frame_size": [32, 32],
		"sprite_offset": [0, -8],
		"bounds": [24, 24]
	}

	var vd = VisualData.from_dict(dict)

	assert_eq(vd.renderer_type, "sprite_2d", "Should set renderer type")
	assert_eq(vd.sprite_sheet_path, "res://assets/wizard.png", "Should set sprite sheet path")
	assert_eq(vd.frame_size, Vector2(32, 32), "Should parse frame size")
	assert_eq(vd.sprite_offset, Vector2(0, -8), "Should parse sprite offset")
	assert_eq(vd.bounds, Vector2(24, 24), "Should parse bounds")

func test_from_dict_shadow_configuration():
	var dict = {
		"shadow": {
			"enabled": true,
			"texture": "res://assets/shadow.png",
			"opacity": 0.5
		}
	}

	var vd = VisualData.from_dict(dict)

	assert_true(vd.shadow_enabled, "Should enable shadow")
	assert_eq(vd.shadow_texture_path, "res://assets/shadow.png", "Should set shadow texture")
	assert_eq(vd.shadow_opacity, 0.5, "Should set shadow opacity")

func test_from_dict_with_animations():
	var dict = {
		"animations": {
			"walk": {
				"frames": [0, 1, 2, 3],
				"fps": 8,
				"loop": true
			},
			"attack": {
				"frames": [4, 5, 6],
				"fps": 12,
				"loop": false
			}
		}
	}

	var vd = VisualData.from_dict(dict)

	assert_eq(vd.animations.size(), 2, "Should have 2 animations")
	assert_true(vd.animations.has("walk"), "Should have walk animation")
	assert_true(vd.animations.has("attack"), "Should have attack animation")

	var walk_anim = vd.animations["walk"]
	assert_eq(walk_anim.frames, [0, 1, 2, 3], "Walk animation should have correct frames")
	assert_eq(walk_anim.fps, 8, "Walk animation should have correct FPS")
	assert_true(walk_anim.loop, "Walk animation should loop")

	var attack_anim = vd.animations["attack"]
	assert_eq(attack_anim.frames, [4, 5, 6], "Attack animation should have correct frames")
	assert_eq(attack_anim.fps, 12, "Attack animation should have correct FPS")
	assert_false(attack_anim.loop, "Attack animation should not loop")

func test_from_dict_with_missing_fields():
	var dict = {}

	var vd = VisualData.from_dict(dict)

	assert_eq(vd.renderer_type, "label", "Should use default renderer type")
	assert_eq(vd.sprite_sheet_path, "", "Should use default sprite sheet path")
	assert_eq(vd.frame_size, Vector2.ZERO, "Should use default frame size")
	assert_eq(vd.sprite_offset, Vector2.ZERO, "Should use default sprite offset")
	assert_eq(vd.bounds, Vector2.ZERO, "Should use default bounds")
	assert_false(vd.shadow_enabled, "Should use default shadow enabled")
	assert_eq(vd.emoji, "", "Should use default emoji")
	assert_eq(vd.font_size, 16, "Should use default font size")
	assert_eq(vd.animations.size(), 0, "Should have no animations")

func test_from_dict_with_malformed_arrays():
	var dict = {
		"frame_size": [32],  # Incomplete array
		"sprite_offset": [],  # Empty array
		"bounds": [16, 16, 16]  # Too many elements
	}

	var vd = VisualData.from_dict(dict)

	assert_eq(vd.frame_size, Vector2.ZERO, "Should default to ZERO for incomplete array")
	assert_eq(vd.sprite_offset, Vector2.ZERO, "Should default to ZERO for empty array")
	assert_eq(vd.bounds, Vector2(16, 16), "Should use first two elements")

func test_from_dict_complete_configuration():
	var dict = {
		"renderer_type": "sprite_2d",
		"sprite_sheet": "res://sprites/wizard.png",
		"frame_size": [48, 48],
		"sprite_offset": [4, -12],
		"bounds": [32, 40],
		"shadow": {
			"enabled": true,
			"texture": "res://shadows/blob.png",
			"opacity": 0.4
		},
		"emoji": "🧙",
		"font_size": 32,
		"animations": {
			"idle": {
				"frames": [0, 1],
				"fps": 4,
				"loop": true
			}
		}
	}

	var vd = VisualData.from_dict(dict)

	assert_eq(vd.renderer_type, "sprite_2d", "Should set all fields correctly")
	assert_eq(vd.sprite_sheet_path, "res://sprites/wizard.png")
	assert_eq(vd.frame_size, Vector2(48, 48))
	assert_eq(vd.sprite_offset, Vector2(4, -12))
	assert_eq(vd.bounds, Vector2(32, 40))
	assert_true(vd.shadow_enabled)
	assert_eq(vd.shadow_texture_path, "res://shadows/blob.png")
	assert_eq(vd.shadow_opacity, 0.4)
	assert_eq(vd.emoji, "🧙")
	assert_eq(vd.font_size, 32)
	assert_eq(vd.animations.size(), 1)
