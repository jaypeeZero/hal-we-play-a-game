extends GutTest

const EmotionalState = preload("res://scripts/core/ai/emotional_state.gd")
const AIPersonality = preload("res://scripts/core/ai/ai_personality.gd")

func test_emotional_state_initialization():
	var personality: AIPersonality = AIPersonality.create_default()
	var emotional_state: EmotionalState = EmotionalState.new(personality)

	assert_not_null(emotional_state, "Should create emotional state")
	assert_eq(emotional_state.confidence, 0.5, "Initial confidence should be 0.5")
	assert_eq(emotional_state.fear, 0.0, "Initial fear should be 0.0")
	assert_eq(emotional_state.morale, 0.5, "Initial morale should be 0.5")

func test_confidence_increases_with_allies():
	var personality: AIPersonality = AIPersonality.create_default()
	personality.morale_bonus_per_ally = 0.2
	var emotional_state: EmotionalState = EmotionalState.new(personality)

	var context: Dictionary = {
		"ally_count": 3,
		"enemy_count": 1,
		"health_percent": 1.0,
		"threat_level": 0.0
	}

	emotional_state.update(context)

	assert_gt(emotional_state.morale, 0.5, "Morale should increase with allies")
	assert_gt(emotional_state.confidence, 0.5, "Confidence should increase with allies")

func test_fear_increases_at_low_health():
	var personality: AIPersonality = AIPersonality.create_default()
	personality.panic_threshold = 0.3
	var emotional_state: EmotionalState = EmotionalState.new(personality)

	var context: Dictionary = {
		"ally_count": 0,
		"enemy_count": 1,
		"health_percent": 0.2,  # Below panic threshold
		"threat_level": 0.5
	}

	emotional_state.update(context)

	assert_gt(emotional_state.fear, 0.0, "Fear should increase at low health")
	assert_true(emotional_state.should_flee(), "Should want to flee at low health")

func test_should_attack_when_confident():
	var personality: AIPersonality = AIPersonality.create_default()
	personality.min_confidence_to_attack = 0.6
	personality.morale_bonus_per_ally = 0.3
	var emotional_state: EmotionalState = EmotionalState.new(personality)

	var context: Dictionary = {
		"ally_count": 2,
		"enemy_count": 1,
		"health_percent": 1.0,
		"threat_level": 0.0
	}

	emotional_state.update(context)

	assert_true(emotional_state.should_attack(), "Should attack when confident")
	assert_false(emotional_state.should_flee(), "Should not flee when confident")

func test_should_flee_when_panicked():
	var personality: AIPersonality = AIPersonality.create_default()
	personality.panic_threshold = 0.4
	var emotional_state: EmotionalState = EmotionalState.new(personality)

	var context: Dictionary = {
		"ally_count": 0,
		"enemy_count": 3,
		"health_percent": 0.2,
		"threat_level": 0.8
	}

	emotional_state.update(context)

	assert_true(emotional_state.should_flee(), "Should flee when panicked")
	assert_false(emotional_state.should_attack(), "Should not attack when panicked")
	assert_true(emotional_state.is_panicked(), "Should be in panicked state")
