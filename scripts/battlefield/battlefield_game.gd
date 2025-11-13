extends Node2D

const PlayerScene = preload("res://scenes/player.tscn")
const HandUI = preload("res://scripts/ui/hand/hand_ui.gd")
const PlayerStatusBars = preload("res://scripts/ui/status_bars/player_status_bars.gd")
const CastingRadiusVisual = preload("res://scripts/ui/visuals/casting_radius_visual.gd")
const TreeTerrain = preload("res://scripts/entities/terrain/tree_terrain.gd")
const MedallionData = preload("res://scripts/core/data/medallion_data.gd")
const EndGameScreen = preload("res://scripts/ui/menus/end_game_screen.gd")
const PauseMenuScene = preload("res://scenes/pause_menu.tscn")
const TerrainGenerator = preload("res://scripts/battlefield/terrain_generator.gd")
const TerrainData = preload("res://scripts/core/data/terrain_data.gd")

const BORDER_MARGIN = 20.0
const BATTLEFIELD_WIDTH = 1280.0
const BATTLEFIELD_HEIGHT = 720.0

var players: Array[PlayerCharacter] = []
var hand_uis: Array[HandUI] = []
var casting_radius_visuals: Array[CastingRadiusVisual] = []

# Match statistics tracking
var match_start_time: float = 0.0
var match_stats: Dictionary = {
	"player1_damage_dealt": 0.0,
	"player2_damage_dealt": 0.0,
	"player1_creatures_spawned": 0,
	"player2_creatures_spawned": 0,
	"player1_spells_cast": 0,
	"player2_spells_cast": 0
}

# Systems
var input_handler: InputHandler
var combat_system: CombatSystem
var ai_opponent_controller: AIOpponentController

var player_configs: Array[Dictionary] = [
	{
		"player_id": 1,
		"position": Vector2(200, 360),
		"emoji": "🧙",
		"hand_ui_left_side": true
	},
	{
		"player_id": 2,
		"position": Vector2(1080, 360),
		"emoji": "🧙‍♂️",
		"hand_ui_left_side": false
	}
]

# Random terrain generation
@export var enable_random_terrain: bool = true
@export var random_terrain_tree_clusters: int = 3
@export var random_terrain_boulders: int = 4
@export var random_terrain_chasms: int = 2

func _ready() -> void:
	# Initialize match tracking
	match_start_time = Time.get_ticks_msec() / 1000.0

	# Initialize systems
	input_handler = InputHandler.new()
	add_child(input_handler)

	combat_system = CombatSystem.new()
	combat_system.scene_root = self
	combat_system.entity_spawned.connect(_on_entity_spawned)
	combat_system.entity_spawned.connect(_on_entity_spawned_for_stats)
	combat_system.entity_spawned.connect(_on_entity_spawned_for_logging)
	add_child(combat_system)

	ai_opponent_controller = AIOpponentController.new()
	add_child(ai_opponent_controller)

	# Instantiate players from scene
	for config: Dictionary in player_configs:
		var player: PlayerCharacter = PlayerScene.instantiate() as PlayerCharacter
		player.player_id = config.player_id as int
		player.global_position = config.position as Vector2
		add_child(player)

		# Remove old static Sprite (EmojiRenderer will create it)
		var sprite: Label = player.get_node("Sprite") as Label
		sprite.queue_free()

		# Register with VisualBridge (must be in tree first)
		VisualBridgeAutoload.register_entity(player as IRenderable)

		players.append(player)
		player.health_component.died.connect(_on_player_died.bind(config.player_id))

		# Connect stats tracking
		player.health_component.damaged.connect(_on_player_damaged_for_stats.bind(config.player_id as int))
		player.hand.card_played.connect(_on_card_played_for_stats.bind(config.player_id as int))

		# Connect logging
		player.health_component.damaged.connect(_on_entity_damaged_for_logging.bind(player))
		player.health_component.died.connect(_on_player_died_for_logging.bind(config.player_id))
		player.mana_changed.connect(_on_player_mana_changed_for_logging.bind(config.player_id as int))
		player.hand.card_played.connect(_on_card_played_for_logging.bind(config.player_id as int))

	# Setup status bars for each player
	_setup_status_bars()

	# Setup Hand UIs (only if running standalone, not in SubViewport)
	if _is_running_standalone():
		_setup_hand_ui()

	# Setup pause menu
	var pause_menu: CanvasLayer = PauseMenuScene.instantiate()
	add_child(pause_menu)

	# Setup casting radius visuals
	_setup_casting_radius_visuals()

	# Setup border trees
	_setup_border_trees()

	# Setup random terrain (if enabled)
	if enable_random_terrain:
		_setup_random_terrain()

