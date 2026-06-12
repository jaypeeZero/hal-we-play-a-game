extends GutTest

## Tests for MissionTargetingSystem.score_multiplier.
## Tests behavior: given mission + candidates, expected multipliers emerge.
## No assertions on internal function calls.


func _fighter(hull_id: String = "") -> Dictionary:
	return {"ship_type": "fighter", "hull_id": hull_id}


func _capital(hull_id: String = "") -> Dictionary:
	return {"ship_type": "capital", "hull_id": hull_id}


func _corvette(hull_id: String = "") -> Dictionary:
	return {"ship_type": "corvette", "hull_id": hull_id}


# --- FREE mission ---

func test_free_mission_always_returns_one() -> void:
	var mult := MissionTargetingSystem.score_multiplier(SquadronData.Mission.FREE, {}, _fighter())
	assert_eq(mult, 1.0)


func test_free_mission_capital_also_returns_one() -> void:
	var mult := MissionTargetingSystem.score_multiplier(SquadronData.Mission.FREE, {}, _capital())
	assert_eq(mult, 1.0)


# --- INTERCEPT mission ---

func test_intercept_priority_class_gets_high_multiplier() -> void:
	var mult := MissionTargetingSystem.score_multiplier(
		SquadronData.Mission.INTERCEPT, {"priority_class": "fighter"}, _fighter()
	)
	assert_eq(mult, MissionTargetingSystem.INTERCEPT_HIT_MULTIPLIER)


func test_intercept_non_priority_class_gets_one() -> void:
	var mult := MissionTargetingSystem.score_multiplier(
		SquadronData.Mission.INTERCEPT, {"priority_class": "fighter"}, _capital()
	)
	assert_eq(mult, MissionTargetingSystem.INTERCEPT_MISS_MULTIPLIER)


func test_intercept_priority_class_scores_higher_than_other() -> void:
	var base_score := 10.0
	var fighter_score := base_score * MissionTargetingSystem.score_multiplier(
		SquadronData.Mission.INTERCEPT, {"priority_class": "fighter"}, _fighter()
	)
	var capital_score := base_score * MissionTargetingSystem.score_multiplier(
		SquadronData.Mission.INTERCEPT, {"priority_class": "fighter"}, _capital()
	)
	assert_gt(fighter_score, capital_score)


func test_intercept_empty_priority_class_hits_all_types() -> void:
	# An empty priority_class means "any type matches" — returns hit multiplier.
	var mult := MissionTargetingSystem.score_multiplier(
		SquadronData.Mission.INTERCEPT, {"priority_class": ""}, _capital()
	)
	assert_eq(mult, MissionTargetingSystem.INTERCEPT_HIT_MULTIPLIER)


# --- ELIMINATE mission ---

func test_eliminate_named_hull_gets_high_multiplier() -> void:
	var mult := MissionTargetingSystem.score_multiplier(
		SquadronData.Mission.ELIMINATE, {"target_hull_id": "hull_99"}, _fighter("hull_99")
	)
	assert_eq(mult, MissionTargetingSystem.ELIMINATE_HIT_MULTIPLIER)


func test_eliminate_other_hull_gets_low_multiplier() -> void:
	var mult := MissionTargetingSystem.score_multiplier(
		SquadronData.Mission.ELIMINATE, {"target_hull_id": "hull_99"}, _fighter("hull_42")
	)
	assert_eq(mult, MissionTargetingSystem.ELIMINATE_MISS_MULTIPLIER)


func test_eliminate_target_outscores_any_other_ship() -> void:
	var base_score := 1.0
	var target_score := base_score * MissionTargetingSystem.score_multiplier(
		SquadronData.Mission.ELIMINATE, {"target_hull_id": "hull_99"}, _fighter("hull_99")
	)
	var other_score := base_score * MissionTargetingSystem.score_multiplier(
		SquadronData.Mission.ELIMINATE, {"target_hull_id": "hull_99"}, _capital("hull_42")
	)
	assert_gt(target_score, other_score)


# --- ESCORT / SCREEN ---

func test_escort_returns_one() -> void:
	var mult := MissionTargetingSystem.score_multiplier(SquadronData.Mission.ESCORT, {}, _fighter())
	assert_eq(mult, 1.0)


func test_screen_returns_one() -> void:
	var mult := MissionTargetingSystem.score_multiplier(SquadronData.Mission.SCREEN, {}, _fighter())
	assert_eq(mult, 1.0)


# --- has_positional_mission ---

func test_patrol_is_positional() -> void:
	assert_true(MissionTargetingSystem.has_positional_mission(SquadronData.Mission.PATROL))


func test_escort_is_positional() -> void:
	assert_true(MissionTargetingSystem.has_positional_mission(SquadronData.Mission.ESCORT))


func test_screen_is_positional() -> void:
	assert_true(MissionTargetingSystem.has_positional_mission(SquadronData.Mission.SCREEN))


func test_assault_is_positional() -> void:
	assert_true(MissionTargetingSystem.has_positional_mission(SquadronData.Mission.ASSAULT))


func test_free_is_not_positional() -> void:
	assert_false(MissionTargetingSystem.has_positional_mission(SquadronData.Mission.FREE))


func test_intercept_is_not_positional() -> void:
	assert_false(MissionTargetingSystem.has_positional_mission(SquadronData.Mission.INTERCEPT))


func test_eliminate_is_not_positional() -> void:
	assert_false(MissionTargetingSystem.has_positional_mission(SquadronData.Mission.ELIMINATE))


# --- pure function contract ---

func test_score_multiplier_does_not_mutate_params() -> void:
	var params := {"priority_class": "fighter"}
	var before_size := params.size()
	MissionTargetingSystem.score_multiplier(SquadronData.Mission.INTERCEPT, params, _fighter())
	assert_eq(params.size(), before_size)


func test_score_multiplier_does_not_mutate_candidate() -> void:
	var ship := _fighter("hull_1")
	var before_size := ship.size()
	MissionTargetingSystem.score_multiplier(SquadronData.Mission.ELIMINATE, {"target_hull_id": "hull_1"}, ship)
	assert_eq(ship.size(), before_size)
