extends GutTest

## Tests for RoguelikeRun state management - FUNCTIONALITY ONLY
## Verifies per-hull fleet persistence, damage carry-over, sortie eligibility,
## jump repairs, and enemy fleet independence.

var _saved_fleet_hulls: Array
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
var _saved_money: int
var _saved_battle_summary: Dictionary


func before_each() -> void:
	_saved_fleet_hulls = RoguelikeRun.fleet_hulls.duplicate(true)
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
	_saved_money = RoguelikeRun.money
	_saved_battle_summary = RoguelikeRun.last_battle_summary.duplicate(true)


func after_each() -> void:
	RoguelikeRun.fleet_hulls = _saved_fleet_hulls
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
	RoguelikeRun.money = _saved_money
	RoguelikeRun.last_battle_summary = _saved_battle_summary


const PILOT_DOCTRINE := "charge_head_on"


func _counts(overrides: Dictionary = {}) -> Dictionary:
	var base := {"fighter": 0, "heavy_fighter": 0,
		"torpedo_boat": 0, "corvette": 0, "capital": 0}
	for key in overrides:
		base[key] = overrides[key]
	return base


func _make_ship(ship_type: String) -> Dictionary:
	return ShipData.create_ship_instance(ship_type, 0, Vector2.ZERO)


## A survivor ship for the hull, as the battle scene hands one back: it carries
## the hull's stable id and a deep copy of its live crew.
func _survivor_for(hull: Dictionary) -> Dictionary:
	var survivor := _make_ship(hull.ship_type)
	survivor["hull_id"] = hull.hull_id
	survivor["crew"] = hull.crew.duplicate(true)
	return survivor


# ============================================================================
# RUN START: PER-HULL ROSTER
# ============================================================================

func test_run_start_creates_a_hull_per_ship():
	RoguelikeRun.start_run(_counts({"fighter": 2, "corvette": 1}))

	assert_eq(RoguelikeRun.fleet_hulls.size(), 3,
		"Each ship in the starting fleet should get its own hull record")
	var types: Array = []
	for hull in RoguelikeRun.fleet_hulls:
		types.append(hull.ship_type)
		assert_gt(hull.crew.size(), 0, "Every starting hull should be crewed")
	assert_eq(types.count("fighter"), 2, "Two fighter hulls expected")
	assert_eq(types.count("corvette"), 1, "One corvette hull expected")


func test_each_hull_has_a_unique_id():
	RoguelikeRun.start_run(_counts({"fighter": 3}))

	var ids: Array = []
	for hull in RoguelikeRun.fleet_hulls:
		ids.append(hull.hull_id)
	var unique: Array = []
	for id in ids:
		if id not in unique:
			unique.append(id)
	assert_eq(unique.size(), ids.size(), "Every hull id should be unique within a run")


func test_hull_has_a_standard_complement():
	RoguelikeRun.start_run(_counts({"fighter": 1}))

	assert_gt(RoguelikeRun.fleet_hulls[0].complement.size(), 0,
		"A hull's standard complement should be derived at creation")


func test_roster_crew_have_unique_callsigns():
	RoguelikeRun.start_run(_counts({"fighter": 2}))

	var callsigns: Array = []
	for hull in RoguelikeRun.fleet_hulls:
		for member in hull.crew:
			assert_true(member.has("callsign"), "Roster crew need a player-facing callsign")
			callsigns.append(member.callsign)
	assert_eq(callsigns.size(), 2, "One pilot per fighter")
	assert_ne(callsigns[0], callsigns[1], "Callsigns should be distinct")


func test_run_start_resets_doctrine():
	DoctrineSystem.set_instruction_in_place(
		RoguelikeRun.doctrine, DoctrineSystem.SCOPE_FLEET, "", PILOT_DOCTRINE)

	RoguelikeRun.start_run(_counts({"fighter": 1}))

	assert_true(RoguelikeRun.doctrine[DoctrineSystem.SCOPE_FLEET].is_empty(),
		"Doctrine is run state: a new run starts with no standing instructions")


# ============================================================================
# SORTIE ELIGIBILITY
# ============================================================================

func test_sortieable_excludes_iced_hulls():
	RoguelikeRun.start_run(_counts({"fighter": 2}))
	RoguelikeRun.fleet_hulls[0].iced = true

	assert_eq(RoguelikeRun.sortieable_hulls().size(), 1,
		"An iced hull should not sortie")


