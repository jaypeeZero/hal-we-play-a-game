extends Node2D

## Visible driver for RaceSimulator: watch a field of ships fly the track.
## Replays a (track, entrants, seed) tuple using the same step_one() path as the
## headless sim, reuses VisualBridgeAutoload / ShipEntity for the 3D ships, and
## draws 2D overlays on top for legibility: a background grid, each racer's flown
## line as coloured dots, big always-visible gates, and a heading arrow per ship
## (screen-constant size so racers stay visible when zoomed out). A corner minimap
## shows everyone.

const FIXED_STEP := RaceSimulator.FIXED_STEP
## Playback speed multiplier — a real-time 3-lap race is minutes long.
const DEFAULT_RACE_SPEED := 4.0
var race_speed: float = DEFAULT_RACE_SPEED

## On-screen sizes (pixels) for overlay elements — divided by camera zoom so they
## stay a constant size on screen regardless of how far out you zoom.
const SHIP_ARROW_PX := 16.0
const GATE_LINE_PX := 5.0
const GATE_DOT_PX := 7.0
const GRID_LINE_PX := 1.0
const GATE_NUMBER_PX := 16.0
## Background grid spacing in world units.
const GRID_SPACING := 500.0
## Racing-line trail: dot size (screen px) and how often a point is sampled.
const TRAIL_DOT_PX := 2.0
const TRAIL_SAMPLE_STEPS := 9
## Minimap panel size + margin from the corner.
const MINIMAP_W := 280.0
const MINIMAP_H := 200.0
const MINIMAP_MARGIN := 14.0

const GRID_COL := Color(0.16, 0.18, 0.22, 0.6)
const GATE_COL := Color(1.0, 0.82, 0.25, 0.95)
const GATE_START_COL := Color(0.35, 1.0, 0.45, 0.95)
## Ship-arrow outline thickness (screen px) and the zoom range over which the
## arrows fade out — once you zoom in close you see the actual ships instead.
const ARROW_OUTLINE_PX := 2.5
const ARROW_FADE_START_ZOOM := 0.55
const ARROW_FADE_END_ZOOM := 1.0
## Distinct racer colors (cycled).
const PALETTE := [
	Color(0.95, 0.30, 0.30), Color(0.30, 0.70, 1.0), Color(0.40, 0.95, 0.45),
	Color(1.0, 0.80, 0.25), Color(0.80, 0.45, 1.0), Color(0.30, 0.95, 0.90),
]

# Set these before the scene enters the tree (watch launcher / betting replay).
## Track to race.
var track: Dictionary = {}
## Field of {ship, crew} entrants.
var entrants: Array = []
## Seed for deterministic race.
var race_seed: int = 0

var _ships: Array = []
var _states: Dictionary = {}
var _ship_entities: Dictionary = {}
var _session: Dictionary = {}
var _colors: Dictionary = {}
var _trails: Dictionary = {}      # ship_id -> PackedVector2Array of flown positions
var _trail_tick: int = 0
var _marker_points: Array = []
var _gate_segments: Array = []   # [[post_a, post_b], ...]
var _bounds: Dictionary = {}
var _time: float = 0.0
var _time_limit: float = 0.0
var _finished: bool = false
var _accumulated_delta: float = 0.0

# Preloaded (not referenced by class_name) so the scene loads even before the
# global class cache knows RaceMinimap — e.g. a fresh headless run.
const RaceMinimapScript := preload("res://scripts/space/race_minimap.gd")

@onready var _camera: CameraController = $Camera
@onready var _hud: Label = get_node_or_null("../UI/HUD")
var _minimap = null
var _font: Font = ThemeDB.fallback_font

signal race_finished(results: Dictionary)


func _ready() -> void:
	# The caller (watch launcher / betting replay) must inject the field first.
	if track.is_empty() or entrants.is_empty():
		push_error("ShipRaceGame requires `track` and `entrants` set before the scene loads.")
		return
	_cache_track_geometry()
	_setup_race()
	_build_minimap()
	_build_skip_button()
	_frame_camera()
	_update_hud()
	queue_redraw()


func _cache_track_geometry() -> void:
	"""Cache gate posts, midpoints and padded bounds used by the overlays."""
	_bounds = RaceTrack.track_bounds(track)
	_marker_points = []
	_gate_segments = []
	for i in range(RaceTrack.marker_count(track)):
		_marker_points.append(RaceTrack.marker_position(track, i))
		_gate_segments.append([RaceTrack.gate_post_a(track, i), RaceTrack.gate_post_b(track, i)])


