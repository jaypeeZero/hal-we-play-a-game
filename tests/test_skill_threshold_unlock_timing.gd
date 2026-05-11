extends GutTest

## Behavior tests: skill-gated maneuver unlocks must require genuinely high skill.
##
## The goal: a pilot at skill 11/20 (0.55) should be meaningfully different from
## skill 17/20 (0.85). These tests verify that elite behaviors only unlock near
## the top of the range, not at the midpoint.

# ============================================================================
# JINKING — the most basic evasive maneuver
# ============================================================================

func test_jink_threshold_is_above_midpoint():
	# BEHAVIOR: Jinking is not a mediocre pilot's trick.
	# It should require above-average skill to execute.
	assert_gt(WingConstants.PILOT_JINKING_SKILL, 0.55,
		"Jink threshold must be well above midpoint so mid-skill pilots don't jink")

func test_pilot_just_below_jink_threshold_has_zero_amplitude():
	# BEHAVIOR: A pilot one step below the jink threshold does no jinking at all —
	# the threshold is a hard gate, not a soft ramp starting at zero.
	var below_jink = WingConstants.PILOT_JINKING_SKILL - 0.01
	var params = FighterPilotAI._calculate_jink_params(below_jink)
	assert_eq(params.amplitude, 0.0, "Pilot just below jink threshold must have zero jink amplitude")

func test_pilot_just_above_jink_threshold_jinks():
	# BEHAVIOR: Crossing the jink threshold immediately enables evasive jinking.
	var above_jink = WingConstants.PILOT_JINKING_SKILL + 0.01
	var params = FighterPilotAI._calculate_jink_params(above_jink)
	assert_gt(params.amplitude, 0.0, "Pilot just above jink threshold must jink")

func test_elite_pilot_jinks_at_full_amplitude():
	# BEHAVIOR: A max-skill pilot jinks as aggressively as possible.
	var params = FighterPilotAI._calculate_jink_params(1.0)
	assert_almost_eq(params.amplitude, WingConstants.PILOT_JINK_AMPLITUDE_MAX, 0.01,
		"Max-skill pilot should jink at full amplitude")

# ============================================================================
# DEFENSIVE SPIRAL — elite-only maneuver
# ============================================================================

func test_defensive_maneuver_threshold_is_near_elite():
	# BEHAVIOR: The defensive spiral is an expert technique — it must require
	# elite skill, not just above-average. Threshold must exceed 0.80.
	assert_gt(WingConstants.PILOT_DEFENSIVE_MANEUVER_SKILL, 0.80,
		"Defensive spiral must require elite skill (threshold > 0.80)")

func test_mid_high_skill_pilot_does_not_defensive_spiral_when_disadvantaged():
	# BEHAVIOR: A strong-but-not-elite pilot in a bad position takes a simpler
	# defensive option (ANGLED) rather than the full defensive spiral.
	var mid_high = WingConstants.PILOT_DEFENSIVE_MANEUVER_SKILL - 0.05
	var style = FighterPilotAI._select_approach_style(mid_high, "disadvantaged", 0.5)
	assert_ne(style, FighterPilotAI.ApproachStyle.DEFENSIVE_SPIRAL,
		"Pilot below defensive-maneuver threshold must NOT use defensive spiral")

func test_elite_pilot_uses_defensive_spiral_when_disadvantaged():
	# BEHAVIOR: Only an elite pilot can execute the defensive spiral when outpositioned.
	var elite = WingConstants.PILOT_DEFENSIVE_MANEUVER_SKILL + 0.05
	var style = FighterPilotAI._select_approach_style(elite, "disadvantaged", 0.5)
	assert_eq(style, FighterPilotAI.ApproachStyle.DEFENSIVE_SPIRAL,
		"Elite pilot in disadvantaged position must use defensive spiral")

# ============================================================================
# PURSUIT CURVES — above mid-tier capability
# ============================================================================

func test_pursuit_curve_threshold_above_midpoint():
	# BEHAVIOR: Pursuit curves (lead/lag targeting) require deliberate skill development.
	assert_gt(WingConstants.PILOT_PURSUIT_CURVE_SKILL, 0.55,
		"Pursuit curves must require above-average skill (threshold > 0.55)")

# ============================================================================
# TARGET SELECTION QUALITY — high skill leaders pick the best target
# ============================================================================

func test_lead_pick_best_skill_is_near_elite():
	# BEHAVIOR: Always picking the optimal target from a scored list is an
	# elite capability, not a midrange one.
	assert_gt(WingConstants.LEAD_PICK_BEST_SKILL, 0.75,
		"Optimal target selection must require near-elite skill (threshold > 0.75)")
