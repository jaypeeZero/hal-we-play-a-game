extends GutTest

## Tests for Layer C — Player "All-Out Attack" order.
## Verifies that issuing the order stamps press_attack posture on every
## player-team pilot/captain and that cancelling strips it again.
## Uses minimal mocks — we test the pure posture-writing logic, not the
## full game node (which requires a running scene).

const GAME_TIME := 150.0


# ---------------------------------------------------------------------------
# Helpers — thin stand-ins for the game-side data the methods read
# ---------------------------------------------------------------------------

func _make_player_pilot(ship_id: String = "fighter_1") -> Dictionary:
	var crew := TestFactories.make_pilot("p_player", ship_id)
	return crew


func _make_enemy_pilot(ship_id: String = "enemy_1") -> Dictionary:
	var crew := TestFactories.make_pilot("p_enemy", ship_id)
	return crew


func _make_player_captain(ship_id: String = "cap_ship") -> Dictionary:
	return TestFactories.make_crew_captain(0.9, ship_id)


func _make_player_engineer(ship_id: String = "fighter_1") -> Dictionary:
	return TestFactories.make_crew_member(CrewData.Role.ENGINEER, 0.7, ship_id)


## Simulate _issue_allout_attack on a crew list + ship map.
## Returns the mutated crew list (same references, posture written in-place).
func _issue_allout_attack(
	crew_list: Array,
	ship_map: Dictionary,  # id -> ship dict (must include "team")
	game_time: float
) -> Array:
	var posture := {
		"type": "posture",
		"subtype": "press_attack",
		"target_id": "",
		"expires_at": 0.0,
		"player_override": true,
		"timestamp": game_time,
	}
	for crew in crew_list:
		var role: int = crew.get("role", -1)
		if role not in [CrewData.Role.PILOT, CrewData.Role.CAPTAIN]:
			continue
		var ship_id: String = crew.get("assigned_to", "")
		var ship: Dictionary = ship_map.get(ship_id, {})
		if ship.is_empty() or ship.get("team", -1) != 0:
			continue
		crew["combat_posture"] = posture.duplicate(true)
	return crew_list


func _cancel_allout_attack(crew_list: Array, ship_map: Dictionary) -> Array:
	for crew in crew_list:
		var role: int = crew.get("role", -1)
		if role not in [CrewData.Role.PILOT, CrewData.Role.CAPTAIN]:
			continue
		var ship_id: String = crew.get("assigned_to", "")
		var ship: Dictionary = ship_map.get(ship_id, {})
		if ship.is_empty() or ship.get("team", -1) != 0:
			continue
		var posture: Dictionary = crew.get("combat_posture", {})
		if posture.get("player_override", false):
			crew["combat_posture"] = {}
	return crew_list


# ---------------------------------------------------------------------------
# Issue order
# ---------------------------------------------------------------------------

func test_issue_stamps_press_attack_on_player_pilots():
	var pilot := _make_player_pilot("f1")
	var ship_map := {"f1": {"id": "f1", "team": 0}}

	_issue_allout_attack([pilot], ship_map, GAME_TIME)

	assert_true(pilot.has("combat_posture"),
		"Player pilot should receive a combat_posture after all-out attack issued")
	assert_eq(pilot.combat_posture.get("subtype", ""), "press_attack",
		"combat_posture subtype must be press_attack")
	assert_true(pilot.combat_posture.get("player_override", false),
		"Issued posture must carry player_override=true")


func test_issue_stamps_press_attack_on_player_captains():
	var captain := _make_player_captain("cs1")
	var ship_map := {"cs1": {"id": "cs1", "team": 0}}

	_issue_allout_attack([captain], ship_map, GAME_TIME)

	assert_true(captain.has("combat_posture"),
		"Player captain should receive combat_posture")
	assert_eq(captain.combat_posture.get("subtype", ""), "press_attack")


func test_issue_does_not_stamp_engineers():
	var engineer := _make_player_engineer("f1")
	var ship_map := {"f1": {"id": "f1", "team": 0}}

	_issue_allout_attack([engineer], ship_map, GAME_TIME)

	assert_false(engineer.has("combat_posture"),
		"Engineer must not receive a combat_posture from all-out attack order")


func test_issue_does_not_stamp_enemy_pilots():
	var enemy_pilot := _make_enemy_pilot("e1")
	var ship_map := {"e1": {"id": "e1", "team": 1}}  # enemy team

	_issue_allout_attack([enemy_pilot], ship_map, GAME_TIME)

	assert_false(enemy_pilot.has("combat_posture"),
		"Enemy pilot must not receive the all-out attack posture")


