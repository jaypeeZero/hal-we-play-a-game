extends RefCounted
class_name CommanderAI

## Pure functional fleet commander role AI — GOAP refactor.
## Strategic decisions across all squadrons: concentrate force, withdraw, shift focus.
## commit_reserves dropped (dead branch — knowledge match was a pass/TODO with no mechanic).
## Public API (make_decision signature) frozen for test compatibility.

const REDECIDE_MIN = 2.0
const REDECIDE_MAX = 4.0


## Public entry point — called by CrewAISystem dispatcher.
static func make_decision(crew_data: Dictionary, game_time: float) -> Dictionary:
	var updated := crew_data.duplicate(true)
	var ws := CommanderWorldState.build(updated, game_time)
	var result := CommanderBrain.decide(ws, game_time)

	# AssessAction always qualifies, so result should never be empty, but guard anyway
	if result.is_empty():
		updated.next_decision_time = game_time + randf_range(REDECIDE_MIN, REDECIDE_MAX)
		return {"crew_data": updated}

	var decision: Dictionary = result.get("decision", {})
	var issued_orders: Array = result.get("issued_orders", [])

	updated.orders.issued   = issued_orders
	updated.orders.current  = decision
	updated.next_decision_time = game_time + _decision_delay()

	return {"crew_data": updated, "decision": decision}


## Uniform re-decision delay — commander has only one cadence.
static func _decision_delay() -> float:
	return randf_range(REDECIDE_MIN, REDECIDE_MAX)
