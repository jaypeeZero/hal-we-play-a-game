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
const SpatialGridSystem = preload("res://scripts/space/systems/spatial_grid_system.gd")

# Spatial-grid cell size. Comparable to typical sensor/awareness range tier;
# tune empirically with the perf harness — too small inflates cells walked,
# too large inflates candidates per cell.
const GRID_CELL_SIZE: float = 256.0

# Preload entity classes
const ShipEntity = preload("res://scripts/space/entities/ship_entity.gd")
const ProjectileEntity = preload("res://scripts/space/entities/projectile_entity.gd")
const VisualEffectEntity = preload("res://scripts/space/entities/visual_effect_entity.gd")
const ObstacleEntity = preload("res://scripts/space/entities/obstacle_entity.gd")

# Preload debug overlay
const DebugOverlay = preload("res://scripts/space/debug_overlay.gd")

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
var _battlefield_size: Vector2 = Vector2(5000, 3500)

const CAMPAIGN_MAP_SCENE := "res://scenes/campaign_map_3d.tscn"

## Roguelike defeats need the wiped fleet's final state, but destroyed
## ships leave _ships (and their crew leave _crew_list) during cleanup;
## each lost player ship is captured here at the moment of destruction.
var _fallen_player_ships: Array = []

# Weapon update timer
var _weapon_update_timer: float = 0.0
const WEAPON_UPDATE_INTERVAL: float = 0.1

# Crew AI state
var _crew_list: Array = []  # Array of crew_data Dictionaries
var _crew_mailboxes: Dictionary = {}  # crew_id -> Array[event] for the scheduler
var _crew_index: Dictionary = {}  # crew_id -> crew_data (O(1) lookup)
const ENABLE_CREW_AI = true  # Re-enabled with proper event architecture

# Wing formation state
var _previous_wings: Array = []  # Previous frame's wings for loyalty preservation
var _wings_last_formed_at: float = -1.0  # game_time of last form_wings() call
var _wings_dirty: bool = true  # Set true when membership-affecting events fire

var _debug_overlay: DebugOverlay

