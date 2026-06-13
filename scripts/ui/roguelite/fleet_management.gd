extends Control
class_name FleetManagement

const MESSAGES := [
	{"from": "Admiral Chen", "title": "Fleet Status Report", "message": "All ships report combat ready. Awaiting your orders, Commander."},
	{"from": "Intel Division", "title": "Enemy Movement Detected", "message": "Long-range sensors have detected hostile fleet activity in Sector 7."},
	{"from": "Supply Command", "title": "Resupply Complete", "message": "Ammunition and fuel reserves have been replenished to full capacity."},
	{"from": "Science Officer", "title": "Anomaly Detected", "message": "Unusual energy signatures detected near the jump gate. Recommend caution."},
	{"from": "Flight Command", "title": "Pilot Reports", "message": "All fighter squadrons report green across the board. Ready for deployment."},
]

const MESSAGE_BODY_MIN_WIDTH := 300

@onready var _messages_list: VBoxContainer = $MarginContainer/VBoxContainer/MessagesContainer/MessagesList
@onready var _status_label: Label = $MarginContainer/VBoxContainer/StatusLabel
@onready var _manage_crew_btn: Button = $MarginContainer/VBoxContainer/ManageCrewButton


func _ready() -> void:
	_populate_messages()
	_status_label.text = ""
	_manage_crew_btn.visible = RoguelikeRun.has_fleet()


func _populate_messages() -> void:
	# Clear existing messages
	for child in _messages_list.get_children():
		child.queue_free()

	# Add each message
	for msg in MESSAGES:
		var message_item = _create_message_item(msg)
		_messages_list.add_child(message_item)


func _create_message_item(msg: Dictionary) -> PanelContainer:
	var panel := UiKit.card()

	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 4)
	panel.add_child(container)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	container.add_child(header)
	header.add_child(UiKit.label(msg["from"], UiKit.ACCENT, 13))
	header.add_child(UiKit.label(msg["title"], UiKit.INK, 13))

	var body := UiKit.label(msg["message"], UiKit.DIM, 12)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD
	body.custom_minimum_size = Vector2(MESSAGE_BODY_MIN_WIDTH, 0)
	container.add_child(body)

	return panel


func _on_fleet_launch_pressed() -> void:
	# The run already started on entering Roguelike mode; the roster and any
	# doctrine authored in Edit Fleet must survive, so do not restart it here.
	if RoguelikeRun.fleet_hulls.is_empty():
		_status_label.text = "Configure at least one ship before launch."
		_status_label.modulate = UiKit.BAD
		return

	get_tree().change_scene_to_file("res://scenes/campaign_map_3d.tscn")


func _on_edit_fleet_pressed() -> void:
	RoguelikeRun.editor_return_scene = "res://scenes/fleet_management.tscn"
	get_tree().change_scene_to_file("res://scenes/fleet_editor.tscn")


func _on_manage_crew_pressed() -> void:
	CrewManagementScreen.open(get_tree().current_scene)
