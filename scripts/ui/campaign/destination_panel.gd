class_name DestinationPanel
extends PanelContainer

## Right-anchored side panel for the 3D star map. Shows details about
## a selected campaign node and provides a Launch button to jump to it.
## Added under a CanvasLayer by the map scene.

signal launch_requested(node_id: String)
signal closed

const PANEL_WIDTH := 320
const SCREEN_MARGIN := 20

const TYPE_LABELS := {
	"battle": "Battle",
	"shop":   "Shop",
	"randr":  "R&R",
}

var _launch_button: Button
var _content_box: VBoxContainer
var _current_node_id: String


func _ready() -> void:
	custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	add_theme_stylebox_override("panel", UiKit.panel_box(UiKit.PANEL, UiKit.LINE))
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	offset_right = -SCREEN_MARGIN
	offset_left = offset_right - PANEL_WIDTH
	visible = false


## Rebuild content for the given node dict and show the panel.
func show_node(node: Dictionary, is_current_position: bool) -> void:
	_current_node_id = str(node.get("id", ""))

	# Clear previous content
	for child in get_children():
		child.queue_free()

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	add_child(outer)

	# Title
	outer.add_child(UiKit.section_title(str(node.get("name", ""))))

	# Type badge
	var node_type: String = node.get("type", "")
	var type_label: String = TYPE_LABELS.get(node_type, node_type.capitalize())
	var badge_color: Color
	match node_type:
		"battle": badge_color = UiKit.BAD
		"shop":   badge_color = UiKit.ACCENT
		_:         badge_color = UiKit.GOOD
	outer.add_child(UiKit.badge(type_label, badge_color))

	# Jump cost
	var gap: int = node.get("star_date_gap", 0)
	outer.add_child(UiKit.label("Jump: +%d star dates" % gap, UiKit.DIM))

	# Status line
	var status_text: String
	var status_color: Color
	if is_current_position:
		status_text = "Current location"
		status_color = UiKit.INK
	elif node.get("visited", false):
		status_text = "Visited"
		status_color = UiKit.DIM
	elif node.get("accessible", false):
		status_text = "In jump range"
		status_color = UiKit.GOOD
	else:
		status_text = "Out of jump range"
		status_color = UiKit.DIM
	outer.add_child(UiKit.label(status_text, status_color))

	# Type-specific details
	match node_type:
		"battle":
			var scout_card := UiKit.card(UiKit.PANEL_2, UiKit.LINE)
			var card_box := VBoxContainer.new()
			card_box.add_theme_constant_override("separation", 4)
			scout_card.add_child(card_box)
			card_box.add_child(UiKit.section_title("Scout Report"))
			var enemy_fleet: Dictionary = node.get("enemy_fleet", {})
			for line in ScoutReportSystem.report_lines(enemy_fleet):
				card_box.add_child(UiKit.label(line, UiKit.DIM))
			outer.add_child(scout_card)
		"shop":
			outer.add_child(UiKit.label("Trading post — hulls for sale, crew for hire.", UiKit.DIM))
		"randr":
			outer.add_child(UiKit.label("Rest stop — extended shore leave and repairs.", UiKit.DIM))

	# Footer
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", 8)

	var close_btn := Button.new()
	close_btn.text = "Close"
	UiKit.style_button(close_btn, "ghost")
	close_btn.pressed.connect(_on_close)
	footer.add_child(close_btn)

	_launch_button = Button.new()
	_launch_button.text = "Launch"
	UiKit.style_button(_launch_button, "primary")
	_launch_button.disabled = not node.get("accessible", false)
	_launch_button.pressed.connect(_on_launch)
	footer.add_child(_launch_button)

	outer.add_child(footer)

	visible = true


## Hide the panel without emitting signals.
func dismiss() -> void:
	visible = false


func _on_close() -> void:
	visible = false
	closed.emit()


func _on_launch() -> void:
	visible = false
	launch_requested.emit(_current_node_id)
