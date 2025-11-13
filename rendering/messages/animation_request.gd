class_name AnimationRequest extends RefCounted

## Priority levels (higher priority can interrupt lower)
enum Priority {
	LOW = 0,        # Idle animations
	NORMAL = 1,     # Movement
	HIGH = 2,       # Attacks, spells
	CRITICAL = 3    # Death (cannot be interrupted)
}

## Name of animation to play
var animation_name: String = ""

## Blend time when transitioning (seconds)
var blend_time: float = 0.1

## Priority of this animation
var priority: Priority = Priority.NORMAL

## Can this animation be interrupted by higher priority?
var interruptible: bool = true

## Factory method for common cases
static func create(anim_name: String, pri: Priority = Priority.NORMAL) -> AnimationRequest:
	var request = AnimationRequest.new()
	request.animation_name = anim_name
	request.priority = pri
	request.interruptible = (pri != Priority.CRITICAL)
	return request

## Serialize for debugging
func to_dict() -> Dictionary:
	return {
		"animation_name": animation_name,
		"blend_time": blend_time,
		"priority": Priority.keys()[priority],
		"interruptible": interruptible
	}
