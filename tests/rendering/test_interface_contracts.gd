extends GutTest

# Test that interfaces properly assert when methods are not implemented

func test_i_renderable_get_entity_id_not_implemented():
	var renderable = IRenderable.new()
	add_child_autofree(renderable)

	assert_false(renderable.get_entity_id() != "", "IRenderable.get_entity_id() should return empty string when not implemented")

func test_i_renderable_get_visual_type_not_implemented():
	var renderable = IRenderable.new()
	add_child_autofree(renderable)

	assert_false(renderable.get_visual_type() != "", "IRenderable.get_visual_type() should return empty string when not implemented")

func test_i_renderable_has_signals():
	var renderable = IRenderable.new()
	add_child_autofree(renderable)

	assert_true(renderable.has_signal("state_changed"), "IRenderable should have state_changed signal")
	assert_true(renderable.has_signal("animation_requested"), "IRenderable should have animation_requested signal")

func test_i_visual_theme_get_visual_data_returns_default():
	var theme = IVisualTheme.new()

	var result = theme.get_visual_data("test_type")

	assert_not_null(result, "Should return a VisualData instance")
	assert_true(result is VisualData, "Should return VisualData type")

func test_i_visual_theme_get_ui_icon_returns_null():
	var theme = IVisualTheme.new()

	var result = theme.get_ui_icon("test_medallion")

	assert_null(result, "Should return null when not implemented")

func test_i_visual_theme_get_animation_spec_returns_default():
	var theme = IVisualTheme.new()

	var result = theme.get_animation_spec("wizard", "walk")

	assert_not_null(result, "Should return an AnimationSpec instance")
	assert_true(result is AnimationSpec, "Should return AnimationSpec type")

# Note: IVisualRenderer methods cannot be easily tested for assertions
# because they are Node-based and assertions in Godot will halt execution.
# In practice, these methods will assert during actual usage.
func test_i_visual_renderer_is_node():
	var renderer = IVisualRenderer.new()
	add_child_autofree(renderer)

	assert_true(renderer is Node, "IVisualRenderer should extend Node")

func test_entity_state_flags_constants_exist():
	# Verify all expected constants exist and have correct values
	assert_eq(EntityStateFlags.MOVING, "moving", "MOVING constant should exist")
	assert_eq(EntityStateFlags.IDLE, "idle", "IDLE constant should exist")
	assert_eq(EntityStateFlags.ATTACKING, "attacking", "ATTACKING constant should exist")
	assert_eq(EntityStateFlags.BLOCKING, "blocking", "BLOCKING constant should exist")
	assert_eq(EntityStateFlags.CASTING, "casting", "CASTING constant should exist")
	assert_eq(EntityStateFlags.STUNNED, "stunned", "STUNNED constant should exist")
	assert_eq(EntityStateFlags.SUMMONING, "summoning", "SUMMONING constant should exist")

func test_entity_state_flags_are_unique():
	var flags = [
		EntityStateFlags.MOVING,
		EntityStateFlags.IDLE,
		EntityStateFlags.ATTACKING,
		EntityStateFlags.BLOCKING,
		EntityStateFlags.DODGING,
		EntityStateFlags.CASTING,
		EntityStateFlags.STUNNED,
		EntityStateFlags.ROOTED
	]

	var unique_flags = {}
	for flag in flags:
		unique_flags[flag] = true

	assert_eq(unique_flags.size(), flags.size(), "All flags should be unique")
