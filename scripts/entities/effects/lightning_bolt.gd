extends EffectObject
class_name LightningBolt

# Signals
signal spell_cast(target_position: Vector2)
signal hit_target(target: Node2D)

# Lightning properties
const PLAYER_SIZE = 30.0  # Base player size for range calculation
const RANGE_MULTIPLIER = 6.0  # 6x player size
const FIRST_DAMAGE_TIME = 0.33  # 1/3 second
const SECOND_DAMAGE_TIME = 0.83  # 5/6 second (0.33 + 0.5)
const FIRST_DAMAGE = 1.0
const SECOND_DAMAGE = 3.0
const LINE_WIDTH_INITIAL = 3.0
const LINE_WIDTH_FINAL = 8.0

var cast_time: float = 0.0
var has_dealt_first_damage: bool = false
var has_dealt_second_damage: bool = false
var cast_direction: Vector2

func initialize(data: Dictionary, target_pos: Vector2) -> void:
	super.initialize(data, target_pos)
	target_position = target_pos
	cast_direction = (target_position - global_position).normalized()

	# Set visual type for lightning effect
	visual_type = "effect_lightning"
	entity_id = "lightning_%s" % _generate_unique_id()

	spell_cast.emit(target_pos)

	# Emit initial state
	_emit_lightning_state()

func _process(delta: float) -> void:
	super._process(delta)

	cast_time += delta

	# First damage at 0.33s
	if cast_time >= FIRST_DAMAGE_TIME and not has_dealt_first_damage:
		_deal_damage_to_targets(FIRST_DAMAGE)
		has_dealt_first_damage = true

	# Second damage at 0.83s with visual growth
	if cast_time >= SECOND_DAMAGE_TIME and not has_dealt_second_damage:
		_deal_damage_to_targets(SECOND_DAMAGE)
		_request_animation("grow", AnimationRequest.Priority.HIGH)
		has_dealt_second_damage = true

		# Disappear shortly after second damage
		await get_tree().create_timer(0.1).timeout
		queue_free()

func _deal_damage_to_targets(damage_amount: float) -> void:
	var combatants: Array[Node] = get_tree().get_nodes_in_group("combatants")

	for combatant: Node in combatants:
		if _is_target_in_line(combatant.global_position):
			combatant.take_damage(damage_amount, self)
			hit_target.emit(combatant)

func _is_target_in_line(target_pos: Vector2) -> bool:
	# Calculate if target is within the lightning bolt line
	var range: float = PLAYER_SIZE * RANGE_MULTIPLIER
	var line_end: Vector2 = global_position + cast_direction * range

	# Use point-to-line-segment distance
	var distance: float = _point_to_line_distance(target_pos, global_position, line_end)

	# Check if within line width and within range
	var is_within_width: bool = distance < LINE_WIDTH_FINAL
	var is_within_range: bool = global_position.distance_to(target_pos) < range

	# Also check if target is in front of caster (dot product)
	var to_target: Vector2 = (target_pos - global_position).normalized()
	var is_in_front: bool = cast_direction.dot(to_target) > 0.5

	return is_within_width and is_within_range and is_in_front

func _point_to_line_distance(point: Vector2, line_start: Vector2, line_end: Vector2) -> float:
	var line_vec: Vector2 = line_end - line_start
	var point_vec: Vector2 = point - line_start
	var line_len: float = line_vec.length()

	if line_len == 0:
		return point.distance_to(line_start)

	var t: float = clamp(point_vec.dot(line_vec) / (line_len * line_len), 0.0, 1.0)
	var projection: Vector2 = line_start + t * line_vec
	return point.distance_to(projection)

## Emit lightning state with direction info
func _emit_lightning_state() -> void:
	var state = EntityState.new()
	state.facing_direction = cast_direction
	state_changed.emit(state)
