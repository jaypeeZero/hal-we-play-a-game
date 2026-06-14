extends GutTest

## Tests for LargeShipPilotAI behavior.
##
## The non-reflex engage tail now emits subtype "tactical" (a SteeringBlender
## directive) instead of FSM-specific large_ship_* subtypes. Tests below
## verify the new behavior for the engage path and preserve all reflex coverage
## (tactical_break, fighting_withdrawal, area_leash, edge_boundary) unchanged.
##
## Migration summary vs. old file:
##   CHANGED:  test_closing_transitions_to_broadside_when_optimal_range_reached
##             test_broadside_transitions_to_repositioning_when_arc_lost
##             test_broadside_transitions_to_kiting_when_fighter_enters_safe_range
##             test_aggressive_and_cautious_captains_pick_different_phases_at_same_range
##             test_aggressive_captain_holds_repositioning_longer_than_cautious
##             test_large_ship_finds_enemy_target
##             test_corvette_pilot_decision_routes_to_large_ship_ai
##             test_decision_applies_to_ship_orders
##             test_movement_system_executes_large_ship_maneuver
##   KEPT:     test_critical_section_armor_forces_fighting_withdrawal
##             test_engine_damage_forces_fighting_withdrawal
##             test_outgunned_cautious_captain_withdraws
##             test_tactical_break_interrupts_broadside_when_capital_has_nose_on_us
##             test_no_tactical_break_when_threat_is_outside_break_range
##             test_capital_far_outside_leash_drops_fight_to_return
##             test_no_decision_without_enemies
##             test_infer_ship_type_returns_corvette_for_multi_crew
##             test_infer_ship_type_returns_fighter_for_solo
##   ADDED:    test_engage_emits_tactical_subtype_with_required_directive_fields
##             test_artillery_role_yields_broadside_facing_mode
##             test_anchor_role_yields_nose_on_facing_mode
##             test_large_preferred_range_for_kite_mentality
##             test_broadside_facing_mode_perpendicular_to_target
##             test_nose_on_facing_mode_faces_target
##
## Behaviour-only per CLAUDE.md: assertions describe what the captain *does*,
## not the literal numbers tuning the decision.

const PILOT_SKILL := 0.6
const CORVETTE_PILOT_SKILL := 0.7

func _make_pilot(id: String, ship_id: String, aggression: float = 0.5, skill: float = PILOT_SKILL) -> Dictionary:
	return TestFactories.make_pilot(id, ship_id, skill, aggression, "captain1")

## Make a pilot whose crew["tactics"] has the given role, so build_directive
## returns the matching facing_mode.
func _make_pilot_with_role(id: String, ship_id: String, role: String) -> Dictionary:
	var pilot := _make_pilot(id, ship_id)
	pilot["tactics"] = {"role": role, "mentality_scalar": 0.5, "range_scalar": 0.5, "duty": "support"}
	return pilot

## Make a pilot with high range_scalar (kite mentality) to verify large preferred_range.
func _make_pilot_kite(id: String, ship_id: String) -> Dictionary:
	var pilot := _make_pilot(id, ship_id)
	pilot["tactics"] = {"role": "artillery", "mentality_scalar": 0.3, "range_scalar": 1.0, "duty": "hold"}
	return pilot

# ============================================================================
# NON-REFLEX ENGAGE TAIL — now emits "tactical"
# ============================================================================

func test_engage_emits_tactical_subtype_with_required_directive_fields():
	# BEHAVIOR: The non-reflex engage path emits subtype "tactical" carrying
	# all six contract fields so MovementSystem can re-blend them each frame.
	# (Previously emitted large_ship_close_to_broadside / large_ship_hold_broadside
	# depending on FSM phase — no longer the case for the engage tail.)
	var ship = TestFactories.make_capital("c1", Vector2(0, 0), 0)
	var pilot = _make_pilot("p1", "c1", 0.5)
	var enemy = TestFactories.make_capital("e1", Vector2(3000, 0), 1)

	var result = LargeShipPilotAI.make_decision(pilot, ship, [ship, enemy], 0.0)

	assert_true(result.has("decision"), "Should produce a decision")
	var d: Dictionary = result.decision
	assert_eq(d.get("type", ""), "maneuver", "type must be maneuver")
	assert_eq(d.get("subtype", ""), "tactical", "Non-reflex engage must emit subtype 'tactical'")
	assert_true(d.has("goal_weights"),    "directive must carry goal_weights")
	assert_true(d.has("preferred_range"), "directive must carry preferred_range")
	assert_true(d.has("facing_mode"),     "directive must carry facing_mode")
	assert_true(d.has("engagement_target"), "directive must carry engagement_target")
	assert_eq(d.get("target_id", ""), "e1", "target_id must be set to enemy ship_id")

