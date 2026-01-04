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

# Initial pause state
var _initial_paused: bool = true

# Weapon update timer
var _weapon_update_timer: float = 0.0
const WEAPON_UPDATE_INTERVAL: float = 0.1

# Crew AI - EVENT-DRIVEN (no polling!)
var _crew_list: Array = []  # Array of crew_data Dictionaries
var _crew_events: Array = []  # Events to process this frame
var _crew_index: Dictionary = {}  # crew_id -> crew_data (O(1) lookup)
const ENABLE_CREW_AI = true  # Re-enabled with proper event architecture

# Wing formation state
var _previous_wings: Array = []  # Previous frame's wings for loyalty preservation

func _ready() -> void:
	# Allow processing when paused (for initial unpause)
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_setup_input_actions()

	if ENABLE_CREW_AI:
		_initialize_knowledge_base()
		_enable_event_tracking()

	# Obstacle spawning disabled for better user interaction
	# _spawn_initial_obstacles()

	# Spawn 2 squadrons per team on opposite sides of the map
	_spawn_initial_squadrons()

	# Pause the game on start
	get_tree().paused = true

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
	if ENABLE_CREW_AI:
		_update_crew_ai_systems(delta)

	# 1. MOVEMENT SYSTEM - Update ship positions with obstacle avoidance
	_ships = MovementSystem.update_all_ships(_ships, delta, _obstacles)

	# 1a. OBSTACLE MOVEMENT - Update asteroid/debris positions
	_obstacles = MovementSystem.update_all_obstacles(_obstacles, delta)

	# 1b. SPATIAL TRIGGERS - Check for sensor contacts after movement
	if ENABLE_CREW_AI:
		_check_spatial_awareness_triggers()

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

	# Remove all destroyed projectile entities (ship hits and obstacle hits)
	if collision_result.has("destroyed_projectile_ids"):
		for projectile_id in collision_result.destroyed_projectile_ids:
			_remove_projectile(projectile_id)

	# Emit damage events to crew (EVENT-DRIVEN)
	if ENABLE_CREW_AI and not collision_result.hits.is_empty():
		_emit_damage_events(collision_result.hits)

	# SQUADRON LEADERSHIP SUCCESSION - Check for destroyed squadron leaders
	if ENABLE_CREW_AI:
		_check_squadron_leadership_succession()

	# 5a. PHYSICAL COLLISION SYSTEM - Handle ship-ship and ship-obstacle collisions
	var physics_collision_result = CollisionSystem.process_physical_collisions(_ships, _obstacles)
	_ships = physics_collision_result.ships
	_obstacles = physics_collision_result.obstacles

	# Spawn visual effects from physical collisions
	for collision_event in physics_collision_result.collision_events:
		# Get damage amount (ship-obstacle has 'damage', ship-ship has 'damage1' and 'damage2')
		var damage = collision_event.get("damage", 0.0)
		if damage == 0.0:  # Ship-ship collision
			damage = max(collision_event.get("damage1", 0.0), collision_event.get("damage2", 0.0))

		if damage > 5.0:  # Only show effect for significant impacts
			var effect = VisualEffectSystem.create_effect(
				"effect_impact",
				collision_event.get("position", Vector2.ZERO),
				0.4
			)
			_spawn_visual_effect(effect)

	# Emit collision damage events to crew (EVENT-DRIVEN)
	if ENABLE_CREW_AI and not physics_collision_result.collision_events.is_empty():
		for event in physics_collision_result.collision_events:
			if event.type == "ship_obstacle_collision" and event.damage > 0:
				_crew_events.append({
					type = "ship_collision",
					ship_id = event.ship_id,
					damage = event.damage,
					timestamp = Time.get_ticks_msec()
				})
			elif event.type == "ship_ship_collision":
				if event.damage1 > 0:
					_crew_events.append({
						type = "ship_collision",
						ship_id = event.ship1_id,
						damage = event.damage1,
						timestamp = Time.get_ticks_msec()
					})
				if event.damage2 > 0:
					_crew_events.append({
						type = "ship_collision",
						ship_id = event.ship2_id,
						damage = event.damage2,
						timestamp = Time.get_ticks_msec()
					})

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

	# Remove crew assigned to this ship (if AI enabled)
	if ENABLE_CREW_AI:
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
	# Handle initial unpause with spacebar
	if _initial_paused and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		get_tree().paused = false
		_initial_paused = false
		get_viewport().set_input_as_handled()
		return

	# Ship spawn requests
	if event.is_action_pressed("spawn_fighter"):
		_request_squadron_spawn("fighter", 0)  # Spawn squadron of 6 fighters
	elif event.is_action_pressed("spawn_corvette"):
		_request_spawn("corvette", 1, 0)
	elif event.is_action_pressed("spawn_capital"):
		_request_spawn("capital", 1, 0)
	elif event.is_action_pressed("spawn_enemy_fighter"):
		_request_squadron_spawn("fighter", 1)  # Spawn squadron of 6 enemy fighters
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
			if _pending_spawn.get("is_squadron", false):
				_execute_squadron_spawn(get_global_mouse_position())
			else:
				_execute_spawn(get_global_mouse_position())

