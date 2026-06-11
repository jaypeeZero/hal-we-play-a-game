extends GutTest

## Tests for RoguelikeRun state management - FUNCTIONALITY ONLY
## Verifies fleet persistence, damage carry-over, and enemy fleet independence

var _saved_fleet: Dictionary
var _saved_fleet_ships: Array
var _saved_fleet_crew: Array
var _saved_doctrine: Dictionary
var _saved_enemy_fleet: Dictionary
var _saved_active: bool
var _saved_started_first_battle: bool
var _saved_star_date: int
var _saved_repair_summary: Dictionary
var _saved_campaign: Dictionary
var _saved_battle_result: String
var _saved_lost_ships: Array
var _saved_lost_crew: Array


func before_each() -> void:
	_saved_fleet = RoguelikeRun.fleet.duplicate(true)
	_saved_fleet_ships = RoguelikeRun.fleet_ships.duplicate(true)
	_saved_fleet_crew = RoguelikeRun.fleet_crew.duplicate(true)
	_saved_doctrine = RoguelikeRun.doctrine.duplicate(true)
	_saved_enemy_fleet = RoguelikeRun.enemy_fleet.duplicate(true)
	_saved_active = RoguelikeRun.active
	_saved_started_first_battle = RoguelikeRun.started_first_battle
	_saved_star_date = RoguelikeRun.current_star_date
	_saved_repair_summary = RoguelikeRun.last_jump_repair_summary.duplicate(true)
	_saved_campaign = RoguelikeRun.campaign.duplicate(true)
	_saved_battle_result = RoguelikeRun.pending_battle_result
	_saved_lost_ships = RoguelikeRun.lost_fleet_final_ships.duplicate(true)
	_saved_lost_crew = RoguelikeRun.lost_fleet_final_crew.duplicate(true)


func after_each() -> void:
	RoguelikeRun.fleet = _saved_fleet
	RoguelikeRun.fleet_ships = _saved_fleet_ships
	RoguelikeRun.fleet_crew = _saved_fleet_crew
	RoguelikeRun.doctrine = _saved_doctrine
	RoguelikeRun.enemy_fleet = _saved_enemy_fleet
	RoguelikeRun.active = _saved_active
	RoguelikeRun.started_first_battle = _saved_started_first_battle
	RoguelikeRun.current_star_date = _saved_star_date
	RoguelikeRun.last_jump_repair_summary = _saved_repair_summary
	RoguelikeRun.campaign = _saved_campaign
	RoguelikeRun.pending_battle_result = _saved_battle_result
	RoguelikeRun.lost_fleet_final_ships = _saved_lost_ships
	RoguelikeRun.lost_fleet_final_crew = _saved_lost_crew


func _make_ship(ship_type: String) -> Dictionary:
	return ShipData.create_ship_instance(ship_type, 0, Vector2.ZERO)


# ============================================================================
# FLEET TRACKING AFTER BATTLE
# ============================================================================

func test_update_fleet_stores_surviving_ships():
	var ship1 = _make_ship("fighter")
	var ship2 = _make_ship("corvette")

	RoguelikeRun.update_fleet_after_battle([ship1, ship2])

	assert_eq(RoguelikeRun.fleet_ships.size(), 2, "Both surviving ships should be stored")


func test_update_fleet_rebuilds_count_dict():
	var ships := [_make_ship("fighter"), _make_ship("fighter"), _make_ship("corvette")]

	RoguelikeRun.update_fleet_after_battle(ships)

	assert_eq(RoguelikeRun.fleet.get("fighter", 0), 2, "Fleet count should reflect 2 fighters")
	assert_eq(RoguelikeRun.fleet.get("corvette", 0), 1, "Fleet count should reflect 1 corvette")