func _setup_race() -> void:
	"""Initialize racers via the shared simulator setup, then build visual entities."""
	var field: Dictionary = RaceSimulator.setup_field(track, entrants, race_seed)
	_ships = field.ships
	_states = field.states
	_session = field.session

	for i in range(_ships.size()):
		var ship: Dictionary = _ships[i]
		_colors[ship.ship_id] = PALETTE[i % PALETTE.size()]
		_trails[ship.ship_id] = PackedVector2Array()
		var entity := ShipEntity.new()
		entity.initialize(ship.ship_id, ship.get("team", 0), ship.get("collision_radius", 15.0), ship.get("type", "fighter"))
		add_child(entity)
		_ship_entities[ship.ship_id] = entity

	_time_limit = RaceSimulator._time_limit(track)


func _build_minimap() -> void:
	"""Create the corner minimap on the UI layer and seed it with the track."""
	var ui: Node = get_node_or_null("../UI")
	if ui == null:
		return
	_minimap = RaceMinimapScript.new()
	_minimap.anchor_left = 1.0
	_minimap.anchor_top = 1.0
	_minimap.anchor_right = 1.0
	_minimap.anchor_bottom = 1.0
	_minimap.offset_left = -(MINIMAP_W + MINIMAP_MARGIN)
	_minimap.offset_top = -(MINIMAP_H + MINIMAP_MARGIN)
	_minimap.offset_right = -MINIMAP_MARGIN
	_minimap.offset_bottom = -MINIMAP_MARGIN
	ui.add_child(_minimap)
	_minimap.setup(_bounds, _gate_segments)


func _build_skip_button() -> void:
	"""Add a top-right Skip button that fast-forwards to the finish."""
	var ui: Node = get_node_or_null("../UI")
	if ui == null:
		return
	var btn := Button.new()
	btn.text = "Skip ▶▶"
	btn.anchor_left = 1.0
	btn.anchor_right = 1.0
	btn.offset_left = -120.0
	btn.offset_top = 12.0
	btn.offset_right = -12.0
	btn.offset_bottom = 44.0
	btn.pressed.connect(_skip_to_finish)
	ui.add_child(btn)


## Fast-forward the simulation to the finish (no rendering), then settle.
func _skip_to_finish() -> void:
	"""Run remaining ticks immediately until the race ends."""
	while not _finished:
		_time += FIXED_STEP
		_tick_all()


## Zoom/position the overview camera so the whole track is visible.
func _frame_camera() -> void:
	"""Frame the camera on the padded marker bounds of the track."""
	if _camera == null:
		return
	_camera.set_overview(_bounds.center, _bounds.size)


func _process(delta: float) -> void:
	if _finished:
		return

	_accumulated_delta += delta * race_speed
	while _accumulated_delta >= FIXED_STEP and not _finished:
		_accumulated_delta -= FIXED_STEP
		_time += FIXED_STEP
		_tick_all()

	_sync_entities()
	_update_hud()
	_update_minimap()
	queue_redraw()


func _tick_all() -> void:
	"""Step every racer one fixed tick, sampling each one's flown line."""
	for ship_ref in _ships:
		RaceSimulator.step_one(ship_ref, _states, _ships, track, _time, _session)

	_trail_tick += 1
	if _trail_tick % TRAIL_SAMPLE_STEPS == 0:
		for ship in _ships:
			_trails[ship.ship_id].append(ship.position)

	if _time >= _time_limit or RaceSimulator._all_finished(_states):
		_end_race()


func _sync_entities() -> void:
	"""Push ship position/rotation to visual entities."""
	for ship in _ships:
		var sid: String = ship.ship_id
		if _ship_entities.has(sid):
			var entity: ShipEntity = _ship_entities[sid]
			entity.sync_transform(ship)
			entity.emit_state(ship)


# ── 2D overlays (drawn in world space, on top of the 3D ships) ───────────────

func _draw() -> void:
	if _marker_points.is_empty():
		return
	var zoom: float = _camera.zoom.x if _camera != null else 1.0
	var inv: float = 1.0 / maxf(zoom, 0.001)  # px → world units at current zoom
	_draw_grid(inv)
	_draw_trails(inv)
	_draw_gates(inv)
	_draw_arrows(inv, zoom)


func _draw_grid(inv: float) -> void:
	"""Faint world grid so motion is readable against the empty background."""
	var lo: Vector2 = _bounds.center - _bounds.size * 0.5 - Vector2(GRID_SPACING, GRID_SPACING)
	var hi: Vector2 = _bounds.center + _bounds.size * 0.5 + Vector2(GRID_SPACING, GRID_SPACING)
	var w: float = GRID_LINE_PX * inv
	var x: float = floorf(lo.x / GRID_SPACING) * GRID_SPACING
	while x <= hi.x:
		draw_line(Vector2(x, lo.y), Vector2(x, hi.y), GRID_COL, w)
		x += GRID_SPACING
	var y: float = floorf(lo.y / GRID_SPACING) * GRID_SPACING
	while y <= hi.y:
		draw_line(Vector2(lo.x, y), Vector2(hi.x, y), GRID_COL, w)
		y += GRID_SPACING


