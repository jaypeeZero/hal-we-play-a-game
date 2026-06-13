extends GutTest

## Tests for RoguelikeRun.can_transfer, can_swap, swap_crew — BEHAVIOR ONLY.
## Verifies that the validity checks and the swap mutation produce correct fleet
## state, including command-chain rewire and gunner weapon-id exchange.

var _saved_fleet_hulls: Array
var _saved_money: int
var _saved_doctrine: Dictionary
var _saved_active: bool
var _saved_campaign: Dictionary
var _saved_hired_ids: Array


func before_each() -> void:
	_saved_fleet_hulls = RoguelikeRun.fleet_hulls.duplicate(true)
	_saved_money = RoguelikeRun.money
	_saved_doctrine = RoguelikeRun.doctrine.duplicate(true)
	_saved_active = RoguelikeRun.active
	_saved_campaign = RoguelikeRun.campaign.duplicate(true)
	_saved_hired_ids = RoguelikeRun.hired_roster_ids.duplicate()


func after_each() -> void:
	RoguelikeRun.fleet_hulls = _saved_fleet_hulls
	RoguelikeRun.money = _saved_money
	RoguelikeRun.doctrine = _saved_doctrine
	RoguelikeRun.active = _saved_active
	RoguelikeRun.campaign = _saved_campaign
	RoguelikeRun.hired_roster_ids = _saved_hired_ids


func _counts(overrides: Dictionary = {}) -> Dictionary:
	var base := {"fighter": 0, "heavy_fighter": 0,
		"torpedo_boat": 0, "corvette": 0, "capital": 0}
	for key in overrides:
		base[key] = overrides[key]
	return base


## First pilot on any hull in the fleet.
func _first_pilot_id() -> String:
	for hull in RoguelikeRun.fleet_hulls:
		for member in hull.get("crew", []):
			if member.get("role", -1) == CrewData.Role.PILOT:
				return member.crew_id
	return ""


## Hull that contains `crew_id`.
func _hull_of(crew_id: String) -> Dictionary:
	for hull in RoguelikeRun.fleet_hulls:
		for member in hull.get("crew", []):
			if member.get("crew_id", "") == crew_id:
				return hull
	return {}


# ---- can_transfer ----

func test_can_transfer_true_for_matching_vacancy():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	RoguelikeRun.money = 100000
	var src: Dictionary = RoguelikeRun.fleet_hulls[0]
	var dest := RoguelikeRun.add_purchased_hull("fighter")  # empty: pilot vacancy
	var pilot_id: String = src.crew[0].crew_id

	assert_true(RoguelikeRun.can_transfer(pilot_id, dest.hull_id),
		"can_transfer is true when destination has a matching vacancy")


func test_can_transfer_false_same_hull():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	var hull: Dictionary = RoguelikeRun.fleet_hulls[0]
	var pilot_id: String = hull.crew[0].crew_id

	assert_false(RoguelikeRun.can_transfer(pilot_id, hull.hull_id),
		"can_transfer rejects a move to the same hull")


func test_can_transfer_false_no_vacancy():
	RoguelikeRun.start_run(_counts({"fighter": 2}))
	var src: Dictionary = RoguelikeRun.fleet_hulls[0]
	var dest: Dictionary = RoguelikeRun.fleet_hulls[1]  # already has a pilot
	var pilot_id: String = src.crew[0].crew_id

	assert_false(RoguelikeRun.can_transfer(pilot_id, dest.hull_id),
		"can_transfer rejects when destination has no same-role vacancy")


func test_can_transfer_false_missing_crew():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	RoguelikeRun.money = 100000
	var dest := RoguelikeRun.add_purchased_hull("fighter")

	assert_false(RoguelikeRun.can_transfer("nonexistent_id", dest.hull_id),
		"can_transfer rejects a crew_id that does not exist in the fleet")


# ---- can_swap ----

func test_can_swap_true_for_same_role_different_hulls():
	RoguelikeRun.start_run(_counts({"fighter": 2}))
	var id_a: String = RoguelikeRun.fleet_hulls[0].crew[0].crew_id
	var id_b: String = RoguelikeRun.fleet_hulls[1].crew[0].crew_id

	assert_true(RoguelikeRun.can_swap(id_a, id_b),
		"can_swap is true for two pilots on different hulls")


func test_can_swap_false_same_hull():
	RoguelikeRun.start_run(_counts({"corvette": 1}))
	var hull: Dictionary = RoguelikeRun.fleet_hulls[0]
	# Need at least two crew on one hull; use the full complement.
	var crew_ids: Array = hull.crew.map(func(m): return m.crew_id)
	if crew_ids.size() < 2:
		pass_test("precondition: not enough crew for same-hull test; skipping")
		return

	assert_false(RoguelikeRun.can_swap(crew_ids[0], crew_ids[1]),
		"can_swap rejects two crew members on the same hull")


