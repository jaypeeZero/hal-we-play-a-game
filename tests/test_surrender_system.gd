extends GutTest

## Behavior tests: a side whose surviving ships are mostly fleeing for a
## sustained period surrenders; rallying cancels the countdown.

const TEAM_A := 0
const TEAM_B := 1
const TICK_DELTA := 0.5


func _make_fighter(id: String, team: int, status: String = "operational") -> Dictionary:
	return {
		"ship_id": id,
		"type": "fighter",
		"team": team,
		"position": Vector2.ZERO,
		"status": status,
		"orders": {"current_order": "", "target_id": ""},
	}


func _make_crew(crew_id: String, ship_id: String) -> Dictionary:
	return {
		"crew_id": crew_id,
		"role": CrewData.Role.PILOT,
		"assigned_to": ship_id,
		"combat_state": {},
		"orders": {"received": null},
	}


func _set_fleeing_orders(ship: Dictionary, mode: String = "retreat") -> Dictionary:
	ship.orders["survival_mode"] = mode
	return ship


## Tick repeatedly until total seconds have elapsed.
func _tick_for(state: Dictionary, ships: Array, crew: Array, seconds: float) -> Dictionary:
	var elapsed := 0.0
	while elapsed < seconds:
		state = SurrenderSystem.tick(state, ships, crew, TICK_DELTA)
		elapsed += TICK_DELTA
	return state


# ---------------------------------------------------------------------------
# is_ship_fleeing
# ---------------------------------------------------------------------------

func test_ship_with_survival_mode_retreat_is_fleeing():
	var ship = _set_fleeing_orders(_make_fighter("s1", TEAM_A), "retreat")
	assert_true(SurrenderSystem.is_ship_fleeing(ship, []),
		"survival_mode retreat must count as fleeing")


func test_ship_with_survival_mode_evade_is_fleeing():
	var ship = _set_fleeing_orders(_make_fighter("s1", TEAM_A), "evade")
	assert_true(SurrenderSystem.is_ship_fleeing(ship, []),
		"survival_mode evade must count as fleeing")


func test_crew_locked_on_evade_outnumbered_marks_ship_fleeing():
	var ship = _make_fighter("s1", TEAM_A)
	var crew = _make_crew("c1", "s1")
	crew.combat_state["locked_action_id"] = "evade_outnumbered"
	assert_true(SurrenderSystem.is_ship_fleeing(ship, [crew]),
		"GOAP evade_outnumbered lock must count as fleeing")


func test_large_ship_fighting_withdrawal_is_fleeing():
	var ship = _make_fighter("s1", TEAM_A)
	ship.orders["maneuver_subtype"] = "large_ship_fighting_withdrawal"
	assert_true(SurrenderSystem.is_ship_fleeing(ship, []),
		"large ship fighting withdrawal must count as fleeing")


func test_ordinary_combat_states_are_not_fleeing():
	# Normal firing-pass states (e.g. extending) must NOT read as fleeing.
	var ship = _make_fighter("s1", TEAM_A)
	ship.orders["maneuver_subtype"] = "fight_evasive_retreat"  # produced by "extending" phase
	ship.orders["survival_mode"] = ""
	var crew = _make_crew("c1", "s1")
	crew.combat_state["locked_action_id"] = "attack"
	crew.combat_state["engagement_phase"] = "extending"
	assert_false(SurrenderSystem.is_ship_fleeing(ship, [crew]),
		"extending firing pass / attack lock must not count as fleeing")


# ---------------------------------------------------------------------------
# tick — countdown lifecycle
# ---------------------------------------------------------------------------

func test_majority_fleeing_starts_countdown_and_it_decreases():
	var ships = [
		_set_fleeing_orders(_make_fighter("a1", TEAM_A)),
		_set_fleeing_orders(_make_fighter("a2", TEAM_A)),
		_make_fighter("a3", TEAM_A),
		_make_fighter("b1", TEAM_B),
		_make_fighter("b2", TEAM_B),
	]
	var state = SurrenderSystem.tick(SurrenderSystem.initial_state(), ships, [], TICK_DELTA)
	assert_true(state[TEAM_A].countdown_active, "2/3 fleeing must start the countdown")
	var first_remaining: float = state[TEAM_A].time_remaining

	state = SurrenderSystem.tick(state, ships, [], TICK_DELTA)
	assert_lt(state[TEAM_A].time_remaining, first_remaining,
		"countdown must decrease across ticks")
	assert_false(state[TEAM_B].countdown_active,
		"the non-fleeing team must have no countdown")


func test_countdown_expiry_reports_surrendered_team():
	var ships = [
		_set_fleeing_orders(_make_fighter("a1", TEAM_A)),
		_set_fleeing_orders(_make_fighter("a2", TEAM_A)),
		_make_fighter("b1", TEAM_B),
		_make_fighter("b2", TEAM_B),
	]
	var state = _tick_for(SurrenderSystem.initial_state(), ships, [],
		SurrenderSystem.SURRENDER_COUNTDOWN_SECONDS + TICK_DELTA)
	assert_eq(SurrenderSystem.surrendered_team(state), TEAM_A,
		"the fleeing team must surrender when the countdown expires")


func test_no_surrender_before_countdown_expires():
	var ships = [
		_set_fleeing_orders(_make_fighter("a1", TEAM_A)),
		_set_fleeing_orders(_make_fighter("a2", TEAM_A)),
		_make_fighter("b1", TEAM_B),
		_make_fighter("b2", TEAM_B),
	]
	var state = _tick_for(SurrenderSystem.initial_state(), ships, [],
		SurrenderSystem.SURRENDER_COUNTDOWN_SECONDS * 0.5)
	assert_eq(SurrenderSystem.surrendered_team(state), SurrenderSystem.NO_SURRENDER,
		"no surrender while the countdown is still running")


