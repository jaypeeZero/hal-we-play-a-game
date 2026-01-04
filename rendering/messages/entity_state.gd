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

## Per-section damage data for ships (armor and internals)
## Each element: {"section_id": String, "armor_percent": float, "internal_percent": float}
var section_damage: Array[Dictionary] = []

## Physicalized components for visual representation
## Each element: {
##   "component_id": String,
##   "component_type": String (engine, weapon, control, power),
##   "visual_type": String (for different component appearances),
##   "position_offset": Vector2,
##   "rotation": float (for turrets),
##   "status": String (operational, damaged, destroyed)
## }
var components: Array[Dictionary] = []

## Thrust state for visual effects
var is_main_engine_firing: bool = false  # True when forward thrust is active
var maneuvering_thrust_direction: Vector2 = Vector2.ZERO  # Direction of lateral/reverse thrust

## Wing formation visual
## Color.TRANSPARENT means not in a wing
var wing_color: Color = Color.TRANSPARENT

# ===== DEBUG VISUALIZATION =====
## Direction the pilot is trying to move towards (world-space direction vector)
## Vector2.ZERO means no direction to show
var debug_pilot_direction: Vector2 = Vector2.ZERO

## Leader identification number for squadron/wing leaders
## 0 means not a leader, positive number indicates leader index
var debug_leader_number: int = 0

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
		"status_effects": status_effects,
		"section_damage": section_damage,
		"components": components,
		"is_main_engine_firing": is_main_engine_firing,
		"maneuvering_thrust_direction": maneuvering_thrust_direction,
		"wing_color": wing_color,
		"debug_pilot_direction": debug_pilot_direction,
		"debug_leader_number": debug_leader_number
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

	var section_arr = data.get("section_damage", [])
	state.section_damage.assign(section_arr)

	var components_arr = data.get("components", [])
	state.components.assign(components_arr)

	state.is_main_engine_firing = data.get("is_main_engine_firing", false)
	state.maneuvering_thrust_direction = data.get("maneuvering_thrust_direction", Vector2.ZERO)
	state.wing_color = data.get("wing_color", Color.TRANSPARENT)
	state.debug_pilot_direction = data.get("debug_pilot_direction", Vector2.ZERO)
	state.debug_leader_number = data.get("debug_leader_number", 0)

	return state
