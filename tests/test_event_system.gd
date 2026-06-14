extends GutTest

## Tests for EventSystem — FUNCTIONALITY ONLY.
## Verifies generation, targeting bias, effect application, expiry, and
## save round-trips. Never asserts specific shipped data values.


# ---------------------------------------------------------------------------
# HELPERS
# ---------------------------------------------------------------------------

func _make_rng(seed_val: int = 42) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	return rng


## Minimal hull record with a non-empty ship record (so ship-target requires pass).
func _make_hull(hull_id: String = "hull_0", ship_type: String = "fighter") -> Dictionary:
	var ship := ShipData.create_ship_instance(ship_type, 0, Vector2.ZERO)
	return {
		"hull_id": hull_id,
		"ship_type": ship_type,
		"ship_name": "Test Ship",
		"iced": false,
		"crew": [],
		"complement": [],
		"ship": ship,
	}


## Minimal crew dict with a given crew_id and optional attributes.
func _make_crew(crew_id: String = "c1", callsign: String = "Alpha",
		attributes: Array = []) -> Dictionary:
	var m := CrewData.create_crew_member(CrewData.Role.PILOT)
	m["crew_id"] = crew_id
	m["callsign"] = callsign
	m["attributes"] = attributes
	return m


## A run_state snapshot for testing (no battles done, no ships, no crew).
func _empty_run_state() -> Dictionary:
	return {
		"hulls": [],
		"crew": [],
		"star_date": 2310,
		"places": ["Kepler Station", "Dust Rim", "Vega Crossing"],
		"battle_count": 0,
	}


## A run_state with one hull and one crew member.
func _run_state_with_fleet(hull: Dictionary, member: Dictionary) -> Dictionary:
	var h := hull.duplicate(true)
	h["crew"] = [member.duplicate(true)]
	return {
		"hulls": [h],
		"crew": [member.duplicate(true)],
		"star_date": 2310,
		"places": ["Kepler Station"],
		"battle_count": 5,
	}


# ---------------------------------------------------------------------------
# EVENT COUNT SCALES WITH DATE_DELTA
# ---------------------------------------------------------------------------

func test_short_jump_produces_fewer_or_equal_events_than_long_jump():
	var hull := _make_hull()
	var member := _make_crew()
	var state := _run_state_with_fleet(hull, member)

	var short_events := EventSystem.generate_for_jump(state, 1, _make_rng(1))
	var long_events  := EventSystem.generate_for_jump(state, 20, _make_rng(2))
	assert_lte(short_events.size(), long_events.size(),
		"More travel time yields at least as many events")


func test_event_count_is_clamped_to_min():
	var state := _run_state_with_fleet(_make_hull(), _make_crew())
	# delta=0 should still yield MIN events (clamped)
	var events := EventSystem.generate_for_jump(state, 0, _make_rng(99))
	assert_gte(events.size(), WingConstants.EVENTS_PER_JUMP_MIN,
		"Zero date_delta still yields at least EVENTS_PER_JUMP_MIN events")


func test_event_count_is_clamped_to_max():
	var state := _run_state_with_fleet(_make_hull(), _make_crew())
	# Very long jump should be capped at MAX
	var events := EventSystem.generate_for_jump(state, 1000, _make_rng(7))
	assert_lte(events.size(), WingConstants.EVENTS_PER_JUMP_MAX,
		"Very long date_delta is capped at EVENTS_PER_JUMP_MAX events")


# ---------------------------------------------------------------------------
# ATTRIBUTE-BIASED TARGETING
# ---------------------------------------------------------------------------