func test_sortieable_excludes_pilotless_hulls():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	RoguelikeRun.fleet_hulls[0].crew = []

	assert_eq(RoguelikeRun.sortieable_hulls().size(), 0,
		"A hull with no pilot cannot take the field")


func test_fleet_counts_only_sortieable_excludes_iced():
	RoguelikeRun.start_run(_counts({"fighter": 2}))
	RoguelikeRun.fleet_hulls[0].iced = true

	assert_eq(RoguelikeRun.fleet_counts(true).get("fighter", 0), 1,
		"Sortieable counts should drop the iced hull")
	assert_eq(RoguelikeRun.fleet_counts(false).get("fighter", 0), 2,
		"Full counts should include the iced hull")


# ============================================================================
# BATTLE OUTCOME: SURVIVORS, LOSSES, DAMAGE CARRY-OVER
# ============================================================================

func test_surviving_hull_keeps_armor_damage():
	RoguelikeRun.start_run(_counts({"corvette": 1}))
	var survivor := _survivor_for(RoguelikeRun.fleet_hulls[0])
	survivor["armor_sections"][0]["current_armor"] = 0

	RoguelikeRun.apply_battle_outcome([survivor])

	assert_eq(RoguelikeRun.fleet_hulls[0].ship["armor_sections"][0]["current_armor"], 0,
		"Depleted armor should carry over to the hull's persisted state")


func test_surviving_hull_keeps_internal_damage():
	RoguelikeRun.start_run(_counts({"corvette": 1}))
	var survivor := _survivor_for(RoguelikeRun.fleet_hulls[0])
	survivor["internals"][0]["status"] = "destroyed"

	RoguelikeRun.apply_battle_outcome([survivor])

	assert_eq(RoguelikeRun.fleet_hulls[0].ship["internals"][0]["status"], "destroyed",
		"A destroyed internal should carry over to the hull's persisted state")


func test_surviving_hull_keeps_crew_identity():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	var crew_id: String = RoguelikeRun.fleet_hulls[0].crew[0].crew_id
	var survivor := _survivor_for(RoguelikeRun.fleet_hulls[0])

	RoguelikeRun.apply_battle_outcome([survivor])

	assert_eq(RoguelikeRun.fleet_hulls[0].crew[0].crew_id, crew_id,
		"A surviving hull keeps the identity of the crew that flew it")


func test_persisted_survivor_is_deep_copied():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	var survivor := _survivor_for(RoguelikeRun.fleet_hulls[0])
	RoguelikeRun.apply_battle_outcome([survivor])

	survivor["armor_sections"][0]["current_armor"] = 999

	assert_ne(RoguelikeRun.fleet_hulls[0].ship["armor_sections"][0]["current_armor"], 999,
		"The persisted hull state should be a deep copy, not a live reference")


func test_lost_sortied_hull_is_removed():
	RoguelikeRun.start_run(_counts({"fighter": 2}))
	var kept: Dictionary = RoguelikeRun.fleet_hulls[0]

	RoguelikeRun.apply_battle_outcome([_survivor_for(kept)])

	assert_eq(RoguelikeRun.fleet_hulls.size(), 1,
		"A sortied hull with no survivor should be removed from the fleet")
	assert_eq(RoguelikeRun.fleet_hulls[0].hull_id, kept.hull_id,
		"The surviving hull should be the one that came back")


func test_iced_hull_untouched_when_battle_lost():
	RoguelikeRun.start_run(_counts({"fighter": 2}))
	RoguelikeRun.fleet_hulls[0].iced = true
	var iced_id: String = RoguelikeRun.fleet_hulls[0].hull_id

	# The only sortied hull dies; nobody comes back.
	RoguelikeRun.apply_battle_outcome([])

	assert_false(RoguelikeRun.hull_by_id(iced_id).is_empty(),
		"An iced hull never sortied, so a lost battle must not remove it")


func test_pilotless_hull_untouched_when_battle_lost():
	RoguelikeRun.start_run(_counts({"fighter": 1, "corvette": 1}))
	# Strip the fighter's crew so only the corvette sorties.
	for hull in RoguelikeRun.fleet_hulls:
		if hull.ship_type == "fighter":
			hull.crew = []
	var fighter_present := false
	for hull in RoguelikeRun.fleet_hulls:
		if hull.ship_type == "fighter":
			fighter_present = true

	RoguelikeRun.apply_battle_outcome([])

	var still_present := false
	for hull in RoguelikeRun.fleet_hulls:
		if hull.ship_type == "fighter":
			still_present = true
	assert_true(fighter_present and still_present,
		"A pilotless hull stays home, so a lost battle must not remove it")


