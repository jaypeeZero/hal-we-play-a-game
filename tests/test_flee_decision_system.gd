extends GutTest

## Behavior tests for the commit-to-flee decision: pressure (low hull,
## outnumbered, survival mode, captain order) vs resolve (composure/aggression).
## Asserts capabilities, not the exact weight arithmetic.

const TEAM_A := 0
const TEAM_B := 1


func _crew(composure: float, aggression: float, received = null) -> Dictionary:
	return {
		"crew_id": "c1",
		"stats": {"skills": {"composure": composure, "aggression": aggression, "piloting": 0.5}},
		"orders": {"received": received},
	}


## A ship with `armor_ratio` of its armor remaining, at `pos`, in `survival_mode`.
func _ship(armor_ratio: float, survival_mode := "", pos := Vector2.ZERO) -> Dictionary:
	return {
		"ship_id": "s1",
		"type": "fighter",
		"team": TEAM_A,
		"position": pos,
		"status": "operational",
		"armor_sections": [{"current_armor": armor_ratio * 100.0, "max_armor": 100.0}],
		"orders": {"survival_mode": survival_mode, "current_order": ""},
	}


func _enemy(id: String, pos: Vector2) -> Dictionary:
	return {"ship_id": id, "type": "fighter", "team": TEAM_B, "position": pos, "status": "operational"}


func test_low_hull_outnumbered_and_evading_commits():
	var crew := _crew(0.3, 0.3)
	var ship := _ship(0.1, "evade")
	var enemies: Array = [
		_enemy("e1", Vector2(100, 0)),
		_enemy("e2", Vector2(150, 0)),
		_enemy("e3", Vector2(200, 0)),
	]
	assert_eq(FleeDecisionSystem.decide(crew, ship, [ship] + enemies),
		FleeDecisionSystem.COMMITTED,
		"low hull + outnumbered + evading must commit to flee")


func test_healthy_high_composure_not_outnumbered_returns():
	var crew := _crew(1.0, 0.8)
	var ship := _ship(1.0)
	assert_eq(FleeDecisionSystem.decide(crew, ship, [ship]),
		FleeDecisionSystem.RETURNING,
		"a healthy, steady, unthreatened pilot turns back")


func test_captain_retreat_order_forces_commit():
	var crew := _crew(1.0, 1.0, {"type": "withdraw"})
	var ship := _ship(1.0)
	assert_eq(FleeDecisionSystem.decide(crew, ship, [ship]),
		FleeDecisionSystem.COMMITTED,
		"a fleet retreat order forces a commit regardless of resolve")


func test_decision_is_a_pure_function_of_inputs():
	var crew := _crew(0.3, 0.3)
	var ship := _ship(0.1, "evade")
	var enemies: Array = [
		_enemy("e1", Vector2(100, 0)),
		_enemy("e2", Vector2(150, 0)),
		_enemy("e3", Vector2(200, 0)),
	]
	var all_ships: Array = [ship] + enemies
	var first := FleeDecisionSystem.decide(crew, ship, all_ships)
	var second := FleeDecisionSystem.decide(crew, ship, all_ships)
	assert_eq(first, second, "same inputs must yield the same decision")
