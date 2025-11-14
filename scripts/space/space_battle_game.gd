class_name SpaceBattleGame
extends Node2D

## Pure ECS orchestrator for space combat game
## Systems process data, entities are minimal wrappers for physics
## Data flows: ships[] -> Systems -> updated ships[] -> sync entities

# Preload system classes
const MovementSystem = preload("res://scripts/space/systems/movement_system.gd")
const ProjectileSystem = preload("res://scripts/space/systems/projectile_system.gd")
const CollisionSystem = preload("res://scripts/space/systems/collision_system.gd")
const VisualEffectSystem = preload("res://scripts/space/systems/visual_effect_system.gd")

# Preload entity classes
const ShipEntity = preload("res://scripts/space/entities/ship_entity.gd")
const ProjectileEntity = preload("res://scripts/space/entities/projectile_entity.gd")
const VisualEffectEntity = preload("res://scripts/space/entities/visual_effect_entity.gd")
const ObstacleEntity = preload("res://scripts/space/entities/obstacle_entity.gd")

signal game_started()
signal game_ended(winner: int)
signal ship_spawned(ship_id: String)

# ============================================================================
# ECS DATA - Pure data arrays
# ============================================================================

var _ships: Array = []  # Array of ship_data Dictionaries
var _projectiles: Array = []  # Array of projectile_data Dictionaries
var _visual_effects: Array = []  # Array of visual_effect_data Dictionaries
var _obstacles: Array = []  # Array of obstacle_data Dictionaries

# ============================================================================
# ENTITIES - Minimal Godot nodes for physics
# ============================================================================

var _ship_entities: Dictionary = {}  # ship_id -> ShipEntity
var _projectile_entities: Dictionary = {}  # projectile_id -> ProjectileEntity
var _effect_entities: Dictionary = {}  # effect_id -> VisualEffectEntity
var _obstacle_entities: Dictionary = {}  # obstacle_id -> ObstacleEntity

# ============================================================================
# GAME STATE
# ============================================================================

var _pending_spawn: Dictionary = {}
var _battlefield_size: Vector2 = Vector2(1920, 1080)

# Weapon update timer
var _weapon_update_timer: float = 0.0
const WEAPON_UPDATE_INTERVAL: float = 0.1

# Crew AI
var _crew_list: Array = []  # Array of crew_data Dictionaries
var _recent_events: Array = []  # Events for tactical memory
const MAX_EVENT_HISTORY = 20

func _ready() -> void:
	_setup_input_actions()
	_initialize_knowledge_base()
	_enable_event_tracking()
	_spawn_initial_obstacles()
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
	_ensure_action("spawn_obstacle_small", KEY_7)
	_ensure_action("spawn_obstacle_medium", KEY_8)
	_ensure_action("spawn_obstacle_large", KEY_9)
	_ensure_action("spawn_platform", KEY_0)

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
	# 0. CREW AI SYSTEMS - Update crew awareness, tactical memory, and decisions
	_update_crew_ai_systems(delta)

	# 1. MOVEMENT SYSTEM - Update ship positions with obstacle avoidance
	_ships = MovementSystem.update_all_ships(_ships, delta, _obstacles)

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

	# 5. COLLISION SYSTEM - Detect hits and apply damage (includes obstacles)
	var collision_result = CollisionSystem.process_collisions(_ships, _projectiles, _obstacles)
	_ships = collision_result.ships
	_projectiles = collision_result.projectiles
	_obstacles = collision_result.obstacles

	# Spawn visual effects from collisions
	if collision_result.has("visual_effects"):
		for effect_data in collision_result.visual_effects:
			_spawn_visual_effect(effect_data)

	# Remove destroyed projectiles from hits
	for hit in collision_result.hits:
		_remove_projectile(hit.projectile_id)

	# 6. VISUAL EFFECT SYSTEM - Update and remove expired effects
	var effect_result = VisualEffectSystem.update_all_effects(_visual_effects, delta)
	_visual_effects = effect_result.effects

	# Remove expired effects
	for expired_id in effect_result.expired_ids:
		_remove_visual_effect(expired_id)

	# 7. CHECK FOR DESTROYED SHIPS AND OBSTACLES
	_cleanup_destroyed_ships()
	_cleanup_destroyed_obstacles()

	# 8. SYNC ENTITIES - Update Godot nodes from data
	_sync_all_entities()

	# 9. CHECK WIN CONDITION
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

	# Remove crew assigned to this ship
	_remove_crew_for_ship(ship_id)

	# Log event
	if BattleEventLoggerAutoload.service:
		BattleEventLoggerAutoload.service.log_event("ship_destroyed", {"ship_id": ship_id})

