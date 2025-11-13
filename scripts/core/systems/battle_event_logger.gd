extends Node
class_name BattleEventLogger

## Pure event stream logger
## Emits standardized events for all battle interactions
## Tests and systems can subscribe to watch the event stream

signal event_occurred(event: Dictionary)

# Event history (optional, for replay/debugging)
var event_history: Array[Dictionary] = []
var track_history: bool = false
var battle_start_time: float = 0.0

func _ready() -> void:
	battle_start_time = Time.get_ticks_msec() / 1000.0

## Log an event and emit it to all subscribers
func log_event(event_type: String, data: Dictionary) -> void:
	var event: Dictionary = {
		"type": event_type,
		"timestamp": Time.get_ticks_msec() / 1000.0 - battle_start_time,
		"data": data
	}

	if track_history:
		event_history.append(event)

	# Print event to console
	_print_event(event)

	event_occurred.emit(event)

## Convenience methods for common events
func log_creature_spawned(creature_id: String, creature_type: String, owner_id: int, position: Vector2) -> void:
	log_event("creature_spawned", {
		"creature_id": creature_id,
		"creature_type": creature_type,
		"owner_id": owner_id,
		"position": position
	})

func log_spell_cast(caster_id: String, caster_type: String, spell_id: String, target_pos: Vector2) -> void:
	log_event("spell_cast", {
		"caster_id": caster_id,
		"caster_type": caster_type,
		"spell_id": spell_id,
		"target_pos": target_pos
	})

func log_projectile_fired(projectile_id: String, source_id: String, target_pos: Vector2) -> void:
	log_event("projectile_fired", {
		"projectile_id": projectile_id,
		"source_id": source_id,
		"target_pos": target_pos
	})

func log_damage_dealt(victim_id: String, attacker_id: String, amount: float, damage_type: String = "physical") -> void:
	log_event("damage_dealt", {
		"victim_id": victim_id,
		"attacker_id": attacker_id,
		"amount": amount,
		"damage_type": damage_type
	})

func log_creature_died(creature_id: String, creature_type: String, killer_id: String = "") -> void:
	log_event("creature_died", {
		"creature_id": creature_id,
		"creature_type": creature_type,
		"killer_id": killer_id
	})

func log_player_died(player_id: int) -> void:
	log_event("player_died", {
		"player_id": player_id
	})

func log_mana_changed(player_id: int, new_amount: float) -> void:
	log_event("mana_changed", {
		"player_id": player_id,
		"new_amount": new_amount
	})

## Query helpers for event history (if enabled)

func get_events_of_type(event_type: String) -> Array[Dictionary]:
	return event_history.filter(func(e: Dictionary) -> bool: return e.type == event_type)

func get_events_in_timerange(start_time: float, end_time: float) -> Array[Dictionary]:
	return event_history.filter(func(e: Dictionary) -> bool:
		return e.timestamp >= start_time and e.timestamp <= end_time
	)

func get_events_matching(predicate: Callable) -> Array[Dictionary]:
	return event_history.filter(predicate)

func _print_event(event: Dictionary) -> void:
	var timestamp: String = "[%.2fs]" % event.timestamp
	var event_type: String = event.type
	var data_str: String = _format_data(event.data)
	print("%s %s: %s" % [timestamp, event_type, data_str])

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

func print_history() -> void:
	print("\n=== Battle Event History ===")
	for event: Dictionary in event_history:
		print("[%.2fs] %s: %s" % [event.timestamp, event.type, event.data])
	print("=== End History ===\n")
