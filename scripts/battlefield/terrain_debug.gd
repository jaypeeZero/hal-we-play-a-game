extends Node2D

## Debug scene for testing terrain generation
## Press SPACE to regenerate terrain

const TerrainData = preload("res://scripts/core/data/terrain_data.gd")
const TerrainGenerator = preload("res://scripts/battlefield/terrain_generator.gd")

const BATTLEFIELD_WIDTH = 1280.0
const BATTLEFIELD_HEIGHT = 720.0
const PLAYER1_SPAWN = Vector2(200, 360)
const PLAYER2_SPAWN = Vector2(1080, 360)

var terrain_generator: TerrainGenerator
var current_terrain: Array[Node2D] = []
var generation_count: int = 0

# UI elements
var info_label: Label

func _ready() -> void:
	_setup_background()
	_setup_player_spawn_markers()
	_setup_ui()

	# Create generator
	terrain_generator = TerrainGenerator.new(BATTLEFIELD_WIDTH, BATTLEFIELD_HEIGHT)

	# Generate initial terrain
	_generate_terrain()

func _setup_background() -> void:
	var background: ColorRect = ColorRect.new()
	background.size = Vector2(BATTLEFIELD_WIDTH, BATTLEFIELD_HEIGHT)
	background.color = Color(0.2, 0.2, 0.2)  # Dark gray
	add_child(background)

func _setup_player_spawn_markers() -> void:
	# Player 1 marker
	_create_player_marker(PLAYER1_SPAWN, "P1", Color.CYAN)

	# Player 2 marker
	_create_player_marker(PLAYER2_SPAWN, "P2", Color.ORANGE)

func _create_player_marker(pos: Vector2, label_text: String, marker_color: Color) -> void:
	# Circle marker
	var marker: ColorRect = ColorRect.new()
	marker.size = Vector2(20, 20)
	marker.position = pos - Vector2(10, 10)
	marker.color = marker_color
	marker.color.a = 0.5  # Semi-transparent
	add_child(marker)

	# Label
	var label: Label = Label.new()
	label.text = label_text
	label.position = pos + Vector2(-10, -30)
	label.add_theme_color_override("font_color", marker_color)
	add_child(label)

	# Clear radius visualization
	var clear_area: ColorRect = ColorRect.new()
	var clear_radius: float = TerrainGenerator.PLAYER_CLEAR_RADIUS
	clear_area.size = Vector2(clear_radius * 2, clear_radius * 2)
	clear_area.position = pos - Vector2(clear_radius, clear_radius)
	clear_area.color = marker_color
	clear_area.color.a = 0.1  # Very transparent
	add_child(clear_area)

func _setup_ui() -> void:
	# Info label
	info_label = Label.new()
	info_label.position = Vector2(10, 10)
	info_label.add_theme_color_override("font_color", Color.WHITE)
	add_child(info_label)
	_update_info_label()

func _update_info_label() -> void:
	var text: String = "Terrain Debug Scene (Generation #%d)\n" % generation_count
	text += "Press SPACE to regenerate\n"
	text += "Press 1-5 for different densities\n"
	text += "Terrain objects: %d" % current_terrain.size()
	info_label.text = text

func _input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed:
		var key: int = (event as InputEventKey).keycode

		match key:
			KEY_SPACE:
				_generate_terrain()
			KEY_1:
				_generate_terrain_with_config(1, 2, 1)  # Minimal
			KEY_2:
				_generate_terrain_with_config(2, 3, 1)  # Light
			KEY_3:
				_generate_terrain_with_config(3, 4, 2)  # Medium (default)
			KEY_4:
				_generate_terrain_with_config(4, 6, 3)  # Heavy
			KEY_5:
				_generate_terrain_with_config(6, 8, 4)  # Maximum

func _generate_terrain() -> void:
	# Generate with default config
	var config: TerrainGenerator.TerrainConfig = TerrainGenerator.TerrainConfig.new(3, 4, 2)
	_generate_terrain_with_config_object(config)

func _generate_terrain_with_config(tree_clusters: int, boulders: int, chasms: int) -> void:
	var config: TerrainGenerator.TerrainConfig = TerrainGenerator.TerrainConfig.new(
		tree_clusters,
		boulders,
		chasms
	)
	_generate_terrain_with_config_object(config)

func _generate_terrain_with_config_object(config: TerrainGenerator.TerrainConfig) -> void:
	# Clear existing terrain
	_clear_terrain()

	# Generate new terrain
	var placements: Array = terrain_generator.generate(config)
	generation_count += 1

	# Spawn terrain objects
	for placement in placements:
		var terrain_placement: TerrainGenerator.TerrainPlacement = placement as TerrainGenerator.TerrainPlacement
		_spawn_terrain(terrain_placement.terrain_type, terrain_placement.position, terrain_placement.radius)

	_update_info_label()

func _clear_terrain() -> void:
	for terrain in current_terrain:
		terrain.queue_free()
	current_terrain.clear()

func _spawn_terrain(terrain_type_str: String, pos: Vector2, custom_radius: float = 0.0) -> void:
	# Map string to enum
	var terrain_type: TerrainData.TerrainType
	match terrain_type_str:
		"tree_evergreen":
			terrain_type = TerrainData.TerrainType.TREE_EVERGREEN
		"tree_deciduous":
			terrain_type = TerrainData.TerrainType.TREE_DECIDUOUS
		"boulder":
			terrain_type = TerrainData.TerrainType.BOULDER
		"chasm":
			terrain_type = TerrainData.TerrainType.CHASM
		_:
			push_error("Unknown terrain type: %s" % terrain_type_str)
			return

	# Get terrain data and class
	var data: Dictionary = TerrainData.get_data(terrain_type)
	var terrain_class: GDScript = TerrainData.get_terrain_class(terrain_type)

	if not terrain_class:
		push_error("No terrain class found for type: %s" % terrain_type_str)
		return

	# Override collision radius if custom radius is provided (for variable-sized chasms)
	if custom_radius > 0.0:
		data["collision_radius"] = custom_radius

	# Create terrain object
	@warning_ignore("unsafe_method_access")
	var terrain: Node2D = terrain_class.new()
	add_child(terrain)
	terrain.global_position = pos

	# Initialize terrain with data
	@warning_ignore("unsafe_method_access")
	terrain.initialize(data, pos)

	# Register with VisualBridge
	if terrain is IRenderable:
		VisualBridgeAutoload.register_entity(terrain as IRenderable)

	current_terrain.append(terrain)
