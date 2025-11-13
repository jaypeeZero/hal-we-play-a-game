extends Control

const BattlefieldGameScene = preload("res://scenes/battlefield_game.tscn")
const HandUI = preload("res://scripts/ui/hand/hand_ui.gd")
const BattlefieldBorder = preload("res://scripts/ui/battlefield_border.gd")

const BATTLEFIELD_WIDTH = 1280.0
const BATTLEFIELD_HEIGHT = 720.0

var viewport_container: SubViewportContainer
var subviewport: SubViewport
var battlefield_game: Node2D
var hand_uis: Array[HandUI] = []

func _ready() -> void:
	_setup_viewport()
	# Wait one frame for battlefield_game to initialize
	await get_tree().process_frame
	_setup_ui_layer()

func _setup_viewport() -> void:
	# Create ViewportContainer to hold the game viewport
	viewport_container = SubViewportContainer.new()
	viewport_container.size = Vector2(BATTLEFIELD_WIDTH, BATTLEFIELD_HEIGHT)
	viewport_container.position = Vector2.ZERO
	viewport_container.stretch = true
	viewport_container.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(viewport_container)

	# Create SubViewport (the actual render target for the game)
	subviewport = SubViewport.new()
	subviewport.size = Vector2(BATTLEFIELD_WIDTH, BATTLEFIELD_HEIGHT)
	subviewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	subviewport.handle_input_locally = false  # We'll transform and push input manually
	viewport_container.add_child(subviewport)

	# Instantiate the battlefield game into the viewport
	battlefield_game = BattlefieldGameScene.instantiate()
	subviewport.add_child(battlefield_game)

func _setup_ui_layer() -> void:
	# Add battlefield border frame directly to root (no CanvasLayer)
	var border: BattlefieldBorder = BattlefieldBorder.new()
	border.size = Vector2(BATTLEFIELD_WIDTH, BATTLEFIELD_HEIGHT)
	border.position = Vector2.ZERO
	border.z_index = 100  # Render above viewport
	add_child(border)

	# Get references we need from the game
	var input_handler: InputHandler = _get_game_input_handler()
	var players: Array = _get_game_players()
	var player_configs: Array = _get_game_player_configs()

	# Create Hand UI for each player (directly as children, no CanvasLayer)
	for i: int in range(players.size()):
		var player: PlayerCharacter = players[i] as PlayerCharacter
		var hand_ui: HandUI = HandUI.new()
		hand_ui.z_index = 100  # Same layer as border
		hand_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Don't block mouse
		add_child(hand_ui)

		var config: Dictionary = player_configs[i]
		var keybinds: Array[String] = []
		keybinds.assign(input_handler.player_configs[i].hand_key_labels as Array)
		hand_ui.initialize(player.hand, config.hand_ui_left_side as bool, keybinds, i, input_handler, Vector2(BATTLEFIELD_WIDTH, BATTLEFIELD_HEIGHT))
		hand_uis.append(hand_ui)

	# Connect to game end to clean up UI
	battlefield_game.tree_exiting.connect(_on_game_ending)

func _input(event: InputEvent) -> void:
	# Transform input events for the SubViewport
	if event is InputEventMouse:
		var mouse_event: InputEventMouse = event.duplicate() as InputEventMouse

		# Get mouse position relative to the viewport container
		var local_pos: Vector2 = viewport_container.get_local_mouse_position()

		# Check if mouse is within viewport bounds
		if local_pos.x >= 0 and local_pos.x <= BATTLEFIELD_WIDTH and \
		   local_pos.y >= 0 and local_pos.y <= BATTLEFIELD_HEIGHT:
			mouse_event.position = local_pos
			subviewport.push_input(mouse_event)
	elif event is InputEventKey:
		# Pass keyboard events directly to the viewport
		subviewport.push_input(event)

func _on_game_ending() -> void:
	# Clean up UI when game ends
	queue_free()

# Helper methods to access battlefield_game internals
func _get_game_input_handler() -> InputHandler:
	return battlefield_game.get("input_handler") as InputHandler

func _get_game_players() -> Array:
	return battlefield_game.get("players") as Array

func _get_game_player_configs() -> Array:
	return battlefield_game.get("player_configs") as Array
