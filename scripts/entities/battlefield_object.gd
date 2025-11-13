extends IRenderable
class_name BattlefieldObject

# Base class for all objects that exist on the battlefield
# Subclasses: ProjectileObject, CreatureObject, EffectObject, TerrainObject
# Implements IRenderable interface - emits signals instead of creating visuals

signal reached_target()

# Signals inherited from IRenderable:
# - state_changed(state: EntityState)
# - animation_requested(request: AnimationRequest)

# Common properties
var damage: float = 0.0
var target_position: Vector2

# Renderable properties
var entity_id: String = ""
var visual_type: String = ""

func _ready() -> void:
	entity_id = _generate_unique_id()

func initialize(data: Dictionary, target_pos: Vector2) -> void:
	damage = data.get("damage", 0.0)
	target_position = target_pos

func is_magical() -> bool:
	# Override in subclasses to indicate if this is a magical attack
	return false

## IRenderable interface implementation
func get_entity_id() -> String:
	return entity_id

func get_visual_type() -> String:
	return visual_type

## Emit state whenever visual properties change
func _emit_state_update() -> void:
	var state = EntityState.new()
	state_changed.emit(state)

## Request animations instead of playing them
func _request_animation(anim_name: String, priority: AnimationRequest.Priority = AnimationRequest.Priority.NORMAL) -> void:
	var request = AnimationRequest.create(anim_name, priority)
	animation_requested.emit(request)

## Get collision radius from visual data for this entity's visual type
func get_collision_radius_for_visual_type() -> float:
	if not visual_type:
		return 0.0
	var visual_data = VisualBridgeAutoload.get_current_theme().get_visual_data(visual_type)
	return visual_data.get_collision_radius()

## Generate unique entity ID
static func _generate_unique_id() -> String:
	return "%d_%d" % [ResourceUID.create_id(), Time.get_ticks_msec()]
