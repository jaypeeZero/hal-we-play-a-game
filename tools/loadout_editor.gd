extends Control

const DEFAULT_LOADOUT_PATH = "res://default_loadout.json"
const PLAYER_LOADOUT_PATH = "res://player_loadout.json"
const OPPONENT_LOADOUT_PATH = "res://opponent_loadout.json"

var editing_opponent: bool = false
var current_loadout: Dictionary = {}
var medallion_spinboxes: Dictionary = {}

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var loadout_name_edit: LineEdit = $VBoxContainer/LoadoutNameEdit
@onready var medallions_container: VBoxContainer = $VBoxContainer/ScrollContainer/MedallionsContainer


func _ready() -> void:
	# Defer to allow set_opponent_mode to be called first
	call_deferred("_initialize")


func _initialize() -> void:
	_load_loadout()
	_build_ui()


func set_opponent_mode(is_opponent: bool) -> void:
	editing_opponent = is_opponent


func _get_loadout_path() -> String:
	return OPPONENT_LOADOUT_PATH if editing_opponent else PLAYER_LOADOUT_PATH


func _load_loadout() -> void:
	var path = _get_loadout_path()

	if FileAccess.file_exists(path):
		var file = FileAccess.open(path, FileAccess.READ)
		if file:
			var json = JSON.new()
			var error = json.parse(file.get_as_text())
			file.close()
			if error == OK and json.get_data() is Dictionary:
				current_loadout = json.get_data()
				return

	# Fall back to default loadout
	if FileAccess.file_exists(DEFAULT_LOADOUT_PATH):
		var file = FileAccess.open(DEFAULT_LOADOUT_PATH, FileAccess.READ)
		if file:
			var json = JSON.new()
			var error = json.parse(file.get_as_text())
			file.close()
			if error == OK and json.get_data() is Dictionary:
				current_loadout = json.get_data().duplicate(true)
				current_loadout["loadout_name"] = "Opponent Default" if editing_opponent else "Player Default"
				return

	# Empty fallback
	current_loadout = {"loadout_name": "New Loadout", "medallions": {}}


func _build_ui() -> void:
	var label_text = "Opponent Satchel" if editing_opponent else "Player Satchel"
	title_label.text = label_text

	loadout_name_edit.text = current_loadout.get("loadout_name", "Unnamed")

	# Clear existing medallion UI
	for child in medallions_container.get_children():
		child.queue_free()
	medallion_spinboxes.clear()

	# Build medallion rows
	var medallions = current_loadout.get("medallions", {})
	for medallion_name in medallions.keys():
		_add_medallion_row(medallion_name, medallions[medallion_name])


func _add_medallion_row(medallion_name: String, count: int) -> void:
	var row = HBoxContainer.new()

	var label = Label.new()
	label.text = medallion_name.replace("_", " ").capitalize()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var spinbox = SpinBox.new()
	spinbox.min_value = 0
	spinbox.max_value = 99
	spinbox.value = count
	spinbox.custom_minimum_size.x = 80
	row.add_child(spinbox)

	medallions_container.add_child(row)
	medallion_spinboxes[medallion_name] = spinbox


func _on_save_button_pressed() -> void:
	# Update loadout from UI
	current_loadout["loadout_name"] = loadout_name_edit.text

	var medallions = {}
	for medallion_name in medallion_spinboxes.keys():
		medallions[medallion_name] = int(medallion_spinboxes[medallion_name].value)
	current_loadout["medallions"] = medallions

	# Write to file
	var path = _get_loadout_path()
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(current_loadout, "\t"))
		file.close()
		print("Loadout saved to: " + path)


func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
