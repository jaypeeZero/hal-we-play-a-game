class_name HeadshotSilhouette
extends Control

## Placeholder crew "portrait": a head-and-shoulders outline drawn in code,
## no art assets. Proportions are ratios of the control's size so the
## silhouette scales with whatever box the layout gives it.

const PORTRAIT_SIZE := Vector2(96, 112)
const HEAD_CENTER_Y_RATIO := 0.34
const HEAD_RADIUS_RATIO := 0.20      # of height
const SHOULDER_HALF_WIDTH_RATIO := 0.40  # of width
const SHOULDER_HEIGHT_RATIO := 0.34  # of height
const ARC_SEGMENTS := 48
const OUTLINE_WIDTH := 2.0


func _init() -> void:
	custom_minimum_size = PORTRAIT_SIZE


func _draw() -> void:
	var head_center := Vector2(size.x * 0.5, size.y * HEAD_CENTER_Y_RATIO)
	var head_radius := size.y * HEAD_RADIUS_RATIO
	draw_circle(head_center, head_radius, UiKit.PANEL_2)
	draw_arc(head_center, head_radius, 0.0, TAU, ARC_SEGMENTS, UiKit.DIM, OUTLINE_WIDTH)

	# Shoulders: the upper half of an ellipse anchored to the bottom edge.
	var shoulder_center := Vector2(size.x * 0.5, size.y)
	var rx := size.x * SHOULDER_HALF_WIDTH_RATIO
	var ry := size.y * SHOULDER_HEIGHT_RATIO
	var dome := PackedVector2Array()
	for i in range(ARC_SEGMENTS + 1):
		var angle := PI + PI * float(i) / float(ARC_SEGMENTS)
		dome.append(shoulder_center + Vector2(cos(angle) * rx, sin(angle) * ry))
	draw_colored_polygon(dome, UiKit.PANEL_2)
	draw_polyline(dome, UiKit.DIM, OUTLINE_WIDTH)