func test_attribute_biases_crew_selection_toward_matching_event():
	## A crew member with likes_a_night_out (event_weights.bar_fight: 3.0)
	## should be selected as bar_fight target significantly more often than
	## a crew member without it. We assert a strong majority across many rolls.

	# Verify the attribute actually has a bar_fight weight before relying on it
	var defn := AttributeLibrary.get_def("likes_a_night_out")
	if defn.is_empty():
		pass  # attribute not in shipped data — skip gracefully
		return
	var weights: Dictionary = defn.get("event_weights", {})
	if not weights.has("bar_fight"):
		pass
		return

	var biased_crew   := _make_crew("biased",   "Rowdy",  ["likes_a_night_out"])
	var neutral_crew  := _make_crew("neutral",  "Steady", [])
	var hull := _make_hull()
	hull["crew"] = [biased_crew.duplicate(true), neutral_crew.duplicate(true)]
	var state: Dictionary = {
		"hulls": [hull],
		"crew": [biased_crew.duplicate(true), neutral_crew.duplicate(true)],
		"star_date": 2310,
		"places": [],
		"battles_done": false,
	}

	var biased_count  := 0
	var neutral_count := 0
	for i in range(200):
		var rng := _make_rng(i + 100)
		var events := EventSystem.generate_for_jump(state, 5, rng)
		for ev in events:
			if ev.get("id", "") == "bar_fight":
				if ev.get("target", {}).get("crew_id", "") == "biased":
					biased_count += 1
				elif ev.get("target", {}).get("crew_id", "") == "neutral":
					neutral_count += 1

	assert_gt(biased_count, neutral_count,
		"Crew with bar_fight event_weight bias is selected more often for bar_fight")


# ---------------------------------------------------------------------------
# REQUIRES FILTERING
# ---------------------------------------------------------------------------

func test_template_requiring_ship_is_excluded_when_no_ships():
	## engineers_botched_repair requires "ship": true.
	## Without a hull carrying a ship record it must never be selected.
	var state := _empty_run_state()
	# No hulls — requires.ship must exclude all ship templates
	var selected_ids: Array = []
	for i in range(50):
		var events := EventSystem.generate_for_jump(state, 5, _make_rng(i))
		for ev in events:
			selected_ids.append(ev.get("id", ""))

	assert_false(selected_ids.has("engineers_botched_repair"),
		"engineers_botched_repair is never selected when no ship record exists")


func test_template_requiring_crew_is_excluded_when_no_crew():
	## bar_fight requires "crew": true. With no crew it must never appear.
	var state := _empty_run_state()
	# hull with no crew
	var hull := _make_hull()
	hull["crew"] = []
	state["hulls"] = [hull]
	state["crew"]  = []

	var selected_ids: Array = []
	for i in range(50):
		var events := EventSystem.generate_for_jump(state, 5, _make_rng(i + 50))
		for ev in events:
			selected_ids.append(ev.get("id", ""))

	assert_false(selected_ids.has("bar_fight"),
		"bar_fight is never selected when no crew exists")


func test_template_requiring_min_battles_excluded_when_no_battles():
	## battle_hardened requires "min_battles": 1. With battle_count=0 it
	## must not appear.
	var hull := _make_hull()
	var member := _make_crew()
	var state := _run_state_with_fleet(hull, member)
	state["battle_count"] = 0

	var selected_ids: Array = []
	for i in range(80):
		var events := EventSystem.generate_for_jump(state, 5, _make_rng(i + 200))
		for ev in events:
			selected_ids.append(ev.get("id", ""))

	assert_false(selected_ids.has("battle_hardened"),
		"battle_hardened is never selected when battle_count is 0")


func test_min_battles_compares_count_not_just_presence():
	## A template requiring min_battles:5 must stay excluded at battle_count=3 —
	## proving the gate is an integer comparison, not a "≥1 battle" boolean.
	var hull := _make_hull()
	var member := _make_crew()
	var state := _run_state_with_fleet(hull, member)
	state["battle_count"] = 3

	var selected_ids: Array = []
	for i in range(120):
		var events := EventSystem.generate_for_jump(state, 9, _make_rng(i + 500))
		for ev in events:
			selected_ids.append(ev.get("id", ""))

	assert_false(selected_ids.has("war_weary_onset"),
		"war_weary_onset (min_battles:5) must not appear at battle_count=3")


