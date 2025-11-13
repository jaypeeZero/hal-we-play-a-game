extends GutTest

const TerrainGenerator = preload("res://scripts/battlefield/terrain_generator.gd")

const BATTLEFIELD_WIDTH = 1280.0
const BATTLEFIELD_HEIGHT = 720.0

var generator: TerrainGenerator

func before_each():
	generator = TerrainGenerator.new(BATTLEFIELD_WIDTH, BATTLEFIELD_HEIGHT, 12345)

func test_generator_creates_terrain_placements():
	var config: TerrainGenerator.TerrainConfig = TerrainGenerator.TerrainConfig.new(2, 3, 1)
	var placements: Array = generator.generate(config)

	assert_gt(placements.size(), 0, "Should generate terrain placements")

func test_generator_respects_player_clear_zones():
	var config: TerrainGenerator.TerrainConfig = TerrainGenerator.TerrainConfig.new(10, 10, 10)
	var placements: Array = generator.generate(config)

	var player1_spawn: Vector2 = TerrainGenerator.PLAYER1_SPAWN
	var player2_spawn: Vector2 = TerrainGenerator.PLAYER2_SPAWN
	var clear_radius: float = TerrainGenerator.PLAYER_CLEAR_RADIUS

	for placement in placements:
		var terrain_placement: TerrainGenerator.TerrainPlacement = placement as TerrainGenerator.TerrainPlacement
		var distance_to_p1: float = terrain_placement.position.distance_to(player1_spawn)
		var distance_to_p2: float = terrain_placement.position.distance_to(player2_spawn)

		assert_gt(distance_to_p1, clear_radius, "Terrain should not spawn in player 1 clear zone")
		assert_gt(distance_to_p2, clear_radius, "Terrain should not spawn in player 2 clear zone")

func test_generator_respects_battlefield_bounds():
	var config: TerrainGenerator.TerrainConfig = TerrainGenerator.TerrainConfig.new(10, 10, 10)
	var placements: Array = generator.generate(config)

	var margin: float = TerrainGenerator.OBSTACLE_EDGE_MARGIN

	for placement in placements:
		var terrain_placement: TerrainGenerator.TerrainPlacement = placement as TerrainGenerator.TerrainPlacement
		var pos: Vector2 = terrain_placement.position

		assert_gt(pos.x, margin, "X position should be within bounds")
		assert_lt(pos.x, BATTLEFIELD_WIDTH - margin, "X position should be within bounds")
		assert_gt(pos.y, margin, "Y position should be within bounds")
		assert_lt(pos.y, BATTLEFIELD_HEIGHT - margin, "Y position should be within bounds")

func test_generator_creates_tree_clusters():
	var config: TerrainGenerator.TerrainConfig = TerrainGenerator.TerrainConfig.new(3, 0, 0)
	var placements: Array = generator.generate(config)

	# Count trees
	var tree_count: int = 0
	for placement in placements:
		var terrain_placement: TerrainGenerator.TerrainPlacement = placement as TerrainGenerator.TerrainPlacement
		if terrain_placement.terrain_type in ["tree_evergreen", "tree_deciduous"]:
			tree_count += 1

	# Should have at least some trees (clusters generate 2-5 trees each)
	assert_gt(tree_count, 0, "Should generate trees")

func test_generator_creates_boulders():
	var config: TerrainGenerator.TerrainConfig = TerrainGenerator.TerrainConfig.new(0, 5, 0)
	var placements: Array = generator.generate(config)

	# Count boulders
	var boulder_count: int = 0
	for placement in placements:
		var terrain_placement: TerrainGenerator.TerrainPlacement = placement as TerrainGenerator.TerrainPlacement
		if terrain_placement.terrain_type == "boulder":
			boulder_count += 1

	assert_gt(boulder_count, 0, "Should generate boulders")

func test_generator_creates_chasms():
	var config: TerrainGenerator.TerrainConfig = TerrainGenerator.TerrainConfig.new(0, 0, 3)
	var placements: Array = generator.generate(config)

	# Count chasms
	var chasm_count: int = 0
	for placement in placements:
		var terrain_placement: TerrainGenerator.TerrainPlacement = placement as TerrainGenerator.TerrainPlacement
		if terrain_placement.terrain_type == "chasm":
			chasm_count += 1

	assert_gt(chasm_count, 0, "Should generate chasms")