func _ready() -> void:
	_setup_input_actions()

	if ENABLE_CREW_AI:
		_enable_event_tracking()

	_spawn_from_battle_plan()

	_debug_overlay = DebugOverlay.new()
	_debug_overlay._game = self
	_debug_overlay.z_index = 100
	add_child(_debug_overlay)

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
		var pre_movement_ship_grid = SpatialGridSystem.build(_ships, GRID_CELL_SIZE)
		var pre_movement_projectile_grid = SpatialGridSystem.build(_projectiles, GRID_CELL_SIZE)
		_update_crew_ai_systems(delta, pre_movement_ship_grid, pre_movement_projectile_grid)

	# 0a. PENDING INTENT - Apply reactive decisions whose commit_at has passed.
	# Skill-based reaction latency lives here: an evasion decided 700 ms ago
	# by a rookie pilot only takes effect now.
	if ENABLE_CREW_AI:
		_commit_pending_intents()

	# 1. MOVEMENT SYSTEM - Update ship positions with obstacle avoidance
	var game_time = Time.get_ticks_msec() / 1000.0
	_ships = MovementSystem.update_all_ships(_ships, delta, game_time, _obstacles)

	# 1a. OBSTACLE MOVEMENT - Update asteroid/debris positions
	_obstacles = MovementSystem.update_all_obstacles(_obstacles, delta)

	# Rebuild grids against post-movement positions; consumed by spatial
	# triggers and collision below.
	var ship_grid = SpatialGridSystem.build(_ships, GRID_CELL_SIZE)
	var obstacle_grid = SpatialGridSystem.build(_obstacles, GRID_CELL_SIZE)

	# 1b. SPATIAL TRIGGERS - Check for sensor contacts after movement
	if ENABLE_CREW_AI:
		_check_spatial_awareness_triggers(ship_grid)

	# 2. WEAPON SYSTEM - Generate fire commands
	_weapon_update_timer += delta
	var fire_commands = []
	if _weapon_update_timer >= WEAPON_UPDATE_INTERVAL:
		_weapon_update_timer = 0.0
		fire_commands = _process_weapons(delta)

	# 3. SPAWN PROJECTILES from fire commands
	if not fire_commands.is_empty():
		_spawn_projectiles(fire_commands)

	# 4. PROJECTILE SYSTEM - Update projectile positions IN PLACE.
	# Projectiles are mutated rather than re-allocated (~5400 dict allocs/sec
	# at scale would otherwise drive GC jitter); _projectiles still holds the
	# same dicts but with updated position/lifetime.
	var projectile_result = ProjectileSystem.advance_all_projectiles_in_place(_projectiles, delta)

	# Remove expired projectiles (entity cleanup + array filter)
	for expired_id in projectile_result.expired_ids:
		_remove_projectile(expired_id)
	if not projectile_result.expired_ids.is_empty():
		var expired_set = {}
		for id in projectile_result.expired_ids:
			expired_set[id] = true
		var kept: Array = []
		for p in _projectiles:
			if p != null and not expired_set.has(p.projectile_id):
				kept.append(p)
		_projectiles = kept

	# 5. COLLISION SYSTEM - Detect hits and apply damage (includes obstacles)
	var collision_result = CollisionSystem.process_collisions(_ships, _projectiles, _obstacles, ship_grid, obstacle_grid)
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

	# Notify crew that their ship took damage (posts to mailbox).
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
		entity.initialize(projectile_data.projectile_id, team, projectile_data.get("projectile_type", "standard"))
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
	# Removing a ship can break wing membership (lead death, formation gap).
	_wings_dirty = true

	# Remove from data
	var ship = _find_ship_by_id(ship_id)
	if not ship.is_empty():
		if RoguelikeRun.active and ship.get("team", -1) == 0:
			_fallen_player_ships.append(_with_attached_crew(ship))
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
	var radius = effect_data.get("radius", 0.0)  # For explosion effects
	entity.initialize(effect_data.effect_id, effect_data.type, effect_data.max_lifetime, radius)
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
	# Ignore gameplay input while the log console has captured the keyboard.
	if LogConsole.capturing_input:
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
	BattleEventLoggerAutoload.log_event("spawn_armed", {"ship_type": ship_type, "count": count, "team": team})

func _request_squadron_spawn(ship_type: String, team: int) -> void:
	_pending_spawn = {
		"type": ship_type,
		"team": team,
		"is_squadron": true
	}
	BattleEventLoggerAutoload.log_event("spawn_armed", {"ship_type": ship_type, "squadron": true, "team": team})

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

			var patrol_center := _battlefield_size * 0.5
			var patrol_radius: float = BattlePlanner.LARGE_SHIP_PATROL_ZONE_RADIUS if FleetDataManager.is_large_ship(ship_type) else BattlePlanner.PATROL_ZONE_RADIUS
			spawn_ship(ship_type, team, ship_position, patrol_center, patrol_radius)

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

		# Create entity - use hull-derived collision radius from ship_data
		var entity = ShipEntity.new()
		entity.initialize(ship_data.ship_id, team, ship_data.collision_radius, "fighter")
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
		BattleEventLoggerAutoload.log_event("squadron_spawned", {"leader": leader_callsign, "size": ship_ids.size(), "team": team})

	_pending_spawn = {}

## Spawn a ship at the given position
func spawn_ship(ship_type: String, team: int, position: Vector2, patrol_center: Vector2, patrol_radius: float) -> Dictionary:
	# Create ship data
	var ship_data = ShipData.create_ship_instance(ship_type, team, position)
	if ship_data.is_empty():
		push_error("Failed to create ship data for type: " + ship_type)
		return {}

	ship_data["assigned_area"] = {
		"center": patrol_center,
		"radius": patrol_radius,
	}

	# Add to data array
	_ships.append(ship_data)

	# Create entity - use hull-derived collision radius from ship_data
	var entity = ShipEntity.new()
	entity.initialize(ship_data.ship_id, team, ship_data.collision_radius, ship_type)
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
	BattleEventLoggerAutoload.log_event("spawn_armed", {"obstacle_type": obstacle_type})