func test_update_fleet_zeroes_lost_ship_types():
	var ships := [_make_ship("fighter")]
	RoguelikeRun.fleet = {"fighter": 2, "corvette": 3, "capital": 1,
		"heavy_fighter": 0, "torpedo_boat": 0}

	RoguelikeRun.update_fleet_after_battle(ships)

	assert_eq(RoguelikeRun.fleet.get("corvette", -1), 0,
		"Lost ship types should be zeroed in fleet count")
	assert_eq(RoguelikeRun.fleet.get("capital", -1), 0,
		"Lost ship types should be zeroed in fleet count")


# ============================================================================
# FLEET EMPTY CHECK
# ============================================================================

func test_fleet_is_empty_when_no_survivors():
	RoguelikeRun.update_fleet_after_battle([])

	assert_true(RoguelikeRun.is_fleet_empty(), "Fleet should be empty with no survivors")


func test_fleet_is_not_empty_when_any_ship_survives():
	RoguelikeRun.update_fleet_after_battle([_make_ship("fighter")])

	assert_false(RoguelikeRun.is_fleet_empty(), "Fleet should not be empty with a surviving ship")


# ============================================================================
# DAMAGE STATE PERSISTENCE
# ============================================================================

func test_surviving_ship_armor_damage_is_preserved():
	var ship = _make_ship("fighter")
	ship["armor_sections"][0]["current_armor"] = 0

	RoguelikeRun.update_fleet_after_battle([ship])

	assert_eq(RoguelikeRun.fleet_ships[0]["armor_sections"][0]["current_armor"], 0,
		"Depleted armor should carry over to next battle")


func test_surviving_ship_internal_damage_is_preserved():
	var ship = _make_ship("corvette")
	ship["internals"][0]["status"] = "destroyed"
	ship["internals"][0]["current_health"] = 0

	RoguelikeRun.update_fleet_after_battle([ship])

	assert_eq(RoguelikeRun.fleet_ships[0]["internals"][0]["status"], "destroyed",
		"Destroyed internal component should carry over to next battle")


func test_surviving_ship_stat_penalties_are_preserved():
	var ship = _make_ship("corvette")
	var base_speed: float = ship["stats"]["max_speed"]
	ship["stats"]["max_speed"] = base_speed * 0.5

	RoguelikeRun.update_fleet_after_battle([ship])

	assert_almost_eq(
		RoguelikeRun.fleet_ships[0]["stats"]["max_speed"],
		base_speed * 0.5,
		0.01,
		"Speed penalty from engine damage should carry over to next battle"
	)


func test_fleet_ships_are_deep_copied():
	var ship = _make_ship("fighter")
	RoguelikeRun.update_fleet_after_battle([ship])

	# Modify the original after storing
	ship["armor_sections"][0]["current_armor"] = 999.0

	assert_ne(RoguelikeRun.fleet_ships[0]["armor_sections"][0]["current_armor"], 999.0,
		"fleet_ships should be a deep copy, not a reference")


# ============================================================================
# ENEMY FLEET INDEPENDENCE
# ============================================================================

func test_enemy_fleet_is_not_affected_by_player_battle_results():
	RoguelikeRun.enemy_fleet = {
		"fighter": 3, "corvette": 2, "heavy_fighter": 0, "torpedo_boat": 0, "capital": 0
	}

	RoguelikeRun.update_fleet_after_battle([_make_ship("fighter")])

	assert_eq(RoguelikeRun.enemy_fleet.get("fighter", 0), 3,
		"Enemy fighter count should not change after player battle")
	assert_eq(RoguelikeRun.enemy_fleet.get("corvette", 0), 2,
		"Enemy corvette count should not change after player battle")


func test_enemy_fleet_survives_multiple_battles():
	RoguelikeRun.enemy_fleet = {
		"fighter": 2, "corvette": 1, "heavy_fighter": 0, "torpedo_boat": 0, "capital": 0
	}
	var enemy_fighter_count: int = RoguelikeRun.enemy_fleet["fighter"]

	RoguelikeRun.update_fleet_after_battle([_make_ship("fighter")])
	RoguelikeRun.update_fleet_after_battle([_make_ship("fighter")])

	assert_eq(RoguelikeRun.enemy_fleet.get("fighter", 0), enemy_fighter_count,
		"Enemy fleet should be identical before and after multiple battles")


