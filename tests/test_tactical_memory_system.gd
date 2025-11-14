extends GutTest

## Tests for TacticalMemorySystem
## Tests crew memory updates, decision tracking, and situation summaries

# ============================================================================
# MEMORY UPDATE TESTS
# ============================================================================

func test_update_crew_memory_with_no_events():
	var crew = CrewData.create_crew_member(CrewData.Role.PILOT, 0.5)
	crew.assigned_to = "ship_1"

	var updated = TacticalMemorySystem.update_crew_memory(crew, [], 0.0)

	assert_eq(updated.awareness.tactical_memory.recent_events.size(), 0)
	assert_not_null(updated.awareness.tactical_memory.current_situation)

func test_update_crew_memory_with_events():
	var crew = CrewData.create_crew_member(CrewData.Role.PILOT, 0.5)
	crew.assigned_to = "ship_1"

	var events = [
		{"type": "damage_dealt", "data": {"victim_id": "ship_1"}},
		{"type": "projectile_fired", "data": {"source_id": "ship_2"}}
	]

	var updated = TacticalMemorySystem.update_crew_memory(crew, events, 1.0)

	assert_eq(updated.awareness.tactical_memory.recent_events.size(), 2)

func test_recent_events_limited():
	var crew = CrewData.create_crew_member(CrewData.Role.PILOT, 0.5)
	crew.assigned_to = "ship_1"

	# Create more events than MAX_RECENT_EVENTS
	var many_events = []
	for i in range(15):
		many_events.append({"type": "test_event", "data": {"index": i}})

	var updated = TacticalMemorySystem.update_crew_memory(crew, many_events, 1.0)

	assert_lte(
		updated.awareness.tactical_memory.recent_events.size(),
		TacticalMemorySystem.MAX_RECENT_EVENTS,
		"Should not exceed max recent events"
	)

func test_update_all_crew_memory():
	var crew_list = [
		CrewData.create_crew_member(CrewData.Role.PILOT, 0.5),
		CrewData.create_crew_member(CrewData.Role.GUNNER, 0.5)
	]

	var events = [{"type": "test", "data": {}}]

	var updated_list = TacticalMemorySystem.update_all_crew_memory(crew_list, events, 1.0)

	assert_eq(updated_list.size(), 2)
	for crew in updated_list:
		assert_has(crew.awareness.tactical_memory, "recent_events")
		assert_has(crew.awareness.tactical_memory, "current_situation")

# ============================================================================
# DECISION OUTCOME TRACKING TESTS
# ============================================================================

func test_record_successful_decision():
	var crew = CrewData.create_crew_member(CrewData.Role.PILOT, 0.5)
	var decision = {"type": "maneuver", "subtype": "evade"}

	var updated = TacticalMemorySystem.record_decision_outcome(crew, decision, true)

	assert_eq(updated.awareness.tactical_memory.successful_tactics.get("maneuver_evade", 0), 1)

func test_record_failed_decision():
	var crew = CrewData.create_crew_member(CrewData.Role.PILOT, 0.5)
	var decision = {"type": "maneuver", "subtype": "evade"}

	var updated = TacticalMemorySystem.record_decision_outcome(crew, decision, false)

	assert_eq(updated.awareness.tactical_memory.failed_tactics.get("maneuver_evade", 0), 1)

func test_record_multiple_outcomes():
	var crew = CrewData.create_crew_member(CrewData.Role.PILOT, 0.5)
	var decision = {"type": "maneuver", "subtype": "zigzag"}

	# 3 successes
	crew = TacticalMemorySystem.record_decision_outcome(crew, decision, true)
	crew = TacticalMemorySystem.record_decision_outcome(crew, decision, true)
	crew = TacticalMemorySystem.record_decision_outcome(crew, decision, true)

	# 1 failure
	crew = TacticalMemorySystem.record_decision_outcome(crew, decision, false)

	assert_eq(crew.awareness.tactical_memory.successful_tactics.get("maneuver_zigzag", 0), 3)
	assert_eq(crew.awareness.tactical_memory.failed_tactics.get("maneuver_zigzag", 0), 1)