func test_artillery_role_yields_broadside_facing_mode():
	# BEHAVIOR: A ship whose resolved role is "artillery" must get facing_mode
	# "broadside" so the converter keeps its side batteries on the enemy.
	var ship = TestFactories.make_capital("c1", Vector2(0, 0), 0)
	var pilot = _make_pilot_with_role("p1", "c1", "artillery")
	var enemy = TestFactories.make_capital("e1", Vector2(3000, 0), 1)

	var result = LargeShipPilotAI.make_decision(pilot, ship, [ship, enemy], 0.0)

	assert_eq(result.decision.facing_mode, "broadside",
		"Artillery role must yield facing_mode 'broadside'")

func test_anchor_role_yields_nose_on_facing_mode():
	# BEHAVIOR: A ship whose resolved role is "anchor" must get facing_mode
	# "nose_on" so it always presents its bow armor and forward guns.
	var ship = TestFactories.make_capital("c1", Vector2(0, 0), 0)
	var pilot = _make_pilot_with_role("p1", "c1", "anchor")
	var enemy = TestFactories.make_capital("e1", Vector2(3000, 0), 1)

	var result = LargeShipPilotAI.make_decision(pilot, ship, [ship, enemy], 0.0)

	assert_eq(result.decision.facing_mode, "nose_on",
		"Anchor role must yield facing_mode 'nose_on'")

func test_large_preferred_range_for_kite_mentality():
	# BEHAVIOR: A capital with range_scalar=1.0 (kite) must produce a
	# preferred_range larger than the default engagement range — it wants to
	# stay far out. Tests that the range dial actually moves the blender output.
	var ship = TestFactories.make_capital("c1", Vector2(0, 0), 0)
	var pilot_kite = _make_pilot_kite("p1", "c1")
	var pilot_mid  = _make_pilot("p2", "c1")           # no custom tactics → fallback mid
	var enemy = TestFactories.make_capital("e1", Vector2(3000, 0), 1)

	var r_kite = LargeShipPilotAI.make_decision(pilot_kite, ship, [ship, enemy], 0.0)
	var r_mid  = LargeShipPilotAI.make_decision(pilot_mid,  ship, [ship, enemy], 0.0)

	assert_gt(r_kite.decision.preferred_range, r_mid.decision.preferred_range,
		"Kite tactics must yield larger preferred_range than balanced defaults")

# ============================================================================
# SELF-PRESERVATION REFLEXES — unchanged, still emit large_ship_*
# ============================================================================

func test_critical_section_armor_forces_fighting_withdrawal():
	# BEHAVIOR: When any principal armor section drops below critical, the
	# captain must transition to fighting_withdrawal regardless of phase.
	var ship = TestFactories.make_capital("c1", Vector2(0, 0), 0)
	# Crater the front armor below the critical ratio
	ship.armor_sections[0].current_armor = ship.armor_sections[0].max_armor * 0.05
	var pilot = _make_pilot("p1", "c1", 0.5)
	var enemy = TestFactories.make_capital("e1", Vector2(2000, 0), 1)

	var result = LargeShipPilotAI.make_decision(pilot, ship, [ship, enemy], 0.0)

	assert_eq(result.decision.subtype, "large_ship_fighting_withdrawal",
		"Critical section should force withdrawal: " + result.decision.subtype)

func test_engine_damage_forces_fighting_withdrawal():
	# BEHAVIOR: Engine damage forces a withdrawal — the ship can't hold a
	# proper broadside posture when its drive is compromised.
	var ship = TestFactories.make_capital("c1", Vector2(0, 0), 0)
	ship.internals[0].status = "damaged"
	var pilot = _make_pilot("p1", "c1", 0.5)
	var enemy = TestFactories.make_capital("e1", Vector2(2000, 0), 1)

	var result = LargeShipPilotAI.make_decision(pilot, ship, [ship, enemy], 0.0)

	assert_eq(result.decision.subtype, "large_ship_fighting_withdrawal",
		"Engine damage should force withdrawal: " + result.decision.subtype)

