extends CanvasLayer
class_name PauseMenu

# Reference to the Control child that contains the actual UI
@onready var _menu_container: Control = $Control

func _ready() -> void:
	_menu_container.hide()
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED

func _input(event: InputEvent) -> void:
	# ESC always toggles pause
	if event.is_action_pressed("ui_cancel"):
		toggle_pause()
		get_viewport().set_input_as_handled()
		return

	# Spacebar toggles pause - use paused state directly, not visibility
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		toggle_pause()
		get_viewport().set_input_as_handled()

func toggle_pause() -> void:
	# Use the actual paused state, not visibility
	if get_tree().paused:
		resume()
	else:
		pause()

func pause() -> void:
	get_tree().paused = true
	_menu_container.show()

func resume() -> void:
	get_tree().paused = false
	_menu_container.hide()

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
