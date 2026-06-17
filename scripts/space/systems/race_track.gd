class_name RaceTrack
extends RefCounted

## Pure static helpers for race track data: load, gate detection, lap progress.
## All functions are stateless — the track Dictionary is the only shared state.
##
## A gate is a pair of posts {a, b}; a racer passes it by flying BETWEEN the two
## posts (its path segment must cross the post-to-post segment). marker_position
## returns the gate midpoint (the point a racer aims for).

const TRACKS_PATH := "res://data/race_tracks/"
## DNF cutoff: elapsed time limit = estimated ideal lap time × laps × this.
const FINISH_TIME_LIMIT_MULT := 4.0
## Starting line: the field forms up abreast in a single straight row this far
## OUTSIDE the first gate (back along the approach), then charges it together.
const START_LINE_SETBACK := 1875.0
## Lateral gap between racers on the starting line (world units).
const START_LINE_SPACING := 170.0


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


## List available tracks as [{id, name}], sorted by name. Scans the track dir.
static func list_tracks() -> Array:
	"""Enumerate every track JSON under TRACKS_PATH for track-picker UIs."""
	var out: Array = []
	var dir := DirAccess.open(TRACKS_PATH)
	if dir == null:
		return out
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".json"):
			var id := fname.get_basename()
			out.append({"id": id, "name": load_track(id).get("name", id)})
		fname = dir.get_next()
	dir.list_dir_end()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.name < b.name)
	return out


## Number of gates on this track.
static func marker_count(track: Dictionary) -> int:
	return track.get("gates", []).size()


## A gate's two posts (the points a racer flies between).
static func gate_post_a(track: Dictionary, idx: int) -> Vector2:
	return _read_point(track.get("gates", []), idx, "a")


static func gate_post_b(track: Dictionary, idx: int) -> Vector2:
	return _read_point(track.get("gates", []), idx, "b")


static func _read_point(gates: Array, idx: int, key: String) -> Vector2:
	"""Read post `key` of gate `idx` as a Vector2 (zero if out of range)."""
	if idx < 0 or idx >= gates.size():
		return Vector2.ZERO
	var p = gates[idx].get(key, [0, 0])
	return Vector2(float(p[0]), float(p[1]))


## Aim point for a gate: the midpoint between its two posts.
static func marker_position(track: Dictionary, index: int) -> Vector2:
	return (gate_post_a(track, index) + gate_post_b(track, index)) * 0.5


## Total gate crossings required to finish: laps × gate count.
static func total_markers_to_finish(track: Dictionary) -> int:
	return track.get("laps", 1) * marker_count(track)


## Unit vector along the gate opening (post a → post b).
static func gate_tangent(track: Dictionary, idx: int) -> Vector2:
	var span: Vector2 = gate_post_b(track, idx) - gate_post_a(track, idx)
	return span.normalized() if span.length() > 0.0 else Vector2.UP


## Half the distance between a gate's posts (world units).
static func gate_half_width(track: Dictionary, idx: int) -> float:
	return gate_post_a(track, idx).distance_to(gate_post_b(track, idx)) * 0.5


## Padding (world units) added around the gate AABB when framing a camera.
const TRACK_VIEW_PADDING := 700.0


## Axis-aligned bounds covering every gate post, padded. Returns {center, size}
## for framing an overview camera on the whole track.
static func track_bounds(track: Dictionary) -> Dictionary:
	"""Compute a padded {center, size} covering every gate post."""
	var n: int = marker_count(track)
	if n == 0:
		return {"center": Vector2.ZERO, "size": Vector2(2000, 2000)}
	var lo: Vector2 = gate_post_a(track, 0)
	var hi: Vector2 = lo
	for i in range(n):
		for p in [gate_post_a(track, i), gate_post_b(track, i)]:
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
			hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	lo -= Vector2(TRACK_VIEW_PADDING, TRACK_VIEW_PADDING)
	hi += Vector2(TRACK_VIEW_PADDING, TRACK_VIEW_PADDING)
	return {"center": (lo + hi) * 0.5, "size": hi - lo}


## Did the racer fly BETWEEN gate idx's posts this tick? True when the movement
## segment prev_pos→cur_pos crosses the post-to-post segment. Direction-agnostic
## (a pass from either side counts); the gate sequence enforces lap order.
static func crossed_gate(track: Dictionary, idx: int,
		prev_pos: Vector2, cur_pos: Vector2) -> bool:
	if idx < 0 or idx >= marker_count(track):
		return false
	return _segments_cross(prev_pos, cur_pos,
		gate_post_a(track, idx), gate_post_b(track, idx))


## True when open segments p1→p2 and p3→p4 properly intersect.
static func _segments_cross(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2) -> bool:
	"""Standard orientation test for segment intersection."""
	var d1: float = _cross(p4 - p3, p1 - p3)
	var d2: float = _cross(p4 - p3, p2 - p3)
	var d3: float = _cross(p2 - p1, p3 - p1)
	var d4: float = _cross(p2 - p1, p4 - p1)
	return ((d1 > 0.0) != (d2 > 0.0)) and ((d3 > 0.0) != (d4 > 0.0))


static func _cross(u: Vector2, v: Vector2) -> float:
	return u.x * v.y - u.y * v.x


## Starting positions for n_racers: a single straight line, abreast, set back
## OUTSIDE the first gate and all facing it — so the field charges gate 1 together.
## Returns Array of {position: Vector2, heading: float}.
static func starting_grid(track: Dictionary, n_racers: int) -> Array:
	var gate0: Vector2 = marker_position(track, 0)
	var start: Dictionary = track.get("start", {})
	var sp_arr: Array = start.get("position", [gate0.x, gate0.y])
	var start_pos: Vector2 = Vector2(float(sp_arr[0]), float(sp_arr[1]))

	# Approach axis: from the designer's start point toward the first gate.
	var approach: Vector2 = gate0 - start_pos
	approach = approach.normalized() if approach.length() > 1.0 else Vector2(0.0, -1.0)
	var heading: float = atan2(approach.x, -approach.y)   # face the first gate
	var right: Vector2 = Vector2(approach.y, -approach.x)  # lateral (abreast) axis

	# One straight row, centred on a point set back outside the first gate.
	var line_centre: Vector2 = gate0 - approach * START_LINE_SETBACK
	var result: Array = []
	for i in range(n_racers):
		var offset: float = (float(i) - float(n_racers - 1) * 0.5) * START_LINE_SPACING
		result.append({ "position": line_centre + right * offset, "heading": heading })
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
