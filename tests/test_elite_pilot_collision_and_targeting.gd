extends GutTest

## Elite pilots (skill 15+/20) avoid ramming squadmates and break lock for
## significantly closer threats. Rookies do neither.

const BASELINE_SKILL := 0.5

func _make_pilot_with_piloting(piloting: float) -> Dictionary:
	var crew = TestFactories.make_pilot("p", "me", BASELINE_SKILL)
	crew.stats.skills.piloting = piloting
	return crew

# ============================================================================
# FRIENDLY COLLISION AVOIDANCE
# ============================================================================

func test_elite_breaks_for_friendly_on_collision_course():
	# BEHAVIOR: Elite pilots notice when a squadmate is closing fast and
	# break off — they don't plough through their own formation.
	var me = TestFactories.make_fighter("me", Vector2.ZERO, 0, {"velocity": Vector2(200, 0)})
	var friend = TestFactories.make_fighter("friend", Vector2(500, 0), 0, {"velocity": Vector2(-200, 0)})  # closing head-on
	var enemy = TestFactories.make_fighter("enemy", Vector2(0, 3000), 1)  # out of collision range, not aiming at me

	var crew = _make_pilot_with_piloting(WingConstants.PILOT_FRIENDLY_COLLISION_SKILL + 0.05)
	crew.awareness.threats = ["enemy"]

	var decision = FighterPilotAI.make_decision(crew, me, [me, friend, enemy], [crew], 0.0)
	assert_eq(decision.subtype, "fight_friendly_avoid",
		"Elite pilot must break when on collision course with a friendly")

func test_rookie_does_not_avoid_friendly_collision():
	# BEHAVIOR: Rookies lack situational awareness and fly straight through their
	# own formation — only their current combat target gets attention.
	var me = TestFactories.make_fighter("me", Vector2.ZERO, 0, {"velocity": Vector2(200, 0)})
	var friend = TestFactories.make_fighter("friend", Vector2(500, 0), 0, {"velocity": Vector2(-200, 0)})
	var enemy = TestFactories.make_fighter("enemy", Vector2(0, 3000), 1)

	var crew = _make_pilot_with_piloting(WingConstants.PILOT_FRIENDLY_COLLISION_SKILL - 0.1)
	crew.awareness.threats = ["enemy"]

	var decision = FighterPilotAI.make_decision(crew, me, [me, friend, enemy], [crew], 0.0)
	assert_ne(decision.subtype, "fight_friendly_avoid",
		"Rookie must not trigger friendly collision avoidance")

func test_no_break_when_not_closing_on_friendly():
	# BEHAVIOR: A nearby friendly flying in the same direction is not a
	# collision risk — no evasion should fire.
	var me = TestFactories.make_fighter("me", Vector2.ZERO, 0, {"velocity": Vector2(200, 0)})
	var friend = TestFactories.make_fighter("friend", Vector2(300, 0), 0, {"velocity": Vector2(200, 0)})  # same direction
	var enemy = TestFactories.make_fighter("enemy", Vector2(0, 3000), 1)

	var crew = _make_pilot_with_piloting(WingConstants.PILOT_FRIENDLY_COLLISION_SKILL + 0.05)
	crew.awareness.threats = ["enemy"]

	var decision = FighterPilotAI.make_decision(crew, me, [me, friend, enemy], [crew], 0.0)
	assert_ne(decision.subtype, "fight_friendly_avoid",
		"No break needed when friendly is flying parallel, not closing")

# ============================================================================
# CLOSE TARGET PRIORITIZATION
# ============================================================================

func test_elite_breaks_lock_when_closer_threat_appears():
	# BEHAVIOR: An elite pilot locked on a distant target notices when a new
	# threat enters close range and immediately re-evaluates — they don't keep
	# charging a ship 2000 units away while ignoring one 300 units away.
	var me = TestFactories.make_fighter("me", Vector2.ZERO, 0)
	var far_enemy = TestFactories.make_fighter("far_enemy", Vector2(2000, 0), 1)
	var close_enemy = TestFactories.make_fighter("close_enemy", Vector2(300, 0), 1)  # inside CLOSE_RANGE

	var crew = _make_pilot_with_piloting(WingConstants.CLOSE_TARGET_RELOCK_SKILL + 0.1)
	crew.combat_state = {
		"locked_target_id": "far_enemy",
		"target_locked_until": 100.0
	}

	var target = FighterPilotAI._find_best_target(crew, [me, far_enemy, close_enemy], 0.0)
	assert_ne(target, "far_enemy",
		"Elite pilot must break lock when a significantly closer threat enters close range")

func test_rookie_stays_locked_despite_closer_threat():
	# BEHAVIOR: Rookies fixate and ignore better options — they stay committed
	# to the original target even when something is right in their face.
	var me = TestFactories.make_fighter("me", Vector2.ZERO, 0)
	var far_enemy = TestFactories.make_fighter("far_enemy", Vector2(2000, 0), 1)
	var close_enemy = TestFactories.make_fighter("close_enemy", Vector2(300, 0), 1)

	var crew = _make_pilot_with_piloting(0.2)  # extreme fixation range
	crew.combat_state = {
		"locked_target_id": "far_enemy",
		"target_locked_until": 100.0
	}

	var target = FighterPilotAI._find_best_target(crew, [me, far_enemy, close_enemy], 0.0)
	assert_eq(target, "far_enemy",
		"Rookie must stay locked on original target despite closer option")

func test_no_lock_break_when_closer_enemy_not_in_close_range():
	# BEHAVIOR: "Closer" only overrides the lock when the new threat is
	# genuinely in close range — not just slightly nearer at long distance.
	# This prevents constant target-switching in long-range engagements.
	var me = TestFactories.make_fighter("me", Vector2.ZERO, 0)
	var far_enemy = TestFactories.make_fighter("far_enemy", Vector2(3000, 0), 1)
	var mid_enemy = TestFactories.make_fighter("mid_enemy", Vector2(1500, 0), 1)  # closer, but NOT in CLOSE_RANGE

	var crew = _make_pilot_with_piloting(WingConstants.CLOSE_TARGET_RELOCK_SKILL + 0.1)
	crew.combat_state = {
		"locked_target_id": "far_enemy",
		"target_locked_until": 100.0
	}

	var target = FighterPilotAI._find_best_target(crew, [me, far_enemy, mid_enemy], 0.0)
	assert_eq(target, "far_enemy",
		"Lock should hold when closer enemy is outside close range — prevents long-range thrashing")
