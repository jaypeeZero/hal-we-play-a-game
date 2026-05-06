extends GutTest

## Verifies that squadron-play selection scales with leader tactics:
## elite leaders unlock higher-tier plays (pincer/bracket/kill_box), while
## rookie leaders fall through with no play selected at all.

const TEST_PLAYS := {
	"pincer": {
		"min_tactics": 0.5,
		"min_wing_size": 4,
		"phases": [
			{"duration": 3.0, "roles": {"A": "engage_frontal", "B": "loop_wide_left"}},
			{"duration": 0.0, "roles": {"A": "merge_attack", "B": "merge_attack"}},
		],
	},
	"kill_box": {
		"min_tactics": 0.75,
		"min_wing_size": 6,
		"phases": [
			{"duration": 2.0, "roles": {"A": "engage_frontal", "B": "flank_left", "C": "flank_right"}},
			{"duration": 0.0, "roles": {"A": "merge_attack", "B": "merge_attack", "C": "merge_attack"}},
		],
	},
}

func before_each() -> void:
	SquadronPlaySystem._inject_plays_for_test(TEST_PLAYS)

func _make_leader(tactics: float) -> Dictionary:
	return {
		"crew_id": "leader",
		"stats": {"skill": tactics, "skills": {"tactics": tactics}},
	}

func _wing(n: int) -> Dictionary:
	var fighters: Array = []
	for i in n:
		fighters.append("fighter_%d" % i)
	return {"fighters": fighters}

func _geometry() -> Dictionary:
	return {
		"target_id": "enemy_1",
		"target_position": Vector2(2000, 0),
		"target_facing": Vector2(-1, 0),
	}

func test_elite_leader_with_full_wing_unlocks_top_tier_play():
	var elite := _make_leader(0.9)
	var selection := SquadronPlaySystem.select_play(elite, _wing(6), _geometry())

	assert_false(selection.is_empty(), "Elite + 6 fighters should pick a play")
	assert_eq(selection.play_id, "kill_box", "Elite should pick the most ambitious qualifying play")

func test_mid_skill_leader_picks_qualifying_lower_tier_play():
	var mid := _make_leader(0.6)
	var selection := SquadronPlaySystem.select_play(mid, _wing(4), _geometry())

	assert_false(selection.is_empty(), "Mid-tactics leader should pick a play")
	assert_eq(selection.play_id, "pincer", "Mid should pick pincer (only one they qualify for)")

func test_rookie_leader_picks_no_play():
	var rookie := _make_leader(0.2)
	var selection := SquadronPlaySystem.select_play(rookie, _wing(6), _geometry())

	assert_true(selection.is_empty(), "Rookie below min_tactics gates picks no play")

func test_undersized_wing_blocks_play_even_for_elite():
	var elite := _make_leader(0.95)
	var selection := SquadronPlaySystem.select_play(elite, _wing(2), _geometry())

	assert_true(selection.is_empty(), "Elite with too few fighters falls back to no play")

func test_role_assignments_cover_all_fighters():
	var elite := _make_leader(0.9)
	var fighters := _wing(6)
	var selection := SquadronPlaySystem.select_play(elite, fighters, _geometry())

	var assignments: Dictionary = selection.role_assignments
	assert_eq(assignments.size(), 6, "Every fighter gets a role")
	# Verify role distribution is approximately even — no fighter is left out.
	for fighter_id in fighters.fighters:
		assert_true(assignments.has(fighter_id), "Fighter %s assigned a role" % fighter_id)

func test_no_target_blocks_selection():
	var elite := _make_leader(0.9)
	var geometry := _geometry()
	geometry.target_id = ""
	var selection := SquadronPlaySystem.select_play(elite, _wing(6), geometry)

	assert_true(selection.is_empty(), "Without a target, no play is selected")
