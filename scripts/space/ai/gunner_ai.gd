extends RefCounted
class_name GunnerAI

## Pure functional gunner role AI — GOAP refactor.
## Knowledge-driven target selection with hold/standard/suppressive/precision modes.
## Public API (make_decision signature + constants) is frozen for test compatibility.

# Re-decision delays — re-exported so tests that reference GunnerAI.* still resolve
const SUPPRESSIVE_REDECIDE_DELAY    = GunnerAction.SUPPRESSIVE_REDECIDE_DELAY
const PRECISION_REDECIDE_MIN        = GunnerAction.PRECISION_REDECIDE_MIN
const PRECISION_REDECIDE_MAX        = GunnerAction.PRECISION_REDECIDE_MAX
const STANDARD_REDECIDE_AFTER_ORDER = GunnerAction.STANDARD_REDECIDE_AFTER_ORDER
const HOLD_REDECIDE_MIN             = GunnerAction.HOLD_REDECIDE_MIN
const HOLD_REDECIDE_MAX             = GunnerAction.HOLD_REDECIDE_MAX
const NO_TARGETS_REDECIDE_MIN       = GunnerAction.NO_TARGETS_REDECIDE_MIN
const NO_TARGETS_REDECIDE_MAX       = GunnerAction.NO_TARGETS_REDECIDE_MAX
const MULTI_TARGET_REDECIDE_DELAY   = GunnerAction.MULTI_TARGET_REDECIDE_DELAY
const MULTI_TARGET_THRESHOLD        = GunnerAction.MULTI_TARGET_THRESHOLD
const SUPPRESSIVE_TARGET_COUNT_THRESHOLD = GunnerAction.SUPPRESSIVE_TARGET_COUNT_THRESHOLD


## Public entry point — called by CrewAISystem dispatcher.
static func make_decision(crew_data: Dictionary, game_time: float) -> Dictionary:
	# Reflex: captain order short-circuits the brain (mirrors fighter reflexes)
	if crew_data.get("orders", {}).get("received") != null:
		return _execute_order(crew_data, game_time)

	var updated := crew_data.duplicate(true)
	var ws := GunnerWorldState.build(updated, game_time)
	var decision := GunnerBrain.decide(ws, game_time)

	updated.next_decision_time = game_time + _decision_delay(decision, ws)

	if not decision.is_empty():
		updated.orders.current = decision
		return {"crew_data": updated, "decision": decision}

	# No candidates — omit "decision" key, matching old no-targets return shape
	return {"crew_data": updated}


## Execute a target order received from the captain.
static func _execute_order(crew_data: Dictionary, game_time: float) -> Dictionary:
	var order: Dictionary = crew_data.get("orders", {}).get("received", {})
	var updated := crew_data.duplicate(true)
	updated.orders.current  = order
	updated.orders.received = null

	var fire_subtype: String = order.get("subtype", "fire")
	var decision := {
		"type": "fire",
		"subtype": fire_subtype,
		"crew_id": updated.get("crew_id", ""),
		"entity_id": updated.get("assigned_to", ""),
		"target_id": order.get("target_id", ""),
		"skill_factor": CrewAISystem.calculate_effective_skill(updated),
		"delay": updated.get("stats", {}).get("reaction_time", 0.1),
		"timestamp": game_time,
	}

	updated.next_decision_time = game_time + _order_delay(fire_subtype)
	return {"crew_data": updated, "decision": decision}


## Map a decision subtype → re-decision delay (mirrors _get_fighter_decision_delay).
static func _decision_delay(decision: Dictionary, ws: GunnerWorldState) -> float:
	match decision.get("subtype", ""):
		"suppressive_fire":
			return GunnerAction.SUPPRESSIVE_REDECIDE_DELAY
		"precision_shot":
			return randf_range(GunnerAction.PRECISION_REDECIDE_MIN, GunnerAction.PRECISION_REDECIDE_MAX)
		"hold_fire":
			return randf_range(GunnerAction.HOLD_REDECIDE_MIN, GunnerAction.HOLD_REDECIDE_MAX)
		"fire":
			if ws.target_count >= GunnerAction.MULTI_TARGET_THRESHOLD:
				return GunnerAction.MULTI_TARGET_REDECIDE_DELAY
			return randf_range(GunnerAction.HOLD_REDECIDE_MIN, GunnerAction.HOLD_REDECIDE_MAX)
		_:
			# Empty decision — no targets available
			return randf_range(GunnerAction.NO_TARGETS_REDECIDE_MIN, GunnerAction.NO_TARGETS_REDECIDE_MAX)


## Map an order subtype → re-decision delay on the order path.
static func _order_delay(fire_subtype: String) -> float:
	match fire_subtype:
		"suppressive_fire":
			return GunnerAction.SUPPRESSIVE_REDECIDE_DELAY
		"precision_shot":
			return randf_range(GunnerAction.PRECISION_REDECIDE_MIN, GunnerAction.PRECISION_REDECIDE_MAX)
		_:
			return GunnerAction.STANDARD_REDECIDE_AFTER_ORDER
