class_name GunnerAction
extends RefCounted

## Base class for GOAP gunner actions.
## Subclasses override action_id(), cost(), precondition(), and execute().
## Static helpers here are shared by all gunner action subclasses.

# Re-decision delays per fire mode
const SUPPRESSIVE_REDECIDE_DELAY    = 0.05
const PRECISION_REDECIDE_MIN        = 0.8
const PRECISION_REDECIDE_MAX        = 1.2
const STANDARD_REDECIDE_AFTER_ORDER = 0.1
const HOLD_REDECIDE_MIN             = 0.5
const HOLD_REDECIDE_MAX             = 1.0
const NO_TARGETS_REDECIDE_MIN       = 1.0
const NO_TARGETS_REDECIDE_MAX       = 2.0
const MULTI_TARGET_REDECIDE_DELAY   = 0.1
const MULTI_TARGET_THRESHOLD        = 2

# Gunner-knowledge threshold
const SUPPRESSIVE_TARGET_COUNT_THRESHOLD = 3

# Target scoring weights
const DAMAGED_TARGET_BONUS    = 50.0
const HIGH_VALUE_TARGET_BONUS = 30.0
const DISTANCE_SCORE_MAX      = 100.0
const DISTANCE_SCORE_DIVISOR  = 10.0
const DEFAULT_TARGET_DISTANCE = 1000.0


# Virtual interface

func action_id() -> String:
	return ""

func cost(_ws: GunnerWorldState) -> float:
	return 1.0

func precondition(_ws: GunnerWorldState) -> bool:
	return false

func execute(_ws: GunnerWorldState) -> Dictionary:
	return {}


# Shared static helper: build a fire decision dict

static func make_fire_decision(
	ws: GunnerWorldState, target_id: String, mode: String
) -> Dictionary:
	return {
		"type": "fire",
		"subtype": mode,
		"crew_id": ws.crew_data.get("crew_id", ""),
		"entity_id": ws.crew_data.get("assigned_to", ""),
		"target_id": target_id,
		"skill_factor": ws.effective_skill,
		"delay": ws.crew_data.get("stats", {}).get("reaction_time", 0.1),
		"timestamp": ws.game_time,
	}
