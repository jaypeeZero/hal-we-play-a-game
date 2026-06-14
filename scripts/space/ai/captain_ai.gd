extends RefCounted
class_name CaptainAI

## Pure functional captain role AI — GOAP refactor.
## Knowledge-driven ship-level tactical decisions, command-style modulated.
## Public API (make_decision signature) frozen for test compatibility.

const REDECIDE_MIN = 1.0
const REDECIDE_MAX = 2.0

## Commander cadence — matches CommanderAI.REDECIDE_MIN/MAX.
const COMMANDER_REDECIDE_MIN = 2.0
const COMMANDER_REDECIDE_MAX = 4.0


## Public entry point — called by CrewAISystem dispatcher.
static func make_decision(crew_data: Dictionary, game_time: float) -> Dictionary:
	# BLENDED ABSORBER — must run BEFORE the old short-circuit so commander
	# orders set posture/focus on the ship rather than producing discrete sub-orders.
	# After absorption orders.received is null, so the short-circuit below is skipped
	# and CaptainBrain runs normally with posture/focus already stamped.
	var absorbed := _absorb_commander_order(crew_data)

	# Old short-circuit path is now dead for command orders (absorbed above).
	# Kept for any non-command received order that slips through (defensive).
	if absorbed.get("orders", {}).get("received") != null:
		return _execute_order(absorbed, game_time)

	var updated := absorbed.duplicate(true)

	# Commander hat: run CommanderAI alongside the captain's normal brain so
	# the flagship also adopts the fleet posture it commands. The commander
	# decision sets orders.issued (to subordinates) and stamps posture/focus
	# on the flagship's own ship.orders via _run_commander_brain.
	if crew_data.get("command_hat", "") == "commander":
		updated = _run_commander_brain(updated, game_time)

	var ws := CaptainWorldState.build(updated, game_time)
	var result := CaptainBrain.decide(ws, game_time)

	if result.is_empty():
		updated.next_decision_time = game_time + randf_range(REDECIDE_MIN, REDECIDE_MAX)
		return {"crew_data": updated}

	var decision: Dictionary  = result.get("decision", {})
	var captain_orders: Array = result.get("issued_orders", [])

	updated.orders.current = decision
	# Merge captain orders with any commander orders already placed this tick.
	var existing_issued: Array = updated.orders.get("issued", []).duplicate()
	existing_issued.append_array(captain_orders)
	updated.orders.issued   = existing_issued
	updated.next_decision_time = game_time + _decision_delay()

	return {"crew_data": updated, "decision": decision}


## Absorb a received commander order into ship.orders.posture / ship.orders.focus_target.
## Clears orders.received so the old discrete short-circuit is bypassed and
## CaptainBrain runs normally on the blended posture/focus it set.
## Mirrors CrewAISystem._absorb_command_order but is self-contained so CaptainAI
## tests don't require the full system stack.
static func _absorb_commander_order(crew_data: Dictionary) -> Dictionary:
	var received: Variant = crew_data.get("orders", {}).get("received")
	if received == null or not received is Dictionary:
		return crew_data

	var updated: Dictionary = crew_data.duplicate(true)
	var order_type: String = received.get("type", "")

	match order_type:
		"engage":
			# Concentrate / redirect: stamp the ship's focus target so the pilot reads it.
			var target_id: String = received.get("target_id", "")
			if target_id != "":
				updated.orders["focus_target"] = target_id
			updated.orders["posture"] = ""   # clear any prior posture — go offensive

		"withdraw":
			# Fleet-level retreat: stamp withdraw posture on the ship.
			updated.orders["posture"] = "withdraw"

		"hold":
			# Hold the line: stamp hold posture on the ship.
			updated.orders["posture"] = "hold"

		_:
			# Unknown / irrelevant order type — clear without side-effects.
			pass

	updated.orders.received = null
	return updated


## Activate CommanderBrain for a commander-hat captain. Merges issued orders
## into crew_data.orders.issued and stamps the flagship's own posture/focus
## so the ship the commander captains adopts the fleet stance it just ordered.
## Thrash risk: commander cadence 2-4 s, plan-lock 1.2 s — bounded, acceptable.
static func _run_commander_brain(crew_data: Dictionary, game_time: float) -> Dictionary:
	var ws := CommanderWorldState.build(crew_data, game_time)
	var result := CommanderBrain.decide(ws, game_time)

	var updated: Dictionary = crew_data.duplicate(true)

	if result.is_empty():
		# AssessAction always qualifies — guard defensively.
		updated["commander_next_decision_time"] = \
			game_time + randf_range(COMMANDER_REDECIDE_MIN, COMMANDER_REDECIDE_MAX)
		return updated

	var decision: Dictionary = result.get("decision", {})
	var cmd_orders: Array    = result.get("issued_orders", [])
	var subtype: String      = decision.get("subtype", "")

	# Merge commander-issued orders (to subordinate leaders) with any already present.
	var existing_issued: Array = updated.orders.get("issued", []).duplicate()
	existing_issued.append_array(cmd_orders)
	updated.orders.issued = existing_issued

	# Flagship adopts its own commanded posture/focus — the ship the commander
	# captains behaves consistently with the fleet order it just issued.
	match subtype:
		"strategic_withdrawal":
			updated.orders["posture"] = "withdraw"
		"hold_line":
			updated.orders["posture"] = "hold"
		"concentrate_force", "shift_focus":
			var target_id: String = decision.get("target_id", "")
			if target_id != "":
				updated.orders["focus_target"] = target_id
			updated.orders["posture"] = ""   # offensive — clear any prior hold/withdraw

	# Advance the commander's own cadence timer (separate from captain cadence).
	updated["commander_next_decision_time"] = \
		game_time + randf_range(COMMANDER_REDECIDE_MIN, COMMANDER_REDECIDE_MAX)

	return updated


## Execute a received non-command order (defensive fallback — rarely reached
## now that _absorb_commander_order consumes command orders first).
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


## Translate a received order into subordinate orders (used by the fallback
## _execute_order path for non-command orders only).
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
