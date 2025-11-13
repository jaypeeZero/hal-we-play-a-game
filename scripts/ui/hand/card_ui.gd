extends Control
class_name CardUI

const Medallion = preload("res://scripts/core/game_systems/medallion.gd")

const BASE_WIDTH = 80
const BASE_HEIGHT = 110
const BASE_PADDING = 5

var _medallion: Medallion
var _keybind: String
var _ui_scale: float = 1.0
var _is_selected: bool = false

# UI elements
var _background: ColorRect
var _name_label: Label
var _cost_label: Label
var _icon_label: Label
var _keybind_label: Label

# Animation
var _tween: Tween
var _is_animating: bool = false

func _init() -> void:
	custom_minimum_size = Vector2(BASE_WIDTH, BASE_HEIGHT) * _ui_scale
	size = Vector2(BASE_WIDTH, BASE_HEIGHT) * _ui_scale

func _ready() -> void:
	_setup_ui()

func update_scale(scale: float) -> void:
	_ui_scale = scale
	custom_minimum_size = Vector2(BASE_WIDTH, BASE_HEIGHT) * scale
	size = Vector2(BASE_WIDTH, BASE_HEIGHT) * scale

	# Update UI elements if they exist
	if _background:
		_background.size = size

	if _name_label:
		_name_label.add_theme_font_size_override("font_size", int(10 * scale))

	if _cost_label:
		_cost_label.add_theme_font_size_override("font_size", int(10 * scale))

	if _icon_label:
		_icon_label.add_theme_font_size_override("font_size", int(32 * scale))
		_icon_label.position = Vector2(BASE_WIDTH * scale / 2 - 20 * scale, 45 * scale)
		_icon_label.size = Vector2(40 * scale, 40 * scale)

	if _keybind_label:
		_keybind_label.add_theme_font_size_override("font_size", int(12 * scale))
		_keybind_label.position = Vector2(BASE_PADDING * scale, BASE_HEIGHT * scale - 20 * scale - BASE_PADDING * scale)
		_keybind_label.size = Vector2(BASE_WIDTH * scale - BASE_PADDING * 2 * scale, 20 * scale)

func _setup_ui() -> void:
	# Background
	_background = ColorRect.new()
	_background.size = size
	_background.color = Color(0.2, 0.2, 0.25, 0.9)
	add_child(_background)

	# Name and cost (top section)
	var top_container: VBoxContainer = VBoxContainer.new()
	top_container.position = Vector2(BASE_PADDING * _ui_scale, BASE_PADDING * _ui_scale)
	top_container.size = Vector2(BASE_WIDTH * _ui_scale - BASE_PADDING * 2 * _ui_scale, 30 * _ui_scale)
	add_child(top_container)

	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", int(10 * _ui_scale))
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	top_container.add_child(_name_label)

	_cost_label = Label.new()
	_cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cost_label.add_theme_font_size_override("font_size", int(10 * _ui_scale))
	_cost_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
	top_container.add_child(_cost_label)

	# Icon (middle section)
	_icon_label = Label.new()
	_icon_label.position = Vector2(BASE_WIDTH * _ui_scale / 2 - 20 * _ui_scale, 45 * _ui_scale)
	_icon_label.size = Vector2(40 * _ui_scale, 40 * _ui_scale)
	_icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_icon_label.add_theme_font_size_override("font_size", int(32 * _ui_scale))
	add_child(_icon_label)

	# Keybind (bottom section)
	_keybind_label = Label.new()
	_keybind_label.position = Vector2(BASE_PADDING * _ui_scale, BASE_HEIGHT * _ui_scale - 20 * _ui_scale - BASE_PADDING * _ui_scale)
	_keybind_label.size = Vector2(BASE_WIDTH * _ui_scale - BASE_PADDING * 2 * _ui_scale, 20 * _ui_scale)
	_keybind_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_keybind_label.add_theme_font_size_override("font_size", int(12 * _ui_scale))
	_keybind_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	add_child(_keybind_label)

func set_medallion(medallion: Medallion) -> void:
	_medallion = medallion
	_update_display()

func set_keybind(key: String) -> void:
	_keybind = key
	if _keybind_label:
		_keybind_label.text = key

func set_selected(is_selected: bool) -> void:
	_is_selected = is_selected
	if _background:
		if is_selected:
			_background.color = Color(0.4, 0.6, 0.3, 0.9)  # Green highlight
		else:
			_background.color = Color(0.2, 0.2, 0.25, 0.9)  # Default color

func _update_display() -> void:
	if not _medallion:
		return

	_name_label.text = _medallion.get_medallion_name()
	_cost_label.text = str(int(_medallion.get_medallion_cost())) + " mana"
	_icon_label.text = _medallion.get_medallion_icon()

func animate_suck_out() -> void:
	if _is_animating:
		return
	_is_animating = true

	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, "scale", Vector2(0.1, 0.1), 0.2)
	_tween.tween_property(self, "modulate:a", 0.0, 0.2)
	_tween.set_parallel(false)
	await _tween.finished

func animate_blorp_in() -> void:
	scale = Vector2(0.1, 0.1)
	modulate.a = 0.0

	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, "scale", Vector2(1.2, 1.2), 0.15)
	_tween.tween_property(self, "modulate:a", 1.0, 0.15)
	_tween.set_parallel(false)
	_tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1)
	await _tween.finished
	_is_animating = false
