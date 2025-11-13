extends GutTest

const StatusBar = preload("res://scripts/ui/status_bars/status_bar.gd")

# Basic functionality
func test_creates_progress_bar():
	var status_bar = StatusBar.new()
	add_child_autofree(status_bar)
	status_bar.initialize()

	assert_not_null(status_bar.get_bar(), "Should create a ProgressBar")

func test_initializes_with_defaults():
	var status_bar = StatusBar.new()
	add_child_autofree(status_bar)
	status_bar.initialize()

	var bar = status_bar.get_bar()
	assert_eq(bar.custom_minimum_size.x, 40.0, "Default width should be 40")
	assert_eq(bar.custom_minimum_size.y, 6.0, "Default height should be 6")
	assert_eq(bar.position, Vector2.ZERO, "Default position should be zero")

func test_initializes_with_config():
	var status_bar = StatusBar.new()
	add_child_autofree(status_bar)
	status_bar.initialize({
		"width": 100.0,
		"height": 10.0,
		"position": Vector2(50, 25),
		"bg_color": Color.BLACK,
		"fill_color": Color.GREEN
	})

	var bar = status_bar.get_bar()
	assert_eq(bar.custom_minimum_size.x, 100.0, "Should use custom width")
	assert_eq(bar.custom_minimum_size.y, 10.0, "Should use custom height")
	assert_eq(bar.position, Vector2(50, 25), "Should use custom position")

# Value updates
func test_set_value_updates_current_and_max():
	var status_bar = StatusBar.new()
	add_child_autofree(status_bar)
	status_bar.initialize()

	status_bar.set_value(75, 150)

	var bar = status_bar.get_bar()
	assert_eq(bar.value, 75.0, "Should set current value")
	assert_eq(bar.max_value, 150.0, "Should set max value")

func test_set_value_handles_zero_health():
	var status_bar = StatusBar.new()
	add_child_autofree(status_bar)
	status_bar.initialize()

	status_bar.set_value(0, 100)

	var bar = status_bar.get_bar()
	assert_eq(bar.value, 0.0, "Should handle zero health")

# Sizing
func test_set_size_updates_dimensions():
	var status_bar = StatusBar.new()
	add_child_autofree(status_bar)
	status_bar.initialize()

	status_bar.set_size(80.0, 12.0)

	var bar = status_bar.get_bar()
	assert_eq(bar.custom_minimum_size.x, 80.0, "Should update width")
	assert_eq(bar.custom_minimum_size.y, 12.0, "Should update height")

func test_size_persists_after_initialization():
	var status_bar = StatusBar.new()
	add_child_autofree(status_bar)
	status_bar.initialize({"width": 50.0, "height": 8.0})

	var bar = status_bar.get_bar()
	assert_eq(bar.custom_minimum_size.x, 50.0, "Width should persist")
	assert_eq(bar.custom_minimum_size.y, 8.0, "Height should persist")

# Positioning
func test_set_position_offset_moves_bar():
	var status_bar = StatusBar.new()
	add_child_autofree(status_bar)
	status_bar.initialize()

	status_bar.set_position_offset(Vector2(100, 200))

	var bar = status_bar.get_bar()
	assert_eq(bar.position, Vector2(100, 200), "Should move bar to new position")

func test_position_defaults_to_zero():
	var status_bar = StatusBar.new()
	add_child_autofree(status_bar)
	status_bar.initialize()

	var bar = status_bar.get_bar()
	assert_eq(bar.position, Vector2.ZERO, "Default position should be zero")

# Styling
func test_set_colors_updates_background():
	var status_bar = StatusBar.new()
	add_child_autofree(status_bar)
	status_bar.initialize()

	status_bar.set_colors(Color.BLACK, Color.WHITE)

	var bar = status_bar.get_bar()
	var style_bg = bar.get_theme_stylebox("background")
	assert_eq(style_bg.bg_color, Color.BLACK, "Should update background color")

func test_set_colors_updates_fill():
	var status_bar = StatusBar.new()
	add_child_autofree(status_bar)
	status_bar.initialize()

	status_bar.set_colors(Color.BLACK, Color.WHITE)

	var bar = status_bar.get_bar()
	var style_fg = bar.get_theme_stylebox("fill")
	assert_eq(style_fg.bg_color, Color.WHITE, "Should update fill color")