## Spawn all ships for the upcoming battle from BattlePlan. The pre-battle
## scene populates the plan; if a developer launches space_battle.tscn
## directly the planner builds defaults from the on-disk fleets, so this
## is shared code, not a fallback path.
func _spawn_from_battle_plan() -> void:
	if not BattlePlan.has_plan():
		var team0_fleet: Dictionary
		var team1_fleet: Dictionary
		if RoguelikeRun.active:
			team0_fleet = RoguelikeRun.fleet
			team1_fleet = RoguelikeRun.enemy_fleet
		else:
			team0_fleet = FleetDataManager.load_fleet(0)
			team1_fleet = FleetDataManager.load_fleet(1)
		BattlePlan.battlefield_size = _battlefield_size
		BattlePlan.entries = BattlePlanner.build_default_plan(team0_fleet, team1_fleet, _battlefield_size)
	else:
		_battlefield_size = BattlePlan.battlefield_size

	for entry in BattlePlan.entries:
		spawn_ship(
			entry["ship_type"],
			int(entry["team"]),
			entry["position"],
			entry["patrol_center"],
			float(entry["patrol_radius"])
		)

	# Plan is consumed: re-entering battle requires a fresh plan.
	BattlePlan.clear()

	if RoguelikeRun.active:
		_apply_roguelike_damage_states()


func _apply_roguelike_damage_states() -> void:
	if RoguelikeRun.fleet_ships.is_empty():
		return

	var saved_by_type: Dictionary = {}
	for saved_ship in RoguelikeRun.fleet_ships:
		var t: String = saved_ship.get("type", "")
		if not saved_by_type.has(t):
			saved_by_type[t] = []
		saved_by_type[t].append(saved_ship)

	for i in range(_ships.size()):
		var ship: Dictionary = _ships[i]
		if ship.get("team", -1) != 0:
			continue
		var ship_type: String = ship.get("type", "")
		if not saved_by_type.has(ship_type) or saved_by_type[ship_type].is_empty():
			continue
		var saved: Dictionary = saved_by_type[ship_type].pop_front()
		_ships[i] = DictUtils.merge_dict(saved, {
			"ship_id": ship["ship_id"],
			"position": ship["position"],
			"rotation": ship["rotation"],
			"velocity": ship["velocity"],
			"angular_velocity": ship["angular_velocity"],
			"assigned_area": ship["assigned_area"],
		})


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

	if RoguelikeRun.active:
		_handle_roguelike_battle_end(winner)


## The campaign map owns all campaign branching; the battle scene only
## records the outcome and the fleet's final state, then returns to it.
func _handle_roguelike_battle_end(winner: int) -> void:
	var result: String = CampaignSystem.RESULT_VICTORY if winner == 0 \
		else CampaignSystem.RESULT_DEFEAT
	var final_ships := _get_player_ships_final_state()
	RoguelikeRun.record_battle_result(result, final_ships, _crew_groups_for_ships(final_ships))
	get_tree().call_deferred("change_scene_to_file", CAMPAIGN_MAP_SCENE)


## Every team-0 ship's final state - survivors as they stand, ships lost
## during the battle as they were at the moment of destruction.
func _get_player_ships_final_state() -> Array:
	var final_states: Array = _fallen_player_ships.duplicate(true)
	for ship in _ships:
		if ship == null or ship.is_empty():
			continue
		if ship.get("team", -1) != 0:
			continue
		final_states.append(_with_attached_crew(ship))
	return final_states


## A deep copy of the ship with the battle's live crew attached, so
## roguelike jump repairs see the engineers who actually served aboard.
func _with_attached_crew(ship: Dictionary) -> Dictionary:
	var copy: Dictionary = ship.duplicate(true)
	copy["crew"] = _crew_list \
		.filter(func(c): return c.get("assigned_to", "") == ship.get("ship_id", "")) \
		.map(func(c): return c.duplicate(true))
	return copy