func _request_spawn(ship_type: String, count: int, team: int) -> void:
	_pending_spawn = {
		"type": ship_type,
		"count": count,
		"team": team,
		"is_squadron": false
	}
	print("Click to spawn %d %s(s) for team %d" % [count, ship_type, team])

func _request_squadron_spawn(ship_type: String, team: int) -> void:
	_pending_spawn = {
		"type": ship_type,
		"team": team,
		"is_squadron": true
	}
	print("Click to spawn fighter squadron (6 fighters) for team %d" % team)

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

func _execute_squadron_spawn(spawn_position: Vector2) -> void:
	if _pending_spawn.is_empty():
		return

	var team = _pending_spawn.team
	var ship_ids = []

	# Formation positions for 6 fighters (V formation with leader at point)
	# Alpha at point, alternating backward in rank left-to-right
	var formation_positions = [
		Vector2(0, 0),        # Alpha - point (squadron leader)
		Vector2(-80, 80),     # Beta - left back
		Vector2(80, 80),      # Gamma - right back
		Vector2(-160, 160),   # Delta - left further back
		Vector2(160, 160),    # Epsilon - right further back
		Vector2(-240, 240)    # Zeta - left furthest back
	]

	# Spawn 6 fighters
	for i in range(6):
		var offset = formation_positions[i]
		var ship_position = spawn_position + offset

		ship_position.x = clamp(ship_position.x, 50, _battlefield_size.x - 50)
		ship_position.y = clamp(ship_position.y, 50, _battlefield_size.y - 50)

		# Create ship data
		var ship_data = ShipData.create_ship_instance("fighter", team, ship_position)
		if ship_data.is_empty():
			push_error("Failed to create fighter for squadron")
			continue

		# Add to data array
		_ships.append(ship_data)
		ship_ids.append(ship_data.ship_id)

		# Create entity
		var entity = ShipEntity.new()
		entity.initialize(ship_data.ship_id, team, ship_data.stats.size, "fighter")
		add_child(entity)
		_ship_entities[ship_data.ship_id] = entity

		# Emit signal
		ship_spawned.emit(ship_data.ship_id)

	# Create squadron crew structure if AI enabled
	if ENABLE_CREW_AI and ship_ids.size() == 6:
		# Team 0: Ace pilots (skill 1.0), Team 1: Rookie pilots (skill 0.0)
		var squadron_skill = 1.0 if team == 0 else 0.0
		var squadron_crew = CrewData.create_fighter_squadron(squadron_skill)

		# Assign each crew member to their ship
		for i in range(6):
			if i < squadron_crew.size() and i < ship_ids.size():
				squadron_crew[i].assigned_to = ship_ids[i]
				_crew_list.append(squadron_crew[i])
				_crew_index[squadron_crew[i].crew_id] = squadron_crew[i]

		var leader_callsign = squadron_crew[0].get("callsign", "Alpha")
		print("Spawned fighter squadron: %s leads with %d fighters for team %d" % [leader_callsign, 6, team])

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

	# Create crew for this ship (if AI enabled)
	if ENABLE_CREW_AI:
		_create_crew_for_ship(ship_data.ship_id, ship_type, team)

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

## Spawn initial squadrons at game start based on saved fleet configurations
func _spawn_initial_squadrons() -> void:
	# Load fleet configurations from saved files (or use defaults)
	var team0_fleet := FleetDataManager.load_fleet(0)
	var team1_fleet := FleetDataManager.load_fleet(1)

	# Calculate spawn positions on opposite sides of the map
	var margin = 200.0

	# Team 0 (Player) - Left side (Green)
	var team0_x = margin

	# Team 1 (Enemy) - Right side (Grey/White)
	var team1_x = _battlefield_size.x - margin

	# Spawn Team 0 ships
	_spawn_fleet_for_team(team0_fleet, 0, team0_x)

	# Spawn Team 1 ships
	_spawn_fleet_for_team(team1_fleet, 1, team1_x)


