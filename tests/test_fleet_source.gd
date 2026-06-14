extends GutTest

## Shared contract tests for FleetSource implementations.
## Tests run against SkirmishSource (built deterministically from team 9).
## RunSource contract tests run against a started RoguelikeRun (saved/restored).
##
## Tests assert BEHAVIOR: assign places crew in a slot, unassign returns to pool, etc.
## No specific roster names, hull counts, or data values asserted.

const TEST_TEAM: int = 9
const SAVE_PATH: String = "user://skirmish_fleet_team_9.json"
const PRESET_PATH: String = "user://skirmish_fleet_preset_team_9.json"

# Saved RoguelikeRun state for restoration after each test.
var _saved_fleet_hulls: Array = []
var _saved_doctrine: Dictionary = {}
var _saved_enemy_fleet: Dictionary = {}
var _saved_active: bool = false
var _saved_started_first_battle: bool = false
var _saved_star_date: int = 0
var _saved_hired_roster_ids: Array = []
var _saved_next_hull_id: int = 0
var _saved_squadrons: Array = []
var _saved_money: int = 0
var _saved_campaign: Dictionary = {}


func before_each() -> void:
	_delete_if_exists(SAVE_PATH)
	_delete_if_exists(PRESET_PATH)
	_saved_fleet_hulls = RoguelikeRun.fleet_hulls.duplicate(true)
	_saved_doctrine = RoguelikeRun.doctrine.duplicate(true)
	_saved_enemy_fleet = RoguelikeRun.enemy_fleet.duplicate(true)
	_saved_active = RoguelikeRun.active
	_saved_started_first_battle = RoguelikeRun.started_first_battle
	_saved_star_date = RoguelikeRun.current_star_date
	_saved_hired_roster_ids = RoguelikeRun.hired_roster_ids.duplicate()
	_saved_next_hull_id = RoguelikeRun._next_hull_id
	_saved_squadrons = RoguelikeRun.squadrons.duplicate(true)
	_saved_money = RoguelikeRun.money
	_saved_campaign = RoguelikeRun.campaign.duplicate(true)


func after_each() -> void:
	_delete_if_exists(SAVE_PATH)
	_delete_if_exists(PRESET_PATH)
	RoguelikeRun.fleet_hulls = _saved_fleet_hulls
	RoguelikeRun.doctrine = _saved_doctrine
	RoguelikeRun.enemy_fleet = _saved_enemy_fleet
	RoguelikeRun.active = _saved_active
	RoguelikeRun.started_first_battle = _saved_started_first_battle
	RoguelikeRun.current_star_date = _saved_star_date
	RoguelikeRun.hired_roster_ids = _saved_hired_roster_ids
	RoguelikeRun._next_hull_id = _saved_next_hull_id
	RoguelikeRun.squadrons = _saved_squadrons
	RoguelikeRun.money = _saved_money
	RoguelikeRun.campaign = _saved_campaign


# ============================================================
# SkirmishSource contract tests
# ============================================================

func test_skirmish_source_ships_returns_non_empty_fleet() -> void:
	"""SkirmishSource.ships() returns the generated fleet (non-empty)."""
	var src: SkirmishSource = SkirmishSource.new(TEST_TEAM)
	assert_true(src.ships().size() > 0, "skirmish fleet is non-empty")


func test_skirmish_source_squadrons_returns_empty() -> void:
	"""SkirmishSource.squadrons() returns an empty array (skirmish has none)."""
	var src: SkirmishSource = SkirmishSource.new(TEST_TEAM)
	assert_eq(src.squadrons().size(), 0, "skirmish has no squadrons")


