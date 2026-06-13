extends GutTest

## Behavior tests for CrewProgressionSystem.
## All fixtures are hand-built — no roster JSON, no specific data values asserted.

const MANY_SEEDS := [1, 42, 137, 999, 7777]


func _seeded_rng(s: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	return rng


func _make_member(role: int, skill_level: float, crew_id: String, callsign: String = "") -> Dictionary:
	var skills := {}
	for name in CrewData.SKILL_NAMES:
		skills[name] = skill_level
	skills[CrewData.PERSONALITY_SKILL] = 0.5
	return {
		"crew_id": crew_id,
		"callsign": callsign if callsign != "" else crew_id,
		"role": role,
		"stats": {"skills": skills},
	}


func _make_hull(hull_id: String, crew: Array, ship_type: String = "fighter") -> Dictionary:
	return {"hull_id": hull_id, "ship_type": ship_type, "crew": crew}


func _find_record(report: Array, crew_id: String) -> Dictionary:
	for rec in report:
		if rec.get("crew_id", "") == crew_id:
			return rec
	return {}


func _find_skill_delta(record: Dictionary, skill_name: String) -> Dictionary:
	for s in record.get("skills", []):
		if s.get("skill", "") == skill_name:
			return s
	return {}


func _no_ship_delta() -> Array:
	return []


func _ship_delta(hull_id: String, armor_before: float, armor_after: float,
		systems_before: float = 1.0, systems_after: float = 1.0) -> Array:
	return [{
		"hull_id": hull_id,
		"armor_before": armor_before,
		"armor_after": armor_after,
		"systems_before": systems_before,
		"systems_after": systems_after,
		"destroyed": false,
	}]


# --- Used skills grow ---

func test_pilot_piloting_increases_after_battle():
	var pilot := _make_member(CrewData.Role.PILOT, 0.5, "p1")
	var hull := _make_hull("h1", [pilot])
	var before := float(pilot.stats.skills["piloting"])

	CrewProgressionSystem.award_experience([hull], [], _no_ship_delta(), _seeded_rng(1))

	assert_true(float(pilot.stats.skills["piloting"]) > before,
		"Pilot's piloting should increase after a battle")


func test_gunner_aim_increases_after_battle():
	var gunner := _make_member(CrewData.Role.GUNNER, 0.5, "g1")
	var hull := _make_hull("h1", [gunner])
	var before := float(gunner.stats.skills["aim"])

	CrewProgressionSystem.award_experience([hull], [], _no_ship_delta(), _seeded_rng(1))

	assert_true(float(gunner.stats.skills["aim"]) > before,
		"Gunner's aim should increase after a battle")


# --- Unused skills don't grow absent mentoring ---

func test_gunner_piloting_unchanged_without_exceptional_pilot():
	var gunner := _make_member(CrewData.Role.GUNNER, 0.5, "g1")
	var hull := _make_hull("h1", [gunner])
	var before := float(gunner.stats.skills["piloting"])

	CrewProgressionSystem.award_experience([hull], [], _no_ship_delta(), _seeded_rng(1))

	assert_eq(float(gunner.stats.skills["piloting"]), before,
		"Gunner's piloting should not change without an exceptional pilot aboard")


# --- Gain stays within the band ---

func test_used_skill_gain_within_band():
	for seed in MANY_SEEDS:
		var pilot := _make_member(CrewData.Role.PILOT, 0.3, "p1")
		var hull := _make_hull("h1", [pilot])
		var before := float(pilot.stats.skills["piloting"])

		CrewProgressionSystem.award_experience([hull], [], _no_ship_delta(), _seeded_rng(seed))

		var delta := float(pilot.stats.skills["piloting"]) - before
		assert_true(delta >= WingConstants.USED_GAIN_MIN,
			"Piloting gain should be >= USED_GAIN_MIN (seed %d)" % seed)
		assert_true(delta <= WingConstants.USED_GAIN_MAX,
			"Piloting gain should be <= USED_GAIN_MAX (seed %d)" % seed)


# --- Primary develops faster than secondary ---

func test_primary_develops_faster_than_secondary():
	var primary_total := 0.0
	var secondary_total := 0.0
	var runs := 20

	for i in range(runs):
		var pilot := _make_member(CrewData.Role.PILOT, 0.5, "p1")
		var hull := _make_hull("h1", [pilot])
		var primary_before := float(pilot.stats.skills["piloting"])
		var secondary_before := float(pilot.stats.skills["awareness"])

		CrewProgressionSystem.award_experience([hull], [], _no_ship_delta(), _seeded_rng(i * 13))

		primary_total += float(pilot.stats.skills["piloting"]) - primary_before
		secondary_total += float(pilot.stats.skills["awareness"]) - secondary_before

	var primary_mean := primary_total / runs
	var secondary_mean := secondary_total / runs
	assert_true(primary_mean > secondary_mean,
		"Primary skill mean delta should exceed secondary skill mean delta")


# --- Aggression not trained by role-use ---

func test_aggression_unchanged_with_no_adversity():
	for seed in MANY_SEEDS:
		var pilot := _make_member(CrewData.Role.PILOT, 0.5, "p1")
		var hull := _make_hull("h1", [pilot])
		var before := float(pilot.stats.skills[CrewData.PERSONALITY_SKILL])

		# No ship_deltas = no adversity = aggression must not move
		CrewProgressionSystem.award_experience([hull], [], _no_ship_delta(), _seeded_rng(seed))

		assert_eq(float(pilot.stats.skills[CrewData.PERSONALITY_SKILL]), before,
			"Aggression must not change when adversity is 0 (seed %d)" % seed)


# --- Aggression hardens with high composure under fire ---

func test_aggression_rises_for_high_composure_under_fire():
	var pilot := _make_member(CrewData.Role.PILOT, 0.5, "p1")
	# High composure: above COMPOSURE_PIVOT
	pilot.stats.skills["composure"] = WingConstants.COMPOSURE_PIVOT + 0.1
	var hull := _make_hull("h1", [pilot])
	var before := float(pilot.stats.skills[CrewData.PERSONALITY_SKILL])
	var deltas := _ship_delta("h1", 0.8, 0.4)  # took armor damage

	CrewProgressionSystem.award_experience([hull], [], deltas, _seeded_rng(1))

	assert_true(float(pilot.stats.skills[CrewData.PERSONALITY_SKILL]) > before,
		"High-composure crew should harden (aggression up) under fire")


# --- Aggression falls with low composure under fire ---

func test_aggression_falls_for_low_composure_under_fire():
	var pilot := _make_member(CrewData.Role.PILOT, 0.5, "p1")
	# Low composure: below COMPOSURE_PIVOT
	pilot.stats.skills["composure"] = WingConstants.COMPOSURE_PIVOT - 0.1
	var hull := _make_hull("h1", [pilot])
	var before := float(pilot.stats.skills[CrewData.PERSONALITY_SKILL])
	var deltas := _ship_delta("h1", 0.8, 0.4)

	CrewProgressionSystem.award_experience([hull], [], deltas, _seeded_rng(1))

	assert_true(float(pilot.stats.skills[CrewData.PERSONALITY_SKILL]) < before,
		"Low-composure crew should lose nerve (aggression down) under fire")


# --- Bigger mauling, bigger aggression shift ---

func test_bigger_mauling_bigger_aggression_shift():
	# Light damage
	var pilot_light := _make_member(CrewData.Role.PILOT, 0.5, "p1")
	pilot_light.stats.skills["composure"] = WingConstants.COMPOSURE_PIVOT + 0.1
	var hull_light := _make_hull("h1", [pilot_light])
	var light_deltas := _ship_delta("h1", 1.0, 0.9)  # small loss
	var agg_before_light := float(pilot_light.stats.skills[CrewData.PERSONALITY_SKILL])
	CrewProgressionSystem.award_experience([hull_light], [], light_deltas, _seeded_rng(42))
	var light_shift := abs(float(pilot_light.stats.skills[CrewData.PERSONALITY_SKILL]) - agg_before_light)

	# Heavy damage (same seed)
	var pilot_heavy := _make_member(CrewData.Role.PILOT, 0.5, "p1")
	pilot_heavy.stats.skills["composure"] = WingConstants.COMPOSURE_PIVOT + 0.1
	var hull_heavy := _make_hull("h1", [pilot_heavy])
	var heavy_deltas := _ship_delta("h1", 1.0, 0.0)  # total loss
	var agg_before_heavy := float(pilot_heavy.stats.skills[CrewData.PERSONALITY_SKILL])
	CrewProgressionSystem.award_experience([hull_heavy], [], heavy_deltas, _seeded_rng(42))
	var heavy_shift := abs(float(pilot_heavy.stats.skills[CrewData.PERSONALITY_SKILL]) - agg_before_heavy)

	assert_true(heavy_shift > light_shift,
		"A heavier mauling should produce a larger aggression shift")


# --- Commander self-coaching is neutral ---

func test_commander_not_self_coached():
	var captain := _make_member(CrewData.Role.CAPTAIN, 1.0, "cap", "Ace")
	var subordinate := _make_member(CrewData.Role.PILOT, 0.5, "sub", "Rookie")
	var hull := _make_hull("h1", [captain, subordinate])

	var report := CrewProgressionSystem.award_experience([hull], [], _no_ship_delta(), _seeded_rng(1))

	var cap_rec := _find_record(report, "cap")
	var sub_rec := _find_record(report, "sub")
	assert_eq(float(cap_rec.get("coach_mult", -1.0)), 1.0,
		"Commander's own coach_mult must be 1.0 (no self-boost)")
	assert_true(float(sub_rec.get("coach_mult", 1.0)) > 1.0,
		"High-tactics captain should give subordinate a coach_mult > 1.0")


# --- Mentoring trickle ---

func test_mentoring_trickle_in_unused_skill():
	# Exceptional pilot aboard — gunner should get a piloting trickle
	var ace_pilot := _make_member(CrewData.Role.PILOT, 0.9, "ace", "Ace")
	ace_pilot.stats.skills["piloting"] = WingConstants.EXCEPTIONAL_SKILL_THRESHOLD + 0.01
	var gunner := _make_member(CrewData.Role.GUNNER, 0.5, "gun", "Gun")
	var hull := _make_hull("h1", [ace_pilot, gunner])
	var before := float(gunner.stats.skills["piloting"])

	var report := CrewProgressionSystem.award_experience([hull], [], _no_ship_delta(), _seeded_rng(1))

	var gunner_rec := _find_record(report, "gun")
	var trickle := _find_skill_delta(gunner_rec, "piloting")
	assert_true(not trickle.is_empty(), "Gunner should have a piloting delta from mentoring")
	var delta_val := float(trickle.get("delta", 0.0))
	assert_true(delta_val > 0.0, "Trickle delta must be positive")
	assert_true(delta_val < WingConstants.USED_GAIN_MIN,
		"Trickle delta must be strictly below the used-gain floor")
	assert_eq(trickle.get("source", ""), "mentored",
		"Trickle skill source must be 'mentored'")


# --- Exceptional member doesn't mentor themselves ---

func test_exceptional_member_does_not_self_mentor():
	var ace := _make_member(CrewData.Role.PILOT, 0.5, "ace", "Ace")
	ace.stats.skills["piloting"] = WingConstants.EXCEPTIONAL_SKILL_THRESHOLD + 0.01
	var hull := _make_hull("h1", [ace])

	var report := CrewProgressionSystem.award_experience([hull], [], _no_ship_delta(), _seeded_rng(1))

	var ace_rec := _find_record(report, "ace")
	for delta in ace_rec.get("skills", []):
		if delta.get("skill", "") == "piloting":
			assert_ne(delta.get("source", ""), "mentored",
				"Ace must not have a 'mentored' source for their own primary skill")


# --- Better commander -> more growth ---

func test_better_commander_yields_more_growth():
	# Reuse same seed; only commander tactics differs
	var run_with_tactics := func(tactics: float) -> float:
		var captain := _make_member(CrewData.Role.CAPTAIN, 0.5, "cap", "Cap")
		captain.stats.skills["tactics"] = tactics
		var subordinate := _make_member(CrewData.Role.PILOT, 0.5, "sub", "Sub")
		var hull := _make_hull("h1", [captain, subordinate])
		var before := float(subordinate.stats.skills["piloting"])
		CrewProgressionSystem.award_experience([hull], [], _no_ship_delta(), _seeded_rng(7))
		return float(subordinate.stats.skills["piloting"]) - before

	var low_gain := run_with_tactics.call(0.1)
	var high_gain := run_with_tactics.call(0.9)
	assert_true(high_gain > low_gain,
		"A high-tactics commander should produce more subordinate growth than a low-tactics one")


# --- Self-led solo pilot ---

func test_solo_pilot_develops_with_coach_mult_one():
	var pilot := _make_member(CrewData.Role.PILOT, 0.5, "p1")
	var hull := _make_hull("h1", [pilot])
	var before := float(pilot.stats.skills["piloting"])

	var report := CrewProgressionSystem.award_experience([hull], [], _no_ship_delta(), _seeded_rng(1))

	var rec := _find_record(report, "p1")
	assert_eq(float(rec.get("coach_mult", -1.0)), 1.0,
		"Solo pilot (self-commander) must have coach_mult 1.0")
	assert_true(float(pilot.stats.skills["piloting"]) > before,
		"Solo pilot must still develop their skills")


# --- Mastery taper ---

func test_mastery_taper_high_skill_gains_less():
	var gains_at := func(skill_val: float) -> float:
		var pilot := _make_member(CrewData.Role.PILOT, 0.5, "p1")
		pilot.stats.skills["piloting"] = skill_val
		var hull := _make_hull("h1", [pilot])
		var before := float(pilot.stats.skills["piloting"])
		CrewProgressionSystem.award_experience([hull], [], _no_ship_delta(), _seeded_rng(42))
		return float(pilot.stats.skills["piloting"]) - before

	var mid_gain := gains_at.call(0.5)
	var near_max_gain := gains_at.call(0.99)
	assert_true(near_max_gain < mid_gain,
		"A near-mastery skill should gain less than a mid-range skill (taper)")


func test_skill_never_exceeds_one():
	for seed in MANY_SEEDS:
		var pilot := _make_member(CrewData.Role.PILOT, 0.999, "p1")
		var hull := _make_hull("h1", [pilot])
		CrewProgressionSystem.award_experience([hull], [], _no_ship_delta(), _seeded_rng(seed))
		for skill_name in CrewData.SKILL_NAMES:
			assert_true(float(pilot.stats.skills[skill_name]) <= 1.0,
				"No skill should exceed 1.0 (seed %d, skill %s)" % [seed, skill_name])


# --- Mutation persists ---

func test_mutation_persists_on_crew_dict():
	var pilot := _make_member(CrewData.Role.PILOT, 0.4, "p1")
	var hull := _make_hull("h1", [pilot])
	var before := float(pilot.stats.skills["piloting"])

	CrewProgressionSystem.award_experience([hull], [], _no_ship_delta(), _seeded_rng(1))

	# The same crew dict (reference) should reflect the change
	assert_true(float(pilot.stats.skills["piloting"]) > before,
		"In-place mutation must be visible on the original crew dict reference")


# --- Dead crew get nothing ---

func test_dead_crew_produce_no_record():
	# A hull absent from `hulls` (e.g. lost with all hands) has no crew in the
	# post-fold array, so there's simply nothing for the system to process.
	var living_pilot := _make_member(CrewData.Role.PILOT, 0.5, "alive")
	var living_hull := _make_hull("h1", [living_pilot])

	# The dead hull is not passed in at all — simulates apply_battle_outcome folding.
	var report := CrewProgressionSystem.award_experience([living_hull], [], _no_ship_delta(), _seeded_rng(1))

	var ids := report.map(func(r): return r.get("crew_id", ""))
	assert_true("alive" in ids, "Living crew should appear in the report")
	assert_false("dead" in ids, "Crew not in any passed hull must not appear in the report")