## Spawn all ships for a team based on fleet configuration
func _spawn_fleet_for_team(fleet: Dictionary, team: int, base_x: float) -> void:
	print("=== SPAWNING FLEET FOR TEAM %d ===" % team)
	print("Fleet config: %s" % str(fleet))
	print("Battlefield height: %s" % _battlefield_size.y)
	var spawn_positions = ShipData.calculate_fleet_spawn_positions(fleet, base_x, _battlefield_size.y)
	print("Got %d spawn positions" % spawn_positions.size())
	for spawn_info in spawn_positions:
		print("  Spawning %s at position %s (size=%.0f)" % [spawn_info["type"], spawn_info["position"], spawn_info["size"]])
		spawn_ship(spawn_info["type"], team, spawn_info["position"])

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

## Update crew AI systems each frame - EVENT-DRIVEN (no polling!)
func _update_crew_ai_systems(delta: float) -> void:
	if _crew_list.is_empty():
		return  # No crew to process

	var game_time = Time.get_ticks_msec() / 1000.0

	# Update crew awareness (periodic - every frame for now, could be throttled)
	_crew_list = InformationSystem.update_all_crew_awareness(_crew_list, _ships, _projectiles, game_time)

	# Process command chain (information flows up, orders flow down)
	_crew_list = CommandChainSystem.process_command_chain(_crew_list)

	# Form wings and update ship visual data with wing colors
	var wings = WingFormationSystem.form_wings(_ships, _crew_list, _previous_wings)
	_update_ship_wing_colors(wings)
	_update_ship_debug_data(wings)
	_previous_wings = wings  # Store for next frame's loyalty preservation

	# EVENT-DRIVEN: Only process crew events, don't poll all crew
	_process_crew_events(_crew_events, delta, game_time)
	_crew_events.clear()

	# Check for decision timers (crew scheduled to wake up)
	_check_crew_decision_timers(delta, game_time, wings)

## Process crew events (EVENT-DRIVEN: only affected crew)
func _process_crew_events(events: Array, delta: float, game_time: float) -> void:
	for event in events:
		var crew_id = event.get("crew_id", "")
		if crew_id.is_empty():
			continue

		# Find crew member (O(1) with index, fallback to O(N) search)
		var crew = _find_crew_by_id(crew_id)
		if crew.is_empty():
			continue

		# Handle event based on type
		match event.type:
			"sensor_contact":
				_handle_sensor_contact_event(crew, event, game_time)
			"target_lost":
				_handle_target_lost_event(crew, event, game_time)
			"order_received":
				_handle_order_received_event(crew, event, game_time)
			"ship_damaged":
				_handle_ship_damaged_event(crew, event, game_time)
			"battle_event":
				_handle_battle_event(crew, event, game_time)

## Check if any crew need to make decisions (timer expired)
func _check_crew_decision_timers(delta: float, game_time: float, wings: Array = []) -> void:
	var decisions = []

	for i in range(_crew_list.size()):
		var crew = _crew_list[i]

		# Check if it's time for this crew to think
		if game_time >= crew.get("next_decision_time", 0.0):
			# Make decision based on current state (pass wings for fighter coordination)
			var result = CrewAISystem.update_crew_member(crew, delta, game_time, _ships, _crew_list, wings)
			_crew_list[i] = result.crew_data

			if result.has("decision") and not result.decision.is_empty():
				decisions.append(result.decision)

	# Apply decisions
	if not decisions.is_empty():
		_apply_crew_decisions(decisions)

## Find crew by ID
func _find_crew_by_id(crew_id: String) -> Dictionary:
	# Try index first (O(1))
	if _crew_index.has(crew_id):
		return _crew_index[crew_id]

	# Fallback to linear search and rebuild index
	for crew in _crew_list:
		if crew.crew_id == crew_id:
			_crew_index[crew_id] = crew
			return crew

	return {}

## EVENT HANDLERS - These wake crew when something happens to them

