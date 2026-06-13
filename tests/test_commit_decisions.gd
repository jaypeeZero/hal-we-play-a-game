extends GutTest

## Tests for Layer B — Captain/Commander commit decisions.
## Asserts BEHAVIOR: posture issued when triggers fire, not when progress is
## being made, posture absorption, concentrate-fire targeting.

const GAME_TIME := 200.0


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_captain(subordinates: Array = ["pilot_1"]) -> Dictionary:
	var crew := TestFactories.make_crew_captain(0.9, "ship_1")
	crew.command_chain.subordinates = subordinates
	return crew


func _make_commander(subordinates: Array = ["captain_1"]) -> Dictionary:
	var crew := TestFactories.make_crew_member(
		CrewData.Role.FLEET_COMMANDER, 0.9, "ship_1", null, subordinates
	)
	return crew


func _captain_ws_with(
	enemy_count: int,
	engagement_secs: float,
	net_delta: float,
	has_focus: bool = true
) -> CaptainWorldState:
	var crew := _make_captain()
	# Seed engagement_started_at so elapsed is correct.
	if not crew.has("combat_state"):
		crew["combat_state"] = {}
	crew["combat_state"]["engagement_started_at"] = GAME_TIME - engagement_secs

	# Inject threats to drive enemy_count.
	var threats: Array = []
	for i in range(enemy_count):
		threats.append({"id": "enemy_%d" % i, "status": "operational", "_threat_priority": 50.0})
	crew["awareness"]["threats"] = threats

	# Add a focus target via opportunities so mission_target is populated.
	if has_focus:
		crew["awareness"]["opportunities"] = [{"id": "cap_target", "_opportunity_score": 1.0, "_threat_priority": 1.0}]
	else:
		crew["awareness"]["opportunities"] = []

	var ws := CaptainWorldState.build(crew, GAME_TIME)

	# Directly override net_delta since the event logger isn't wired in unit tests.
	ws.focus_target_net_delta = net_delta
	ws.has_focus_target = has_focus
	return ws


func _commander_ws_with(
	enemy_count: int,
	engagement_secs: float,
	net_delta: float
) -> CommanderWorldState:
	var crew := _make_commander()
	if not crew.has("combat_state"):
		crew["combat_state"] = {}
	crew["combat_state"]["engagement_started_at"] = GAME_TIME - engagement_secs

	var threats: Array = []
	for i in range(enemy_count):
		threats.append({"id": "enemy_%d" % i, "status": "operational", "_threat_priority": 50.0})
	crew["awareness"]["threats"] = threats
	crew["awareness"]["opportunities"] = [{"id": "cap_target", "_opportunity_score": 1.0, "_threat_priority": 1.0}]

	var ws := CommanderWorldState.build(crew, GAME_TIME)
	ws.focus_target_net_delta = net_delta
	ws.has_focus_target = true
	return ws


# ---------------------------------------------------------------------------
# Trigger 1: few enemies + time
# ---------------------------------------------------------------------------

func test_captain_commits_when_few_enemies_and_time_elapsed():
	var ws := _captain_ws_with(1, WingConstants.COMMIT_ENGAGEMENT_SECONDS + 10.0, 999.0)
	var action := CaptainPressAttackAction.new()

	assert_true(action.precondition(ws),
		"Captain should commit when enemy count is at/below threshold and engagement is long")


func test_captain_does_not_commit_when_too_many_enemies():
	var ws := _captain_ws_with(
		WingConstants.COMMIT_ENEMY_COUNT_THRESHOLD + 5,
		WingConstants.COMMIT_ENGAGEMENT_SECONDS + 10.0,
		999.0
	)
	var ws_no_stalemate := ws
	ws_no_stalemate.focus_target_net_delta = WingConstants.COMMIT_STALL_NET_DAMAGE_EPSILON + 10.0
	var action := CaptainPressAttackAction.new()

	assert_false(action.precondition(ws_no_stalemate),
		"Captain must not commit on few-enemies trigger when many enemies remain")


func test_captain_does_not_commit_when_not_enough_time():
	var ws := _captain_ws_with(1, WingConstants.COMMIT_ENGAGEMENT_SECONDS * 0.3, 999.0)
	ws.focus_target_net_delta = WingConstants.COMMIT_STALL_NET_DAMAGE_EPSILON + 10.0
	var action := CaptainPressAttackAction.new()

	assert_false(action.precondition(ws),
		"Captain must not commit on few-enemies trigger before engagement time threshold")


# ---------------------------------------------------------------------------
# Trigger 2: stalemate
# ---------------------------------------------------------------------------

func test_captain_commits_on_stalemate():
	var ws := _captain_ws_with(
		WingConstants.COMMIT_ENEMY_COUNT_THRESHOLD + 5,  # many enemies — blocks trigger 1
		WingConstants.COMMIT_STALL_WINDOW_SECONDS + 5.0,
		0.0  # net delta == 0 → stalemate
	)
	var action := CaptainPressAttackAction.new()

	assert_true(action.precondition(ws),
		"Captain should commit when net hull delta is at/below epsilon (stalemate)")


func test_captain_does_not_commit_when_progress_is_positive():
	var large_net_damage := WingConstants.COMMIT_STALL_NET_DAMAGE_EPSILON + 50.0
	var ws := _captain_ws_with(
		WingConstants.COMMIT_ENEMY_COUNT_THRESHOLD + 5,
		WingConstants.COMMIT_STALL_WINDOW_SECONDS + 5.0,
		large_net_damage  # positive progress — not a stalemate
	)
	var action := CaptainPressAttackAction.new()

	assert_false(action.precondition(ws),
		"Captain must not commit when the fleet is making net progress on the target")


