extends Control


func _on_new_game_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/space_battle.tscn")


func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/settings_menu.tscn")


func _on_ship_editor_pressed() -> void:
	get_tree().change_scene_to_file("res://tools/ship_editor.tscn")


func _on_customize_satchel_pressed() -> void:
	_open_loadout_editor(false)


func _on_customize_opponent_satchel_pressed() -> void:
	_open_loadout_editor(true)


func _open_loadout_editor(is_opponent: bool) -> void:
	var scene = load("res://tools/loadout_editor.tscn")
	var instance = scene.instantiate()
	instance.set_opponent_mode(is_opponent)
	get_tree().root.add_child(instance)
	queue_free()


func _on_quit_pressed() -> void:
	get_tree().quit()
