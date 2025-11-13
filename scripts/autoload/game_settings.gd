extends Node

# Settings values
var master_volume: float = 1.0  # 0.0 to 1.0
var music_volume: float = 0.7
var sfx_volume: float = 0.8
var fullscreen: bool = false
var resolution_index: int = 0  # Index into RESOLUTIONS array
var debug_mode: bool = false  # Debug mode toggle

# Available resolutions
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),   # 0: 720p
	Vector2i(1920, 1080),  # 1: 1080p
	Vector2i(2560, 1440),  # 2: 1440p
	Vector2i(3840, 2160),  # 3: 4K
]

# Settings file path
const SETTINGS_PATH: String = "user://settings.cfg"

# Audio bus indices
var master_bus_idx: int
var music_bus_idx: int
var sfx_bus_idx: int

func _ready() -> void:
	# Get audio bus indices
	master_bus_idx = AudioServer.get_bus_index("Master")
	music_bus_idx = AudioServer.get_bus_index("Music")
	sfx_bus_idx = AudioServer.get_bus_index("SFX")

	# Load settings or use defaults
	load_settings()
	apply_settings()

func load_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	var err: Error = config.load(SETTINGS_PATH)

	if err != OK:
		# First time running, use defaults
		return

	# Load values
	master_volume = config.get_value("audio", "master_volume", 1.0)
	music_volume = config.get_value("audio", "music_volume", 0.7)
	sfx_volume = config.get_value("audio", "sfx_volume", 0.8)
	fullscreen = config.get_value("display", "fullscreen", false)
	resolution_index = config.get_value("display", "resolution_index", 0)
	debug_mode = config.get_value("gameplay", "debug_mode", false)

func save_settings() -> void:
	var config: ConfigFile = ConfigFile.new()

	# Save audio settings
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)

	# Save display settings
	config.set_value("display", "fullscreen", fullscreen)
	config.set_value("display", "resolution_index", resolution_index)

	# Save gameplay settings
	config.set_value("gameplay", "debug_mode", debug_mode)

	# Write to disk
	config.save(SETTINGS_PATH)

func apply_settings() -> void:
	# Apply audio settings
	AudioServer.set_bus_volume_db(master_bus_idx, linear_to_db(master_volume))
	AudioServer.set_bus_volume_db(music_bus_idx, linear_to_db(music_volume))
	AudioServer.set_bus_volume_db(sfx_bus_idx, linear_to_db(sfx_volume))

	# Apply display settings
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var resolution: Vector2i = RESOLUTIONS[resolution_index]
		DisplayServer.window_set_size(resolution)

func set_master_volume(value: float) -> void:
	master_volume = clamp(value, 0.0, 1.0)
	AudioServer.set_bus_volume_db(master_bus_idx, linear_to_db(master_volume))

func set_music_volume(value: float) -> void:
	music_volume = clamp(value, 0.0, 1.0)
	AudioServer.set_bus_volume_db(music_bus_idx, linear_to_db(music_volume))

func set_sfx_volume(value: float) -> void:
	sfx_volume = clamp(value, 0.0, 1.0)
	AudioServer.set_bus_volume_db(sfx_bus_idx, linear_to_db(sfx_volume))

func set_fullscreen(enabled: bool) -> void:
	fullscreen = enabled
	if enabled:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func set_resolution(index: int) -> void:
	resolution_index = clamp(index, 0, RESOLUTIONS.size() - 1)
	if not fullscreen:
		var resolution: Vector2i = RESOLUTIONS[resolution_index]
		DisplayServer.window_set_size(resolution)

func set_debug_mode(enabled: bool) -> void:
	debug_mode = enabled
