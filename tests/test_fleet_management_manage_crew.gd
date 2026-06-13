extends GutTest

## Behavior tests for the "Manage Crew" button in FleetManagement.
## Verifies the button is only shown during an active run with hulls.

const FleetManagementScene := preload("res://scenes/fleet_management.tscn")

var _saved_fleet_hulls: Array
var _saved_active: bool
var _saved_money: int
var _saved_hired_ids: Array


func before_each() -> void:
	_saved_fleet_hulls = RoguelikeRun.fleet_hulls.duplicate(true)
	_saved_active = RoguelikeRun.active
	_saved_money = RoguelikeRun.money
	_saved_hired_ids = RoguelikeRun.hired_roster_ids.duplicate()


func after_each() -> void:
	RoguelikeRun.fleet_hulls = _saved_fleet_hulls
	RoguelikeRun.active = _saved_active
	RoguelikeRun.money = _saved_money
	RoguelikeRun.hired_roster_ids = _saved_hired_ids


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


func test_manage_crew_button_visible_during_active_run() -> void:
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	var scene: FleetManagement = FleetManagementScene.instantiate()
	add_child_autofree(scene)
	var btn := _find_button(scene, "Manage Crew")
	assert_not_null(btn, "Manage Crew button exists in scene")
	assert_true(btn.visible, "Manage Crew button is visible during active run with hulls")


func test_manage_crew_button_hidden_when_no_active_run() -> void:
	RoguelikeRun.active = false
	RoguelikeRun.fleet_hulls = []
	var scene: FleetManagement = FleetManagementScene.instantiate()
	add_child_autofree(scene)
	var btn := _find_button(scene, "Manage Crew")
	assert_not_null(btn, "Manage Crew button exists in scene")
	assert_false(btn.visible, "Manage Crew button hidden when no active run")
