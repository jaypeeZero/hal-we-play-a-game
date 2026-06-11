extends GutTest

## Tests for the engagement-cycle FSM and supporting tactical hooks
## (target lock, threat-on-six interrupt, wing-level phase coordination).
## Verifies BEHAVIOR, not specific tuning numbers.

func _make_ship(id: String, team: int, pos: Vector2, rotation: float = 0.0) -> Dictionary:
	return {
		"ship_id": id,
		"team": team,
		"type": "fighter",
		"position": pos,
		"rotation": rotation,
		"velocity": Vector2.ZERO,
		"status": "operational",
		"stats": {"max_speed": 300.0, "acceleration": 100.0, "turn_rate": 4.0, "size": 15.0},
		"orders": {"current_order": "engage", "target_id": ""},
		"armor_sections": [{"section_id": "front", "current_armor": 25, "max_armor": 25, "arc": {"start": -90, "end": 90}}],
		"collision_radius": 15.0
	}

func _make_crew(id: String, assigned_to: String, aggression: float = 0.5) -> Dictionary:
	return {
		"crew_id": id,
		"assigned_to": assigned_to,
		"stats": {"skill": 0.6, "skills": {"aggression": aggression}, "reaction_time": 0.1},
		"awareness": {"threats": [], "opportunities": [], "known_entities": []},
		"combat_state": {"locked_target_id": "", "lock_start_time": 0.0},
		"orders": {"received": null, "current": null, "issued": []}
	}

# ============================================================================
# CORE FSM — phases advance through firing_pass → extend → reposition → approach
# ============================================================================

func test_phase_advances_through_full_cycle():
	var ship = _make_ship("me", 0, Vector2(0, 0))
	ship.velocity = Vector2(0, -200)
	var target = _make_ship("tgt", 1, Vector2(0, -1000))  # in my front
	var crew = _make_crew("c", "me", 0.5)

	var info1 = FighterPilotAI._step_engagement_phase(crew, ship, target, 0.0)
	var info2 = FighterPilotAI._step_engagement_phase(crew, ship, target, 0.5)
	var info3 = FighterPilotAI._step_engagement_phase(crew, ship, target, 3.0)
	var info4 = FighterPilotAI._step_engagement_phase(crew, ship, target, 3.5)
	var info5 = FighterPilotAI._step_engagement_phase(crew, ship, target, 5.0)

	assert_eq(info1.phase, "firing_pass", "Should enter firing_pass when target in zone")
	assert_eq(info2.phase, "firing_pass", "Should remain firing_pass briefly")
	assert_eq(info3.phase, "extending", "Should transition to extending after firing_pass duration")
	assert_eq(info4.phase, "extending", "Should remain extending briefly")
	assert_eq(info5.phase, "repositioning", "Should transition to repositioning after extend")

func test_aggressive_pilots_stay_in_firing_pass_longer():
	var target = _make_ship("tgt", 1, Vector2(0, -1000))

	var hot_ship = _make_ship("hot", 0, Vector2(0, 0))
	hot_ship.velocity = Vector2(0, -200)
	var cold_ship = _make_ship("cold", 0, Vector2(0, 0))
	cold_ship.velocity = Vector2(0, -200)

	var hot_crew = _make_crew("hc", "hot", 1.0)
	var cold_crew = _make_crew("cc", "cold", 0.0)

	# Both enter firing_pass
	FighterPilotAI._step_engagement_phase(hot_crew, hot_ship, target, 0.0)
	FighterPilotAI._step_engagement_phase(cold_crew, cold_ship, target, 0.0)

	# At 2.0s, the cold pilot should already have broken; the hot one still firing
	var hot_at_2 = FighterPilotAI._step_engagement_phase(hot_crew, hot_ship, target, 2.0)
	var cold_at_2 = FighterPilotAI._step_engagement_phase(cold_crew, cold_ship, target, 2.0)

	assert_eq(hot_at_2.phase, "firing_pass", "Aggressive pilot still committing at 2s")
	assert_eq(cold_at_2.phase, "extending", "Cautious pilot already broke off by 2s")

