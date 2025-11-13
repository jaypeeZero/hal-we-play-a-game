extends Node

## Thin wrapper autoload that holds the GameLogger instance
## Ensures app-wide singleton behavior while keeping the logger testable

var service  # Untyped to avoid type mismatch with loaded script

func _ready() -> void:
	service = load("res://scripts/core/systems/game_logger.gd").new()
	add_child(service)

## Manual logging API
func write_log(message: String, level: String = "INFO") -> void:
	service.write_log(message, level)

## Log a custom signal event
func log_signal(source_node: Node, signal_name: String, args: Array) -> void:
	service.log_signal(source_node, signal_name, args)

## Log a structured event
func log_event(event_name: String, data: Dictionary = {}) -> void:
	service.log_event(event_name, data)

## Enable/disable logging
func set_enabled(enabled: bool) -> void:
	service.enabled = enabled

## Get log history
func get_history() -> Array[String]:
	return service.get_history()

## Clear log history
func clear_history() -> void:
	service.clear_history()

## Print all logs
func print_history() -> void:
	service.print_history()
