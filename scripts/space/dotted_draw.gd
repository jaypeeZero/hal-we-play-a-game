class_name DottedDraw
extends RefCounted

## Shared dotted-line / dotted-circle primitives. Used by debug_overlay and
## the pre-battle screen so the visual language is identical and there is
## exactly one implementation to maintain.

const DASH_LENGTH: float = 12.0
const DASH_GAP: float = 8.0
const LINE_WIDTH: float = 1.5
const CIRCLE_SEGMENTS: int = 64


static func draw_dotted_line(canvas: CanvasItem, from: Vector2, to: Vector2, color: Color, line_width: float = LINE_WIDTH) -> void:
	var total: float = from.distance_to(to)
	if total <= 0.0:
		return
	var dir: Vector2 = (to - from) / total
	var stride: float = DASH_LENGTH + DASH_GAP
	var traveled: float = 0.0
	while traveled < total:
		var seg_end: float = min(traveled + DASH_LENGTH, total)
		canvas.draw_line(from + dir * traveled, from + dir * seg_end, color, line_width)
		traveled += stride


static func draw_dotted_circle(canvas: CanvasItem, center: Vector2, radius: float, color: Color, line_width: float = LINE_WIDTH) -> void:
	var step: float = TAU / CIRCLE_SEGMENTS
	var draw_segment: bool = true
	var prev: Vector2 = center + Vector2(radius, 0)
	for i in range(1, CIRCLE_SEGMENTS + 1):
		var theta: float = i * step
		var p: Vector2 = center + Vector2(cos(theta), sin(theta)) * radius
		if draw_segment:
			canvas.draw_line(prev, p, color, line_width)
		draw_segment = not draw_segment
		prev = p