func test_doctrine_pruned_when_hull_lost():
	RoguelikeRun.start_run(_counts({"fighter": 2}))
	var kept: Dictionary = RoguelikeRun.fleet_hulls[0]
	var lost: Dictionary = RoguelikeRun.fleet_hulls[1]
	var lost_crew_id: String = lost.crew[0].crew_id
	DoctrineSystem.set_instruction_in_place(
		RoguelikeRun.doctrine, DoctrineSystem.SCOPE_CREW, lost_crew_id, PILOT_DOCTRINE)

	RoguelikeRun.apply_battle_outcome([_survivor_for(kept)])

	assert_false(RoguelikeRun.doctrine[DoctrineSystem.SCOPE_CREW].has(lost_crew_id),
		"Per-crew doctrine for crew lost with their hull should be purged")


# ============================================================================
# CASUALTIES & INSURANCE
# ============================================================================

func test_lost_hull_charges_insurance_for_all_aboard():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	var crew_size: int = RoguelikeRun.fleet_hulls[0].crew.size()
	var money_before: int = RoguelikeRun.money

	# The lone sortied hull is lost: everyone aboard is a casualty.
	RoguelikeRun.apply_battle_outcome([])

	assert_eq(RoguelikeRun.last_battle_summary.get("casualties", 0), crew_size,
		"Every crew member aboard a lost hull is a casualty")
	assert_eq(RoguelikeRun.money,
		money_before - EconomySystem.insurance_total(crew_size),
		"Insurance is paid out for each casualty")


func test_surviving_hull_loses_the_gunner_whose_mount_was_destroyed():
	RoguelikeRun.start_run(_counts({"corvette": 1}))
	var hull: Dictionary = RoguelikeRun.fleet_hulls[0]
	var gunner_id := ""
	var weapon_id := ""
	for member in hull.crew:
		if member.get("role", -1) == CrewData.Role.GUNNER and member.has("weapon_id"):
			gunner_id = member.crew_id
			weapon_id = member.weapon_id
			break
	assert_ne(gunner_id, "", "precondition: a corvette carries a bound gunner")

	var survivor := _make_ship("corvette")
	survivor["hull_id"] = hull.hull_id
	survivor["crew"] = hull.crew.duplicate(true)
	for component in survivor.internals:
		if component.get("type", "") == "weapon_mount" and component.get("weapon_id", "") == weapon_id:
			component.status = "destroyed"
			component.current_health = 0

	RoguelikeRun.apply_battle_outcome([survivor])

	var survivor_ids: Array = RoguelikeRun.fleet_hulls[0].crew.map(func(m): return m.crew_id)
	assert_false(gunner_id in survivor_ids,
		"The gunner whose mount was shot off is a casualty")
	var has_pilot := false
	for member in RoguelikeRun.fleet_hulls[0].crew:
		if member.get("role", -1) == CrewData.Role.PILOT:
			has_pilot = true
	assert_true(has_pilot, "The pilot survives a hull that came home")


# ============================================================================
# FLEET EMPTY CHECK
# ============================================================================

func test_fleet_empty_after_all_hulls_lost():
	RoguelikeRun.start_run(_counts({"fighter": 1}))

	RoguelikeRun.apply_battle_outcome([])

	assert_true(RoguelikeRun.is_fleet_empty(),
		"Losing the last sortied hull empties the fleet")


func test_fleet_not_empty_while_a_hull_survives():
	RoguelikeRun.start_run(_counts({"fighter": 1}))

	RoguelikeRun.apply_battle_outcome([_survivor_for(RoguelikeRun.fleet_hulls[0])])

	assert_false(RoguelikeRun.is_fleet_empty(),
		"A surviving hull keeps the fleet non-empty")


# ============================================================================
# ENEMY FLEET INDEPENDENCE
# ============================================================================

