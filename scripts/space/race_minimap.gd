class_name RaceMinimap
extends Control

## Fixed-corner minimap for the race scene: draws the track outline, gate
## markers, and a bright dot per racer so you always know who is where,
## independent of the world camera's zoom/pan.

const PANEL_BG := Color(0.05, 0.06, 0.09, 0.85)
const BORDER := Color(0.45, 0.55, 0.65, 0.9)
const TRACK_COL := Color(0.55, 0.6, 0.7, 0.7)
const MARKER_COL := Color(1.0, 0.82, 0.2, 1.0)
const START_COL := Color(0.35, 1.0, 0.45, 1.0)
## Fraction of the panel used (leaves an inset border).
const FIT := 0.88
## Radius of a racer dot, in pixels.
const SHIP_DOT := 5.5
const MARKER_DOT := 3.5

var _bounds: Dictionary = {"center": Vector2.ZERO, "size": Vector2(1000, 1000)}
var _markers: Array = []   # Array[Vector2]
var _racers: Array = []     # Array[{pos: Vector2, color: Color, dir: Vector2}]


## One-time setup: the world bounds to frame and the gate marker positions.
func setup(bounds: Dictionary, markers: Array) -> void:
	"""Store the track framing and markers, then redraw."""
	_bounds = bounds
	_markers = markers
	queue_redraw()


## Per-frame update: current racer positions, colors and travel directions.
func update_racers(racers: Array) -> void:
	"""Store the latest racer dots and request a redraw."""
	_racers = racers
	queue_redraw()


## Map a world position into panel-local pixels (aspect preserved, centered).
func _world_to_map(p: Vector2) -> Vector2:
	var wsize: Vector2 = _bounds.size
	var scale: float = minf(size.x / maxf(wsize.x, 1.0), size.y / maxf(wsize.y, 1.0)) * FIT
	var used: Vector2 = wsize * scale
	var pad: Vector2 = (size - used) * 0.5
	var origin: Vector2 = _bounds.center - wsize * 0.5
	return pad + (p - origin) * scale


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), PANEL_BG, true)
	draw_rect(Rect2(Vector2.ZERO, size), BORDER, false, 2.0)

	# Track path: connect the gate markers in order, closing the loop.
	if _markers.size() >= 2:
		var pts: PackedVector2Array = PackedVector2Array()
		for m in _markers:
			pts.append(_world_to_map(m))
		pts.append(_world_to_map(_markers[0]))
		draw_polyline(pts, TRACK_COL, 2.0)

	# Gate markers (start/finish highlighted).
	for i in range(_markers.size()):
		var mp: Vector2 = _world_to_map(_markers[i])
		draw_circle(mp, MARKER_DOT, START_COL if i == 0 else MARKER_COL)

	# Racers: bright filled dot + dark outline + a short heading tick.
	for r in _racers:
		var p: Vector2 = _world_to_map(r.pos)
		draw_circle(p, SHIP_DOT, r.color)
		draw_arc(p, SHIP_DOT, 0.0, TAU, 20, Color(0, 0, 0, 0.9), 1.5)
		var d: Vector2 = r.dir
		if d.length() > 0.01:
			draw_line(p, p + d.normalized() * (SHIP_DOT + 5.0), r.color, 2.0)