func _handle_sensor_contact_event(crew: Dictionary, event: Dictionary, game_time: float) -> void:
	# Enemy detected - update awareness and trigger decision
	var enemy_id = event.data.get("enemy_id", "")
	if enemy_id.is_empty():
		return

	# Update crew awareness with new contact
	var updated_crew = InformationSystem.update_crew_awareness(crew, _ships, _projectiles, game_time)

	# Record in tactical memory
	updated_crew = TacticalMemorySystem.record_event(updated_crew, {
		"type": "threat_detected",
		"entity_id": enemy_id,
		"timestamp": game_time
	})

	# Force immediate decision
	updated_crew.next_decision_time = game_time

	# Update in list
	_update_crew_in_list(updated_crew)

func _handle_target_lost_event(crew: Dictionary, event: Dictionary, game_time: float) -> void:
	# Target lost - need new target
	var updated_crew = crew.duplicate(true)

	# Clear current target
	if updated_crew.awareness.has("current_target"):
		updated_crew.awareness.current_target = ""

	# Force decision to find new target
	updated_crew.next_decision_time = game_time

	_update_crew_in_list(updated_crew)

func _handle_order_received_event(crew: Dictionary, event: Dictionary, game_time: float) -> void:
	# Order from superior - process through command chain
	var order = event.data.get("order", {})
	if order.is_empty():
		return

	var updated_crew = CommandChainSystem.process_single_order(crew, order)

	# Force decision to execute order
	updated_crew.next_decision_time = game_time

	_update_crew_in_list(updated_crew)

func _handle_ship_damaged_event(crew: Dictionary, event: Dictionary, game_time: float) -> void:
	# Ship damaged - alert condition
	var damage_data = event.data

	var updated_crew = TacticalMemorySystem.record_event(crew, {
		"type": "ship_damaged",
		"damage": damage_data,
		"timestamp": game_time
	})

	# Force immediate reassessment
	updated_crew.next_decision_time = game_time

	_update_crew_in_list(updated_crew)

func _handle_battle_event(crew: Dictionary, event: Dictionary, game_time: float) -> void:
	# Generic battle event - update memory
	var event_data = event.data

	var updated_crew = TacticalMemorySystem.record_event(crew, event_data)

	_update_crew_in_list(updated_crew)

## Update crew in the list (maintains immutability)
func _update_crew_in_list(updated_crew: Dictionary) -> void:
	for i in range(_crew_list.size()):
		if _crew_list[i].crew_id == updated_crew.crew_id:
			_crew_list[i] = updated_crew
			_crew_index[updated_crew.crew_id] = updated_crew
			break

## Apply crew decisions to game state
func _apply_crew_decisions(decisions: Array) -> void:
	# Log decisions
	for decision in decisions:
		if BattleEventLoggerAutoload.service:
			BattleEventLoggerAutoload.service.log_event("crew_decision", {
				"crew_id": decision.get("crew_id", "unknown"),
				"type": decision.get("type", "unknown"),
				"subtype": decision.get("subtype", ""),
				"entity_id": decision.get("entity_id", "")
			})

	# Apply decisions to ships
	var result = CrewIntegrationSystem.apply_crew_decisions_to_ships(_ships, _crew_list, decisions)
	_ships = result.ships

## SPATIAL AWARENESS - Check for sensor contacts (EVENT-DRIVEN)
func _check_spatial_awareness_triggers() -> void:
	# For each crew member, check if enemies enter/exit their awareness range
	for i in range(_crew_list.size()):
		var crew = _crew_list[i]
		var ship_id = crew.assigned_to
		var ship = _find_ship_by_id(ship_id)
		if ship.is_empty():
			continue

		var ship_pos = ship.position
		var sensor_range = 800.0  # TODO: Get from ship stats

		# Get previous contacts
		var previous_contacts = crew.awareness.get("known_entities", {})
		var current_contacts = {}

		# Helper to check if ID exists in previous contacts (handles both Dict and Array)
		var has_previous_contact = func(ship_id: String) -> bool:
			if typeof(previous_contacts) == TYPE_DICTIONARY:
				return previous_contacts.has(ship_id)
			elif typeof(previous_contacts) == TYPE_ARRAY:
				for entity in previous_contacts:
					if typeof(entity) == TYPE_DICTIONARY:
						if entity.get("id") == ship_id:
							return true
					elif typeof(entity) == TYPE_STRING:
						if entity == ship_id:
							return true
				return false
			return false

		# Check all ships for contacts
		for other_ship in _ships:
			if other_ship.ship_id == ship_id:
				continue  # Skip self
			if other_ship.team == ship.team:
				continue  # Skip allies (for now)

			var distance = ship_pos.distance_to(other_ship.position)
			if distance <= sensor_range:
				# In range!
				current_contacts[other_ship.ship_id] = true

				# New contact?
				if not has_previous_contact.call(other_ship.ship_id):
					_queue_crew_event(crew.crew_id, "sensor_contact", {
						"enemy_id": other_ship.ship_id,
						"position": other_ship.position,
						"distance": distance
					})

		# Check for lost contacts
		# Handle both Dictionary (new format) and Array (from command chain system)
		var previous_ids = []
		if typeof(previous_contacts) == TYPE_DICTIONARY:
			previous_ids = previous_contacts.keys()
		elif typeof(previous_contacts) == TYPE_ARRAY:
			# Extract IDs from entity objects
			for entity in previous_contacts:
				if typeof(entity) == TYPE_DICTIONARY and entity.has("id"):
					previous_ids.append(entity.id)
				elif typeof(entity) == TYPE_STRING:
					previous_ids.append(entity)

		for previous_id in previous_ids:
			if not current_contacts.has(previous_id):
				_queue_crew_event(crew.crew_id, "target_lost", {
					"enemy_id": previous_id
				})

		# Update crew with current contacts
		var updated_crew = crew.duplicate(true)
		updated_crew.awareness.known_entities = current_contacts
		_crew_list[i] = updated_crew
		_crew_index[crew.crew_id] = updated_crew

