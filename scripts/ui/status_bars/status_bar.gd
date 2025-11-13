extends Node2D
class_name StatusBar

# Consolidated bar component that handles health/mana bars with optional features
# Combines functionality from HealthBar and CreatureHealthBar

enum ColorMode { STATIC, INTERPOLATED }

var bar: ProgressBar
var color_mode: ColorMode = ColorMode.STATIC

# Bar configuration
var bar_width: float = 40.0
var bar_height: float = 6.0
var bar_position: Vector2 = Vector2.ZERO
var background_color: Color = Color(0.2, 0.2, 0.2, 0.8)
var fill_color: Color = Color(0.8, 0.2, 0.2, 1.0)

# Optional features
var auto_hide: bool = false
var is_visible_flag: bool = false

func initialize(config: Dictionary = {}) -> void:
	# Apply configuration
	bar_width = config.get("width", bar_width)
	bar_height = config.get("height", bar_height)
	bar_position = config.get("position", bar_position)
	background_color = config.get("bg_color", background_color)
	fill_color = config.get("fill_color", fill_color)
	color_mode = config.get("color_mode", ColorMode.STATIC)
	auto_hide = config.get("auto_hide", auto_hide)

	# Create and configure bar
	_create_bar()

	# Initialize visibility based on auto_hide
	if auto_hide:
		hide_bar()
	else:
		is_visible_flag = true

func _create_bar() -> void:
	bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(bar_width, bar_height)
	bar.position = bar_position
	bar.max_value = 100
	bar.value = 100
	bar.show_percentage = false

	# Apply styling
	_apply_styles()

	add_child(bar)

func _apply_styles() -> void:
	var style_bg: StyleBoxFlat = StyleBoxFlat.new()
	style_bg.bg_color = background_color
	bar.add_theme_stylebox_override("background", style_bg)

	var style_fg: StyleBoxFlat = StyleBoxFlat.new()
	style_fg.bg_color = fill_color
	bar.add_theme_stylebox_override("fill", style_fg)

func set_value(current: float, maximum: float) -> void:
	if auto_hide and not is_visible_flag:
		show_bar()

	if bar:
		bar.max_value = maximum
		bar.value = current

		# Update color if interpolation mode is enabled
		if color_mode == ColorMode.INTERPOLATED:
			_update_bar_color(current, maximum)

func _update_bar_color(current: float, maximum: float) -> void:
	var health_percent: float = current / maximum if maximum > 0 else 0
	var new_color: Color

	# Interpolate from green (full health) to red (low health)
	if health_percent > 0.5:
		# Green to yellow (100% to 50%)
		var t: float = (1.0 - health_percent) * 2.0  # 0 to 1
		new_color = Color(0.2 + t * 0.8, 0.8, 0.2, 1.0)
	else:
		# Yellow to red (50% to 0%)
		var t: float = health_percent * 2.0  # 0 to 1
		new_color = Color(1.0, 0.2 + t * 0.6, 0.2, 1.0)

	fill_color = new_color
	set_colors(background_color, new_color)

func set_size(width: float, height: float) -> void:
	bar_width = width
	bar_height = height
	if bar:
		bar.custom_minimum_size = Vector2(width, height)

func set_position_offset(pos: Vector2) -> void:
	bar_position = pos
	if bar:
		bar.position = pos

func set_colors(bg_color: Color, fg_color: Color) -> void:
	background_color = bg_color
	fill_color = fg_color
	if bar:
		_apply_styles()

func show_bar() -> void:
	is_visible_flag = true
	if bar:
		bar.visible = true

func hide_bar() -> void:
	is_visible_flag = false
	if bar:
		bar.visible = false

func get_bar() -> ProgressBar:
	return bar
