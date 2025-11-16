extends Control

## Ship Editor UI - Visual tool for composing ships from sprite parts

@onready var ship_type_dropdown: OptionButton = $VBoxContainer/ShipTypeDropdown
@onready var ship_info_label: Label = $VBoxContainer/ShipInfoLabel

# Ship types available in the game
const SHIP_TYPES = ["fighter", "corvette", "capital"]

func _ready() -> void:
	_setup_dropdown()
	ship_type_dropdown.item_selected.connect(_on_ship_type_selected)

	print("Ship Editor loaded")

func _setup_dropdown() -> void:
	ship_type_dropdown.clear()
	for ship_type in SHIP_TYPES:
		ship_type_dropdown.add_item(ship_type.capitalize())

func _on_ship_type_selected(index: int) -> void:
	var ship_type = SHIP_TYPES[index]
	print("\n=== Ship Type Selected: " + ship_type + " ===")

	# Load ship data from ShipData definitions
	var ship_data = _get_ship_data(ship_type)

	if ship_data:
		# Log the JSON data
		var json_string = JSON.stringify(ship_data, "\t")
		print("Ship Data JSON:")
		print(json_string)

		# Update info label
		ship_info_label.text = "Ship Type: " + ship_type.capitalize() + "\n"
		ship_info_label.text += "Armor Sections: " + str(ship_data.get("armor_sections", []).size()) + "\n"
		ship_info_label.text += "Internals: " + str(ship_data.get("internals", []).size()) + "\n"
		ship_info_label.text += "Weapons: " + str(ship_data.get("weapons", []).size())
	else:
		print("ERROR: Could not load ship data for " + ship_type)
		ship_info_label.text = "ERROR: Ship data not found"

func _get_ship_data(ship_type: String) -> Dictionary:
	# Get ship definition from ShipData
	var ship_def = {}

	match ship_type:
		"fighter":
			ship_def = ShipData.create_fighter_definition()
		"corvette":
			ship_def = ShipData.create_corvette_definition()
		"capital":
			ship_def = ShipData.create_capital_definition()

	# Create a full ship instance to get complete data
	if ship_def:
		var ship_instance = ShipData.create_ship(ship_type, 0, Vector2.ZERO, 0.0)
		return ship_instance

	return {}
