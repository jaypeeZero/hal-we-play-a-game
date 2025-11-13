extends TerrainObject
class_name Chasm

# Chasm is a dangerous hole that blocks all movement and removes creatures that enter

func _setup_visual(data: Dictionary) -> void:
	# Visuals handled by renderer (supports both emoji and shape rendering)
	_setup_blocking_collision()

func _setup_blocking_collision() -> void:
	# Create StaticBody2D to physically block movement (players and creatures)
	var static_body: StaticBody2D = StaticBody2D.new()
	static_body.name = "ChasmBlocker"
	add_child(static_body)

	# Set collision layer for pathfinding detection
	static_body.collision_layer = CollisionLayers.TERRAIN_COLLISION_LAYER
	static_body.collision_mask = 0  # Static body doesn't need to detect anything

	# Add collision shape
	var collision_shape: CollisionShape2D = CollisionShape2D.new()
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = get_collision_radius_for_visual_type()
	collision_shape.shape = shape
	static_body.add_child(collision_shape)

func _on_object_entered(object: BattlefieldObject) -> void:
	# Creatures that somehow enter the chasm are removed
	# (Physical blocking should prevent this in most cases)
	if object is CreatureObject:
		if object and is_instance_valid(object):
			object.queue_free()

func _on_player_entered(player: PlayerCharacter) -> void:
	# Players are blocked by StaticBody2D - no action needed
	pass