## Queue an event for a crew member
func _queue_crew_event(crew_id: String, event_type: String, data: Dictionary) -> void:
	_crew_events.append({
		"crew_id": crew_id,
		"type": event_type,
		"data": data
	})

## Emit damage events to crew of damaged ships
func _emit_damage_events(hits: Array) -> void:
	for hit in hits:
		var target_id = hit.get("target_id", "")
		if target_id.is_empty():
			continue

		# Find crew assigned to this ship
		for crew in _crew_list:
			if crew.assigned_to == target_id:
				_queue_crew_event(crew.crew_id, "ship_damaged", {
					"damage": hit.get("damage", 0),
					"section": hit.get("section", ""),
					"attacker": hit.get("projectile_id", "")
				})

## Create and assign crew to a ship
func _create_crew_for_ship(ship_id: String, ship_type: String, team: int) -> void:
	# Determine crew skill based on team (extreme values for testing)
	# Team 0: Ace pilots (skill 1.0) - best possible
	# Team 1: Rookie pilots (skill 0.0) - worst possible
	var base_skill = 1.0 if team == 0 else 0.0

	# Get actual weapon count from ship data
	var ship_data = _find_ship_by_id(ship_id)
	var weapon_count = ship_data.weapons.size() if not ship_data.is_empty() else 1
	var new_crew = []

	match ship_type:
		"fighter":
			# Solo pilot for fighters
			new_crew = CrewData.create_solo_fighter_crew(base_skill)
		"heavy_fighter":
			# Pilot + gunner for heavy fighters (rear turret defense)
			new_crew = CrewData.create_heavy_fighter_crew(base_skill)
		"corvette", "capital":
			# Captain + pilot + gunners based on actual weapon count
			new_crew = CrewData.create_ship_crew(weapon_count, base_skill)

	# Assign crew to ship and add to index
	for crew_member in new_crew:
		crew_member.assigned_to = ship_id
		_crew_list.append(crew_member)
		_crew_index[crew_member.crew_id] = crew_member

	print("Created %d crew for %s (type: %s)" % [new_crew.size(), ship_id, ship_type])

## Remove crew assigned to a ship
func _remove_crew_for_ship(ship_id: String) -> void:
	var crew_to_remove = []
	for crew in _crew_list:
		if crew.assigned_to == ship_id:
			crew_to_remove.append(crew)

	for crew in crew_to_remove:
		_crew_list.erase(crew)
		_crew_index.erase(crew.crew_id)  # Clean up index

	if crew_to_remove.size() > 0:
		print("Removed %d crew members from destroyed ship %s" % [crew_to_remove.size(), ship_id])

## Update ship data with wing colors for visualization
func _update_ship_wing_colors(wings: Array) -> void:
	# First, clear all wing colors (ships not in a wing)
	for ship in _ships:
		ship["_wing_color"] = Color.TRANSPARENT

	# Then, set wing colors for ships that are in a wing
	for wing in wings:
		var wing_color = wing.get("wing_color", Color.TRANSPARENT)
		var ship_ids = WingFormationSystem.get_wing_ship_ids(wing)

		for ship_id in ship_ids:
			for ship in _ships:
				if ship.get("ship_id", "") == ship_id:
					ship["_wing_color"] = wing_color
					break

