extends Node2D
class_name PlayerStatusBars

const StatusBar = preload("res://scripts/ui/status_bars/status_bar.gd")

# UI component that displays health and mana bars for a player
# Positioned at the bottom corners of the player character

var health_bar: StatusBar
var mana_bar: StatusBar

const BASE_BAR_WIDTH = 40.0
const BASE_BAR_HEIGHT = 6.0
const BASE_OFFSET_X = 20.0  # Distance from center to bar
const BASE_OFFSET_Y = 25.0  # Distance below center

var _ui_scale: float = 1.0

func _ready() -> void:
	_ui_scale = _calculate_scale()
	_create_bars()
	get_viewport().size_changed.connect(_on_viewport_resized)

func _calculate_scale() -> float:
	var viewport_height: float = get_viewport().get_visible_rect().size.y
	return viewport_height / 720.0

func _on_viewport_resized() -> void:
	_ui_scale = _calculate_scale()
	_update_bar_sizes()
	_update_bar_positions()

func _update_bar_sizes() -> void:
	var width: float = BASE_BAR_WIDTH * _ui_scale
	var height: float = BASE_BAR_HEIGHT * _ui_scale
	health_bar.set_size(width, height)
	mana_bar.set_size(width, height)

func _update_bar_positions() -> void:
	var offset_x: float = BASE_OFFSET_X * _ui_scale
	var offset_y: float = BASE_OFFSET_Y * _ui_scale
	health_bar.set_position_offset(Vector2(-offset_x - BASE_BAR_WIDTH * _ui_scale, offset_y))
	mana_bar.set_position_offset(Vector2(offset_x, offset_y))

func _create_bars() -> void:
	# Create health bar
	health_bar = StatusBar.new()
	add_child(health_bar)
	health_bar.initialize({
		"width": BASE_BAR_WIDTH * _ui_scale,
		"height": BASE_BAR_HEIGHT * _ui_scale,
		"position": Vector2(-BASE_OFFSET_X * _ui_scale - BASE_BAR_WIDTH * _ui_scale, BASE_OFFSET_Y * _ui_scale),
		"bg_color": Color(0.2, 0.2, 0.2, 0.8),
		"fill_color": Color(0.8, 0.2, 0.2, 1.0),
		"color_mode": StatusBar.ColorMode.STATIC
	})
	health_bar.get_bar().name = "HealthBar"

	# Create mana bar
	mana_bar = StatusBar.new()
	add_child(mana_bar)
	mana_bar.initialize({
		"width": BASE_BAR_WIDTH * _ui_scale,
		"height": BASE_BAR_HEIGHT * _ui_scale,
		"position": Vector2(BASE_OFFSET_X * _ui_scale, BASE_OFFSET_Y * _ui_scale),
		"bg_color": Color(0.2, 0.2, 0.2, 0.8),
		"fill_color": Color(0.2, 0.4, 0.8, 1.0),
		"color_mode": StatusBar.ColorMode.STATIC
	})
	mana_bar.get_bar().name = "ManaBar"

func set_health(current: float, maximum: float) -> void:
	if health_bar:
		health_bar.set_value(current, maximum)

func set_mana(current: float, maximum: float) -> void:
	if mana_bar:
		mana_bar.set_value(current, maximum)