## Crew grouped by the ship they crewed, in the shape
## RoguelikeRun.fleet_crew stores (see take_saved_crew).
func _crew_groups_for_ships(ships: Array) -> Array:
	var groups: Array = []
	for ship in ships:
		var members: Array = ship.get("crew", [])
		if not members.is_empty():
			groups.append({"ship_type": ship.get("type", ""), "crew": members.duplicate(true)})
	return groups

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

## Enable event history tracking
func _enable_event_tracking() -> void:
	if BattleEventLoggerAutoload.service:
		BattleEventLoggerAutoload.service.track_history = true

## Update crew AI systems each frame.  Information sharing up the command
## chain runs always; the per-crew decision/awareness path runs only for
## crew that wake (timer due or events pending) inside CrewSchedulerSystem.
func _update_crew_ai_systems(delta: float, ship_grid: Dictionary, projectile_grid: Dictionary) -> void:
	if _crew_list.is_empty():
		return  # No crew to process

	var game_time = Time.get_ticks_msec() / 1000.0

	# Awareness is now refreshed on-wake by CrewSchedulerSystem.tick_with_awareness;
	# the per-frame fleet-wide scan was the dominant CPU cost at scale (50 crew x
	# ~120 entities = 6000 distance checks/frame, plus thousands of dict allocs).

	# Process command chain (information flows up, orders flow down)
	_crew_list = CommandChainSystem.process_command_chain(_crew_list)

	# Form wings only when stale or invalidated.  Wings are stable on a
	# per-second-ish timescale; the per-frame call was pure overhead.
	# Safety-net interval ensures eventual reform even if no event fires.
	const WING_REFORM_INTERVAL := 0.5
	var wings_age = game_time - _wings_last_formed_at
	if _wings_dirty or wings_age >= WING_REFORM_INTERVAL or _previous_wings.is_empty():
		_previous_wings = WingFormationSystem.form_wings(_ships, _crew_list, _previous_wings)
		_wings_last_formed_at = game_time
		_wings_dirty = false
	var wings = _previous_wings
	_update_ship_wing_colors(wings)
	_update_ship_debug_data(wings)

	# Run the scheduler — drains mailboxes, applies event side effects,
	# refreshes awareness on wake, decides, returns updated crew + decisions.
	var result = CrewSchedulerSystem.tick_with_awareness(
		_crew_list, game_time, _crew_mailboxes, _ships, _projectiles, wings,
		ship_grid, projectile_grid)
	_crew_list = result.crew_list
	_crew_mailboxes = result.mailboxes
	_rebuild_crew_index()

	if not result.decisions.is_empty():
		_apply_crew_decisions(result.decisions)

## Rebuild the crew_id -> crew_data index after the scheduler returns a fresh list.
func _rebuild_crew_index() -> void:
	_crew_index.clear()
	for crew in _crew_list:
		_crew_index[crew.crew_id] = crew

## Apply due pending intents and emit decision_committed events.
func _commit_pending_intents() -> void:
	var game_time = Time.get_ticks_msec() / 1000.0
	var result = PendingIntentSystem.commit_due(_ships, game_time)
	_ships = result.ships
	if BattleEventLoggerAutoload.service:
		for entry in result.committed:
			BattleEventLoggerAutoload.service.log_event("decision_committed", entry)

