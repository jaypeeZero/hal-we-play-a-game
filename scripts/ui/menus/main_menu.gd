extends Control


func _on_new_game_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/space_battle.tscn")


func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/settings_menu.tscn")


func _on_ship_editor_pressed() -> void:
	get_tree().change_scene_to_file("res://tools/ship_editor.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()
