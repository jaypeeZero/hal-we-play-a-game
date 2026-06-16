extends Control

## Standalone launcher to WATCH a ship race without playing through a campaign.
##
## Run it:
##   godot res://tools/race_preview.tscn
## or, in the editor, open this scene and press F6 (Play Scene).
##
## Pick a track from the dropdown to test pilots/ships on different layouts.
## Touches no run/save state — purely a preview.

const RACE_SEED := 1

var _tracks: Array = []          # [{id, name}]
var _track_picker: OptionButton
var _race_scene: Node = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_tracks = RaceTrack.list_tracks()
	_build_controls()
	_load_selected()


func _build_controls() -> void:
	"""Top-center track dropdown + restart, on a layer above the race UI."""
	var layer := CanvasLayer.new()
	layer.layer = 3
	add_child(layer)

	var bar := HBoxContainer.new()
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.offset_left = -190.0
	bar.offset_top = 10.0
	bar.offset_right = 190.0
	bar.offset_bottom = 44.0
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	layer.add_child(bar)

	bar.add_child(_make_label("Track:"))
	_track_picker = OptionButton.new()
	for t in _tracks:
		_track_picker.add_item(t.name)
	_track_picker.item_selected.connect(func(_i: int) -> void: _load_selected())
	bar.add_child(_track_picker)

	var restart := Button.new()
	restart.text = "Restart"
	restart.pressed.connect(_load_selected)
	bar.add_child(restart)


func _load_selected() -> void:
	"""(Re)load the race scene for the currently selected track."""
	if _race_scene != null:
		_race_scene.queue_free()
		_race_scene = null
	var idx: int = maxi(_track_picker.selected, 0)
	var track_id: String = _tracks[idx].id if idx < _tracks.size() else "asteroid_sprint"
	var scene: Node = load("res://scenes/ship_race.tscn").instantiate()
	var game: Node = scene.get_node("ShipRaceGame")
	game.track = RaceTrack.load_track(track_id)
	game.entrants = _demo_entrants()
	game.race_seed = RACE_SEED
	add_child(scene)
	_race_scene = scene


func _make_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return lbl


func _demo_entrants() -> Array:
	"""A mixed field with a clear skill/ship spread, so the race is fun to watch."""
	return [
		_entrant("fighter", "Ace", 0.95),
		_entrant("fighter", "Rookie", 0.20),
		_entrant("heavy_fighter", "Tank", 0.60),
		_entrant("corvette", "Brick", 0.50),
		_entrant("fighter", "Vega", 0.75),
		_entrant("heavy_fighter", "Hauler", 0.40),
	]


func _entrant(ship_type: String, callsign: String, piloting: float) -> Dictionary:
	"""Build one {ship, crew} entrant for the preview field."""
	return {
		"ship": ShipData.create_ship_instance(ship_type, 0, Vector2.ZERO),
		"crew": {
			"crew_id": "demo_%s" % callsign,
			"callsign": callsign,
			"role": CrewData.Role.PILOT,
			"qualified_roles": [CrewData.Role.PILOT],
			"stats": {
				"stress": 0.0, "fatigue": 0.0, "reaction_time": 0.15,
				"skills": {
					"piloting": piloting, "awareness": 0.6, "composure": 0.6,
					"aggression": 0.5, "aim": 0.5, "tactics": 0.5, "machinery": 0.5,
				},
			},
		},
	}
