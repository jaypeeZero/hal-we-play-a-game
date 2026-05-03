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

func make_test_ship(id: String, team: int, pos: Vector2) -> Dictionary:
	return {
		"ship_id": id,
		"team": team,
		"position": pos,
		"velocity": Vector2.ZERO,
		"rotation": 0.0,
		"status": "operational",
		"type": "fighter",
		"collision_radius": 15.0,
		"stats": {"max_speed": 300.0, "acceleration": 100.0, "turn_rate": 3.0},
		"weapons": []
	}

func make_opportunity(id: String, score: float) -> Dictionary:
	return {"id": id, "type": "ship", "_opportunity_score": score}

# ============================================================================
# BEHAVIOR 1: Sleeping crew do not decide
# ============================================================================

func test_sleeping_crew_produces_no_decision():
	var pilot = make_pilot()
	pilot.next_decision_time = 5.0
	pilot.awareness.opportunities = [make_opportunity("enemy_1", 100.0)]

	var result = CrewSchedulerSystem.tick_with_awareness([pilot], 1.0, {})

	assert_eq(result.decisions.size(), 0,
		"A crew with next_decision_time in the future must not produce a decision.")

# ============================================================================
# BEHAVIOR 2: Awakened crew do decide
# ============================================================================

func test_awakened_crew_produces_a_decision():
	var pilot = make_pilot()
	pilot.next_decision_time = 0.5
	pilot.awareness.opportunities = [make_opportunity("enemy_1", 100.0)]

	var result = CrewSchedulerSystem.tick_with_awareness([pilot], 1.0, {})

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
		var result = CrewSchedulerSystem.tick_with_awareness(crew_list, time, {})
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
		var p_result = CrewSchedulerSystem.tick_with_awareness([pilot], time, {})
		pilot = p_result.crew_list[0]
		pilot_decisions += p_result.decisions.size()

		# refresh gunner's opportunity each tick (so it has something to fire at)
		gunner.awareness.opportunities = [make_opportunity("enemy_1", 100.0)]
		var g_result = CrewSchedulerSystem.tick_with_awareness([gunner], time, {})
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
		var c_result = CrewSchedulerSystem.tick_with_awareness([captain], time, {})
		captain = c_result.crew_list[0]
		captain_decisions += c_result.decisions.size()

		var p_result = CrewSchedulerSystem.tick_with_awareness([pilot], time, {})
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
		var result = CrewSchedulerSystem.tick_with_awareness([pilot], time, {})
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

	var result = CrewSchedulerSystem.tick_with_awareness([pilot], 1.0, {})

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
# BEHAVIOR: Awareness is refreshed only when crew wakes
# ============================================================================
#
# Per-frame awareness scans were costing 6,000+ distance checks at 30 fighters
# scale.  The optimization: refresh a crew's awareness when they wake (event
# or scheduled), not every frame.  These tests describe the contract.

func test_sleeping_crew_awareness_is_not_refreshed():
	var Scheduler = _load_scheduler_with_awareness()
	if Scheduler == null:
		pending("CrewSchedulerSystem.tick_with_awareness not implemented yet.")
		return

	var pilot = make_pilot()
	pilot.next_decision_time = 5.0  # asleep
	pilot.awareness.last_update = 0.0

	var ship = make_test_ship("ship_1", 0, Vector2.ZERO)
	var enemy = make_test_ship("enemy_1", 1, Vector2(100, 0))

	var result = Scheduler.tick_with_awareness([pilot], 1.0, {}, [ship, enemy], [], [])

	# Sleeping crew should not have their awareness refreshed
	assert_eq(result.crew_list[0].awareness.last_update, 0.0,
		"Sleeping crew with no events should NOT refresh awareness.")

func test_waking_crew_awareness_is_refreshed():
	var Scheduler = _load_scheduler_with_awareness()
	if Scheduler == null:
		pending("CrewSchedulerSystem.tick_with_awareness not implemented yet.")
		return

	var pilot = make_pilot()
	pilot.next_decision_time = 0.5  # due to wake
	pilot.awareness.last_update = 0.0

	var ship = make_test_ship("ship_1", 0, Vector2.ZERO)
	var enemy = make_test_ship("enemy_1", 1, Vector2(200, 0))

	var result = Scheduler.tick_with_awareness([pilot], 1.0, {}, [ship, enemy], [], [])

	assert_eq(result.crew_list[0].awareness.last_update, 1.0,
		"A waking crew member's awareness should be refreshed at game_time.")

