extends Node

## Autoload for hull shape data
## Loads hull geometries from JSON at game start

func _ready() -> void:
	HullShapes.load_hull_shapes()