func _is_running_standalone() -> bool:
	# If we're in a SubViewport, the parent will be a SubViewport node
	# If standalone, we're directly in the root Window
	return get_viewport() == get_tree().root

func _setup_status_bars() -> void:
	for player: PlayerCharacter in players:
		var status_bars: PlayerStatusBars = PlayerStatusBars.new()
		player.add_child(status_bars)

		# Connect player signals to status bars
		player.health_component.health_changed.connect(func(current: float, maximum: float) -> void:
			status_bars.set_health(current, maximum))
		player.mana_changed.connect(func(_mana: float) -> void:
			status_bars.set_mana(player.mana, player.max_mana))

		# Initialize status bars with current values
		status_bars.set_health(player.health_component.health, player.health_component.max_health)
		status_bars.set_mana(player.mana, player.max_mana)

func _setup_hand_ui() -> void:
	# Create CanvasLayer for UI (renders on top)
	var ui_layer: CanvasLayer = CanvasLayer.new()
	add_child(ui_layer)

	# Create Hand UI for each player
	for i: int in range(players.size()):
		var hand_ui: HandUI = HandUI.new()
		ui_layer.add_child(hand_ui)

		var config: Dictionary = player_configs[i]
		var keybinds: Array[String] = []
		keybinds.assign(input_handler.player_configs[i].hand_key_labels as Array)
		hand_ui.initialize(players[i].hand, config.hand_ui_left_side as bool, keybinds, i, input_handler)
		hand_uis.append(hand_ui)

func _setup_casting_radius_visuals() -> void:
	# Only show casting radius for Player 1 (human player)
	# Player 2 is AI-driven and doesn't need visual feedback
	var visual: CastingRadiusVisual = CastingRadiusVisual.new()
	add_child(visual)
	visual.global_position = players[0].global_position
	casting_radius_visuals.append(visual)
	visual.show_visual()

func _process(delta: float) -> void:
	# Player 1: Human-controlled via keyboard
	input_handler.handle_movement([players[0]], delta)

	# Player 2: AI-controlled
	ai_opponent_controller.handle_movement(players[1], delta)
	ai_opponent_controller.handle_casting(players[1], players[0], combat_system, delta)

	# Update casting radius visuals
	_update_casting_radius_visuals()

func _input(event: InputEvent) -> void:
	# Toggle fullscreen with F11
	if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_F11:
		GameSettings.set_fullscreen(!GameSettings.fullscreen)
		get_tree().root.set_input_as_handled()
		return

	input_handler.handle_casting_input(event, players, combat_system)

func _on_entity_spawned(entity: Node2D) -> void:
	# Connect explosion visuals for projectiles
	if entity is ProjectileObject:
		(entity as ProjectileObject).exploded.connect(_on_projectile_exploded)

func _on_projectile_exploded(explosion_position: Vector2) -> void:
	_create_explosion_visual(explosion_position)

func _create_explosion_visual(position: Vector2) -> void:
	var explosion: ColorRect = ColorRect.new()
	explosion.size = Vector2(5, 5)
	explosion.position = Vector2(-2.5, -2.5)
	explosion.color = Color(1.0, 0.5, 0.0, 0.8) # Orange

	add_child(explosion)
	explosion.global_position = position

	# Animate explosion
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(explosion as Object, "size", Vector2(40, 40), 0.3)
	tween.tween_property(explosion as Object, "position", Vector2(-20, -20), 0.3)
	tween.tween_property(explosion as Object, "modulate:a", 0.0, 0.3)
	tween.finished.connect(func() -> void: explosion.queue_free())

func _on_player_died(player_id: int) -> void:
	var winner_id: int = 3 - player_id # If P1 died, winner is P2 (3-1=2)
	var duration: float = (Time.get_ticks_msec() / 1000.0) - match_start_time

	# Add duration to stats
	var final_stats: Dictionary = match_stats.duplicate()
	final_stats["duration"] = duration

	# Load and show end screen
	var end_screen_scene: PackedScene = load("res://scenes/end_game_screen.tscn")
	var end_screen: EndGameScreen = end_screen_scene.instantiate() as EndGameScreen
	get_tree().root.add_child(end_screen)
	end_screen.setup(winner_id, final_stats)

	queue_free() # Remove battlefield

