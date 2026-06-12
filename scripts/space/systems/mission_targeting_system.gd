class_name MissionTargetingSystem
extends RefCounted

## Pure scoring helpers for mission-driven target selection.
## Called by squadron_leader_ai and captain_ai when scoring candidate ships.

const ELIMINATE_HIT_MULTIPLIER := 5.0
const ELIMINATE_MISS_MULTIPLIER := 0.3
const INTERCEPT_HIT_MULTIPLIER := 3.0
const INTERCEPT_MISS_MULTIPLIER := 1.0
const DEFAULT_MULTIPLIER := 1.0


## Return a score multiplier for a candidate ship given the active mission.
## Multiply existing score by this value before ranking.
static func score_multiplier(mission: String, params: Dictionary, candidate_ship: Dictionary) -> float:
	match mission:
		SquadronData.Mission.INTERCEPT:
			var priority_class: String = params.get("priority_class", "")
			if priority_class == "" or priority_class == candidate_ship.get("ship_type", ""):
				return INTERCEPT_HIT_MULTIPLIER
			return INTERCEPT_MISS_MULTIPLIER

		SquadronData.Mission.ELIMINATE:
			var target_id: String = params.get("target_hull_id", "")
			if target_id != "" and target_id == candidate_ship.get("hull_id", ""):
				return ELIMINATE_HIT_MULTIPLIER
			return ELIMINATE_MISS_MULTIPLIER

		SquadronData.Mission.ESCORT, SquadronData.Mission.SCREEN:
			# Positional missions — caller handles positioning; scoring unchanged.
			return DEFAULT_MULTIPLIER

		_:
			return DEFAULT_MULTIPLIER


## True for missions that require the squadron to move to a position rather
## than simply bias target priority.
static func has_positional_mission(mission: String) -> bool:
	return mission in [
		SquadronData.Mission.PATROL,
		SquadronData.Mission.ESCORT,
		SquadronData.Mission.SCREEN,
		SquadronData.Mission.ASSAULT,
	]
