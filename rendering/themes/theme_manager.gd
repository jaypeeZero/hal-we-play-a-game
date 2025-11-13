class_name ThemeManager extends Node

var active_theme: JsonTheme
var available_themes: Dictionary = {}  # theme_name -> JsonTheme

func _ready() -> void:
	_discover_themes()
	_load_default_theme()

func _discover_themes() -> void:
	# Scan themes/ directory for JSON files
	var theme_dir: String = "res://themes/"

	if not DirAccess.dir_exists_absolute(theme_dir):
		push_warning("Themes directory not found: %s" % theme_dir)
		return

	var dir: DirAccess = DirAccess.open(theme_dir)
	if not dir:
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()

	while file_name != "":
		if file_name.ends_with(".json"):
			var theme_path: String = theme_dir + file_name
			var theme: JsonTheme = JsonTheme.load_from_file(theme_path)

			if theme and theme.theme_name != "":
				available_themes[theme.theme_name] = theme
				print("Discovered theme: %s" % theme.theme_name)

		file_name = dir.get_next()

	dir.list_dir_end()

func _load_default_theme() -> void:
	# Try to load emoji theme first (always available)
	if "emoji_simple" in available_themes:
		set_active_theme("emoji_simple")
	elif available_themes.size() > 0:
		var first_theme: JsonTheme = available_themes.values()[0]
		set_active_theme(first_theme.theme_name)
	else:
		push_error("No themes available!")

func set_active_theme(theme_name: String) -> bool:
	if theme_name in available_themes:
		active_theme = available_themes[theme_name]
		print("Active theme set to: %s" % theme_name)
		return true

	push_error("Theme not found: %s" % theme_name)
	return false

func get_active_theme() -> JsonTheme:
	return active_theme

func get_available_theme_names() -> Array[String]:
	var names: Array[String] = []
	names.assign(available_themes.keys())
	return names
