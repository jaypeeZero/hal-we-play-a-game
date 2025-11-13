extends PanelContainer
class_name MedallionCard


@onready var icon_label: Label = $MarginContainer/HBoxContainer/IconLabel
@onready var name_label: Label = %NameLabel
@onready var type_label: Label = %TypeLabel
@onready var stats_container: GridContainer = %StatsContainer
@onready var description_label: Label = %DescriptionLabel


func setup(medallion_data: Dictionary) -> void:
	icon_label.text = medallion_data.get("icon", "?")
	name_label.text = medallion_data.get("name", "Unknown")

	# Use category instead of type (old field name)
	var category: String = medallion_data.get("category", medallion_data.get("type", "Unknown"))
	type_label.text = category.to_upper()

	# Clear and rebuild stats
	for child: Node in stats_container.get_children():
		child.queue_free()

	# Only show Mana Cost (the spell casting stat)
	if "mana_cost" in medallion_data:
		_add_stat_label("Mana: %d" % medallion_data.mana_cost)

	# Show spawn count if applicable (now in properties sub-dict)
	var properties: Dictionary = medallion_data.get("properties", {})
	if "spawn_count" in properties:
		_add_stat_label("Spawns: %d" % properties.spawn_count)

	description_label.text = medallion_data.get("description", "")


func _add_stat_label(text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	stats_container.add_child(label)