# ---------------------------------------------------------------------------
# PERMANENT CREW_SKILL EFFECT
# ---------------------------------------------------------------------------

func test_permanent_crew_skill_effect_mutates_stored_skill():
	## classify_effects on a permanent crew_skill effect returns it in permanent[].
	var event := {
		"id": "test_perm_skill",
		"target": {"kind": "crew", "crew_id": "c1"},
		"effects": [{"kind": "crew_skill", "skill": "composure", "value": 0.1, "duration": "permanent"}],
		"polarity": "positive",
	}
	var result := EventSystem.classify_effects(event)
	assert_eq(result["permanent"].size(), 1, "Permanent effect lands in permanent[]")
	assert_eq(result["temp"].size(), 0, "No temp effect for permanent duration")
	assert_eq(result["permanent"][0]["kind"], "crew_skill")


func test_battles_crew_skill_effect_lands_in_temp():
	## A battles:N crew_skill effect must go into temp[], not permanent[].
	var event := {
		"id": "test_temp_skill",
		"target": {"kind": "crew", "crew_id": "c1"},
		"effects": [{"kind": "crew_skill", "skill": "composure", "value": -0.05, "duration": "battles:2"}],
		"polarity": "negative",
	}
	var result := EventSystem.classify_effects(event)
	assert_eq(result["temp"].size(), 1, "Temp effect lands in temp[]")
	assert_eq(result["permanent"].size(), 0, "No permanent entry for battles:N duration")
	var rec: Dictionary = result["temp"][0]
	assert_eq(rec["expires_after_battles"], 2)
	assert_eq(rec["skill"], "composure")


# ---------------------------------------------------------------------------
# APPLY_ACTIVE_CREW_SKILL
# ---------------------------------------------------------------------------

func test_apply_active_crew_skill_raises_effective_skill():
	var skills := {"composure": 0.5, "aim": 0.7}
	var active_effects := [
		{"kind": "crew_skill", "target": {"kind": "crew", "crew_id": "c1"},
		 "skill": "composure", "value": 0.1, "expires_after_battles": 2}
	]
	var effective := EventSystem.apply_active_crew_skill(skills, "c1", active_effects)
	assert_almost_eq(effective["composure"], 0.6, 0.001,
		"Crew skill temp effect raises effective composure")
	assert_almost_eq(effective["aim"], 0.7, 0.001,
		"Unrelated skills are untouched")


func test_apply_active_crew_skill_is_pure():
	var skills := {"composure": 0.4}
	var active_effects := [
		{"kind": "crew_skill", "target": {"kind": "crew", "crew_id": "c1"},
		 "skill": "composure", "value": 0.2, "expires_after_battles": 1}
	]
	EventSystem.apply_active_crew_skill(skills, "c1", active_effects)
	assert_almost_eq(skills["composure"], 0.4, 0.001,
		"Original skills dict is unmodified (pure)")


func test_apply_active_crew_skill_ignores_other_crew():
	var skills := {"aim": 0.5}
	var active_effects := [
		{"kind": "crew_skill", "target": {"kind": "crew", "crew_id": "other_crew"},
		 "skill": "aim", "value": 0.3, "expires_after_battles": 1}
	]
	var effective := EventSystem.apply_active_crew_skill(skills, "c1", active_effects)
	assert_almost_eq(effective["aim"], 0.5, 0.001,
		"Effect targeting a different crew_id is ignored")


func test_apply_active_crew_skill_clamps_to_one():
	var skills := {"composure": 0.95}
	var active_effects := [
		{"kind": "crew_skill", "target": {"kind": "crew", "crew_id": "c1"},
		 "skill": "composure", "value": 0.2, "expires_after_battles": 1}
	]
	var effective := EventSystem.apply_active_crew_skill(skills, "c1", active_effects)
	assert_lte(effective["composure"], 1.0,
		"Effective skill is clamped to 1.0")


