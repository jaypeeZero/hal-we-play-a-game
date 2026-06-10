extends Node

var bridge  # VisualBridge - untyped to avoid parse-time dependency

func _ready() -> void:
	bridge = VisualBridge.new()
	add_child(bridge)
	bridge.set_renderer(Renderer78.new())

	var logger = get_node_or_null("/root/GameLogger")
	if logger:
		logger.write_log("VisualBridgeAutoload ready (using Renderer78)")
	else:
		print("VisualBridgeAutoload ready (using Renderer78)")
