extends GutTest

const BattlefieldGame = preload("res://scripts/battlefield/battlefield_game.gd")
const TerrainData = preload("res://scripts/core/data/terrain_data.gd")
const TreeTerrain = preload("res://scripts/entities/terrain/tree_terrain.gd")

var battlefield: Node2D

func before_each():
	battlefield = BattlefieldGame.new()
	add_child_autofree(battlefield)

func test_battlefield_can_spawn_terrain():
	# Test helper method for spawning terrain (now uses string IDs)
	var terrain = battlefield._spawn_terrain_tree("tree_evergreen", Vector2(100, 100))

	assert_not_null(terrain)
	assert_true(terrain is TreeTerrain)
	assert_eq(terrain.global_position, Vector2(100, 100))

func test_battlefield_border_trees_exist():
	# After calling a border setup method, trees should exist
	battlefield._setup_border_trees()

	# Count tree terrain in scene
	var tree_count = 0
	for child in battlefield.get_children():
		if child is TreeTerrain:
			tree_count += 1

	assert_gt(tree_count, 0, "Border should have trees")

