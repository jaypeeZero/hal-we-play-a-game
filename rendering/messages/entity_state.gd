class_name EntityState extends RefCounted

# ===== CORE PROPERTIES (Universal, never change) =====
## Current velocity (for auto-playing walk animation)
var velocity: Vector2 = Vector2.ZERO

## Health percentage (for visual feedback like color tinting)
var health_percent: float = 1.0

## Direction entity is facing (for directional sprites)
var facing_direction: Vector2 = Vector2.DOWN

# ===== EXTENSIBLE STATE FLAGS =====
## Behavioral state tags (moving, attacking, blocking, etc.)
## Use EntityStateFlags constants for type-safe flag names
var state_flags: Array[String] = []

## Visual status effects (burning, frozen, poisoned, etc.)
var status_effects: Array[String] = []

# ===== TYPE-SAFE HELPER METHODS =====
func has_flag(flag: String) -> bool:
	return flag in state_flags

func add_flag(flag: String) -> void:
	if flag not in state_flags:
		state_flags.append(flag)

func remove_flag(flag: String) -> void:
	state_flags.erase(flag)

func clear_flags() -> void:
	state_flags.clear()

# ===== SERIALIZATION =====
func to_dict() -> Dictionary:
	return {
		"velocity": velocity,
		"health_percent": health_percent,
		"facing_direction": facing_direction,
		"state_flags": state_flags,
		"status_effects": status_effects
	}

static func from_dict(data: Dictionary) -> EntityState:
	var state = EntityState.new()
	state.velocity = data.get("velocity", Vector2.ZERO)
	state.health_percent = data.get("health_percent", 1.0)
	state.facing_direction = data.get("facing_direction", Vector2.DOWN)

	var flags_arr = data.get("state_flags", [])
	state.state_flags.assign(flags_arr)

	var effects_arr = data.get("status_effects", [])
	state.status_effects.assign(effects_arr)

	return state
