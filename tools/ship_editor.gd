extends Control

## Ship Editor UI - Visual tool for composing ships from sprite parts

@onready var ship_type_dropdown: OptionButton = $VBoxContainer/ShipTypeDropdown
@onready var ship_info_label: Label = $VBoxContainer/ShipInfoLabel
@onready var ship_canvas: Control = $VBoxContainer/ShipCanvas

# Ship types available in the game
const SHIP_TYPES = ["fighter", "corvette", "capital"]

# Component colors - color-coded by type
const COLOR_ARMOR = Color(0.3, 0.6, 1.0)       # Blue - armor sections
const COLOR_INTERNAL = Color(1.0, 0.5, 0.2)   # Orange - internal components
const COLOR_WEAPON = Color(1.0, 0.3, 0.3)     # Red - weapons
const COLOR_ENGINE = Color(0.3, 1.0, 0.5)     # Green - engines

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

		# Draw the ship visually
		_draw_ship(ship_data)
	else:
		print("ERROR: Could not load ship data for " + ship_type)
		ship_info_label.text = "ERROR: Ship data not found"

func _get_ship_data(ship_type: String) -> Dictionary:
	# Create a full ship instance using ShipData API
	var ship_instance = ShipData.create_ship_instance(ship_type, 0, Vector2.ZERO, false)
	return ship_instance

func _draw_ship(ship_data: Dictionary) -> void:
	# Clear previous drawing
	for child in ship_canvas.get_children():
		child.queue_free()

	# Center point for drawing
	var center = ship_canvas.size / 2.0
	var scale_factor = 2.0  # Scale up for visibility

	# Determine ship type from type field
	var ship_type = ship_data.get("type", "fighter")

	# Draw hull shape based on ship type (ARMOR ONLY)
	_draw_hull_shape(ship_type, ship_data, center, scale_factor)

	# # Draw internal components
	for internal in ship_data.get("internals", []):
		_draw_internal_component(internal, center, scale_factor)

	# # Draw weapons
	for weapon in ship_data.get("weapons", []):
		_draw_weapon(weapon, center, scale_factor)

	print("Ship drawn (ARMOR ONLY): " + ship_type + " with " +
		str(ship_data.get("armor_sections", []).size()) + " armor sections")

func _draw_hull_shape(ship_type: String, ship_data: Dictionary, center: Vector2, scale: float) -> void:
	# Load hull sections from JSON data
	var sections = HullShapes.get_sections(ship_type)

	if sections.is_empty():
		print("WARNING: No hull shape data found for " + ship_type)
		return

	# Draw each section with different color shades
	var section_index = 0
	for section in sections:
		var section_id = section.section_id
		var points = section.points

		if points.is_empty():
			continue

		# Create Line2D for this section
		var line = Line2D.new()
		line.width = 1.5

		# Color shade based on section index
		var shade = section_index * 0.15
		line.default_color = COLOR_ARMOR.lightened(shade)

		# Add rotated and scaled points
		for point in points:
			var scaled_point = point * scale
			var rotated_point = HullShapes.rotate_90(scaled_point)
			line.add_point(center + rotated_point)

		ship_canvas.add_child(line)

		# Add section label
		var label = Label.new()
		label.text = section_id
		label.add_theme_color_override("font_color", COLOR_ARMOR.lightened(shade))

		# Position label at centroid of section
		var centroid = _calculate_centroid(points)
		var scaled_centroid = centroid * scale
		var rotated_centroid = HullShapes.rotate_90(scaled_centroid)
		label.position = center + rotated_centroid - Vector2(15, 5)
		ship_canvas.add_child(label)

		section_index += 1

## Calculate centroid of a polygon
func _calculate_centroid(points: Array) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO

	var sum = Vector2.ZERO
	for point in points:
		sum += point
	return sum / points.size()

func _draw_internal_component(internal: Dictionary, center: Vector2, scale: float) -> void:
	# Draw internal as a small circle at offset position
	var offset = internal.get("position_offset", Vector2.ZERO) * scale
	var pos = center + offset

	var circle = Control.new()
	circle.position = pos - Vector2(5, 5)
	circle.custom_minimum_size = Vector2(10, 10)
	circle.draw.connect(func():
		circle.draw_circle(Vector2(5, 5), 5, COLOR_INTERNAL)
		circle.draw_arc(Vector2(5, 5), 5, 0, TAU, 12, COLOR_INTERNAL.lightened(0.3), 1.5)
	)
	ship_canvas.add_child(circle)

	# Add label
	var label = Label.new()
	label.text = internal.get("type", "?")[0].to_upper()  # First letter of type
	label.add_theme_color_override("font_color", COLOR_INTERNAL)
	label.position = pos + Vector2(8, -8)
	ship_canvas.add_child(label)

func _draw_weapon(weapon: Dictionary, center: Vector2, scale: float) -> void:
	# Draw weapon as a small rectangle at offset position with rotation
	var offset = weapon.get("position_offset", Vector2.ZERO) * scale
	var pos = center + offset
	var facing = weapon.get("facing", 0.0)

	var rect = Control.new()
	rect.position = pos - Vector2(4, 8)
	rect.custom_minimum_size = Vector2(8, 16)
	rect.rotation = facing
	rect.draw.connect(func():
		rect.draw_rect(Rect2(0, 0, 8, 16), Color.TRANSPARENT, false, 1.5)
		rect.draw_rect(Rect2(1, 1, 6, 14), COLOR_WEAPON, false, 1.5)
	)
	ship_canvas.add_child(rect)

	# Add label
	var label = Label.new()
	label.text = "W"
	label.add_theme_color_override("font_color", COLOR_WEAPON)
	label.position = pos + Vector2(10, -8)
	ship_canvas.add_child(label)
