class_name SkillRadarChart
extends Control

## Radar (spider) chart over a set of 0..1 values — the crew skill polygon.
## The geometry is pure and static (polygon_points / axis_points) so it is
## testable without rendering; _draw paints grid rings, spokes, the value
## polygon, and axis labels in UiKit colours.

const CHART_SIZE := Vector2(220, 220)
## Space reserved around the grid for axis labels.
const LABEL_MARGIN := 30.0
const LABEL_OFFSET := 8.0
const GRID_RINGS := [0.25, 0.5, 0.75, 1.0]
const GRID_WIDTH := 1.0
const OUTLINE_WIDTH := 2.0
const FILL_ALPHA := 0.25
const LABEL_FONT_SIZE := 10
## A polygon needs at least three axes to enclose an area.
const MIN_AXES := 3

var _values: Array = []
var _labels: Array = []


func _init() -> void:
	custom_minimum_size = CHART_SIZE


func set_values(values: Array) -> void:
	_values = values.duplicate()
	queue_redraw()


func set_axis_labels(labels: Array) -> void:
	_labels = labels.duplicate()
	queue_redraw()


## Unit direction of axis `index` out of `count`, first axis pointing
## straight up, subsequent axes clockwise.
static func axis_direction(index: int, count: int) -> Vector2:
	var angle := -PI / 2 + TAU * float(index) / float(count)
	return Vector2(cos(angle), sin(angle))


## Vertices of the value polygon: vertex i sits along axis i at
## clamp(value, 0, 1) * radius from the center.
static func polygon_points(values: Array, center: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in values.size():
		var reach := radius * clampf(float(values[i]), 0.0, 1.0)
		points.append(center + axis_direction(i, values.size()) * reach)
	return points


## The grid ring's vertices: every axis endpoint at full radius.
static func axis_points(count: int, center: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in count:
		points.append(center + axis_direction(i, count) * radius)
	return points


func _draw() -> void:
	var count := _values.size()
	if count < MIN_AXES:
		return
	var center := size / 2.0
	var radius := minf(center.x, center.y) - LABEL_MARGIN
	if radius <= 0.0:
		return

	for ring in GRID_RINGS:
		var ring_points := axis_points(count, center, radius * float(ring))
		ring_points.append(ring_points[0])
		draw_polyline(ring_points, UiKit.LINE, GRID_WIDTH)

	for spoke_end in axis_points(count, center, radius):
		draw_line(center, spoke_end, UiKit.LINE, GRID_WIDTH)

	var polygon := polygon_points(_values, center, radius)
	var fill := UiKit.ACCENT
	fill.a = FILL_ALPHA
	draw_colored_polygon(polygon, fill)
	var outline := polygon.duplicate()
	outline.append(polygon[0])
	draw_polyline(outline, UiKit.ACCENT, OUTLINE_WIDTH)

	_draw_axis_labels(count, center, radius)


func _draw_axis_labels(count: int, center: Vector2, radius: float) -> void:
	var font := get_theme_default_font()
	if font == null:
		return
	for i in mini(_labels.size(), count):
		var text := str(_labels[i])
		var text_size := font.get_string_size(
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE)
		var direction := axis_direction(i, count)
		var anchor := center + direction * (radius + LABEL_OFFSET)
		# Shift the text box outward so it never overlaps the grid: centered
		# above/below on vertical axes, left/right-aligned on side axes.
		var pos := Vector2(
			anchor.x - text_size.x * (0.5 - direction.x * 0.5),
			anchor.y + text_size.y * 0.25 + direction.y * text_size.y * 0.5)
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, UiKit.DIM)
