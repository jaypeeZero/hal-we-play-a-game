extends Node2D

## Visible driver for RaceSimulator: watch a field of ships fly the track.
## Replays a (track, entrants, seed) tuple using the same step_one() path as the
## headless sim, and reuses VisualBridgeAutoload / ShipEntity for rendering
## (same renderer as the battle scene). Frames an overview camera on the whole
## track and shows a live standings HUD.

const FIXED_STEP := RaceSimulator.FIXED_STEP
## Pixel offset to center a marker's number label on the gate position.
const MARKER_LABEL_OFFSET := 10.0

# Set these before the scene enters the tree (betting replay / watch launcher).
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
var _time: float = 0.0
var _time_limit: float = 0.0
var _finished: bool = false
var _accumulated_delta: float = 0.0

@onready var _camera: CameraController = $Camera
@onready var _hud: Label = get_node_or_null("../UI/HUD")

signal race_finished(results: Dictionary)


func _ready() -> void:
	# The caller (watch launcher / betting replay) must inject the field first.
	if track.is_empty() or entrants.is_empty():
		push_error("ShipRaceGame requires `track` and `entrants` set before the scene loads.")
		return
	_setup_race()
	_spawn_marker_visuals()
	_frame_camera()
	_update_hud()


func _setup_race() -> void:
	"""Initialize racers via the shared simulator setup, then build visual entities."""
	var field: Dictionary = RaceSimulator.setup_field(track, entrants, race_seed)
	_ships = field.ships
	_states = field.states
	_session = field.session

	for ship in _ships:
		var entity := ShipEntity.new()
		entity.initialize(ship.ship_id, ship.get("team", 0), ship.get("collision_radius", 15.0), ship.get("type", "fighter"))
		add_child(entity)
		_ship_entities[ship.ship_id] = entity

	_time_limit = RaceSimulator._time_limit(track)


## Zoom/position the overview camera so the whole track is visible.
func _frame_camera() -> void:
	"""Frame the camera on the padded marker bounds of the track."""
	if _camera == null:
		return
	var bounds: Dictionary = RaceTrack.track_bounds(track)
	_camera.set_overview(bounds.center, bounds.size)


func _process(delta: float) -> void:
	if _finished:
		return

	_accumulated_delta += delta
	while _accumulated_delta >= FIXED_STEP and not _finished:
		_accumulated_delta -= FIXED_STEP
		_time += FIXED_STEP
		_tick_all()

	_sync_entities()
	_update_hud()


func _tick_all() -> void:
	"""Step every racer one fixed tick."""
	for ship_ref in _ships:
		RaceSimulator.step_one(ship_ref, _states, _ships, track, _time, _session)

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


func _spawn_marker_visuals() -> void:
	"""Place a numbered label at each gate marker so the track is legible."""
	for i in range(RaceTrack.marker_count(track)):
		var lbl := Label.new()
		lbl.text = str(i + 1)
		lbl.position = RaceTrack.marker_position(track, i) - Vector2(MARKER_LABEL_OFFSET, MARKER_LABEL_OFFSET)
		add_child(lbl)


## Live running-order HUD: sort racers by laps done, then by closeness to the
## marker they're chasing (ahead = closer to the next gate).
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
	"""Mark remaining racers DNF, refresh the HUD a final time, and emit results."""
	_finished = true
	for sid in _states:
		if not _states[sid].finished:
			_states[sid].dnf = true
	_update_hud()
	var results: Dictionary = RaceTelemetry.finalize(_session, _states, _time)
	race_finished.emit(results)
