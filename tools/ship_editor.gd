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

	# Determine ship type from class_name
	var ship_type = ship_data.get("class_name", "fighter")

	# Draw hull shape based on ship type
	_draw_hull_shape(ship_type, ship_data, center, scale_factor)

	# Draw internal components
	for internal in ship_data.get("internals", []):
		_draw_internal_component(internal, center, scale_factor)

	# Draw weapons
	for weapon in ship_data.get("weapons", []):
		_draw_weapon(weapon, center, scale_factor)

	print("Ship drawn: " + ship_type + " with " +
		str(ship_data.get("armor_sections", []).size()) + " armor sections, " +
		str(ship_data.get("internals", []).size()) + " internals, " +
		str(ship_data.get("weapons", []).size()) + " weapons")

func _draw_hull_shape(ship_type: String, ship_data: Dictionary, center: Vector2, scale: float) -> void:
	match ship_type:
		"fighter":
			_draw_fighter_hull(ship_data, center, scale)
		"corvette":
			_draw_corvette_hull(ship_data, center, scale)
		"capital":
			_draw_capital_hull(ship_data, center, scale)
		_:
			_draw_fighter_hull(ship_data, center, scale)

func _draw_fighter_hull(ship_data: Dictionary, center: Vector2, scale: float) -> void:
	# Fighter: elongated triangle shape
	var size = 15.0 * scale
	var length = size * 1.6  # Elongated
	var width = size * 0.8
	var nose_y = -length
	var tail_y = length * 0.3
	var mid_y = 0  # Split between front and back sections

	# FRONT section (pointy nose to middle)
	var front_line = Line2D.new()
	front_line.width = 1.5
	front_line.default_color = COLOR_ARMOR
	front_line.add_point(center + Vector2(0, nose_y))  # Nose
	front_line.add_point(center + Vector2(-width * 0.5, mid_y))  # Left mid
	front_line.add_point(center + Vector2(width * 0.5, mid_y))  # Right mid
	front_line.add_point(center + Vector2(0, nose_y))  # Back to nose
	ship_canvas.add_child(front_line)

	# Front label
	var front_label = Label.new()
	front_label.text = "front"
	front_label.add_theme_color_override("font_color", COLOR_ARMOR)
	front_label.position = center + Vector2(-15, nose_y * 0.5)
	ship_canvas.add_child(front_label)

	# BACK section (middle to tail)
	var back_line = Line2D.new()
	back_line.width = 1.5
	back_line.default_color = COLOR_ARMOR.lightened(0.3)
	back_line.add_point(center + Vector2(-width * 0.5, mid_y))  # Left mid
	back_line.add_point(center + Vector2(-width * 0.4, tail_y))  # Left tail
	back_line.add_point(center + Vector2(width * 0.4, tail_y))  # Right tail
	back_line.add_point(center + Vector2(width * 0.5, mid_y))  # Right mid
	back_line.add_point(center + Vector2(-width * 0.5, mid_y))  # Back to left mid
	ship_canvas.add_child(back_line)

	# Back label
	var back_label = Label.new()
	back_label.text = "back"
	back_label.add_theme_color_override("font_color", COLOR_ARMOR.lightened(0.3))
	back_label.position = center + Vector2(-15, mid_y + 10)
	ship_canvas.add_child(back_label)