# ============================================================================
# RUN LIFECYCLE
# ============================================================================

func test_end_run_clears_fleet_ships():
	RoguelikeRun.update_fleet_after_battle([_make_ship("fighter")])

	RoguelikeRun.end_run()

	assert_true(RoguelikeRun.fleet_ships.is_empty(),
		"fleet_ships should be cleared when run ends")


func test_end_run_clears_enemy_fleet():
	RoguelikeRun.enemy_fleet = {"fighter": 3, "corvette": 1,
		"heavy_fighter": 0, "torpedo_boat": 0, "capital": 0}

	RoguelikeRun.end_run()

	assert_true(RoguelikeRun.enemy_fleet.is_empty(),
		"enemy_fleet should be cleared when run ends")


# ============================================================================
# JUMP REPAIRS (Engineers + star dates)
# ============================================================================

const JUMP_DATE_DELTA := 5

func _make_damaged_ship_with_crew(engineer_count: int) -> Dictionary:
	var ship = _make_ship("corvette")
	ship["armor_sections"][0]["current_armor"] = 1
	ship["crew"] = []
	for i in engineer_count:
		ship["crew"].append(TestFactories.make_crew_engineer(1.0, ship.ship_id))
	return ship


func _total_armor(ship: Dictionary) -> int:
	return DamageResolver.calculate_total_armor(ship)


func test_jump_repairs_heal_ship_with_engineers():
	RoguelikeRun.fleet_ships = [_make_damaged_ship_with_crew(1)]
	var before = _total_armor(RoguelikeRun.fleet_ships[0])

	var summary = RoguelikeRun.apply_jump_repairs(RoguelikeRun.current_star_date + JUMP_DATE_DELTA, false)

	assert_gt(_total_armor(RoguelikeRun.fleet_ships[0]), before,
		"Ship with an engineer should heal during the jump")
	assert_eq(summary.ships_repaired, 1, "Summary should count the repaired ship")
	assert_eq(summary.date_delta, JUMP_DATE_DELTA, "Summary should report the star-date gap")


func test_jump_repairs_skip_ship_without_engineers():
	RoguelikeRun.fleet_ships = [_make_damaged_ship_with_crew(0)]
	var before = _total_armor(RoguelikeRun.fleet_ships[0])

	RoguelikeRun.apply_jump_repairs(RoguelikeRun.current_star_date + JUMP_DATE_DELTA, false)

	assert_eq(_total_armor(RoguelikeRun.fleet_ships[0]), before,
		"Ship without engineers should not heal during the jump")


func test_wider_date_gap_heals_more():
	var start_date = RoguelikeRun.current_star_date

	RoguelikeRun.fleet_ships = [_make_damaged_ship_with_crew(1)]
	RoguelikeRun.apply_jump_repairs(start_date + 2, false)
	var narrow_gap_armor = _total_armor(RoguelikeRun.fleet_ships[0])

	RoguelikeRun.current_star_date = start_date
	RoguelikeRun.fleet_ships = [_make_damaged_ship_with_crew(1)]
	RoguelikeRun.apply_jump_repairs(start_date + 9, false)
	var wide_gap_armor = _total_armor(RoguelikeRun.fleet_ships[0])

	assert_gt(wide_gap_armor, narrow_gap_armor,
		"A longer jump (more downtime) should repair more")


