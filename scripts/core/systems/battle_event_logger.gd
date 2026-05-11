extends Node
class_name BattleEventLogger

## Battle event + AI decision logger.
##
## Emits standardized events for all battle interactions and AI decisions,
## prints them to the console, and persists them as JSONL to disk so an LLM
## can reconstruct what happened in a game from the log file alone.
##
## Each line written is a self-contained JSON object: {type, timestamp, data}.
## Decisions carry full reasoning context (role, ship, target, threats,
## opportunities, stress, effective skill) so the log is replayable without
## the game state.

# Single source of truth for where battle logs live on disk.
const LOG_DIR := "~/.logs/space-game"

signal event_occurred(event: Dictionary)

var event_history: Array[Dictionary] = []
var track_history: bool = false
var battle_start_time: float = 0.0

var _log_file: FileAccess = null
var _log_path: String = ""

func _ready() -> void:
	battle_start_time = Time.get_ticks_msec() / 1000.0
	_open_log_file()

func _exit_tree() -> void:
	_close_log_file()

# ============================================================================
# CORE LOGGING
# ============================================================================

## Log an event: emit signal, print to console, and append a JSON line to disk.
func log_event(event_type: String, data: Dictionary) -> void:
	var event: Dictionary = {
		"type": event_type,
		"timestamp": Time.get_ticks_msec() / 1000.0 - battle_start_time,
		"data": data
	}

	if track_history:
		event_history.append(event)

	_print_event(event)
	_write_event_to_file(event)
	event_occurred.emit(event)

# ============================================================================
# AI DECISION LOGGING
# ============================================================================

## Log a crew AI decision with full reasoning context.
## Captures who decided, what they decided, and the situational context that
## drove the decision so an LLM can reconstruct the rationale offline.
func log_ai_decision(crew_data: Dictionary, decision: Dictionary, trigger: String = "scheduled") -> void:
	var awareness: Dictionary = crew_data.get("awareness", {})
	var stats: Dictionary = crew_data.get("stats", {})

	log_event("ai_decision", {
		"crew_id": crew_data.get("crew_id", ""),
		"crew_name": crew_data.get("name", ""),
		"role": _role_name(crew_data.get("role", -1)),
		"ship_id": crew_data.get("assigned_to", ""),
		"decision_type": decision.get("type", "unknown"),
		"decision_subtype": decision.get("subtype", ""),
		"target_id": decision.get("target_id", ""),
		"entity_id": decision.get("entity_id", ""),
		"trigger": trigger,
		"stress": stats.get("stress", 0.0),
		"fatigue": stats.get("fatigue", 0.0),
		"threats": _summarize_threats(awareness.get("threats", [])),
		"opportunities": _summarize_opportunities(awareness.get("opportunities", [])),
		"current_target": awareness.get("current_target", ""),
		"engagement_phase": crew_data.get("combat_state", {}).get("engagement_phase", ""),
		"order_received": _summarize_order(crew_data.get("orders", {}).get("received")),
	})

## Log an order being issued up or down the command chain.
func log_order_issued(superior_id: String, subordinate_id: String, order: Dictionary) -> void:
	log_event("order_issued", {
		"superior_id": superior_id,
		"subordinate_id": subordinate_id,
		"order_type": order.get("type", ""),
		"order_subtype": order.get("subtype", ""),
		"target_id": order.get("target_id", ""),
		"play_id": order.get("play_id", ""),
	})

## Log a reactive event that woke a crew member (threat, damage, lock).
func log_ai_trigger(crew_id: String, trigger_type: String, source_id: String = "") -> void:
	log_event("ai_trigger", {
		"crew_id": crew_id,
		"trigger_type": trigger_type,
		"source_id": source_id,
	})

# ============================================================================
# CONVENIENCE METHODS (battle events)
# ============================================================================

func log_creature_spawned(creature_id: String, creature_type: String, owner_id: int, position: Vector2) -> void:
	log_event("creature_spawned", {
		"creature_id": creature_id,
		"creature_type": creature_type,
		"owner_id": owner_id,
		"position": position,
	})

func log_spell_cast(caster_id: String, caster_type: String, spell_id: String, target_pos: Vector2) -> void:
	log_event("spell_cast", {
		"caster_id": caster_id,
		"caster_type": caster_type,
		"spell_id": spell_id,
		"target_pos": target_pos,
	})

func log_projectile_fired(projectile_id: String, source_id: String, target_pos: Vector2) -> void:
	log_event("projectile_fired", {
		"projectile_id": projectile_id,
		"source_id": source_id,
		"target_pos": target_pos,
	})

func log_damage_dealt(victim_id: String, attacker_id: String, amount: float, damage_type: String = "physical") -> void:
	log_event("damage_dealt", {
		"victim_id": victim_id,
		"attacker_id": attacker_id,
		"amount": amount,
		"damage_type": damage_type,
	})

func log_creature_died(creature_id: String, creature_type: String, killer_id: String = "") -> void:
	log_event("creature_died", {
		"creature_id": creature_id,
		"creature_type": creature_type,
		"killer_id": killer_id,
	})