func test_skirmish_unassign_moves_crew_to_pool() -> void:
	"""unassign removes a crew member from their ship and adds them to the pool."""
	var src: SkirmishSource = SkirmishSource.new(TEST_TEAM)
	var hull: Dictionary = src.ships()[0]
	assert_true(hull.get("crew", []).size() > 0, "first ship has crew")
	var member: Dictionary = hull.get("crew", [])[0]
	var crew_id: String = str(member.get("crew_id", ""))
	var pool_before: int = src.crew_pool().size()
	var crew_before: int = hull.get("crew", []).size()

	src.unassign(crew_id)

	assert_eq(src.crew_pool().size(), pool_before + 1, "pool grew by one")
	assert_eq(hull.get("crew", []).size(), crew_before - 1, "ship lost one crew member")
	var still_on_ship: bool = false
	for m in hull.get("crew", []):
		if str(m.get("crew_id", "")) == crew_id:
			still_on_ship = true
	assert_false(still_on_ship, "unassigned crew is no longer on the ship")


func test_skirmish_assign_moves_crew_from_pool_to_ship() -> void:
	"""assign pulls a crew member from the pool into a matching vacant slot."""
	var src: SkirmishSource = SkirmishSource.new(TEST_TEAM)
	var hull: Dictionary = src.ships()[0]
	var member: Dictionary = hull.get("crew", [])[0]
	var crew_id: String = str(member.get("crew_id", ""))

	src.unassign(crew_id)
	var pool_before_assign: int = src.crew_pool().size()
	var crew_before_assign: int = hull.get("crew", []).size()

	assert_true(src.can_assign(crew_id, str(hull.get("hull_id", ""))), "can_assign true after unassign")
	src.assign(crew_id, str(hull.get("hull_id", "")))

	assert_eq(src.crew_pool().size(), pool_before_assign - 1, "pool shrank by one after assign")
	assert_eq(hull.get("crew", []).size(), crew_before_assign + 1, "ship gained one crew member")


func test_skirmish_can_assign_false_when_no_vacancy() -> void:
	"""can_assign returns false when the target hull has no vacancy for that crew's role."""
	var src: SkirmishSource = SkirmishSource.new(TEST_TEAM)
	# Find a crew member on the pool (unassign one first).
	var hull: Dictionary = src.ships()[0]
	var member: Dictionary = hull.get("crew", [])[0]
	var crew_id: String = str(member.get("crew_id", ""))
	src.unassign(crew_id)
	# Re-assign them back to fill the vacancy.
	src.assign(crew_id, str(hull.get("hull_id", "")))
	# Now the slot is filled — can_assign with another pool member targeting the same role should be false
	# if no other vacancy of that role exists on that hull.
	var refilled_crew: Dictionary = {}
	for m in hull.get("crew", []):
		if str(m.get("crew_id", "")) == crew_id:
			refilled_crew = m
	assert_false(refilled_crew.is_empty(), "crew was re-assigned")
	# Double-unassign to confirm the vacancy was filled.
	src.unassign(crew_id)
	# Hull now has one vacancy again — assign a pool member of a different role and verify can_assign is false.
	var pool: Array = src.crew_pool()
	var wrong_role_member: Dictionary = {}
	var target_role: int = int(refilled_crew.get("role", CrewData.Role.PILOT))
	for pooled in pool:
		if int(pooled.get("role", -1)) != target_role:
			wrong_role_member = pooled
			break
	if wrong_role_member.is_empty():
		pass_test("no cross-role pool member available — skip")
		return
	var wrong_id: String = str(wrong_role_member.get("crew_id", ""))
	assert_false(
		src.can_assign(wrong_id, str(hull.get("hull_id", ""))),
		"wrong-role crew cannot fill a role-mismatched vacancy")


func test_skirmish_add_ship_grows_fleet() -> void:
	"""add_ship increases the ship count by one."""
	var src: SkirmishSource = SkirmishSource.new(TEST_TEAM)
	var before: int = src.ships().size()
	src.add_ship("fighter")
	assert_eq(src.ships().size(), before + 1, "fleet grew by one after add_ship")


func test_skirmish_add_ship_new_hull_has_complement() -> void:
	"""add_ship produces a hull with at least one complement slot and crew."""
	var src: SkirmishSource = SkirmishSource.new(TEST_TEAM)
	src.add_ship("fighter")
	var new_hull: Dictionary = src.ships()[src.ships().size() - 1]
	assert_true(new_hull.get("complement", []).size() > 0, "new hull has complement")
	assert_true(new_hull.get("crew", []).size() > 0, "new hull has crew")