func test_get_tactic_success_rate():
	var crew = CrewData.create_crew_member(CrewData.Role.PILOT, 0.5)
	var decision = {"type": "fire", "subtype": "burst"}

	# 7 successes, 3 failures = 70% success rate
	for i in range(7):
		crew = TacticalMemorySystem.record_decision_outcome(crew, decision, true)
	for i in range(3):
		crew = TacticalMemorySystem.record_decision_outcome(crew, decision, false)

	var success_rate = TacticalMemorySystem.get_tactic_success_rate(crew, "fire_burst")

	assert_eq(success_rate, 0.7, "Should calculate 70% success rate")

func test_get_tactic_success_rate_unknown():
	var crew = CrewData.create_crew_member(CrewData.Role.PILOT, 0.5)

	var success_rate = TacticalMemorySystem.get_tactic_success_rate(crew, "unknown_tactic")

	assert_eq(success_rate, 0.5, "Unknown tactic should default to 50%")

func test_has_tried_tactic():
	var crew = CrewData.create_crew_member(CrewData.Role.PILOT, 0.5)
	var decision = {"type": "maneuver", "subtype": "evade"}

	assert_false(TacticalMemorySystem.has_tried_tactic(crew, "maneuver_evade"))

	crew = TacticalMemorySystem.record_decision_outcome(crew, decision, true)

	assert_true(TacticalMemorySystem.has_tried_tactic(crew, "maneuver_evade"))

# ============================================================================
# SITUATION SUMMARY TESTS
# ============================================================================

func test_generate_situation_summary_basic():
	var crew = CrewData.create_crew_member(CrewData.Role.PILOT, 0.5)

	var summary = TacticalMemorySystem.generate_situation_summary(crew)

	assert_not_null(summary)
	assert_typeof(summary, TYPE_STRING)
	assert_true(summary.contains("piloting") or summary.contains("navigation"))

func test_generate_situation_summary_with_threats():
	var crew = CrewData.create_crew_member(CrewData.Role.PILOT, 0.5)
	crew.awareness.threats = [
		{"id": "enemy_1", "type": "ship", "_threat_priority": 180.0}
	]

	var summary = TacticalMemorySystem.generate_situation_summary(crew)

	assert_true(summary.contains("threat") or summary.contains("close") or summary.contains("enemy"))

func test_generate_situation_summary_with_opportunities():
	var crew = CrewData.create_crew_member(CrewData.Role.GUNNER, 0.5)
	crew.awareness.opportunities = [
		{"id": "enemy_1", "type": "ship", "status": "damaged", "_opportunity_score": 150.0}
	]

	var summary = TacticalMemorySystem.generate_situation_summary(crew)

	assert_true(summary.contains("damaged") or summary.contains("enemy") or summary.contains("target"))

func test_generate_situation_summary_role_specific():
	var pilot = CrewData.create_crew_member(CrewData.Role.PILOT, 0.5)
	var captain = CrewData.create_crew_member(CrewData.Role.CAPTAIN, 0.5)

	var pilot_summary = TacticalMemorySystem.generate_situation_summary(pilot)
	var captain_summary = TacticalMemorySystem.generate_situation_summary(captain)

	# Summaries should have role-specific keywords
	assert_true(pilot_summary.contains("piloting") or pilot_summary.contains("navigation"))
	assert_true(captain_summary.contains("tactics") or captain_summary.contains("coordination"))

# ============================================================================
# TACTIC ID EXTRACTION TESTS
# ============================================================================

func test_get_tactic_id_from_decision():
	var decision = {"type": "maneuver", "subtype": "evade"}

	var tactic_id = TacticalMemorySystem.get_tactic_id_from_decision(decision)

	assert_eq(tactic_id, "maneuver_evade")

func test_get_tactic_id_no_subtype():
	var decision = {"type": "hold"}

	var tactic_id = TacticalMemorySystem.get_tactic_id_from_decision(decision)

	assert_eq(tactic_id, "hold")

# ============================================================================
# MEMORY QUERY TESTS
# ============================================================================

func test_get_top_successful_tactics():
	var crew = CrewData.create_crew_member(CrewData.Role.PILOT, 0.5)

	# Create different tactics with varying success
	var decision1 = {"type": "maneuver", "subtype": "evade"}
	var decision2 = {"type": "maneuver", "subtype": "zigzag"}

	# Tactic 1: 8/10 = 80%
	for i in range(8):
		crew = TacticalMemorySystem.record_decision_outcome(crew, decision1, true)
	for i in range(2):
		crew = TacticalMemorySystem.record_decision_outcome(crew, decision1, false)

	# Tactic 2: 5/10 = 50%
	for i in range(5):
		crew = TacticalMemorySystem.record_decision_outcome(crew, decision2, true)
	for i in range(5):
		crew = TacticalMemorySystem.record_decision_outcome(crew, decision2, false)

	var top_tactics = TacticalMemorySystem.get_top_successful_tactics(crew, 2)

	assert_eq(top_tactics.size(), 2)
	assert_eq(top_tactics[0].tactic_id, "maneuver_evade", "Best tactic should be first")
	assert_gt(top_tactics[0].success_rate, top_tactics[1].success_rate)

