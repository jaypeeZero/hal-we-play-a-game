class_name VisualBridge extends Node

## Active renderer (can be swapped at runtime)
var active_renderer: IVisualRenderer = null

## Registry of all entities (entity_id -> IRenderable)
var _entity_registry: Dictionary = {}

## Emitted when renderer changes
signal renderer_changed(new_renderer: IVisualRenderer)

func _ready() -> void:
	name = "VisualBridge"

func _exit_tree() -> void:
	# Clean up renderer when VisualBridge is destroyed
	_detach_old_renderer()

## Set active renderer
## Detaches old renderer, attaches new renderer to all entities
func set_renderer(renderer: IVisualRenderer) -> void:
	_detach_old_renderer()
	_attach_new_renderer(renderer)

func _detach_old_renderer() -> void:
	if not active_renderer:
		return

	# Detach from all registered entities
	for entity_id in _entity_registry:
		var entity: IRenderable = _entity_registry[entity_id]
		if is_instance_valid(entity):
			active_renderer.detach_from_entity(entity)

	# Cleanup renderer resources
	active_renderer.cleanup()

	# Remove from scene tree and free
	if active_renderer.get_parent() == self:
		remove_child(active_renderer)
	active_renderer.queue_free()
	active_renderer = null

func _attach_new_renderer(renderer: IVisualRenderer) -> void:
	active_renderer = renderer

	# Add renderer to scene tree
	add_child(active_renderer)

	active_renderer.initialize()

	# Attach to all registered entities
	for entity_id in _entity_registry:
		var entity: IRenderable = _entity_registry[entity_id]
		if is_instance_valid(entity):
			active_renderer.attach_to_entity(entity)

	renderer_changed.emit(active_renderer)

## Register newly spawned entity
func register_entity(entity: IRenderable) -> void:
	var entity_id: String = entity.get_entity_id()

	if entity_id in _entity_registry:
		push_warning("Entity already registered: %s" % entity_id)
		return

	# Add to registry
	_entity_registry[entity_id] = entity

	# Connect entity signals
	entity.state_changed.connect(_on_entity_state_changed.bind(entity_id))
	entity.animation_requested.connect(_on_entity_animation_requested.bind(entity_id))

	# Connect cleanup signal
	if not entity.tree_exiting.is_connected(_on_entity_destroyed):
		entity.tree_exiting.connect(_on_entity_destroyed.bind(entity))

	# Attach to active renderer (if exists)
	if active_renderer:
		active_renderer.attach_to_entity(entity)


## Unregister destroyed entity
func unregister_entity(entity: IRenderable) -> void:
	var entity_id: String = entity.get_entity_id()

	if not entity_id in _entity_registry:
		push_warning("Entity not registered: %s" % entity_id)
		return

	# Detach from renderer
	if active_renderer:
		active_renderer.detach_from_entity(entity)

	# Disconnect signals
	if entity.state_changed.is_connected(_on_entity_state_changed):
		entity.state_changed.disconnect(_on_entity_state_changed)

	if entity.animation_requested.is_connected(_on_entity_animation_requested):
		entity.animation_requested.disconnect(_on_entity_animation_requested)

	if entity.tree_exiting.is_connected(_on_entity_destroyed):
		entity.tree_exiting.disconnect(_on_entity_destroyed)

	# Remove from registry
	_entity_registry.erase(entity_id)


## Signal handler: Entity state changed
func _on_entity_state_changed(state: EntityState, entity_id: String) -> void:
	if not active_renderer:
		return

	active_renderer.update_state(entity_id, state)

## Signal handler: Entity requested animation
func _on_entity_animation_requested(request: AnimationRequest, entity_id: String) -> void:
	if not active_renderer:
		return

	active_renderer.play_animation(entity_id, request)

## Signal handler: Entity being destroyed
func _on_entity_destroyed(entity: IRenderable) -> void:
	unregister_entity(entity)

## Render all projectiles in one batched pass (no per-projectile entities).
func update_projectiles(projectiles: Array) -> void:
	if active_renderer:
		active_renderer.update_projectiles(projectiles)

## Get registered entity count (for debugging)
func get_entity_count() -> int:
	return _entity_registry.size()

## Get all registered entity IDs (for debugging)
func get_registered_entity_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_entity_registry.keys())
	return ids

## Hot-reload active renderer (refresh all visuals)
func refresh_visuals() -> void:
	if not active_renderer:
		push_warning("Cannot refresh: no active renderer")
		return

	# Detach and reattach all entities
	for entity_id in _entity_registry:
		var entity: IRenderable = _entity_registry[entity_id]
		if is_instance_valid(entity):
			active_renderer.detach_from_entity(entity)
			active_renderer.attach_to_entity(entity)
