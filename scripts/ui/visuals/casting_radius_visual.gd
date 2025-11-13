extends Node2D
class_name CastingRadiusVisual

var main_radius: float = 200.0
var target_position: Vector2 = Vector2.ZERO
var cursor_radius: float = 15.0
var line_width: float = 2.0
var main_circle_color: Color = Color.WHITE
var cursor_circle_color: Color = Color(1.0, 1.0, 1.0, 0.7)  # Slightly transparent white

func _ready() -> void:
	# Start hidden, will be shown by Battlefield
	visible = false

func set_radius(new_radius: float) -> void:
	if main_radius != new_radius:
		main_radius = new_radius
		queue_redraw()

func set_target_position(mouse_pos: Vector2, caster_pos: Vector2) -> void:
	# Calculate clamped position
	var direction: Vector2 = mouse_pos - caster_pos
	var distance: float = direction.length()

	if distance > main_radius:
		# Clamp to circle edge
		target_position = caster_pos + direction.normalized() * main_radius
	else:
		target_position = mouse_pos

	queue_redraw()

func show_visual() -> void:
	visible = true

func hide_visual() -> void:
	visible = false

func _draw() -> void:
	# Draw main casting radius circle
	_draw_circle_outline(Vector2.ZERO, main_radius, main_circle_color, line_width)

	# Draw target cursor circle (relative to target_position, but we need it in local coords)
	var local_target_pos: Vector2 = target_position - global_position
	draw_circle(local_target_pos, cursor_radius, cursor_circle_color)

func _draw_circle_outline(center: Vector2, radius: float, color: Color, width: float) -> void:
	# Draw circle as many small line segments
	var segments: int = 64
	var points: PackedVector2Array = []

	for i: int in range(segments + 1):
		var angle: float = (i / float(segments)) * TAU
		var x: float = center.x + cos(angle) * radius
		var y: float = center.y + sin(angle) * radius
		points.append(Vector2(x, y))

	# Draw the outline using multiple small lines
	for i: int in range(segments):
		draw_line(points[i], points[i + 1], color, width)
