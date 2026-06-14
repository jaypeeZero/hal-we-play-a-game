extends GutTest

## Phase 3a: tactics-driven targeting weight.
##
## Verifies that a crew's resolved tactics dict (priority + sector_focus) reshapes
## the threat/opportunity ranking produced by InformationSystem so that doctrine
## like "kill capitals first" or "work the right wing" actually changes which
## enemy each ship engages. Skill-gated noise is NOT tested here; see
## test_threat_prioritization.gd. These tests use high-tactics crew so the
## doctrine signal is clean.
##
## URGENCY NOTE: _compute_urgency is dominated by closing_speed / time_to_intercept.
## Entity_infos must carry non-zero closing velocity toward own_ship so that urgency
## is positive; then _threat_priority (carrying the tactics multiplier) scales it.
## We set a uniform closing speed on all entities in a test so that the ONLY
## difference between them is their tactics-boosted _threat_priority.

# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

## Crew with tactics block injected directly (bypasses TacticsSystem.compile_for_crew
## so tests don't require the full preset pipeline).
func _make_crew(tactics_dict: Dictionary) -> Dictionary:
	var crew = CrewData.create_crew_member(CrewData.Role.PILOT, 1.0)
	crew.assigned_to = "own_1"
	crew["tactics"] = tactics_dict
	# High awareness + tactics → clean ordering, no noise.
	crew.stats.skills.awareness = 1.0
	crew.stats.skills.tactics = 1.0
	return crew

## Crew with no tactics block (baseline regression).
func _make_crew_no_tactics() -> Dictionary:
	var crew = CrewData.create_crew_member(CrewData.Role.PILOT, 1.0)
	crew.assigned_to = "own_1"
	crew.stats.skills.awareness = 1.0
	crew.stats.skills.tactics = 1.0
	return crew

func _own_ship(pos: Vector2 = Vector2.ZERO) -> Dictionary:
	return {
		"ship_id": "own_1",
		"team": 0,
		"position": pos,
		"velocity": Vector2.ZERO,
		"rotation": 0.0,
		"status": "operational",
		"type": "fighter",
	}

## Entity_info snapshot at `pos` heading toward `own_pos` with `closing_speed`.
## A non-zero closing_speed makes _compute_urgency > 0 so _threat_priority
## (which carries the tactics multiplier) becomes the decisive factor when two
## entities share the same distance and closing speed.
func _make_entity_info(id: String, ship_type: String, pos: Vector2,
		own_pos: Vector2 = Vector2.ZERO, closing_speed: float = 100.0,
		team: int = 1) -> Dictionary:
	# Velocity points from pos toward own_pos at closing_speed magnitude.
	var to_own := (own_pos - pos)
	var vel := Vector2.ZERO
	if to_own.length() > 0.001:
		vel = to_own.normalized() * closing_speed
	return {
		"id": id,
		"type": "ship",
		"ship_type": ship_type,
		"team": team,
		"position": pos,
		"velocity": vel,
		"status": "operational",
		"_threat_priority": 80.0,  # overwritten by add_threat_priority; present for completeness
	}

## Full ship dict (for all_ships) with armor sections so weakest_first can read health.
func _make_ship_dict(id: String, ship_type: String, pos: Vector2, team: int,
		armor_current: int, armor_max: int) -> Dictionary:
	return {
		"ship_id": id,
		"type": ship_type,
		"team": team,
		"position": pos,
		"velocity": Vector2.ZERO,
		"rotation": 0.0,
		"status": "operational",
		"armor_sections": [
			{
				"section_id": "front",
				"current_armor": armor_current,
				"max_armor": armor_max,
				"size": 1.0,
				"arc": {"start": -90.0, "end": 90.0},
			}
		],
		"internals": [],
		"weapons": [],
	}

## Run identify_threats for own_ship against a set of visible enemy entity_infos.
func _rank_threats(entity_infos: Array, own: Dictionary, crew: Dictionary,
		all_ships: Array) -> Array:
	return InformationSystem.identify_threats(entity_infos, own, crew, all_ships)

## Run identify_opportunities for own_ship.
func _rank_opps(entity_infos: Array, own: Dictionary, crew: Dictionary,
		all_ships: Array) -> Array:
	return InformationSystem.identify_opportunities(entity_infos, own, crew, all_ships)

# ---------------------------------------------------------------------------
# capitals_first
# ---------------------------------------------------------------------------

func test_capitals_first_ranks_capital_above_closer_fighter():
	## capitals_first: capital at 500u must outrank a closer fighter at 200u.
	## Both close at the same speed so _threat_priority (boosted by tactics) is the tiebreaker.
	var crew = _make_crew({"priority": "capitals_first", "sector_focus": "none"})
	var own = _own_ship(Vector2.ZERO)

	var fighter_info = _make_entity_info("f1", "fighter", Vector2(200, 0), Vector2.ZERO)
	var capital_info = _make_entity_info("c1", "capital", Vector2(500, 0), Vector2.ZERO)
	var all_ships = [
		own,
		_make_ship_dict("f1", "fighter", Vector2(200, 0), 1, 100, 100),
		_make_ship_dict("c1", "capital", Vector2(500, 0), 1, 100, 100),
	]

	var ranked = _rank_threats([fighter_info, capital_info], own, crew, all_ships)
	assert_gte(ranked.size(), 2, "Both enemies should be visible.")
	assert_eq(ranked[0].id, "c1", "capitals_first: capital must rank above the closer fighter.")