func test_issue_stamps_all_player_pilots_in_mixed_fleet():
	var p1 := _make_player_pilot("f1")
	var p2 := _make_player_pilot("f2")
	var enemy := _make_enemy_pilot("e1")
	var engineer := _make_player_engineer("f1")
	var ship_map := {
		"f1": {"id": "f1", "team": 0},
		"f2": {"id": "f2", "team": 0},
		"e1": {"id": "e1", "team": 1},
	}

	_issue_allout_attack([p1, p2, enemy, engineer], ship_map, GAME_TIME)

	assert_true(p1.has("combat_posture"), "First player pilot must be stamped")
	assert_true(p2.has("combat_posture"), "Second player pilot must be stamped")
	assert_false(enemy.has("combat_posture"), "Enemy must not be stamped")
	assert_false(engineer.has("combat_posture"), "Engineer must not be stamped")


# ---------------------------------------------------------------------------
# FighterWorldState reads the player-issued posture
# ---------------------------------------------------------------------------

func test_player_issued_posture_activates_press_attack_in_world_state():
	var crew := _make_player_pilot("fighter_1")
	crew["combat_posture"] = {
		"subtype": "press_attack",
		"target_id": "",
		"expires_at": 0.0,
		"player_override": true,
	}
	var fighter := TestFactories.make_fighter("fighter_1", Vector2.ZERO)
	var capital := TestFactories.make_capital("cap1", Vector2(2000, 0), 1)

	var ws := FighterWorldState.build(crew, fighter, [fighter, capital], [], GAME_TIME, [])

	assert_true(ws.press_attack,
		"player_override posture should activate press_attack in FighterWorldState")


func test_player_issued_posture_selects_press_maneuver():
	var crew := _make_player_pilot("fighter_1")
	crew["combat_posture"] = {
		"subtype": "press_attack",
		"target_id": "",
		"expires_at": 0.0,
		"player_override": true,
	}
	var fighter := TestFactories.make_fighter("fighter_1", Vector2.ZERO)
	var capital := TestFactories.make_capital("cap1", Vector2(2000, 0), 1)

	var ws := FighterWorldState.build(crew, fighter, [fighter, capital], [], GAME_TIME, [])
	var action := AttackAction.new()
	var decision := action.execute(ws)

	# Press-attack now routes through the blender (subtype "tactical") with the
	# aggressive "press" posture rather than a discrete fight_press_attack maneuver.
	assert_eq(decision.get("subtype", ""), "tactical",
		"Player all-out order routes the fighter through the blended press posture")
	var gw: Dictionary = decision.get("goal_weights", {})
	assert_gt(gw.get("pursue", 0.0), gw.get("keep_range", 1.0),
		"All-out press makes pursue the dominant goal — the fighter commits and closes")


# ---------------------------------------------------------------------------
# Cancel order
# ---------------------------------------------------------------------------

func test_cancel_removes_player_override_postures():
	var pilot := _make_player_pilot("f1")
	pilot["combat_posture"] = {
		"subtype": "press_attack",
		"target_id": "",
		"expires_at": 0.0,
		"player_override": true,
	}
	var ship_map := {"f1": {"id": "f1", "team": 0}}

	_cancel_allout_attack([pilot], ship_map)

	assert_true(pilot.combat_posture.is_empty(),
		"Cancel should clear player_override posture from player pilot")


func test_cancel_does_not_remove_ai_postures():
	# AI-issued postures have player_override=false; cancel must not touch them.
	var pilot := _make_player_pilot("f1")
	pilot["combat_posture"] = {
		"subtype": "press_attack",
		"target_id": "t1",
		"expires_at": GAME_TIME + 30.0,
		"player_override": false,  # AI-issued
	}
	var ship_map := {"f1": {"id": "f1", "team": 0}}

	_cancel_allout_attack([pilot], ship_map)

	assert_false(pilot.combat_posture.is_empty(),
		"Cancel must not remove AI-issued (non-player_override) postures")


func test_cancel_does_not_affect_enemy_postures():
	var enemy := _make_enemy_pilot("e1")
	enemy["combat_posture"] = {
		"subtype": "press_attack",
		"player_override": true,
	}
	var ship_map := {"e1": {"id": "e1", "team": 1}}

	_cancel_allout_attack([enemy], ship_map)

	# Enemy should still have it (cancel only touches team 0)
	assert_true(enemy.has("combat_posture") and not enemy.combat_posture.is_empty(),
		"Cancel must not strip postures from enemy crew")


func test_issue_then_cancel_restores_neutral_posture():
	var pilot := _make_player_pilot("f1")
	var ship_map := {"f1": {"id": "f1", "team": 0}}

	_issue_allout_attack([pilot], ship_map, GAME_TIME)
	assert_true(pilot.has("combat_posture"), "Posture should exist after issue")

	_cancel_allout_attack([pilot], ship_map)
	assert_true(pilot.combat_posture.is_empty(),
		"After cancel, pilot posture should be cleared")

	# And the fighter world state should no longer press
	var fighter := TestFactories.make_fighter("f1", Vector2.ZERO)
	var capital := TestFactories.make_capital("cap1", Vector2(2000, 0), 1)
	var ws := FighterWorldState.build(pilot, fighter, [fighter, capital], [], GAME_TIME, [])
	assert_false(ws.press_attack,
		"After cancel, FighterWorldState should not have press_attack active")