func test_enemy_fleet_is_not_affected_by_battle_outcome():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	RoguelikeRun.enemy_fleet = {
		"fighter": 3, "corvette": 2, "heavy_fighter": 0, "torpedo_boat": 0, "capital": 0
	}

	RoguelikeRun.apply_battle_outcome([_survivor_for(RoguelikeRun.fleet_hulls[0])])

	assert_eq(RoguelikeRun.enemy_fleet.get("fighter", 0), 3,
		"Enemy counts should not change from a player battle outcome")
	assert_eq(RoguelikeRun.enemy_fleet.get("corvette", 0), 2,
		"Enemy counts should not change from a player battle outcome")


# ============================================================================
# RUN LIFECYCLE
# ============================================================================

func test_end_run_clears_fleet_hulls():
	RoguelikeRun.start_run(_counts({"fighter": 1}))

	RoguelikeRun.end_run()

	assert_true(RoguelikeRun.fleet_hulls.is_empty(),
		"fleet_hulls should be cleared when the run ends")


func test_end_run_clears_enemy_fleet():
	RoguelikeRun.enemy_fleet = {"fighter": 3, "corvette": 1,
		"heavy_fighter": 0, "torpedo_boat": 0, "capital": 0}

	RoguelikeRun.end_run()

	assert_true(RoguelikeRun.enemy_fleet.is_empty(),
		"enemy_fleet should be cleared when the run ends")


# ============================================================================
# JUMP REPAIRS (Engineers + star dates)
# ============================================================================

const JUMP_DATE_DELTA := 5


## A damaged corvette hull crewed by `engineer_count` engineers, ready for a
## jump-repair pass. The damage lives in `hull.ship` (crew stripped); the
## engineers live in `hull.crew`, the way the persistent fleet stores them.
func _make_damaged_hull(engineer_count: int) -> Dictionary:
	var ship := _make_ship("corvette")
	ship["armor_sections"][0]["current_armor"] = 1
	var crew: Array = []
	for i in engineer_count:
		crew.append(TestFactories.make_crew_engineer(1.0, ship.ship_id))
	return {
		"hull_id": "hull_jump",
		"ship_type": "corvette",
		"iced": false,
		"crew": crew,
		"complement": [],
		"ship": ship,
	}


func _hull_armor(hull: Dictionary) -> int:
	return DamageResolver.calculate_total_armor(hull.ship)


func test_jump_repairs_heal_hull_with_engineers():
	RoguelikeRun.fleet_hulls = [_make_damaged_hull(1)]
	var before := _hull_armor(RoguelikeRun.fleet_hulls[0])

	var summary = RoguelikeRun.apply_jump_repairs(RoguelikeRun.current_star_date + JUMP_DATE_DELTA, false)

	assert_gt(_hull_armor(RoguelikeRun.fleet_hulls[0]), before,
		"A hull with an engineer should heal during the jump")
	assert_eq(summary.ships_repaired, 1, "Summary should count the repaired hull")
	assert_eq(summary.date_delta, JUMP_DATE_DELTA, "Summary should report the star-date gap")


func test_jump_repairs_skip_hull_without_engineers():
	RoguelikeRun.fleet_hulls = [_make_damaged_hull(0)]
	var before := _hull_armor(RoguelikeRun.fleet_hulls[0])

	RoguelikeRun.apply_jump_repairs(RoguelikeRun.current_star_date + JUMP_DATE_DELTA, false)

	assert_eq(_hull_armor(RoguelikeRun.fleet_hulls[0]), before,
		"A hull without engineers should not heal during the jump")


func test_wider_date_gap_heals_more():
	var start_date = RoguelikeRun.current_star_date

	RoguelikeRun.fleet_hulls = [_make_damaged_hull(1)]
	RoguelikeRun.apply_jump_repairs(start_date + 2, false)
	var narrow_gap_armor := _hull_armor(RoguelikeRun.fleet_hulls[0])

	RoguelikeRun.current_star_date = start_date
	RoguelikeRun.fleet_hulls = [_make_damaged_hull(1)]
	RoguelikeRun.apply_jump_repairs(start_date + 9, false)
	var wide_gap_armor := _hull_armor(RoguelikeRun.fleet_hulls[0])

	assert_gt(wide_gap_armor, narrow_gap_armor,
		"A longer jump (more downtime) should repair more")