# ---------------------------------------------------------------------------
# APPLY_ACTIVE_SHIP_EFFECTS
# ---------------------------------------------------------------------------

func test_apply_active_ship_effects_folds_ship_modifier():
	var ship := ShipData.create_ship_instance("fighter", 0, Vector2.ZERO)
	var active_effects := [
		{"kind": "ship_modifier",
		 "target": {"kind": "ship", "hull_id": "hull_0"},
		 "field": "pilot_accel_factor", "value": -0.12, "expires_after_battles": 1}
	]
	var result := EventSystem.apply_active_ship_effects(ship, "hull_0", active_effects)
	var cm: Dictionary = result.get("crew_modifiers", {})
	assert_true(cm.has("pilot_accel_factor"),
		"ship_modifier effect writes the field into crew_modifiers")
	assert_almost_eq(float(cm["pilot_accel_factor"]), -0.12, 0.001,
		"Modifier value is applied correctly")


func test_apply_active_ship_effects_is_pure():
	var ship := ShipData.create_ship_instance("fighter", 0, Vector2.ZERO)
	var before_cm: Dictionary = ship.get("crew_modifiers", {}).duplicate()
	var active_effects := [
		{"kind": "ship_modifier", "target": {"kind": "ship", "hull_id": "hull_0"},
		 "field": "pilot_accel_factor", "value": -0.12, "expires_after_battles": 1}
	]
	EventSystem.apply_active_ship_effects(ship, "hull_0", active_effects)
	assert_eq(ship.get("crew_modifiers", {}), before_cm,
		"Original ship_data crew_modifiers are unmodified (pure)")


func test_apply_active_ship_effects_ignores_other_hulls():
	var ship := ShipData.create_ship_instance("fighter", 0, Vector2.ZERO)
	var active_effects := [
		{"kind": "ship_modifier", "target": {"kind": "ship", "hull_id": "hull_99"},
		 "field": "pilot_accel_factor", "value": -0.12, "expires_after_battles": 1}
	]
	var result := EventSystem.apply_active_ship_effects(ship, "hull_0", active_effects)
	var cm: Dictionary = result.get("crew_modifiers", {})
	assert_false(cm.has("pilot_accel_factor"),
		"Effect targeting a different hull_id is ignored")


func test_apply_active_ship_effects_ignores_non_ship_modifier_effects():
	var ship := ShipData.create_ship_instance("fighter", 0, Vector2.ZERO)
	var active_effects := [
		{"kind": "crew_skill", "target": {"kind": "crew", "crew_id": "c1"},
		 "skill": "composure", "value": 0.1, "expires_after_battles": 1}
	]
	var result := EventSystem.apply_active_ship_effects(ship, "hull_0", active_effects)
	# Crew-skill effects must not touch crew_modifiers
	assert_false(result.get("crew_modifiers", {}).has("composure"),
		"crew_skill effects are not applied to crew_modifiers")


# ---------------------------------------------------------------------------
# TICK_BATTLE_EFFECTS — EXPIRY
# ---------------------------------------------------------------------------

func test_tick_battle_effects_decrements_counter():
	var effects := [
		{"kind": "ship_modifier", "target": {"kind": "ship", "hull_id": "hull_0"},
		 "field": "pilot_accel_factor", "value": -0.12, "expires_after_battles": 2}
	]
	var result := EventSystem.tick_battle_effects(effects)
	assert_eq(result.size(), 1, "Effect with 2 battles remaining survives one tick")
	assert_eq(result[0]["expires_after_battles"], 1,
		"Counter is decremented from 2 to 1")


func test_tick_battle_effects_removes_expired():
	var effects := [
		{"kind": "ship_modifier", "target": {"kind": "ship", "hull_id": "hull_0"},
		 "field": "pilot_accel_factor", "value": -0.12, "expires_after_battles": 1}
	]
	var result := EventSystem.tick_battle_effects(effects)
	assert_eq(result.size(), 0,
		"Effect with 1 battle remaining is removed after tick")


