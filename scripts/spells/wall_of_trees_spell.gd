extends EffectSpell
class_name WallOfTreesSpell

# Spawns a line of 5 trees perpendicular to cast direction
# (Will be changed to blob formation later)

const SPAWN_COUNT = 5
const TREE_SPACING = 35.0

func resolve(caster: Node2D, target_pos: Vector2, data: Dictionary, scene_root: Node2D) -> Node2D:
	var entity_class: Variant = data.get("entity_class")
	if not entity_class:
		push_error("WallOfTreesSpell: No entity_class provided in data")
		return null

	var positions: Array = _calculate_line_positions(caster.global_position, target_pos)
	var first_tree: Node2D = null

	for pos: Vector2 in positions:
		@warning_ignore("unsafe_method_access")
		var tree: Node2D = entity_class.new()
		scene_root.add_child(tree)
		tree.global_position = pos
		@warning_ignore("unsafe_method_access")
		tree.initialize(data, pos)

		# Register with VisualBridge (must be in scene tree first)
		if tree is IRenderable:
			VisualBridgeAutoload.register_entity(tree as IRenderable)

		if not first_tree:
			first_tree = tree

	return first_tree

func _calculate_line_positions(caster_pos: Vector2, target_pos: Vector2) -> Array:
	var cast_dir: Vector2 = (target_pos - caster_pos).normalized()
	var perpendicular: Vector2 = Vector2(-cast_dir.y, cast_dir.x)
	var positions: Array = []

	for i: int in range(SPAWN_COUNT):
		var offset: float = (i - (SPAWN_COUNT - 1) / 2.0) * TREE_SPACING
		positions.append(target_pos + perpendicular * offset)

	return positions
