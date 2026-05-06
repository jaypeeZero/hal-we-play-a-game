extends GutTest

## Tests for LargeShipPilotAI behavior — FSM transitions, personality
## differentiation, self-preservation triggers, and tactical-break interrupt.
## Behaviour-only per CLAUDE.md: assertions describe what the captain *does*,
## not the literal numbers tuning the decision.

var game_time := 0.0

# ============================================================================
# FIXTURES
# ============================================================================

func _make_capital(id: String, pos: Vector2, team: int = 0, rotation: float = 0.0) -> Dictionary:
	return {
		"ship_id": id,
		"type": "capital",
		"team": team,
		"position": pos,
		"rotation": rotation,
		"velocity": Vector2.ZERO,
		"status": "operational",
		"collision_radius": 60.0,
		"stats": {"max_speed": 100.0, "size": 60.0, "turn_rate": 1.0, "acceleration": 60.0},
		"armor_sections": [
			{"section_id": "front", "current_armor": 100, "max_armor": 100},
			{"section_id": "port", "current_armor": 100, "max_armor": 100},
			{"section_id": "starboard", "current_armor": 100, "max_armor": 100},
			{"section_id": "rear", "current_armor": 100, "max_armor": 100},
		],
		"internals": [
			{"component_id": "eng_main", "type": "engine", "status": "operational"},
		],
		"orders": {"current_order": "", "target_id": "", "maneuver_subtype": ""},
	}

func _make_fighter(id: String, pos: Vector2, team: int = 1, rotation: float = 0.0) -> Dictionary:
	return {
		"ship_id": id,
		"type": "fighter",
		"team": team,
		"position": pos,
		"rotation": rotation,
		"velocity": Vector2.ZERO,
		"status": "operational",
		"collision_radius": 10.0,
		"stats": {"max_speed": 400.0, "size": 10.0, "turn_rate": 3.0, "acceleration": 200.0},
	}

func _make_pilot(id: String, ship_id: String, aggression: float = 0.5, skill: float = 0.6) -> Dictionary:
	return {
		"crew_id": id,
		"role": CrewData.Role.PILOT,
		"assigned_to": ship_id,
		"stats": {
			"reaction_time": 0.1,
			"stress": 0.0,
			"fatigue": 0.0,
			"skills": {
				"aim": skill,
				"piloting": skill,
				"awareness": skill,
				"tactics": skill,
				"composure": skill,
				"aggression": aggression
			},
		},
		"awareness": {"threats": [], "opportunities": [], "known_entities": []},
		"orders": {"received": null, "current": null},
		"command_chain": {"superior": "captain1", "subordinates": []},
		"combat_state": {},
		"current_action": "idle",
		"next_decision_time": 0.0,
	}

func _phase(crew: Dictionary) -> String:
	return str(crew.get("combat_state", {}).get("engagement_phase", ""))

# ============================================================================
# FSM TRANSITIONS
# ============================================================================

func test_closing_transitions_to_broadside_when_optimal_range_reached():
	# BEHAVIOR: A capital out at long range is closing, then commits to
	# broadside once it crosses into the optimal band.
	var ship = _make_capital("c1", Vector2(0, 0), 0)
	var pilot = _make_pilot("p1", "c1", 0.5)
	var enemy_far = _make_capital("e1", Vector2(0, 5000), 1)  # well past optimal
	enemy_far.team = 1

	# First decision at far range — phase should be closing
	var result_far = LargeShipPilotAI.make_decision(pilot, ship, [ship, enemy_far], 0.0)
	assert_eq(result_far.decision.subtype, "large_ship_close_to_broadside",
		"Far range capital should close to broadside")

	# Bring the enemy into optimal range; reuse same crew so phase persists
	var pilot2 = result_far.crew_data
	var enemy_close = _make_capital("e1", Vector2(0, 1000), 1)
	enemy_close.team = 1
	var result_close = LargeShipPilotAI.make_decision(pilot2, ship, [ship, enemy_close], 0.5)

	assert_eq(result_close.decision.subtype, "large_ship_hold_broadside",
		"Closing → broadside when range crosses optimal")

