extends Control


@onready var medallion_list: VBoxContainer = %MedallionList
@onready var all_button: Button = %AllButton
@onready var spells_button: Button = %SpellsButton
@onready var creatures_button: Button = %CreaturesButton
@onready var terrain_button: Button = %TerrainButton

var current_filter: String = "all"
var medallion_card_scene: PackedScene = preload("res://scenes/medallion_card.tscn")


func _ready() -> void:
	_populate_list("all")


func _populate_list(filter: String) -> void:
	# Clear existing cards
	for child: Node in medallion_list.get_children():
		child.queue_free()

	# Get all medallion data from JSON
	var all_medallions: Array = _get_all_medallions()

	# Filter and display
	for medallion_data: Dictionary in all_medallions:
		var category: String = medallion_data.get("category", "")
		if filter == "all" or category == filter:
			var card: MedallionCard = medallion_card_scene.instantiate()
			medallion_list.add_child(card)
			card.setup(medallion_data)


func _get_all_medallions() -> Array:
	# Load all medallions from JSON - auto-populates!
	var medallion_data: MedallionData = MedallionData.new()
	return medallion_data.get_all_medallions()


func _on_all_button_toggled(_toggled_on: bool) -> void:
	if all_button.button_pressed:
		spells_button.set_pressed_no_signal(false)
		creatures_button.set_pressed_no_signal(false)
		terrain_button.set_pressed_no_signal(false)
		_populate_list("all")
		current_filter = "all"


func _on_spells_button_toggled(_toggled_on: bool) -> void:
	if spells_button.button_pressed:
		all_button.set_pressed_no_signal(false)
		_populate_list("spell")
		current_filter = "spell"
	elif not creatures_button.button_pressed and not terrain_button.button_pressed:
		all_button.set_pressed_no_signal(true)
		_populate_list("all")
		current_filter = "all"


func _on_creatures_button_toggled(_toggled_on: bool) -> void:
	if creatures_button.button_pressed:
		all_button.set_pressed_no_signal(false)
		_populate_list("creature")
		current_filter = "creature"
	elif not spells_button.button_pressed and not terrain_button.button_pressed:
		all_button.set_pressed_no_signal(true)
		_populate_list("all")
		current_filter = "all"


func _on_terrain_button_toggled(_toggled_on: bool) -> void:
	if terrain_button.button_pressed:
		all_button.set_pressed_no_signal(false)
		_populate_list("terrain")
		current_filter = "terrain"
	elif not spells_button.button_pressed and not creatures_button.button_pressed:
		all_button.set_pressed_no_signal(true)
		_populate_list("all")
		current_filter = "all"


func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