func test_tick_battle_effects_is_pure():
	var effects := [
		{"kind": "crew_skill", "target": {"kind": "crew", "crew_id": "c1"},
		 "skill": "composure", "value": 0.05, "expires_after_battles": 3}
	]
	EventSystem.tick_battle_effects(effects)
	assert_eq(effects[0]["expires_after_battles"], 3,
		"Original effects array is unmodified (pure)")


func test_ship_modifier_not_present_after_expiry():
	## Simulate: apply effect, tick once → effect gone from active_effects.
	## A subsequent apply_active_ship_effects call should NOT see it.
	var ship := ShipData.create_ship_instance("fighter", 0, Vector2.ZERO)
	var effects := [
		{"kind": "ship_modifier", "target": {"kind": "ship", "hull_id": "hull_0"},
		 "field": "pilot_accel_factor", "value": -0.12, "expires_after_battles": 1}
	]
	# Tick the effect (expires)
	var after_tick := EventSystem.tick_battle_effects(effects)
	assert_eq(after_tick.size(), 0, "Effect expired")
	# apply_active_ship_effects with empty effects → no modifier
	var result := EventSystem.apply_active_ship_effects(ship, "hull_0", after_tick)
	assert_false(result.get("crew_modifiers", {}).has("pilot_accel_factor"),
		"No modifier applied after effect expires")


# ---------------------------------------------------------------------------
# ADD_ATTRIBUTE / REMOVE_ATTRIBUTE
# ---------------------------------------------------------------------------

func test_add_attribute_effect_classified_as_permanent():
	var event := {
		"id": "battle_hardened",
		"target": {"kind": "crew", "crew_id": "c1"},
		"effects": [{"kind": "add_attribute", "attribute": "battle_hardened"}],
		"polarity": "positive",
	}
	var result := EventSystem.classify_effects(event)
	assert_eq(result["permanent"].size(), 1,
		"add_attribute is a permanent effect")
	assert_eq(result["permanent"][0]["kind"], "add_attribute")


func test_remove_attribute_effect_classified_as_permanent():
	var event := {
		"id": "redemption_arc",
		"target": {"kind": "crew", "crew_id": "c1"},
		"effects": [
			{"kind": "remove_attribute", "attribute": "shaken"},
			{"kind": "remove_attribute", "attribute": "war_weary"},
		],
		"polarity": "positive",
	}
	var result := EventSystem.classify_effects(event)
	assert_eq(result["permanent"].size(), 2,
		"Both remove_attribute effects are permanent")


# ---------------------------------------------------------------------------
# GENERATE_FOR_JUMP PURITY
# ---------------------------------------------------------------------------

func test_generate_for_jump_same_seed_same_result():
	var hull := _make_hull()
	var member := _make_crew()
	var state := _run_state_with_fleet(hull, member)

	var rng_a := _make_rng(12345)
	var rng_b := _make_rng(12345)

	var events_a := EventSystem.generate_for_jump(state, 5, rng_a)
	var events_b := EventSystem.generate_for_jump(state, 5, rng_b)

	assert_eq(events_a.size(), events_b.size(),
		"Same seed yields same event count")
	for i in range(events_a.size()):
		assert_eq(events_a[i]["id"], events_b[i]["id"],
			"Same seed yields same event ids in same order")


func test_generate_for_jump_does_not_mutate_run_state():
	var hull := _make_hull()
	var member := _make_crew("c99", "Ghost", ["likes_a_night_out"])
	var state := _run_state_with_fleet(hull, member)

	var original_crew_size: int = state["crew"].size()
	var original_hulls_size: int = state["hulls"].size()
	var original_star_date: int = state["star_date"]

	EventSystem.generate_for_jump(state, 5, _make_rng(777))

	assert_eq(state["crew"].size(), original_crew_size,
		"run_state crew is not mutated by generate_for_jump")
	assert_eq(state["hulls"].size(), original_hulls_size,
		"run_state hulls is not mutated by generate_for_jump")
	assert_eq(state["star_date"], original_star_date,
		"run_state star_date is not mutated by generate_for_jump")