# Stats tracking signal handlers
func _on_player_damaged_for_stats(amount: float, source_id: int, player_id: int) -> void:
	# Track damage dealt by the OTHER player (source)
	# When player 1 takes damage, player 2 dealt it (and vice versa)
	var dealer_id: int = 3 - player_id
	var stat_key: String = "player%d_damage_dealt" % dealer_id
	match_stats[stat_key] = (match_stats[stat_key] as float) + amount

func _on_card_played_for_stats(_slot: int, _medallion: Medallion, player_id: int) -> void:
	var stat_key: String = "player%d_spells_cast" % player_id
	match_stats[stat_key] = (match_stats[stat_key] as int) + 1

func _on_entity_spawned_for_stats(entity: Node2D) -> void:
	# Track creature spawns - need to identify owner
	if entity is CreatureObject:
		var creature: CreatureObject = entity as CreatureObject
		var owner_id: int = creature.owner_id
		var stat_key: String = "player%d_creatures_spawned" % owner_id
		match_stats[stat_key] = (match_stats[stat_key] as int) + 1

func _update_casting_radius_visuals() -> void:
	# Update Player 1's casting radius visual
	var player: PlayerCharacter = players[0]
	var visual: CastingRadiusVisual = casting_radius_visuals[0]

	# Update visual position to match player
	visual.global_position = player.global_position

	# Get max casting range from player's hand
	var max_range: float = _get_max_casting_range_from_hand(player.hand)
	visual.set_radius(max_range)

	# Update target position based on mouse
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	visual.set_target_position(mouse_pos, player.global_position)

func _get_max_casting_range_from_hand(hand: Hand) -> float:
	var max_range: float = 0.0

	# Iterate through all cards in hand
	for i: int in range(hand.get_card_count()):
		var medallion: Medallion = hand.get_card(i)
		if medallion:
			var medallion_data_instance: MedallionData = MedallionData.new()
			var data: Dictionary = medallion_data_instance.get_medallion(medallion.id)
			var range_val: float = data.get("casting_range", 200.0)
			max_range = max(max_range, range_val)

	return max_range if max_range > 0.0 else 400.0

func _spawn_terrain_tree(terrain_type_str: String, pos: Vector2) -> TreeTerrain:
	# Create tree terrain directly with data
	var tree: TreeTerrain = TreeTerrain.new()
	add_child(tree)
	var data: Dictionary = {
		"terrain_type": terrain_type_str,
		"collision_radius": 15.0,
		"blocks_movement": true
	}
	tree.initialize(data, pos)

	# Register with VisualBridge (must be in tree first)
	VisualBridgeAutoload.register_entity(tree as IRenderable)

	return tree

func _setup_border_trees() -> void:
	var tree_types: Array[String] = [
		"tree_evergreen",
		"tree_deciduous"
	]

	# Tree collision radius
	var tree_collision_radius: float = 15.0

	# Spacing = diameter with slight overlap for visual intermingling
	var spacing: float = tree_collision_radius * 1.8 # 15 * 1.8 = 27px (slight overlap)

	# Top edge
	var x: float = BORDER_MARGIN
	while x < BATTLEFIELD_WIDTH - BORDER_MARGIN:
		var tree_type: String = tree_types[randi() % tree_types.size()]
		_spawn_terrain_tree(tree_type, Vector2(x, BORDER_MARGIN))
		x += spacing

	# Bottom edge
	x = BORDER_MARGIN
	while x < BATTLEFIELD_WIDTH - BORDER_MARGIN:
		var tree_type: String = tree_types[randi() % tree_types.size()]
		_spawn_terrain_tree(tree_type, Vector2(x, BATTLEFIELD_HEIGHT - BORDER_MARGIN))
		x += spacing

	# Left edge (offset to avoid corner overlap)
	var y: float = BORDER_MARGIN + spacing
	while y < BATTLEFIELD_HEIGHT - BORDER_MARGIN - spacing:
		var tree_type: String = tree_types[randi() % tree_types.size()]
		_spawn_terrain_tree(tree_type, Vector2(BORDER_MARGIN, y))
		y += spacing

	# Right edge (offset to avoid corners)
	y = BORDER_MARGIN + spacing
	while y < BATTLEFIELD_HEIGHT - BORDER_MARGIN - spacing:
		var tree_type: String = tree_types[randi() % tree_types.size()]
		_spawn_terrain_tree(tree_type, Vector2(BATTLEFIELD_WIDTH - BORDER_MARGIN, y))
		y += spacing