func test_broadside_transitions_to_repositioning_when_arc_lost():
	# BEHAVIOR: Once committed to broadside, losing the perpendicular arc
	# should drive the captain into a reposition-arc maneuver.
	var ship = _make_capital("c1", Vector2(0, 0), 0, 0.0)  # forward = (0,-1)
	var pilot = _make_pilot("p1", "c1", 0.5)
	var enemy = _make_capital("e1", Vector2(1500, 0), 1)  # to the right → broadside arc
	enemy.team = 1

	var step1 = LargeShipPilotAI.make_decision(pilot, ship, [ship, enemy], 0.0)
	assert_eq(step1.decision.subtype, "large_ship_hold_broadside",
		"Setup: should be in broadside")

	# Hold past PHASE_MIN_DURATION, then rotate so we point at the target
	# (forward becomes ~(1, 0), aligning with to_target → arc lost)
	var ship_rot = ship.duplicate(true)
	ship_rot.rotation = PI / 2.0
	var step2 = LargeShipPilotAI.make_decision(step1.crew_data, ship_rot, [ship_rot, enemy], 1.5)

	assert_eq(step2.decision.subtype, "large_ship_reposition_arc",
		"Broadside → repositioning when arc lost: " + step2.decision.subtype)

func test_broadside_transitions_to_kiting_when_fighter_enters_safe_range():
	# BEHAVIOR: A fighter inside the safety bubble overrides everything else
	# and forces the ship to kite (back away) regardless of phase.
	var ship = _make_capital("c1", Vector2(0, 0), 0, 0.0)
	var pilot = _make_pilot("p1", "c1", 0.5)
	var enemy_capital = _make_capital("ec", Vector2(1500, 0), 1)
	enemy_capital.team = 1

	# Frame 1: in broadside vs distant capital
	var s1 = LargeShipPilotAI.make_decision(pilot, ship, [ship, enemy_capital], 0.0)
	assert_eq(s1.decision.subtype, "large_ship_hold_broadside")

	# Frame 2: a fighter materialises inside the safe range
	var fighter_close = _make_fighter("f1", Vector2(800, 0), 1)
	var s2 = LargeShipPilotAI.make_decision(
		s1.crew_data, ship, [ship, enemy_capital, fighter_close], 0.5)

	assert_eq(s2.decision.subtype, "large_ship_kite",
		"Fighter inside safe range should force kiting: " + s2.decision.subtype)

# ============================================================================
# SELF-PRESERVATION
# ============================================================================

func test_critical_section_armor_forces_fighting_withdrawal():
	# BEHAVIOR: When any principal armor section drops below critical, the
	# captain must transition to fighting_withdrawal regardless of phase.
	var ship = _make_capital("c1", Vector2(0, 0), 0)
	# Crater the front armor below the critical ratio
	ship.armor_sections[0].current_armor = 5  # 5/100 = 0.05
	var pilot = _make_pilot("p1", "c1", 0.5)
	var enemy = _make_capital("e1", Vector2(2000, 0), 1)
	enemy.team = 1

	var result = LargeShipPilotAI.make_decision(pilot, ship, [ship, enemy], 0.0)

	assert_eq(result.decision.subtype, "large_ship_fighting_withdrawal",
		"Critical section should force withdrawal: " + result.decision.subtype)

func test_engine_damage_forces_fighting_withdrawal():
	# BEHAVIOR: Engine damage forces a withdrawal — the ship can't hold a
	# proper broadside posture when its drive is compromised.
	var ship = _make_capital("c1", Vector2(0, 0), 0)
	ship.internals[0].status = "damaged"
	var pilot = _make_pilot("p1", "c1", 0.5)
	var enemy = _make_capital("e1", Vector2(2000, 0), 1)
	enemy.team = 1

	var result = LargeShipPilotAI.make_decision(pilot, ship, [ship, enemy], 0.0)

	assert_eq(result.decision.subtype, "large_ship_fighting_withdrawal",
		"Engine damage should force withdrawal: " + result.decision.subtype)