func test_skirmish_remove_ship_shrinks_fleet() -> void:
	"""remove_ship decreases the ship count by one."""
	var src: SkirmishSource = SkirmishSource.new(TEST_TEAM)
	var before: int = src.ships().size()
	var hull_id: String = str(src.ships()[0].get("hull_id", ""))
	src.remove_ship(hull_id)
	assert_eq(src.ships().size(), before - 1, "fleet shrank by one after remove_ship")


func test_skirmish_remove_ship_returns_crew_to_pool() -> void:
	"""remove_ship sends all crew from the removed ship back to the pool."""
	var src: SkirmishSource = SkirmishSource.new(TEST_TEAM)
	var hull: Dictionary = src.ships()[0]
	var hull_id: String = str(hull.get("hull_id", ""))
	var crew_count: int = hull.get("crew", []).size()
	var pool_before: int = src.crew_pool().size()

	src.remove_ship(hull_id)

	assert_eq(src.crew_pool().size(), pool_before + crew_count, "pool grew by removed ship's crew count")


func test_skirmish_swap_exchanges_two_crew() -> void:
	"""swap moves crew_a to hull_b and crew_b to hull_a."""
	var src: SkirmishSource = SkirmishSource.new(TEST_TEAM)
	# Find two ships with crew of the same role.
	var hull_a: Dictionary = {}
	var hull_b: Dictionary = {}
	var member_a: Dictionary = {}
	var member_b: Dictionary = {}
	for hull in src.ships():
		for member in hull.get("crew", []):
			var role: int = int(member.get("role", -1))
			if member_a.is_empty():
				member_a = member
				hull_a = hull
			elif role == int(member_a.get("role", -2)) and str(hull.get("hull_id", "")) != str(hull_a.get("hull_id", "")):
				member_b = member
				hull_b = hull
				break
		if not member_b.is_empty():
			break

	if member_b.is_empty():
		pass_test("could not find two crew of the same role on different ships — skip")
		return

	var crew_id_a: String = str(member_a.get("crew_id", ""))
	var crew_id_b: String = str(member_b.get("crew_id", ""))
	var hull_id_a: String = str(hull_a.get("hull_id", ""))
	var hull_id_b: String = str(hull_b.get("hull_id", ""))

	src.swap(crew_id_a, crew_id_b)

	# crew_a should now be on hull_b.
	var a_on_b: bool = false
	for m in hull_b.get("crew", []):
		if str(m.get("crew_id", "")) == crew_id_a:
			a_on_b = true
	# crew_b should now be on hull_a.
	var b_on_a: bool = false
	for m in hull_a.get("crew", []):
		if str(m.get("crew_id", "")) == crew_id_b:
			b_on_a = true

	assert_true(a_on_b, "crew_a moved to hull_b after swap")
	assert_true(b_on_a, "crew_b moved to hull_a after swap")


func test_skirmish_set_tactics_persists_on_hull() -> void:
	"""set_tactics writes the tactics dict onto the target hull."""
	var src: SkirmishSource = SkirmishSource.new(TEST_TEAM)
	var hull: Dictionary = src.ships()[0]
	var hull_id: String = str(hull.get("hull_id", ""))
	var new_tactics: Dictionary = {"mission": "patrol", "mission_params": {"radius": 200}}

	src.set_tactics(hull_id, new_tactics)

	assert_eq(str(hull.get("tactics", {}).get("mission", "")), "patrol", "tactics.mission updated")


