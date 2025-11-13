class_name SensorySystem
extends RefCounted

## Perception system for creatures
## Determines what creature can see/hear in environment

const CollisionLayers = preload("res://scripts/core/autoload/collision_layers.gd")

# Perception configuration (from AIPersonality)
var awareness_radius: float = 200.0
var use_line_of_sight: bool = true

# Cached queries (updated periodically, not every frame)
var visible_enemies: Array = []
var visible_allies: Array = []
var nearby_cover: Array = []
var current_threats: Array = []

# Last update time (for delta accumulation)
var time_since_update: float = 0.0
var update_interval: float = 0.2  # Update every 0.2s, not every frame

# Reference to owning creature
var owner: Node2D
var world: World2D

func _init(p_owner: Node2D, p_personality: AIPersonality) -> void:
	owner = p_owner
	awareness_radius = p_personality.awareness_radius

## Update sensory information
## Called by AIController with delta accumulation
func update(delta: float) -> void:
	time_since_update += delta
	if time_since_update < update_interval:
		return  # Not time to update yet

	time_since_update = 0.0

	# Cache world reference
	if owner.is_inside_tree():
		world = owner.get_world_2d()
	else:
		return

	_scan_for_entities()
	_assess_threats()
	_scan_for_cover()

func _scan_for_entities() -> void:
	visible_enemies.clear()
	visible_allies.clear()

	if not owner.is_inside_tree():
		return

	var all_combatants: Array = owner.get_tree().get_nodes_in_group("combatants")
	var owner_id: int = owner.get("owner_id") if "owner_id" in owner else -1

	for creature: Variant in all_combatants:
		if creature == owner or not is_instance_valid(creature):
			continue

		var distance: float = owner.global_position.distance_to(creature.global_position)
		if distance > awareness_radius:
			continue  # Outside awareness range

		# Check line of sight if enabled
		if use_line_of_sight and _is_blocked_by_terrain(creature):
			continue  # Can't see through terrain

		# Classify as ally or enemy
		var creature_owner_id: int = creature.get("owner_id") if "owner_id" in creature else -1
		if creature_owner_id == owner_id:
			visible_allies.append(creature)
		else:
			visible_enemies.append(creature)

func _is_blocked_by_terrain(target: Node2D) -> bool:
	"""Check if terrain blocks line of sight to target"""
	if not world:
		return false

	var space_state: PhysicsDirectSpaceState2D = world.direct_space_state
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(
		owner.global_position,
		target.global_position
	)
	query.collision_mask = CollisionLayers.TERRAIN_COLLISION_LAYER
	query.hit_from_inside = false

	var result: Dictionary = space_state.intersect_ray(query)
	return not result.is_empty()  # True if terrain hit

func _assess_threats() -> void:
	"""Evaluate threat level of each visible enemy"""
	current_threats.clear()

	for enemy: Variant in visible_enemies:
		if not is_instance_valid(enemy):
			continue

		var threat: float = _calculate_threat_level(enemy)
		if threat > 0.0:
			current_threats.append({
				"entity": enemy,
				"threat_level": threat,
				"distance": owner.global_position.distance_to(enemy.global_position)
			})

	# Sort by threat level (highest first)
	current_threats.sort_custom(func(a, b): return a.threat_level > b.threat_level)

func _calculate_threat_level(enemy: Node2D) -> float:
	"""Calculate how dangerous an enemy is (0.0 to 1.0)"""
	if not is_instance_valid(enemy):
		return 0.0

	var threat: float = 0.0

	# Closer enemies are more threatening
	var distance: float = owner.global_position.distance_to(enemy.global_position)
	var proximity_threat: float = 1.0 - (distance / awareness_radius)

	# High damage enemies are more threatening
	var damage: float = enemy.get("damage") if "damage" in enemy else 10.0
	var damage_threat: float = clamp(damage / 30.0, 0.0, 1.0)  # Normalize by typical damage

	# Combine factors
	threat = (proximity_threat * 0.6) + (damage_threat * 0.4)

	return clamp(threat, 0.0, 1.0)

func _scan_for_cover() -> void:
	"""Find nearby terrain that could be used as cover"""
	nearby_cover.clear()

	if not owner.is_inside_tree():
		return

	var terrain_objects: Array = owner.get_tree().get_nodes_in_group("terrain")

	for terrain: Variant in terrain_objects:
		if not is_instance_valid(terrain):
			continue

		var distance: float = owner.global_position.distance_to(terrain.global_position)
		if distance > awareness_radius:
			continue

		nearby_cover.append({
			"position": terrain.global_position,
			"distance": distance
		})

	# Sort by distance (nearest first)
	nearby_cover.sort_custom(func(a, b): return a.distance < b.distance)

## Get context data for EmotionalState
func get_emotional_context() -> Dictionary:
	var highest_threat: float = current_threats[0].threat_level if current_threats.size() > 0 else 0.0

	return {
		"ally_count": visible_allies.size(),
		"enemy_count": visible_enemies.size(),
		"health_percent": _get_owner_health_percent(),
		"threat_level": highest_threat
	}

func _get_owner_health_percent() -> float:
	if "health_component" in owner and owner.health_component:
		return owner.health_component.health / owner.health_component.max_health
	return 1.0

## Query methods for AIController

func get_nearest_enemy() -> Node2D:
	if visible_enemies.is_empty():
		return null

	var nearest: Node2D = null
	var nearest_dist: float = INF

	for enemy: Variant in visible_enemies:
		if not is_instance_valid(enemy):
			continue

		var dist: float = owner.global_position.distance_to(enemy.global_position)
		if dist < nearest_dist:
			nearest = enemy
			nearest_dist = dist

	return nearest

func get_highest_threat() -> Dictionary:
	if current_threats.is_empty():
		return {}
	return current_threats[0]

func is_cover_available() -> bool:
	return nearby_cover.size() > 0

func get_nearest_cover_position() -> Vector2:
	if nearby_cover.is_empty():
		return owner.global_position
	return nearby_cover[0].position

func is_hidden_from(target: Node2D) -> bool:
	"""Check if terrain blocks target's line of sight to us"""
	return _is_blocked_by_terrain(target)

func has_allies_nearby() -> bool:
	return visible_allies.size() > 0

func is_outnumbered() -> bool:
	return visible_enemies.size() > visible_allies.size() + 1  # +1 for self
