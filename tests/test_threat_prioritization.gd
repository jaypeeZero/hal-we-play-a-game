extends GutTest

## Phase 03: threat prioritization quality scales with crew skill.
##
## Awareness gates how many threats the crew can hold on their list at all;
## tactics shapes whether they are correctly *ordered* by urgency. Elite
## crew see more threats and rank them cleanly; rookies see fewer and
## sometimes mis-prioritise which one to react to first.

func _make_crew(awareness: float, tactics: float) -> Dictionary:
	var crew = CrewData.create_crew_member(CrewData.Role.PILOT, 0.5)
	crew.stats.skills.awareness = awareness
	crew.stats.skills.tactics = tactics
	return crew

func _own_ship() -> Dictionary:
	return {
		"ship_id": "me",
		"team": 0,
		"position": Vector2.ZERO,
		"velocity": Vector2.ZERO,
		"rotation": 0.0,
		"status": "operational"
	}

## Build a threat heading toward us. The closer / faster-closing the
## bandit, the higher the urgency.
func _make_threat(id: String, distance: float, closing_speed: float, base_priority: float = 50.0) -> Dictionary:
	# Place the bandit on +X with velocity heading back toward origin.
	return {
		"id": id,
		"type": "ship",
		"team": 1,
		"position": Vector2(distance, 0),
		"velocity": Vector2(-closing_speed, 0),
		"_threat_priority": base_priority
	}

# ----------------------------------------------------------------------------
# Ordering
# ----------------------------------------------------------------------------

func test_high_tactics_orders_threats_by_urgency_descending():
	# Three threats: one closing fast and near, one slower and farther, one
	# basically static. A high-tactics, max-awareness crew must rank them in
	# strict urgency order.
	var crew = _make_crew(1.0, 1.0)
	var threats = [
		_make_threat("static",   600.0,    5.0),
		_make_threat("nearfast",  200.0, 300.0),
		_make_threat("midslow",   400.0,  60.0),
	]

	var ranked = InformationSystem.prioritize_threats(threats, crew, _own_ship())

	assert_eq(ranked.size(), 3, "All three threats fit under the awareness cap.")
	assert_eq(ranked[0].id, "nearfast", "Closest+fastest closer must be #1.")
	assert_eq(ranked[2].id, "static",   "Static bandit must be last.")

func test_low_tactics_can_misorder_close_threats():
	# Two threats whose urgency scores are close — within reach of the
	# tactics-noise multiplier. A high-tactics crew always picks the same
	# winner; a zero-tactics crew flips order at least occasionally over
	# many trials.
	seed(0)
	var rookie = _make_crew(1.0, 0.0)
	var elite = _make_crew(1.0, 1.0)
	# Same closing speed, slightly different distances → similar urgencies.
	var threats = [
		_make_threat("a", 200.0, 200.0),
		_make_threat("b", 220.0, 200.0),
	]

	# Elite is deterministic.
	for i in range(20):
		var ranked = InformationSystem.prioritize_threats(threats, elite, _own_ship())
		assert_eq(ranked[0].id, "a", "Elite must always pick the urgency-best threat.")

	# Rookie should flip at least once across 50 trials.
	var saw_misorder := false
	for i in range(50):
		var ranked = InformationSystem.prioritize_threats(threats, rookie, _own_ship())
		if ranked[0].id != "a":
			saw_misorder = true
			break

	assert_true(saw_misorder,
		"Low-tactics crew should sometimes mis-prioritize close-urgency threats.")

# ----------------------------------------------------------------------------
# Awareness cap
# ----------------------------------------------------------------------------

func test_low_awareness_drops_low_urgency_threats():
	# Eight threats; an awareness-0.25 crew should only carry ~2 (floor of
	# 0.25 * MAX_VISIBLE_THREATS). The kept threats must be the highest-urgency.
	var crew = _make_crew(0.25, 1.0)
	var threats = []
	for i in range(8):
		# Vary closing speed so urgency strictly decreases.
		threats.append(_make_threat("t_%d" % i, 300.0, 400.0 - i * 40.0))

	var ranked = InformationSystem.prioritize_threats(threats, crew, _own_ship())

	assert_lt(ranked.size(), threats.size(),
		"Low awareness must drop some threats off the visible list.")
	assert_eq(ranked[0].id, "t_0",
		"Highest-urgency threat survives the awareness cap.")

func test_high_awareness_keeps_full_list():
	var crew = _make_crew(1.0, 1.0)
	var threats = []
	for i in range(WingConstants.MAX_VISIBLE_THREATS):
		threats.append(_make_threat("t_%d" % i, 300.0, 400.0 - i * 10.0))

	var ranked = InformationSystem.prioritize_threats(threats, crew, _own_ship())

	assert_eq(ranked.size(), WingConstants.MAX_VISIBLE_THREATS,
		"Full-awareness crew sees every threat up to the global cap.")

func test_awareness_cap_keeps_at_least_one_threat():
	# A 0.0-awareness crew is not blind — they still see the single
	# most-urgent threat (you don't fail to notice the bandit on your nose).
	var crew = _make_crew(0.0, 1.0)
	var threats = [
		_make_threat("near", 200.0, 300.0),
		_make_threat("far",  900.0,   5.0),
	]
	var ranked = InformationSystem.prioritize_threats(threats, crew, _own_ship())
	assert_eq(ranked.size(), 1, "Even at zero awareness, one threat survives.")
	assert_eq(ranked[0].id, "near", "And it's the highest-urgency one.")
