extends GutTest

## Behavior tests: elite pilots begin evasive maneuvering the moment an enemy
## has a firing solution on them, before any shot is fired.

var game_time: float = 0.0

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
				"tactics": 0.5,
				"composure": 0.8,
				"aggression": 0.5
			}
		},
		"awareness": {
			"threats": ["enemy_ship"],
			"opportunities": [],
			"known_entities": []
		},
		"orders": {
			"current": {"target_id": "enemy_ship"},
			"received": null,
			"issued": []
		},
		"command_chain": {"superior": null, "subordinates": []},
		"combat_state": {}
	}

func _make_fighter(id: String, team: int, pos: Vector2, rot: float = 0.0) -> Dictionary:
	return {
		"ship_id": id,
		"type": "fighter",
		"team": team,
		"position": pos,
		"rotation": rot,
		"velocity": Vector2.ZERO,
		"status": "operational",
		"collision_radius": 15.0,
		"stats": {"max_speed": 300.0, "acceleration": 100.0, "turn_rate": 3.0, "mass": 50.0, "size": 15.0},
		"orders": {"current_order": "", "target_id": ""},
		"armor_sections": [{"section_id": "front", "current_armor": 100.0, "max_armor": 100.0, "arc": {"start": -90, "end": 90}}]
	}

func test_elite_pilot_evades_when_enemy_has_firing_solution():
	# BEHAVIOR: An elite pilot senses when an enemy's nose is pointed at them
	# within engagement range, and immediately begins evasive maneuvering before
	# any shot lands.
	#
	# My ship at (0,0), enemy at (2500, 0) facing LEFT = toward me.
	# get_visual_forward(rot) = Vector2(sin(rot), -cos(rot))
	# Facing left: sin(rot)=-1, -cos(rot)=0 → rot = -PI/2
	var my_ship = _make_fighter("my_ship", 0, Vector2.ZERO)
	var enemy = _make_fighter("enemy_ship", 1, Vector2(2500, 0), -PI / 2.0)

	var crew = _make_pilot("elite_pilot", "my_ship", 0.9)

	var decision = FighterPilotAI.make_decision(crew, my_ship, [my_ship, enemy], [crew], game_time)

	assert_eq(decision.subtype, "fight_dodge_and_weave",
		"Elite pilot should evade when enemy has a firing solution on them")
	assert_true(decision.get("pre_commit_evasion", false),
		"Decision should be tagged as pre-commit evasion")

func test_rookie_pilot_does_not_pre_commit_evade():
	# BEHAVIOR: A rookie pilot lacks the situational awareness to notice an enemy
	# lining up a shot before it arrives — they just charge or pursue normally.
	var my_ship = _make_fighter("my_ship", 0, Vector2.ZERO)
	var enemy = _make_fighter("enemy_ship", 1, Vector2(2500, 0), -PI / 2.0)

	var crew = _make_pilot("rookie_pilot", "my_ship", 0.3)

	var decision = FighterPilotAI.make_decision(crew, my_ship, [my_ship, enemy], [crew], game_time)

	assert_false(decision.get("pre_commit_evasion", false),
		"Rookie must NOT pre-commit evade — they cannot read enemy firing solutions")

func test_pre_commit_evasion_does_not_trigger_beyond_engagement_range():
	# BEHAVIOR: Pre-commit evasion is only relevant when an enemy is close enough
	# that their firing solution matters. An enemy beyond PRE_COMMIT_ENGAGEMENT_RANGE
	# poses no immediate threat even if they are facing us.
	var my_ship = _make_fighter("my_ship", 0, Vector2.ZERO)
	var far_enemy_x = WingConstants.PRE_COMMIT_ENGAGEMENT_RANGE + 500.0
	var enemy = _make_fighter("enemy_ship", 1, Vector2(far_enemy_x, 0), -PI / 2.0)

	var crew = _make_pilot("elite_pilot", "my_ship", 0.9)

	var decision = FighterPilotAI.make_decision(crew, my_ship, [my_ship, enemy], [crew], game_time)

	assert_false(decision.get("pre_commit_evasion", false),
		"Pre-commit evasion must not fire when enemy is beyond engagement range")
