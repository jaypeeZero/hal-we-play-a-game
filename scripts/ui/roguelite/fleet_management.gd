extends Control
class_name FleetManagement

@onready var _status_label: Label = $MarginContainer/VBoxContainer/StatusLabel
@onready var _manage_crew_btn: Button = $MarginContainer/VBoxContainer/ManageCrewButton


func _ready() -> void:
	"""Initialise the Fleet Manager hub screen."""
	NavBar.attach(self, NavGraph.Screen.FLEET_MANAGER)
	_status_label.text = ""
	_manage_crew_btn.visible = RoguelikeRun.has_fleet()


func _on_fleet_launch_pressed() -> void:
	# The run already started on entering Roguelike mode; the roster and any
	# doctrine authored in Edit Fleet must survive, so do not restart it here.
	if RoguelikeRun.fleet_hulls.is_empty():
		_status_label.text = "Configure at least one ship before launch."
		_status_label.modulate = UiKit.BAD
		return

	get_tree().change_scene_to_file("res://scenes/campaign_map_3d.tscn")


func _on_edit_fleet_pressed() -> void:
	var screen := FleetCommandScreen.new()
	screen.setup(RunSource.new(), "done")
	screen.done.connect(func() -> void: screen.queue_free())
	get_tree().get_root().add_child(screen)


func _on_manage_crew_pressed() -> void:
	FleetCommandScreen.open_overlay(get_tree().current_scene)
