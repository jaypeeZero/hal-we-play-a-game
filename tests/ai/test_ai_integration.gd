extends GutTest

const AIController = preload("res://scripts/core/ai/ai_controller.gd")
const AIPersonality = preload("res://scripts/core/ai/ai_personality.gd")
const CreatureObject = preload("res://scripts/entities/creatures/creature_object.gd")
const CreatureTypeData = preload("res://scripts/core/data/creature_type_data.gd")

func test_creature_initializes_with_ai_from_creature_type():
	var creature_type_data: CreatureTypeData = CreatureTypeData.new()
	var wolf_data: Dictionary = creature_type_data.get_creature("wolf")

	assert_false(wolf_data.is_empty(), "Wolf creature type should exist")
	assert_true(wolf_data.has("ai_config"), "Wolf should have ai_config")

	# Create creature with AI config
	var creature: CreatureObject = CreatureObject.new()
	add_child_autofree(creature)

	var creature_data: Dictionary = wolf_data.get("stats", {}).duplicate()
	creature_data["ai_config"] = wolf_data["ai_config"]
	creature_data["creature_type"] = "wolf"

	creature.initialize(creature_data, Vector2(100, 0))

	assert_not_null(creature.ai_controller, "Creature should have AI controller")
	assert_not_null(creature.ai_controller.personality, "AI controller should have personality")
	assert_eq(creature.ai_controller.personality.pack_instinct, 0.9, "Should load wolf pack instinct")

func test_ai_controller_makes_decisions():
	var personality: AIPersonality = AIPersonality.create_default()
	personality.boldness = 0.8

	var creature: CreatureObject = CreatureObject.new()
	add_child_autofree(creature)

	var data: Dictionary = {
		"speed": 100.0,
		"max_health": 50.0,
		"damage": 10.0,
		"collision_radius": 14.0
	}
	creature.initialize(data, Vector2(100, 0))

	var controller: AIController = AIController.new(creature, personality)

	# Initially should be idle (no enemies)
	controller.update(1.0)
	assert_eq(controller.current_behavior, "idle", "Should start in idle with no enemies")

func test_ai_switches_to_attack_when_enemy_nearby():
	var personality: AIPersonality = AIPersonality.create_default()
	personality.boldness = 0.9
	personality.min_confidence_to_attack = 0.4

	var creature: CreatureObject = CreatureObject.new()
	add_child_autofree(creature)
	creature.owner_id = 1
	creature.global_position = Vector2(0, 0)

	var data: Dictionary = {
		"speed": 100.0,
		"max_health": 50.0,
		"damage": 10.0,
		"collision_radius": 14.0
	}
	creature.initialize(data, Vector2(100, 0))

	# Create enemy creature
	var enemy: CreatureObject = CreatureObject.new()
	add_child_autofree(enemy)
	enemy.owner_id = 2
	enemy.global_position = Vector2(50, 0)  # Within awareness radius
	enemy.initialize(data, Vector2(0, 0))

	var controller: AIController = AIController.new(creature, personality)

	# Wait for AI to update and make decision
	await wait_frames(2)
	controller.update(1.0)  # Force update

	# Should detect enemy and switch to attack/seek
	assert_true(controller.current_behavior in ["attack", "seek"], "Should attack or seek enemy: got %s" % controller.current_behavior)
	assert_gt(controller.sensory_system.visible_enemies.size(), 0, "Should detect enemy")

func test_creature_with_ai_generates_steering_force():
	var personality: AIPersonality = AIPersonality.create_default()
	personality.boldness = 0.9

	var creature: CreatureObject = CreatureObject.new()
	add_child_autofree(creature)
	creature.owner_id = 1
	creature.global_position = Vector2(0, 0)

	var data: Dictionary = {
		"speed": 100.0,
		"max_health": 50.0,
		"damage": 10.0,
		"collision_radius": 14.0
	}
	creature.initialize(data, Vector2(100, 0))

	var controller: AIController = AIController.new(creature, personality)
	creature.ai_controller = controller

	# Create enemy
	var enemy: CreatureObject = CreatureObject.new()
	add_child_autofree(enemy)
	enemy.owner_id = 2
	enemy.global_position = Vector2(100, 0)
	enemy.initialize(data, Vector2(0, 0))

	await wait_frames(2)
	controller.update(1.0)

	# Get steering force from AI
	var steering: Vector2 = controller.get_steering_force()

	# Should have some steering force (not zero if seeking/attacking)
	if controller.current_behavior in ["attack", "seek"]:
		assert_ne(steering, Vector2.ZERO, "Should have steering force when seeking/attacking")
