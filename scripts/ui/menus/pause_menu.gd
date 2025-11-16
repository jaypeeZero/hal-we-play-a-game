extends CanvasLayer
class_name PauseMenu

func _ready() -> void:
	hide()
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED

func _input(event: InputEvent) -> void:
	# Check for ESC or Spacebar to toggle pause
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_SPACE):
		toggle_pause()
		get_viewport().set_input_as_handled()

func toggle_pause() -> void:
	if visible:
		resume()
	else:
		pause()

func pause() -> void:
	get_tree().paused = true
	show()

func resume() -> void:
	get_tree().paused = false
	hide()

func _on_resume_pressed() -> void:
	resume()

func _on_restart_pressed() -> void:
	resume()  # Unpause first
	get_tree().reload_current_scene()

func _on_settings_pressed() -> void:
	# Don't unpause - stay paused while in settings
	get_tree().change_scene_to_file("res://scenes/settings_menu.tscn")

func _on_main_menu_pressed() -> void:
	resume()  # Unpause first
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
