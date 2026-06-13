extends GutTest

## Behavior tests for the "Manage Crew" button in SquadronManager.
## Verifies button presence in header during active run only.

var _saved_fleet_hulls: Array
var _saved_active: bool
var _saved_money: int
var _saved_hired_ids: Array
var _saved_squadrons: Array


func before_each() -> void:
	_saved_fleet_hulls = RoguelikeRun.fleet_hulls.duplicate(true)
	_saved_active = RoguelikeRun.active
	_saved_money = RoguelikeRun.money
	_saved_hired_ids = RoguelikeRun.hired_roster_ids.duplicate()
	_saved_squadrons = RoguelikeRun.squadrons.duplicate(true)


func after_each() -> void:
	RoguelikeRun.fleet_hulls = _saved_fleet_hulls
	RoguelikeRun.active = _saved_active
	RoguelikeRun.money = _saved_money
	RoguelikeRun.hired_roster_ids = _saved_hired_ids
	RoguelikeRun.squadrons = _saved_squadrons


func _counts(overrides: Dictionary = {}) -> Dictionary:
	var base := {"fighter": 0, "heavy_fighter": 0,
		"torpedo_boat": 0, "corvette": 0, "capital": 0}
	for key in overrides:
		base[key] = overrides[key]
	return base


func _find_button(node: Node, text: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text == text:
			return child
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _make_squadron_manager(fleet_hulls: Array) -> SquadronManager:
	var mgr := SquadronManager.new()
	add_child_autofree(mgr)
	mgr.setup(fleet_hulls)
	return mgr


func test_manage_crew_button_present_during_active_run() -> void:
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	var hulls := RoguelikeRun.fleet_hulls.duplicate(true)
	var mgr := _make_squadron_manager(hulls)
	var btn := _find_button(mgr, "Manage Crew")
	assert_not_null(btn, "Manage Crew button present in SquadronManager during active run")


func test_manage_crew_button_absent_without_active_run() -> void:
	RoguelikeRun.active = false
	RoguelikeRun.fleet_hulls = []
	var hulls := [{"hull_id": "fighter_0", "ship_type": "fighter"}]
	var mgr := _make_squadron_manager(hulls)
	var btn := _find_button(mgr, "Manage Crew")
	assert_null(btn, "Manage Crew button absent when no active run")
