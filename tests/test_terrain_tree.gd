extends GutTest

const TreeTerrain = preload("res://scripts/entities/terrain/tree_terrain.gd")
const TerrainData = preload("res://scripts/core/data/terrain_data.gd")
const CreatureObject = preload("res://scripts/entities/creatures/creature_object.gd")

var battlefield: Node2D
var tree: TreeTerrain

func before_each():
	battlefield = add_child_autofree(Node2D.new())
	tree = TreeTerrain.new()
	battlefield.add_child(tree)
	var data = TerrainData.get_data(TerrainData.TerrainType.TREE_EVERGREEN)
	tree.initialize(data, Vector2(200, 200))

func test_tree_spawns_at_position():
	assert_eq(tree.global_position, Vector2(200, 200))

func test_tree_collision_radius():
	assert_eq(tree.get_collision_radius(), 15.0)

func test_tree_is_in_terrain_group():
	assert_true(tree.is_in_group("terrain"))

func test_tree_terrain_type():
	assert_eq(tree.terrain_type, "tree_evergreen")

func test_tree_collision_detection():
	# Create a mock creature
	var creature = CreatureObject.new()
	creature.name = "TestCreature"
	battlefield.add_child(creature)
	creature.global_position = Vector2(200, 200)

	# Add HitBox
	var hitbox = Area2D.new()
	hitbox.name = "HitBox"
	creature.add_child(hitbox)

	# Watch for signal
	watch_signals(tree)

	# Simulate entering tree
	tree._on_area_entered(hitbox)

	# Should emit object_entered signal
	assert_signal_emitted(tree, "object_entered")

	# Creature should NOT be deleted (unlike chasm)
	assert_true(is_instance_valid(creature), "Creature should not be deleted by tree")

func test_evergreen_terrain_data():
	var data = TerrainData.get_data(TerrainData.TerrainType.TREE_EVERGREEN)
	assert_eq(data["terrain_type"], "tree_evergreen")
	assert_eq(data["collision_radius"], 15.0)

func test_deciduous_terrain_data():
	var data = TerrainData.get_data(TerrainData.TerrainType.TREE_DECIDUOUS)
	assert_eq(data["terrain_type"], "tree_deciduous")
	assert_eq(data["collision_radius"], 15.0)

func test_deciduous_different_from_evergreen():
	var deciduous_data = TerrainData.get_data(TerrainData.TerrainType.TREE_DECIDUOUS)
	var deciduous = TreeTerrain.new()
	battlefield.add_child(deciduous)
	deciduous.initialize(deciduous_data, Vector2(300, 300))

	var evergreen_data = TerrainData.get_data(TerrainData.TerrainType.TREE_EVERGREEN)
	var evergreen = TreeTerrain.new()
	battlefield.add_child(evergreen)
	evergreen.initialize(evergreen_data, Vector2(400, 400))

	# Just verify both render with correct terrain types
	assert_eq(deciduous.terrain_type, "tree_deciduous")
	assert_eq(evergreen.terrain_type, "tree_evergreen")

func test_tree_blocks_creature_movement():
	var evergreen_data = TerrainData.get_data(TerrainData.TerrainType.TREE_EVERGREEN)
	var tree = TreeTerrain.new()
	battlefield.add_child(tree)
	tree.initialize(evergreen_data, Vector2(300, 300))

	var creature = CreatureObject.new()
	battlefield.add_child(creature)
	var creature_data = {"collision_radius": 10.0, "max_health": 50.0}
	creature.initialize(creature_data, Vector2(300, 300), null)

	# Wait for collision detection
	await get_tree().create_timer(0.1).timeout

	# Creature should be pushed out of tree center
	var distance = tree.global_position.distance_to(creature.global_position)
	assert_gte(distance, tree.get_collision_radius() - 5.0, "Creature should be pushed to edge")
