extends GutTest

## Behavior tests: elite pilots immediately re-evaluate when their current
## target dies. Rookies continue on their normal cadence.

var game_time: float = 10.0

func _make_pilot(id: String, ship_id: String, piloting: float) -> Dictionary:
	return {
		"crew_id": id,
		"role": CrewData.Role.PILOT,
		"assigned_to": ship_id,
		"is_squadron_leader": false,
		"stats": {
			"reaction_time": 0.1,
			"stress": 0.0,
			"fatigue": 0.0,
			"skills": {
				"piloting": piloting,
				"aim": 0.8,
				"awareness": 0.8,
				"tactics": 0.8,
				"composure": 0.8,
				"aggression": 0.5,
				"decision_time": 0.3
			}
		},
		"awareness": {
			"threats": ["dead_target"],
			"opportunities": [],
			"known_entities": []
		},
		"orders": {
			"current": {"target_id": "dead_target"},
			"received": null,
			"issued": []
		},
		"command_chain": {"superior": null, "subordinates": []},
		"combat_state": {}
	}

func _make_fighter(id: String, team: int, pos: Vector2, operational: bool = true) -> Dictionary:
	return {
		"ship_id": id,
		"type": "fighter",
		"team": team,
		"position": pos,
		"rotation": 0.0,
		"velocity": Vector2.ZERO,
		"status": "operational" if operational else "destroyed",
		"collision_radius": 15.0,
		"stats": {"max_speed": 300.0, "acceleration": 100.0, "turn_rate": 3.0, "mass": 50.0, "size": 15.0},
		"orders": {"current_order": "", "target_id": ""},
		"armor_sections": [{"section_id": "front", "current_armor": 100.0, "max_armor": 100.0, "arc": {"start": -90, "end": 90}}]
	}

func _make_context(all_ships: Array, crew_list: Array) -> Dictionary:
	return {
		"all_ships": all_ships,
		"all_crew": crew_list,
		"wings": []
	}

func test_elite_pilot_gets_fast_next_decision_when_target_dies():
	# BEHAVIOR: An elite pilot whose current target was just destroyed should
	# get a very short next_decision_time so they immediately re-evaluate and
	# pick a new target.
	var my_ship = _make_fighter("my_ship", 0, Vector2.ZERO)
	var dead_target = _make_fighter("dead_target", 1, Vector2(500, 0), false)
	var live_enemy = _make_fighter("live_enemy", 1, Vector2(800, 0), true)

	var crew = _make_pilot("elite_pilot", "my_ship", 0.9)
	var context = _make_context([my_ship, dead_target, live_enemy], [crew])

	var result = CrewAISystem.make_fighter_pilot_decision(crew, context, game_time)
	var updated = result.get("crew_data", {})
	var next_time = updated.get("next_decision_time", INF)

	assert_lt(next_time, game_time + 0.1,
		"Elite pilot should re-evaluate almost immediately when current target dies")

func test_rookie_pilot_gets_normal_decision_timing_when_target_dies():
	# BEHAVIOR: A rookie pilot whose current target died continues on their
	# normal (longer) decision cadence — they don't notice as quickly.
	var my_ship = _make_fighter("my_ship", 0, Vector2.ZERO)
	var dead_target = _make_fighter("dead_target", 1, Vector2(500, 0), false)
	var live_enemy = _make_fighter("live_enemy", 1, Vector2(800, 0), true)

	var crew = _make_pilot("rookie_pilot", "my_ship", 0.2)
	var context = _make_context([my_ship, dead_target, live_enemy], [crew])

	var result = CrewAISystem.make_fighter_pilot_decision(crew, context, game_time)
	var updated = result.get("crew_data", {})
	var next_time = updated.get("next_decision_time", INF)

	assert_gt(next_time, game_time + 0.1,
		"Rookie pilot should NOT get fast re-evaluation when target dies")

func test_elite_gets_faster_reassessment_than_rookie_when_target_dies():
	# BEHAVIOR: The timing difference between elite and rookie is the point —
	# elite pilots are quicker to exploit the kill by pivoting to the next target.
	var my_ship = _make_fighter("my_ship", 0, Vector2.ZERO)
	var dead_target = _make_fighter("dead_target", 1, Vector2(500, 0), false)
	var live_enemy = _make_fighter("live_enemy", 1, Vector2(800, 0), true)

	var elite_crew = _make_pilot("elite_pilot", "my_ship", 0.9)
	var rookie_crew = _make_pilot("rookie_pilot", "my_ship", 0.2)

	var context = _make_context([my_ship, dead_target, live_enemy], [elite_crew])
	var elite_result = CrewAISystem.make_fighter_pilot_decision(elite_crew, context, game_time)
	var elite_next = elite_result.get("crew_data", {}).get("next_decision_time", INF)

	context = _make_context([my_ship, dead_target, live_enemy], [rookie_crew])
	var rookie_result = CrewAISystem.make_fighter_pilot_decision(rookie_crew, context, game_time)
	var rookie_next = rookie_result.get("crew_data", {}).get("next_decision_time", INF)

	assert_lt(elite_next, rookie_next,
		"Elite pilot should reassess faster than rookie when target dies")
