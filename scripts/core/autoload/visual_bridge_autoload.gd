extends Node

var bridge  # VisualBridge - untyped to avoid parse-time dependency

func _ready() -> void:
	bridge = VisualBridge.new()
	add_child(bridge)

	# Initialize with Renderer78 (uses HullShapes data)
	var renderer = Renderer78.new()
	var theme = JsonTheme.load_from_file("res://themes/emoji_simple.json")
	bridge.set_renderer(renderer, theme)

	# Log via GameLogger if available, otherwise use print
	var logger = get_node_or_null("/root/GameLogger")
	if logger:
		logger.write_log("VisualBridgeAutoload ready (using Renderer78)")
	else:
		print("VisualBridgeAutoload ready (using Renderer78)")

## Convenience methods for global access
func register_entity(entity: IRenderable) -> void:
	bridge.register_entity(entity)

func unregister_entity(entity: IRenderable) -> void:
	bridge.unregister_entity(entity)

func set_renderer(renderer: IVisualRenderer, theme: IVisualTheme) -> void:
	bridge.set_renderer(renderer, theme)

func get_active_theme() -> IVisualTheme:
	return bridge.active_theme

func get_active_renderer() -> IVisualRenderer:
	return bridge.active_renderer
