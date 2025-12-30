extends Node

## Thin wrapper autoload that holds the BattleEventLogger instance
## Ensures app-wide singleton behavior while keeping the logger testable

# Preload at compile time - required for exported builds
const BattleEventLoggerScript = preload("res://scripts/core/systems/battle_event_logger.gd")

var service: Node

func _ready() -> void:
	service = BattleEventLoggerScript.new()
	add_child(service)
	print("BattleEventLogger service initialized")

## Direct delegation methods
func log_event(event_type: String, data: Dictionary) -> void:
	service.log_event(event_type, data)

func log_creature_spawned(creature_id: String, creature_type: String, owner_id: int, position: Vector2) -> void:
	service.log_creature_spawned(creature_id, creature_type, owner_id, position)

func log_spell_cast(caster_id: String, caster_type: String, spell_id: String, target_pos: Vector2) -> void:
	service.log_spell_cast(caster_id, caster_type, spell_id, target_pos)

func log_projectile_fired(projectile_id: String, source_id: String, target_pos: Vector2) -> void:
	service.log_projectile_fired(projectile_id, source_id, target_pos)

func log_damage_dealt(victim_id: String, attacker_id: String, amount: float, damage_type: String = "physical") -> void:
	service.log_damage_dealt(victim_id, attacker_id, amount, damage_type)

func log_creature_died(creature_id: String, creature_type: String, killer_id: String = "") -> void:
	service.log_creature_died(creature_id, creature_type, killer_id)

func log_player_died(player_id: int) -> void:
	service.log_player_died(player_id)

func log_mana_changed(player_id: int, new_amount: float) -> void:
	service.log_mana_changed(player_id, new_amount)
