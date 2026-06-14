extends GutTest

## Reaction commit delay must be strictly ordered by the gating skill —
## `piloting` for pilots, `tactics` for capital captains. Combined with
## detection latency, this is what produces the elite-vs-rookie spread.

func _make_crew(skill_key: String, skill: float, composure: float = 0.5, stress: float = 0.0) -> Dictionary:
	return {
		"crew_id": "c",
		"stats": {
			"stress": stress,
			"fatigue": 0.0,
			"skills": {
				skill_key: skill,
				"composure": composure
			}
		}
	}

func _delays(skill_key: String, skill_levels: Array) -> Array:
	var out: Array = []
	for s in skill_levels:
		var crew = _make_crew(skill_key, s)
		out.append(CrewAISystem.calculate_reaction_delay(crew, skill_key))
	return out

func test_pilot_delay_strictly_ordered_by_piloting():
	var levels := [0.95, 0.7, 0.4, 0.1]
	var delays = _delays("piloting", levels)
	for i in range(1, delays.size()):
		assert_lt(delays[i - 1], delays[i],
			"Higher piloting must commit faster (level %s vs %s, got %s vs %s)" %
			[levels[i - 1], levels[i], delays[i - 1], delays[i]])

func test_captain_delay_strictly_ordered_by_tactics():
	var levels := [0.95, 0.7, 0.4, 0.1]
	var delays = _delays("tactics", levels)
	for i in range(1, delays.size()):
		assert_lt(delays[i - 1], delays[i],
			"Higher tactics must commit faster (level %s vs %s)" % [levels[i - 1], levels[i]])

func test_elite_pilot_commits_well_under_quarter_second():
	var elite = _make_crew("piloting", 0.95)
	var delay = CrewAISystem.calculate_reaction_delay(elite, "piloting")
	# 0.95 piloting → ~0.035s. Comfortably under 0.2s acceptance threshold.
	assert_lt(delay, 0.2, "Elite pilot commit delay must be well under 200 ms.")

func test_rookie_pilot_commits_well_above_half_second():
	var rookie = _make_crew("piloting", 0.1)
	var delay = CrewAISystem.calculate_reaction_delay(rookie, "piloting")
	# 0.1 piloting → 0.63s. S1b acceptance: rookie ≥ 1.0s only when stressed.
	assert_gt(delay, 0.5, "Rookie pilot commit delay must clearly lag elites.")