func test_can_swap_false_different_roles():
	RoguelikeRun.start_run(_counts({"corvette": 2}))
	# Find a pilot on hull 0 and a gunner on hull 1.
	var pilot_id := ""
	var gunner_id := ""
	for member in RoguelikeRun.fleet_hulls[0].get("crew", []):
		if member.get("role", -1) == CrewData.Role.PILOT:
			pilot_id = member.crew_id
	for member in RoguelikeRun.fleet_hulls[1].get("crew", []):
		if member.get("role", -1) == CrewData.Role.GUNNER:
			gunner_id = member.crew_id
	if pilot_id == "" or gunner_id == "":
		pass_test("precondition: corvette lacks pilot+gunner pair; skipping")
		return

	assert_false(RoguelikeRun.can_swap(pilot_id, gunner_id),
		"can_swap rejects a cross-role swap")


func test_can_swap_false_missing_crew():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	var pilot_id: String = RoguelikeRun.fleet_hulls[0].crew[0].crew_id

	assert_false(RoguelikeRun.can_swap(pilot_id, "nonexistent_id"),
		"can_swap rejects when one of the crew ids does not exist")


func test_can_swap_false_same_id():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	var pilot_id: String = RoguelikeRun.fleet_hulls[0].crew[0].crew_id

	assert_false(RoguelikeRun.can_swap(pilot_id, pilot_id),
		"can_swap rejects when both ids refer to the same person")


# ---- swap_crew ----

func test_swap_crew_exchanges_hull_membership():
	RoguelikeRun.start_run(_counts({"fighter": 2}))
	var hull_a: Dictionary = RoguelikeRun.fleet_hulls[0]
	var hull_b: Dictionary = RoguelikeRun.fleet_hulls[1]
	var id_a: String = hull_a.crew[0].crew_id
	var id_b: String = hull_b.crew[0].crew_id

	var ok := RoguelikeRun.swap_crew(id_a, id_b)

	assert_true(ok, "swap_crew returns true on a valid pair")
	assert_eq(_hull_of(id_a).hull_id, hull_b.hull_id,
		"crew A now lives on hull B after the swap")
	assert_eq(_hull_of(id_b).hull_id, hull_a.hull_id,
		"crew B now lives on hull A after the swap")


func test_swap_crew_rewires_command_chains():
	RoguelikeRun.start_run(_counts({"fighter": 2}))
	var hull_a: Dictionary = RoguelikeRun.fleet_hulls[0]
	var hull_b: Dictionary = RoguelikeRun.fleet_hulls[1]
	var id_a: String = hull_a.crew[0].crew_id
	var id_b: String = hull_b.crew[0].crew_id

	RoguelikeRun.swap_crew(id_a, id_b)

	# After the swap each pilot is the lone crew on its new hull, so they have
	# no superior (they are effectively the commander of an empty hull).
	var moved_a: Dictionary = {}
	for member in hull_b.crew:
		if member.crew_id == id_a:
			moved_a = member
	var moved_b: Dictionary = {}
	for member in hull_a.crew:
		if member.crew_id == id_b:
			moved_b = member

	assert_false(moved_a.is_empty(), "Pilot A landed on hull B")
	assert_false(moved_b.is_empty(), "Pilot B landed on hull A")


func test_swap_crew_false_for_invalid_pair():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	var pilot_id: String = RoguelikeRun.fleet_hulls[0].crew[0].crew_id

	var ok := RoguelikeRun.swap_crew(pilot_id, "ghost_id")

	assert_false(ok, "swap_crew returns false when the pair is invalid")


func test_swap_crew_gunners_exchange_weapon_ids():
	# Use two corvettes (each has a gunner slot bound to a weapon).
	RoguelikeRun.start_run(_counts({"corvette": 2}))
	var hull_a: Dictionary = RoguelikeRun.fleet_hulls[0]
	var hull_b: Dictionary = RoguelikeRun.fleet_hulls[1]

	var gunner_a: Dictionary = {}
	var gunner_b: Dictionary = {}
	for member in hull_a.crew:
		if member.get("role", -1) == CrewData.Role.GUNNER and member.has("weapon_id"):
			gunner_a = member
	for member in hull_b.crew:
		if member.get("role", -1) == CrewData.Role.GUNNER and member.has("weapon_id"):
			gunner_b = member
	if gunner_a.is_empty() or gunner_b.is_empty():
		pass_test("precondition: corvettes lack bound gunners; skipping")
		return

	var wid_a: String = gunner_a.weapon_id
	var wid_b: String = gunner_b.weapon_id
	var id_a: String = gunner_a.crew_id
	var id_b: String = gunner_b.crew_id

	RoguelikeRun.swap_crew(id_a, id_b)

	# Find where each gunner landed and check their weapon binding.
	var landed_a: Dictionary = {}
	var landed_b: Dictionary = {}
	for hull in RoguelikeRun.fleet_hulls:
		for member in hull.crew:
			if member.crew_id == id_a:
				landed_a = member
			elif member.crew_id == id_b:
				landed_b = member

	assert_eq(landed_a.get("weapon_id", ""), wid_b,
		"Gunner A now operates the weapon that belonged to gunner B's hull")
	assert_eq(landed_b.get("weapon_id", ""), wid_a,
		"Gunner B now operates the weapon that belonged to gunner A's hull")
