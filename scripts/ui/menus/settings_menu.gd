extends Control

# Audio controls
@onready var master_slider: HSlider = %MasterSlider
@onready var master_value: Label = %MasterValue
@onready var music_slider: HSlider = %MusicSlider
@onready var music_value: Label = %MusicValue
@onready var sfx_slider: HSlider = %SfxSlider
@onready var sfx_value: Label = %SfxValue

# Display controls
@onready var fullscreen_toggle: CheckButton = %FullscreenToggle
@onready var resolution_dropdown: OptionButton = %ResolutionDropdown

# Gameplay controls
@onready var debug_mode_toggle: CheckButton = %DebugModeToggle

# Debug tool controls
@onready var pilot_direction_toggle: CheckButton = %PilotDirectionToggle
@onready var leader_numbers_toggle: CheckButton = %LeaderNumbersToggle

# Buttons
@onready var reset_button: Button = %ResetButton
@onready var back_button: Button = %BackButton

func _ready() -> void:
	_setup_ui()
	_load_current_settings()
	_connect_signals()

func _setup_ui() -> void:
	# Setup sliders
	master_slider.min_value = 0.0
	master_slider.max_value = 1.0
	master_slider.step = 0.01

	music_slider.min_value = 0.0
	music_slider.max_value = 1.0
	music_slider.step = 0.01

	sfx_slider.min_value = 0.0
	sfx_slider.max_value = 1.0
	sfx_slider.step = 0.01

	# Setup resolution dropdown
	resolution_dropdown.clear()
	for i: int in GameSettings.RESOLUTIONS.size():
		var res: Vector2i = GameSettings.RESOLUTIONS[i]
		resolution_dropdown.add_item("%dx%d" % [res.x, res.y], i)

func _load_current_settings() -> void:
	# Load audio settings
	master_slider.value = GameSettings.master_volume
	music_slider.value = GameSettings.music_volume
	sfx_slider.value = GameSettings.sfx_volume

	_update_volume_labels()

	# Load display settings
	fullscreen_toggle.button_pressed = GameSettings.fullscreen
	resolution_dropdown.selected = GameSettings.resolution_index

	# Disable resolution if fullscreen
	resolution_dropdown.disabled = GameSettings.fullscreen

	# Load gameplay settings
	debug_mode_toggle.button_pressed = GameSettings.debug_mode

	# Load debug tool settings
	pilot_direction_toggle.button_pressed = GameSettings.show_pilot_direction
	leader_numbers_toggle.button_pressed = GameSettings.show_leader_numbers

func _connect_signals() -> void:
	# Audio signals
	master_slider.value_changed.connect(_on_master_volume_changed)
	music_slider.value_changed.connect(_on_music_volume_changed)
	sfx_slider.value_changed.connect(_on_sfx_volume_changed)

	# Display signals
	fullscreen_toggle.toggled.connect(_on_fullscreen_toggled)
	resolution_dropdown.item_selected.connect(_on_resolution_selected)

	# Gameplay signals
	debug_mode_toggle.toggled.connect(_on_debug_mode_toggled)

	# Debug tool signals
	pilot_direction_toggle.toggled.connect(_on_pilot_direction_toggled)
	leader_numbers_toggle.toggled.connect(_on_leader_numbers_toggled)

	# Buttons
	reset_button.pressed.connect(_on_reset_pressed)
	back_button.pressed.connect(_on_back_pressed)

func _on_master_volume_changed(value: float) -> void:
	GameSettings.set_master_volume(value)
	_update_volume_labels()

func _on_music_volume_changed(value: float) -> void:
	GameSettings.set_music_volume(value)
	_update_volume_labels()

func _on_sfx_volume_changed(value: float) -> void:
	GameSettings.set_sfx_volume(value)
	_update_volume_labels()
	# Play test sound effect
	# AudioManager.play_sfx("ui_click") # When audio system exists

func _update_volume_labels() -> void:
	master_value.text = "%d%%" % int(GameSettings.master_volume * 100)
	music_value.text = "%d%%" % int(GameSettings.music_volume * 100)
	sfx_value.text = "%d%%" % int(GameSettings.sfx_volume * 100)

func _on_fullscreen_toggled(enabled: bool) -> void:
	GameSettings.set_fullscreen(enabled)
	resolution_dropdown.disabled = enabled

func _on_resolution_selected(index: int) -> void:
	GameSettings.set_resolution(index)

func _on_debug_mode_toggled(enabled: bool) -> void:
	GameSettings.set_debug_mode(enabled)

func _on_pilot_direction_toggled(enabled: bool) -> void:
	GameSettings.set_show_pilot_direction(enabled)

func _on_leader_numbers_toggled(enabled: bool) -> void:
	GameSettings.set_show_leader_numbers(enabled)

func _on_reset_pressed() -> void:
	GameSettings.reset_to_defaults()
	_load_current_settings()

func _on_back_pressed() -> void:
	# Save settings before leaving
	GameSettings.save_settings()
	# Return to main menu
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