func test_capitals_first_via_opportunities():
	## Opportunity path (no _compute_urgency): tactics multiplier applied to score directly.
	var crew = _make_crew({"priority": "capitals_first", "sector_focus": "none"})
	var own = _own_ship(Vector2.ZERO)

	var fighter_info = _make_entity_info("f1", "fighter", Vector2(200, 0), Vector2.ZERO)
	var capital_info = _make_entity_info("c1", "capital", Vector2(500, 0), Vector2.ZERO)
	var all_ships = [
		own,
		_make_ship_dict("f1", "fighter", Vector2(200, 0), 1, 100, 100),
		_make_ship_dict("c1", "capital", Vector2(500, 0), 1, 100, 100),
	]

	var ranked = _rank_opps([fighter_info, capital_info], own, crew, all_ships)
	assert_gte(ranked.size(), 2)
	assert_eq(ranked[0].id, "c1", "capitals_first opportunity: capital must rank first.")

# ---------------------------------------------------------------------------
# fighters_first
# ---------------------------------------------------------------------------

func test_fighters_first_ranks_fighter_above_capital():
	## fighters_first: fighter at 500u must outrank a closer capital at 200u.
	var crew = _make_crew({"priority": "fighters_first", "sector_focus": "none"})
	var own = _own_ship(Vector2.ZERO)

	var capital_info = _make_entity_info("c1", "capital", Vector2(200, 0), Vector2.ZERO)
	var fighter_info = _make_entity_info("f1", "fighter", Vector2(500, 0), Vector2.ZERO)
	var all_ships = [
		own,
		_make_ship_dict("c1", "capital", Vector2(200, 0), 1, 100, 100),
		_make_ship_dict("f1", "fighter", Vector2(500, 0), 1, 100, 100),
	]

	var ranked = _rank_threats([capital_info, fighter_info], own, crew, all_ships)
	assert_gte(ranked.size(), 2)
	assert_eq(ranked[0].id, "f1", "fighters_first: farther fighter must rank above closer capital.")

# ---------------------------------------------------------------------------
# weakest_first
# ---------------------------------------------------------------------------

func test_weakest_first_prefers_low_armor_enemy():
	## Two fighters at the same distance and closing speed: only health ratio differs.
	## The damaged one (10% armor) must rank first.
	var crew = _make_crew({"priority": "weakest_first", "sector_focus": "none"})
	var own = _own_ship(Vector2.ZERO)

	var pos = Vector2(300, 0)
	var healthy_info = _make_entity_info("healthy", "fighter", pos, Vector2.ZERO)
	var damaged_info = _make_entity_info("damaged", "fighter", pos, Vector2.ZERO)
	var all_ships = [
		own,
		_make_ship_dict("healthy", "fighter", pos, 1, 100, 100),  # 100% armor
		_make_ship_dict("damaged", "fighter", pos, 1,  10, 100),  # 10% armor
	]

	var ranked = _rank_threats([healthy_info, damaged_info], own, crew, all_ships)
	assert_gte(ranked.size(), 2)
	assert_eq(ranked[0].id, "damaged", "weakest_first: low-armor enemy must rank first.")

# ---------------------------------------------------------------------------
# nearest
# ---------------------------------------------------------------------------

func test_nearest_favors_closest_enemy():
	## nearest: closer capital (150u) must beat farther fighter (800u).
	## nearest adds a distance-based boost so the near ship wins over class.
	var crew = _make_crew({"priority": "nearest", "sector_focus": "none"})
	var own = _own_ship(Vector2.ZERO)

	var near_capital = _make_entity_info("c1", "capital", Vector2(150, 0), Vector2.ZERO)
	var far_fighter  = _make_entity_info("f1", "fighter", Vector2(800, 0), Vector2.ZERO)
	var all_ships = [
		own,
		_make_ship_dict("c1", "capital", Vector2(150, 0), 1, 100, 100),
		_make_ship_dict("f1", "fighter", Vector2(800, 0), 1, 100, 100),
	]

	var ranked = _rank_threats([near_capital, far_fighter], own, crew, all_ships)
	assert_gte(ranked.size(), 2)
	assert_eq(ranked[0].id, "c1", "nearest: capital at 150u must beat fighter at 800u.")

# ---------------------------------------------------------------------------
# sector_focus
# ---------------------------------------------------------------------------
#
# Geometry: own-team centroid at (0,0), enemy centroid at (0,1000).
# axis = (0,1000).  right_dir = (-axis.y, axis.x).normalised = (-1,0).
# Entity at (-300, 500): offset = (-300,500), lateral = (-300)*(-1) = +300 > 100 → RIGHT.
# Entity at (+300, 500): offset = (+300,500), lateral = (+300)*(-1) = -300 < -100 → LEFT.