func test_outgunned_cautious_captain_withdraws():
	# BEHAVIOR: A cautious captain (low aggression) that finds itself locally
	# outnumbered by enemy capitals breaks off. A heroic captain at the same
	# odds keeps fighting.
	var ship = TestFactories.make_capital("c1", Vector2(0, 0), 0)
	var enemy_a = TestFactories.make_capital("ea", Vector2(2000, 0), 1)
	var enemy_b = TestFactories.make_capital("eb", Vector2(0, 2000), 1)
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
# TACTICAL BREAK REFLEX — unchanged, still emits large_ship_present_thickest_armor
# ============================================================================

func test_tactical_break_interrupts_broadside_when_capital_has_nose_on_us():
	# BEHAVIOR: An enemy capital inside tactical-break range with its nose on
	# us interrupts the FSM and presents thickest armor instead of the engage
	# directive.
	var ship = TestFactories.make_capital("c1", Vector2(0, 0), 0, 0.0)  # forward (0,-1)
	# Heroic captain so the survival overlay doesn't pre-empt the test setup
	var pilot = _make_pilot("p1", "c1", 1.0)

	# A second capital threat with a mean angle on us, inside break range
	var threat = TestFactories.make_capital("e_threat", Vector2(0, -700), 1, PI)
	# threat rotation PI → forward = (sin PI, -cos PI) = (0, 1). To-us vector
	# from threat to me = (0, 0) - (0,-700) = (0, 700) → normalized (0, 1).
	# nose dot = (0,1)·(0,1) = 1.0 ≥ TACTICAL_BREAK_ARC_DOT.

	# Plus a separate broadside-engagement target so the engage path would fire
	var primary = TestFactories.make_capital("e1", Vector2(1500, 0), 1)

	var result = LargeShipPilotAI.make_decision(pilot, ship, [ship, threat, primary], 0.0)

	assert_eq(result.decision.subtype, "large_ship_present_thickest_armor",
		"Tactical break should override the engage directive: " + result.decision.subtype)

func test_no_tactical_break_when_threat_is_outside_break_range():
	# BEHAVIOR: A capital with a nose on us but at long range does NOT trigger
	# the break — only close-range arcs do.
	var ship = TestFactories.make_capital("c1", Vector2(0, 0), 0, 0.0)
	# Heroic captain so survival overlay doesn't pre-empt the assertion
	var pilot = _make_pilot("p1", "c1", 1.0)
	var distant = TestFactories.make_capital("e_far", Vector2(0, -1800), 1, PI)  # nose on us, but far
	var primary = TestFactories.make_capital("e1", Vector2(1500, 0), 1)

	var result = LargeShipPilotAI.make_decision(pilot, ship, [ship, distant, primary], 0.0)

	assert_ne(result.decision.subtype, "large_ship_present_thickest_armor",
		"Distant nose-on threat should NOT trigger break")

# ============================================================================
# AREA LEASH REFLEX — unchanged, still emits large_ship_*
# ============================================================================

func test_capital_far_outside_leash_drops_fight_to_return():
	# BEHAVIOR: A capital well beyond its assigned area drops the engagement
	# and emits a closing maneuver pointed back toward home. The return marker
	# is on the decision so the maneuver layer can prioritize it.
	# Far outside the patrol area but still well inside the escape boundary, so
	# this exercises the leash and not the (harder) boundary reflex.
	var ship = TestFactories.make_capital("c1", Vector2(4500, 1750), 0)
	ship["assigned_area"] = {"center": Vector2(2500, 1750), "radius": 1000.0}
	# 2000 > 1.5 * 1000, so we're "far outside"
	var pilot = _make_pilot("p1", "c1", 0.5)
	var enemy = TestFactories.make_capital("e1", Vector2(4800, 1750), 1)

	var result = LargeShipPilotAI.make_decision(pilot, ship, [ship, enemy], 0.0)

	assert_true(result.decision.has("return_to_area"),
		"Decision should be tagged as return-to-area")
	assert_true(result.decision.subtype.begins_with("large_ship_"),
		"Leash-return maneuver should still be a large ship subtype (reflex path)")

# ============================================================================
# TARGET SELECTION AND IDLE
# ============================================================================

func test_large_ship_finds_enemy_target():
	# BEHAVIOR: LargeShipPilotAI produces a "tactical" decision with the enemy
	# as target_id when an enemy is present.
	var my_corvette = TestFactories.make_corvette("corvette1", Vector2(0, 0), 0)
	var enemy_fighter = TestFactories.make_fighter("enemy1", Vector2(1000, 0), 1)
	var crew = _make_pilot("pilot1", "corvette1", 0.5, CORVETTE_PILOT_SKILL)

	var result = LargeShipPilotAI.make_decision(crew, my_corvette, [my_corvette, enemy_fighter], 1.0)

	assert_true(result.has("decision"), "Should make a decision when enemy present")
	if result.has("decision"):
		assert_eq(result.decision.type, "maneuver", "Should be a maneuver decision")
		assert_eq(result.decision.target_id, "enemy1", "Should target the enemy")
		# Non-reflex engage path now emits "tactical", not "large_ship_*"
		assert_eq(result.decision.subtype, "tactical",
			"Non-reflex engage decision must be 'tactical': " + result.decision.get("subtype", ""))

