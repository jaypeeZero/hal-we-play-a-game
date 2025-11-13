extends Node

## Automatically discovers and connects ALL signals across the game
## Logs every signal to GameLogger without filtering or hard-coding signal names

var enabled: bool = true
var monitored_nodes: Dictionary = {}  # node_instance_id -> node reference
var monitored_signals: Dictionary = {}  # signal_name -> count
var game_logger  # Reference to GameLogger autoload - untyped to avoid circular dependency

func _ready() -> void:
	pass

## Start monitoring custom signals in the scene tree
func monitor_tree() -> void:
	if not enabled:
		return

	var root: Node = get_tree().root
	_monitor_node(root)

## Stop monitoring
func stop_monitoring() -> void:
	enabled = false
	_disconnect_all()

## Monitor a specific node's signals
func monitor_node(node: Node) -> void:
	if not enabled or not is_node_valid(node):
		return

	_monitor_node(node)

## Check if node is still valid
func is_node_valid(node: Node) -> bool:
	return is_instance_valid(node) and not node.is_queued_for_deletion()

## Get list of all custom signals found
func get_custom_signals() -> Dictionary:
	return monitored_signals.duplicate()

## Internal helper methods

func _monitor_node(node: Node) -> void:
	if not is_node_valid(node):
		return

	# Skip logger nodes to prevent feedback loops
	if node.name in ["GameLogger", "SignalMonitor"]:
		return

	var node_id: int = node.get_instance_id()
	if node_id in monitored_nodes:
		return

	monitored_nodes[node_id] = node

	# Connect to every signal on this node
	for signal_dict: Dictionary in node.get_signal_list():
		var signal_name: String = signal_dict.name

		# Lambda accepts any args to handle signals with varying argument counts
		var on_signal_func = func(_arg1 = null, _arg2 = null, _arg3 = null, _arg4 = null) -> void:
			if enabled and is_node_valid(node):
				_on_signal_emitted([], node, signal_name)

		var handler = Callable(on_signal_func)
		if not node.is_connected(signal_name, handler):
			node.connect(signal_name, handler)

			if signal_name not in monitored_signals:
				monitored_signals[signal_name] = 0
			monitored_signals[signal_name] += 1

	# Recursively monitor children
	for child: Node in node.get_children():
		_monitor_node(child)

## Set reference to GameLogger (called by SignalMonitorAutoload)
func set_game_logger(logger) -> void:
	game_logger = logger

## Signal emission handler
func _on_signal_emitted(args: Array, source_node: Node, signal_name: String) -> void:
	if not enabled or not is_node_valid(source_node):
		return

	# Use cached GameLogger reference if available
	if game_logger:
		game_logger.log_signal(source_node, signal_name, args)

## Disconnect all monitored signals
func _disconnect_all() -> void:
	monitored_nodes.clear()
	monitored_signals.clear()
