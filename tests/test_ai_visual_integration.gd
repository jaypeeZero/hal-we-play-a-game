extends GutTest

var creature: CreatureObject
var received_states: Array[EntityState] = []

func before_each():
	creature = autofree(CreatureObject.new())
	received_states.clear()
	add_child_autofree(creature)

func test_ai_signals_connected_when_ai_configured():
	var data = _get_creature_data_with_ai()
	creature.initialize(data, Vector2(100, 100))

	assert_not_null(creature.ai_controller, "AI controller should exist")
	assert_true(creature.ai_controller.tactical_action.is_connected(creature._on_ai_tactical_action), "tactical_action signal should be connected")
	assert_true(creature.ai_controller.stealth_mode_changed.is_connected(creature._on_ai_stealth_mode_changed), "stealth_mode_changed signal should be connected")
	assert_true(creature.ai_controller.charge_initiated.is_connected(creature._on_ai_charge_initiated), "charge_initiated signal should be connected")
	assert_true(creature.ai_controller.ambush_triggered.is_connected(creature._on_ai_ambush_triggered), "ambush_triggered signal should be connected")
	assert_true(creature.ai_controller.behavior_changed.is_connected(creature._on_ai_behavior_changed), "behavior_changed signal should be connected")

func test_ai_signals_not_connected_without_ai():
	var data = _get_creature_data_without_ai()
	creature.initialize(data, Vector2(100, 100))

	assert_null(creature.ai_controller, "AI controller should not exist")

func test_stealth_mode_sets_stealth_flag():
	var data = _get_creature_data_with_ai()
	creature.initialize(data, Vector2(100, 100))
	creature.state_changed.connect(_on_state_changed)

	creature.ai_controller.stealth_mode_changed.emit(true)

	assert_eq(creature._current_ai_state_flag, EntityStateFlags.STEALTH, "Stealth flag should be set")
	assert_gt(received_states.size(), 0, "State should be emitted")
	assert_true(received_states[-1].has_flag(EntityStateFlags.STEALTH), "EntityState should contain STEALTH flag")

func test_stealth_mode_clears_stealth_flag():
	var data = _get_creature_data_with_ai()
	creature.initialize(data, Vector2(100, 100))
	creature.state_changed.connect(_on_state_changed)

	creature.ai_controller.stealth_mode_changed.emit(true)
	creature.ai_controller.stealth_mode_changed.emit(false)

	assert_eq(creature._current_ai_state_flag, "", "Stealth flag should be cleared")

func test_tactical_action_stealth_sets_flag():
	var data = _get_creature_data_with_ai()
	creature.initialize(data, Vector2(100, 100))
	creature.state_changed.connect(_on_state_changed)

	creature.ai_controller.tactical_action.emit("stealth_activated", Vector2.ZERO)

	assert_eq(creature._current_ai_state_flag, EntityStateFlags.STEALTH)

func test_tactical_action_fleeing_sets_flag():
	var data = _get_creature_data_with_ai()
	creature.initialize(data, Vector2(100, 100))
	creature.state_changed.connect(_on_state_changed)

	creature.ai_controller.tactical_action.emit("fleeing", Vector2.ZERO)

	assert_eq(creature._current_ai_state_flag, EntityStateFlags.FLEEING)

func test_tactical_action_charge_sets_flag():
	var data = _get_creature_data_with_ai()
	creature.initialize(data, Vector2(100, 100))
	creature.state_changed.connect(_on_state_changed)

	creature.ai_controller.tactical_action.emit("charge_initiated", Vector2.ZERO)

	assert_eq(creature._current_ai_state_flag, EntityStateFlags.CHARGING_ATTACK)

func test_tactical_action_pack_sets_flag():
	var data = _get_creature_data_with_ai()
	creature.initialize(data, Vector2(100, 100))
	creature.state_changed.connect(_on_state_changed)

	creature.ai_controller.tactical_action.emit("pack_coordinating", Vector2.ZERO)

	assert_eq(creature._current_ai_state_flag, EntityStateFlags.PACK_COORDINATING)

func test_tactical_action_swarm_sets_flag():
	var data = _get_creature_data_with_ai()
	creature.initialize(data, Vector2(100, 100))
	creature.state_changed.connect(_on_state_changed)

	creature.ai_controller.tactical_action.emit("swarm_attacking", Vector2.ZERO)

	assert_eq(creature._current_ai_state_flag, EntityStateFlags.SWARM_ATTACKING)

func test_tactical_action_ambush_sets_flag():
	var data = _get_creature_data_with_ai()
	creature.initialize(data, Vector2(100, 100))
	creature.state_changed.connect(_on_state_changed)

	creature.ai_controller.tactical_action.emit("ambush_triggered", Vector2.ZERO)

	assert_eq(creature._current_ai_state_flag, EntityStateFlags.AMBUSHING)