func test_outgunned_cautious_captain_withdraws():
	# BEHAVIOR: A cautious captain (low aggression) that finds itself locally
	# outnumbered by enemy capitals breaks off. A heroic captain at the same
	# odds keeps fighting.
	var ship = _make_capital("c1", Vector2(0, 0), 0)
	var enemy_a = _make_capital("ea", Vector2(2000, 0), 1)
	enemy_a.team = 1
	var enemy_b = _make_capital("eb", Vector2(0, 2000), 1)
	enemy_b.team = 1
	var ships = [ship, enemy_a, enemy_b]

	var cautious = _make_pilot("p_c", "c1", 0.0)
	var heroic = _make_pilot("p_h", "c1", 1.0)

	var r_cautious = LargeShipPilotAI.make_decision(cautious, ship, ships, 0.0)
	var r_heroic = LargeShipPilotAI.make_decision(heroic, ship, ships, 0.0)

	assert_eq(r_cautious.decision.subtype, "large_ship_fighting_withdrawal",
		"Cautious captain should withdraw when outgunned 1-vs-2")
	assert_ne(r_heroic.decision.subtype, "large_ship_fighting_withdrawal",
		"Heroic captain (high aggression) should not withdraw at the same odds")

# ============================================================================
# PERSONALITY DIFFERENTIATION
# ============================================================================

func test_aggressive_and_cautious_captains_pick_different_phases_at_same_range():
	# BEHAVIOR: At a range that sits between the aggressive and cautious
	# optimal-range thresholds, the cautious captain commits to broadside
	# while the aggressive captain stays closing. Same skill, different doctrine.
	# Use rotation that does NOT give us a broadside arc, so the fall-through
	# is purely range-based.
	var ship = _make_capital("c1", Vector2(0, 0), 0, PI / 2.0)  # forward ~(1, 0)
	# Distance 1300: between aggressive optimal (~960) and cautious optimal (~1440)
	var enemy = _make_capital("e1", Vector2(1300, 0), 1)
	enemy.team = 1
	var ships = [ship, enemy]

	var aggressive = _make_pilot("p_a", "c1", 1.0, 0.6)
	var cautious = _make_pilot("p_c", "c1", 0.0, 0.6)

	var r_a = LargeShipPilotAI.make_decision(aggressive, ship, ships, 0.0)
	var r_c = LargeShipPilotAI.make_decision(cautious, ship, ships, 0.0)

	assert_eq(r_a.decision.subtype, "large_ship_close_to_broadside",
		"Aggressive captain should still be closing at this range (tighter optimal): " + r_a.decision.subtype)
	assert_eq(r_c.decision.subtype, "large_ship_hold_broadside",
		"Cautious captain should already be broadside (looser optimal): " + r_c.decision.subtype)

func test_aggressive_captain_holds_repositioning_longer_than_cautious():
	# BEHAVIOR: Once both captains are swinging for a new arc (repositioning),
	# the aggressive one stays in that phase longer than the cautious one
	# before timing out — same skill, different commitment timing.
	var ship_initial = _make_capital("c1", Vector2(0, 0), 0, 0.0)
	var enemy = _make_capital("e1", Vector2(1500, 0), 1)
	enemy.team = 1

	var aggressive = _make_pilot("p_a", "c1", 1.0, 0.6)
	var cautious = _make_pilot("p_c", "c1", 0.0, 0.6)

	# Frame 1: enter broadside
	var r1_a = LargeShipPilotAI.make_decision(aggressive, ship_initial, [ship_initial, enemy], 0.0)
	var r1_c = LargeShipPilotAI.make_decision(cautious, ship_initial, [ship_initial, enemy], 0.0)
	assert_eq(r1_a.decision.subtype, "large_ship_hold_broadside")
	assert_eq(r1_c.decision.subtype, "large_ship_hold_broadside")

	# Frame 2: rotate off broadside arc; past min commit duration → repositioning
	var ship_rot = ship_initial.duplicate(true)
	ship_rot.rotation = PI / 2.0  # forward (1,0), no broadside arc on target at (2000,0)
	var r2_a = LargeShipPilotAI.make_decision(r1_a.crew_data, ship_rot, [ship_rot, enemy], 1.5)
	var r2_c = LargeShipPilotAI.make_decision(r1_c.crew_data, ship_rot, [ship_rot, enemy], 1.5)
	assert_eq(r2_a.decision.subtype, "large_ship_reposition_arc",
		"Aggressive enters repositioning")
	assert_eq(r2_c.decision.subtype, "large_ship_reposition_arc",
		"Cautious enters repositioning")

	# Frame 3: 5 seconds later (past cautious's reposition timeout, before
	# aggressive's). Cautious gives up the swing; aggressive holds it.
	var r3_a = LargeShipPilotAI.make_decision(r2_a.crew_data, ship_rot, [ship_rot, enemy], 6.5)
	var r3_c = LargeShipPilotAI.make_decision(r2_c.crew_data, ship_rot, [ship_rot, enemy], 6.5)

	assert_ne(r3_a.decision.subtype, r3_c.decision.subtype,
		"Aggressive and cautious should diverge in phase commitment timing")

