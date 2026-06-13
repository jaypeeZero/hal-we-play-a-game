extends RefCounted
class_name SquadronLeaderAI

## Pure functional squadron leader role AI — GOAP refactor.
## Squadron play system runs as a reflex before the brain (mirrors fighter pilot priority cascade).
## Public API (make_decision signature) frozen for test compatibility.

const REDECIDE_MIN = 1.5
const REDECIDE_MAX = 3.0


## Public entry point — called by CrewAISystem dispatcher.
static func make_decision(crew_data: Dictionary, game_time: float) -> Dictionary:
	var updated := crew_data.duplicate(true)

	# SQUADRON PLAYS — runs before the GOAP brain. A play stays in flight across
	# decisions; wrapping it in an action would fight the plan lock.
	var play_result := _try_run_squadron_play(updated, game_time)
	if not play_result.is_empty():
		return play_result

	var ws := SquadronLeaderWorldState.build(updated, game_time)
	var result := SquadronLeaderBrain.decide(ws, game_time)

	if result.is_empty():
		# NOTE: no-decision path intentionally does NOT advance next_decision_time,
		# so the leader stays due and re-rolls every scheduler tick.
		# This preserves the existing INDIVIDUAL-coordination-fail behavior.
		# Likely a bug worth a separate fix (should use idle cadence like other roles).
		return {"crew_data": updated}

	var decision: Dictionary = result.get("decision", {})
	var issued_orders: Array = result.get("issued_orders", [])

	updated.orders.issued  = issued_orders
	updated.orders.current = decision
	updated.next_decision_time = game_time + randf_range(REDECIDE_MIN, REDECIDE_MAX)

	return {"crew_data": updated, "decision": decision}


## Drive the squadron play system. Returns the standard {crew_data, decision}
## envelope when a play is active, or {} to let the GOAP brain run.
static func _try_run_squadron_play(crew_data: Dictionary, game_time: float) -> Dictionary:
	var subordinates: Array = crew_data.get("command_chain", {}).get("subordinates", [])
	if subordinates.size() < 2:
		return {}

	var geometry := _build_play_geometry(crew_data)
	if geometry.is_empty():
		return {}

	var wing_state := {"fighters": subordinates}
	var result := SquadronPlaySystem.tick_squadron_play(crew_data, wing_state, geometry, game_time)
	if not result.get("selected", false):
		return {}

	var updated: Dictionary = result.get("crew_data", crew_data)
	var orders: Array       = result.get("orders", [])
	var active_play: Dictionary = updated.get("squadron_state", {}).get("active_play", {})

	updated.orders.issued = orders
	var decision := {
		"type": "squadron_command",
		"subtype": "execute_play",
		"crew_id": updated.get("crew_id", ""),
		"play_id": active_play.get("play_id", ""),
		"phase": active_play.get("phase_index", 0),
		"target_id": active_play.get("target_id", ""),
		"delay": CrewAISystem.calculate_decision_delay(updated),
		"timestamp": game_time,
	}
	updated.orders.current = decision
	updated.next_decision_time = game_time + randf_range(REDECIDE_MIN, REDECIDE_MAX)

	_log_play_executed(updated, active_play)

	return {"crew_data": updated, "decision": decision}


## Build geometry for the play system from leader awareness.
static func _build_play_geometry(crew_data: Dictionary) -> Dictionary:
	var opportunities: Array = crew_data.get("awareness", {}).get("opportunities", [])
	if opportunities.is_empty():
		return {}
	var top: Dictionary = opportunities[0]
	var target_id: String = top.get("id", "")
	if target_id == "":
		return {}
	var pos: Vector2 = top.get("position", Vector2.ZERO)
	var vel: Vector2 = top.get("velocity", Vector2.ZERO)
	var facing := vel.normalized() if vel.length() > 1.0 else Vector2.RIGHT
	return {
		"target_id": target_id,
		"target_position": pos,
		"target_facing": facing,
	}


static func _log_play_executed(leader_crew: Dictionary, active_play: Dictionary) -> void:
	var loop := Engine.get_main_loop()
	if loop == null or not loop is SceneTree:
		return
	var root := (loop as SceneTree).root
	if root == null or not root.has_node("BattleEventLoggerAutoload"):
		return
	var logger := root.get_node("BattleEventLoggerAutoload")
	var fighters: Array = active_play.get("role_assignments", {}).keys()
	logger.log_event("play_executed", {
		"leader_crew_id": leader_crew.get("crew_id", ""),
		"play_id": active_play.get("play_id", ""),
		"phase": active_play.get("phase_index", 0),
		"fighters": fighters.size(),
		"target_id": active_play.get("target_id", ""),
	})
