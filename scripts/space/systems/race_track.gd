class_name RaceTrack
extends RefCounted

## Pure static helpers for race track data: load, gate detection, lap progress.
## All functions are stateless — the track Dictionary is the only shared state.

const TRACKS_PATH := "res://data/race_tracks/"
const DEFAULT_CHECKPOINT_RADIUS := 250.0
const DEFAULT_GATE_WIDTH := 500.0
## DNF cutoff: elapsed time limit = estimated ideal lap time × laps × this.
const FINISH_TIME_LIMIT_MULT := 4.0
## Grid rows per column before wrapping to next column.
const GRID_ROWS_PER_COLUMN := 4
## Stagger offset between even/odd grid rows (fraction of lateral spacing).
const GRID_STAGGER_FRACTION := 0.5


## Load a track dict from data/race_tracks/<track_id>.json.
static func load_track(track_id: String) -> Dictionary:
	var path := TRACKS_PATH + track_id + ".json"
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("RaceTrack: cannot read track file %s" % path)
		return {}
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("RaceTrack: invalid JSON in %s" % path)
		return {}
	return parsed


## Number of gate markers on this track.
static func marker_count(track: Dictionary) -> int:
	return track.get("markers", []).size()


## World position of marker at index.
static func marker_position(track: Dictionary, index: int) -> Vector2:
	var markers: Array = track.get("markers", [])
	if index < 0 or index >= markers.size():
		return Vector2.ZERO
	var pos = markers[index].get("position", [0, 0])
	return Vector2(float(pos[0]), float(pos[1]))


## Total gate crossings required to finish: laps × marker count.
static func total_markers_to_finish(track: Dictionary) -> int:
	return track.get("laps", 1) * marker_count(track)


## Padding (world units) added around the marker AABB when framing a camera.
const TRACK_VIEW_PADDING := 700.0


## Axis-aligned bounds of all markers, padded. Returns {center, size} for
## framing an overview camera on the whole track.
static func track_bounds(track: Dictionary) -> Dictionary:
	"""Compute a padded {center, size} covering every gate marker."""
	var n: int = marker_count(track)
	if n == 0:
		return {"center": Vector2.ZERO, "size": Vector2(2000, 2000)}
	var lo: Vector2 = marker_position(track, 0)
	var hi: Vector2 = lo
	for i in range(1, n):
		var p: Vector2 = marker_position(track, i)
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	lo -= Vector2(TRACK_VIEW_PADDING, TRACK_VIEW_PADDING)
	hi += Vector2(TRACK_VIEW_PADDING, TRACK_VIEW_PADDING)
	return {"center": (lo + hi) * 0.5, "size": hi - lo}


## Gate-crossing check: did segment prev_pos→cur_pos cross marker[idx]'s gate?
## Gate is defined by its center, normal, and width. A crossing counts when:
##   1. The segment crosses the gate line (sign change along the normal axis).
##   2. The crossing point is within gate_width / 2 of the gate center.
## Direction-agnostic: a pass from either side counts (racers approach gates
## from varying headings; the marker sequence already enforces lap order).
static func crossed_gate(track: Dictionary, idx: int,
		prev_pos: Vector2, cur_pos: Vector2) -> bool:
	var markers: Array = track.get("markers", [])
	if idx < 0 or idx >= markers.size():
		return false
	var m: Dictionary = markers[idx]
	var center := marker_position(track, idx)
	var norm_arr = m.get("gate_normal", [1, 0])
	var normal := Vector2(float(norm_arr[0]), float(norm_arr[1])).normalized()
	var width: float = float(m.get("gate_width", DEFAULT_GATE_WIDTH))

	# Signed distances from the gate plane (normal dot (pos - center)).
	var d_prev: float = normal.dot(prev_pos - center)
	var d_cur: float = normal.dot(cur_pos - center)

	# Must cross the plane (sign change or arrive exactly on it).
	if d_prev * d_cur > 0.0:
		return false

	# Interpolate crossing point.
	var t: float = 0.0
	var denom: float = d_prev - d_cur
	if abs(denom) > 0.0001:
		t = d_prev / denom
	var cross_point: Vector2 = prev_pos.lerp(cur_pos, t)

	# Must be within gate half-width along the perpendicular axis.
	var tangent: Vector2 = Vector2(-normal.y, normal.x)
	var lateral: float = abs(tangent.dot(cross_point - center))
	return lateral <= width * 0.5


## Fallback: within checkpoint_radius of the marker center.
static func within_checkpoint(track: Dictionary, idx: int, pos: Vector2) -> bool:
	var radius: float = float(track.get("checkpoint_radius", DEFAULT_CHECKPOINT_RADIUS))
	return pos.distance_to(marker_position(track, idx)) <= radius


## Compute starting grid positions for n_racers.
## Returns Array of {position: Vector2, heading: float}.
static func starting_grid(track: Dictionary, n_racers: int) -> Array:
	var start: Dictionary = track.get("start", {})
	var base_pos_arr: Array = start.get("position", [0, 0])
	var base_pos: Vector2 = Vector2(float(base_pos_arr[0]), float(base_pos_arr[1]))
	var heading: float = float(start.get("heading", 0.0))
	var spacing_arr = start.get("grid_spacing", [120, 90])
	var lon_step: float = float(spacing_arr[0])  # along heading axis
	var lat_step: float = float(spacing_arr[1])  # perpendicular

	# Forward and right vectors derived from heading.
	var fwd := Vector2(sin(heading), -cos(heading))
	var right := Vector2(fwd.y, -fwd.x)

	var result: Array = []
	for i in range(n_racers):
		var row: int = i % GRID_ROWS_PER_COLUMN
		var col: int = i / GRID_ROWS_PER_COLUMN
		var stagger: float = lat_step * GRID_STAGGER_FRACTION if row % 2 == 1 else 0.0
		var pos: Vector2 = base_pos \
			- fwd * lon_step * float(col) \
			+ right * (lat_step * float(row - (GRID_ROWS_PER_COLUMN - 1) * 0.5) + stagger)
		result.append({ "position": pos, "heading": heading })
	return result


## Initial per-racer progress dict for the simulator.
static func make_race_state(ship_id: String, crew_id: String) -> Dictionary:
	"""Create a fresh race state for one racer."""
	return {
		"ship_id": ship_id,
		"crew_id": crew_id,
		"lap": 0,
		"next_marker": 0,
		"markers_passed": 0,
		"finished": false,
		"finish_time": -1.0,
		"dnf": false,
		"last_marker_time": 0.0,
		"lap_start_time": 0.0,
		"lap_times": [],
		"best_lap": -1.0,
	}


## Advance one racer's progress given their position movement this tick.
## Returns a new state dict (does not mutate the input).
static func advance_progress(state: Dictionary, track: Dictionary,
		prev_pos: Vector2, cur_pos: Vector2, time: float) -> Dictionary:
	"""Update lap/marker counters after a physics step. Pure function."""
	if state.finished:
		return state
	var s: Dictionary = state.duplicate(true)
	var idx: int = s.next_marker
	if crossed_gate(track, idx, prev_pos, cur_pos):
		s.markers_passed += 1
		s.last_marker_time = time
		s.next_marker = (idx + 1) % marker_count(track)
		if s.next_marker == 0:
			# Completed a full lap.
			var lap_t: float = time - s.lap_start_time
			s.lap_times.append(lap_t)
			s.best_lap = lap_t if s.best_lap < 0.0 else min(s.best_lap, lap_t)
			s.lap_start_time = time
			s.lap += 1
		if s.markers_passed >= total_markers_to_finish(track):
			s.finished = true
			s.finish_time = time
	return s
