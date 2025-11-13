extends Control

const MedallionData = preload("res://scripts/core/data/medallion_data.gd")

@onready var rows_container: VBoxContainer = %RowsContainer
@onready var add_button: Button = %AddButton
@onready var save_button: Button = %SaveButton
@onready var back_button: Button = %BackButton

const LOADOUT_PATH = "res://player_loadout.json"

var medallion_data: MedallionData
var medallion_names: Array[String] = []

func _ready() -> void:
	medallion_data = MedallionData.new()
	_load_medallion_names()
	_load_loadout()

	add_button.pressed.connect(_on_add_pressed)
	save_button.pressed.connect(_on_save_pressed)
	back_button.pressed.connect(_on_back_pressed)

func _load_medallion_names() -> void:
	var all_medallions: Array = medallion_data.get_all_medallions()
	for m in all_medallions:
		if m.has("id"):
			medallion_names.append(m.id)
	medallion_names.sort()

func _load_loadout() -> void:
	if not FileAccess.file_exists(LOADOUT_PATH):
		return

	var file: FileAccess = FileAccess.open(LOADOUT_PATH, FileAccess.READ)
	if not file:
		push_error("Failed to open loadout file")
		return

	var json_string: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	var error: Error = json.parse(json_string)
	if error != OK:
		push_error("Failed to parse loadout JSON")
		return

	var data: Dictionary = json.data
	var medallions: Dictionary = data.get("medallions", {})

	for medallion_id: String in medallions.keys():
		var quantity: int = medallions[medallion_id]
		_add_row(medallion_id, quantity)

func _add_row(medallion_id: String = "", quantity: int = 0) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 40)

	# Dropdown for medallion selection
	var dropdown: OptionButton = OptionButton.new()
	dropdown.custom_minimum_size = Vector2(200, 0)
	dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	for name in medallion_names:
		dropdown.add_item(name)

	# Set the selected item if medallion_id is provided
	if medallion_id != "":
		var idx: int = medallion_names.find(medallion_id)
		if idx >= 0:
			dropdown.selected = idx

	row.add_child(dropdown)

	# Quantity spinbox
	var spinbox: SpinBox = SpinBox.new()
	spinbox.custom_minimum_size = Vector2(100, 0)
	spinbox.min_value = 0
	spinbox.max_value = 99
	spinbox.step = 1
	spinbox.value = quantity
	spinbox.allow_greater = false
	spinbox.allow_lesser = false
	row.add_child(spinbox)

	# Remove button
	var remove_button: Button = Button.new()
	remove_button.text = "-"
	remove_button.custom_minimum_size = Vector2(40, 0)
	remove_button.pressed.connect(func(): _on_remove_pressed(row))
	row.add_child(remove_button)

	rows_container.add_child(row)

func _on_add_pressed() -> void:
	_add_row()

func _on_remove_pressed(row: HBoxContainer) -> void:
	row.queue_free()

func _on_save_pressed() -> void:
	var medallions: Dictionary = {}

	for row in rows_container.get_children():
		if not row is HBoxContainer:
			continue

		var children: Array[Node] = row.get_children()
		if children.size() < 2:
			continue

		var dropdown: OptionButton = children[0] as OptionButton
		var spinbox: SpinBox = children[1] as SpinBox

		if dropdown and spinbox:
			var medallion_id: String = medallion_names[dropdown.selected]
			var quantity: int = int(spinbox.value)
			medallions[medallion_id] = quantity

	var data: Dictionary = {
		"loadout_name": "Player Default",
		"medallions": medallions
	}

	var file: FileAccess = FileAccess.open(LOADOUT_PATH, FileAccess.WRITE)
	if not file:
		push_error("Failed to save loadout file")
		return

	file.store_string(JSON.stringify(data, "\t"))
	file.close()

	print("Loadout saved successfully!")

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
