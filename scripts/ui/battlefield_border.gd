extends Control
class_name BattlefieldBorder

const BORDER_THICKNESS = 4.0
const BORDER_COLOR = Color(0.4, 0.4, 0.4, 1.0)
const INNER_SHADOW_COLOR = Color(0.1, 0.1, 0.1, 0.5)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _draw() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, size)

	# Draw outer border frame
	draw_rect(rect, BORDER_COLOR, false, BORDER_THICKNESS)

	# Draw inner shadow for depth
	var inner_rect: Rect2 = rect.grow(-BORDER_THICKNESS)
	draw_rect(inner_rect, INNER_SHADOW_COLOR, false, 2.0)