func test_rnr_heals_more_than_battle_jump_at_equal_gap():
	var start_date = RoguelikeRun.current_star_date

	RoguelikeRun.fleet_ships = [_make_damaged_ship_with_crew(1)]
	RoguelikeRun.apply_jump_repairs(start_date + JUMP_DATE_DELTA, false)
	var battle_jump_armor = _total_armor(RoguelikeRun.fleet_ships[0])

	RoguelikeRun.current_star_date = start_date
	RoguelikeRun.fleet_ships = [_make_damaged_ship_with_crew(1)]
	RoguelikeRun.apply_jump_repairs(start_date + JUMP_DATE_DELTA, true)
	var rnr_armor = _total_armor(RoguelikeRun.fleet_ships[0])

	assert_gt(rnr_armor, battle_jump_armor,
		"R&R downtime should repair more than a battle jump of the same gap")


func test_jump_repairs_restore_destroyed_components():
	var ship = _make_damaged_ship_with_crew(1)
	ship["internals"][0]["status"] = "destroyed"
	ship["internals"][0]["current_health"] = 0
	RoguelikeRun.fleet_ships = [ship]

	RoguelikeRun.apply_jump_repairs(RoguelikeRun.current_star_date + JUMP_DATE_DELTA, true)

	assert_gt(RoguelikeRun.fleet_ships[0]["internals"][0]["current_health"], 0,
		"Downtime repairs should restore destroyed components")
	assert_ne(RoguelikeRun.fleet_ships[0]["internals"][0]["status"], "destroyed",
		"Restored component should no longer be destroyed")


func test_jump_advances_current_star_date():
	var destination = RoguelikeRun.current_star_date + JUMP_DATE_DELTA

	RoguelikeRun.apply_jump_repairs(destination, false)

	assert_eq(RoguelikeRun.current_star_date, destination,
		"The jump should move the run to the destination star date")


func test_jump_repair_summary_persists_for_the_map():
	RoguelikeRun.fleet_ships = [_make_damaged_ship_with_crew(1)]

	RoguelikeRun.apply_jump_repairs(RoguelikeRun.current_star_date + JUMP_DATE_DELTA, false)

	assert_gt(RoguelikeRun.last_jump_repair_summary.get("ships_repaired", 0), 0,
		"The map reports repairs after a battle from the persisted summary")


func test_fleet_ships_empty_at_run_start():
	# start_run reads team1 fleet from disk which may not exist in test env;
	# we verify fleet_ships is reset regardless of that side-effect
	RoguelikeRun.fleet_ships = [_make_ship("fighter")]
	RoguelikeRun.active = true

	var dummy_fleet := {"fighter": 1, "heavy_fighter": 0,
		"torpedo_boat": 0, "corvette": 0, "capital": 0}
	RoguelikeRun.start_run(dummy_fleet)

	assert_true(RoguelikeRun.fleet_ships.is_empty(),
		"fleet_ships should be empty at the start of a new run (first battle spawns fresh ships)")


# ============================================================================
# CREW ROSTER
# ============================================================================

func test_run_start_creates_a_crew_group_per_hull():
	RoguelikeRun.start_run({"fighter": 2, "heavy_fighter": 0,
		"torpedo_boat": 0, "corvette": 1, "capital": 0})

	assert_eq(RoguelikeRun.fleet_crew.size(), 3,
		"Each hull in the starting fleet should get a crew group at run start")
	var types: Array = []
	for group in RoguelikeRun.fleet_crew:
		types.append(group.ship_type)
		assert_gt(group.crew.size(), 0, "Every crew group should have members")
	assert_eq(types.count("fighter"), 2, "Two fighter crews expected")
	assert_eq(types.count("corvette"), 1, "One corvette crew expected")


func test_roster_crew_have_callsigns():
	RoguelikeRun.start_run({"fighter": 2, "heavy_fighter": 0,
		"torpedo_boat": 0, "corvette": 0, "capital": 0})

	var callsigns: Array = []
	for group in RoguelikeRun.fleet_crew:
		for member in group.crew:
			assert_true(member.has("callsign"), "Roster crew need a player-facing callsign")
			callsigns.append(member.callsign)
	assert_eq(callsigns.size(), 2, "One pilot per fighter")
	assert_ne(callsigns[0], callsigns[1], "Callsigns should be distinct")


