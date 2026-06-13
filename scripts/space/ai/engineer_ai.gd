class_name EngineerAI
extends RefCounted

## Engineer crew decisions — triage and repair the assigned ship.
## GOAP refactor: world state absorbs pick_repair_target's scan loops;
## cost ordering encodes "internals before armor" triage.

# Re-exported from EngineerAction for test compatibility
# (test_engineer_ai.gd and test_torpedo_system.gd reference EngineerAI.ARMOR_REPAIR_SUBTYPE)
const REPAIR_SUBTYPE_PREFIX = EngineerAction.REPAIR_SUBTYPE_PREFIX
const ARMOR_REPAIR_SUBTYPE  = EngineerAction.ARMOR_REPAIR_SUBTYPE


static func make_decision(crew_data: Dictionary, game_time: float, ships: Array) -> Dictionary:
	var updated := crew_data.duplicate(true)
	var ws := EngineerWorldState.build(updated, game_time, ships)
	var decision := EngineerBrain.decide(ws, game_time)

	if not decision.is_empty():
		updated.orders.current   = decision
		updated.current_action   = decision.get("subtype", "idle")
		updated.next_decision_time = game_time + randf_range(
			WingConstants.ENGINEER_REPAIR_CADENCE_MIN, WingConstants.ENGINEER_REPAIR_CADENCE_MAX
		)
		return {"crew_data": updated, "decision": decision}

	# Nothing to repair — idle
	updated.current_action     = "idle"
	updated.next_decision_time = game_time + randf_range(
		WingConstants.ENGINEER_IDLE_CADENCE_MIN, WingConstants.ENGINEER_IDLE_CADENCE_MAX
	)
	return {"crew_data": updated}