# Logging signal handlers
func _on_entity_spawned_for_logging(entity: Node2D) -> void:
	if entity is CreatureObject:
		var creature: CreatureObject = entity as CreatureObject
		BattleEventLoggerAutoload.log_creature_spawned(
			creature.entity_id,
			creature.creature_type_name,
			creature.owner_id,
			creature.global_position
		)
		# Connect to creature's damage and death signals
		creature.health_component.damaged.connect(_on_entity_damaged_for_logging.bind(creature))
		creature.health_component.died.connect(_on_creature_died_for_logging.bind(creature))
	elif entity is ProjectileObject:
		var projectile: ProjectileObject = entity as ProjectileObject
		BattleEventLoggerAutoload.log_projectile_fired(
			projectile.entity_id,
			"unknown",
			projectile.global_position
		)
		# Connect to projectile's explosion signal if available
		if projectile.has_signal("exploded"):
			projectile.exploded.connect(_on_projectile_exploded_for_logging.bind(projectile))

func _on_entity_damaged_for_logging(amount: float, source_id: int, entity: Node) -> void:
	var victim_id: String = (entity as Node).name if entity else "unknown"

	# Try to get entity_id if it's a BattlefieldObject
	if entity is BattlefieldObject:
		victim_id = (entity as BattlefieldObject).entity_id

	BattleEventLoggerAutoload.log_damage_dealt(victim_id, "unknown", amount)

func _on_creature_died_for_logging(creature: CreatureObject) -> void:
	BattleEventLoggerAutoload.log_creature_died(creature.entity_id, creature.creature_type_name)

func _on_player_died_for_logging(player_id: int) -> void:
	BattleEventLoggerAutoload.log_player_died(player_id)

func _on_projectile_exploded_for_logging(projectile: ProjectileObject) -> void:
	BattleEventLoggerAutoload.log_event("projectile_exploded", {
		"projectile_id": projectile.entity_id,
		"position": projectile.global_position
	})

func _on_card_played_for_logging(slot: int, medallion: Variant, player_id: int) -> void:
	@warning_ignore("unsafe_method_access")
	var spell_id: String = medallion.id if medallion else "unknown"
	BattleEventLoggerAutoload.log_spell_cast(
		"player_%d" % player_id,
		"player",
		spell_id,
		Vector2.ZERO
	)

func _on_player_mana_changed_for_logging(new_mana: float, player_id: int) -> void:
	var player: PlayerCharacter = players[player_id - 1] if player_id > 0 and player_id <= players.size() else null
	if player:
		BattleEventLoggerAutoload.log_mana_changed(player_id, new_mana)

func _setup_random_terrain() -> void:
	var generator: TerrainGenerator = TerrainGenerator.new(BATTLEFIELD_WIDTH, BATTLEFIELD_HEIGHT)
	var config: TerrainGenerator.TerrainConfig = TerrainGenerator.TerrainConfig.new(
		random_terrain_tree_clusters,
		random_terrain_boulders,
		random_terrain_chasms
	)

	var placements: Array = generator.generate(config)

	for placement in placements:
		var terrain_placement: TerrainGenerator.TerrainPlacement = placement as TerrainGenerator.TerrainPlacement
		_spawn_terrain_generic(terrain_placement.terrain_type, terrain_placement.position, terrain_placement.radius)

func _spawn_terrain_generic(terrain_type_str: String, pos: Vector2, custom_radius: float = 0.0) -> Node2D:
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
			return null

	# Get terrain data and class
	var data: Dictionary = TerrainData.get_data(terrain_type)
	var terrain_class: GDScript = TerrainData.get_terrain_class(terrain_type)

	if not terrain_class:
		push_error("No terrain class found for type: %s" % terrain_type_str)
		return null

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

	# Register with VisualBridge (must be in scene tree first)
	if terrain is IRenderable:
		VisualBridgeAutoload.register_entity(terrain as IRenderable)

	return terrain
