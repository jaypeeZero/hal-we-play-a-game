class_name SquadronData
extends RefCounted

## Pure static helper — defines mission constants and squadron factory.
## No mutable state; all data lives in RoguelikeRun.squadrons.

const Mission := {
	"PATROL": "patrol",
	"INTERCEPT": "intercept",
	"ELIMINATE": "eliminate",
	"ESCORT": "escort",
	"ASSAULT": "assault",
	"SCREEN": "screen",
	"FREE": "free",
}

## Parameter keys by mission type — for validation and UI generation.
const MISSION_PARAMS := {
	"patrol":    ["zone_center_x", "zone_center_y", "zone_radius"],
	"intercept": ["priority_class"],
	"eliminate": ["target_hull_id"],
	"escort":    ["escort_hull_id"],
	"assault":   ["zone_center_x", "zone_center_y"],
	"screen":    ["screen_for_hull_id"],
	"free":      [],
}


static func create(name: String) -> Dictionary:
	"""Return a new squadron dict with a unique id, no hull assignments, and FREE mission."""
	return {
		"squadron_id": "sq_%d" % Time.get_ticks_usec(),
		"name": name,
		"hull_ids": [],
		"mission": Mission.FREE,
		"mission_params": {},
	}