func test_rnr_heals_more_than_battle_jump_at_equal_gap():
	var start_date = RoguelikeRun.current_star_date

	RoguelikeRun.fleet_hulls = [_make_damaged_hull(1)]
	RoguelikeRun.apply_jump_repairs(start_date + JUMP_DATE_DELTA, false)
	var battle_jump_armor := _hull_armor(RoguelikeRun.fleet_hulls[0])

	RoguelikeRun.current_star_date = start_date
	RoguelikeRun.fleet_hulls = [_make_damaged_hull(1)]
	RoguelikeRun.apply_jump_repairs(start_date + JUMP_DATE_DELTA, true)
	var rnr_armor := _hull_armor(RoguelikeRun.fleet_hulls[0])

	assert_gt(rnr_armor, battle_jump_armor,
		"R&R downtime should repair more than a battle jump of the same gap")


func test_jump_repairs_restore_destroyed_components():
	var hull := _make_damaged_hull(1)
	hull.ship["internals"][0]["status"] = "destroyed"
	hull.ship["internals"][0]["current_health"] = 0
	RoguelikeRun.fleet_hulls = [hull]

	RoguelikeRun.apply_jump_repairs(RoguelikeRun.current_star_date + JUMP_DATE_DELTA, true)

	assert_gt(RoguelikeRun.fleet_hulls[0].ship["internals"][0]["current_health"], 0,
		"Downtime repairs should restore destroyed components")
	assert_ne(RoguelikeRun.fleet_hulls[0].ship["internals"][0]["status"], "destroyed",
		"Restored component should no longer be destroyed")


func test_jump_repairs_skip_pristine_hulls():
	RoguelikeRun.start_run(_counts({"fighter": 1}))

	var summary = RoguelikeRun.apply_jump_repairs(RoguelikeRun.current_star_date + JUMP_DATE_DELTA, false)

	assert_eq(summary.ships_repaired, 0,
		"A pristine hull (no recorded damage) has nothing to repair")


func test_jump_advances_current_star_date():
	var destination = RoguelikeRun.current_star_date + JUMP_DATE_DELTA

	RoguelikeRun.apply_jump_repairs(destination, false)

	assert_eq(RoguelikeRun.current_star_date, destination,
		"The jump should move the run to the destination star date")


func test_jump_repair_summary_persists_for_the_map():
	RoguelikeRun.fleet_hulls = [_make_damaged_hull(1)]

	RoguelikeRun.apply_jump_repairs(RoguelikeRun.current_star_date + JUMP_DATE_DELTA, false)

	assert_gt(RoguelikeRun.last_jump_repair_summary.get("ships_repaired", 0), 0,
		"The map reports repairs after a battle from the persisted summary")


# ============================================================================
# ROSTER RECONCILE (Edit Fleet adjusts fleet counts mid-setup)
# ============================================================================

func _hulls_of_type(ship_type: String) -> int:
	var n := 0
	for hull in RoguelikeRun.fleet_hulls:
		if hull.get("ship_type", "") == ship_type:
			n += 1
	return n


func _roster_has_crew_id(crew_id: String) -> bool:
	for hull in RoguelikeRun.fleet_hulls:
		for member in hull.crew:
			if member.get("crew_id", "") == crew_id:
				return true
	return false


func test_reconcile_adds_hulls_when_a_count_grows():
	RoguelikeRun.start_run(_counts({"fighter": 1}))

	RoguelikeRun.reconcile_roster_to_counts(_counts({"fighter": 3}))

	assert_eq(_hulls_of_type("fighter"), 3,
		"Raising a ship count should add hulls for the new ships")


func test_reconcile_drops_hulls_when_a_count_shrinks():
	RoguelikeRun.start_run(_counts({"fighter": 3}))

	RoguelikeRun.reconcile_roster_to_counts(_counts({"fighter": 1}))

	assert_eq(_hulls_of_type("fighter"), 1,
		"Lowering a ship count should drop the surplus hulls")


func test_reconcile_preserves_identity_of_retained_crew():
	RoguelikeRun.start_run(_counts({"fighter": 2}))
	var kept_id: String = RoguelikeRun.fleet_hulls[0].crew[0].crew_id

	RoguelikeRun.reconcile_roster_to_counts(_counts({"fighter": 1}))

	assert_true(_roster_has_crew_id(kept_id),
		"Crew on a retained hull should keep their identity across a fleet edit")


func test_reconcile_purges_doctrine_for_dropped_crew():
	RoguelikeRun.start_run(_counts({"fighter": 2}))
	var dropped_id: String = RoguelikeRun.fleet_hulls[1].crew[0].crew_id
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


