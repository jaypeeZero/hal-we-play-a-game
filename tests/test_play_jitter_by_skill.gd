extends GutTest

## Verifies that play execution scatter is ordered by leader tactics:
## elite leaders' fighters land tightly on planned offsets, rookie leaders'
## scatter further. Uses the deterministic per-ship jitter so the assertion
## is a strict ordering rather than a probabilistic check.

const SIMPLE_PLAYS := {
	"pincer": {
		"min_tactics": 0.0,
		"min_wing_size": 2,
		"phases": [
			{"duration": 5.0, "roles": {"A": "engage_frontal", "B": "loop_wide_left"}},
		],
	},
}

func before_each() -> void:
	SquadronPlaySystem._inject_plays_for_test(SIMPLE_PLAYS)

func _leader(tactics: float) -> Dictionary:
	return {"crew_id": "leader", "stats": {"skill": tactics, "skills": {"tactics": tactics}}}

func _wing() -> Dictionary:
	return {"fighters": ["f1", "f2", "f3", "f4"]}

func _geometry() -> Dictionary:
	return {
		"target_id": "enemy",
		"target_position": Vector2.ZERO,
		"target_facing": Vector2(1, 0),
	}

func _scatter_for_tactics(tactics: float) -> float:
	# Sum of distances from each fighter's actual offset to its planned
	# (no-jitter) offset. Higher = sloppier execution.
	var leader := _leader(tactics)
	var selection := SquadronPlaySystem.select_play(leader, _wing(), _geometry())
	var play := SquadronPlaySystem.init_active_play(selection, leader, 0.0)
	var ticked := SquadronPlaySystem.tick_play(play, 0.0, _geometry())

	var elite_leader := _leader(1.0)  # baseline: no jitter
	var elite_play := SquadronPlaySystem.init_active_play(
		SquadronPlaySystem.select_play(elite_leader, _wing(), _geometry()),
		elite_leader, 0.0)
	var elite_ticked := SquadronPlaySystem.tick_play(elite_play, 0.0, _geometry())

	var total := 0.0
	for fid in ticked.fighter_offsets.keys():
		var actual: Vector2 = ticked.fighter_offsets[fid]
		var planned: Vector2 = elite_ticked.fighter_offsets[fid]
		total += actual.distance_to(planned)
	return total

func test_scatter_strictly_ordered_by_tactics():
	var elite_scatter := _scatter_for_tactics(1.0)
	var mid_scatter := _scatter_for_tactics(0.5)
	var rookie_scatter := _scatter_for_tactics(0.0)

	assert_almost_eq(elite_scatter, 0.0, 0.5,
		"Elite leader produces effectively zero scatter")
	assert_gt(mid_scatter, elite_scatter,
		"Mid-tactics leader scatters more than elite")
	assert_gt(rookie_scatter, mid_scatter,
		"Rookie leader scatters more than mid")

func test_apply_jitter_amplitude_scales_with_one_minus_tactics():
	# Stochastic check via repeated samples. Compare mean magnitude of jitter
	# applied to the same base offset across many trials.
	seed(12345)
	var samples := 200
	var elite_total := 0.0
	var rookie_total := 0.0
	for _i in samples:
		var elite_jitter := SquadronPlaySystem.apply_jitter(Vector2.ZERO, 1.0)
		var rookie_jitter := SquadronPlaySystem.apply_jitter(Vector2.ZERO, 0.0)
		elite_total += elite_jitter.length()
		rookie_total += rookie_jitter.length()
	assert_almost_eq(elite_total, 0.0, 0.5, "Elite stochastic jitter is zero")
	assert_gt(rookie_total, 100.0, "Rookie stochastic jitter has substantial mean magnitude")
