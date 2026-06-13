class_name EngineerAction
extends RefCounted

## Base class for GOAP engineer actions.
## Subclasses override action_id(), cost(), precondition(), and execute().

# Repair subtype identifiers (re-exported by EngineerAI for test compatibility)
const REPAIR_SUBTYPE_PREFIX = "fix_"
const ARMOR_REPAIR_SUBTYPE  = "fix_armor"

# Cost bands — internals always < armor since ratio ∈ [0,1]
# This encodes today's "internals before armor" triage in cost ordering.
const INTERNAL_COST_BASE = 1.0
const ARMOR_COST_BASE    = 3.0


# Virtual interface

func action_id() -> String:
	return ""

func cost(_ws: EngineerWorldState) -> float:
	return 1.0

func precondition(_ws: EngineerWorldState) -> bool:
	return false

func execute(_ws: EngineerWorldState) -> Dictionary:
	return {}


# Shared static helper: build a repair decision dict

static func make_repair_decision(
	ws: EngineerWorldState,
	subtype: String,
	target_key: String,
	target_id: String
) -> Dictionary:
	var d := {
		"type": "repair",
		"subtype": subtype,
		"crew_id": ws.crew_data.get("crew_id", ""),
		"entity_id": ws.crew_data.get("assigned_to", ""),
		"skill_factor": ws.effective_skill,
		"timestamp": ws.game_time,
	}
	d[target_key] = target_id
	return d
