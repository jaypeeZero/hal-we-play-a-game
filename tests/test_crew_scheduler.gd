extends GutTest

## Behavior tests for the event-driven crew scheduler.
##
## These describe what the scheduling layer should DO, regardless of the
## underlying queue / mailbox implementation.  Tests for behaviors not yet
## implemented are marked pending() and will activate as the new modules
## come online.
##
## Phase 1 of the optimize-npc-commands branch.

# ============================================================================
# HELPERS
# ============================================================================

func make_pilot(skill: float = 0.7, ship_id: String = "ship_1") -> Dictionary:
	var pilot = CrewData.create_crew_member(CrewData.Role.PILOT, skill)
	pilot.assigned_to = ship_id
	# Treat as multi-crew so pilot decisions use evade/pursue subtypes
	pilot.command_chain.superior = "captain_x"
	return pilot

func make_gunner(skill: float = 0.7, ship_id: String = "ship_1") -> Dictionary:
	var gunner = CrewData.create_crew_member(CrewData.Role.GUNNER, skill)
	gunner.assigned_to = ship_id
	gunner.command_chain.superior = "captain_x"
	return gunner

func make_captain(skill: float = 0.7, ship_id: String = "ship_1") -> Dictionary:
	var captain = CrewData.create_crew_member(CrewData.Role.CAPTAIN, skill)
	captain.assigned_to = ship_id
	captain.command_chain.subordinates = ["pilot_x", "gunner_x"]
	return captain

func make_threat(id: String, priority: float) -> Dictionary:
	return {"id": id, "type": "ship", "_threat_priority": priority}

func make_opportunity(id: String, score: float) -> Dictionary:
	return {"id": id, "type": "ship", "_opportunity_score": score}

# ============================================================================
# BEHAVIOR 1: Sleeping crew do not decide
# ============================================================================

func test_sleeping_crew_produces_no_decision():
	var pilot = make_pilot()
	pilot.next_decision_time = 5.0
	pilot.awareness.opportunities = [make_opportunity("enemy_1", 100.0)]

	var result = CrewAISystem.update_all_crew([pilot], 0.016, 1.0)

	assert_eq(result.decisions.size(), 0,
		"A crew with next_decision_time in the future must not produce a decision.")

# ============================================================================
# BEHAVIOR 2: Awakened crew do decide
# ============================================================================

func test_awakened_crew_produces_a_decision():
	var pilot = make_pilot()
	pilot.next_decision_time = 0.5
	pilot.awareness.opportunities = [make_opportunity("enemy_1", 100.0)]

	var result = CrewAISystem.update_all_crew([pilot], 0.016, 1.0)

	assert_eq(result.decisions.size(), 1,
		"A crew whose wake time has passed must produce a decision.")

# ============================================================================
# BEHAVIOR 4: Every active crew eventually acts
# ============================================================================

func test_all_active_crew_eventually_decide():
	var crew_list = [
		make_pilot(0.7, "ship_a"),
		make_gunner(0.7, "ship_b"),
		make_pilot(0.7, "ship_c"),
	]
	# Give each something to do
	for c in crew_list:
		if c.role == CrewData.Role.PILOT:
			c.awareness.opportunities = [make_opportunity("enemy", 100.0)]
		elif c.role == CrewData.Role.GUNNER:
			c.awareness.opportunities = [make_opportunity("enemy", 100.0)]

	var who_acted = {}
	var time = 0.0
	# Run 30 simulated seconds, ticking every 0.05s
	for i in range(600):
		time += 0.05
		var result = CrewAISystem.update_all_crew(crew_list, 0.05, time)
		crew_list = result.crew_list
		for d in result.decisions:
			who_acted[d.entity_id] = true

	assert_eq(who_acted.size(), 3,
		"All three crew should have produced at least one decision over 30 simulated seconds.")

# ============================================================================
# BEHAVIOR 14: Per-role cadences differ (pilots > gunners > captains)
# ============================================================================

