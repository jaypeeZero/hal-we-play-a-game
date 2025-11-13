class_name TerrainGenerator
extends RefCounted

## Generates randomized terrain layouts for the battlefield
## Focuses on natural-looking placement with mostly open space

const TerrainData = preload("res://scripts/core/data/terrain_data.gd")

# Generation parameters
const TREE_CLUSTER_MIN_SIZE = 2
const TREE_CLUSTER_MAX_SIZE = 5
const TREE_CLUSTER_SPREAD = 40.0  # How spread out trees in a cluster are
const BOULDER_MIN_SPACING = 80.0  # Minimum distance between boulders
const CHASM_MIN_SPACING = 150.0   # Minimum distance between chasms
const CHASM_MIN_RADIUS = 20.0     # Smallest chasm size
const CHASM_MAX_RADIUS = 45.0     # Largest chasm size
const OBSTACLE_EDGE_MARGIN = 60.0 # Stay away from edges
const PLAYER_CLEAR_RADIUS = 150.0 # Clear area around player spawns

# Player spawn positions (hardcoded from battlefield_game)
const PLAYER1_SPAWN = Vector2(200, 360)
const PLAYER2_SPAWN = Vector2(1080, 360)

class TerrainConfig:
	var tree_cluster_count: int = 3
	var boulder_count: int = 4
	var chasm_count: int = 2
	var tree_types: Array = ["tree_evergreen", "tree_deciduous"]

	func _init(p_tree_clusters: int = 3, p_boulders: int = 4, p_chasms: int = 2):
		tree_cluster_count = p_tree_clusters
		boulder_count = p_boulders
		chasm_count = p_chasms

class TerrainPlacement:
	var terrain_type: String
	var position: Vector2
	var radius: float = 0.0  # Optional: for variable-sized obstacles (chasms)

	func _init(p_type: String, p_position: Vector2, p_radius: float = 0.0):
		terrain_type = p_type
		position = p_position
		radius = p_radius

var battlefield_width: float
var battlefield_height: float
var placed_positions: Array[Vector2] = []
var rng: RandomNumberGenerator

func _init(p_width: float, p_height: float, seed_value: int = -1):
	battlefield_width = p_width
	battlefield_height = p_height
	rng = RandomNumberGenerator.new()
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()

func generate(config: TerrainConfig) -> Array[TerrainPlacement]:
	placed_positions.clear()
	var placements: Array[TerrainPlacement] = []

	# Generate tree clusters
	for i in range(config.tree_cluster_count):
		var cluster = _generate_tree_cluster(config.tree_types)
		placements.append_array(cluster)

	# Generate scattered boulders
	for i in range(config.boulder_count):
		var boulder = _generate_boulder()
		if boulder:
			placements.append(boulder)

	# Generate chasms (most dangerous, least frequent)
	for i in range(config.chasm_count):
		var chasm = _generate_chasm()
		if chasm:
			placements.append(chasm)

	return placements

func _generate_tree_cluster(tree_types: Array) -> Array[TerrainPlacement]:
	var cluster: Array[TerrainPlacement] = []

	# Find a valid cluster center
	var center = _find_valid_position(OBSTACLE_EDGE_MARGIN, 0.0)
	if center == Vector2.ZERO:
		return cluster  # Couldn't find valid position

	# Generate cluster
	var cluster_size = rng.randi_range(TREE_CLUSTER_MIN_SIZE, TREE_CLUSTER_MAX_SIZE)

	for i in range(cluster_size):
		# Offset from center with some randomness
		var angle = rng.randf_range(0, TAU)
		var distance = rng.randf_range(0, TREE_CLUSTER_SPREAD)
		var offset = Vector2(cos(angle), sin(angle)) * distance
		var tree_pos = center + offset

		# Validate position
		if _is_position_valid(tree_pos, OBSTACLE_EDGE_MARGIN, 0.0):
			var tree_type = tree_types[rng.randi() % tree_types.size()]
			cluster.append(TerrainPlacement.new(tree_type, tree_pos))
			placed_positions.append(tree_pos)

	return cluster

func _generate_boulder() -> TerrainPlacement:
	var pos = _find_valid_position(OBSTACLE_EDGE_MARGIN, BOULDER_MIN_SPACING)
	if pos == Vector2.ZERO:
		return null

	placed_positions.append(pos)
	return TerrainPlacement.new("boulder", pos)

func _generate_chasm() -> TerrainPlacement:
	var pos = _find_valid_position(OBSTACLE_EDGE_MARGIN, CHASM_MIN_SPACING)
	if pos == Vector2.ZERO:
		return null

	# Generate random radius for this chasm
	var radius = rng.randf_range(CHASM_MIN_RADIUS, CHASM_MAX_RADIUS)

	placed_positions.append(pos)
	return TerrainPlacement.new("chasm", pos, radius)

func _find_valid_position(edge_margin: float, min_spacing: float, max_attempts: int = 50) -> Vector2:
	for attempt in range(max_attempts):
		var x = rng.randf_range(edge_margin, battlefield_width - edge_margin)
		var y = rng.randf_range(edge_margin, battlefield_height - edge_margin)
		var pos = Vector2(x, y)

		if _is_position_valid(pos, edge_margin, min_spacing):
			return pos

	return Vector2.ZERO  # Failed to find valid position

func _is_position_valid(pos: Vector2, edge_margin: float, min_spacing: float) -> bool:
	# Check bounds
	if pos.x < edge_margin or pos.x > battlefield_width - edge_margin:
		return false
	if pos.y < edge_margin or pos.y > battlefield_height - edge_margin:
		return false

	# Check player spawn clearance
	if pos.distance_to(PLAYER1_SPAWN) < PLAYER_CLEAR_RADIUS:
		return false
	if pos.distance_to(PLAYER2_SPAWN) < PLAYER_CLEAR_RADIUS:
		return false

	# Check spacing from other obstacles
	if min_spacing > 0:
		for placed_pos in placed_positions:
			if pos.distance_to(placed_pos) < min_spacing:
				return false

	return true
