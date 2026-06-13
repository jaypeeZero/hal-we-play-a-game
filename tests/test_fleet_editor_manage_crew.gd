extends GutTest

## Behavior tests for the "Manage Crew" button in FleetEditor.
## Verifies button presence in footer during active run only.

const FleetEditorScene := preload("res://scenes/fleet_editor.tscn")

var _saved_fleet_hulls: Array
var _saved_active: bool
var _saved_money: int
var _saved_hired_ids: Array
var _saved_return_scene: String


func before_each() -> void:
	_saved_fleet_hulls = RoguelikeRun.fleet_hulls.duplicate(true)
	_saved_active = RoguelikeRun.active
	_saved_money = RoguelikeRun.money
	_saved_hired_ids = RoguelikeRun.hired_roster_ids.duplicate()
	_saved_return_scene = RoguelikeRun.editor_return_scene


func after_each() -> void:
	RoguelikeRun.fleet_hulls = _saved_fleet_hulls
	RoguelikeRun.active = _saved_active
	RoguelikeRun.money = _saved_money
	RoguelikeRun.hired_roster_ids = _saved_hired_ids
	RoguelikeRun.editor_return_scene = _saved_return_scene


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


func test_manage_crew_button_present_during_active_run() -> void:
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	var scene: Control = FleetEditorScene.instantiate()
	add_child_autofree(scene)
	var btn := _find_button(scene, "Manage Crew")
	assert_not_null(btn, "Manage Crew button exists in footer during active run")


func test_manage_crew_button_absent_without_active_run() -> void:
	RoguelikeRun.active = false
	RoguelikeRun.fleet_hulls = []
	var scene: Control = FleetEditorScene.instantiate()
	add_child_autofree(scene)
	var btn := _find_button(scene, "Manage Crew")
	assert_null(btn, "Manage Crew button not present when no active run")
