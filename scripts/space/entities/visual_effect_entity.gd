class_name VisualEffectEntity
extends IRenderable

## Minimal visual effect entity for temporary animations/particles
## Used for damage effects, explosions, etc.
## Auto-destroys after lifetime expires

var entity_id: String = ""
var effect_type: String = ""
var lifetime: float = 0.0
var max_lifetime: float = 1.0

## Initialize entity with ID and effect type
func initialize(id: String, type: String, duration: float = 1.0) -> void:
	entity_id = id
	effect_type = type
	max_lifetime = duration

	# Register with visual bridge for rendering
	if VisualBridgeAutoload.bridge:
		VisualBridgeAutoload.bridge.register_entity(self)

## Update lifetime and check if expired
func update(delta: float) -> bool:
	lifetime += delta
	return lifetime >= max_lifetime

## Emit state for renderer (called by game loop)
func emit_state(effect_data: Dictionary) -> void:
	var state = _create_entity_state(effect_data)
	state_changed.emit(state)

## Create entity state for renderer
func _create_entity_state(effect_data: Dictionary) -> EntityState:
	var state = EntityState.new()
	state.velocity = Vector2.ZERO
	state.facing_direction = Vector2.DOWN
	state.health_percent = 1.0 - (lifetime / max_lifetime)  # Fade over time
	return state

## IRenderable implementation
func get_entity_id() -> String:
	return entity_id

func get_visual_type() -> String:
	return effect_type

## Clean up
func _exit_tree() -> void:
	if VisualBridgeAutoload.bridge:
		VisualBridgeAutoload.bridge.unregister_entity(self)