## Apply crew decisions to game state.
##
## Reactive decisions (those carrying `commit_at` in the future) are stashed
## on the ship's pending_intent buffer; PendingIntentSystem.commit_due picks
## them up next frame. Everything else flows through CrewIntegrationSystem
## immediately — non-reactive decisions don't pay reaction-latency cost.
func _apply_crew_decisions(decisions: Array) -> void:
	var game_time = Time.get_ticks_msec() / 1000.0
	var immediate_decisions: Array = []
	var pending_decisions: Array = []
	for decision in decisions:
		if BattleEventLoggerAutoload.service:
			var crew_snapshot = CrewIntegrationSystem.find_crew_by_id(_crew_list, decision.get("crew_id", ""))
			if crew_snapshot.is_empty():
				crew_snapshot = {"crew_id": decision.get("crew_id", "unknown")}
			var trigger = "reactive" if decision.has("commit_at") and decision.commit_at > game_time else "scheduled"
			BattleEventLoggerAutoload.service.log_ai_decision(crew_snapshot, decision, trigger)

		if decision.has("commit_at") and decision.commit_at > game_time:
			pending_decisions.append(decision)
		else:
			immediate_decisions.append(decision)

	# Stash pending decisions on their ships; supersedes any waiting intent.
	for decision in pending_decisions:
		var ship_id = decision.get("entity_id", "")
		var ship_idx = CrewIntegrationSystem.find_ship_index(_ships, ship_id)
		if ship_idx < 0:
			continue
		var crew_snapshot = CrewIntegrationSystem.find_crew_by_id(_crew_list, decision.get("crew_id", ""))
		var payload = {"decision": decision, "crew_snapshot": crew_snapshot}
		_ships[ship_idx] = PendingIntentSystem.attach(
			_ships[ship_idx],
			decision.get("intent_type", ""),
			payload,
			decision.commit_at
		)

	if not immediate_decisions.is_empty():
		var result = CrewIntegrationSystem.apply_crew_decisions_to_ships(_ships, _crew_list, immediate_decisions)
		_ships = result.ships

## Detect newly-visible enemies and lost contacts; post threat_appeared /
## target_lost events into the mailbox so the scheduler wakes the crew.
##
## Detection latency is per-crew: a high-awareness pilot perceives the
## threat almost immediately; a rookie pilot's mailbox event is held back
## by up to MAX_DETECTION_LAG seconds via the event's `deliver_at`. This
## is the foundation of S1 ("The First Burst").
func _check_spatial_awareness_triggers(ship_grid: Dictionary) -> void:
	# For each crew member, check if enemies enter/exit their awareness range
	for i in range(_crew_list.size()):
		var crew = _crew_list[i]
		var ship_id = crew.assigned_to
		var ship = _find_ship_by_id(ship_id)
		if ship.is_empty():
			continue

		var ship_pos = ship.position
		# Same per-crew sensor range InformationSystem uses for awareness.
		var sensor_range: float = float(crew.get("stats", {}).get("awareness_range", 800.0))

		# Previous frame's spatial sightings as {ship_id: true}.
		var previous_contacts: Dictionary = crew.awareness.get("_spatial_seen", {})
		var current_contacts: Dictionary = {}

		# Candidate set comes from the grid; the per-ship filter below stays
		# identical so semantics are preserved.
		var candidates = SpatialGridSystem.query_radius(ship_grid, ship_pos, sensor_range)
		for other_ship in candidates:
			if other_ship.ship_id == ship_id:
				continue  # Skip self
			if other_ship.team == ship.team:
				continue  # Skip allies (for now)

			var distance = ship_pos.distance_to(other_ship.position)
			if distance <= sensor_range:
				# In range!
				current_contacts[other_ship.ship_id] = true

				# New contact?
				if not previous_contacts.has(other_ship.ship_id):
					var awareness: float = clamp(float(crew.get("stats", {}).get("skills", {}).get("awareness", 0.5)), 0.0, 1.0)
					var latency: float = (1.0 - awareness) * WingConstants.MAX_DETECTION_LAG
					_queue_crew_event(crew.crew_id, "threat_appeared", {
						"enemy_id": other_ship.ship_id,
						"position": other_ship.position,
						"distance": distance
					}, latency)

		# Fire target_lost for ships that were visible last frame but aren't now.
		for previous_id in previous_contacts.keys():
			if not current_contacts.has(previous_id):
				_queue_crew_event(crew.crew_id, "target_lost", {
					"enemy_id": previous_id
				})

		# Snapshot this frame's sightings under a dedicated key — must not
		# alias awareness.known_entities, which is the Array of entity-info
		# records owned by InformationSystem.
		var updated_crew = crew.duplicate(true)
		updated_crew.awareness["_spatial_seen"] = current_contacts
		_crew_list[i] = updated_crew
		_crew_index[crew.crew_id] = updated_crew

