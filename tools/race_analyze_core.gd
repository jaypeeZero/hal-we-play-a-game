extends RefCounted

## Flight-line analyzer core (see race_analyze.gd). Runs one racer and reports:
##  - heading-rate (deg/s) timeline stats,
##  - per gate crossing: where in the gate it crossed (0..1), the speed there, and
##    the PEAK heading-rate in the 0.5s after vs before — i.e. the "snap",
##  - total time / gates made.
## A clean, smooth line = low post-gate snap and crossings well inside (~0.2..0.8).

const FIXED := 1.0 / 60.0
const MAX_TICKS := 18000
const WINDOW := 30          # 0.5s at 60Hz, for pre/post-gate heading-rate windows


func run(_tree: SceneTree, args: PackedStringArray) -> int:
	var track_id := "asteroid_sprint"
	var piloting := 0.7
	for a in args:
		if a.begins_with("--track="):
			track_id = a.substr(8)
		elif a.begins_with("--piloting="):
			piloting = float(a.substr(11))
		elif a.begins_with("--margin="):
			MovementSystem.nav_anticipation_margin = float(a.substr(9))

	var track := RaceTrack.load_track(track_id)
	if track.is_empty():
		push_error("bad track"); return 1
	var entrants := [{
		"ship": ShipData.create_ship_instance("fighter", 0, Vector2.ZERO),
		"crew": _crew(piloting),
	}]
	var field: Dictionary = RaceSimulator.setup_field(track, entrants, 1)
	var sid: String = field.ships[0].ship_id
	var ship: Dictionary = field.ships[0]
	var states: Dictionary = field.states

	var rate: PackedFloat32Array = PackedFloat32Array()   # heading-rate per tick (deg/s)
	var crossings: Array = []                              # {tick, gate, param, speed}
	var traj: Array = []                                   # [x,y,speed] every TRAJ_EVERY ticks
	var prev_rot: float = ship.rotation
	var prev_marker: int = states[sid].next_marker
	var t := 0.0
	for i in range(MAX_TICKS):
		t += FIXED
		var pre: Vector2 = ship.position
		RaceSimulator.step_one(ship, states, field.ships, track, t, field.session)
		if i % 6 == 0:
			traj.append([ship.position.x, ship.position.y, ship.velocity.length(), states[sid].next_marker])
		var st: Dictionary = states[sid]
		rate.append(abs(rad_to_deg(wrapf(ship.rotation - prev_rot, -PI, PI)) / FIXED))
		prev_rot = ship.rotation
		if st.next_marker != prev_marker:
			var g: int = prev_marker
			crossings.append({
				"tick": i, "gate": g, "speed": ship.velocity.length(),
				"param": _cross_param(track, g, pre, ship.position),
			})
			prev_marker = st.next_marker
		if st.finished or st.dnf:
			break

	_report(track_id, piloting, rate, crossings, states[sid], t)
	for row in args:
		if row == "--dump":
			print("TRAJ aiming=next_marker  (x, y, speed, aim)")
			for r in traj:
				print("%.0f %.0f %.0f %d" % [r[0], r[1], r[2], r[3]])
	return 0


func _report(track_id: String, piloting: float, rate: PackedFloat32Array,
		crossings: Array, st: Dictionary, t: float) -> void:
	print("=== %s | piloting %.2f ===" % [track_id, piloting])
	var status := ("finished %.1fs" % st.finish_time) if st.finished else \
		("DNF — %d gates" % st.markers_passed)
	print("%s | gates crossed: %d | peak heading-rate: %.0f°/s" % [status, crossings.size(), _max(rate)])
	print("gate |  where  | speed | turn-rate pre→post (°/s)  [snap]")
	for c in crossings:
		var tk: int = c.tick
		var pre_max: float = _window_max(rate, tk - WINDOW, tk)
		var post_max: float = _window_max(rate, tk, tk + WINDOW)
		var snap := "  <<< SNAP" if post_max > pre_max * 2.0 and post_max > 80.0 else ""
		print("  %2d  |  %.2f   | %4.0f  |  %5.0f → %5.0f%s" % [
			c.gate, c.param, c.speed, pre_max, post_max, snap])


func _crew(p: float) -> Dictionary:
	return {"crew_id": "c", "callsign": "A", "role": CrewData.Role.PILOT,
		"qualified_roles": [CrewData.Role.PILOT],
		"stats": {"stress": 0.0, "fatigue": 0.0, "reaction_time": 0.15,
			"skills": {"piloting": p, "awareness": p, "composure": 0.6,
				"aggression": 0.5, "aim": 0.5, "tactics": 0.5, "machinery": 0.5}}}


## Param 0..1 along gate g's posts where prev→cur crossed (clamped report value).
func _cross_param(track: Dictionary, g: int, prev: Vector2, cur: Vector2) -> float:
	var a: Vector2 = RaceTrack.gate_post_a(track, g)
	var b: Vector2 = RaceTrack.gate_post_b(track, g)
	var e: Vector2 = b - a
	var d: Vector2 = cur - prev
	var denom: float = e.x * d.y - e.y * d.x
	if absf(denom) < 0.0001:
		return 0.5
	var pp: Vector2 = prev - a
	return clampf((pp.x * d.y - pp.y * d.x) / denom, 0.0, 1.0)


func _max(arr: PackedFloat32Array) -> float:
	var m := 0.0
	for v in arr:
		m = maxf(m, v)
	return m


func _window_max(arr: PackedFloat32Array, lo: int, hi: int) -> float:
	var m := 0.0
	for i in range(maxi(lo, 0), mini(hi, arr.size())):
		m = maxf(m, arr[i])
	return m
