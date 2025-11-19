extends Control

## Ship Editor UI - Visual tool for composing ships from sprite parts

@onready var ship_type_dropdown: OptionButton = $HBoxContainer/VBoxContainer/ShipTypeDropdown
@onready var ship_info_label: Label = $HBoxContainer/VBoxContainer/ShipInfoLabel
@onready var ship_canvas: Control = $HBoxContainer/VBoxContainer/ShipCanvas
@onready var properties_label: Label = $HBoxContainer/PropertiesPanel/PropertiesScrollContainer/PropertiesLabel

# Ship types available in the game
const SHIP_TYPES = ["fighter", "corvette", "capital"]

# Component colors - color-coded by type
const COLOR_ARMOR = Color(0.3, 0.6, 1.0)       # Blue - armor sections
const COLOR_INTERNAL = Color(1.0, 0.5, 0.2)   # Orange - internal components
const COLOR_WEAPON = Color(1.0, 0.3, 0.3)     # Red - weapons
const COLOR_ENGINE = Color(0.3, 1.0, 0.5)     # Green - engines

# Current ship data and selected component
var current_ship_data: Dictionary = {}
var selected_component: Dictionary = {}
var selected_component_type: String = ""

# Drag state for engines
var dragging_engine: Dictionary = {}
var dragging_engine_index: int = -1
var drag_visual: Control = null
var drag_tween: Tween = null
var scale_factor: float = 2.0  # Store for coordinate conversion

func _ready() -> void:
	_setup_dropdown()
	ship_type_dropdown.item_selected.connect(_on_ship_type_selected)

	print("Ship Editor loaded")

func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

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
		# Store current ship data
		current_ship_data = ship_data

		# Clear selected component
		selected_component = {}
		selected_component_type = ""
		_update_properties_display()

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
	scale_factor = 2.0  # Scale up for visibility

	# Determine ship type from type field
	var ship_type = ship_data.get("type", "fighter")

	# Draw hull shape based on ship type (ARMOR ONLY)
	_draw_hull_shape(ship_type, ship_data, center, scale_factor)

	# Draw internal components (separate engines from others)
	var internals = ship_data.get("internals", [])
	for i in range(internals.size()):
		var internal = internals[i]
		if internal.get("type") == "engine":
			_draw_engine_component(internal, i, center, scale_factor)
		else:
			_draw_internal_component(internal, center, scale_factor)

	# Draw weapons
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

		# Find matching armor section data
		var armor_data = {}
		for armor_section in ship_data.get("armor_sections", []):
			if armor_section.get("section_id") == section_id:
				armor_data = armor_section
				break

		# Calculate centroid for positioning
		var centroid = _calculate_centroid(points)
		var scaled_centroid = centroid * scale
		var rotated_centroid = HullShapes.rotate_90(scaled_centroid)
		var centroid_pos = center + rotated_centroid

		# Create clickable button for armor section
		if not armor_data.is_empty():
			var button = Button.new()
			button.position = centroid_pos - Vector2(20, 20)
			button.custom_minimum_size = Vector2(40, 40)
			button.flat = true
			button.pressed.connect(_on_component_clicked.bind(armor_data, "armor"))
			ship_canvas.add_child(button)

		# Calculate transformed points for this section
		var transformed_points: PackedVector2Array = []
		for point in points:
			var scaled_point = point * scale
			var rotated_point = HullShapes.rotate_90(scaled_point)
			transformed_points.append(center + rotated_point)

		# Close the polygon by adding the first point again
		if points.size() > 0:
			var first_point = points[0] * scale
			var rotated_first = HullShapes.rotate_90(first_point)
			transformed_points.append(center + rotated_first)

		# Color shade based on section index
		var shade = section_index * 0.15
		var line_color = COLOR_ARMOR.lightened(shade)

		# Create Control node with draw callback for this section
		var hull_section = Control.new()
		hull_section.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hull_section.draw.connect(func():
			hull_section.draw_polyline(transformed_points, line_color, 1.5)
		)
		ship_canvas.add_child(hull_section)

		# Add section label
		var label = Label.new()
		label.text = section_id
		label.add_theme_color_override("font_color", COLOR_ARMOR.lightened(shade))
		label.position = centroid_pos - Vector2(15, 5)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	var rotated_offset = HullShapes.rotate_90(offset)
	var pos = center + rotated_offset

	# Create clickable button for internal component
	var button = Button.new()
	button.position = pos - Vector2(8, 8)
	button.custom_minimum_size = Vector2(16, 16)
	button.flat = true
	button.pressed.connect(_on_component_clicked.bind(internal, "internal"))
	ship_canvas.add_child(button)

	var circle = Control.new()
	circle.position = pos - Vector2(5, 5)
	circle.custom_minimum_size = Vector2(10, 10)
	circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ship_canvas.add_child(label)