## Queue an event for a crew member.  Wakes them on the next scheduler tick
## and supplies the event to apply_event_side_effects (tactical memory,
## current_target updates, urgent-event dispatch).
##
## `latency_seconds` lets perception be skill-gated: a low-awareness crew
## sees a `threat_appeared` event hundreds of ms after a high-awareness one.
func _queue_crew_event(crew_id: String, event_type: String, data: Dictionary, latency_seconds: float = 0.0) -> void:
	var event: Dictionary = {
		"type": event_type,
		"data": data
	}
	if latency_seconds > 0.0:
		var game_time: float = Time.get_ticks_msec() / 1000.0
		event["deliver_at"] = game_time + latency_seconds
	_crew_mailboxes = CrewMailboxSystem.post_event(_crew_mailboxes, crew_id, event)

## Emit damage events to crew of damaged ships. Damage is felt fast — but
## not instantly: a low-awareness pilot still loses ~MAX_DAMAGE_PERCEPTION_LAG
## sorting out what just hit them.
func _emit_damage_events(hits: Array) -> void:
	for hit in hits:
		# Hits come from CollisionSystem.create_hit, which keys the victim
		# as `ship_id`.
		var target_id = hit.get("ship_id", "")
		if target_id.is_empty():
			continue

		# Find crew assigned to this ship
		for crew in _crew_list:
			if crew.assigned_to == target_id:
				var awareness: float = clamp(float(crew.get("stats", {}).get("skills", {}).get("awareness", 0.5)), 0.0, 1.0)
				var latency: float = (1.0 - awareness) * WingConstants.MAX_DAMAGE_PERCEPTION_LAG
				_queue_crew_event(crew.crew_id, "ship_damaged", {
					"damage": hit.get("damage", 0),
					"section": hit.get("section", ""),
					"attacker": hit.get("projectile_id", "")
				}, latency)

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

	# In a roguelike run, the player's crew roster persists: bind the next
	# saved group for this hull type before creating anyone new. Binding
	# is in entry order — DoctrineSystem.map_entries_to_crew_groups relies
	# on this contract.
	if team == 0 and RoguelikeRun.active:
		for saved_member in RoguelikeRun.take_saved_crew(ship_type):
			new_crew.append(CrewData.reset_for_battle(saved_member))

	if new_crew.is_empty():
		new_crew = CrewData.create_crew_for_ship_type(ship_type, weapon_count, base_skill)

	# Compile the run's doctrine (player standing instructions) into each
	# crew member's knowledge set.
	if team == 0 and RoguelikeRun.active:
		for i in range(new_crew.size()):
			new_crew[i] = DoctrineSystem.compile_for_crew(new_crew[i], ship_type, RoguelikeRun.doctrine)

	# Assign crew to ship and add to index
	for crew_member in new_crew:
		crew_member.assigned_to = ship_id
		_crew_list.append(crew_member)
		_crew_index[crew_member.crew_id] = crew_member

	BattleEventLoggerAutoload.log_event("crew_created", {"ship_id": ship_id, "ship_type": ship_type, "count": new_crew.size()})

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
		BattleEventLoggerAutoload.log_event("crew_removed", {"ship_id": ship_id, "count": crew_to_remove.size()})

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
			var raw_tid = ship.get("orders", {}).get("target_id")
			var target_id: String = raw_tid if raw_tid != null else ""
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

			for crew in updated_squadron:
				if crew.get("is_squadron_leader", false) and crew.crew_id != leader_id:
					BattleEventLoggerAutoload.log_event("squadron_leader_promoted", {
						"crew_id": crew.crew_id, "callsign": crew.get("callsign", "Unknown")})
