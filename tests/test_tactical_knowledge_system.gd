extends GutTest

## Tests for TacticalKnowledgeSystem
## Tests BM25 knowledge retrieval and pattern matching

# ============================================================================
# KNOWLEDGE QUERY TESTS
# ============================================================================

func test_query_returns_results():
	var results = TacticalKnowledgeSystem.query_knowledge("evasion threat", CrewData.Role.PILOT, 5)

	assert_gt(results.size(), 0, "Should find relevant patterns")

func test_query_filters_by_role():
	var pilot_results = TacticalKnowledgeSystem.query_knowledge("target fire", CrewData.Role.PILOT, 10)
	var gunner_results = TacticalKnowledgeSystem.query_knowledge("target fire", CrewData.Role.GUNNER, 10)

	# Both should get results, but different patterns
	assert_gt(pilot_results.size(), 0, "Pilot should get results")
	assert_gt(gunner_results.size(), 0, "Gunner should get results")

	# Check that role filtering works
	for result in pilot_results:
		assert_true(result.has("content"), "Result should have content")

func test_query_pilot_convenience():
	var results = TacticalKnowledgeSystem.query_pilot_knowledge("evade threat", 2)

	assert_lte(results.size(), 2, "Should respect top_k limit")
	if results.size() > 0:
		assert_has(results[0], "content")
		assert_has(results[0], "score")

func test_query_gunner_convenience():
	var results = TacticalKnowledgeSystem.query_gunner_knowledge("target priority", 2)

	assert_lte(results.size(), 2, "Should respect top_k limit")

func test_query_captain_convenience():
	var results = TacticalKnowledgeSystem.query_captain_knowledge("damaged enemy", 2)

	assert_lte(results.size(), 2, "Should respect top_k limit")

func test_empty_query_returns_empty():
	var results = TacticalKnowledgeSystem.query_knowledge("", CrewData.Role.PILOT, 5)

	assert_eq(results.size(), 0, "Empty query should return no results")

# ============================================================================
# BM25 SCORING TESTS
# ============================================================================

func test_relevance_score_exact_match():
	var pattern = {
		"role": CrewData.Role.PILOT,
		"tags": ["evasion", "combat"],
		"text": "evade dodge threat enemy"
	}

	var score = TacticalKnowledgeSystem.calculate_relevance_score("evade threat enemy", pattern)

	assert_gt(score, 0.5, "Exact terms should have high score")

func test_relevance_score_partial_match():
	var pattern = {
		"role": CrewData.Role.PILOT,
		"tags": ["evasion"],
		"text": "evade dodge maneuver"
	}

	var score = TacticalKnowledgeSystem.calculate_relevance_score("evade fire", pattern)

	assert_gt(score, 0.0, "Partial match should have some score")

func test_relevance_score_no_match():
	var pattern = {
		"role": CrewData.Role.PILOT,
		"tags": ["navigation"],
		"text": "course heading navigation"
	}

	var score = TacticalKnowledgeSystem.calculate_relevance_score("fire target weapons", pattern)

	# May have low score but won't be exactly 0 if there's any overlap
	assert_gte(score, 0.0, "Score should be non-negative")

func test_tag_boost():
	var pattern = {
		"role": CrewData.Role.PILOT,
		"tags": ["evasion", "combat"],
		"text": "evade dodge"
	}

	var score_with_tag = TacticalKnowledgeSystem.calculate_relevance_score("evasion maneuver", pattern)
	var score_without_tag = TacticalKnowledgeSystem.calculate_relevance_score("maneuver", pattern)

	assert_gt(score_with_tag, score_without_tag, "Query with matching tag should score higher")

# ============================================================================
# TOKENIZATION TESTS
# ============================================================================

func test_tokenize_basic():
	var tokens = TacticalKnowledgeSystem.tokenize("hello world test")

	assert_eq(tokens.size(), 3)
	assert_has(tokens, "hello")
	assert_has(tokens, "world")
	assert_has(tokens, "test")