func test_get_tactics_to_avoid():
	var crew = CrewData.create_crew_member(CrewData.Role.PILOT, 0.5)

	var decision = {"type": "maneuver", "subtype": "direct"}

	# Very low success: 1/10 = 10%
	crew = TacticalMemorySystem.record_decision_outcome(crew, decision, true)
	for i in range(9):
		crew = TacticalMemorySystem.record_decision_outcome(crew, decision, false)

	var bad_tactics = TacticalMemorySystem.get_tactics_to_avoid(crew, 0.3)

	assert_eq(bad_tactics.size(), 1)
	assert_eq(bad_tactics[0].tactic_id, "maneuver_direct")
	assert_lt(bad_tactics[0].success_rate, 0.3)

func test_has_sufficient_experience():
	var crew = CrewData.create_crew_member(CrewData.Role.PILOT, 0.5)

	assert_false(TacticalMemorySystem.has_sufficient_experience(crew, 5))

	# Add some decisions
	var decision = {"type": "maneuver", "subtype": "evade"}
	for i in range(6):
		crew = TacticalMemorySystem.record_decision_outcome(crew, decision, true)

	assert_true(TacticalMemorySystem.has_sufficient_experience(crew, 5))

# ============================================================================
# MEMORY STATISTICS TESTS
# ============================================================================

func test_get_memory_stats_empty():
	var crew = CrewData.create_crew_member(CrewData.Role.PILOT, 0.5)

	var stats = TacticalMemorySystem.get_memory_stats(crew)

	assert_eq(stats.total_decisions, 0)
	assert_eq(stats.total_successes, 0)
	assert_eq(stats.total_failures, 0)
	assert_eq(stats.overall_success_rate, 0.0)
	assert_eq(stats.unique_tactics_tried, 0)

func test_get_memory_stats_with_history():
	var crew = CrewData.create_crew_member(CrewData.Role.PILOT, 0.5)

	var decision1 = {"type": "maneuver", "subtype": "evade"}
	var decision2 = {"type": "fire", "subtype": "burst"}

	# 3 successes, 2 failures across 2 tactics
	crew = TacticalMemorySystem.record_decision_outcome(crew, decision1, true)
	crew = TacticalMemorySystem.record_decision_outcome(crew, decision1, true)
	crew = TacticalMemorySystem.record_decision_outcome(crew, decision1, false)
	crew = TacticalMemorySystem.record_decision_outcome(crew, decision2, true)
	crew = TacticalMemorySystem.record_decision_outcome(crew, decision2, false)

	var stats = TacticalMemorySystem.get_memory_stats(crew)

	assert_eq(stats.total_decisions, 5)
	assert_eq(stats.total_successes, 3)
	assert_eq(stats.total_failures, 2)
	assert_eq(stats.overall_success_rate, 0.6)
	assert_eq(stats.unique_tactics_tried, 2)

# ============================================================================
# EVENT FILTERING TESTS
# ============================================================================

func test_add_to_recent_events():
	var current = [{"type": "old1"}, {"type": "old2"}]
	var new_events = [{"type": "new1"}, {"type": "new2"}]

	var combined = TacticalMemorySystem.add_to_recent_events(current, new_events)

	assert_eq(combined.size(), 4)
	assert_eq(combined[0].type, "old1")
	assert_eq(combined[3].type, "new2")

func test_add_to_recent_events_overflow():
	var current = []
	for i in range(TacticalMemorySystem.MAX_RECENT_EVENTS):
		current.append({"type": "event", "index": i})

	var new_events = [{"type": "new1"}, {"type": "new2"}]

	var combined = TacticalMemorySystem.add_to_recent_events(current, new_events)

	assert_eq(combined.size(), TacticalMemorySystem.MAX_RECENT_EVENTS, "Should not exceed max")
	# Should keep most recent events
	assert_eq(combined[combined.size() - 1].type, "new2")
