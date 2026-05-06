extends GutTest

## Verifies the pincer play actually creates pincer geometry — pair B's
## phase-2 waypoint sits behind the target, while pair A stays in front.

const PINCER_PLAYS := {
	"pincer": {
		"min_tactics": 0.5,
		"min_wing_size": 4,
		"phases": [
			{
				"duration": 3.0,
				"roles": {"A": "engage_frontal", "B": "loop_wide_left"},
			},
			{
				"duration": 4.5,
				"roles": {"A": "hold_pressure", "B": "approach_target_six"},
			},
			{
				"duration": 0.0,
				"roles": {"A": "merge_attack", "B": "merge_attack"},
			},
		],
	},
}

func before_each() -> void:
	SquadronPlaySystem._inject_plays_for_test(PINCER_PLAYS)

func _elite_leader() -> Dictionary:
	# Elite tactics so jitter is zero and offsets are crisp for assertions.
	return {
		"crew_id": "leader",
		"stats": {"skill": 1.0, "skills": {"tactics": 1.0}},
	}

func _wing4() -> Dictionary:
	# Role assignment is round-robin over the role letters A,B in alphabetical
	# order — so fighters[0,2] → "A" and fighters[1,3] → "B". Tests resolve
	# pair membership through `role_assignments` rather than relying on names.
	return {"fighters": ["f1", "f2", "f3", "f4"]}

func _fighters_in_role(assignments: Dictionary, letter: String) -> Array:
	var out: Array = []
	for fid in assignments.keys():
		if assignments[fid] == letter:
			out.append(fid)
	return out

# Target sits at origin facing +X. "Behind the target" therefore means
# negative-X positions; "in front" means positive-X.
func _geometry() -> Dictionary:
	return {
		"target_id": "enemy",
		"target_position": Vector2.ZERO,
		"target_facing": Vector2(1, 0),
	}

func test_phase_1_splits_pair_a_front_pair_b_lateral():
	var leader := _elite_leader()
	var selection := SquadronPlaySystem.select_play(leader, _wing4(), _geometry())
	var play := SquadronPlaySystem.init_active_play(selection, leader, 0.0)
	var ticked := SquadronPlaySystem.tick_play(play, 0.0, _geometry())

	var offsets: Dictionary = ticked.fighter_offsets
	var pair_a := _fighters_in_role(selection.role_assignments, "A")
	var pair_b := _fighters_in_role(selection.role_assignments, "B")
	assert_gt(pair_a.size(), 0, "Pair A populated")
	assert_gt(pair_b.size(), 0, "Pair B populated")

	# Pair A engages frontally — should be in front (positive X).
	for ship_id in pair_a:
		var off: Vector2 = offsets[ship_id]
		assert_gt(off.x, 0.0, "%s assigned frontal — should be in front of target" % ship_id)
	# Pair B loops wide left — should have large lateral offset.
	for ship_id in pair_b:
		var off: Vector2 = offsets[ship_id]
		assert_gt(absf(off.y), 1000.0, "%s loops wide — should have big lateral offset" % ship_id)

func test_phase_2_pair_b_arcs_to_target_six():
	var leader := _elite_leader()
	var selection := SquadronPlaySystem.select_play(leader, _wing4(), _geometry())
	var play := SquadronPlaySystem.init_active_play(selection, leader, 0.0)
	# Advance into phase 2 (after first phase's 3.0s duration).
	var ticked := SquadronPlaySystem.tick_play(play, 4.0, _geometry())

	assert_eq(ticked.phase_index, 1, "Should be in phase 1 (the second phase)")
	var offsets: Dictionary = ticked.fighter_offsets
	var pair_a := _fighters_in_role(selection.role_assignments, "A")
	var pair_b := _fighters_in_role(selection.role_assignments, "B")

	# Pair A holds pressure — still in front of target.
	for ship_id in pair_a:
		assert_gt(offsets[ship_id].x, 0.0,
			"%s holds pressure — should still be in front" % ship_id)
	# Pair B approaches the six — must be BEHIND target (negative X).
	for ship_id in pair_b:
		assert_lt(offsets[ship_id].x, 0.0,
			"%s approaches the six — should be behind target" % ship_id)

func test_phase_3_merge_collapses_to_target():
	var leader := _elite_leader()
	var selection := SquadronPlaySystem.select_play(leader, _wing4(), _geometry())
	var play := SquadronPlaySystem.init_active_play(selection, leader, 0.0)
	# Advance well past both phase durations into the merge.
	var ticked := SquadronPlaySystem.tick_play(play, 20.0, _geometry())

	assert_eq(ticked.phase_index, 2, "Should be in the merge phase")
	# Merge offsets are the target itself (modulo jitter, which is 0 for elite).
	for ship_id in selection.role_assignments.keys():
		var off: Vector2 = ticked.fighter_offsets[ship_id]
		assert_lt(off.length(), 1.0, "%s merges on target (offset ≈ 0)" % ship_id)
