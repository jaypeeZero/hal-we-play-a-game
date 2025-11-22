extends Control

## Ship Editor UI - Visual tool for composing ships from sprite parts
## Uses shared HullShapeDrawer for consistent visuals with 78Renderer

@onready var ship_type_dropdown: OptionButton = $HBoxContainer/VBoxContainer/ShipTypeDropdown
@onready var ship_info_label: Label = $HBoxContainer/VBoxContainer/ShipInfoLabel
@onready var ship_canvas: Control = $HBoxContainer/VBoxContainer/ShipCanvas
@onready var properties_container: VBoxContainer = $HBoxContainer/PropertiesPanel/PropertiesScrollContainer/PropertiesContainer
@onready var properties_label: Label = $HBoxContainer/PropertiesPanel/PropertiesScrollContainer/PropertiesContainer/PropertiesLabel

# Path for saving custom ship configurations
const CUSTOM_SHIPS_PATH = "user://custom_ships/"

# Ship types available in the game
const SHIP_TYPES = ["fighter", "corvette", "capital"]

# Component colors - must match HullShapeDrawer for visual consistency
const COLOR_ARMOR = Color(0.3, 0.6, 1.0)       # Blue - armor sections
const COLOR_INTERNAL = Color(1.0, 0.5, 0.2)   # Orange - internal components
const COLOR_WEAPON = Color(1.0, 0.3, 0.3)     # Red - weapons
const COLOR_ENGINE = Color(0.3, 1.0, 0.5)     # Green - engines

# Current ship data and selected component
var current_ship_data: Dictionary = {}
var selected_component: Dictionary = {}
var selected_component_type: String = ""

# Drag state for components (engines and weapons)
var dragging_component: Dictionary = {}
var dragging_component_index: int = -1
var dragging_component_type: String = ""  # "engine" or "weapon"
var drag_visual: Control = null
var drag_tween: Tween = null
var scale_factor: float = 2.0  # Store for coordinate conversion

# Track selected component index for editing
var selected_component_index: int = -1

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

	# Draw weapons (with index for dragging)
	var weapons = ship_data.get("weapons", [])
	for i in range(weapons.size()):
		_draw_weapon_component(weapons[i], i, center, scale_factor)

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
	engine_container.gui_input.connect(_on_component_drag_input.bind(engine, engine_index, "engine", engine_container))

func _on_component_drag_input(event: InputEvent, component: Dictionary, component_index: int, component_type: String, container: Control) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# Start dragging
				dragging_component = component
				dragging_component_index = component_index
				dragging_component_type = component_type
				drag_visual = container
				selected_component = component
				selected_component_type = component_type
				selected_component_index = component_index
				_update_properties_display()
				print("Started dragging " + component_type + " " + str(component_index))
			else:
				# Stop dragging and finalize position
				if dragging_component_index == component_index and dragging_component_type == component_type:
					_finalize_component_position(container)
					dragging_component = {}
					dragging_component_index = -1
					dragging_component_type = ""
					drag_visual = null
					print("Stopped dragging " + component_type + " " + str(component_index))
	elif event is InputEventMouseMotion:
		if dragging_component_index == component_index and dragging_component_type == component_type and drag_visual:
			# Move component to mouse position with animation
			var target_pos = ship_canvas.get_local_mouse_position() - Vector2(8, 8)
			_animate_component_to_position(container, target_pos)

func _animate_component_to_position(container: Control, target_pos: Vector2) -> void:
	# Kill any existing tween
	if drag_tween and drag_tween.is_valid():
		drag_tween.kill()

	# Create smooth animation tween
	drag_tween = create_tween()
	drag_tween.set_trans(Tween.TRANS_EXPO)
	drag_tween.set_ease(Tween.EASE_OUT)
	drag_tween.tween_property(container, "position", target_pos, 0.1)

func _finalize_component_position(container: Control) -> void:
	if dragging_component_index < 0:
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

	# Update the component's position_offset in current_ship_data
	if dragging_component_type == "engine":
		var internals = current_ship_data.get("internals", [])
		if dragging_component_index < internals.size():
			internals[dragging_component_index]["position_offset"] = unscaled_offset
	elif dragging_component_type == "weapon":
		var weapons = current_ship_data.get("weapons", [])
		if dragging_component_index < weapons.size():
			weapons[dragging_component_index]["position_offset"] = unscaled_offset

	# Update the reference
	dragging_component["position_offset"] = unscaled_offset
	selected_component = dragging_component
	_update_properties_display()
	print(dragging_component_type.capitalize() + " " + str(dragging_component_index) + " moved to offset: " + str(unscaled_offset))

