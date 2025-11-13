class_name NullRenderer extends Node

## Implements IVisualRenderer interface
## Creates no visual nodes - used for testing and headless mode

var _attached_entity_count: int = 0

func initialize(theme: IVisualTheme) -> void:
	name = "NullRenderer"
	print("NullRenderer initialized (headless mode)")

func attach_to_entity(entity: IRenderable) -> void:
	_attached_entity_count += 1
	# No visual nodes created

func detach_from_entity(entity: IRenderable) -> void:
	_attached_entity_count -= 1
	# No cleanup needed

func update_state(entity_id: String, state: EntityState) -> void:
	# No-op
	pass

func play_animation(entity_id: String, request: AnimationRequest) -> void:
	# No-op
	pass

func cleanup() -> void:
	_attached_entity_count = 0
	print("NullRenderer cleaned up")

func get_attached_count() -> int:
	return _attached_entity_count