func test_rallying_cancels_countdown():
	var fleeing_a1 = _set_fleeing_orders(_make_fighter("a1", TEAM_A))
	var fleeing_a2 = _set_fleeing_orders(_make_fighter("a2", TEAM_A))
	var ships = [fleeing_a1, fleeing_a2, _make_fighter("b1", TEAM_B), _make_fighter("b2", TEAM_B)]
	var state = _tick_for(SurrenderSystem.initial_state(), ships, [],
		SurrenderSystem.SURRENDER_COUNTDOWN_SECONDS * 0.5)
	assert_true(state[TEAM_A].countdown_active)

	# The fleet rallies: pilots drop survival mode.
	fleeing_a1.orders["survival_mode"] = ""
	fleeing_a2.orders["survival_mode"] = ""
	state = SurrenderSystem.tick(state, ships, [], TICK_DELTA)
	assert_false(state[TEAM_A].countdown_active, "rallying must cancel the countdown")
	assert_eq(SurrenderSystem.surrendered_team(state), SurrenderSystem.NO_SURRENDER)

	# Fleeing again restarts from the full countdown, not where it left off.
	fleeing_a1.orders["survival_mode"] = "retreat"
	fleeing_a2.orders["survival_mode"] = "retreat"
	state = SurrenderSystem.tick(state, ships, [], TICK_DELTA)
	assert_almost_eq(state[TEAM_A].time_remaining,
		SurrenderSystem.SURRENDER_COUNTDOWN_SECONDS - TICK_DELTA, 0.001,
		"a restarted countdown must begin from the full duration")


func test_exactly_half_fleeing_is_not_a_majority():
	var ships = [
		_set_fleeing_orders(_make_fighter("a1", TEAM_A)),
		_make_fighter("a2", TEAM_A),
		_make_fighter("b1", TEAM_B),
		_make_fighter("b2", TEAM_B),
	]
	var state = SurrenderSystem.tick(SurrenderSystem.initial_state(), ships, [], TICK_DELTA)
	assert_false(state[TEAM_A].countdown_active,
		"exactly half fleeing must not start a countdown")


func test_destroyed_ships_are_excluded_from_the_count():
	# 1 fleeing of 2 alive (destroyed fleeing ship excluded from numerator,
	# destroyed non-fleeing ship excluded from denominator) -> no majority.
	var ships = [
		_set_fleeing_orders(_make_fighter("a1", TEAM_A)),
		_make_fighter("a2", TEAM_A),
		_set_fleeing_orders(_make_fighter("a3", TEAM_A, "destroyed")),
		_make_fighter("a4", TEAM_A, "destroyed"),
		_make_fighter("b1", TEAM_B),
		_make_fighter("b2", TEAM_B),
	]
	var state = SurrenderSystem.tick(SurrenderSystem.initial_state(), ships, [], TICK_DELTA)
	assert_false(state[TEAM_A].countdown_active,
		"destroyed ships must not count toward fleeing or alive totals")


func test_lone_surviving_ship_fleeing_does_not_surrender():
	var ships = [
		_set_fleeing_orders(_make_fighter("a1", TEAM_A)),
		_make_fighter("b1", TEAM_B),
		_make_fighter("b2", TEAM_B),
	]
	var state = SurrenderSystem.tick(SurrenderSystem.initial_state(), ships, [], TICK_DELTA)
	assert_false(state[TEAM_A].countdown_active,
		"a side below the minimum ship count must not start surrendering")


func test_fleeing_detected_via_assigned_crew_in_tick():
	# tick() must match crew to ships by assigned_to.
	var ships = [
		_make_fighter("a1", TEAM_A),
		_make_fighter("a2", TEAM_A),
		_make_fighter("b1", TEAM_B),
		_make_fighter("b2", TEAM_B),
	]
	var crew_a1 = _make_crew("c1", "a1")
	var crew_a2 = _make_crew("c2", "a2")
	crew_a1.combat_state["locked_action_id"] = "evade_outnumbered"
	crew_a2.combat_state["locked_action_id"] = "evade_outnumbered"
	var state = SurrenderSystem.tick(
		SurrenderSystem.initial_state(), ships, [crew_a1, crew_a2], TICK_DELTA)
	assert_true(state[TEAM_A].countdown_active,
		"crew flee locks must mark their assigned ships as fleeing")


# ---------------------------------------------------------------------------
# survival_mode lands on ship orders through CrewIntegrationSystem
# ---------------------------------------------------------------------------

func test_survival_reflex_decision_writes_survival_mode_to_ship_orders():
	var ship = _make_fighter("s1", TEAM_A)
	var crew = _make_crew("c1", "s1")
	var decision = {
		"type": "maneuver",
		"subtype": "fight_evasive_retreat",
		"target_id": "e1",
		"survival_mode": "retreat",
	}
	var updated = CrewIntegrationSystem.apply_maneuver_decision(ship, decision, crew)
	assert_true(SurrenderSystem.is_ship_fleeing(updated, []),
		"a survival-reflex decision must leave the ship readable as fleeing")

	# A later non-survival decision clears the flee flag.
	var calm_decision = {
		"type": "maneuver",
		"subtype": "fight_direct_approach",
		"target_id": "e1",
	}
	updated = CrewIntegrationSystem.apply_maneuver_decision(updated, calm_decision, crew)
	assert_false(SurrenderSystem.is_ship_fleeing(updated, []),
		"a non-survival decision must clear the flee flag")