func test_charge_initiated_sets_flag():
	var data = _get_creature_data_with_ai()
	creature.initialize(data, Vector2(100, 100))
	creature.state_changed.connect(_on_state_changed)

	creature.ai_controller.charge_initiated.emit(Vector2.RIGHT)

	assert_eq(creature._current_ai_state_flag, EntityStateFlags.CHARGING_ATTACK)

func test_ambush_triggered_sets_flag():
	var data = _get_creature_data_with_ai()
	creature.initialize(data, Vector2(100, 100))
	var target = autofree(Node2D.new())
	creature.state_changed.connect(_on_state_changed)

	creature.ai_controller.ambush_triggered.emit(target)

	assert_eq(creature._current_ai_state_flag, EntityStateFlags.AMBUSHING)

func test_behavior_changed_to_idle_clears_flag():
	var data = _get_creature_data_with_ai()
	creature.initialize(data, Vector2(100, 100))
	creature.state_changed.connect(_on_state_changed)

	creature.ai_controller.tactical_action.emit("fleeing", Vector2.ZERO)
	assert_eq(creature._current_ai_state_flag, EntityStateFlags.FLEEING)

	creature.ai_controller.behavior_changed.emit("idle")

	assert_eq(creature._current_ai_state_flag, "", "Flag should be cleared on idle")

func test_behavior_changed_to_seek_clears_flag():
	var data = _get_creature_data_with_ai()
	creature.initialize(data, Vector2(100, 100))
	creature.state_changed.connect(_on_state_changed)

	creature.ai_controller.tactical_action.emit("pack_coordinating", Vector2.ZERO)
	creature.ai_controller.behavior_changed.emit("seek")

	assert_eq(creature._current_ai_state_flag, "", "Flag should be cleared on seek")

func test_behavior_changed_to_attack_clears_flag():
	var data = _get_creature_data_with_ai()
	creature.initialize(data, Vector2(100, 100))
	creature.state_changed.connect(_on_state_changed)

	creature.ai_controller.tactical_action.emit("swarm_attacking", Vector2.ZERO)
	creature.ai_controller.behavior_changed.emit("attack")

	assert_eq(creature._current_ai_state_flag, "", "Flag should be cleared on attack")

func test_entity_state_includes_ai_flag():
	var data = _get_creature_data_with_ai()
	creature.initialize(data, Vector2(100, 100))
	creature.state_changed.connect(_on_state_changed)

	creature.ai_controller.stealth_mode_changed.emit(true)

	var state = received_states[-1]
	assert_true(state.has_flag(EntityStateFlags.STEALTH), "EntityState should have STEALTH flag")

func test_entity_state_includes_movement_and_ai_flags():
	var data = _get_creature_data_with_ai()
	creature.initialize(data, Vector2(100, 100))
	creature.state_changed.connect(_on_state_changed)
	creature.velocity = Vector2(100, 0)

	creature.ai_controller.tactical_action.emit("fleeing", Vector2.ZERO)

	var state = received_states[-1]
	assert_true(state.has_flag(EntityStateFlags.MOVING), "EntityState should have MOVING flag")
	assert_true(state.has_flag(EntityStateFlags.FLEEING), "EntityState should have FLEEING flag")

func _on_state_changed(state: EntityState):
	received_states.append(state)

func _get_creature_data_with_ai() -> Dictionary:
	return {
		"speed": 100.0,
		"max_health": 50.0,
		"collision_radius": 10.0,
		"creature_type": "test_creature",
		"ai_config": {
			"personality": {
				"boldness": 0.5,
				"aggression": 0.5
			},
			"awareness_radius": 200.0
		}
	}

func _get_creature_data_without_ai() -> Dictionary:
	return {
		"speed": 100.0,
		"max_health": 50.0,
		"collision_radius": 10.0,
		"creature_type": "test_creature"
	}

func test_debug_overlay_gets_ai_info():
	var data = _get_creature_data_with_ai()
	creature.initialize(data, Vector2(100, 100))

	var debug_info = creature.ai_controller.get_debug_info()

	assert_not_null(debug_info, "Debug info should be returned")
	assert_true("behavior" in debug_info, "Debug info should contain behavior")
	assert_true("awareness_radius" in debug_info, "Debug info should contain awareness_radius")
	assert_true("confidence" in debug_info, "Debug info should contain confidence")
	assert_true("fear" in debug_info, "Debug info should contain fear")
	assert_true("aggression" in debug_info, "Debug info should contain aggression")
	assert_true("visible_enemies" in debug_info, "Debug info should contain visible_enemies")
	assert_true("visible_allies" in debug_info, "Debug info should contain visible_allies")

func test_debug_overlay_handles_creature_without_ai():
	var data = _get_creature_data_without_ai()
	creature.initialize(data, Vector2(100, 100))

	assert_null(creature.ai_controller, "Creature should not have AI controller")
	# Debug overlay should handle this gracefully without crashing
