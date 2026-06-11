extends Control

@onready var _continue_button: Button = $HBoxContainer/MenuSide/Container/ContinueButton


func _ready() -> void:
	_continue_button.visible = CampaignSaveManager.has_save()


func _on_new_game_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/pre_battle.tscn")


func _on_edit_fleets_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/fleet_editor.tscn")


func _on_roguelite_pressed() -> void:
	# Entering Roguelike mode starts the run, so crew and doctrine exist for
	# the Edit Fleet / Fleet Management screens before the first battle.
	RoguelikeRun.start_run(FleetDataManager.load_fleet(0))
	get_tree().change_scene_to_file("res://scenes/fleet_management.tscn")


func _on_continue_pressed() -> void:
	if RoguelikeRun.load_campaign_from_disk():
		get_tree().change_scene_to_file("res://scenes/campaign_map_3d.tscn")


func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/settings_menu.tscn")


func _on_ship_editor_pressed() -> void:
	get_tree().change_scene_to_file("res://tools/ship_editor.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()