func test_pilots_decide_more_often_than_gunners():
	var pilot = make_pilot(0.7, "ship_a")
	pilot.awareness.opportunities = [make_opportunity("enemy_1", 100.0)]
	var gunner = make_gunner(0.7, "ship_b")
	# Gunner with no targets idles longer
	# Use captain as proxy for the slower-still cadence

	var pilot_decisions = 0
	var gunner_decisions = 0
	var time = 0.0
	for i in range(200):
		time += 0.1
		var p_result = CrewAISystem.update_all_crew([pilot], 0.1, time)
		pilot = p_result.crew_list[0]
		pilot_decisions += p_result.decisions.size()

		# refresh gunner's opportunity each tick (so it has something to fire at)
		gunner.awareness.opportunities = [make_opportunity("enemy_1", 100.0)]
		var g_result = CrewAISystem.update_all_crew([gunner], 0.1, time)
		gunner = g_result.crew_list[0]
		gunner_decisions += g_result.decisions.size()

	# Pilots tick at ~0.7-1.0s for evasion / 0.3-0.5s, gunners at 0.5-2s
	# We assert directionally: pilots produce more or equal decisions, never fewer
	assert_true(pilot_decisions >= gunner_decisions,
		"Pilots should decide at least as often as gunners over the same window.")

func test_captains_decide_less_often_than_pilots():
	var captain = make_captain(0.7, "ship_a")
	captain.awareness.opportunities = [make_opportunity("enemy_1", 100.0)]
	var pilot = make_pilot(0.7, "ship_b")
	pilot.awareness.opportunities = [make_opportunity("enemy_1", 100.0)]

	var captain_decisions = 0
	var pilot_decisions = 0
	var time = 0.0
	for i in range(200):
		time += 0.1
		var c_result = CrewAISystem.update_all_crew([captain], 0.1, time)
		captain = c_result.crew_list[0]
		captain_decisions += c_result.decisions.size()

		var p_result = CrewAISystem.update_all_crew([pilot], 0.1, time)
		pilot = p_result.crew_list[0]
		pilot_decisions += p_result.decisions.size()

	assert_true(pilot_decisions > captain_decisions,
		"Pilots should decide strictly more often than captains over the same window.")

# ============================================================================
# BEHAVIOR 9: Heartbeat fallback liveness
# ============================================================================

func test_heartbeat_fallback_pilot_decides_within_window():
	# A pilot with no events and nothing happening should still produce a
	# decision within their heartbeat window (proposed: 0.2s for pilots, with
	# decision frequencies that schedule them well under 5s).
	var pilot = make_pilot(0.7)
	pilot.awareness.opportunities = [make_opportunity("enemy_1", 100.0)]

	var time = 0.0
	var first_decision_at = -1.0
	for i in range(100):
		time += 0.05
		var result = CrewAISystem.update_all_crew([pilot], 0.05, time)
		pilot = result.crew_list[0]
		if result.decisions.size() > 0 and first_decision_at < 0.0:
			first_decision_at = time
			break

	assert_true(first_decision_at >= 0.0 and first_decision_at <= 5.0,
		"Pilot must decide within 5s heartbeat window.  Got: %s" % first_decision_at)

# ============================================================================
# BEHAVIOR 8: Sleeping crew without events produces no work
# ============================================================================

func test_sleeping_crew_does_not_mutate_crew_data():
	var pilot = make_pilot()
	pilot.next_decision_time = 100.0
	var original_skill = pilot.stats.skill

	var result = CrewAISystem.update_all_crew([pilot], 0.016, 1.0)

	assert_eq(result.crew_list.size(), 1, "Crew list preserved")
	# State updates (stress/fatigue) may still happen, but skill must not mutate
	assert_eq(result.crew_list[0].stats.skill, original_skill,
		"Sleeping crew's skill must not change.")
	assert_eq(result.decisions.size(), 0, "No decisions produced for sleeping crew.")

# ============================================================================
# BEHAVIOR 6: Mailbox event wakes a sleeping crew
# ============================================================================

func test_mailbox_event_wakes_sleeping_crew():
	var Mailbox = _load_mailbox()
	var Scheduler = _load_scheduler()
	if Mailbox == null or Scheduler == null:
		pending("CrewMailboxSystem / CrewSchedulerSystem not implemented yet.")
		return

	var pilot = make_pilot()
	pilot.next_decision_time = 5.0
	pilot.awareness.opportunities = [make_opportunity("enemy_1", 100.0)]

	var mailboxes = Mailbox.post_event({}, pilot.crew_id, {
		"type": "threat_appeared",
		"data": {"enemy_id": "enemy_1"}
	})

	var result = Scheduler.tick([pilot], 1.0, mailboxes)

	assert_eq(result.decisions.size(), 1,
		"Posting an event for a sleeping crew should wake them this tick.")

# ============================================================================
# BEHAVIOR 7: Event reaches the decision context
# ============================================================================

