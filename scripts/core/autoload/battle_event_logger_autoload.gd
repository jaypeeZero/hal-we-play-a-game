extends Node

## Thin wrapper autoload that holds the BattleEventLogger instance
## Ensures app-wide singleton behavior while keeping the logger testable

var service: Node

func _ready() -> void:
	service = load("res://scripts/core/systems/battle_event_logger.gd").new()
	add_child(service)

## Direct delegation methods
func log_event(event_type: String, data: Dictionary) -> void:
	service.log_event(event_type, data)

func log_damage_dealt(victim_id: String, attacker_id: String, amount: float, damage_type: String = "physical") -> void:
	service.log_damage_dealt(victim_id, attacker_id, amount, damage_type)

func log_ai_decision(crew_data: Dictionary, decision: Dictionary, trigger: String = "scheduled") -> void:
	service.log_ai_decision(crew_data, decision, trigger)

func log_order_issued(superior_id: String, subordinate_id: String, order: Dictionary) -> void:
	service.log_order_issued(superior_id, subordinate_id, order)

func log_ai_trigger(crew_id: String, trigger_type: String, source_id: String = "") -> void:
	service.log_ai_trigger(crew_id, trigger_type, source_id)
