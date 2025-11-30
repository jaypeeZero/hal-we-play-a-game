extends Control
class_name FleetManagement

const MESSAGES := [
	{"from": "Admiral Chen", "title": "Fleet Status Report", "message": "All ships report combat ready. Awaiting your orders, Commander."},
	{"from": "Intel Division", "title": "Enemy Movement Detected", "message": "Long-range sensors have detected hostile fleet activity in Sector 7."},
	{"from": "Supply Command", "title": "Resupply Complete", "message": "Ammunition and fuel reserves have been replenished to full capacity."},
	{"from": "Science Officer", "title": "Anomaly Detected", "message": "Unusual energy signatures detected near the jump gate. Recommend caution."},
	{"from": "Flight Command", "title": "Pilot Reports", "message": "All fighter squadrons report green across the board. Ready for deployment."},
]

@onready var _messages_list: VBoxContainer = $MarginContainer/VBoxContainer/MessagesContainer/MessagesList


func _ready() -> void:
	_populate_messages()


func _populate_messages() -> void:
	# Clear existing messages
	for child in _messages_list.get_children():
		child.queue_free()

	# Add each message
	for msg in MESSAGES:
		var message_item = _create_message_item(msg)
		_messages_list.add_child(message_item)


func _create_message_item(msg: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.2, 1.0)
	style.border_color = Color(0.4, 0.4, 0.5, 1.0)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4

	panel.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 4)
	margin.add_child(container)

	# Header: From and Title
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	container.add_child(header)

	var from_label := Label.new()
	from_label.text = msg["from"]
	from_label.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	header.add_child(from_label)

	var title_label := Label.new()
	title_label.text = msg["title"]
	title_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	header.add_child(title_label)

	# Message body
	var body_label := Label.new()
	body_label.text = msg["message"]
	body_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	body_label.custom_minimum_size = Vector2(300, 0)
	container.add_child(body_label)

	return panel


func _on_fleet_launch_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/roguelite_map.tscn")
