class_name CommanderAction
extends RefCounted

## Base class for GOAP commander actions.
## execute() returns {"decision": ..., "issued_orders": [...]}

# Strategic-withdrawal trigger
const WITHDRAWAL_THREAT_MULTIPLIER = 2

# Cost bands
const COST_WITHDRAWAL   = 0.2  # urgent strategic withdrawal
const COST_CONCENTRATE  = 0.3  # concentrate force
const COST_SHIFT        = 0.35 # shift focus
const COST_HOLD_LINE    = 0.4  # hold the line
const COST_ASSESS       = 1.0  # default — always fires, highest cost


# Virtual interface

func action_id() -> String:
	return ""

func cost(_ws: CommanderWorldState) -> float:
	return 1.0

func precondition(_ws: CommanderWorldState) -> bool:
	return false

func execute(_ws: CommanderWorldState) -> Dictionary:
	return {}


# Shared static helpers

static func make_strategic_decision(
	ws: CommanderWorldState,
	subtype: String,
	extra: Dictionary = {}
) -> Dictionary:
	var d := {
		"type": "strategic",
		"subtype": subtype,
		"crew_id": ws.crew_data.get("crew_id", ""),
		"delay": CrewAISystem.calculate_decision_delay(ws.crew_data),
		"timestamp": ws.game_time,
	}
	for k in extra:
		d[k] = extra[k]
	return d


static func orders_to_subordinates(ws: CommanderWorldState, template: Dictionary) -> Array:
	var result: Array = []
	for sub_id in ws.crew_data.get("command_chain", {}).get("subordinates", []):
		var order: Dictionary = template.duplicate(true)
		order["to"] = sub_id
		result.append(order)
	return result