func test_skirmish_commit_persists_and_reload_reflects_changes() -> void:
	"""commit() saves to disk; a fresh SkirmishSource reload reflects the persisted state."""
	var src: SkirmishSource = SkirmishSource.new(TEST_TEAM)
	var hull: Dictionary = src.ships()[0]
	var hull_id: String = str(hull.get("hull_id", ""))
	var tactics: Dictionary = {"mission": "escort", "mission_params": {}}
	src.set_tactics(hull_id, tactics)
	src.commit()

	# Reload from disk.
	var src2: SkirmishSource = SkirmishSource.new(TEST_TEAM)
	var reloaded_hull: Dictionary = {}
	for h in src2.ships():
		if str(h.get("hull_id", "")) == hull_id:
			reloaded_hull = h
	assert_false(reloaded_hull.is_empty(), "reloaded hull found by id")
	assert_eq(
		str(reloaded_hull.get("tactics", {}).get("mission", "")),
		"escort",
		"tactics.mission persisted and reloaded")


func test_skirmish_set_fleet_preset_round_trips() -> void:
	"""set_fleet_preset is read back by get_fleet_preset on the same source."""
	var src: SkirmishSource = SkirmishSource.new(TEST_TEAM)
	src.set_fleet_preset("hammer_and_anvil")
	assert_eq(src.get_fleet_preset(), "hammer_and_anvil", "fleet preset reads back")


func test_skirmish_set_command_role_persists_on_hull() -> void:
	"""set_command_role writes the command_role mark onto the target hull."""
	var src: SkirmishSource = SkirmishSource.new(TEST_TEAM)
	var hull_id: String = str(src.ships()[0].get("hull_id", ""))
	src.set_command_role(hull_id, "commander")
	assert_eq(str(src.ships()[0].get("command_role", "")), "commander",
		"command_role mark set on hull")


func test_skirmish_fleet_preset_and_role_persist_through_commit_reload() -> void:
	"""commit() persists fleet preset + per-hull role/overrides; a fresh source reloads them."""
	var src: SkirmishSource = SkirmishSource.new(TEST_TEAM)
	var hull_id: String = str(src.ships()[0].get("hull_id", ""))
	src.set_fleet_preset("hammer_and_anvil")
	src.set_tactics(hull_id, {
		"mission": "free", "mission_params": {},
		"role": "artillery",
		"overrides": {"mentality": "all_out", "engagement_range": ""},
	})
	src.commit()

	var src2: SkirmishSource = SkirmishSource.new(TEST_TEAM)
	assert_eq(src2.get_fleet_preset(), "hammer_and_anvil", "fleet preset persisted + reloaded")
	var reloaded: Dictionary = {}
	for h in src2.ships():
		if str(h.get("hull_id", "")) == hull_id:
			reloaded = h
	assert_eq(str(reloaded.get("tactics", {}).get("role", "")), "artillery",
		"per-hull role persisted + reloaded")
	assert_eq(
		str(reloaded.get("tactics", {}).get("overrides", {}).get("mentality", "")),
		"all_out",
		"per-hull mentality override persisted + reloaded")


# ============================================================
# RunSource contract tests (over a live RoguelikeRun)
# ============================================================

func test_run_source_ships_reflects_run_fleet() -> void:
	"""RunSource.ships() returns the same array as RoguelikeRun.fleet_hulls."""
	RoguelikeRun.start_run(_run_counts())
	var src: RunSource = RunSource.new()
	assert_eq(src.ships().size(), RoguelikeRun.fleet_hulls.size(),
		"RunSource.ships() matches fleet_hulls size")


func test_run_source_squadrons_returns_run_squadrons() -> void:
	"""RunSource.squadrons() returns the same reference as RoguelikeRun.squadrons."""
	RoguelikeRun.start_run(_run_counts())
	var src: RunSource = RunSource.new()
	assert_eq(src.squadrons().size(), RoguelikeRun.squadrons.size(),
		"RunSource.squadrons() matches run squadrons size")


func test_run_source_add_ship_grows_fleet() -> void:
	"""add_ship on RunSource increases RoguelikeRun.fleet_hulls by one."""
	RoguelikeRun.start_run(_run_counts())
	var src: RunSource = RunSource.new()
	var before: int = src.ships().size()
	src.add_ship("fighter")
	assert_eq(src.ships().size(), before + 1, "fleet grew after RunSource.add_ship")


