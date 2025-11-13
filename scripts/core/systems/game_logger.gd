extends Node

## Universal game event logger
## Logs all custom signals and manual log messages to a unified stream
## Works across entire game including menus

signal log_message_written(message: String, level: String)

enum LogLevel { DEBUG, INFO, WARN, ERROR }

var enabled: bool = true
var log_history: Array[String] = []
var track_history: bool = true
var start_time: float = 0.0

# Debounce state
var pending_message: String = ""
var pending_level: String = ""
var pending_count: int = 0
var last_flush_time: float = 0.0
var debounce_window: float = 0.05  # 50ms base window for batching
var current_window: float = 0.05  # Extends with each repeated log
var max_window: float = 1.0  # Maximum window (1 second)

func _ready() -> void:
	start_time = Time.get_ticks_msec() / 1000.0
	write_log("GameLogger initialized", "INFO")

func _process(_delta: float) -> void:
	# Periodically flush pending logs to avoid holding them forever
	var now: float = Time.get_ticks_msec() / 1000.0
	if pending_message != "" and (now - last_flush_time) > current_window:
		_flush_pending()

## Manual logging method - primary API for custom logs
func write_log(message: String, level: String = "INFO") -> void:
	if not enabled:
		return

	var timestamp: String = _get_timestamp()
	var formatted: String = "%s [%s] %s" % [timestamp, level, message]

	_output_debounced(formatted, level)

## Log a custom signal event
func log_signal(source_node: Node, signal_name: String, args: Array) -> void:
	if not enabled:
		return

	var timestamp: String = _get_timestamp()
	var source_name: String = source_node.name if source_node else "Unknown"
	var args_str: String = _format_args(args)
	var formatted: String = "%s [SIGNAL] %s.%s%s" % [timestamp, source_name, signal_name, args_str]

	_output_debounced(formatted, "SIGNAL")

## Log a structured event
func log_event(event_name: String, data: Dictionary = {}) -> void:
	if not enabled:
		return

	var timestamp: String = _get_timestamp()
	var data_str: String = _format_data(data)
	var formatted: String = "%s [EVENT] %s %s" % [timestamp, event_name, data_str]

	_output_debounced(formatted, "EVENT")

## Clear log history
func clear_history() -> void:
	log_history.clear()

## Get all logs
func get_history() -> Array[String]:
	return log_history

## Print all logged messages to console
func print_history() -> void:
	print("\n=== Game Log History ===")
	for msg: String in log_history:
		print(msg)
	print("=== End Log History ===\n")

## Internal helper methods

func _output_debounced(message: String, level: String) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	var time_since_flush: float = now - last_flush_time

	if pending_message == message:
		# Same message: extend window and increment count
		pending_count += 1
		current_window = minf(current_window * 1.5, max_window)
		last_flush_time = now
	else:
		# Different message: flush pending and start new one
		if time_since_flush > debounce_window:
			_flush_pending()
		pending_message = message
		pending_level = level
		current_window = debounce_window
		pending_count = 1
		last_flush_time = now

func _flush_pending() -> void:
	if pending_message == "":
		return

	var output: String = pending_message
	if pending_count > 1:
		output = "%s - x%d" % [pending_message, pending_count]

	if track_history:
		log_history.append(output)

	print(output)
	log_message_written.emit(output, pending_level)

	pending_message = ""
	pending_level = ""
	pending_count = 0
	current_window = debounce_window

func _get_timestamp() -> String:
	var elapsed: float = (Time.get_ticks_msec() / 1000.0) - start_time
	return "[%.2fs]" % elapsed

func _format_args(args: Array) -> String:
	if args.is_empty():
		return "()"

	var parts: Array[String] = []
	for arg: Variant in args:
		parts.append(_format_value(arg))
	return "(" + ", ".join(parts) + ")"

func _format_data(data: Dictionary) -> String:
	if data.is_empty():
		return "{}"

	var parts: Array[String] = []
	for key: String in data.keys():
		var value: Variant = data[key]
		parts.append("%s=%s" % [key, _format_value(value)])
	return "{" + ", ".join(parts) + "}"

func _format_value(value: Variant) -> String:
	if value is float:
		return "%.1f" % value
	elif value is int:
		return str(value)
	elif value is Vector2:
		return "(%.0f,%.0f)" % [value.x, value.y]
	elif value is String:
		return value
	elif value is bool:
		return "true" if value else "false"
	elif value is Array:
		return str(value)
	elif value is Dictionary:
		return str(value)
	elif value == null:
		return "null"
	else:
		return str(value)
