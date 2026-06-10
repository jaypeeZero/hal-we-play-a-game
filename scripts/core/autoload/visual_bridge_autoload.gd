extends Node

var bridge  # VisualBridge - untyped to avoid parse-time dependency

func _ready() -> void:
	bridge = VisualBridge.new()
	add_child(bridge)
	bridge.set_renderer(Renderer78.new())