func test_sector_focus_right_boosts_right_sector_enemy():
	## Two fighters equidistant from own ship; right-sector one must win with sector_focus=right.
	var own = _own_ship(Vector2(0, 0))
	var right_enemy_pos = Vector2(-300, 500)
	var left_enemy_pos  = Vector2( 300, 500)

	# Both at ~583u, same closing speed → urgency equal without sector_focus.
	var right_info = _make_entity_info("right_e", "fighter", right_enemy_pos, Vector2.ZERO)
	var left_info  = _make_entity_info("left_e",  "fighter", left_enemy_pos,  Vector2.ZERO)

	var all_ships = [
		own,
		_make_ship_dict("right_e", "fighter", right_enemy_pos, 1, 100, 100),
		_make_ship_dict("left_e",  "fighter", left_enemy_pos,  1, 100, 100),
	]

	var crew = _make_crew({"priority": "nearest", "sector_focus": "right"})
	var ranked = _rank_threats([right_info, left_info], own, crew, all_ships)
	assert_gte(ranked.size(), 2)
	assert_eq(ranked[0].id, "right_e",
		"sector_focus=right: right-sector enemy must rank above equidistant left-sector enemy.")

func test_sector_focus_left_boosts_left_sector_enemy():
	## Mirror of above: sector_focus=left must put the left-sector enemy first.
	var own = _own_ship(Vector2(0, 0))
	var right_enemy_pos = Vector2(-300, 500)
	var left_enemy_pos  = Vector2( 300, 500)

	var right_info = _make_entity_info("right_e", "fighter", right_enemy_pos, Vector2.ZERO)
	var left_info  = _make_entity_info("left_e",  "fighter", left_enemy_pos,  Vector2.ZERO)

	var all_ships = [
		own,
		_make_ship_dict("right_e", "fighter", right_enemy_pos, 1, 100, 100),
		_make_ship_dict("left_e",  "fighter", left_enemy_pos,  1, 100, 100),
	]

	var crew = _make_crew({"priority": "nearest", "sector_focus": "left"})
	var ranked = _rank_threats([right_info, left_info], own, crew, all_ships)
	assert_gte(ranked.size(), 2)
	assert_eq(ranked[0].id, "left_e",
		"sector_focus=left: left-sector enemy must rank above equidistant right-sector enemy.")

# ---------------------------------------------------------------------------
# No-tactics regression
# ---------------------------------------------------------------------------

func test_no_tactics_block_ranking_unchanged_from_baseline():
	## A crew with no "tactics" key must not change ranking (multiplier stays 1.0).
	## Two capitals at different distances: nearer always wins regardless of tactics.
	var crew_nearest  = _make_crew({"priority": "nearest", "sector_focus": "none"})
	var crew_no_tact  = _make_crew_no_tactics()
	var own = _own_ship(Vector2.ZERO)

	var near_info = _make_entity_info("near", "capital", Vector2(200, 0), Vector2.ZERO)
	var far_info  = _make_entity_info("far",  "capital", Vector2(600, 0), Vector2.ZERO)
	var all_ships = [
		own,
		_make_ship_dict("near", "capital", Vector2(200, 0), 1, 100, 100),
		_make_ship_dict("far",  "capital", Vector2(600, 0), 1, 100, 100),
	]

	var ranked_nearest  = _rank_threats([near_info, far_info], own, crew_nearest,  all_ships)
	var ranked_no_tact  = _rank_threats([near_info, far_info], own, crew_no_tact,  all_ships)

	assert_gte(ranked_nearest.size(),  2)
	assert_gte(ranked_no_tact.size(),  2)
	assert_eq(ranked_nearest[0].id,  "near", "nearest tactics: closer capital ranks first.")
	assert_eq(ranked_no_tact[0].id,  "near", "no-tactics: closer capital still ranks first (no regression).")

# ---------------------------------------------------------------------------
# command_first
# ---------------------------------------------------------------------------

func test_command_first_ranks_capital_ahead_of_fighter():
	## command_first treats capitals as command targets; must beat a closer fighter.
	var crew = _make_crew({"priority": "command_first", "sector_focus": "none"})
	var own = _own_ship(Vector2.ZERO)

	var fighter_info = _make_entity_info("f1", "fighter", Vector2(200, 0), Vector2.ZERO)
	var capital_info = _make_entity_info("c1", "capital", Vector2(500, 0), Vector2.ZERO)
	var all_ships = [
		own,
		_make_ship_dict("f1", "fighter", Vector2(200, 0), 1, 100, 100),
		_make_ship_dict("c1", "capital", Vector2(500, 0), 1, 100, 100),
	]

	var ranked = _rank_threats([fighter_info, capital_info], own, crew, all_ships)
	assert_gte(ranked.size(), 2)
	assert_eq(ranked[0].id, "c1", "command_first: capital must rank above the closer fighter.")