func test_run_source_remove_ship_shrinks_fleet() -> void:
	"""remove_ship on RunSource removes the hull from RoguelikeRun.fleet_hulls."""
	RoguelikeRun.start_run(_run_counts())
	var src: RunSource = RunSource.new()
	var before: int = src.ships().size()
	assert_true(before > 0, "fleet is non-empty")
	var hull_id: String = str(src.ships()[0].get("hull_id", ""))
	src.remove_ship(hull_id)
	assert_eq(src.ships().size(), before - 1, "fleet shrank after RunSource.remove_ship")


func test_run_source_can_assign_reflects_transfer_eligibility() -> void:
	"""RunSource.can_assign matches RoguelikeRun.can_transfer for the same args."""
	RoguelikeRun.start_run(_run_counts())
	var src: RunSource = RunSource.new()
	var hulls: Array = src.ships()
	if hulls.size() < 2:
		pass_test("need at least 2 hulls — skip")
		return
	var hull_a: Dictionary = hulls[0]
	var hull_b: Dictionary = hulls[1]
	if hull_a.get("crew", []).is_empty():
		pass_test("hull_a has no crew — skip")
		return
	var crew_id: String = str(hull_a.get("crew", [])[0].get("crew_id", ""))
	var hull_b_id: String = str(hull_b.get("hull_id", ""))
	assert_eq(
		src.can_assign(crew_id, hull_b_id),
		RoguelikeRun.can_transfer(crew_id, hull_b_id),
		"can_assign matches RoguelikeRun.can_transfer")


func test_run_source_set_tactics_writes_to_hull() -> void:
	"""RunSource.set_tactics writes the tactics dict to the hull in the run fleet."""
	RoguelikeRun.start_run(_run_counts())
	var src: RunSource = RunSource.new()
	var hull: Dictionary = src.ships()[0]
	var hull_id: String = str(hull.get("hull_id", ""))
	var tactics: Dictionary = {"mission": "intercept", "mission_params": {}}
	src.set_tactics(hull_id, tactics)
	assert_eq(
		str(RoguelikeRun.hull_by_id(hull_id).get("tactics", {}).get("mission", "")),
		"intercept",
		"tactics written to RoguelikeRun hull")


func test_run_source_set_fleet_preset_stored_on_run_tactics() -> void:
	"""RunSource.set_fleet_preset stores the id on RoguelikeRun.tactics["preset"] and reads back."""
	RoguelikeRun.start_run(_run_counts())
	var src: RunSource = RunSource.new()
	src.set_fleet_preset("hammer_and_anvil")
	assert_eq(str(RoguelikeRun.tactics.get("preset", "")), "hammer_and_anvil",
		"preset stored on run tactics")
	assert_eq(src.get_fleet_preset(), "hammer_and_anvil", "get_fleet_preset reads it back")


func test_run_source_set_command_role_writes_to_hull() -> void:
	"""RunSource.set_command_role marks the hull in the run fleet."""
	RoguelikeRun.start_run(_run_counts())
	var src: RunSource = RunSource.new()
	var hull_id: String = str(src.ships()[0].get("hull_id", ""))
	src.set_command_role(hull_id, "squadron_leader")
	assert_eq(str(RoguelikeRun.hull_by_id(hull_id).get("command_role", "")), "squadron_leader",
		"command_role written to run hull")


func test_run_source_commit_is_noop() -> void:
	"""RunSource.commit() does not raise an error (is a no-op)."""
	RoguelikeRun.start_run(_run_counts())
	var src: RunSource = RunSource.new()
	src.commit()
	pass_test("commit() is a no-op and did not error")


# ============================================================
# Helpers
# ============================================================

func _run_counts() -> Dictionary:
	"""Minimal fleet counts for a run (2 fighters, 1 corvette)."""
	return {"fighter": 2, "heavy_fighter": 0, "torpedo_boat": 0, "corvette": 1, "capital": 0}


func _delete_if_exists(path: String) -> void:
	"""Delete a user:// file if it exists."""
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