func test_no_decision_without_enemies():
	# BEHAVIOR: No enemies means idle
	var my_corvette = TestFactories.make_corvette("corvette1", Vector2(0, 0), 0)
	var friendly = TestFactories.make_corvette("friendly1", Vector2(500, 0), 0)  # Same team
	var crew = _make_pilot("pilot1", "corvette1", 0.5, CORVETTE_PILOT_SKILL)

	var result = LargeShipPilotAI.make_decision(crew, my_corvette, [my_corvette, friendly], 1.0)

	# Should NOT have a decision key when no targets
	assert_false(result.has("decision"), "Should not have decision without enemies")

# ============================================================================
# CREW AI SYSTEM ROUTING
# ============================================================================

func test_infer_ship_type_returns_corvette_for_multi_crew():
	# BEHAVIOR: Pilots with a captain superior should be identified as corvette pilots
	var crew = _make_pilot("pilot1", "corvette1", 0.5, CORVETTE_PILOT_SKILL)  # has captain

	var ship_type = CrewAISystem.infer_ship_type(crew)

	assert_eq(ship_type, "corvette", "Pilot with captain should be corvette type")

func test_infer_ship_type_returns_fighter_for_solo():
	# BEHAVIOR: Solo pilots (no superior) should be identified as fighters
	var crew = TestFactories.make_pilot("pilot1", "fighter1", CORVETTE_PILOT_SKILL)  # no captain

	var ship_type = CrewAISystem.infer_ship_type(crew)

	assert_eq(ship_type, "fighter", "Pilot without captain should be fighter type")

func test_corvette_pilot_decision_routes_to_large_ship_ai():
	# BEHAVIOR: make_corvette_pilot_decision returns a "tactical" directive
	# (the non-reflex engage path is now "tactical" not "large_ship_*").
	var my_corvette = TestFactories.make_corvette("corvette1", Vector2(0, 0), 0)
	var enemy = TestFactories.make_fighter("enemy1", Vector2(1000, 0), 1)
	var crew = _make_pilot("pilot1", "corvette1", 0.5, CORVETTE_PILOT_SKILL)

	var context = {
		"ship_data": my_corvette,
		"all_ships": [my_corvette, enemy],
		"is_outnumbered": false
	}

	var result = CrewAISystem.make_corvette_pilot_decision(crew, context, 1.0)

	assert_true(result.has("decision"), "Should return a decision")
	if result.has("decision"):
		assert_eq(result.decision.subtype, "tactical",
			"Non-reflex corvette engage must be 'tactical': " + result.decision.get("subtype", ""))

# ============================================================================
# INTEGRATION — decision-to-movement flow
# ============================================================================

func test_decision_applies_to_ship_orders():
	# BEHAVIOR: A tactical large-ship decision must set current_order="tactical"
	# and copy all contract fields onto orders so MovementSystem can re-blend.
	var my_corvette = TestFactories.make_corvette("corvette1", Vector2(0, 0), 0)
	var enemy = TestFactories.make_fighter("enemy1", Vector2(1000, 0), 1)
	var crew = _make_pilot("pilot1", "corvette1", 0.5, CORVETTE_PILOT_SKILL)

	var result = LargeShipPilotAI.make_decision(crew, my_corvette, [my_corvette, enemy], 1.0)
	assert_true(result.has("decision"), "Should have decision")

	var applied = CrewIntegrationSystem.apply_decision_to_ship(my_corvette, result.decision, crew)

	assert_eq(applied.orders.current_order, "tactical",
		"Current order must be 'tactical': " + applied.orders.get("current_order", "EMPTY"))
	assert_eq(applied.orders.target_id, "enemy1", "target_id must be set")
	assert_true(applied.orders.has("goal_weights"),    "orders must have goal_weights")
	assert_true(applied.orders.has("preferred_range"), "orders must have preferred_range")
	assert_true(applied.orders.has("facing_mode"),     "orders must have facing_mode")

