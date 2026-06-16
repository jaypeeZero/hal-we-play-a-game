extends Control

## Standalone launcher to WATCH a ship race without playing through a campaign.
##
## Run it:
##   godot res://tools/race_preview.tscn
## or, in the editor, open this scene and press F6 (Play Scene).
##
## Loads the visible race scene with a demo field of varied ships + pilots so you
## can watch how they fly. Touches no run/save state — purely a preview.

const TRACK_ID := "asteroid_sprint"
const RACE_SEED := 1


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var scene: Node = load("res://scenes/ship_race.tscn").instantiate()
	var game: Node = scene.get_node("ShipRaceGame")
	# Inject the field BEFORE the scene enters the tree so _ready() sees it.
	game.track = RaceTrack.load_track(TRACK_ID)
	game.entrants = _demo_entrants()
	game.race_seed = RACE_SEED
	add_child(scene)


func _demo_entrants() -> Array:
	"""A mixed field with a clear skill/ship spread, so the race is fun to watch."""
	return [
		_entrant("fighter", "Ace", 0.95),
		_entrant("fighter", "Rookie", 0.20),
		_entrant("heavy_fighter", "Tank", 0.60),
		_entrant("corvette", "Brick", 0.50),
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
