extends GutTest

func test_entity_state_default_values():
	var state = EntityState.new()

	assert_eq(state.velocity, Vector2.ZERO, "Velocity should default to ZERO")
	assert_eq(state.health_percent, 1.0, "Health percent should default to 1.0")
	assert_eq(state.facing_direction, Vector2.DOWN, "Facing direction should default to DOWN")
	assert_eq(state.state_flags.size(), 0, "State flags should be empty")
	assert_eq(state.status_effects.size(), 0, "Status effects should be empty")

func test_add_flag():
	var state = EntityState.new()

	state.add_flag(EntityStateFlags.MOVING)

	assert_true(state.has_flag(EntityStateFlags.MOVING), "Should have MOVING flag")
	assert_eq(state.state_flags.size(), 1, "Should have one flag")

func test_add_flag_prevents_duplicates():
	var state = EntityState.new()

	state.add_flag(EntityStateFlags.ATTACKING)
	state.add_flag(EntityStateFlags.ATTACKING)

	assert_eq(state.state_flags.size(), 1, "Should not add duplicate flags")

func test_remove_flag():
	var state = EntityState.new()
	state.add_flag(EntityStateFlags.CASTING)

	state.remove_flag(EntityStateFlags.CASTING)

	assert_false(state.has_flag(EntityStateFlags.CASTING), "Should not have CASTING flag")
	assert_eq(state.state_flags.size(), 0, "Should have no flags")

func test_clear_flags():
	var state = EntityState.new()
	state.add_flag(EntityStateFlags.MOVING)
	state.add_flag(EntityStateFlags.ATTACKING)

	state.clear_flags()

	assert_eq(state.state_flags.size(), 0, "Should clear all flags")

func test_to_dict_serialization():
	var state = EntityState.new()
	state.velocity = Vector2(10.0, 20.0)
	state.health_percent = 0.5
	state.facing_direction = Vector2.LEFT
	state.add_flag(EntityStateFlags.MOVING)
	state.add_flag(EntityStateFlags.ATTACKING)
	state.status_effects.append("burning")

	var dict = state.to_dict()

	assert_eq(dict["velocity"], Vector2(10.0, 20.0), "Velocity should serialize")
	assert_eq(dict["health_percent"], 0.5, "Health percent should serialize")
	assert_eq(dict["facing_direction"], Vector2.LEFT, "Facing direction should serialize")
	assert_eq(dict["state_flags"].size(), 2, "State flags should serialize")
	assert_true(EntityStateFlags.MOVING in dict["state_flags"], "Should contain MOVING flag")
	assert_true(EntityStateFlags.ATTACKING in dict["state_flags"], "Should contain ATTACKING flag")
	assert_eq(dict["status_effects"].size(), 1, "Status effects should serialize")
	assert_true("burning" in dict["status_effects"], "Should contain burning effect")

func test_from_dict_deserialization():
	var dict = {
		"velocity": Vector2(5.0, 15.0),
		"health_percent": 0.75,
		"facing_direction": Vector2.RIGHT,
		"state_flags": [EntityStateFlags.DODGING, EntityStateFlags.BLOCKING],
		"status_effects": ["frozen", "poisoned"]
	}

	var state = EntityState.from_dict(dict)

	assert_eq(state.velocity, Vector2(5.0, 15.0), "Velocity should deserialize")
	assert_eq(state.health_percent, 0.75, "Health percent should deserialize")
	assert_eq(state.facing_direction, Vector2.RIGHT, "Facing direction should deserialize")
	assert_eq(state.state_flags.size(), 2, "State flags should deserialize")
	assert_true(state.has_flag(EntityStateFlags.DODGING), "Should have DODGING flag")
	assert_true(state.has_flag(EntityStateFlags.BLOCKING), "Should have BLOCKING flag")
	assert_eq(state.status_effects.size(), 2, "Status effects should deserialize")
	assert_true("frozen" in state.status_effects, "Should have frozen effect")
	assert_true("poisoned" in state.status_effects, "Should have poisoned effect")

func test_roundtrip_serialization():
	var original = EntityState.new()
	original.velocity = Vector2(3.0, 7.0)
	original.health_percent = 0.25
	original.facing_direction = Vector2.UP
	original.add_flag(EntityStateFlags.STUNNED)
	original.status_effects.append("burning")

	var dict = original.to_dict()
	var restored = EntityState.from_dict(dict)

	assert_eq(restored.velocity, original.velocity, "Velocity should roundtrip")
	assert_eq(restored.health_percent, original.health_percent, "Health percent should roundtrip")
	assert_eq(restored.facing_direction, original.facing_direction, "Facing direction should roundtrip")
	assert_eq(restored.state_flags, original.state_flags, "State flags should roundtrip")
	assert_eq(restored.status_effects, original.status_effects, "Status effects should roundtrip")

func test_from_dict_with_missing_fields():
	var dict = {}

	var state = EntityState.from_dict(dict)

	assert_eq(state.velocity, Vector2.ZERO, "Should use default velocity")
	assert_eq(state.health_percent, 1.0, "Should use default health percent")
	assert_eq(state.facing_direction, Vector2.DOWN, "Should use default facing direction")
	assert_eq(state.state_flags.size(), 0, "Should have empty flags")
	assert_eq(state.status_effects.size(), 0, "Should have empty effects")
