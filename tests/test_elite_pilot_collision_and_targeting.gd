extends GutTest

## Elite pilots (skill 15+/20) avoid ramming squadmates and break lock for
## significantly closer threats. Rookies do neither.

func create_ship(id: String, pos: Vector2, team: int, vel: Vector2 = Vector2.ZERO) -> Dictionary:
	return {
		"ship_id": id, "type": "fighter", "team": team,
		"position": pos, "velocity": vel, "rotation": 0.0,
		"status": "operational", "collision_radius": 15.0,
		"stats": {"max_speed": 300.0, "acceleration": 100.0, "turn_rate": 3.0, "mass": 50.0, "size": 15.0},
		"orders": {"current_order": "", "target_id": ""}
	}

func create_crew(id: String, ship_id: String, piloting: float) -> Dictionary:
	return {
		"crew_id": id, "role": CrewData.Role.PILOT, "assigned_to": ship_id,
		"stats": {
			"reaction_time": 0.1, "stress": 0.0, "fatigue": 0.0,
			"skills": {"aim": 0.5, "piloting": piloting, "awareness": 0.5,
					   "tactics": 0.5, "composure": 0.5, "aggression": 0.5}
		},
		"awareness": {"threats": [], "opportunities": [], "known_entities": []},
		"combat_state": {}
	}

# ============================================================================
# FRIENDLY COLLISION AVOIDANCE
# ============================================================================

func test_elite_breaks_for_friendly_on_collision_course():
	# BEHAVIOR: Elite pilots notice when a squadmate is closing fast and
	# break off — they don't plough through their own formation.
	var me = create_ship("me", Vector2.ZERO, 0, Vector2(200, 0))
	var friend = create_ship("friend", Vector2(500, 0), 0, Vector2(-200, 0))  # closing head-on
	var enemy = create_ship("enemy", Vector2(0, 3000), 1)  # out of collision range, not aiming at me

	var crew = create_crew("p", "me", WingConstants.PILOT_FRIENDLY_COLLISION_SKILL + 0.05)
	crew.awareness.threats = ["enemy"]

	var decision = FighterPilotAI.make_decision(crew, me, [me, friend, enemy], [crew], 0.0)
	assert_eq(decision.subtype, "fight_lateral_break",
		"Elite pilot must break when on collision course with a friendly")

func test_rookie_does_not_avoid_friendly_collision():
	# BEHAVIOR: Rookies lack situational awareness and fly straight through their
	# own formation — only their current combat target gets attention.
	var me = create_ship("me", Vector2.ZERO, 0, Vector2(200, 0))
	var friend = create_ship("friend", Vector2(500, 0), 0, Vector2(-200, 0))
	var enemy = create_ship("enemy", Vector2(0, 3000), 1)

	var crew = create_crew("p", "me", WingConstants.PILOT_FRIENDLY_COLLISION_SKILL - 0.1)
	crew.awareness.threats = ["enemy"]

	var decision = FighterPilotAI.make_decision(crew, me, [me, friend, enemy], [crew], 0.0)
	assert_ne(decision.subtype, "fight_lateral_break",
		"Rookie must not trigger friendly collision avoidance")

func test_no_break_when_not_closing_on_friendly():
	# BEHAVIOR: A nearby friendly flying in the same direction is not a
	# collision risk — no evasion should fire.
	var me = create_ship("me", Vector2.ZERO, 0, Vector2(200, 0))
	var friend = create_ship("friend", Vector2(300, 0), 0, Vector2(200, 0))  # same direction
	var enemy = create_ship("enemy", Vector2(0, 3000), 1)

	var crew = create_crew("p", "me", WingConstants.PILOT_FRIENDLY_COLLISION_SKILL + 0.05)
	crew.awareness.threats = ["enemy"]

	var decision = FighterPilotAI.make_decision(crew, me, [me, friend, enemy], [crew], 0.0)
	assert_ne(decision.subtype, "fight_lateral_break",
		"No break needed when friendly is flying parallel, not closing")

# ============================================================================
# CLOSE TARGET PRIORITIZATION
# ============================================================================

func test_elite_breaks_lock_when_closer_threat_appears():
	# BEHAVIOR: An elite pilot locked on a distant target notices when a new
	# threat enters close range and immediately re-evaluates — they don't keep
	# charging a ship 2000 units away while ignoring one 300 units away.
	var me = create_ship("me", Vector2.ZERO, 0)
	var far_enemy = create_ship("far_enemy", Vector2(2000, 0), 1)
	var close_enemy = create_ship("close_enemy", Vector2(300, 0), 1)  # inside CLOSE_RANGE

	var crew = create_crew("p", "me", WingConstants.CLOSE_TARGET_RELOCK_SKILL + 0.1)
	crew.combat_state = {
		"locked_target_id": "far_enemy",
		"target_locked_until": Time.get_ticks_msec() / 1000.0 + 100.0
	}

	var target = FighterPilotAI._find_best_target(crew, [me, far_enemy, close_enemy])
	assert_ne(target, "far_enemy",
		"Elite pilot must break lock when a significantly closer threat enters close range")

func test_rookie_stays_locked_despite_closer_threat():
	# BEHAVIOR: Rookies fixate and ignore better options — they stay committed
	# to the original target even when something is right in their face.
	var me = create_ship("me", Vector2.ZERO, 0)
	var far_enemy = create_ship("far_enemy", Vector2(2000, 0), 1)
	var close_enemy = create_ship("close_enemy", Vector2(300, 0), 1)

	var crew = create_crew("p", "me", 0.2)  # extreme fixation range
	crew.combat_state = {
		"locked_target_id": "far_enemy",
		"target_locked_until": Time.get_ticks_msec() / 1000.0 + 100.0
	}

	var target = FighterPilotAI._find_best_target(crew, [me, far_enemy, close_enemy])
	assert_eq(target, "far_enemy",
		"Rookie must stay locked on original target despite closer option")

func test_no_lock_break_when_closer_enemy_not_in_close_range():
	# BEHAVIOR: "Closer" only overrides the lock when the new threat is
	# genuinely in close range — not just slightly nearer at long distance.
	# This prevents constant target-switching in long-range engagements.
	var me = create_ship("me", Vector2.ZERO, 0)
	var far_enemy = create_ship("far_enemy", Vector2(3000, 0), 1)
	var mid_enemy = create_ship("mid_enemy", Vector2(1500, 0), 1)  # closer, but NOT in CLOSE_RANGE

	var crew = create_crew("p", "me", WingConstants.CLOSE_TARGET_RELOCK_SKILL + 0.1)
	crew.combat_state = {
		"locked_target_id": "far_enemy",
		"target_locked_until": Time.get_ticks_msec() / 1000.0 + 100.0
	}

	var target = FighterPilotAI._find_best_target(crew, [me, far_enemy, mid_enemy])
	assert_eq(target, "far_enemy",
		"Lock should hold when closer enemy is outside close range — prevents long-range thrashing")