func test_victory_keeps_only_surviving_hulls_and_crew():
	RoguelikeRun.start_run(_counts({"fighter": 1, "corvette": 1}))
	var fighter: Dictionary = RoguelikeRun.fleet_hulls[0]
	var corvette: Dictionary = RoguelikeRun.fleet_hulls[1]
	var survivor := _survivor_for(fighter)
	var casualty := _survivor_for(corvette)
	casualty["status"] = "destroyed"

	RoguelikeRun.record_battle_result(
		CampaignSystem.RESULT_VICTORY, [survivor, casualty])

	assert_eq(RoguelikeRun.fleet_hulls.size(), 1, "Only survivors stay in the fleet")
	assert_eq(RoguelikeRun.fleet_hulls[0].ship_type, "fighter",
		"The surviving hull is the one that lived")
	assert_eq(RoguelikeRun.fleet_hulls[0].hull_id, fighter.hull_id,
		"The surviving hull kept its stable identity")
	assert_true(RoguelikeRun.lost_fleet_final_ships.is_empty(),
		"A victory leaves no lost fleet to roll survivors from")


func test_defeat_stashes_final_fleet_state_and_empties_fleet():
	var lost := _ship_with_crew("fighter", "destroyed", "fallen")

	RoguelikeRun.record_battle_result(CampaignSystem.RESULT_DEFEAT, [lost])

	assert_eq(RoguelikeRun.pending_battle_result, CampaignSystem.RESULT_DEFEAT,
		"The defeat is left pending for the campaign map to resolve")
	assert_eq(RoguelikeRun.lost_fleet_final_ships.size(), 1,
		"Defeat stashes the wiped fleet's final ship states")
	assert_true(RoguelikeRun.is_fleet_empty(), "A wiped fleet has no hulls left")


# CAN_AFFORD_REBUILD

func test_can_afford_rebuild_true_when_money_covers_cheapest_hull():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	var cheapest := -1
	for ship_type in FleetDataManager.SHIP_TYPES:
		var price := EconomySystem.ship_purchase_price(ship_type)
		if cheapest < 0 or price < cheapest:
			cheapest = price
	RoguelikeRun.money = cheapest

	assert_true(RoguelikeRun.can_afford_rebuild(),
		"can_afford_rebuild should be true when money equals the cheapest hull price")


func test_can_afford_rebuild_false_when_money_is_zero():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	RoguelikeRun.money = 0

	assert_false(RoguelikeRun.can_afford_rebuild(),
		"can_afford_rebuild should be false when the player has no money")





# ============================================================================

# ============================================================================

func test_reconcile_keeps_callsigns_unique_after_adding():
	RoguelikeRun.start_run(_counts({"fighter": 2}))

	RoguelikeRun.reconcile_roster_to_counts(_counts({"fighter": 4}))

	var callsigns: Array = []
	for hull in RoguelikeRun.fleet_hulls:
		for member in hull.crew:
			callsigns.append(member.callsign)
	var unique: Array = []
	for c in callsigns:
		if c not in unique:
			unique.append(c)
	assert_eq(unique.size(), callsigns.size(),
		"Crew added by a reconcile must not reuse existing callsigns")


# ============================================================================
# FIELDED CREW (read-only run roster view)
# ============================================================================

func test_fielded_crew_flattens_every_hulls_crew():
	RoguelikeRun.fleet_hulls = [
		{"hull_id": "h1", "crew": [{"callsign": "A"}, {"callsign": "B"}]},
		{"hull_id": "h2", "crew": [{"callsign": "C"}]},
		{"hull_id": "h3", "crew": []},
	]

	var crew: Array = RoguelikeRun.fielded_crew()

	assert_eq(crew.size(), 3,
		"fielded_crew returns every crew member serving across all hulls")
	var callsigns: Array = []
	for member in crew:
		callsigns.append(member.get("callsign"))
	assert_true(callsigns.has("A") and callsigns.has("B") and callsigns.has("C"),
		"fielded_crew includes crew drawn from every hull")


func test_fielded_crew_is_empty_without_hulls():
	RoguelikeRun.fleet_hulls = []
	assert_eq(RoguelikeRun.fielded_crew().size(), 0,
		"fielded_crew is empty when the fleet has no hulls")
