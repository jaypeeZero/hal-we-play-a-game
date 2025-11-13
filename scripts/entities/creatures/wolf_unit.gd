extends CreatureObject
class_name WolfUnit

## Wolf uses PackBehavior for coordinated hunting
## Composes behaviors instead of hardcoding

const PackBehavior = preload("res://scripts/core/ai/behaviors/pack_behavior.gd")
const FleeBehavior = preload("res://scripts/core/ai/behaviors/flee_behavior.gd")

func initialize(data: Dictionary, target_pos: Vector2, enemy_player: PlayerCharacter = null) -> void:
	super.initialize(data, target_pos, enemy_player)

	# Configure thresholds
	near_death_threshold = 0.4  # Call for support at 40% health

	# Load wolf movement traits
	if movement_controller:
		var traits: MovementTraits = load("res://resources/movement_traits/wolf_movement.tres")
		movement_controller.load_traits(traits)

	# Connect to damage signal to coordinate pack
	damaged.connect(_on_pack_member_damaged)

	# Compose wolf-specific behaviors (PackBehavior for coordinated hunting)
	if ai_controller:
		ai_controller.add_behavior(PackBehavior.new())  # Priority 1: Pack tactics


func _emit_tactical_signals() -> void:
	"""Wolves emit presence for pack awareness"""
	if not TacticalMap or not is_inside_tree():
		return

	# Broadcast presence
	var sig = TacticalSignal.presence(global_position, owner_id, get_instance_id())
	sig.coordination_group_id = coordination_group_id
	TacticalMap.emit_signal_at(sig)


func _on_target_acquired(target: Node2D) -> void:
	"""Event-driven: emit TARGET_SPOTTED when new target acquired"""
	if TacticalMap and is_inside_tree():
		var sig = TacticalSignal.target_spotted(target.global_position, target, owner_id, get_instance_id())
		sig.coordination_group_id = coordination_group_id
		TacticalMap.emit_signal_at(sig)


func _on_near_death() -> void:
	"""Event-driven: call for pack support when critically wounded"""
	if TacticalMap and is_inside_tree():
		var sig = TacticalSignal.need_support(global_position, owner_id, get_instance_id())
		sig.coordination_group_id = coordination_group_id
		TacticalMap.emit_signal_at(sig)


func _on_pack_member_damaged(_amount: float, _source_id: int = -1) -> void:
	# When this wolf takes damage, ensure pack coordinates on the attacker
	if attack_target and is_instance_valid(attack_target):
		# Emit TARGET_SPOTTED signal so pack knows about threat
		if TacticalMap and is_inside_tree():
			var sig = TacticalSignal.target_spotted(attack_target.global_position, attack_target, owner_id, get_instance_id())
			sig.coordination_group_id = coordination_group_id
			TacticalMap.emit_signal_at(sig)


func _on_area_entered(area: Area2D) -> void:
	super._on_area_entered(area)

	# When we hit something, emit TARGET_SPOTTED
	if attack_target and is_instance_valid(attack_target):
		_on_target_acquired(attack_target)