func test_run_start_resets_doctrine():
	DoctrineSystem.set_instruction_in_place(
		RoguelikeRun.doctrine, DoctrineSystem.SCOPE_FLEET, "", "charge_head_on")

	RoguelikeRun.start_run({"fighter": 1, "heavy_fighter": 0,
		"torpedo_boat": 0, "corvette": 0, "capital": 0})

	assert_true(RoguelikeRun.doctrine[DoctrineSystem.SCOPE_FLEET].is_empty(),
		"Doctrine is run state: a new run starts with no standing instructions")


# ROSTER RECONCILE (Edit Fleet adjusts fleet counts mid-setup)

const PILOT_DOCTRINE := "charge_head_on"


func _counts(overrides: Dictionary = {}) -> Dictionary:
	var base := {"fighter": 0, "heavy_fighter": 0,
		"torpedo_boat": 0, "corvette": 0, "capital": 0}
	for key in overrides:
		base[key] = overrides[key]
	return base


func _groups_of_type(ship_type: String) -> int:
	var n := 0
	for group in RoguelikeRun.fleet_crew:
		if group.get("ship_type", "") == ship_type:
			n += 1
	return n


func _roster_has_crew_id(crew_id: String) -> bool:
	for group in RoguelikeRun.fleet_crew:
		for member in group.crew:
			if member.get("crew_id", "") == crew_id:
				return true
	return false


func test_reconcile_adds_groups_when_a_count_grows():
	RoguelikeRun.start_run(_counts({"fighter": 1}))

	RoguelikeRun.reconcile_roster_to_counts(_counts({"fighter": 3}))

	assert_eq(_groups_of_type("fighter"), 3,
		"Raising a ship count should add crew groups for the new hulls")


func test_reconcile_drops_groups_when_a_count_shrinks():
	RoguelikeRun.start_run(_counts({"fighter": 3}))

	RoguelikeRun.reconcile_roster_to_counts(_counts({"fighter": 1}))

	assert_eq(_groups_of_type("fighter"), 1,
		"Lowering a ship count should drop the surplus crew groups")


func test_reconcile_preserves_identity_of_retained_crew():
	RoguelikeRun.start_run(_counts({"fighter": 2}))
	var kept_id: String = RoguelikeRun.fleet_crew[0].crew[0].crew_id

	RoguelikeRun.reconcile_roster_to_counts(_counts({"fighter": 1}))

	assert_true(_roster_has_crew_id(kept_id),
		"Crew on a retained hull should keep their identity across a fleet edit")


func test_reconcile_purges_doctrine_for_dropped_crew():
	RoguelikeRun.start_run(_counts({"fighter": 2}))
	var dropped_id: String = RoguelikeRun.fleet_crew[1].crew[0].crew_id
	DoctrineSystem.set_instruction_in_place(
		RoguelikeRun.doctrine, DoctrineSystem.SCOPE_CREW, dropped_id, PILOT_DOCTRINE)
	DoctrineSystem.set_disabled_in_place(
		RoguelikeRun.doctrine, dropped_id, PILOT_DOCTRINE, true)

	RoguelikeRun.reconcile_roster_to_counts(_counts({"fighter": 1}))

	assert_false(RoguelikeRun.doctrine[DoctrineSystem.SCOPE_CREW].has(dropped_id),
		"Per-crew doctrine for a removed crew member should be purged")
	assert_false(RoguelikeRun.doctrine["disabled"].has(dropped_id),
		"Disable entries for a removed crew member should be purged")


func test_reconcile_keeps_fleet_doctrine():
	RoguelikeRun.start_run(_counts({"fighter": 2}))
	DoctrineSystem.set_instruction_in_place(
		RoguelikeRun.doctrine, DoctrineSystem.SCOPE_FLEET, "", PILOT_DOCTRINE)

	RoguelikeRun.reconcile_roster_to_counts(_counts({"fighter": 1}))

	assert_eq(RoguelikeRun.doctrine[DoctrineSystem.SCOPE_FLEET].size(), 1,
		"Fleet-wide doctrine should survive a fleet-count edit")


