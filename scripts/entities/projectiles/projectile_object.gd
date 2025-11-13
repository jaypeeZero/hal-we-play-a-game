extends BattlefieldObject
class_name ProjectileObject

const CollisionUtils = preload("res://scripts/core/utilities/collision_utils.gd")

# Signals
signal spell_cast(target_position: Vector2)
signal hit_target(target: Node2D)
signal exploded(position: Vector2)

# Movement properties (from old MovingEntity)
var speed: float = 100.0
var direction: Vector2 = Vector2.ZERO

# Lifetime management (from old MovingEntity)
const MAX_LIFETIME = 10.0
var lifetime: float = 0.0
const PROJECTILE_ARRIVAL_THRESHOLD = 5.0

# Projectile-specific properties
var should_explode: bool = false
var caster: Node2D = null
var hit_box: Area2D
var projectile_type_name: String = "generic"

func initialize(data: Dictionary, target_pos: Vector2, projectile_caster: Node2D = null) -> void:
	caster = projectile_caster
	super.initialize(data, target_pos)
	speed = data.get("speed", 100.0)
	should_explode = data.get("should_explode", false)

	# Set visual type based on projectile data
	projectile_type_name = data.get("projectile_type", "generic")
	visual_type = "projectile_%s" % projectile_type_name
	entity_id = "projectile_%s" % _generate_unique_id()

	_setup_collision(data)
	_update_direction()
	spell_cast.emit(target_pos)

	# Emit initial state
	_emit_projectile_state()

func _setup_collision(data: Dictionary) -> void:
	hit_box = Area2D.new()
	hit_box.name = "HitBox"
	add_child(hit_box)

	var collision_shape: CollisionShape2D = CollisionShape2D.new()
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = get_collision_radius_for_visual_type()
	collision_shape.shape = shape
	hit_box.add_child(collision_shape)

	hit_box.area_entered.connect(_on_area_entered)

func _process(delta: float) -> void:
	# Lifetime limit
	lifetime += delta
	if lifetime > MAX_LIFETIME:
		queue_free()
		return

	# Move toward target
	if direction != Vector2.ZERO:
		_move_toward_target(delta)

func _move_toward_target(delta: float) -> void:
	global_position += direction * speed * delta

	# Emit state (position changes every frame)
	_emit_projectile_state()

	# Check if reached target
	if _has_reached_target():
		_on_reached_target()

func _update_direction() -> void:
	# Calculate direction after entity position is finalized
	direction = (target_position - global_position).normalized()

func _has_reached_target() -> bool:
	return global_position.distance_to(target_position) < PROJECTILE_ARRIVAL_THRESHOLD

func _on_reached_target() -> void:
	# Projectile disappears on arrival
	if should_explode:
		_create_explosion()
	queue_free()

func _on_area_entered(area: Area2D) -> void:
	if area.name == "HitBox":
		var target: Node2D = CollisionUtils.get_valid_target(area, hit_box, [caster])
		if target:
			if target.has_method("take_damage"):
				target.call("take_damage", damage, self)
			hit_target.emit(target)
			if should_explode:
				_create_explosion()
			queue_free()

func _create_explosion() -> void:
	# Request explosion animation
	_request_animation("explode", AnimationRequest.Priority.HIGH)
	exploded.emit(global_position)

## Emit projectile state with velocity info
func _emit_projectile_state() -> void:
	var state = EntityState.new()
	state.velocity = direction * speed if direction else Vector2.ZERO
	state_changed.emit(state)