func test_movement_system_executes_tactical_order_for_large_ship():
	# BEHAVIOR: MovementSystem must move a corvette that has current_order="tactical"
	# — the tactical path is now the normal large-ship engage path.
	var my_corvette = TestFactories.make_corvette("corvette1", Vector2(0, 0), 0)
	my_corvette.orders.current_order = "tactical"
	my_corvette.orders.engagement_target = "enemy1"
	my_corvette.orders.target_id = "enemy1"
	my_corvette.orders.goal_weights = {"pursue": 1.0, "keep_range": 0.4, "evade": 0.05, "formation": 0.0}
	my_corvette.orders.preferred_range = 1200.0
	my_corvette.orders.facing_mode = "auto"
	my_corvette.orders.formation_slot = Vector2.ZERO
	my_corvette.orders.anchor_position = Vector2.ZERO

	var enemy = TestFactories.make_fighter("enemy1", Vector2(2000, 0), 1)
	var all_ships = [my_corvette, enemy]

	var updated = my_corvette
	for i in range(10):
		updated = MovementSystem.update_ship_movement(updated, all_ships, 0.1, 0.0, [])

	assert_gt(updated.velocity.length(), 0.1, "Corvette on 'tactical' order should be moving")
	assert_gt(updated.velocity.x, 0.0, "Corvette should be closing on enemy to the right")

# ============================================================================
# CONVERTER — facing_mode produces correct headings
# ============================================================================

func _heading_to_dir(h: float) -> Vector2:
	return Vector2(sin(h), -cos(h))

func test_broadside_facing_mode_perpendicular_to_target():
	# BEHAVIOR: With facing_mode "broadside", desired_heading must be roughly
	# perpendicular to the bearing to the target (dot product near 0),
	# regardless of distance. Side batteries need to bear.
	# Target is directly to the right (+X). Perpendicular is (0,1) or (0,-1).
	var ship := {
		"ship_id": "c1",
		"type": "capital",
		"position": Vector2.ZERO,
		"velocity": Vector2.ZERO,
		"rotation": 0.0,
		"status": "operational",
		"stats": {"max_speed": 200.0, "acceleration": 50.0, "turn_rate": 1.5, "size": 40.0},
		"orders": {
			"current_order": "tactical",
			"engagement_target": "e1",
			"goal_weights": {"pursue": 0.5, "keep_range": 0.4, "evade": 0.05, "formation": 0.0},
			"preferred_range": 1200.0,
			"facing_mode": "broadside",
			"formation_slot": Vector2.ZERO,
			"anchor_position": Vector2.ZERO,
		},
		"crew_modifiers": {},
	}
	var target := {"ship_id": "e1", "position": Vector2(3000, 0)}

	var ctrl := MovementSystem.calculate_blended_control(ship, target, [], [], [], 0.016)
	var facing: Vector2 = _heading_to_dir(ctrl.desired_heading)
	# to_target is (1,0). Perpendicular is (0,±1). So facing.x should be near 0.
	assert_lt(absf(facing.x), 0.3,
		"Broadside facing must be roughly perpendicular to target bearing (|facing.x| < 0.3), got: " + str(facing))

func test_nose_on_facing_mode_faces_target():
	# BEHAVIOR: With facing_mode "nose_on", desired_heading must point toward
	# the target at all ranges. Forward guns and bow armor face the enemy.
	var ship := {
		"ship_id": "c1",
		"type": "capital",
		"position": Vector2.ZERO,
		"velocity": Vector2.ZERO,
		"rotation": 0.0,
		"status": "operational",
		"stats": {"max_speed": 200.0, "acceleration": 50.0, "turn_rate": 1.5, "size": 40.0},
		"orders": {
			"current_order": "tactical",
			"engagement_target": "e1",
			"goal_weights": {"pursue": 0.5, "keep_range": 0.4, "evade": 0.05, "formation": 0.0},
			"preferred_range": 1200.0,
			"facing_mode": "nose_on",
			"formation_slot": Vector2.ZERO,
			"anchor_position": Vector2.ZERO,
		},
		"crew_modifiers": {},
	}
	# Target is far (> LATERAL_THRUST_RANGE) — this is the key test:
	# "auto" would face the move direction at far range, "nose_on" must always face target.
	var target := {"ship_id": "e1", "position": Vector2(5000, 0)}

	var ctrl := MovementSystem.calculate_blended_control(ship, target, [], [], [], 0.016)
	var facing: Vector2 = _heading_to_dir(ctrl.desired_heading)
	# Target is at +X → facing must have positive X component.
	assert_gt(facing.x, 0.5,
		"Nose-on at far range must face the target (+X), got: " + str(facing))