func test_reconcile_prunes_class_doctrine_for_an_emptied_type():
	RoguelikeRun.start_run(_counts({"fighter": 1, "corvette": 1}))
	DoctrineSystem.set_instruction_in_place(
		RoguelikeRun.doctrine, DoctrineSystem.SCOPE_CLASS, "corvette", PILOT_DOCTRINE)

	RoguelikeRun.reconcile_roster_to_counts(_counts({"fighter": 1}))

	assert_false(RoguelikeRun.doctrine[DoctrineSystem.SCOPE_CLASS].has("corvette"),
		"Class doctrine should drop when its ship type is removed from the fleet")


func test_reconcile_keeps_class_doctrine_for_a_present_type():
	RoguelikeRun.start_run(_counts({"fighter": 2}))
	DoctrineSystem.set_instruction_in_place(
		RoguelikeRun.doctrine, DoctrineSystem.SCOPE_CLASS, "fighter", PILOT_DOCTRINE)

	RoguelikeRun.reconcile_roster_to_counts(_counts({"fighter": 1}))

	assert_true(RoguelikeRun.doctrine[DoctrineSystem.SCOPE_CLASS].has("fighter"),
		"Class doctrine should survive while its ship type remains in the fleet")


# ============================================================================
# CAMPAIGN LIFECYCLE
# ============================================================================

func test_start_run_generates_a_campaign():
	RoguelikeRun.start_run(_counts({"fighter": 1}))

	assert_false(RoguelikeRun.campaign.is_empty(),
		"Starting a run generates the multi-sector campaign")
	assert_eq(RoguelikeRun.campaign["current_sector"], CampaignSystem.SECTORS[0],
		"A new campaign starts in the bottom sector")
	assert_gt(CampaignSystem.accessible_node_ids(RoguelikeRun.campaign).size(), 0,
		"A new campaign has an accessible starting node")


func test_end_run_clears_campaign():
	RoguelikeRun.start_run(_counts({"fighter": 1}))

	RoguelikeRun.end_run()

	assert_true(RoguelikeRun.campaign.is_empty(),
		"The campaign should be cleared when the run ends")


# ============================================================================
# BATTLE RESULT RECORDING
# ============================================================================

func _ship_with_crew(ship_type: String, status: String, crew_id: String) -> Dictionary:
	var ship = _make_ship(ship_type)
	ship["status"] = status
	ship["crew"] = [{"crew_id": crew_id, "callsign": crew_id, "assigned_to": ship.ship_id}]
	return ship


func test_victory_keeps_only_surviving_ships_and_crew():
	var survivor := _ship_with_crew("fighter", "operational", "alive")
	var casualty := _ship_with_crew("corvette", "destroyed", "dead")

	RoguelikeRun.record_battle_result(
		CampaignSystem.RESULT_VICTORY, [survivor, casualty], [])

	assert_eq(RoguelikeRun.fleet_ships.size(), 1, "Only survivors stay in the fleet")
	assert_eq(RoguelikeRun.fleet_ships[0]["type"], "fighter",
		"The surviving hull is the one that lived")
	assert_eq(RoguelikeRun.fleet_crew.size(), 1, "Only surviving crews stay")
	assert_eq(RoguelikeRun.fleet_crew[0]["crew"][0]["crew_id"], "alive",
		"The surviving crew kept their identity")
	assert_true(RoguelikeRun.lost_fleet_final_ships.is_empty(),
		"A victory leaves no lost fleet to roll survivors from")


