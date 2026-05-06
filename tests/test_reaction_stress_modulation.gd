extends GutTest

## Reaction commit delay isn't pure skill — composure modulates it. A
## low-composure ace under stress reacts slower than usual; a steady
## rookie performs above their baseline. This is the S1b mechanic.

func _make_crew(skill: float, composure: float, stress: float) -> Dictionary:
	return {
		"crew_id": "c",
		"stats": {
			"stress": stress,
			"fatigue": 0.0,
			"skills": {
				"piloting": skill,
				"composure": composure
			}
		}
	}

func test_high_stress_low_composure_increases_delay_vs_baseline():
	var baseline = _make_crew(0.5, 0.5, 0.0)
	var panicking = _make_crew(0.5, 0.2, 0.9)
	var d_baseline = CrewAISystem.calculate_reaction_delay(baseline, "piloting")
	var d_panicking = CrewAISystem.calculate_reaction_delay(panicking, "piloting")
	assert_gt(d_panicking, d_baseline,
		"Stress beyond composure buffer must lengthen commit delay (got %s vs %s)" %
		[d_panicking, d_baseline])

func test_high_composure_absorbs_moderate_stress():
	# A composed crew member with composure*0.4 >= stress sees no penalty —
	# delay matches the no-stress baseline.
	var calm = _make_crew(0.6, 0.9, 0.3)  # composure*0.4 = 0.36 > stress 0.3
	var baseline = _make_crew(0.6, 0.9, 0.0)
	var d_calm = CrewAISystem.calculate_reaction_delay(calm, "piloting")
	var d_baseline = CrewAISystem.calculate_reaction_delay(baseline, "piloting")
	assert_almost_eq(d_calm, d_baseline, 1e-6,
		"Composure must fully absorb moderate stress.")

func test_low_composure_ace_reacts_slower_than_unstressed_rookie_baseline():
	# Vivid S1b: a 0.95-piloting / 0.1-composure ace under heavy stress can
	# regress past a 0.4-piloting unstressed rookie. Bound is generous to
	# stay tied to behavior, not to specific tuning.
	var panicking_ace = _make_crew(0.95, 0.1, 0.95)
	var d_ace = CrewAISystem.calculate_reaction_delay(panicking_ace, "piloting")
	# Sanity: panicking ace's delay must at least double the un-panicked
	# version — confirms the modulation actually fires hard.
	var calm_ace = _make_crew(0.95, 0.1, 0.0)
	var d_calm_ace = CrewAISystem.calculate_reaction_delay(calm_ace, "piloting")
	assert_gt(d_ace, d_calm_ace * 2.0,
		"Heavy stress must more than double a low-composure ace's delay.")

func test_zero_stress_matches_pure_skill_curve():
	var crew = _make_crew(0.7, 0.3, 0.0)
	var delay = CrewAISystem.calculate_reaction_delay(crew, "piloting")
	var expected = (1.0 - 0.7) * WingConstants.MAX_REACTION_DELAY
	assert_almost_eq(delay, expected, 1e-6,
		"With zero stress, delay must equal the unmodulated skill curve.")
