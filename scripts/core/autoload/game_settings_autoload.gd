extends Node

## GameSettings Autoload - Manages game settings with persistence
## Access via GameSettings singleton

const SETTINGS_PATH = "user://settings.cfg"

# Display settings
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]

# Audio settings
var master_volume: float = 1.0
var music_volume: float = 0.7
var sfx_volume: float = 0.8

# Display settings
var fullscreen: bool = false
var resolution_index: int = 0

# Gameplay settings
var debug_mode: bool = false

# Debug tool settings
var show_pilot_direction: bool = false
var show_leader_numbers: bool = false

func _ready() -> void:
	load_settings()

# ============================================================================
# AUDIO SETTERS
# ============================================================================

func set_master_volume(value: float) -> void:
	master_volume = clamp(value, 0.0, 1.0)
	_apply_audio_settings()

func set_music_volume(value: float) -> void:
	music_volume = clamp(value, 0.0, 1.0)
	_apply_audio_settings()

func set_sfx_volume(value: float) -> void:
	sfx_volume = clamp(value, 0.0, 1.0)
	_apply_audio_settings()

func _apply_audio_settings() -> void:
	# Apply to audio buses when audio system is implemented
	pass

# ============================================================================
# DISPLAY SETTERS
# ============================================================================

func set_fullscreen(enabled: bool) -> void:
	fullscreen = enabled
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		_apply_resolution()

func set_resolution(index: int) -> void:
	resolution_index = clamp(index, 0, RESOLUTIONS.size() - 1)
	if not fullscreen:
		_apply_resolution()

func _apply_resolution() -> void:
	if resolution_index >= 0 and resolution_index < RESOLUTIONS.size():
		var res = RESOLUTIONS[resolution_index]
		DisplayServer.window_set_size(res)

# ============================================================================
# GAMEPLAY SETTERS
# ============================================================================

func set_debug_mode(enabled: bool) -> void:
	debug_mode = enabled

func set_show_pilot_direction(enabled: bool) -> void:
	show_pilot_direction = enabled

func set_show_leader_numbers(enabled: bool) -> void:
	show_leader_numbers = enabled

# ============================================================================
# PERSISTENCE
# ============================================================================

func save_settings() -> void:
	var config = ConfigFile.new()

	# Audio
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)

	# Display
	config.set_value("display", "fullscreen", fullscreen)
	config.set_value("display", "resolution_index", resolution_index)

	# Gameplay
	config.set_value("gameplay", "debug_mode", debug_mode)

	# Debug tools
	config.set_value("debug", "show_pilot_direction", show_pilot_direction)
	config.set_value("debug", "show_leader_numbers", show_leader_numbers)

	var err = config.save(SETTINGS_PATH)
	if err != OK:
		push_warning("Failed to save settings: %s" % error_string(err))

func load_settings() -> void:
	var config = ConfigFile.new()
	var err = config.load(SETTINGS_PATH)

	if err != OK:
		# No settings file yet, use defaults
		return

	# Audio
	master_volume = config.get_value("audio", "master_volume", master_volume)
	music_volume = config.get_value("audio", "music_volume", music_volume)
	sfx_volume = config.get_value("audio", "sfx_volume", sfx_volume)

	# Display
	fullscreen = config.get_value("display", "fullscreen", fullscreen)
	resolution_index = config.get_value("display", "resolution_index", resolution_index)

	# Gameplay
	debug_mode = config.get_value("gameplay", "debug_mode", debug_mode)

	# Debug tools
	show_pilot_direction = config.get_value("debug", "show_pilot_direction", show_pilot_direction)
	show_leader_numbers = config.get_value("debug", "show_leader_numbers", show_leader_numbers)

	# Apply loaded settings
	_apply_audio_settings()
	if fullscreen:
		set_fullscreen(true)
	else:
		_apply_resolution()
