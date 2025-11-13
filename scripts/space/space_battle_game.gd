class_name SpaceBattleGame
extends Node2D

## Pure ECS orchestrator for space combat game
## Systems process data, entities are minimal wrappers for physics
## Data flows: ships[] -> Systems -> updated ships[] -> sync entities

# Preload system classes
const MovementSystem = preload("res://scripts/space/systems/movement_system.gd")
const ProjectileSystem = preload("res://scripts/space/systems/projectile_system.gd")
const CollisionSystem = preload("res://scripts/space/systems/collision_system.gd")

# Preload entity classes
const ShipEntity = preload("res://scripts/space/entities/ship_entity.gd")
const ProjectileEntity = preload("res://scripts/space/entities/projectile_entity.gd")

signal game_started()
signal game_ended(winner: int)
signal ship_spawned(ship_id: String)

# ============================================================================
# ECS DATA - Pure data arrays
# ============================================================================

var _ships: Array = []  # Array of ship_data Dictionaries
var _projectiles: Array = []  # Array of projectile_data Dictionaries

# ============================================================================
# ENTITIES - Minimal Godot nodes for physics
# ============================================================================

var _ship_entities: Dictionary = {}  # ship_id -> ShipEntity
var _projectile_entities: Dictionary = {}  # projectile_id -> ProjectileEntity

# ============================================================================
# GAME STATE
# ============================================================================

var _pending_spawn: Dictionary = {}
var _battlefield_size: Vector2 = Vector2(1920, 1080)

# Weapon update timer
var _weapon_update_timer: float = 0.0
const WEAPON_UPDATE_INTERVAL: float = 0.1

func _ready() -> void:
	_setup_input_actions()
	game_started.emit()

	if BattleEventLoggerAutoload.service:
		BattleEventLoggerAutoload.service.log_event("game_started", {"mode": "space_combat_ecs"})

## Setup input actions
func _setup_input_actions() -> void:
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

# ============================================================================
# ECS GAME LOOP - Systems process data
# ============================================================================

func _process(delta: float) -> void:
	# 1. MOVEMENT SYSTEM - Update ship positions
	_ships = MovementSystem.update_all_ships(_ships, delta)

	# 2. WEAPON SYSTEM - Generate fire commands
	_weapon_update_timer += delta
	var fire_commands = []
	if _weapon_update_timer >= WEAPON_UPDATE_INTERVAL:
		_weapon_update_timer = 0.0
		fire_commands = _process_weapons(delta)

	# 3. SPAWN PROJECTILES from fire commands
	if not fire_commands.is_empty():
		_spawn_projectiles(fire_commands)

	# 4. PROJECTILE SYSTEM - Update projectile positions
	var projectile_result = ProjectileSystem.update_all_projectiles(_projectiles, delta)
	_projectiles = projectile_result.projectiles

	# Remove expired projectiles
	for expired_id in projectile_result.expired_ids:
		_remove_projectile(expired_id)

	# 5. COLLISION SYSTEM - Detect hits and apply damage
	var collision_result = CollisionSystem.process_collisions(_ships, _projectiles)
	_ships = collision_result.ships
	_projectiles = collision_result.projectiles

	# Remove destroyed projectiles from hits
	for hit in collision_result.hits:
		_remove_projectile(hit.projectile_id)

	# 6. CHECK FOR DESTROYED SHIPS
	_cleanup_destroyed_ships()

	# 7. SYNC ENTITIES - Update Godot nodes from data
	_sync_all_entities()

	# 8. CHECK WIN CONDITION
	_check_win_condition()

## Process weapons for all ships - returns Array of fire_commands
func _process_weapons(delta: float) -> Array:
	var all_fire_commands = []

	for i in range(_ships.size()):
		var ship = _ships[i]
		if ship == null:
			continue
		if ship.status in ["disabled", "destroyed"]:
			continue

		var result = WeaponSystem.update_weapons(ship, _ships, delta)
		_ships[i] = result.ship_data  # Update ship with new weapon cooldowns
		all_fire_commands.append_array(result.fire_commands)

	return all_fire_commands

## Spawn projectiles from fire commands
func _spawn_projectiles(fire_commands: Array) -> void:
	for fire_command in fire_commands:
		# Find source ship to get team
		var source_ship = _find_ship_by_id(fire_command.ship_id)
		if source_ship.is_empty():
			continue

		var team = source_ship.team

		# Create projectile data
		var projectile_data = ProjectileSystem.create_projectile(fire_command, team)
		_projectiles.append(projectile_data)

		# Create entity
		var entity = ProjectileEntity.new()
		entity.initialize(projectile_data.projectile_id, team)
		add_child(entity)
		_projectile_entities[projectile_data.projectile_id] = entity

		# Log event
		if BattleEventLoggerAutoload.service:
			BattleEventLoggerAutoload.service.log_event("weapon_fired", {
				"ship_id": fire_command.ship_id,
				"weapon_id": fire_command.weapon_id,
				"target_id": fire_command.target_id
			})

