extends Node

## Thin wrapper autoload that holds the SignalMonitor instance
## Starts monitoring custom signals at game startup
## Ensures app-wide singleton behavior while keeping the monitor testable

var service  # Untyped to avoid type mismatch with loaded script

func _ready() -> void:
	# Wait for GameLogger to be ready
	await get_tree().process_frame

	service = load("res://scripts/core/systems/signal_monitor.gd").new()
	add_child(service)

	# Set GameLogger reference
	var logger = get_node_or_null("/root/GameLogger")
	if logger:
		service.set_game_logger(logger)

	# Start monitoring all custom signals
	service.monitor_tree()

## Monitor a specific node
func monitor_node(node: Node) -> void:
	if service:
		service.monitor_node(node)

## Stop monitoring
func stop_monitoring() -> void:
	if service:
		service.stop_monitoring()

## Get all custom signals being monitored
func get_custom_signals() -> Dictionary:
	if service:
		return service.get_custom_signals()
	return {}

## Enable/disable monitoring
func set_enabled(enabled: bool) -> void:
	if service:
		service.enabled = enabled