## Remove projectile entity
func _remove_projectile(projectile_id: String) -> void:
	if _projectile_entities.has(projectile_id):
		var entity = _projectile_entities[projectile_id]
		entity.queue_free()
		_projectile_entities.erase(projectile_id)

## Spawn visual effect
func _spawn_visual_effect(effect_data: Dictionary) -> void:
	_visual_effects.append(effect_data)

	# Create entity
	var entity = VisualEffectEntity.new()
	entity.initialize(effect_data.effect_id, effect_data.type, effect_data.max_lifetime)
	entity.global_position = effect_data.position
	add_child(entity)
	_effect_entities[effect_data.effect_id] = entity

## Remove visual effect entity
func _remove_visual_effect(effect_id: String) -> void:
	if _effect_entities.has(effect_id):
		var entity = _effect_entities[effect_id]
		entity.queue_free()
		_effect_entities.erase(effect_id)

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

	# Sync visual effects
	for effect in _visual_effects:
		if effect == null:
			continue
		if _effect_entities.has(effect.effect_id):
			var entity = _effect_entities[effect.effect_id]
			entity.global_position = effect.position
			entity.emit_state(effect)

	# Sync obstacles
	for obstacle in _obstacles:
		if obstacle == null:
			continue
		if _obstacle_entities.has(obstacle.obstacle_id):
			var entity = _obstacle_entities[obstacle.obstacle_id]
			entity.sync_transform(obstacle)
			entity.emit_state(obstacle)

# ============================================================================
# SHIP SPAWNING
# ============================================================================

func _input(event: InputEvent) -> void:
	# Ship spawn requests
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

	# Obstacle spawn requests
	elif event.is_action_pressed("spawn_obstacle_small"):
		_request_obstacle_spawn("asteroid_small")
	elif event.is_action_pressed("spawn_obstacle_medium"):
		_request_obstacle_spawn("asteroid_medium")
	elif event.is_action_pressed("spawn_obstacle_large"):
		_request_obstacle_spawn("asteroid_large")
	elif event.is_action_pressed("spawn_platform"):
		_request_obstacle_spawn("platform")

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

	# Check if spawning obstacle or ship
	if _pending_spawn.get("spawn_type", "ship") == "obstacle":
		var obstacle_type = _pending_spawn.type
		spawn_obstacle(obstacle_type, spawn_position)
	else:
		# Spawn ships
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

	# Create crew for this ship
	_create_crew_for_ship(ship_data.ship_id, ship_type)

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
# OBSTACLE SPAWNING
# ============================================================================

func _request_obstacle_spawn(obstacle_type: String) -> void:
	_pending_spawn = {
		"spawn_type": "obstacle",
		"type": obstacle_type
	}
	print("Click to spawn %s obstacle" % obstacle_type)

## Spawn initial obstacles at game start
func _spawn_initial_obstacles() -> void:
	var obstacle_types = [
		{"type": "asteroid_small", "count": 8},
		{"type": "asteroid_medium", "count": 5},
		{"type": "asteroid_large", "count": 3},
		{"type": "platform", "count": 2},
		{"type": "dock_scaffolding", "count": 2},
		{"type": "debris", "count": 10}
	]

	# Add margin to keep obstacles away from edges
	var margin = 150.0
	var spawn_area_min = Vector2(margin, margin)
	var spawn_area_max = _battlefield_size - Vector2(margin, margin)

	for obstacle_config in obstacle_types:
		for i in range(obstacle_config.count):
			var random_pos = Vector2(
				randf_range(spawn_area_min.x, spawn_area_max.x),
				randf_range(spawn_area_min.y, spawn_area_max.y)
			)
			spawn_obstacle(obstacle_config.type, random_pos)

## Spawn an obstacle at the given position
func spawn_obstacle(obstacle_type: String, position: Vector2) -> Dictionary:
	# Create obstacle data
	var obstacle_data = ObstacleData.create_obstacle_instance(obstacle_type, position, randf() * TAU)
	if obstacle_data.is_empty():
		push_error("Failed to create obstacle data for type: " + obstacle_type)
		return {}

	# Add to data array
	_obstacles.append(obstacle_data)

	# Create entity
	var entity = ObstacleEntity.new()
	entity.initialize(obstacle_data.obstacle_id, obstacle_data.type, obstacle_data.radius)
	add_child(entity)
	_obstacle_entities[obstacle_data.obstacle_id] = entity

	# Log event
	if BattleEventLoggerAutoload.service:
		BattleEventLoggerAutoload.service.log_event("obstacle_spawned", {
			"obstacle_id": obstacle_data.obstacle_id,
			"type": obstacle_type,
			"position": position
		})

	return obstacle_data