func test_generator_uses_seed_for_consistency():
	var gen1: TerrainGenerator = TerrainGenerator.new(BATTLEFIELD_WIDTH, BATTLEFIELD_HEIGHT, 999)
	var gen2: TerrainGenerator = TerrainGenerator.new(BATTLEFIELD_WIDTH, BATTLEFIELD_HEIGHT, 999)

	var config: TerrainGenerator.TerrainConfig = TerrainGenerator.TerrainConfig.new(2, 2, 1)

	var placements1: Array = gen1.generate(config)
	var placements2: Array = gen2.generate(config)

	assert_eq(placements1.size(), placements2.size(), "Same seed should generate same number of placements")

	# Check positions match (allowing for floating point precision)
	for i in range(placements1.size()):
		var p1: TerrainGenerator.TerrainPlacement = placements1[i] as TerrainGenerator.TerrainPlacement
		var p2: TerrainGenerator.TerrainPlacement = placements2[i] as TerrainGenerator.TerrainPlacement

		assert_almost_eq(p1.position.x, p2.position.x, 0.01, "Same seed should generate same positions")
		assert_almost_eq(p1.position.y, p2.position.y, 0.01, "Same seed should generate same positions")
		assert_eq(p1.terrain_type, p2.terrain_type, "Same seed should generate same terrain types")

func test_generator_produces_variety():
	var config: TerrainGenerator.TerrainConfig = TerrainGenerator.TerrainConfig.new(5, 5, 3)
	var placements: Array = generator.generate(config)

	var terrain_types_found: Dictionary = {}

	for placement in placements:
		var terrain_placement: TerrainGenerator.TerrainPlacement = placement as TerrainGenerator.TerrainPlacement
		terrain_types_found[terrain_placement.terrain_type] = true

	# Should have multiple terrain types
	assert_gt(terrain_types_found.size(), 1, "Should generate variety of terrain types")

func test_config_can_set_custom_values():
	var config: TerrainGenerator.TerrainConfig = TerrainGenerator.TerrainConfig.new(1, 2, 3)

	assert_eq(config.tree_cluster_count, 1)
	assert_eq(config.boulder_count, 2)
	assert_eq(config.chasm_count, 3)

func test_generator_handles_empty_config():
	var config: TerrainGenerator.TerrainConfig = TerrainGenerator.TerrainConfig.new(0, 0, 0)
	var placements: Array = generator.generate(config)

	assert_eq(placements.size(), 0, "Empty config should generate no terrain")

func test_boulders_maintain_minimum_spacing():
	var config: TerrainGenerator.TerrainConfig = TerrainGenerator.TerrainConfig.new(0, 10, 0)
	var placements: Array = generator.generate(config)

	var boulder_positions: Array[Vector2] = []

	for placement in placements:
		var terrain_placement: TerrainGenerator.TerrainPlacement = placement as TerrainGenerator.TerrainPlacement
		if terrain_placement.terrain_type == "boulder":
			boulder_positions.append(terrain_placement.position)

	# Check spacing between boulders
	for i in range(boulder_positions.size()):
		for j in range(i + 1, boulder_positions.size()):
			var distance: float = boulder_positions[i].distance_to(boulder_positions[j])
			assert_gt(distance, TerrainGenerator.BOULDER_MIN_SPACING,
				"Boulders should maintain minimum spacing")

func test_chasms_maintain_minimum_spacing():
	var config: TerrainGenerator.TerrainConfig = TerrainGenerator.TerrainConfig.new(0, 0, 5)
	var placements: Array = generator.generate(config)

	var chasm_positions: Array[Vector2] = []

	for placement in placements:
		var terrain_placement: TerrainGenerator.TerrainPlacement = placement as TerrainGenerator.TerrainPlacement
		if terrain_placement.terrain_type == "chasm":
			chasm_positions.append(terrain_placement.position)

	# Check spacing between chasms
	for i in range(chasm_positions.size()):
		for j in range(i + 1, chasm_positions.size()):
			var distance: float = chasm_positions[i].distance_to(chasm_positions[j])
			assert_gt(distance, TerrainGenerator.CHASM_MIN_SPACING,
				"Chasms should maintain minimum spacing")
