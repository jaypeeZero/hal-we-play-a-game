extends Control

## Standalone launcher to preview the R&R "Go to the Races" betting screen
## without playing through a campaign.
##
## Run it:
##   godot res://tools/race_preview.tscn
## or, in the editor, open this scene and press F6 (Play Scene).
##
## Seeds demo credits and a tiny fleet (so your own pilots appear in the field
## alongside generated NPCs) only when the run state is empty — it never clobbers
## a real save.

const DEMO_CREDITS := 2000


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_seed_demo_state()
	var screen := RaceBettingScreen.open_overlay(self)
	screen.closed.connect(func() -> void: get_tree().quit())


func _seed_demo_state() -> void:
	"""Give the preview some credits and a couple of pilots if the run is empty."""
	if RoguelikeRun.money < DEMO_CREDITS:
		RoguelikeRun.money = DEMO_CREDITS
	if RoguelikeRun.fleet_hulls.is_empty():
		RoguelikeRun.fleet_hulls = [
			_demo_hull("fighter", "Ace", 0.85),
			_demo_hull("heavy_fighter", "Rook", 0.40),
		]


func _demo_hull(ship_type: String, callsign: String, piloting: float) -> Dictionary:
	"""Build a minimal fleet hull carrying one pilot, for the preview field."""
	return {
		"hull_id": "demo_%s" % callsign,
		"ship_type": ship_type,
		"crew": [{
			"crew_id": "demo_crew_%s" % callsign,
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
		}],
	}