func test_changing_target_resets_phase():
	var ship = _make_ship("me", 0, Vector2(0, 0))
	ship.velocity = Vector2(0, -200)
	var target_a = _make_ship("a", 1, Vector2(0, -1000))
	var target_b = _make_ship("b", 1, Vector2(0, -1100))
	var crew = _make_crew("c", "me", 0.5)

	# Lock onto A, run firing_pass timer past its duration
	FighterPilotAI._step_engagement_phase(crew, ship, target_a, 0.0)
	var late_a = FighterPilotAI._step_engagement_phase(crew, ship, target_a, 3.5)
	assert_eq(late_a.phase, "extending", "Should be extending late in cycle on target A")

	# Switch to target B — phase should reset to approach (or directly to firing_pass)
	var on_b = FighterPilotAI._step_engagement_phase(crew, ship, target_b, 3.5)
	assert_ne(on_b.phase, "extending", "Switching targets must reset the cycle, not preserve extending")

# ============================================================================
# THREAT ON MY SIX — interrupt that fires when an enemy has me in their arc
# ============================================================================

func test_threat_on_six_detected_when_enemy_aimed_at_my_back():
	# I'm at origin facing up; enemy is just behind me (Y+) facing UP (-Y) at me
	var me = _make_ship("me", 0, Vector2(0, 0), 0.0)
	# rotation = 0 → facing visual (0, -1) "up"
	# Enemy is at (0, +400) — behind me in world space
	# We want enemy facing UP (toward -Y) so their nose points at me
	var enemy = _make_ship("enemy", 1, Vector2(0, 400), 0.0)
	# enemy.rotation = 0 means enemy ALSO faces (0,-1). enemy is south of me, looking north → at me. Good.

	var threat = FighterPilotAI._check_threat_on_my_six(me, [me, enemy])
	assert_eq(threat.get("ship_id", ""), "enemy", "Should detect enemy aiming at my back")

func test_no_threat_when_enemy_facing_away():
	var me = _make_ship("me", 0, Vector2(0, 0), 0.0)
	# Enemy behind me but facing AWAY (south, same direction as me). rotation = PI faces (0,+1) south.
	var enemy = _make_ship("enemy", 1, Vector2(0, 400), PI)
	var threat = FighterPilotAI._check_threat_on_my_six(me, [me, enemy])
	assert_true(threat.is_empty(), "Enemy facing away from me is not a threat")

func test_no_threat_when_enemy_far_away():
	var me = _make_ship("me", 0, Vector2(0, 0), 0.0)
	# Enemy aimed at me but well outside TACTICAL_BREAK_RANGE
	var enemy = _make_ship("enemy", 1, Vector2(0, 2000), 0.0)
	var threat = FighterPilotAI._check_threat_on_my_six(me, [me, enemy])
	assert_true(threat.is_empty(), "Enemy outside tactical-break range is not an interrupt")

# ============================================================================
# TARGET LOCK — pilots commit to their chosen target through a cycle
# ============================================================================

func test_locked_target_persists_across_decisions():
	# Once a pilot picks a target, they should stick with it for several
	# seconds even if the scoring would now favor a different one.
	var me = _make_ship("me", 0, Vector2(0, 0))
	me.assigned_to = "me"
	var ships = [
		me,
		_make_ship("alpha", 1, Vector2(900, 0)),  # closer
		_make_ship("beta", 1, Vector2(1100, 0))   # further
	]
	var wing = {"team": 0}
	var crew = _make_crew("c", "me", 0.5)
	crew.assigned_to = "me"
	# Manually lock onto beta with the lock still live at the query time
	crew.combat_state["locked_target_id"] = "beta"
	crew.combat_state["target_locked_until"] = 10.0

	var picked = FighterPilotAI._find_best_target_for_wing(crew, wing, ships, [crew], 0.0)
	assert_eq(picked, "beta", "Locked target should be returned even if a closer target is available")

func test_locked_target_dropped_when_destroyed():
	var me = _make_ship("me", 0, Vector2(0, 0))
	me.assigned_to = "me"
	var dead = _make_ship("dead", 1, Vector2(900, 0))
	dead.status = "destroyed"
	var alive = _make_ship("alive", 1, Vector2(1100, 0))
	var wing = {"team": 0}
	var crew = _make_crew("c", "me", 0.5)
	crew.assigned_to = "me"
	crew.combat_state["locked_target_id"] = "dead"
	crew.combat_state["target_locked_until"] = 10.0

	var picked = FighterPilotAI._find_best_target_for_wing(crew, wing, [me, dead, alive], [crew], 0.0)
	assert_eq(picked, "alive", "Dead locked target must be released")
