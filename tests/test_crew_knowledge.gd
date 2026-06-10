extends GutTest

## Per-crew knowledge sets: a crew member's known_patterns restricts which
## tactical patterns knowledge queries can return. Empty = role baseline.
## This is the foundation of the crew training / instruction system.

func make_pilot_crew(known_patterns: Array) -> Dictionary:
	var crew = CrewData.create_crew_member(CrewData.Role.PILOT, 1.0)
	crew.known_patterns = known_patterns
	return crew

func test_baseline_crew_queries_full_role_doctrine():
	var results = TacticalKnowledgeSystem.query_pilot_knowledge("fighter mid range flank behind", 5)
	assert_gt(results.size(), 1, "Baseline (empty known_patterns) should retrieve from the full role set")

func test_known_patterns_restricts_retrieval():
	var all_results = TacticalKnowledgeSystem.query_pilot_knowledge("fighter mid range flank behind", 5)
	assert_gt(all_results.size(), 1, "Need multiple matching patterns for this test to be meaningful")

	var only_known = [all_results[0].pattern_id]
	var restricted = TacticalKnowledgeSystem.query_pilot_knowledge("fighter mid range flank behind", 5, only_known)

	assert_eq(restricted.size(), 1, "Crew should only retrieve patterns they know")
	assert_eq(restricted[0].pattern_id, only_known[0], "The retrieved pattern must be the known one")

func test_crew_without_relevant_knowledge_gets_nothing():
	var unrelated = ["fighter_capital_retreat"]
	var results = TacticalKnowledgeSystem.query_pilot_knowledge("fighter mid range flank behind", 5, unrelated)
	for r in results:
		assert_eq(r.pattern_id, "fighter_capital_retreat",
			"A crew member can never retrieve a pattern outside their known set")

func test_identical_pilots_with_different_knowledge_choose_differently():
	# BEHAVIOR (plan 06 done-criterion): two otherwise-identical elite pilots
	# in the same situation pick different maneuvers because they know
	# different doctrine.
	var situation = "fighter mid range flank behind position tactical"

	# Pilot A knows only the flanking doctrine; pilot B only the head-on charge.
	var knows_flank = make_pilot_crew(["fighter_flank_mid"])
	var knows_charge = make_pilot_crew(["fighter_approach_far"])

	var maneuver_a = FighterPilotAI._query_fighter_knowledge(situation, knows_flank)
	var maneuver_b = FighterPilotAI._query_fighter_knowledge(situation, knows_charge)

	assert_ne(maneuver_a, "", "Pilot A should find an actionable maneuver")
	assert_ne(maneuver_b, "", "Pilot B should find an actionable maneuver")
	assert_ne(maneuver_a, maneuver_b,
		"Identical pilots with different known_patterns must choose different maneuvers")

func test_query_cache_distinguishes_knowledge_sets():
	# Same situation string queried with different known sets must not leak
	# cached results across crew members.
	var situation = "fighter close range behind advantage dogfight"
	var full = TacticalKnowledgeSystem.query_pilot_knowledge(situation, 3)
	assert_gt(full.size(), 0, "Baseline query should match dogfight patterns")

	var restricted = TacticalKnowledgeSystem.query_pilot_knowledge(situation, 3, ["fighter_approach_far"])
	for r in restricted:
		assert_eq(r.pattern_id, "fighter_approach_far",
			"Restricted query after a baseline query must not return cached baseline results")