func test_defeat_stashes_final_fleet_state_and_empties_fleet():
	var lost := _ship_with_crew("fighter", "destroyed", "fallen")
	var groups := [{"ship_type": "fighter", "crew": lost["crew"].duplicate(true)}]

	RoguelikeRun.record_battle_result(CampaignSystem.RESULT_DEFEAT, [lost], groups)

	assert_eq(RoguelikeRun.pending_battle_result, CampaignSystem.RESULT_DEFEAT,
		"The defeat is left pending for the campaign map to resolve")
	assert_eq(RoguelikeRun.lost_fleet_final_ships.size(), 1,
		"Defeat stashes the wiped fleet's final ship states")
	assert_eq(RoguelikeRun.lost_fleet_final_crew.size(), 1,
		"Defeat stashes the wiped fleet's crew groups")
	assert_true(RoguelikeRun.is_fleet_empty(), "A wiped fleet has no ships left")


# ============================================================================
# DEMOTION
# ============================================================================

func test_apply_demotion_combines_config_with_survivors():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	var survivor := _ship_with_crew("corvette", "operational", "veteran")
	var survivors := {"ships": [survivor],
		"crew_groups": [{"ship_type": "corvette", "crew": survivor["crew"].duplicate(true)}]}

	RoguelikeRun.apply_demotion(survivors, _counts({"fighter": 2}))

	assert_eq(RoguelikeRun.fleet["fighter"], 2,
		"The demoted fleet includes the saved config's hulls")
	assert_eq(RoguelikeRun.fleet["corvette"], 1,
		"The demoted fleet includes the rolled survivors")


func test_apply_demotion_only_survivors_carry_damage_state():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	var survivor := _ship_with_crew("corvette", "operational", "veteran")
	survivor["armor_sections"][0]["current_armor"] = 1
	var survivors := {"ships": [survivor], "crew_groups": []}

	RoguelikeRun.apply_demotion(survivors, _counts({"fighter": 2}))

	assert_eq(RoguelikeRun.fleet_ships.size(), 1,
		"Only survivor hulls carry a saved state; fresh hulls spawn undamaged")
	assert_eq(int(RoguelikeRun.fleet_ships[0]["armor_sections"][0]["current_armor"]), 1,
		"Survivor damage state carries into the demoted run")


func test_apply_demotion_rosters_fresh_crews_plus_survivor_crews():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	var survivor := _ship_with_crew("corvette", "operational", "veteran")
	var survivors := {"ships": [survivor],
		"crew_groups": [{"ship_type": "corvette", "crew": survivor["crew"].duplicate(true)}]}

	RoguelikeRun.apply_demotion(survivors, _counts({"fighter": 2}))

	assert_eq(RoguelikeRun.fleet_crew.size(), 3,
		"Two fresh fighter crews plus the surviving corvette crew")
	assert_true(_roster_has_crew_id("veteran"),
		"The surviving crew keeps its identity through the demotion")


func test_apply_demotion_prunes_doctrine_of_dead_crew():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	var dead := _ship_with_crew("fighter", "destroyed", "casualty")
	RoguelikeRun.lost_fleet_final_crew = [
		{"ship_type": "fighter", "crew": dead["crew"].duplicate(true)}]
	DoctrineSystem.set_instruction_in_place(
		RoguelikeRun.doctrine, DoctrineSystem.SCOPE_CREW, "casualty", PILOT_DOCTRINE)

	RoguelikeRun.apply_demotion({"ships": [], "crew_groups": []}, _counts({"fighter": 1}))

	assert_false(RoguelikeRun.doctrine[DoctrineSystem.SCOPE_CREW].has("casualty"),
		"Doctrine authored for crew lost in the rout is purged")


func test_reconcile_keeps_callsigns_unique_after_adding():
	RoguelikeRun.start_run(_counts({"fighter": 2}))

	RoguelikeRun.reconcile_roster_to_counts(_counts({"fighter": 4}))

	var callsigns: Array = []
	for group in RoguelikeRun.fleet_crew:
		for member in group.crew:
			callsigns.append(member.callsign)
	var unique: Array = []
	for c in callsigns:
		if c not in unique:
			unique.append(c)
	assert_eq(unique.size(), callsigns.size(),
		"Crew added by a reconcile must not reuse existing callsigns")
