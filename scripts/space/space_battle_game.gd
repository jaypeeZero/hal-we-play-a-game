class_name SpaceBattleGame
extends Node2D

## Main orchestrator for space combat game
## Manages ships, spawning, and game flow

signal game_started()
signal game_ended(winner: int)
signal ship_spawned(ship_id: String)

# All active ships
var _ships: Array[ShipObject] = []

# Pending spawn (waiting for mouse click)
var _pending_spawn: Dictionary = {}

# Battlefield bounds
var _battlefield_size: Vector2 = Vector2(1920, 1080)

# Target update timer (ships need to know about each other)
var _target_update_timer: float = 0.0
const TARGET_UPDATE_INTERVAL: float = 0.5  # Update every 0.5 seconds

func _ready() -> void:
	# Initialize game
	_setup_input_actions()
	game_started.emit()

	# Log game start
	if BattleEventLoggerAutoload.logger:
		BattleEventLoggerAutoload.logger.log_custom("game_started", {"mode": "space_combat"})

## Setup input actions if they don't exist
func _setup_input_actions() -> void:
	# Spawn actions
	_ensure_action("spawn_fighter", KEY_1)
	_ensure_action("spawn_corvette", KEY_2)
	_ensure_action("spawn_capital", KEY_3)
	_ensure_action("spawn_enemy_fighter", KEY_4)
	_ensure_action("spawn_enemy_corvette", KEY_5)
	_ensure_action("spawn_enemy_capital", KEY_6)

func _ensure_action(action_name: String, key: int) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
		var event = InputEventKey.new()
		event.keycode = key
		InputMap.action_add_event(action_name, event)

## Process updates
func _process(delta: float) -> void:
	# Update target information for all ships
	_target_update_timer += delta
	if _target_update_timer >= TARGET_UPDATE_INTERVAL:
		_target_update_timer = 0.0
		_update_ship_targets()

## Update all ships with current target list
func _update_ship_targets() -> void:
	# Build array of ship data dictionaries
	var ship_data_array: Array = []
	for ship in _ships:
		ship_data_array.append(ship.get_ship_data())

	# Give each ship the target list
	for ship in _ships:
		ship.set_targets(ship_data_array)

## Handle input for spawning
func _input(event: InputEvent) -> void:
	# Spawn requests
	if event.is_action_pressed("spawn_fighter"):
		_request_spawn("fighter", 3, 0)
	elif event.is_action_pressed("spawn_corvette"):
		_request_spawn("corvette", 1, 0)
	elif event.is_action_pressed("spawn_capital"):
		_request_spawn("capital", 1, 0)
	elif event.is_action_pressed("spawn_enemy_fighter"):
		_request_spawn("fighter", 3, 1)
	elif event.is_action_pressed("spawn_enemy_corvette"):
		_request_spawn("corvette", 1, 1)
	elif event.is_action_pressed("spawn_enemy_capital"):
		_request_spawn("capital", 1, 1)

	# Mouse click to confirm spawn
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not _pending_spawn.is_empty():
			_execute_spawn(get_global_mouse_position())

## Request a spawn (waits for mouse click)
func _request_spawn(ship_type: String, count: int, team: int) -> void:
	_pending_spawn = {
		"type": ship_type,
		"count": count,
		"team": team
	}

	print("Click to spawn %d %s(s) for team %d" % [count, ship_type, team])

## Execute the pending spawn at the clicked position
func _execute_spawn(spawn_position: Vector2) -> void:
	if _pending_spawn.is_empty():
		return

	var ship_type = _pending_spawn.type
	var count = _pending_spawn.count
	var team = _pending_spawn.team

	# Spawn ships with slight offset
	for i in range(count):
		var offset = Vector2(
			randf_range(-50, 50),
			randf_range(-50, 50)
		)
		var ship_position = spawn_position + offset

		# Clamp to battlefield bounds
		ship_position.x = clamp(ship_position.x, 50, _battlefield_size.x - 50)
		ship_position.y = clamp(ship_position.y, 50, _battlefield_size.y - 50)

		spawn_ship(ship_type, team, ship_position)

	# Clear pending spawn
	_pending_spawn = {}

## Spawn a ship at the given position
func spawn_ship(ship_type: String, team: int, position: Vector2) -> ShipObject:
	# Create ship data
	var ship_data = ShipData.create_ship_instance(ship_type, team, position)
	if ship_data.is_empty():
		push_error("Failed to create ship data for type: " + ship_type)
		return null

	# Create ship object
	var ship = ShipObject.new()
	ship.initialize(ship_data)

	# Connect signals
	ship.weapon_fired.connect(_on_ship_weapon_fired)
	ship.ship_destroyed.connect(_on_ship_destroyed.bind(ship))

	# Add to scene and tracking
	add_child(ship)
	_ships.append(ship)

	# Emit signal
	ship_spawned.emit(ship_data.ship_id)

	# Log event
	if BattleEventLoggerAutoload.logger:
		BattleEventLoggerAutoload.logger.log_custom("ship_spawned", {
			"ship_id": ship_data.ship_id,
			"type": ship_type,
			"team": team,
			"position": position
		})

	return ship

## Handle weapon fire from ship
func _on_ship_weapon_fired(weapon_id: String, fire_command: Dictionary) -> void:
	# Add human reaction delay
	if fire_command.has("delay") and fire_command.delay > 0:
		await get_tree().create_timer(fire_command.delay).timeout

	# Create projectile
	var projectile = SpaceProjectile.new()
	projectile.initialize(fire_command)

	add_child(projectile)

	# Log event
	if BattleEventLoggerAutoload.logger:
		BattleEventLoggerAutoload.logger.log_custom("weapon_fired", {
			"ship_id": fire_command.ship_id,
			"weapon_id": weapon_id,
			"target_id": fire_command.target_id
		})

## Handle ship destruction
func _on_ship_destroyed(ship: ShipObject) -> void:
	_ships.erase(ship)

	# Log event
	if BattleEventLoggerAutoload.logger:
		BattleEventLoggerAutoload.logger.log_custom("ship_destroyed", {
			"ship_id": ship.get_entity_id()
		})

	# Check win condition
	_check_win_condition()

## Check if either team has won
func _check_win_condition() -> void:
	var player_ships = 0
	var enemy_ships = 0

	for ship in _ships:
		var data = ship.get_ship_data()
		if data.team == 0:
			player_ships += 1
		else:
			enemy_ships += 1

	if player_ships == 0 and enemy_ships > 0:
		_end_game(1)  # Enemy wins
	elif enemy_ships == 0 and player_ships > 0:
		_end_game(0)  # Player wins

## End the game
func _end_game(winner: int) -> void:
	game_ended.emit(winner)

	if BattleEventLoggerAutoload.logger:
		BattleEventLoggerAutoload.logger.log_custom("game_ended", {"winner": winner})

	print("Game Over! Team %d wins!" % winner)

## Get all ships (for debugging)
func get_ships() -> Array[ShipObject]:
	return _ships

## Get ship by ID
func get_ship_by_id(ship_id: String) -> ShipObject:
	for ship in _ships:
		if ship.get_entity_id() == ship_id:
			return ship
	return null

## Clear all ships (for testing)
func clear_ships() -> void:
	for ship in _ships:
		ship.queue_free()
	_ships.clear()
