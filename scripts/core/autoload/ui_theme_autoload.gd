extends Node

## Applies the UiKit design system as the scene-tree root theme so every
## Control in the game inherits the console look without per-node overrides.


func _ready() -> void:
	get_tree().root.theme = UiKit.build_theme()