func test_pilot_under_missile_lock_makes_evasive_decision():
	var Mailbox = _load_mailbox()
	var Scheduler = _load_scheduler()
	if Mailbox == null or Scheduler == null:
		pending("CrewMailboxSystem / CrewSchedulerSystem not implemented yet.")
		return

	var pilot = make_pilot(0.7)
	pilot.awareness.threats = [make_threat("missile_1", 200.0)]

	var mailboxes = Mailbox.post_event({}, pilot.crew_id, {
		"type": "missile_locked",
		"data": {"missile_id": "missile_1"}
	})

	var result = Scheduler.tick([pilot], 1.0, mailboxes)

	assert_eq(result.decisions.size(), 1, "Pilot should react to missile lock.")
	var decision = result.decisions[0]
	assert_eq(decision.type, "maneuver",
		"A pilot waking on missile_locked should produce a maneuver, not idle.")
	assert_eq(decision.subtype, "evade",
		"Maneuver in response to missile lock should be evasive.")

# ============================================================================
# BEHAVIOR 11: Pilot reacts to a new high-priority threat appearing mid-sleep
# ============================================================================

func test_pilot_reacts_to_threat_appearing_mid_sleep():
	var Mailbox = _load_mailbox()
	var Scheduler = _load_scheduler()
	if Mailbox == null or Scheduler == null:
		pending("CrewMailboxSystem / CrewSchedulerSystem not implemented yet.")
		return

	var pilot = make_pilot()
	pilot.next_decision_time = 10.0  # asleep for a long time
	# A new threat appears in pilot's awareness
	pilot.awareness.threats = [make_threat("enemy_1", 250.0)]

	var mailboxes = Mailbox.post_event({}, pilot.crew_id, {
		"type": "threat_appeared",
		"data": {"enemy_id": "enemy_1"}
	})

	var result = Scheduler.tick([pilot], 1.0, mailboxes)

	assert_eq(result.decisions.size(), 1,
		"Pilot must react to the new threat without waiting until t=10.")

# ============================================================================
# BEHAVIOR: Mailbox cap (10 events per crew, oldest dropped)
# ============================================================================

func test_mailbox_caps_events_at_ten_per_crew():
	var Mailbox = _load_mailbox()
	if Mailbox == null:
		pending("CrewMailboxSystem not implemented yet.")
		return

	var mailboxes = {}
	var crew_id = "crew_x"

	for i in range(11):
		mailboxes = Mailbox.post_event(mailboxes, crew_id, {
			"type": "marker",
			"data": {"index": i}
		})

	var drained = Mailbox.drain_events(mailboxes, crew_id)
	var events = drained.events

	assert_eq(events.size(), 10,
		"Mailbox should cap at 10 events.")
	# Oldest dropped means index 0 is gone, indices 1..10 remain
	assert_eq(events[0].data.index, 1,
		"Oldest event (index 0) should have been dropped.")
	assert_eq(events[events.size() - 1].data.index, 10,
		"Newest event (index 10) should be retained.")

# ============================================================================
# BEHAVIOR: Posting an event marks the crew as having pending work
# ============================================================================

func test_has_pending_reflects_posted_events():
	var Mailbox = _load_mailbox()
	if Mailbox == null:
		pending("CrewMailboxSystem not implemented yet.")
		return

	var mailboxes = {}
	assert_false(Mailbox.has_pending(mailboxes, "crew_x"),
		"Empty mailbox has no pending events.")

	mailboxes = Mailbox.post_event(mailboxes, "crew_x", {
		"type": "weapon_ready", "data": {}
	})
	assert_true(Mailbox.has_pending(mailboxes, "crew_x"),
		"After posting, mailbox reports pending.")

# ============================================================================
# BEHAVIOR: Drain returns events AND empties the mailbox
# ============================================================================

func test_drain_empties_the_mailbox():
	var Mailbox = _load_mailbox()
	if Mailbox == null:
		pending("CrewMailboxSystem not implemented yet.")
		return

	var mailboxes = Mailbox.post_event({}, "crew_x", {
		"type": "weapon_ready", "data": {}
	})

	var drained = Mailbox.drain_events(mailboxes, "crew_x")
	assert_eq(drained.events.size(), 1, "Drain returns the posted event.")
	assert_false(Mailbox.has_pending(drained.mailboxes, "crew_x"),
		"Mailbox is empty after drain.")

# ============================================================================
# Helpers: dynamic loaders so tests parse before the modules exist
# ============================================================================

func _load_mailbox():
	var path = "res://scripts/space/systems/crew_mailbox_system.gd"
	if not ResourceLoader.exists(path):
		return null
	return load(path)

func _load_scheduler():
	var path = "res://scripts/space/systems/crew_scheduler_system.gd"
	if not ResourceLoader.exists(path):
		return null
	return load(path)
