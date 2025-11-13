extends Control


func _on_new_game_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/battlefield.tscn")


func _on_browse_medallions_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/medallion_browser.tscn")


func _on_customize_satchel_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/satchel_customizer.tscn")


func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/settings_menu.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()
