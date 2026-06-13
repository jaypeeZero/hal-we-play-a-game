class_name CaptainAction
extends RefCounted

## Base class for GOAP captain actions.
## execute() returns {"decision": ..., "issued_orders": [...]}

# Critical-damage heuristic
const CRITICAL_STRESS_THRESHOLD = 0.7
const CRITICAL_THREAT_COUNT     = 3

# Captain knowledge thresholds
const WITHDRAW_THREAT_PRIORITY        = 200.0
const DEFENSIVE_THREAT_COUNT          = 2
const STANDARD_DEFENSIVE_THREAT_COUNT = 3
const FLANK_MAX_THREATS               = 1

# REACTIVE captain probabilities
const REACTIVE_PANIC_WITHDRAW_CHANCE           = 0.4
const REACTIVE_HOLD_INSTEAD_OF_ENGAGE_CHANCE   = 0.3
const REACTIVE_HESITATE_ON_OPPORTUNITY_CHANCE  = 0.3

# Cost bands (lower = higher priority)
const COST_REFLEX        = 0.1   # withdraw / defensive_posture when clearly needed
const COST_CARE          = 0.25  # support_ally / flank — specific situational actions
const COST_KNOWLEDGE     = 0.3   # concentrate_fire, aggressive_pursuit
const COST_STANDARD      = 0.5   # engage
const COST_HOLD          = 0.8   # hold / default


# Virtual interface

func action_id() -> String:
	return ""

func cost(_ws: CaptainWorldState) -> float:
	return 1.0

func precondition(_ws: CaptainWorldState) -> bool:
	return false

func execute(_ws: CaptainWorldState) -> Dictionary:
	return {}


# Shared static helpers

static func make_captain_decision(
	ws: CaptainWorldState, order_type: String, target_id: Variant
) -> Dictionary:
	return {
		"type": "tactical",
		"subtype": order_type,
		"crew_id": ws.crew_data.get("crew_id", ""),
		"entity_id": ws.crew_data.get("assigned_to", ""),
		"target_id": target_id,
		"delay": CrewAISystem.calculate_decision_delay(ws.crew_data),
		"timestamp": ws.game_time,
	}


## Emit one order per subordinate using the given template dict.
## Template should contain all keys except "to" (filled per subordinate).
static func orders_to_subordinates(ws: CaptainWorldState, template: Dictionary) -> Array:
	var result: Array = []
	for sub_id in ws.crew_data.get("command_chain", {}).get("subordinates", []):
		var order: Dictionary = template.duplicate(true)
		order["to"] = sub_id
		result.append(order)
	return result