# ============================================================================
# TACTICAL BREAK
# ============================================================================

func test_tactical_break_interrupts_broadside_when_capital_has_nose_on_us():
	# BEHAVIOR: An enemy capital inside tactical-break range with its nose on
	# us interrupts the FSM and presents thickest armor instead of holding
	# the prior phase.
	var ship = _make_capital("c1", Vector2(0, 0), 0, 0.0)  # forward (0,-1)
	# Heroic captain so the survival overlay doesn't pre-empt the test setup
	var pilot = _make_pilot("p1", "c1", 1.0)

	# A second capital threat with a mean angle on us, inside break range
	var threat = _make_capital("e_threat", Vector2(0, -700), 1, PI)
	threat.team = 1
	# threat rotation PI → forward = (sin PI, -cos PI) = (0, 1). To-us vector
	# from threat to me = (0, 0) - (0,-700) = (0, 700) → normalized (0, 1).
	# nose dot = (0,1)·(0,1) = 1.0 ≥ TACTICAL_BREAK_ARC_DOT.

	# Plus a separate broadside-engagement target so the FSM would otherwise
	# be in broadside
	var primary = _make_capital("e1", Vector2(1500, 0), 1)
	primary.team = 1

	var result = LargeShipPilotAI.make_decision(pilot, ship, [ship, threat, primary], 0.0)

	assert_eq(result.decision.subtype, "large_ship_present_thickest_armor",
		"Tactical break should override phase: " + result.decision.subtype)

func test_no_tactical_break_when_threat_is_outside_break_range():
	# BEHAVIOR: A capital with a nose on us but at long range does NOT trigger
	# the break — only close-range arcs do.
	var ship = _make_capital("c1", Vector2(0, 0), 0, 0.0)
	# Heroic captain so survival overlay doesn't pre-empt the assertion
	var pilot = _make_pilot("p1", "c1", 1.0)
	var distant = _make_capital("e_far", Vector2(0, -1800), 1, PI)  # nose on us, but far
	distant.team = 1
	var primary = _make_capital("e1", Vector2(1500, 0), 1)
	primary.team = 1

	var result = LargeShipPilotAI.make_decision(pilot, ship, [ship, distant, primary], 0.0)

	assert_ne(result.decision.subtype, "large_ship_present_thickest_armor",
		"Distant nose-on threat should NOT trigger break")

# ============================================================================
# AREA LEASH
# ============================================================================

func test_capital_far_outside_leash_drops_fight_to_return():
	# BEHAVIOR: A capital well beyond its assigned area drops the engagement
	# and emits a closing maneuver pointed back toward home. The return marker
	# is on the decision so the maneuver layer can prioritize it.
	var ship = _make_capital("c1", Vector2(10000, 0), 0)
	ship["assigned_area"] = {"center": Vector2.ZERO, "radius": 1000.0}
	# 10000 > 1.5 * 1000, so we're "far outside"
	var pilot = _make_pilot("p1", "c1", 0.5)
	var enemy = _make_capital("e1", Vector2(11000, 0), 1)
	enemy.team = 1

	var result = LargeShipPilotAI.make_decision(pilot, ship, [ship, enemy], 0.0)

	assert_true(result.decision.has("return_to_area"),
		"Decision should be tagged as return-to-area")
	assert_true(result.decision.subtype.begins_with("large_ship_"),
		"Maneuver should still be a large ship subtype")
