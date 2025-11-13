extends Node
class_name CombatSystem

signal entity_spawned(entity: Node2D)

const MedallionData = preload("res://scripts/core/data/medallion_data.gd")

var scene_root: Node2D

func cast_from_hand(caster: PlayerCharacter, slot: int, target_pos: Vector2) -> void:
	var medallion: Medallion = caster.hand.get_card(slot)
	if not medallion:
		return

	# Attempt to spend mana (includes validation)
	if not caster.spend_mana(medallion.get_medallion_cost()):
		return  # Failed to spend (insufficient mana)

	# Play the card (replaces it with new one from satchel)
	caster.hand.play_card(slot)

	# Get medallion data using string ID
	var medallion_data_instance: MedallionData = MedallionData.new()
	var data: Dictionary = medallion_data_instance.get_medallion(medallion.id)
	var spell_class: GDScript = medallion_data_instance.get_spell_class(medallion.id)

	if not spell_class:
		push_error("No spell class found for medallion: %s" % medallion.id)
		return

	# Enrich data with resolved classes and visual info so spells don't need to know about ClassRegistry
	var enriched_data: Dictionary = data.get("properties", {}).duplicate()
	var entity_class: GDScript = medallion_data_instance.get_entity_class(medallion.id)
	if entity_class:
		enriched_data["entity_class"] = entity_class
	# Copy visual_emoji from root data to enriched_data for future renderer use
	if data.has("visual_emoji"):
		enriched_data["visual_emoji"] = data["visual_emoji"]

	# Use spell system
	var spell: Spell = spell_class.new()
	var entity: Node2D = spell.resolve(caster, target_pos, enriched_data, scene_root)

	# Emit signal for any spawned entity (battlefield can connect to handle projectile explosions, etc.)
	if entity:
		entity_spawned.emit(entity)