func test_custom_colors_in_initialize():
	var status_bar = StatusBar.new()
	add_child_autofree(status_bar)
	status_bar.initialize({
		"bg_color": Color.BLUE,
		"fill_color": Color.YELLOW
	})

	var bar = status_bar.get_bar()
	var style_bg = bar.get_theme_stylebox("background")
	var style_fg = bar.get_theme_stylebox("fill")
	assert_eq(style_bg.bg_color, Color.BLUE, "Should use custom background color")
	assert_eq(style_fg.bg_color, Color.YELLOW, "Should use custom fill color")

# Accessor
func test_get_bar_returns_progress_bar():
	var status_bar = StatusBar.new()
	add_child_autofree(status_bar)
	status_bar.initialize()

	var bar = status_bar.get_bar()
	assert_true(bar is ProgressBar, "Should return ProgressBar instance")

# Visibility and auto-hide
func test_bar_visible_by_default():
	var status_bar = StatusBar.new()
	add_child_autofree(status_bar)
	status_bar.initialize()

	var bar = status_bar.get_bar()
	assert_true(bar.visible, "Bar should be visible by default")
	assert_true(status_bar.is_visible_flag, "is_visible_flag should be true by default")

func test_bar_hidden_when_auto_hide_enabled():
	var status_bar = StatusBar.new()
	add_child_autofree(status_bar)
	status_bar.initialize({"auto_hide": true})

	var bar = status_bar.get_bar()
	assert_false(bar.visible, "Bar should be hidden initially with auto_hide")
	assert_false(status_bar.is_visible_flag, "is_visible_flag should be false with auto_hide")

func test_bar_shows_on_set_value_with_auto_hide():
	var status_bar = StatusBar.new()
	add_child_autofree(status_bar)
	status_bar.initialize({"auto_hide": true})

	status_bar.set_value(80, 100)

	var bar = status_bar.get_bar()
	assert_true(bar.visible, "Bar should be visible after set_value with auto_hide")
	assert_true(status_bar.is_visible_flag, "is_visible_flag should be true after set_value")

func test_show_and_hide_bar():
	var status_bar = StatusBar.new()
	add_child_autofree(status_bar)
	status_bar.initialize()

	status_bar.hide_bar()
	var bar = status_bar.get_bar()
	assert_false(bar.visible, "Bar should be hidden after hide_bar()")
	assert_false(status_bar.is_visible_flag, "is_visible_flag should be false after hide_bar()")

	status_bar.show_bar()
	assert_true(bar.visible, "Bar should be visible after show_bar()")
	assert_true(status_bar.is_visible_flag, "is_visible_flag should be true after show_bar()")

# Color interpolation
func test_static_color_mode_by_default():
	var status_bar = StatusBar.new()
	add_child_autofree(status_bar)
	status_bar.initialize()

	assert_eq(status_bar.color_mode, StatusBar.ColorMode.STATIC, "Default color mode should be STATIC")

func test_interpolated_color_mode_in_config():
	var status_bar = StatusBar.new()
	add_child_autofree(status_bar)
	status_bar.initialize({"color_mode": StatusBar.ColorMode.INTERPOLATED})

	assert_eq(status_bar.color_mode, StatusBar.ColorMode.INTERPOLATED, "Should use INTERPOLATED mode from config")

func test_bar_color_changes_with_health_interpolated():
	var status_bar = StatusBar.new()
	add_child_autofree(status_bar)
	status_bar.initialize({"color_mode": StatusBar.ColorMode.INTERPOLATED})

	# Full health - should be green
	status_bar.set_value(100, 100)
	var bar = status_bar.get_bar()
	var style_full = bar.get_theme_stylebox("fill")

	# Low health - should be red
	status_bar.set_value(10, 100)
	var style_low = bar.get_theme_stylebox("fill")

	# Colors should be different
	assert_ne(style_full.bg_color, style_low.bg_color, "Bar color should change with health percentage in INTERPOLATED mode")

func test_bar_color_stays_same_with_health_static():
	var status_bar = StatusBar.new()
	add_child_autofree(status_bar)
	var initial_color = Color.GREEN
	status_bar.initialize({
		"color_mode": StatusBar.ColorMode.STATIC,
		"fill_color": initial_color
	})

	# Full health
	status_bar.set_value(100, 100)
	var bar = status_bar.get_bar()
	var style_full = bar.get_theme_stylebox("fill")

	# Low health
	status_bar.set_value(10, 100)
	var style_low = bar.get_theme_stylebox("fill")

	# Colors should be the same in STATIC mode
	assert_eq(style_full.bg_color, style_low.bg_color, "Bar color should not change with health in STATIC mode")
