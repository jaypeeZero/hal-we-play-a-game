extends BattlefieldObject
class_name TerrainObject

# Terrain type - persistent environmental objects on the battlefield
# Terrain never self-destructs and can affect creatures/players
# Uses generic object_entered signal - subclasses decide what to do with each object type

signal object_entered(object: BattlefieldObject)
signal object_exited(object: BattlefieldObject)

var terrain_type: String = ""
var collision_area: Area2D

func initialize(data: Dictionary, target_pos: Vector2) -> void:
	super.initialize(data, target_pos)

	# Handle terrain_type from data
	terrain_type = data.get("terrain_type", "generic")

	# Set visual type based on terrain data
	visual_type = "terrain_%s" % terrain_type
	entity_id = "terrain_%s" % _generate_unique_id()

	target_position = target_pos
	global_position = target_pos

	_setup_collision()
	_setup_visual(data)
	add_to_group("terrain")

	# Emit initial state (terrain is static, only emits once)
	_emit_terrain_state()

func _setup_collision() -> void:
	collision_area = Area2D.new()
	collision_area.name = "TerrainCollision"
	add_child(collision_area)

	# Terrain exists on TERRAIN layer and detects objects on CREATURE layer
	collision_area.collision_layer = CollisionLayers.TERRAIN_COLLISION_LAYER
	collision_area.collision_mask = CollisionLayers.TERRAIN_COLLISION_MASK

	var collision_shape: CollisionShape2D = CollisionShape2D.new()
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = get_collision_radius_for_visual_type()
	collision_shape.shape = shape
	collision_area.add_child(collision_shape)

	collision_area.area_entered.connect(_on_area_entered)
	collision_area.area_exited.connect(_on_area_exited)

func _on_area_entered(area: Area2D) -> void:
	if area.name != "HitBox":
		return

	var parent: Node = area.get_parent()

	# Interact with BattlefieldObjects (creatures, projectiles, effects) and Players
	if parent is BattlefieldObject:
		_on_object_entered(parent as BattlefieldObject)
		object_entered.emit(parent as BattlefieldObject)
	elif parent is PlayerCharacter:
		_on_player_entered(parent as PlayerCharacter)

func _on_area_exited(area: Area2D) -> void:
	if area.name != "HitBox":
		return

	var parent: Node = area.get_parent()

	if parent is BattlefieldObject:
		_on_object_exited(parent as BattlefieldObject)
		object_exited.emit(parent as BattlefieldObject)

func _setup_visual(data: Dictionary) -> void:
	# TODO: Remove this method in Phase 5 (EmojiRenderer) - visuals should be handled by renderer
	# Override in subclasses for specific visual representations (temporary during transition)
	pass

func _on_object_entered(object: BattlefieldObject) -> void:
	# Override in subclasses for specific behavior
	pass

func _on_object_exited(object: BattlefieldObject) -> void:
	# Override in subclasses for specific behavior
	pass

func _on_player_entered(player: PlayerCharacter) -> void:
	# Override in subclasses for specific behavior with players
	pass

## Get collision radius from visual data (size-based system)
func get_collision_radius() -> float:
	return get_collision_radius_for_visual_type()

## Emit terrain state (static, no movement)
func _emit_terrain_state() -> void:
	var state = EntityState.new()
	state.add_flag(EntityStateFlags.IDLE)
	state_changed.emit(state)
