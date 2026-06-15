extends Node2D

## Thin visible driver for RaceSimulator. Replays a (track, entrants, seed) tuple
## using the same per-racer step_one() path as the headless simulator.
## Reuses VisualBridgeAutoload / ShipEntity for rendering (same as battle scene).

const FIXED_STEP := RaceSimulator.FIXED_STEP
## Pixel offset to center a marker's number label on the gate position.
const MARKER_LABEL_OFFSET := 10.0

# Exported so the betting flow can set these before the scene is ready.
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

signal race_finished(results: Dictionary)


func _ready() -> void:
	# The caller (betting replay / debug launcher) must inject the field first.
	if track.is_empty() or entrants.is_empty():
		push_error("ShipRaceGame requires `track` and `entrants` set before the scene loads.")
		return
	_setup_race()
	_spawn_marker_visuals()


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


func _process(delta: float) -> void:
	if _finished:
		return

	_accumulated_delta += delta
	while _accumulated_delta >= FIXED_STEP and not _finished:
		_accumulated_delta -= FIXED_STEP
		_time += FIXED_STEP
		_tick_all()

	_sync_entities()


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


func _end_race() -> void:
	"""Mark remaining racers DNF and emit results."""
	_finished = true
	for sid in _states:
		if not _states[sid].finished:
			_states[sid].dnf = true
	var results: Dictionary = RaceTelemetry.finalize(_session, _states, _time)
	race_finished.emit(results)