func test_event_woken_crew_sees_current_world_state():
	var Scheduler = _load_scheduler_with_awareness()
	var Mailbox = _load_mailbox()
	if Scheduler == null or Mailbox == null:
		pending("CrewSchedulerSystem.tick_with_awareness / CrewMailboxSystem not implemented yet.")
		return

	var pilot = make_pilot()
	pilot.next_decision_time = 100.0  # would otherwise sleep forever
	pilot.awareness.last_update = 0.0

	var ship = make_test_ship("ship_1", 0, Vector2.ZERO)
	var enemy = make_test_ship("enemy_1", 1, Vector2(150, 0))

	var mailboxes = Mailbox.post_event({}, pilot.crew_id, {
		"type": "threat_appeared",
		"data": {"enemy_id": "enemy_1"}
	})

	var result = Scheduler.tick_with_awareness([pilot], 1.0, mailboxes, [ship, enemy], [], [])

	# When woken by an event, the pilot should see the enemy
	var awakened_pilot = result.crew_list[0]
	assert_gt(awakened_pilot.awareness.known_entities.size(), 0,
		"An event-woken crew should refresh awareness and see the enemy.")

# ============================================================================
# REGRESSION: mid-game-spawned crew must produce decisions
#
# A bug was reported where ~half of fighters added mid-battle (via the
# squadron-spawn input) would never act.  Squadron-spawned pilots have
# command_chain.superior set (Alpha is leader), so non-Alpha pilots route
# through make_corvette_pilot_decision -> LargeShipPilotAI.  These tests
# verify that a freshly-added pilot, with default next_decision_time = 0
# and an empty awareness snapshot, will be processed and produce a real
# decision (not silent idle) on its first scheduler tick.
# ============================================================================

func test_mid_game_squadron_pilot_makes_decision_on_first_tick():
	var Scheduler = _load_scheduler_with_awareness()
	if Scheduler == null:
		pending("CrewSchedulerSystem.tick_with_awareness not implemented yet.")
		return

	# Simulate a squadron-style pilot: has a superior (the squadron leader)
	var pilot = CrewData.create_crew_member(CrewData.Role.PILOT, 1.0)
	pilot.assigned_to = "ship_new"
	pilot.command_chain.superior = "crew_alpha_x"
	# next_decision_time defaults to 0; awareness is empty arrays.

	var own_ship = make_test_ship("ship_new", 0, Vector2.ZERO)
	var enemy = make_test_ship("enemy_1", 1, Vector2(300, 0))  # within sensor range

	var result = Scheduler.tick_with_awareness(
		[pilot], 50.0, {}, [own_ship, enemy], [], [])

	assert_eq(result.decisions.size(), 1,
		"A mid-game-spawned squadron pilot should produce a decision on first tick.")
	var d = result.decisions[0]
	assert_ne(d.get("type", ""), "",
		"The decision must be a real maneuver, not an empty/idle dict.")

func test_mid_game_pilot_continues_to_act_across_multiple_ticks():
	var Scheduler = _load_scheduler_with_awareness()
	if Scheduler == null:
		pending("CrewSchedulerSystem.tick_with_awareness not implemented yet.")
		return

	# Squadron-style pilot with a superior.
	var pilot = CrewData.create_crew_member(CrewData.Role.PILOT, 1.0)
	pilot.assigned_to = "ship_new"
	pilot.command_chain.superior = "crew_alpha_x"

	var own_ship = make_test_ship("ship_new", 0, Vector2.ZERO)
	var enemy = make_test_ship("enemy_1", 1, Vector2(300, 0))
	var crew_list = [pilot]

	var decisions_total = 0
	var time = 50.0
	for i in range(200):
		time += 0.1
		var result = Scheduler.tick_with_awareness(
			crew_list, time, {}, [own_ship, enemy], [], [])
		crew_list = result.crew_list
		decisions_total += result.decisions.size()

	assert_gt(decisions_total, 0,
		"A mid-game-spawned pilot must produce at least one decision over 20s.")

