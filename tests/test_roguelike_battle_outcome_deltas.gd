extends GutTest

## Tests for ship_deltas recorded in last_battle_summary by apply_battle_outcome.
## Verifies before/after hull condition tracking for the post-battle overview.

var _saved_fleet_hulls: Array
var _saved_money: int
var _saved_battle_summary: Dictionary
var _saved_battle_progression: Array


func before_each() -> void:
	_saved_fleet_hulls = RoguelikeRun.fleet_hulls.duplicate(true)
	_saved_money = RoguelikeRun.money
	_saved_battle_summary = RoguelikeRun.last_battle_summary.duplicate(true)
	_saved_battle_progression = RoguelikeRun.last_battle_progression.duplicate(true)


func after_each() -> void:
	RoguelikeRun.fleet_hulls = _saved_fleet_hulls
	RoguelikeRun.money = _saved_money
	RoguelikeRun.last_battle_summary = _saved_battle_summary
	RoguelikeRun.last_battle_progression = _saved_battle_progression


func _make_pilot(crew_id: String = "pilot") -> Dictionary:
	return {
		"crew_id": crew_id,
		"callsign": crew_id,
		"role": CrewData.Role.PILOT,
		"assigned_to": "ship_%s" % crew_id,
		"stats": {"skills": {"aim": 0.5, "piloting": 0.5, "machinery": 0.5,
			"awareness": 0.5, "tactics": 0.5, "composure": 0.5, "aggression": 0.5}},
		"command_chain": {"superior": null, "subordinates": []},
	}


func _make_hull(hull_id: String, ship: Dictionary = {}) -> Dictionary:
	var pilot := _make_pilot(hull_id + "_p")
	pilot["assigned_to"] = hull_id + "_ship"
	return {
		"hull_id": hull_id,
		"ship_type": "fighter",
		"iced": false,
		"crew": [pilot],
		"complement": [{"role": CrewData.Role.PILOT}],
		"ship": ship,
	}


func _make_ship_with_armor(hull_id: String, current: float, max_val: float) -> Dictionary:
	return {
		"hull_id": hull_id,
		"ship_id": hull_id + "_ship",
		"armor_sections": [{"current_armor": current, "max_armor": max_val}],
		"internals": [{"current_health": 100.0, "max_health": 100.0}],
	}


func _attach_crew_to_ship(ship: Dictionary, hull: Dictionary) -> Dictionary:
	var ship_copy := ship.duplicate(true)
	ship_copy["crew"] = hull["crew"].duplicate(true)
	for member in ship_copy["crew"]:
		member["assigned_to"] = ship.get("ship_id", "")
	return ship_copy


# --- Ship deltas are recorded ---

func test_ship_deltas_recorded_after_battle():
	var hull := _make_hull("h1", {})
	RoguelikeRun.fleet_hulls = [hull]
	RoguelikeRun.money = 10000

	var survivor_ship := _make_ship_with_armor("h1", 80.0, 100.0)
	var survivor := _attach_crew_to_ship(survivor_ship, hull)
	RoguelikeRun.apply_battle_outcome([survivor])

	var deltas: Array = RoguelikeRun.last_battle_summary.get("ship_deltas", [])
	assert_eq(deltas.size(), 1, "One delta per sortied hull")
	assert_true(deltas[0].has("armor_before"), "Delta should have armor_before")
	assert_true(deltas[0].has("armor_after"), "Delta should have armor_after")
	assert_true(deltas[0].has("systems_before"), "Delta should have systems_before")
	assert_true(deltas[0].has("systems_after"), "Delta should have systems_after")


# --- Damaged survivor shows armor loss ---

func test_damaged_survivor_shows_armor_loss():
	# Hull started pristine (ship = {}), took damage this battle
	var hull := _make_hull("h1", {})
	RoguelikeRun.fleet_hulls = [hull]
	RoguelikeRun.money = 10000

	var survivor_ship := _make_ship_with_armor("h1", 50.0, 100.0)
	var survivor := _attach_crew_to_ship(survivor_ship, hull)
	RoguelikeRun.apply_battle_outcome([survivor])

	var deltas: Array = RoguelikeRun.last_battle_summary.get("ship_deltas", [])
	var delta: Dictionary = deltas[0]
	assert_true(float(delta.get("armor_after", 1.0)) < float(delta.get("armor_before", 0.0)),
		"A hull that took armor damage should show armor_after < armor_before")


# --- Destroyed hull flagged ---

func test_destroyed_hull_flagged_with_zero_armor():
	var hull := _make_hull("h1", {})
	RoguelikeRun.fleet_hulls = [hull]
	RoguelikeRun.money = 10000

	# No survivor for this hull = lost with all hands
	RoguelikeRun.apply_battle_outcome([])

	var deltas: Array = RoguelikeRun.last_battle_summary.get("ship_deltas", [])
	assert_eq(deltas.size(), 1, "Destroyed hull still gets a delta record")
	var delta: Dictionary = deltas[0]
	assert_true(bool(delta.get("destroyed", false)), "Destroyed hull must have destroyed == true")
	assert_eq(float(delta.get("armor_after", -1.0)), 0.0, "Destroyed hull armor_after must be 0.0")
	assert_eq(float(delta.get("systems_after", -1.0)), 0.0, "Destroyed hull systems_after must be 0.0")


# --- Pristine before ---

func test_pristine_hull_reports_armor_before_one():
	# hull.ship = {} means pristine before the battle
	var hull := _make_hull("h1", {})
	RoguelikeRun.fleet_hulls = [hull]
	RoguelikeRun.money = 10000

	var survivor_ship := _make_ship_with_armor("h1", 100.0, 100.0)
	var survivor := _attach_crew_to_ship(survivor_ship, hull)
	RoguelikeRun.apply_battle_outcome([survivor])

	var deltas: Array = RoguelikeRun.last_battle_summary.get("ship_deltas", [])
	assert_eq(float(deltas[0].get("armor_before", 0.0)), 1.0,
		"A hull with pristine ship state should report armor_before == 1.0")