## Cleanup destroyed obstacles
func _cleanup_destroyed_obstacles() -> void:
	var destroyed_obstacles = []

	for obstacle in _obstacles:
		if obstacle == null:
			continue
		if obstacle.get("status", "operational") == "destroyed":
			destroyed_obstacles.append(obstacle)

	for obstacle in destroyed_obstacles:
		_remove_obstacle(obstacle.obstacle_id)

## Remove obstacle and entity
func _remove_obstacle(obstacle_id: String) -> void:
	# Remove from data
	var obstacle_to_remove = null
	for obstacle in _obstacles:
		if obstacle.obstacle_id == obstacle_id:
			obstacle_to_remove = obstacle
			break

	if obstacle_to_remove:
		_obstacles.erase(obstacle_to_remove)

	# Remove entity
	if _obstacle_entities.has(obstacle_id):
		var entity = _obstacle_entities[obstacle_id]
		entity.queue_free()
		_obstacle_entities.erase(obstacle_id)

	# Log event
	if BattleEventLoggerAutoload.service:
		BattleEventLoggerAutoload.service.log_event("obstacle_destroyed", {"obstacle_id": obstacle_id})

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

# ============================================================================
# CREW AI INTEGRATION
# ============================================================================

## Initialize knowledge base from JSON files
func _initialize_knowledge_base() -> void:
	KnowledgeLoader.initialize_knowledge_base()

## Enable event history tracking
func _enable_event_tracking() -> void:
	if BattleEventLoggerAutoload.service:
		BattleEventLoggerAutoload.service.track_history = true
		print("Event history tracking enabled")

## Update crew AI systems each frame
func _update_crew_ai_systems(delta: float) -> void:
	if _crew_list.is_empty():
		return  # No crew to process

	var game_time = Time.get_ticks_msec() / 1000.0

	# 1. Update crew tactical memory with recent events
	if BattleEventLoggerAutoload.service and BattleEventLoggerAutoload.service.track_history:
		var all_events = BattleEventLoggerAutoload.service.event_history
		_recent_events = all_events.slice(max(0, all_events.size() - MAX_EVENT_HISTORY), all_events.size())

	_crew_list = TacticalMemorySystem.update_all_crew_memory(_crew_list, _recent_events, game_time)

	# 2. Update crew awareness (what they can see)
	_crew_list = InformationSystem.update_all_crew_awareness(_crew_list, _ships, _projectiles, game_time)

	# 3. Process command chain (orders down, info up)
	_crew_list = CommandChainSystem.process_command_chain(_crew_list)

	# 4. Process crew decisions (uses TacticalKnowledgeSystem internally)
	var result = CrewAISystem.update_all_crew(_crew_list, delta, game_time)
	_crew_list = result.crew_list
	var decisions = result.decisions

	# 5. Apply crew decisions to ships (minimal for now - mainly logging)
	_apply_crew_decisions(decisions)

## Apply crew decisions to game state
func _apply_crew_decisions(decisions: Array) -> void:
	# For now, just log decisions
	# Full integration would modify ship behavior based on crew decisions
	for decision in decisions:
		if BattleEventLoggerAutoload.service:
			BattleEventLoggerAutoload.service.log_event("crew_decision", {
				"crew_id": decision.get("crew_id", "unknown"),
				"type": decision.get("type", "unknown"),
				"subtype": decision.get("subtype", ""),
				"entity_id": decision.get("entity_id", "")
			})

## Create and assign crew to a ship
func _create_crew_for_ship(ship_id: String, ship_type: String) -> void:
	# Determine crew size based on ship type
	var weapon_count = 1  # Default
	match ship_type:
		"fighter":
			# Solo pilot for fighters
			var crew = CrewData.create_solo_fighter_crew(0.7)
			for crew_member in crew:
				crew_member.assigned_to = ship_id
			_crew_list.append_array(crew)
		"corvette":
			weapon_count = 2
			var crew = CrewData.create_ship_crew(weapon_count, 0.6)
			for crew_member in crew:
				crew_member.assigned_to = ship_id
			_crew_list.append_array(crew)
		"capital":
			weapon_count = 4
			var crew = CrewData.create_ship_crew(weapon_count, 0.8)
			for crew_member in crew:
				crew_member.assigned_to = ship_id
			_crew_list.append_array(crew)

	print("Created crew for %s (type: %s)" % [ship_id, ship_type])

## Remove crew assigned to a ship
func _remove_crew_for_ship(ship_id: String) -> void:
	var crew_to_remove = []
	for crew in _crew_list:
		if crew.assigned_to == ship_id:
			crew_to_remove.append(crew)

	for crew in crew_to_remove:
		_crew_list.erase(crew)

	if crew_to_remove.size() > 0:
		print("Removed %d crew members from destroyed ship %s" % [crew_to_remove.size(), ship_id])
