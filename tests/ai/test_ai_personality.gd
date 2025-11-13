extends GutTest

const AIPersonality = preload("res://scripts/core/ai/ai_personality.gd")

func test_create_default_personality():
	var personality: AIPersonality = AIPersonality.create_default()

	assert_not_null(personality, "Should create default personality")
	assert_eq(personality.boldness, 0.5, "Default boldness should be 0.5")
	assert_eq(personality.aggression, 0.5, "Default aggression should be 0.5")
	assert_eq(personality.awareness_radius, 200.0, "Default awareness radius should be 200")

func test_load_from_data():
	var ai_config: Dictionary = {
		"personality": {
			"boldness": 0.8,
			"aggression": 0.9,
			"intelligence": 0.6,
			"pack_instinct": 0.7,
			"stealth_preference": 0.5
		},
		"awareness_radius": 250.0,
		"ambush_distance": 100.0
	}

	var personality: AIPersonality = AIPersonality.from_data(ai_config)

	assert_eq(personality.boldness, 0.8, "Should load boldness from data")
	assert_eq(personality.aggression, 0.9, "Should load aggression from data")
	assert_eq(personality.intelligence, 0.6, "Should load intelligence from data")
	assert_eq(personality.pack_instinct, 0.7, "Should load pack_instinct from data")
	assert_eq(personality.stealth_preference, 0.5, "Should load stealth_preference from data")
	assert_eq(personality.awareness_radius, 250.0, "Should load awareness_radius from data")
	assert_eq(personality.ambush_distance, 100.0, "Should load ambush_distance from data")

func test_load_with_partial_data():
	var ai_config: Dictionary = {
		"personality": {
			"boldness": 0.3
		},
		"awareness_radius": 150.0
	}

	var personality: AIPersonality = AIPersonality.from_data(ai_config)

	assert_eq(personality.boldness, 0.3, "Should load specified boldness")
	assert_eq(personality.aggression, 0.5, "Should use default for missing aggression")
	assert_eq(personality.awareness_radius, 150.0, "Should load awareness_radius")

func test_load_with_empty_data():
	var ai_config: Dictionary = {}

	var personality: AIPersonality = AIPersonality.from_data(ai_config)

	assert_not_null(personality, "Should create personality with empty data")
	assert_eq(personality.boldness, 0.5, "Should use defaults with empty data")
	assert_eq(personality.awareness_radius, 200.0, "Should use default awareness_radius")