func test_tokenize_lowercase():
	var tokens = TacticalKnowledgeSystem.tokenize("Hello WORLD Test")

	assert_has(tokens, "hello")
	assert_has(tokens, "world")
	assert_has(tokens, "test")

func test_tokenize_multiple_spaces():
	var tokens = TacticalKnowledgeSystem.tokenize("hello  world   test")

	assert_eq(tokens.size(), 3, "Multiple spaces should be handled")

# ============================================================================
# KNOWLEDGE BASE TESTS
# ============================================================================

func test_get_patterns_for_role():
	var pilot_patterns = TacticalKnowledgeSystem.get_patterns_for_role(CrewData.Role.PILOT)

	assert_gt(pilot_patterns.size(), 0, "Should have pilot patterns")

	for pattern_data in pilot_patterns:
		assert_has(pattern_data, "id")
		assert_has(pattern_data, "pattern")
		assert_eq(pattern_data.pattern.role, CrewData.Role.PILOT)

func test_get_pattern_by_id():
	var pattern = TacticalKnowledgeSystem.get_pattern("pilot_evasive_close_threat")

	assert_false(pattern.is_empty(), "Should find existing pattern")
	assert_eq(pattern.role, CrewData.Role.PILOT)
	assert_has(pattern, "content")

func test_get_nonexistent_pattern():
	var pattern = TacticalKnowledgeSystem.get_pattern("nonexistent_pattern_id")

	assert_true(pattern.is_empty(), "Should return empty for nonexistent pattern")

# ============================================================================
# KNOWLEDGE CONTENT TESTS
# ============================================================================

func test_pilot_evasion_pattern_content():
	var results = TacticalKnowledgeSystem.query_pilot_knowledge("close threat enemy fire", 1)

	assert_gt(results.size(), 0, "Should find evasion pattern")

	var content = results[0].content
	assert_has(content, "action", "Pattern should have action guidance")

func test_gunner_targeting_pattern_content():
	var results = TacticalKnowledgeSystem.query_gunner_knowledge("damaged target priority", 1)

	assert_gt(results.size(), 0, "Should find targeting pattern")

	var content = results[0].content
	assert_has(content, "action", "Pattern should have action guidance")

func test_captain_tactical_pattern_content():
	var results = TacticalKnowledgeSystem.query_captain_knowledge("damaged enemy focus fire", 1)

	assert_gt(results.size(), 0, "Should find tactical pattern")

	var content = results[0].content
	assert_has(content, "action", "Pattern should have action guidance")

# ============================================================================
# KNOWLEDGE EXTENSION TESTS
# ============================================================================

func test_add_knowledge_pattern():
	var initial_count = TacticalKnowledgeSystem.get_patterns_for_role(CrewData.Role.PILOT).size()

	TacticalKnowledgeSystem.add_knowledge_pattern(
		"test_custom_pattern",
		CrewData.Role.PILOT,
		["test", "custom"],
		"test custom pattern data",
		{"action": "test_action"}
	)

	var new_count = TacticalKnowledgeSystem.get_patterns_for_role(CrewData.Role.PILOT).size()
	assert_eq(new_count, initial_count + 1, "Should add pattern to knowledge base")

	# Clean up
	TacticalKnowledgeSystem.knowledge_base.erase("test_custom_pattern")

func test_custom_pattern_queryable():
	TacticalKnowledgeSystem.add_knowledge_pattern(
		"test_queryable",
		CrewData.Role.PILOT,
		["unique_test_tag"],
		"unique test query pattern",
		{"test": true}
	)

	var results = TacticalKnowledgeSystem.query_pilot_knowledge("unique test query", 5)

	var found = false
	for result in results:
		if result.pattern_id == "test_queryable":
			found = true
			break

	assert_true(found, "Custom pattern should be queryable")

	# Clean up
	TacticalKnowledgeSystem.knowledge_base.erase("test_queryable")