func test_mid_game_pilot_with_no_visible_enemies_eventually_sees_arrivals():
	# Repro scenario: pilot spawns far from action.  Their initial awareness
	# is empty, they go idle.  Then an enemy moves into range.  They should
	# wake (via sensor_contact event) and act.
	var Scheduler = _load_scheduler_with_awareness()
	var Mailbox = _load_mailbox()
	if Scheduler == null or Mailbox == null:
		pending("CrewSchedulerSystem / CrewMailboxSystem not implemented yet.")
		return

	var pilot = CrewData.create_crew_member(CrewData.Role.PILOT, 1.0)
	pilot.assigned_to = "ship_new"
	pilot.command_chain.superior = "crew_alpha_x"

	var own_ship = make_test_ship("ship_new", 0, Vector2.ZERO)
	var crew_list = [pilot]

	# Tick once with no enemies — pilot decides (idle), schedules far-future wake
	var r1 = Scheduler.tick_with_awareness(crew_list, 50.0, {}, [own_ship], [], [])
	crew_list = r1.crew_list

	# Sleeping now.  Post a threat_appeared event (as if spatial trigger fired).
	var mailboxes = Mailbox.post_event({}, pilot.crew_id, {
		"type": "threat_appeared",
		"data": {"enemy_id": "enemy_late"}
	})
	var enemy = make_test_ship("enemy_late", 1, Vector2(200, 0))

	var r2 = Scheduler.tick_with_awareness(
		crew_list, 51.0, mailboxes, [own_ship, enemy], [], [])

	assert_eq(r2.decisions.size(), 1,
		"An idle mid-game pilot should react to a posted threat event with a decision.")

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

# Stricter loader that also checks the awareness extension is present.
func _load_scheduler_with_awareness():
	var s = _load_scheduler()
	if s == null:
		return null
	if not s.has_method("tick_with_awareness"):
		return null
	return s

# ============================================================================
# EVENT SIDE EFFECTS (formerly handled by space_battle_game.gd's _handle_* methods,
# now consolidated into the scheduler so events flow through one path).
# ============================================================================

func test_sensor_contact_event_records_threat_in_tactical_memory():
	var Scheduler = _load_scheduler_with_awareness()
	var Mailbox = _load_mailbox()
	if Scheduler == null or Mailbox == null:
		pending("CrewSchedulerSystem.tick_with_awareness / CrewMailboxSystem not implemented yet.")
		return

	var pilot = make_pilot()
	pilot.next_decision_time = 0.0  # due
	var own_ship = make_test_ship("ship_1", 0, Vector2.ZERO)
	var enemy = make_test_ship("enemy_1", 1, Vector2(200, 0))

	var mailboxes = Mailbox.post_event({}, pilot.crew_id, {
		"type": "sensor_contact",
		"data": {"enemy_id": "enemy_1", "position": Vector2(200, 0)}
	})

	var result = Scheduler.tick_with_awareness(
		[pilot], 5.0, mailboxes, [own_ship, enemy], [], [])

	var memory = result.crew_list[0].awareness.tactical_memory.recent_events
	var found = false
	for ev in memory:
		if ev.get("type", "") == "threat_detected" and ev.get("entity_id", "") == "enemy_1":
			found = true
			break
	assert_true(found,
		"sensor_contact event should record a threat_detected entry in tactical memory.")

func test_ship_damaged_event_records_in_tactical_memory():
	var Scheduler = _load_scheduler_with_awareness()
	var Mailbox = _load_mailbox()
	if Scheduler == null or Mailbox == null:
		pending("CrewSchedulerSystem.tick_with_awareness / CrewMailboxSystem not implemented yet.")
		return

	var pilot = make_pilot()
	pilot.awareness.threats = [make_threat("enemy_1", 200.0)]
	pilot.next_decision_time = 0.0
	var own_ship = make_test_ship("ship_1", 0, Vector2.ZERO)

	var mailboxes = Mailbox.post_event({}, pilot.crew_id, {
		"type": "ship_damaged",
		"data": {"damage": 12, "section": "nose", "attacker": "proj_1"}
	})

	var result = Scheduler.tick_with_awareness(
		[pilot], 5.0, mailboxes, [own_ship], [], [])

	var memory = result.crew_list[0].awareness.tactical_memory.recent_events
	var found = false
	for ev in memory:
		if ev.get("type", "") == "ship_damaged":
			found = true
			break
	assert_true(found,
		"ship_damaged event should record a ship_damaged entry in tactical memory.")

func test_target_lost_event_clears_current_target():
	var Scheduler = _load_scheduler_with_awareness()
	var Mailbox = _load_mailbox()
	if Scheduler == null or Mailbox == null:
		pending("CrewSchedulerSystem.tick_with_awareness / CrewMailboxSystem not implemented yet.")
		return

	var pilot = make_pilot()
	pilot.awareness["current_target"] = "enemy_old"
	pilot.next_decision_time = 0.0
	var own_ship = make_test_ship("ship_1", 0, Vector2.ZERO)

	var mailboxes = Mailbox.post_event({}, pilot.crew_id, {
		"type": "target_lost",
		"data": {"enemy_id": "enemy_old"}
	})

	var result = Scheduler.tick_with_awareness(
		[pilot], 5.0, mailboxes, [own_ship], [], [])

	assert_eq(result.crew_list[0].awareness.get("current_target", ""), "",
		"target_lost event should clear awareness.current_target.")
