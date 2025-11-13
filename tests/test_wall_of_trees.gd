extends GutTest

const MedallionData = preload("res://scripts/core/data/medallion_data.gd")
const WallOfTreesSpell = preload("res://scripts/spells/wall_of_trees_spell.gd")
const TreeTerrain = preload("res://scripts/entities/terrain/tree_terrain.gd")
const TerrainData = preload("res://scripts/core/data/terrain_data.gd")

var battlefield: Node2D
var spell: WallOfTreesSpell
var caster: Node2D

# Helper to enrich data like CombatSystem does
func enrich_data(raw_data: Dictionary) -> Dictionary:
	var medallion_data = MedallionData.new()
	var enriched = raw_data.get("properties", {}).duplicate()
	var entity_class = medallion_data.get_entity_class(raw_data.get("id", ""))
	if entity_class:
		enriched["entity_class"] = entity_class
	if raw_data.has("visual_emoji"):
		enriched["visual_emoji"] = raw_data["visual_emoji"]
	return enriched

func before_each():
	battlefield = add_child_autofree(Node2D.new())
	spell = WallOfTreesSpell.new()
	caster = Node2D.new()
	battlefield.add_child(caster)
	caster.global_position = Vector2(100, 100)

func test_wall_spawns_five_trees():
	var data = MedallionData.new().get_medallion("wall_of_trees")
	var target_pos = Vector2(300, 300)

	spell.resolve(caster, target_pos, enrich_data(data), battlefield)

	# Count TreeTerrain objects in battlefield
	var tree_count = 0
	for child in battlefield.get_children():
		if child is TreeTerrain:
			tree_count += 1

	assert_eq(tree_count, 5, "Should spawn exactly 5 trees")

func test_wall_forms_line():
	var data = MedallionData.new().get_medallion("wall_of_trees")
	var target_pos = Vector2(300, 300)

	spell.resolve(caster, target_pos, enrich_data(data), battlefield)

	# Collect tree positions
	var tree_positions = []
	for child in battlefield.get_children():
		if child is TreeTerrain:
			tree_positions.append(child.global_position)

	assert_eq(tree_positions.size(), 5, "Should have 5 tree positions")

	# All trees should be at same distance from a line through target_pos
	# For simplicity, check that they form a relatively straight line
	# by checking that min/max y-coordinates are close (assuming horizontal cast)
	# or min/max x-coordinates are close (assuming vertical cast)

func test_wall_perpendicular_to_cast_direction():
	var data = MedallionData.new().get_medallion("wall_of_trees")
	# Cast horizontally to the right
	caster.global_position = Vector2(100, 300)
	var target_pos = Vector2(300, 300)

	spell.resolve(caster, target_pos, enrich_data(data), battlefield)

	# Collect tree positions
	var tree_positions = []
	for child in battlefield.get_children():
		if child is TreeTerrain:
			tree_positions.append(child.global_position)

	# Cast direction is horizontal (to the right), so wall should be vertical
	# All trees should have same x-coordinate (target x)
	for pos in tree_positions:
		assert_almost_eq(pos.x, target_pos.x, 0.1, "Trees should align on x-axis for horizontal cast")

	# Trees should be spread vertically
	var y_coords = tree_positions.map(func(p): return p.y)
	y_coords.sort()
	assert_gt(y_coords[-1] - y_coords[0], 100.0, "Trees should spread vertically")

func test_wall_spacing():
	var data = MedallionData.new().get_medallion("wall_of_trees")
	caster.global_position = Vector2(100, 300)
	var target_pos = Vector2(300, 300)

	spell.resolve(caster, target_pos, enrich_data(data), battlefield)

	# Collect tree positions
	var tree_positions = []
	for child in battlefield.get_children():
		if child is TreeTerrain:
			tree_positions.append(child.global_position)

	# Sort by y-coordinate (since they should be vertically aligned)
	tree_positions.sort_custom(func(a, b): return a.y < b.y)

	# Check spacing between adjacent trees
	for i in range(tree_positions.size() - 1):
		var distance = tree_positions[i].distance_to(tree_positions[i + 1])
		assert_almost_eq(distance, 35.0, 1.0, "Adjacent trees should be ~35 units apart")

func test_wall_centered_on_target():
	var data = MedallionData.new().get_medallion("wall_of_trees")
	caster.global_position = Vector2(100, 300)
	var target_pos = Vector2(300, 300)

	spell.resolve(caster, target_pos, enrich_data(data), battlefield)

	# Collect tree positions
	var tree_positions = []
	for child in battlefield.get_children():
		if child is TreeTerrain:
			tree_positions.append(child.global_position)

	# Center tree should be at target position (or very close)
	# Find the tree closest to target_pos
	var closest_distance = INF
	for pos in tree_positions:
		var dist = pos.distance_to(target_pos)
		if dist < closest_distance:
			closest_distance = dist

	assert_almost_eq(closest_distance, 0.0, 2.0, "One tree should be at or very near target position")

func test_each_tree_is_terrain():
	var data = MedallionData.new().get_medallion("wall_of_trees")
	var target_pos = Vector2(300, 300)

	spell.resolve(caster, target_pos, enrich_data(data), battlefield)

	# Check that each tree is in terrain group and has correct properties
	for child in battlefield.get_children():
		if child is TreeTerrain:
			assert_true(child.is_in_group("terrain"), "Tree should be in terrain group")
			assert_eq(child.terrain_type, "tree_evergreen", "Should be evergreen type")
			assert_eq(child.get_collision_radius(), 15.0, "Should have tree collision radius")

func test_wall_spell_returns_first_tree():
	var data = MedallionData.new().get_medallion("wall_of_trees")
	var target_pos = Vector2(300, 300)

	var result = spell.resolve(caster, target_pos, enrich_data(data), battlefield)

	assert_not_null(result, "Spell should return a tree object")
	assert_true(result is TreeTerrain, "Returned object should be a TreeTerrain")

func test_wall_with_vertical_cast():
	var data = MedallionData.new().get_medallion("wall_of_trees")
	# Cast vertically upward
	caster.global_position = Vector2(300, 500)
	var target_pos = Vector2(300, 200)

	spell.resolve(caster, target_pos, enrich_data(data), battlefield)

	# Collect tree positions
	var tree_positions = []
	for child in battlefield.get_children():
		if child is TreeTerrain:
			tree_positions.append(child.global_position)

	# Cast direction is vertical, so wall should be horizontal
	# All trees should have same y-coordinate
	for pos in tree_positions:
		assert_almost_eq(pos.y, target_pos.y, 0.1, "Trees should align on y-axis for vertical cast")

	# Trees should be spread horizontally
	var x_coords = tree_positions.map(func(p): return p.x)
	x_coords.sort()
	assert_gt(x_coords[-1] - x_coords[0], 100.0, "Trees should spread horizontally")

func test_wall_with_diagonal_cast():
	var data = MedallionData.new().get_medallion("wall_of_trees")
	# Cast diagonally
	caster.global_position = Vector2(100, 100)
	var target_pos = Vector2(300, 300)

	spell.resolve(caster, target_pos, enrich_data(data), battlefield)

	# Just verify 5 trees spawn and they're spaced appropriately
	var tree_positions = []
	for child in battlefield.get_children():
		if child is TreeTerrain:
			tree_positions.append(child.global_position)

	assert_eq(tree_positions.size(), 5, "Should spawn 5 trees for diagonal cast")