## Find ship by ID
func _find_ship_by_id(ship_id: String) -> Dictionary:
	for ship in _ships:
		if ship.ship_id == ship_id:
			return ship
	return {}

## Cleanup destroyed ships
func _cleanup_destroyed_ships() -> void:
	var destroyed_ships = []

	for ship in _ships:
		if ship == null:
			continue
		if DamageResolver.is_ship_destroyed(ship):
			destroyed_ships.append(ship)

	for ship in destroyed_ships:
		_remove_ship(ship.ship_id)

## Remove ship and entity
func _remove_ship(ship_id: String) -> void:
	# Remove from data
	var ship = _find_ship_by_id(ship_id)
	if not ship.is_empty():
		_ships.erase(ship)

	# Remove entity
	if _ship_entities.has(ship_id):
		var entity = _ship_entities[ship_id]
		entity.queue_free()
		_ship_entities.erase(ship_id)

	# Log event
	if BattleEventLoggerAutoload.service:
		BattleEventLoggerAutoload.service.log_event("ship_destroyed", {"ship_id": ship_id})

## Remove projectile entity
func _remove_projectile(projectile_id: String) -> void:
	if _projectile_entities.has(projectile_id):
		var entity = _projectile_entities[projectile_id]
		entity.queue_free()
		_projectile_entities.erase(projectile_id)

## Sync all entities from data
func _sync_all_entities() -> void:
	# Sync ships
	for ship in _ships:
		if ship == null:
			continue
		if _ship_entities.has(ship.ship_id):
			var entity = _ship_entities[ship.ship_id]
			entity.sync_transform(ship)
			entity.emit_state(ship)

	# Sync projectiles
	for projectile in _projectiles:
		if projectile == null:
			continue
		if _projectile_entities.has(projectile.projectile_id):
			var entity = _projectile_entities[projectile.projectile_id]
			entity.sync_transform(projectile)
			entity.emit_state(projectile)

# ============================================================================
# SHIP SPAWNING
# ============================================================================

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

func _request_spawn(ship_type: String, count: int, team: int) -> void:
	_pending_spawn = {
		"type": ship_type,
		"count": count,
		"team": team
	}
	print("Click to spawn %d %s(s) for team %d" % [count, ship_type, team])

func _execute_spawn(spawn_position: Vector2) -> void:
	if _pending_spawn.is_empty():
		return

	var ship_type = _pending_spawn.type
	var count = _pending_spawn.count
	var team = _pending_spawn.team

	for i in range(count):
		var offset = Vector2(randf_range(-50, 50), randf_range(-50, 50))
		var ship_position = spawn_position + offset

		ship_position.x = clamp(ship_position.x, 50, _battlefield_size.x - 50)
		ship_position.y = clamp(ship_position.y, 50, _battlefield_size.y - 50)

		spawn_ship(ship_type, team, ship_position)

	_pending_spawn = {}

## Spawn a ship at the given position
func spawn_ship(ship_type: String, team: int, position: Vector2) -> Dictionary:
	# Create ship data
	var ship_data = ShipData.create_ship_instance(ship_type, team, position)
	if ship_data.is_empty():
		push_error("Failed to create ship data for type: " + ship_type)
		return {}

	# Add to data array
	_ships.append(ship_data)

	# Create entity
	var entity = ShipEntity.new()
	entity.initialize(ship_data.ship_id, team, ship_data.stats.size, ship_type)
	add_child(entity)
	_ship_entities[ship_data.ship_id] = entity

	# Emit signal
	ship_spawned.emit(ship_data.ship_id)

	# Log event
	if BattleEventLoggerAutoload.service:
		BattleEventLoggerAutoload.service.log_event("ship_spawned", {
			"ship_id": ship_data.ship_id,
			"type": ship_type,
			"team": team,
			"position": position
		})

	return ship_data

# ============================================================================
# WIN CONDITION
# ============================================================================

func _check_win_condition() -> void:
	var player_ships = 0
	var enemy_ships = 0

	for ship in _ships:
		if ship == null:
			continue
		if ship.status == "destroyed":
			continue

		if ship.team == 0:
			player_ships += 1
		else:
			enemy_ships += 1

	if player_ships == 0 and enemy_ships > 0:
		_end_game(1)
	elif enemy_ships == 0 and player_ships > 0:
		_end_game(0)

func _end_game(winner: int) -> void:
	game_ended.emit(winner)

	if BattleEventLoggerAutoload.service:
		BattleEventLoggerAutoload.service.log_event("game_ended", {"winner": winner})

	print("Game Over! Team %d wins!" % winner)

# ============================================================================
# PUBLIC API (for testing)
# ============================================================================

func get_ships() -> Array:
	return _ships

func get_ship_by_id(ship_id: String) -> Dictionary:
	return _find_ship_by_id(ship_id)

func clear_ships() -> void:
	for ship_id in _ship_entities.keys():
		_remove_ship(ship_id)
	_ships.clear()
