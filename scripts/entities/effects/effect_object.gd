extends BattlefieldObject
class_name EffectObject

# Effect type - temporary visual/damage effects that appear on the battlefield
# Effects have a limited lifetime and are automatically removed

signal effect_expired()

var lifetime: float = 1.0  # How long the effect lasts in seconds
var _elapsed_time: float = 0.0

func initialize(data: Dictionary, target_pos: Vector2) -> void:
	super.initialize(data, target_pos)
	lifetime = data.get("lifetime", 1.0)

func _process(delta: float) -> void:
	_elapsed_time += delta
	if _elapsed_time >= lifetime:
		effect_expired.emit()
		queue_free()