## Update ship data with debug visualization info
func _update_ship_debug_data(wings: Array) -> void:
	# Skip if debug tools are disabled
	if not GameSettings.show_pilot_direction and not GameSettings.show_leader_numbers:
		# Clear debug data when disabled
		for ship in _ships:
			ship["_debug_pilot_direction"] = Vector2.ZERO
			ship["_debug_leader_number"] = 0
		return

	# Build a map of wing leads (ship_id -> wing_index)
	var wing_leads: Dictionary = {}
	for i in range(wings.size()):
		var wing = wings[i]
		var lead_ship_id = wing.get("lead_ship_id", "")
		if lead_ship_id != "":
			wing_leads[lead_ship_id] = i + 1  # 1-indexed wing number

	# Build a map of squadron leaders (ship_id -> squadron_index)
	var squadron_leaders: Dictionary = {}
	var squadron_index: int = 1
	for crew in _crew_list:
		if crew.get("is_squadron_leader", false):
			var ship_id = crew.get("assigned_to", "")
			if ship_id != "":
				squadron_leaders[ship_id] = squadron_index
				squadron_index += 1

	# Update debug data for each ship
	for ship in _ships:
		var ship_id = ship.get("ship_id", "")

		# Pilot direction - direction to target
		if GameSettings.show_pilot_direction:
			var target_id = ship.get("orders", {}).get("target_id", "")
			if target_id != "":
				var target = _find_ship_by_id(target_id)
				if not target.is_empty():
					var direction = (target.position - ship.position).normalized()
					ship["_debug_pilot_direction"] = direction
				else:
					ship["_debug_pilot_direction"] = Vector2.ZERO
			else:
				ship["_debug_pilot_direction"] = Vector2.ZERO
		else:
			ship["_debug_pilot_direction"] = Vector2.ZERO

		# Leader number - squadron leaders and wing leads
		if GameSettings.show_leader_numbers:
			# Priority: squadron leader > wing lead
			if squadron_leaders.has(ship_id):
				ship["_debug_leader_number"] = squadron_leaders[ship_id]
			elif wing_leads.has(ship_id):
				ship["_debug_leader_number"] = wing_leads[ship_id]
			else:
				ship["_debug_leader_number"] = 0
		else:
			ship["_debug_leader_number"] = 0

## Check for squadron leader deaths and promote next in line
func _check_squadron_leadership_succession() -> void:
	# Group crew by squadron (using command chain)
	var squadrons = {}  # superior_id -> [crew_list]

	# Find all squadron structures
	for crew in _crew_list:
		if not crew.has("squadron_rank"):
			continue

		# Find their squadron by checking superior
		var superior_id = crew.command_chain.get("superior", "")
		if superior_id != "":
			# Non-leader - group by their superior
			if not squadrons.has(superior_id):
				squadrons[superior_id] = []
			squadrons[superior_id].append(crew)
		else:
			# This is a leader - create squadron entry if not exists
			if not squadrons.has(crew.crew_id):
				squadrons[crew.crew_id] = []

	# Check each squadron for leader status
	for leader_id in squadrons.keys():
		var squadron = squadrons[leader_id]

		# Find the leader
		var leader = null
		for crew in _crew_list:
			if crew.crew_id == leader_id:
				leader = crew
				break

		# If leader doesn't exist or their ship is destroyed, promote next in line
		if leader == null:
			continue

		var leader_ship_id = leader.get("assigned_to", "")
		var leader_ship = null
		for ship in _ships:
			if ship.get("ship_id", "") == leader_ship_id:
				leader_ship = ship
				break

		# Leader's ship destroyed or disabled - promote!
		if leader_ship == null or leader_ship.get("status", "") in ["destroyed", "disabled"]:
			# Add leader to squadron list for promotion calculation
			squadron.append(leader)

			# Promote next in line
			var updated_squadron = CrewData.promote_squadron_leader(squadron)

			# Update crew list with promoted squadron
			for updated_crew in updated_squadron:
				for i in range(_crew_list.size()):
					if _crew_list[i].crew_id == updated_crew.crew_id:
						_crew_list[i] = updated_crew
						_crew_index[updated_crew.crew_id] = updated_crew
						break

			# Print promotion message
			for crew in updated_squadron:
				if crew.get("is_squadron_leader", false) and crew.crew_id != leader_id:
					var callsign = crew.get("callsign", "Unknown")
					print("Squadron leadership succession: %s promoted to squadron leader" % callsign)
