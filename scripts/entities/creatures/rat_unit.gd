extends CreatureObject
class_name RatUnit

## Rat uses SwarmBehavior for overwhelming numbers
## Composes behaviors instead of hardcoding

const SwarmBehavior = preload("res://scripts/core/ai/behaviors/swarm_behavior.gd")
const FleeBehavior = preload("res://scripts/core/ai/behaviors/flee_behavior.gd")

# Fleeing thresholds
const FLEEING_HEALTH_THRESHOLD = 0.5  # Below 50% health, flee at full speed
const FLEE_SPEED = 150.0

func initialize(data: Dictionary, target_pos: Vector2, enemy_player: PlayerCharacter = null) -> void:
	super.initialize(data, target_pos, enemy_player)

	# Configure thresholds
	near_death_threshold = FLEEING_HEALTH_THRESHOLD

	# Load rat movement traits (hopping behavior)
	if movement_controller:
		var traits: MovementTraits = load("res://resources/movement_traits/rat_movement.tres")
		movement_controller.load_traits(traits)

	# Compose rat-specific behaviors (SwarmBehavior for overwhelming numbers)
	if ai_controller:
		ai_controller.add_behavior(FleeBehavior.new())   # Priority 1: Flee when panicked
		ai_controller.add_behavior(SwarmBehavior.new())  # Priority 2: Swarm tactics

func _process(delta: float) -> void:
	# Update fleeing state based on health
	if movement_controller and health_component:
		var health_percent: float = health_component.health / health_component.max_health
		movement_controller.behavior_modulator.is_fleeing = (health_percent < FLEEING_HEALTH_THRESHOLD)

	# Continue normal processing
	super._process(delta)


func _emit_tactical_signals() -> void:
	"""Rats emit PRESENCE signals for simple swarm coordination"""
	if not TacticalMap or not is_inside_tree():
		return

	# Always broadcast presence
	var sig = TacticalSignal.presence(global_position, owner_id, get_instance_id())
	sig.coordination_group_id = coordination_group_id
	TacticalMap.emit_signal_at(sig)


func _on_near_death() -> void:
	"""Rats respond to near-death by panicking and spreading fear"""
	if TacticalMap and is_inside_tree():
		var sig = TacticalSignal.panic(global_position, owner_id, get_instance_id())
		sig.coordination_group_id = coordination_group_id
		TacticalMap.emit_signal_at(sig)