# ---------------------------------------------------------------------------
# Posture order output
# ---------------------------------------------------------------------------

func test_commit_action_issues_posture_orders_to_subordinates():
	var ws := _captain_ws_with(1, WingConstants.COMMIT_ENGAGEMENT_SECONDS + 10.0, 0.0)
	var action := CaptainPressAttackAction.new()
	var result := action.execute(ws)

	assert_true(result.has("issued_orders"),
		"Commit action should emit issued_orders")
	assert_false(result["issued_orders"].is_empty(),
		"At least one subordinate should receive a posture order")
	var order: Dictionary = result["issued_orders"][0]
	assert_eq(order.get("type", ""), "posture",
		"Order type must be 'posture'")
	assert_eq(order.get("subtype", ""), "press_attack",
		"Order subtype must be 'press_attack'")
	assert_gt(order.get("expires_at", 0.0), GAME_TIME,
		"Posture order must have a future expiry")


# ---------------------------------------------------------------------------
# Commander symmetry
# ---------------------------------------------------------------------------

func test_commander_commits_when_few_enemies_and_time():
	var ws := _commander_ws_with(1, WingConstants.COMMIT_ENGAGEMENT_SECONDS + 10.0, 999.0)
	var action := CommanderCommitAction.new()

	assert_true(action.precondition(ws),
		"Commander should commit on few-enemies + time trigger")


func test_commander_commits_on_stalemate():
	var ws := _commander_ws_with(
		WingConstants.COMMIT_ENEMY_COUNT_THRESHOLD + 5,
		WingConstants.COMMIT_STALL_WINDOW_SECONDS + 5.0,
		0.0
	)
	var action := CommanderCommitAction.new()

	assert_true(action.precondition(ws),
		"Commander should commit on stalemate trigger")


func test_commander_does_not_commit_when_progress_is_positive():
	var ws := _commander_ws_with(
		WingConstants.COMMIT_ENEMY_COUNT_THRESHOLD + 5,
		WingConstants.COMMIT_STALL_WINDOW_SECONDS + 5.0,
		WingConstants.COMMIT_STALL_NET_DAMAGE_EPSILON + 50.0
	)
	var action := CommanderCommitAction.new()

	assert_false(action.precondition(ws),
		"Commander must not commit when net progress is being made")


# ---------------------------------------------------------------------------
# Posture absorption: delivered press_attack → combat_posture slot
# ---------------------------------------------------------------------------

func test_absorbed_posture_sets_combat_posture_on_pilot():
	var pilot := TestFactories.make_pilot("p1", "ship_1")
	pilot.orders["received"] = {
		"type": "posture",
		"subtype": "press_attack",
		"target_id": "cap_target",
		"expires_at": GAME_TIME + WingConstants.COMMIT_POSTURE_DURATION,
		"player_override": false,
		"timestamp": GAME_TIME,
	}

	var updated := CrewAISystem._absorb_posture_order(pilot)

	assert_true(updated.has("combat_posture"),
		"Absorbed posture order should populate combat_posture")
	assert_eq(updated.combat_posture.get("subtype", ""), "press_attack",
		"combat_posture subtype must be press_attack")
	assert_null(updated.orders.received,
		"orders.received must be cleared after absorbing a posture")


func test_pilot_targets_posture_focus_when_press_active():
	# The posture's target_id should override normal target selection.
	var pilot := TestFactories.make_pilot("p1", "fighter_1")
	pilot["combat_posture"] = {
		"subtype": "press_attack",
		"target_id": "cap_target",
		"expires_at": GAME_TIME + 30.0,
		"player_override": false,
	}
	var fighter := TestFactories.make_fighter("fighter_1", Vector2.ZERO)
	var capital := TestFactories.make_capital("cap_target", Vector2(2000, 0), 1)

	var ws := FighterWorldState.build(pilot, fighter, [fighter, capital], [], GAME_TIME, [])

	assert_true(ws.press_attack, "press_attack should be active with valid posture")
	assert_eq(ws.target_id, "cap_target",
		"FighterWorldState should target the posture's focus target")


# ---------------------------------------------------------------------------
# TacticalProgressSystem helpers
# ---------------------------------------------------------------------------

func test_engagement_elapsed_zero_before_first_contact():
	var crew := _make_captain()
	var elapsed := TacticalProgressSystem.engagement_elapsed(crew, GAME_TIME)
	assert_eq(elapsed, 0.0,
		"Engagement elapsed should be 0 when no engagement has been recorded")


func test_engagement_elapsed_grows_after_stamp():
	var crew := _make_captain()
	if not crew.has("combat_state"):
		crew["combat_state"] = {}
	crew["combat_state"]["engagement_started_at"] = GAME_TIME - 30.0

	var elapsed := TacticalProgressSystem.engagement_elapsed(crew, GAME_TIME)
	assert_almost_eq(elapsed, 30.0, 0.01,
		"Engagement elapsed should reflect time since stamp")


func test_maybe_stamp_only_stamps_once():
	var crew := _make_captain()
	crew["awareness"]["threats"] = [{"id": "e1", "status": "operational"}]

	var stamped1 := TacticalProgressSystem.maybe_stamp_engagement_start(crew, GAME_TIME)
	var stamped2 := TacticalProgressSystem.maybe_stamp_engagement_start(stamped1, GAME_TIME + 10.0)

	assert_almost_eq(
		stamped2.get("combat_state", {}).get("engagement_started_at", -1.0),
		GAME_TIME, 0.01,
		"Engagement start time must not be overwritten on a second call"
	)