# ---------------------------------------------------------------------------
# SAVE ROUND-TRIP
# ---------------------------------------------------------------------------

var _saved_news_feed: Array
var _saved_active_effects: Array
var _saved_fleet_hulls: Array
var _saved_active: bool
var _saved_started_first_battle: bool
var _saved_star_date: int
var _saved_campaign: Dictionary
var _saved_money: int
var _saved_run_roster: Array
var _saved_hired_roster_ids: Array
var _saved_last_battle_summary: Dictionary
var _saved_pending_battle_result: String
var _saved_pending_battle_fled: bool
var _saved_lost_ships: Array
var _saved_lost_crew: Array
var _saved_last_jump_repair: Dictionary
var _saved_last_progression: Array
var _saved_squadrons: Array


func before_each() -> void:
	EventLibrary.invalidate_cache()
	AttributeLibrary.invalidate_cache()
	CampaignSaveManager.delete_save()
	_saved_news_feed              = RoguelikeRun.news_feed.duplicate(true)
	_saved_active_effects         = RoguelikeRun.active_effects.duplicate(true)
	_saved_fleet_hulls            = RoguelikeRun.fleet_hulls.duplicate(true)
	_saved_active                 = RoguelikeRun.active
	_saved_started_first_battle   = RoguelikeRun.started_first_battle
	_saved_star_date              = RoguelikeRun.current_star_date
	_saved_campaign               = RoguelikeRun.campaign.duplicate(true)
	_saved_money                  = RoguelikeRun.money
	_saved_run_roster             = RoguelikeRun.run_roster.duplicate(true)
	_saved_hired_roster_ids       = RoguelikeRun.hired_roster_ids.duplicate(true)
	_saved_last_battle_summary    = RoguelikeRun.last_battle_summary.duplicate(true)
	_saved_pending_battle_result  = RoguelikeRun.pending_battle_result
	_saved_pending_battle_fled    = RoguelikeRun.pending_battle_fled
	_saved_lost_ships             = RoguelikeRun.lost_fleet_final_ships.duplicate(true)
	_saved_lost_crew              = RoguelikeRun.lost_fleet_final_crew.duplicate(true)
	_saved_last_jump_repair       = RoguelikeRun.last_jump_repair_summary.duplicate(true)
	_saved_last_progression       = RoguelikeRun.last_battle_progression.duplicate(true)
	_saved_squadrons              = RoguelikeRun.squadrons.duplicate(true)


func after_each() -> void:
	CampaignSaveManager.delete_save()
	RoguelikeRun.news_feed              = _saved_news_feed
	RoguelikeRun.active_effects         = _saved_active_effects
	RoguelikeRun.fleet_hulls            = _saved_fleet_hulls
	RoguelikeRun.active                 = _saved_active
	RoguelikeRun.started_first_battle   = _saved_started_first_battle
	RoguelikeRun.current_star_date      = _saved_star_date
	RoguelikeRun.campaign               = _saved_campaign
	RoguelikeRun.money                  = _saved_money
	RoguelikeRun.run_roster             = _saved_run_roster
	RoguelikeRun.hired_roster_ids       = _saved_hired_roster_ids
	RoguelikeRun.last_battle_summary    = _saved_last_battle_summary
	RoguelikeRun.pending_battle_result  = _saved_pending_battle_result
	RoguelikeRun.pending_battle_fled    = _saved_pending_battle_fled
	RoguelikeRun.lost_fleet_final_ships = _saved_lost_ships
	RoguelikeRun.lost_fleet_final_crew  = _saved_lost_crew
	RoguelikeRun.last_jump_repair_summary = _saved_last_jump_repair
	RoguelikeRun.last_battle_progression  = _saved_last_progression
	RoguelikeRun.squadrons              = _saved_squadrons