func _draw_trails(inv: float) -> void:
	"""Each racer's actual flown line, as dots in its own colour — so you can see
	who took the tighter/cleaner line."""
	var r: float = TRAIL_DOT_PX * inv
	for sid in _trails:
		var col: Color = _colors.get(sid, Color.WHITE)
		col.a = 0.7
		for p in _trails[sid]:
			draw_circle(p, r, col)


func _draw_gates(inv: float) -> void:
	"""Draw each gate as two posts with the opening line between them, numbered."""
	for i in range(_gate_segments.size()):
		var a: Vector2 = _gate_segments[i][0]
		var b: Vector2 = _gate_segments[i][1]
		var col: Color = GATE_START_COL if i == 0 else GATE_COL
		# Opening line between the posts (dim) + a solid post at each end.
		draw_line(a, b, Color(col.r, col.g, col.b, 0.35), GATE_LINE_PX * inv)
		draw_circle(a, GATE_DOT_PX * inv, col)
		draw_circle(b, GATE_DOT_PX * inv, col)
		var fs: int = int(GATE_NUMBER_PX * inv)
		draw_string(_font, (a + b) * 0.5 + Vector2(GATE_DOT_PX, -GATE_DOT_PX) * inv,
			str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _draw_arrows(inv: float, zoom: float) -> void:
	"""Outline heading arrow per ship — points along travel, screen-constant size.
	Fades out as you zoom in so the actual ships take over up close."""
	var alpha: float = clampf(
		(ARROW_FADE_END_ZOOM - zoom) / (ARROW_FADE_END_ZOOM - ARROW_FADE_START_ZOOM), 0.0, 1.0)
	if alpha <= 0.01:
		return
	var s: float = SHIP_ARROW_PX * inv
	for ship in _ships:
		var pos: Vector2 = ship.position
		var dir: Vector2 = _travel_dir(ship)
		var tip: Vector2 = pos + dir * s
		var left: Vector2 = pos + dir.rotated(2.5) * s * 0.72
		var right: Vector2 = pos + dir.rotated(-2.5) * s * 0.72
		var col: Color = _colors.get(ship.ship_id, Color.WHITE)
		col.a = alpha
		draw_polyline(PackedVector2Array([tip, left, right, tip]), col, ARROW_OUTLINE_PX * inv)


## Direction a ship is travelling (velocity), falling back to its facing.
func _travel_dir(ship: Dictionary) -> Vector2:
	"""Unit travel direction: velocity if moving, else the ship's heading."""
	var vel: Vector2 = ship.get("velocity", Vector2.ZERO)
	if vel.length() > 5.0:
		return vel.normalized()
	var rot: float = ship.get("rotation", 0.0)
	return Vector2(sin(rot), -cos(rot))


# ── HUD + minimap ────────────────────────────────────────────────────────────

func _update_minimap() -> void:
	"""Feed current racer positions/colors/directions to the minimap."""
	if _minimap == null:
		return
	var racers: Array = []
	for ship in _ships:
		racers.append({
			"pos": ship.position,
			"color": _colors.get(ship.ship_id, Color.WHITE),
			"dir": _travel_dir(ship),
		})
	_minimap.update_racers(racers)


## Live running-order HUD: sort by laps done, then closeness to the next gate.
func _update_hud() -> void:
	"""Refresh the standings overlay from current race state."""
	if _hud == null:
		return
	var laps_total: int = track.get("laps", 3)
	var order: Array = _ships.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa: Dictionary = _states[a.ship_id]
		var sb: Dictionary = _states[b.ship_id]
		if sa.markers_passed != sb.markers_passed:
			return sa.markers_passed > sb.markers_passed
		var da: float = a.position.distance_to(RaceTrack.marker_position(track, sa.next_marker))
		var db: float = b.position.distance_to(RaceTrack.marker_position(track, sb.next_marker))
		return da < db)

	var lines: Array = ["RACE  —  %.1fs" % _time]
	var place: int = 1
	for ship in order:
		var st: Dictionary = _states[ship.ship_id]
		var status: String
		if st.finished:
			status = "finished %.1fs" % st.finish_time
		elif st.dnf:
			status = "DNF"
		else:
			status = "lap %d/%d" % [min(st.lap + 1, laps_total), laps_total]
		lines.append("%d. %-9s %s" % [place, _racer_name(ship.ship_id), status])
		place += 1
	_hud.text = "\n".join(lines)


## Display name for a racer (callsign captured in the telemetry session).
func _racer_name(ship_id: String) -> String:
	"""Return the racer's callsign, falling back to the ship id."""
	return _session.get("per_racer", {}).get(ship_id, {}).get("callsign", ship_id)


func _end_race() -> void:
	"""Mark remaining racers DNF, refresh overlays a final time, emit results."""
	_finished = true
	for sid in _states:
		if not _states[sid].finished:
			_states[sid].dnf = true
	_update_hud()
	_update_minimap()
	queue_redraw()
	var results: Dictionary = RaceTelemetry.finalize(_session, _states, _time)
	race_finished.emit(results)
