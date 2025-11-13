extends Node2D
class_name HeadlessBattleSimulator

## Headless battle simulator for testing and simulation
## Creates a minimal battlefield with event stream logging
## No UI, no rendering - pure game logic

const MedallionData = preload("res://scripts/core/data/medallion_data.gd")

signal battle_ended(results: Dictionary)

var combat_system: CombatSystem
var event_logger: BattleEventLogger
var teams: Dictionary = {
	1: [],  # Team A creatures
	2: []   # Team B creatures
}
var battle_active: bool = false
var battle_results: Dictionary = {}
var max_battle_duration: float = 120.0  # 2 minutes max
var elapsed_time: float = 0.0
var time_scale: float = 1.0  # Time acceleration multiplier

func _ready() -> void:
	_setup_systems()

func _setup_systems() -> void:
	# Event logger
	event_logger = BattleEventLogger.new()
	event_logger.track_history = true
	add_child(event_logger)

	# Combat system
	combat_system = CombatSystem.new()
	combat_system.scene_root = self
	add_child(combat_system)

	# Connect combat system to logger
	combat_system.entity_spawned.connect(_on_entity_spawned)

## Spawn a creature for a team
func spawn_creature(creature_type: String, team_id: int, position: Vector2) -> CreatureObject:
	# Get creature data
	var medallion_data: MedallionData = MedallionData.new()
	var entity_class: GDScript = null

	# Look up the creature by medallion ID
	# Map creature_type to actual medallion IDs
	var medallion_id: String = ""
	if creature_type == "wolf":
		medallion_id = "wolf_pack"
	elif creature_type == "rat":
		medallion_id = "rat_swarm"
	elif creature_type == "knight":
		medallion_id = "charging_knight"
	elif creature_type == "bear":
		medallion_id = "bear"
	else:
		push_error("Unknown creature type: %s. Available: wolf, rat, knight, bear" % creature_type)
		return null

	entity_class = medallion_data.get_entity_class(medallion_id)
	if not entity_class:
		push_error("No entity class for: %s" % medallion_id)
		return null

	# Create creature
	var creature: CreatureObject = entity_class.new()
	creature.owner_id = team_id
	add_child(creature)

	# Initialize with basic data
	var data: Dictionary = medallion_data.get_medallion(medallion_id).get("properties", {})
	creature.initialize(data, position)

	# Track in team
	teams[team_id].append(creature)

	# Connect to death signal
	creature.health_component.died.connect(_on_creature_died.bind(creature, team_id))
	creature.health_component.damaged.connect(_on_creature_damaged.bind(creature))

	# Log spawn
	event_logger.log_creature_spawned(
		creature.get_entity_id() if creature.has_method("get_entity_id") else str(creature.get_instance_id()),
		creature_type,
		team_id,
		position
	)

	return creature

## Start a battle
func start_battle() -> void:
	battle_active = true
	elapsed_time = 0.0

	# Apply time acceleration to speed up simulation
	if time_scale > 1.0:
		Engine.time_scale = time_scale

	var message = "Battle started with %d vs %d creatures (time_scale: %.1fx)" % [teams[1].size(), teams[2].size(), time_scale]
	var logger = get_node_or_null("/root/GameLogger")
	if logger:
		logger.write_log(message)
	else:
		print(message)

## Process battle
func _process(delta: float) -> void:
	if not battle_active:
		return

	elapsed_time += delta

	# Check for timeout
	if elapsed_time >= max_battle_duration:
		_end_battle("timeout")
		return

	# Check win conditions
	_check_victory()

func _check_victory() -> void:
	var team1_alive: int = _count_alive_creatures(1)
	var team2_alive: int = _count_alive_creatures(2)

	if team1_alive == 0 and team2_alive == 0:
		_end_battle("draw")
	elif team1_alive == 0:
		_end_battle("team_2_victory")
	elif team2_alive == 0:
		_end_battle("team_1_victory")

func _count_alive_creatures(team_id: int) -> int:
	var count: int = 0
	for creature in teams[team_id]:
		if is_instance_valid(creature) and creature is CreatureObject:
			if not creature.is_queued_for_deletion():
				count += 1
	return count

func _end_battle(outcome: String) -> void:
	battle_active = false

	# Reset time scale
	Engine.time_scale = 1.0

	battle_results = {
		"outcome": outcome,
		"duration": elapsed_time,
		"team_1_survivors": _count_alive_creatures(1),
		"team_2_survivors": _count_alive_creatures(2),
		"total_events": event_logger.event_history.size()
	}

	var end_message = "Battle ended: %s (%.2fs)" % [outcome, elapsed_time]
	var logger = get_node_or_null("/root/GameLogger")
	if logger:
		logger.write_log(end_message)
	else:
		print(end_message)
	battle_ended.emit(battle_results)

## Signal handlers

func _on_entity_spawned(entity: Node2D) -> void:
	# Track projectiles
	if entity is ProjectileObject:
		var proj: ProjectileObject = entity as ProjectileObject
		event_logger.log_projectile_fired(
			str(proj.get_instance_id()),
			str(proj.owner_id) if proj.has("owner_id") else "unknown",
			proj.global_position
		)

func _on_creature_damaged(amount: float, source_id: int, creature: CreatureObject) -> void:
	event_logger.log_damage_dealt(
		creature.get_entity_id() if creature.has_method("get_entity_id") else str(creature.get_instance_id()),
		str(source_id),
		amount,
		"physical"
	)

func _on_creature_died(creature: CreatureObject, team_id: int) -> void:
	if not is_instance_valid(creature):
		return

	var creature_id: String = creature.get_entity_id() if creature.has_method("get_entity_id") else str(creature.get_instance_id())
	var creature_type: String = "unknown"

	# Try to determine creature type from class or properties
	if creature.has_method("get_visual_type"):
		creature_type = creature.get_visual_type()

	event_logger.log_creature_died(
		creature_id,
		creature_type,
		""  # Could track killer if we want
	)

	# Remove from team tracking immediately
	if teams.has(team_id):
		var idx: int = teams[team_id].find(creature)
		if idx >= 0:
			teams[team_id].remove_at(idx)

## Utility: Create a standard battle setup
static func create_symmetric_battle(creature_type_a: String, count_a: int, creature_type_b: String, count_b: int) -> HeadlessBattleSimulator:
	var sim: HeadlessBattleSimulator = HeadlessBattleSimulator.new()

	# Spawn team 1 on left side
	for i: int in range(count_a):
		var x: float = 200.0
		var y: float = 200.0 + i * 50.0
		sim.spawn_creature(creature_type_a, 1, Vector2(x, y))

	# Spawn team 2 on right side
	for i: int in range(count_b):
		var x: float = 1080.0
		var y: float = 200.0 + i * 50.0
		sim.spawn_creature(creature_type_b, 2, Vector2(x, y))

	return sim
