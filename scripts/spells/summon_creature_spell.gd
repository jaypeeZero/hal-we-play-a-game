extends Spell
class_name SummonCreatureSpell

# Spell that creates creature objects
# Uses the entity_class from data or creature type system
# Handles generic pack/swarm linking

const CreatureObject = preload("res://scripts/entities/creatures/creature_object.gd")
const CreatureTypeData = preload("res://scripts/core/data/creature_type_data.gd")
const SWARM_SPAWN_RADIUS = 40.0

func resolve(caster: Node2D, target_pos: Vector2, data: Dictionary, scene_root: Node2D) -> Node2D:
	var creature_type_id: String = data.get("creature_type", "")
	var spawn_count: int = data.get("spawn_count", 1)
	var spawned_creatures: Array = []
	var enemy_player: PlayerCharacter = null

	# Load creature type if specified
	var entity_class: GDScript
	var creature_data: Dictionary

	if creature_type_id:
		# Use creature type system
		var creature_type_service: CreatureTypeData = CreatureTypeData.new()
		var type_data: Dictionary = creature_type_service.get_creature(creature_type_id)
		entity_class = creature_type_service.get_entity_class(creature_type_id)

		if not entity_class:
			push_error("Could not load creature type: %s" % creature_type_id)
			return null

		# Merge stats from creature type with any overrides from medallion
		creature_data = type_data.get("stats", {}).duplicate()
		if type_data.has("ai_config"):
			creature_data["ai_config"] = type_data["ai_config"]

		# Add creature_type ID for visual system
		creature_data["creature_type"] = creature_type_id

		# Preserve medallion-level visual_emoji if present
		if data.has("visual_emoji"):
			creature_data["visual_emoji"] = data["visual_emoji"]
	else:
		# Fallback: use data directly (backward compatible)
		entity_class = data.get("entity_class", CreatureObject)
		creature_data = data

	# Get enemy player reference - find other PlayerCharacter in scene_root
	if caster is PlayerCharacter:
		for child: Node in scene_root.get_children():
			if child is PlayerCharacter and child != caster:
				enemy_player = child
				break

	# Generate unique coordination group ID for this spawn batch
	var coordination_group_id: String = "%s_%s_%d" % [creature_type_id, caster.get_instance_id(), Time.get_ticks_msec()]

	for i: int in range(spawn_count):
		var spawn_offset: Vector2 = _calculate_spawn_offset(i, spawn_count)
		var creature: BattlefieldObject = entity_class.new() as BattlefieldObject

		scene_root.add_child(creature)
		creature.global_position = caster.global_position + spawn_offset

		# Handle different initialize signatures
		if creature is CreatureObject:
			(creature as CreatureObject).initialize(creature_data, target_pos, enemy_player)
		else:
			creature.initialize(creature_data, target_pos)

		# Set owner_id and coordination_group_id if caster is a player
		if caster is PlayerCharacter and creature is CreatureObject:
			(creature as CreatureObject).owner_id = (caster as PlayerCharacter).player_id
			(creature as CreatureObject).coordination_group_id = coordination_group_id

		creature.add_to_group("creatures")
		creature.add_to_group("combatants")

		# Register with VisualBridge (must be in scene tree first)
		VisualBridgeAutoload.register_entity(creature as IRenderable)

		spawned_creatures.append(creature)

	# Handle pack/swarm linking - determined by entity class capabilities
	if spawned_creatures.size() > 1:
		_link_pack_if_supported(spawned_creatures)

	# Return the first creature
	return spawned_creatures[0] if spawned_creatures.size() > 0 else null

func _link_pack_if_supported(units: Array) -> void:
	# Check if creatures support pack behavior by testing for pack_members property
	# This is determined by the entity class, not external configuration
	if units.is_empty():
		return

	# Test the first creature - if it has pack_members, all in this spawn should too
	var first_unit: BattlefieldObject = units[0]
	if not "pack_members" in first_unit:
		return

	# Entity class supports pack behavior - link all units
	for unit: BattlefieldObject in units:
		if "pack_members" in unit:
			unit.set("pack_members", units.duplicate())

	# Assign surrounding angles for pack formation behavior
	var angle_step: float = (2 * PI) / units.size()
	for i: int in range(units.size()):
		var unit: BattlefieldObject = units[i]
		if "assigned_angle" in unit:
			unit.set("assigned_angle", i * angle_step)

func _calculate_spawn_offset(index: int, total_count: int) -> Vector2:
	if total_count == 1:
		return Vector2.ZERO

	var angle: float = (2 * PI * index) / total_count
	return Vector2(cos(angle), sin(angle)) * SWARM_SPAWN_RADIUS