func log_player_died(player_id: int) -> void:
	log_event("player_died", {"player_id": player_id})

func log_mana_changed(player_id: int, new_amount: float) -> void:
	log_event("mana_changed", {"player_id": player_id, "new_amount": new_amount})

# ============================================================================
# QUERY HELPERS (in-memory history)
# ============================================================================

func get_events_of_type(event_type: String) -> Array[Dictionary]:
	return event_history.filter(func(e: Dictionary) -> bool: return e.type == event_type)

func get_events_in_timerange(start_time: float, end_time: float) -> Array[Dictionary]:
	return event_history.filter(func(e: Dictionary) -> bool:
		return e.timestamp >= start_time and e.timestamp <= end_time
	)

func get_events_matching(predicate: Callable) -> Array[Dictionary]:
	return event_history.filter(predicate)

func print_history() -> void:
	print("\n=== Battle Event History ===")
	for event: Dictionary in event_history:
		print("[%.2fs] %s: %s" % [event.timestamp, event.type, event.data])
	print("=== End History ===\n")

## Absolute path of the JSONL file currently being written.
func get_log_path() -> String:
	return _log_path

# ============================================================================
# INTERNAL: file I/O
# ============================================================================

func _open_log_file() -> void:
	var dir_path := _resolve_log_dir()
	var err := DirAccess.make_dir_recursive_absolute(dir_path)
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_warning("BattleEventLogger: could not create log dir %s (err %d)" % [dir_path, err])
		return

	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	_log_path = "%s/battle_%s.jsonl" % [dir_path, stamp]
	_log_file = FileAccess.open(_log_path, FileAccess.WRITE)
	if _log_file == null:
		push_warning("BattleEventLogger: could not open %s for writing" % _log_path)
		return
	print("BattleEventLogger: writing to %s" % _log_path)

func _close_log_file() -> void:
	if _log_file != null:
		_log_file.flush()
		_log_file.close()
		_log_file = null

func _write_event_to_file(event: Dictionary) -> void:
	if _log_file == null:
		return
	_log_file.store_line(JSON.stringify(_to_json_safe(event)))

## Expand the leading `~` in LOG_DIR to the user's home directory.
## Falls back to user:// if HOME is unavailable (sandboxed/web).
func _resolve_log_dir() -> String:
	if not LOG_DIR.begins_with("~"):
		return LOG_DIR
	var home := OS.get_environment("HOME")
	if home.is_empty():
		home = OS.get_environment("USERPROFILE")
	if home.is_empty():
		return ProjectSettings.globalize_path("user://logs")
	return home + LOG_DIR.substr(1)

# ============================================================================
# INTERNAL: formatting
# ============================================================================

func _print_event(event: Dictionary) -> void:
	print("[%.2fs] %s: %s" % [event.timestamp, event.type, _format_data(event.data)])

func _format_data(data: Dictionary) -> String:
	var parts: Array[String] = []
	for key: String in data.keys():
		var value: Variant = data[key]
		if value is float:
			parts.append("%s=%.1f" % [key, value])
		elif value is int:
			parts.append("%s=%d" % [key, value])
		elif value is Vector2:
			parts.append("%s=(%.0f,%.0f)" % [key, value.x, value.y])
		else:
			parts.append("%s=%s" % [key, value])
	return "{" + ", ".join(parts) + "}"

## JSON.stringify can't serialize Vector2/Vector3 etc.; convert them to arrays.
func _to_json_safe(value: Variant) -> Variant:
	if value is Dictionary:
		var out := {}
		for k in value.keys():
			out[str(k)] = _to_json_safe(value[k])
		return out
	if value is Array:
		var out_a: Array = []
		for item in value:
			out_a.append(_to_json_safe(item))
		return out_a
	if value is Vector2:
		return [value.x, value.y]
	if value is Vector3:
		return [value.x, value.y, value.z]
	return value

func _role_name(role: int) -> String:
	match role:
		CrewData.Role.PILOT: return "pilot"
		CrewData.Role.GUNNER: return "gunner"
		CrewData.Role.CAPTAIN: return "captain"
		CrewData.Role.SQUADRON_LEADER: return "squadron_leader"
		CrewData.Role.FLEET_COMMANDER: return "fleet_commander"
		_: return "unknown"

func _summarize_threats(threats: Array) -> Array:
	var out: Array = []
	for t in threats.slice(0, 3):
		if t is Dictionary:
			out.append({
				"id": t.get("entity_id", t.get("id", "")),
				"distance": t.get("distance", 0.0),
				"priority": t.get("priority", 0.0),
			})
	return out

func _summarize_opportunities(opps: Array) -> Array:
	var out: Array = []
	for o in opps.slice(0, 3):
		if o is Dictionary:
			out.append({
				"id": o.get("entity_id", o.get("id", "")),
				"distance": o.get("distance", 0.0),
				"priority": o.get("priority", 0.0),
			})
	return out

func _summarize_order(order: Variant) -> Variant:
	if order == null or not (order is Dictionary):
		return null
	return {
		"type": order.get("type", ""),
		"subtype": order.get("subtype", ""),
		"target_id": order.get("target_id", ""),
	}