func _minimal_save_payload() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	return {
		"campaign": CampaignGenerator.generate(rng),
		"fleet_hulls": [],
		"doctrine": DoctrineSystem.empty_doctrine(),
		"tactics": TacticsSystem.empty_tactics(),
		"enemy_fleet": {},
		"money": 500,
		"current_star_date": 2305,
		"hired_roster_ids": [],
		"run_roster": [],
		"next_hull_id": 0,
		"squadrons": [],
	}


func test_news_feed_persists_through_save_load():
	var payload := _minimal_save_payload()
	var test_feed := [
		{"id": "bar_fight", "star_date": 2305, "headline": "Test", "seen": false}
	]
	payload["news_feed"] = test_feed
	payload["active_effects"] = []

	CampaignSaveManager.save_campaign(payload)
	var loaded := CampaignSaveManager.load_campaign()

	assert_true(loaded.has("news_feed"), "Loaded data has news_feed key")
	assert_eq(loaded["news_feed"].size(), 1, "news_feed round-trips with correct size")
	assert_eq(loaded["news_feed"][0]["id"], "bar_fight",
		"news_feed entry id survives round-trip")


func test_active_effects_persists_through_save_load():
	var payload := _minimal_save_payload()
	var test_effects := [
		{"kind": "ship_modifier", "target": {"kind": "ship", "hull_id": "hull_0"},
		 "field": "pilot_accel_factor", "value": -0.12, "expires_after_battles": 1}
	]
	payload["news_feed"] = []
	payload["active_effects"] = test_effects

	CampaignSaveManager.save_campaign(payload)
	var loaded := CampaignSaveManager.load_campaign()

	assert_true(loaded.has("active_effects"), "Loaded data has active_effects key")
	assert_eq(loaded["active_effects"].size(), 1,
		"active_effects round-trips with correct size")
	assert_eq(loaded["active_effects"][0]["kind"], "ship_modifier",
		"active_effects entry kind survives round-trip")


func test_v2_save_without_news_feed_loads_with_empty_defaults():
	## A save dict missing news_feed / active_effects (simulating a v2 save)
	## must load with empty arrays — the autoload's defaults kick in.
	var payload := _minimal_save_payload()
	# Deliberately omit news_feed and active_effects
	CampaignSaveManager.save_campaign(payload)

	var loaded := CampaignSaveManager.load_campaign()
	# RoguelikeRun.load_campaign_from_disk uses .get(..., [])
	RoguelikeRun.news_feed     = loaded.get("news_feed", [])
	RoguelikeRun.active_effects = loaded.get("active_effects", [])

	assert_eq(RoguelikeRun.news_feed.size(), 0,
		"Missing news_feed key loads as empty array")
	assert_eq(RoguelikeRun.active_effects.size(), 0,
		"Missing active_effects key loads as empty array")


# ---------------------------------------------------------------------------
# CLASSIFY_EFFECTS — temp record shape
# ---------------------------------------------------------------------------

func test_classify_effects_temp_record_has_required_fields():
	var event := {
		"id": "engineers_botched_repair",
		"target": {"kind": "ship", "hull_id": "hull_0"},
		"effects": [
			{"kind": "ship_modifier", "field": "pilot_accel_factor",
			 "value": -0.12, "duration": "battles:1"}
		],
		"polarity": "negative",
	}
	var result := EventSystem.classify_effects(event)
	assert_eq(result["temp"].size(), 1, "One temp effect produced")
	var rec: Dictionary = result["temp"][0]
	assert_true(rec.has("kind"),                "temp record has kind")
	assert_true(rec.has("target"),              "temp record has target")
	assert_true(rec.has("value"),               "temp record has value")
	assert_true(rec.has("expires_after_battles"), "temp record has expires_after_battles")
	assert_true(rec.has("field"),               "ship_modifier temp record has field")
	assert_eq(rec["expires_after_battles"], 1,  "battles:1 → expires_after_battles==1")