func _draw_weapon_component(weapon: Dictionary, weapon_index: int, center: Vector2, scale: float) -> void:
	# Draw weapon as a draggable red rectangle at offset position
	var offset = weapon.get("position_offset", Vector2.ZERO) * scale
	var rotated_offset = HullShapes.rotate_90(offset)
	var pos = center + rotated_offset
	var facing = weapon.get("facing", 0.0)

	# Create container for the weapon visual (will be animated during drag)
	var weapon_container = Control.new()
	weapon_container.name = "Weapon_" + str(weapon_index)
	weapon_container.position = pos - Vector2(8, 8)
	weapon_container.custom_minimum_size = Vector2(16, 16)
	weapon_container.mouse_filter = Control.MOUSE_FILTER_STOP
	ship_canvas.add_child(weapon_container)

	# Draw the weapon rectangle
	var rect = Control.new()
	rect.position = Vector2(4, 0)
	rect.custom_minimum_size = Vector2(8, 16)
	rect.rotation = facing
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.draw.connect(func():
		rect.draw_rect(Rect2(0, 0, 8, 16), COLOR_WEAPON, false, 1.5)
		rect.draw_rect(Rect2(1, 1, 6, 14), COLOR_WEAPON.darkened(0.3), true)
	)
	weapon_container.add_child(rect)

	# Add label
	var label = Label.new()
	label.text = "W"
	label.add_theme_color_override("font_color", COLOR_WEAPON)
	label.position = Vector2(16, 0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weapon_container.add_child(label)

	# Connect mouse input for drag-and-drop
	weapon_container.gui_input.connect(_on_component_drag_input.bind(weapon, weapon_index, "weapon", weapon_container))

## Handle component click
func _on_component_clicked(component_data: Dictionary, component_type: String) -> void:
	selected_component = component_data
	selected_component_type = component_type
	_update_properties_display()
	print("Selected " + component_type + ": " + str(component_data))

## Update the properties panel with editable form elements
func _update_properties_display() -> void:
	# Clear existing form elements (except the label)
	for child in properties_container.get_children():
		if child != properties_label:
			child.queue_free()

	if selected_component.is_empty():
		properties_label.text = "Click on a component to view its properties"
		return

	properties_label.text = "=== " + selected_component_type.to_upper() + " ==="

	# Create editable form fields for each property
	_create_property_fields(selected_component, "", 0)

## Create editable form fields for component properties
func _create_property_fields(data: Dictionary, path_prefix: String, indent_level: int) -> void:
	for key in data.keys():
		var value = data[key]
		var full_path = path_prefix + key if path_prefix.is_empty() else path_prefix + "." + key

		if value is Dictionary:
			# Create a section header for nested dictionaries
			var header = Label.new()
			header.text = "  ".repeat(indent_level) + str(key) + ":"
			header.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			properties_container.add_child(header)
			_create_property_fields(value, full_path, indent_level + 1)
		elif value is Array:
			# Skip arrays for now (complex to edit)
			var header = Label.new()
			header.text = "  ".repeat(indent_level) + str(key) + ": [array]"
			header.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
			properties_container.add_child(header)
		elif value is Vector2:
			# Create Vector2 editor with X and Y fields
			_create_vector2_field(key, value, full_path, indent_level)
		elif value is float or value is int:
			# Create number editor
			_create_number_field(key, value, full_path, indent_level)
		elif value is String:
			# Create text editor
			_create_text_field(key, value, full_path, indent_level)
		elif value is bool:
			# Create checkbox
			_create_bool_field(key, value, full_path, indent_level)
		else:
			# Display as read-only label for other types
			var label = Label.new()
			label.text = "  ".repeat(indent_level) + str(key) + ": " + str(value)
			label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
			properties_container.add_child(label)

func _create_vector2_field(key: String, value: Vector2, path: String, indent: int) -> void:
	var container = HBoxContainer.new()

	var label = Label.new()
	label.text = "  ".repeat(indent) + str(key) + ":"
	label.custom_minimum_size.x = 80
	container.add_child(label)

	var x_label = Label.new()
	x_label.text = "X:"
	container.add_child(x_label)

	var x_edit = SpinBox.new()
	x_edit.min_value = -1000
	x_edit.max_value = 1000
	x_edit.step = 0.5
	x_edit.value = value.x
	x_edit.custom_minimum_size.x = 60
	x_edit.value_changed.connect(_on_vector2_x_changed.bind(path))
	container.add_child(x_edit)

	var y_label = Label.new()
	y_label.text = "Y:"
	container.add_child(y_label)

	var y_edit = SpinBox.new()
	y_edit.min_value = -1000
	y_edit.max_value = 1000
	y_edit.step = 0.5
	y_edit.value = value.y
	y_edit.custom_minimum_size.x = 60
	y_edit.value_changed.connect(_on_vector2_y_changed.bind(path))
	container.add_child(y_edit)

	properties_container.add_child(container)

func _create_number_field(key: String, value: Variant, path: String, indent: int) -> void:
	var container = HBoxContainer.new()

	var label = Label.new()
	label.text = "  ".repeat(indent) + str(key) + ":"
	label.custom_minimum_size.x = 120
	container.add_child(label)

	var edit = SpinBox.new()
	edit.min_value = -10000
	edit.max_value = 10000
	edit.step = 1 if value is int else 0.1
	edit.value = value
	edit.custom_minimum_size.x = 80
	edit.value_changed.connect(_on_number_changed.bind(path))
	container.add_child(edit)

	properties_container.add_child(container)

func _create_text_field(key: String, value: String, path: String, indent: int) -> void:
	var container = HBoxContainer.new()

	var label = Label.new()
	label.text = "  ".repeat(indent) + str(key) + ":"
	label.custom_minimum_size.x = 120
	container.add_child(label)

	var edit = LineEdit.new()
	edit.text = value
	edit.custom_minimum_size.x = 120
	edit.text_changed.connect(_on_text_changed.bind(path))
	container.add_child(edit)

	properties_container.add_child(container)

func _create_bool_field(key: String, value: bool, path: String, indent: int) -> void:
	var container = HBoxContainer.new()

	var label = Label.new()
	label.text = "  ".repeat(indent) + str(key) + ":"
	label.custom_minimum_size.x = 120
	container.add_child(label)

	var check = CheckBox.new()
	check.button_pressed = value
	check.toggled.connect(_on_bool_changed.bind(path))
	container.add_child(check)

	properties_container.add_child(container)

## Property change handlers
func _on_vector2_x_changed(new_value: float, path: String) -> void:
	var current = _get_value_at_path(selected_component, path)
	if current is Vector2:
		var new_vec = Vector2(new_value, current.y)
		_set_value_at_path(selected_component, path, new_vec)
		_update_component_in_ship_data()
		_draw_ship(current_ship_data)

func _on_vector2_y_changed(new_value: float, path: String) -> void:
	var current = _get_value_at_path(selected_component, path)
	if current is Vector2:
		var new_vec = Vector2(current.x, new_value)
		_set_value_at_path(selected_component, path, new_vec)
		_update_component_in_ship_data()
		_draw_ship(current_ship_data)

func _on_number_changed(new_value: float, path: String) -> void:
	_set_value_at_path(selected_component, path, new_value)
	_update_component_in_ship_data()

func _on_text_changed(new_value: String, path: String) -> void:
	_set_value_at_path(selected_component, path, new_value)
	_update_component_in_ship_data()

func _on_bool_changed(new_value: bool, path: String) -> void:
	_set_value_at_path(selected_component, path, new_value)
	_update_component_in_ship_data()

## Get value at dot-separated path in dictionary
func _get_value_at_path(data: Dictionary, path: String) -> Variant:
	var keys = path.split(".")
	var current: Variant = data
	for key in keys:
		if current is Dictionary and current.has(key):
			current = current[key]
		else:
			return null
	return current

## Set value at dot-separated path in dictionary
func _set_value_at_path(data: Dictionary, path: String, value: Variant) -> void:
	var keys = path.split(".")
	var current: Variant = data
	for i in range(keys.size() - 1):
		var key = keys[i]
		if current is Dictionary and current.has(key):
			current = current[key]
		else:
			return
	if current is Dictionary:
		current[keys[keys.size() - 1]] = value

## Update the component in ship data after property changes
func _update_component_in_ship_data() -> void:
	if selected_component_type == "engine" and selected_component_index >= 0:
		var internals = current_ship_data.get("internals", [])
		if selected_component_index < internals.size():
			internals[selected_component_index] = selected_component
	elif selected_component_type == "weapon" and selected_component_index >= 0:
		var weapons = current_ship_data.get("weapons", [])
		if selected_component_index < weapons.size():
			weapons[selected_component_index] = selected_component
	elif selected_component_type == "armor":
		var armor_sections = current_ship_data.get("armor_sections", [])
		for i in range(armor_sections.size()):
			if armor_sections[i].get("section_id") == selected_component.get("section_id"):
				armor_sections[i] = selected_component
				break

## Save ship configuration to file
func _on_save_button_pressed() -> void:
	if current_ship_data.is_empty():
		print("No ship data to save")
		return

	_ensure_custom_ships_dir()

	var ship_type = current_ship_data.get("type", "unknown")
	var file_path = CUSTOM_SHIPS_PATH + ship_type + "_custom.json"

	# Convert ship data to JSON (need to handle Vector2 serialization)
	var save_data = _serialize_ship_data(current_ship_data)
	var json_string = JSON.stringify(save_data, "\t")

	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
		print("Ship configuration saved to: " + file_path)
	else:
		print("ERROR: Could not save ship configuration")

func _ensure_custom_ships_dir() -> void:
	if not DirAccess.dir_exists_absolute(CUSTOM_SHIPS_PATH):
		DirAccess.make_dir_recursive_absolute(CUSTOM_SHIPS_PATH)

## Serialize ship data for JSON (convert Vector2 to dict)
func _serialize_ship_data(data: Variant) -> Variant:
	if data is Dictionary:
		var result = {}
		for key in data.keys():
			result[key] = _serialize_ship_data(data[key])
		return result
	elif data is Array:
		var result = []
		for item in data:
			result.append(_serialize_ship_data(item))
		return result
	elif data is Vector2:
		return {"_type": "Vector2", "x": data.x, "y": data.y}
	else:
		return data
