extends CreatureObject
class_name KnightUnit

enum KnightColor {
	BLUE,
	BLACK,
	RED,
	GREEN
}

enum KnightState {
	CHARGING,
	SEARCHING,
	FIGHTING
}

var knight_color: KnightColor = KnightColor.BLUE
var knight_state: KnightState = KnightState.CHARGING
var charge_distance: float = 0.0
var charge_started: bool = false
var charge_range: float = 200.0
var search_timer: float = 0.0

# Constants for dramatic pause behavior
const SEARCH_PAUSE_TIME: float = 0.4
const CHARGE_COOLDOWN: float = 2.0
var charge_cooldown_timer: float = 0.0

func initialize(data: Dictionary, target_pos: Vector2, enemy_player: PlayerCharacter = null) -> void:
	super.initialize(data, target_pos, enemy_player)

	# Store the charge range from data (casting range)
	charge_range = data.get("casting_range", 200.0)

	# Randomly select knight color
	knight_color = randi() % 4

	# All knights start by charging
	knight_state = KnightState.CHARGING

	# Black knight changes ownership to enemy player
	if knight_color == KnightColor.BLACK:
		owner_id = enemy_player.player_id if enemy_player else -1

	charge_started = false

func _process(delta: float) -> void:
	# Update charge cooldown
	if charge_cooldown_timer > 0:
		charge_cooldown_timer -= delta

	# State machine
	match knight_state:
		KnightState.CHARGING:
			if not charge_started:
				charge_started = true
				charge_distance = 0.0

			charge_distance += speed * delta

			# Charge for the specified distance
			if charge_distance >= charge_range:
				# Red and Green knights disappear after charging
				if knight_color == KnightColor.RED or knight_color == KnightColor.GREEN:
					_on_charge_complete_despawn()
					return
				# Blue and Black knights search for new targets
				else:
					_on_charge_complete_transition()

		KnightState.SEARCHING:
			search_timer -= delta
			if search_timer <= 0:
				var new_target = _find_nearest_enemy()
				if new_target and charge_cooldown_timer <= 0:
					# Found a target and can charge again - initiate new charge
					attack_target = new_target
					knight_state = KnightState.CHARGING
					charge_started = false
					charge_distance = 0.0
					charge_cooldown_timer = CHARGE_COOLDOWN

					# Emit charge signal for visual feedback
					if ai_controller:
						ai_controller.charge_initiated.emit(global_position)
				else:
					# No target or on cooldown - switch to normal fighting
					knight_state = KnightState.FIGHTING

		KnightState.FIGHTING:
			# Normal creature behavior - handled by super._process()
			pass

	super._process(delta)

func _calculate_steering_force() -> Vector2:
	match knight_state:
		KnightState.CHARGING:
			# During charge, move in initial direction at full speed
			if direction != Vector2.ZERO:
				return direction * speed
			return Vector2.ZERO
		KnightState.SEARCHING:
			# Stand still while searching for targets (dramatic pause)
			return Vector2.ZERO
		KnightState.FIGHTING:
			# Normal creature behavior
			return super._calculate_steering_force()
		_:
			return Vector2.ZERO

func _on_area_entered(area: Area2D) -> void:
	# During charge, still deal damage
	super._on_area_entered(area)

	# Event-driven: broadcast collision during charge
	if knight_state == KnightState.CHARGING and attack_target:
		_on_charge_collision(attack_target)
		# Don't stop charging on collision - continue to full distance


func _on_charge_collision(target: Node2D) -> void:
	"""Event: Knight collided with target during charge"""
	if TacticalMap and is_inside_tree():
		var sig = TacticalSignal.attacking(target.global_position, target, owner_id, get_instance_id())
		sig.coordination_group_id = coordination_group_id
		TacticalMap.emit_signal_at(sig)


func _on_charge_complete_transition() -> void:
	"""Event: Knight finished charge, entering search pause"""
	knight_state = KnightState.SEARCHING
	search_timer = SEARCH_PAUSE_TIME
	# Emit tactical signal for visual feedback (knight is searching)
	if TacticalMap and is_inside_tree():
		var sig = TacticalSignal.new()
		sig.signal_type = TacticalSignal.Type.PRESENCE
		sig.position = global_position
		sig.owner_id = owner_id
		sig.coordination_group_id = coordination_group_id
		sig.emitter_id = get_instance_id()
		sig.strength = 1.0
		sig.radius = 50.0
		sig.duration = SEARCH_PAUSE_TIME
		TacticalMap.emit_signal_at(sig)


func _on_charge_complete_despawn() -> void:
	"""Event: Kamikaze knight finished charge and is despawning"""
	if TacticalMap and is_inside_tree():
		# Emit signal so allies know this unit is gone
		var sig = TacticalSignal.new()
		sig.signal_type = TacticalSignal.Type.KILL_CONFIRMED
		sig.position = global_position
		sig.owner_id = owner_id
		sig.coordination_group_id = coordination_group_id
		sig.emitter_id = get_instance_id()
		sig.strength = 0.5
		sig.radius = 100.0
		sig.duration = 1.0
		TacticalMap.emit_signal_at(sig)

	queue_free()


func _find_nearest_enemy() -> Node2D:
	"""Find the nearest enemy for charging"""
	if not ai_controller or not ai_controller.sensory_system:
		return null

	return ai_controller.sensory_system.get_nearest_enemy()
