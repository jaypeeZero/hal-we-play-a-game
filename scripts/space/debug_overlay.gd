class_name DebugOverlay
extends Node2D

## Always-on debug overlay: draws each ship's current focus.
## - Dotted line to enemy target (no circle).
## - Dotted line + dotted circle to patrol/move-to area.
## Pure data consumer: reads parent SpaceBattleGame state, never mutates.

const DASH_LENGTH: float = 12.0
const DASH_GAP: float = 8.0
const LINE_WIDTH: float = 1.5
const CIRCLE_SEGMENTS: int = 64
const TEAM_COLORS: Array = [
	Color(0.4, 0.7, 1.0, 0.6),  # team 0 — blue
	Color(1.0, 0.4, 0.4, 0.6),  # team 1 — red
]

var _game: Node = null  # SpaceBattleGame; set by parent on add_child


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _game == null:
		return
	for ship in _game._ships:
		if ship.get("status", "") == "destroyed":
			continue
		var team: int = int(ship.get("team", 0))
		var color: Color = TEAM_COLORS[team] if team >= 0 and team < TEAM_COLORS.size() else TEAM_COLORS[0]
		_draw_enemy_focus(ship, color)
		_draw_area_focus(ship, color)


func _draw_enemy_focus(ship: Dictionary, color: Color) -> void:
	var orders: Dictionary = ship.get("orders", {})
	var target_id: String = orders.get("target_id", "")
	if target_id == "":
		return
	var target: Dictionary = _game._find_ship_by_id(target_id)
	if target.is_empty() or target.get("status", "") == "destroyed":
		return
	_draw_dotted_line(ship.position, target.position, color)


func _draw_area_focus(ship: Dictionary, color: Color) -> void:
	var area = ship.get("assigned_area")
	if not (area is Dictionary):
		return
	var center: Vector2 = area.get("center", Vector2.ZERO)
	var radius: float = float(area.get("radius", 0.0))
	if radius <= 0.0:
		return
	# Line ends on the circle's rim (not the center) so the line and circle
	# read as one connected shape. If the ship is inside the circle, just
	# draw the line all the way to the center.
	var to_center: Vector2 = center - ship.position
	var dist: float = to_center.length()
	var line_end: Vector2 = center
	if dist > radius:
		line_end = ship.position + to_center / dist * (dist - radius)
	_draw_dotted_line(ship.position, line_end, color)
	_draw_dotted_circle(center, radius, color)


func _draw_dotted_line(from: Vector2, to: Vector2, color: Color) -> void:
	var total: float = from.distance_to(to)
	if total <= 0.0:
		return
	var dir: Vector2 = (to - from) / total
	var stride: float = DASH_LENGTH + DASH_GAP
	var traveled: float = 0.0
	while traveled < total:
		var seg_end: float = min(traveled + DASH_LENGTH, total)
		draw_line(from + dir * traveled, from + dir * seg_end, color, LINE_WIDTH)
		traveled += stride


func _draw_dotted_circle(center: Vector2, radius: float, color: Color) -> void:
	var step: float = TAU / CIRCLE_SEGMENTS
	var draw_segment: bool = true
	var prev: Vector2 = center + Vector2(radius, 0)
	for i in range(1, CIRCLE_SEGMENTS + 1):
		var theta: float = i * step
		var p: Vector2 = center + Vector2(cos(theta), sin(theta)) * radius
		if draw_segment:
			draw_line(prev, p, color, LINE_WIDTH)
		draw_segment = not draw_segment
		prev = p