func _draw_engine_component(engine: Dictionary, engine_index: int, center: Vector2, scale: float) -> void:
	# Draw engine as a draggable green circle
	var offset = engine.get("position_offset", Vector2.ZERO) * scale
	var rotated_offset = HullShapes.rotate_90(offset)
	var pos = center + rotated_offset

	# Create container for the engine visual (will be animated during drag)
	var engine_container = Control.new()
	engine_container.name = "Engine_" + str(engine_index)
	engine_container.position = pos - Vector2(8, 8)
	engine_container.custom_minimum_size = Vector2(16, 16)
	engine_container.mouse_filter = Control.MOUSE_FILTER_STOP
	ship_canvas.add_child(engine_container)

	# Draw the engine circle
	var circle = Control.new()
	circle.position = Vector2(3, 3)
	circle.custom_minimum_size = Vector2(10, 10)
	circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	circle.draw.connect(func():
		circle.draw_circle(Vector2(5, 5), 5, COLOR_ENGINE)
		circle.draw_arc(Vector2(5, 5), 5, 0, TAU, 12, COLOR_ENGINE.lightened(0.3), 1.5)
	)
	engine_container.add_child(circle)

	# Add label
	var label = Label.new()
	label.text = "E"
	label.add_theme_color_override("font_color", COLOR_ENGINE)
	label.position = Vector2(16, 0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	engine_container.add_child(label)

	# Connect mouse input for drag-and-drop
	engine_container.gui_input.connect(_on_engine_gui_input.bind(engine, engine_index, engine_container))

func _on_engine_gui_input(event: InputEvent, engine: Dictionary, engine_index: int, container: Control) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# Start dragging
				dragging_engine = engine
				dragging_engine_index = engine_index
				drag_visual = container
				selected_component = engine
				selected_component_type = "engine"
				_update_properties_display()
				print("Started dragging engine " + str(engine_index))
			else:
				# Stop dragging and finalize position
				if dragging_engine_index == engine_index:
					_finalize_engine_position(container)
					dragging_engine = {}
					dragging_engine_index = -1
					drag_visual = null
					print("Stopped dragging engine " + str(engine_index))
	elif event is InputEventMouseMotion:
		if dragging_engine_index == engine_index and drag_visual:
			# Move engine to mouse position with animation
			var target_pos = ship_canvas.get_local_mouse_position() - Vector2(8, 8)
			_animate_engine_to_position(container, target_pos)

func _animate_engine_to_position(container: Control, target_pos: Vector2) -> void:
	# Kill any existing tween
	if drag_tween and drag_tween.is_valid():
		drag_tween.kill()

	# Create smooth animation tween
	drag_tween = create_tween()
	drag_tween.set_trans(Tween.TRANS_EXPO)
	drag_tween.set_ease(Tween.EASE_OUT)
	drag_tween.tween_property(container, "position", target_pos, 0.1)

func _finalize_engine_position(container: Control) -> void:
	if dragging_engine_index < 0:
		return

	# Convert screen position back to ship data coordinates
	var center = ship_canvas.size / 2.0
	var screen_pos = container.position + Vector2(8, 8)  # Center of the container

	# Reverse the coordinate transformation
	var offset_from_center = screen_pos - center
	# Reverse rotate_90: original rotate_90(point) = Vector2(-point.y, point.x)
	# To reverse: Vector2(offset.y, -offset.x)
	var unrotated_offset = Vector2(offset_from_center.y, -offset_from_center.x)
	var unscaled_offset = unrotated_offset / scale_factor

	# Update the engine's position_offset in current_ship_data
	var internals = current_ship_data.get("internals", [])
	if dragging_engine_index < internals.size():
		internals[dragging_engine_index]["position_offset"] = unscaled_offset
		# Also update the reference
		dragging_engine["position_offset"] = unscaled_offset
		selected_component = dragging_engine
		_update_properties_display()
		print("Engine " + str(dragging_engine_index) + " moved to offset: " + str(unscaled_offset))

func _draw_weapon(weapon: Dictionary, center: Vector2, scale: float) -> void:
	# Draw weapon as a small rectangle at offset position with rotation
	var offset = weapon.get("position_offset", Vector2.ZERO) * scale
	var rotated_offset = HullShapes.rotate_90(offset)
	var pos = center + rotated_offset
	var facing = weapon.get("facing", 0.0)

	# Create clickable button for weapon
	var button = Button.new()
	button.position = pos - Vector2(8, 12)
	button.custom_minimum_size = Vector2(16, 24)
	button.flat = true
	button.pressed.connect(_on_component_clicked.bind(weapon, "weapon"))
	ship_canvas.add_child(button)

	var rect = Control.new()
	rect.position = pos - Vector2(4, 8)
	rect.custom_minimum_size = Vector2(8, 16)
	rect.rotation = facing
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ship_canvas.add_child(label)

## Handle component click
func _on_component_clicked(component_data: Dictionary, component_type: String) -> void:
	selected_component = component_data
	selected_component_type = component_type
	_update_properties_display()
	print("Selected " + component_type + ": " + str(component_data))

## Update the properties panel with selected component data
func _update_properties_display() -> void:
	if selected_component.is_empty():
		properties_label.text = "Click on a component to view its properties"
		return

	var props_text = "=== " + selected_component_type.to_upper() + " ===\n\n"

	# Display all properties recursively
	props_text += _format_properties(selected_component, 0)

	properties_label.text = props_text

## Recursively format properties for display
func _format_properties(data: Variant, indent_level: int) -> String:
	var result = ""
	var indent = "  ".repeat(indent_level)

	if data is Dictionary:
		for key in data.keys():
			var value = data[key]
			if value is Dictionary or value is Array:
				result += indent + str(key) + ":\n"
				result += _format_properties(value, indent_level + 1)
			else:
				result += indent + str(key) + ": " + str(value) + "\n"
	elif data is Array:
		for i in range(data.size()):
			var value = data[i]
			if value is Dictionary or value is Array:
				result += indent + "[" + str(i) + "]:\n"
				result += _format_properties(value, indent_level + 1)
			else:
				result += indent + "[" + str(i) + "]: " + str(value) + "\n"
	else:
		result += indent + str(data) + "\n"

	return result
