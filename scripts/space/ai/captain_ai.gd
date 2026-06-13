extends RefCounted
class_name CaptainAI

## Pure functional captain role AI — GOAP refactor.
## Knowledge-driven ship-level tactical decisions, command-style modulated.
## Public API (make_decision signature) frozen for test compatibility.

const REDECIDE_MIN = 1.0
const REDECIDE_MAX = 2.0


## Public entry point — called by CrewAISystem dispatcher.
static func make_decision(crew_data: Dictionary, game_time: float) -> Dictionary:
	# Reflex: squadron-leader order short-circuits the brain (mirrors fighter reflexes)
	if crew_data.get("orders", {}).get("received") != null:
		return _execute_order(crew_data, game_time)

	var updated := crew_data.duplicate(true)
	var ws := CaptainWorldState.build(updated, game_time)
	var result := CaptainBrain.decide(ws, game_time)

	if result.is_empty():
		updated.next_decision_time = game_time + randf_range(REDECIDE_MIN, REDECIDE_MAX)
		return {"crew_data": updated}

	var decision: Dictionary     = result.get("decision", {})
	var issued_orders: Array     = result.get("issued_orders", [])

	updated.orders.current  = decision
	updated.orders.issued   = issued_orders
	updated.next_decision_time = game_time + _decision_delay()

	return {"crew_data": updated, "decision": decision}


## Execute a squadron-leader order: break it down for subordinates.
static func _execute_order(crew_data: Dictionary, game_time: float) -> Dictionary:
	var order: Dictionary = crew_data.get("orders", {}).get("received", {})
	var updated := crew_data.duplicate(true)
	updated.orders.current  = order
	updated.orders.received = null

	var subordinate_orders := _break_down_order(order, updated)
	updated.orders.issued = subordinate_orders
	updated.next_decision_time = game_time + _decision_delay()

	return {
		"crew_data": updated,
		"decision": _make_order_decision(updated, order, game_time),
	}


## Uniform re-decision delay — captain has only one cadence.
static func _decision_delay() -> float:
	return randf_range(REDECIDE_MIN, REDECIDE_MAX)


## Build a tactical decision dict from a received order.
static func _make_order_decision(crew_data: Dictionary, order: Dictionary, game_time: float) -> Dictionary:
	return {
		"type": "tactical",
		"subtype": order.get("type", "hold"),
		"crew_id": crew_data.get("crew_id", ""),
		"entity_id": crew_data.get("assigned_to", ""),
		"target_id": order.get("target_id"),
		"delay": CrewAISystem.calculate_decision_delay(crew_data),
		"timestamp": game_time,
	}


## Translate a received order into subordinate orders.
static func _break_down_order(order: Dictionary, crew_data: Dictionary) -> Array:
	match order.get("type", ""):
		"engage":
			return _orders_to_subs(crew_data, {
				"type": "engage",
				"subtype": "pursue",
				"target_id": order.get("target_id", ""),
			})
		"withdraw":
			return _orders_to_subs(crew_data, {"type": "withdraw", "subtype": "evade"})
		_:
			return []


## Helper: emit one order per subordinate.
static func _orders_to_subs(crew_data: Dictionary, template: Dictionary) -> Array:
	var result: Array = []
	for sub_id in crew_data.get("command_chain", {}).get("subordinates", []):
		var o: Dictionary = template.duplicate(true)
		o["to"] = sub_id
		result.append(o)
	return result