func _draw_corvette_hull(ship_data: Dictionary, center: Vector2, scale: float) -> void:
	# Corvette: hammerhead front, thin body, thick rear
	var size = 25.0 * scale
	var body_width = size * 0.4
	var hammer_width = size * 0.9
	var rear_width = size * 0.7
	var front_y = -size * 1.2
	var front_mid_y = -size * 0.4
	var rear_mid_y = size * 0.4
	var rear_y = size * 1.2

	# FRONT section - Hammerhead
	var front_line = Line2D.new()
	front_line.width = 1.5
	front_line.default_color = COLOR_ARMOR
	front_line.add_point(center + Vector2(-hammer_width * 0.5, front_y))
	front_line.add_point(center + Vector2(hammer_width * 0.5, front_y))
	front_line.add_point(center + Vector2(body_width * 0.5, front_mid_y))
	front_line.add_point(center + Vector2(-body_width * 0.5, front_mid_y))
	front_line.add_point(center + Vector2(-hammer_width * 0.5, front_y))
	ship_canvas.add_child(front_line)

	var front_label = Label.new()
	front_label.text = "front"
	front_label.add_theme_color_override("font_color", COLOR_ARMOR)
	front_label.position = center + Vector2(-20, front_y + 5)
	ship_canvas.add_child(front_label)

	# MIDDLE section - Thin body
	var mid_line = Line2D.new()
	mid_line.width = 1.5
	mid_line.default_color = COLOR_ARMOR.lightened(0.2)
	mid_line.add_point(center + Vector2(-body_width * 0.5, front_mid_y))
	mid_line.add_point(center + Vector2(body_width * 0.5, front_mid_y))
	mid_line.add_point(center + Vector2(body_width * 0.5, rear_mid_y))
	mid_line.add_point(center + Vector2(-body_width * 0.5, rear_mid_y))
	mid_line.add_point(center + Vector2(-body_width * 0.5, front_mid_y))
	ship_canvas.add_child(mid_line)

	var mid_label = Label.new()
	mid_label.text = "middle"
	mid_label.add_theme_color_override("font_color", COLOR_ARMOR.lightened(0.2))
	mid_label.position = center + Vector2(body_width * 0.5 + 5, 0)
	ship_canvas.add_child(mid_label)

	# BACK section - Thick rear
	var back_line = Line2D.new()
	back_line.width = 1.5
	back_line.default_color = COLOR_ARMOR.lightened(0.4)
	back_line.add_point(center + Vector2(-body_width * 0.5, rear_mid_y))
	back_line.add_point(center + Vector2(-rear_width * 0.5, rear_mid_y + (rear_y - rear_mid_y) * 0.3))
	back_line.add_point(center + Vector2(-rear_width * 0.4, rear_y * 0.85))
	back_line.add_point(center + Vector2(0, rear_y))
	back_line.add_point(center + Vector2(rear_width * 0.4, rear_y * 0.85))
	back_line.add_point(center + Vector2(rear_width * 0.5, rear_mid_y + (rear_y - rear_mid_y) * 0.3))
	back_line.add_point(center + Vector2(body_width * 0.5, rear_mid_y))
	back_line.add_point(center + Vector2(-body_width * 0.5, rear_mid_y))
	ship_canvas.add_child(back_line)

	var back_label = Label.new()
	back_label.text = "back"
	back_label.add_theme_color_override("font_color", COLOR_ARMOR.lightened(0.4))
	back_label.position = center + Vector2(-20, rear_y - 10)
	ship_canvas.add_child(back_label)

func _draw_capital_hull(ship_data: Dictionary, center: Vector2, scale: float) -> void:
	# Capital: Star Destroyer triangle - narrow nose to wide back
	var size = 50.0 * scale
	var length = size * 3.6
	var max_width = size * 1.8
	var nose_y = -length
	var front_split_y = -length * 0.5
	var middle_split_y = 0
	var back_y = length * 0.2

	var width_at_front = max_width * 0.2
	var width_at_middle = max_width * 0.6
	var width_at_back = max_width

	# Draw overall triangle outline
	var outline = Line2D.new()
	outline.width = 1.5
	outline.default_color = COLOR_ARMOR
	outline.add_point(center + Vector2(0, nose_y))
	outline.add_point(center + Vector2(width_at_back * 0.5, back_y))
	outline.add_point(center + Vector2(-width_at_back * 0.5, back_y))
	outline.add_point(center + Vector2(0, nose_y))
	ship_canvas.add_child(outline)

	# Draw section dividers
	var div1 = Line2D.new()
	div1.width = 1.0
	div1.default_color = COLOR_ARMOR.lightened(0.3)
	div1.add_point(center + Vector2(-width_at_front * 0.5, front_split_y))
	div1.add_point(center + Vector2(width_at_front * 0.5, front_split_y))
	ship_canvas.add_child(div1)

	var div2 = Line2D.new()
	div2.width = 1.0
	div2.default_color = COLOR_ARMOR.lightened(0.3)
	div2.add_point(center + Vector2(-width_at_middle * 0.5, middle_split_y))
	div2.add_point(center + Vector2(width_at_middle * 0.5, middle_split_y))
	ship_canvas.add_child(div2)

	# Centerline
	var centerline = Line2D.new()
	centerline.width = 1.0
	centerline.default_color = COLOR_ARMOR.darkened(0.3)
	centerline.add_point(center + Vector2(0, nose_y))
	centerline.add_point(center + Vector2(0, back_y))
	ship_canvas.add_child(centerline)

	# Labels
	var labels_text = ["front_L", "front_R", "mid_L", "mid_R", "back_L", "back_R"]
	var labels_pos = [
		Vector2(-10, (nose_y + front_split_y) / 2),
		Vector2(10, (nose_y + front_split_y) / 2),
		Vector2(-20, (front_split_y + middle_split_y) / 2),
		Vector2(20, (front_split_y + middle_split_y) / 2),
		Vector2(-30, (middle_split_y + back_y) / 2),
		Vector2(30, (middle_split_y + back_y) / 2)
	]

	for i in range(labels_text.size()):
		var label = Label.new()
		label.text = labels_text[i]
		label.add_theme_color_override("font_color", COLOR_ARMOR)
		label.position = center + labels_pos[i]
		ship_canvas.add_child(label)

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
