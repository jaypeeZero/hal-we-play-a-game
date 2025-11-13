## Interface: Any visual rendering system
## Implementations: EmojiRenderer, IsometricRenderer, NullRenderer
class_name IVisualRenderer extends Node

## Initialize renderer with theme data
## Called once when renderer becomes active
func initialize(theme: IVisualTheme) -> void:
	assert(false, "IVisualRenderer.initialize() must be implemented")

## Attach renderer to newly spawned entity
## Create all visual nodes needed for this entity
func attach_to_entity(entity: IRenderable) -> void:
	assert(false, "IVisualRenderer.attach_to_entity() must be implemented")

## Detach renderer from entity being destroyed
## Clean up all visual nodes for this entity
func detach_from_entity(entity: IRenderable) -> void:
	assert(false, "IVisualRenderer.detach_from_entity() must be implemented")

## Update visual state in response to entity state change
func update_state(entity_id: String, state: EntityState) -> void:
	assert(false, "IVisualRenderer.update_state() must be implemented")

## Play animation in response to entity request
func play_animation(entity_id: String, request: AnimationRequest) -> void:
	assert(false, "IVisualRenderer.play_animation() must be implemented")

## Clean up all renderer resources
## Called when renderer is being deactivated
func cleanup() -> void:
	assert(false, "IVisualRenderer.cleanup() must be implemented")
