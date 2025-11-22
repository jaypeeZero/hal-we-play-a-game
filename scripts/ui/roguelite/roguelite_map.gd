extends Control
class_name RogueliteMap

## Roguelite map system with auto-generated nodes
## Node types: battle, randr (R&R), shop

signal node_selected(node_data: Dictionary)
signal map_completed()

enum NodeType { BATTLE, RANDR, SHOP }

const NODE_TYPE_NAMES := {
	NodeType.BATTLE: "Battle",
	NodeType.RANDR: "R&R",
	NodeType.SHOP: "Shop"
}

const NODE_TYPE_COLORS := {
	NodeType.BATTLE: Color(0.9, 0.3, 0.3),  # Red
	NodeType.RANDR: Color(0.3, 0.9, 0.3),   # Green
	NodeType.SHOP: Color(0.3, 0.3, 0.9)     # Blue
}

const DISABLED_COLOR := Color(0.3, 0.3, 0.3, 0.5)
const VISITED_COLOR := Color(0.5, 0.5, 0.5, 0.8)

# Map generation settings
const MIN_ROWS := 5
const MAX_ROWS := 8
const MIN_NODES_PER_ROW := 2
const MAX_NODES_PER_ROW := 4

# Map data
var _map_nodes: Array = []  # Array of rows, each row is Array of node dictionaries
var _current_row: int = -1
var _node_buttons: Dictionary = {}  # node_id -> Button
var _connections: Array = []  # Array of {from_id, to_id}

# UI references
@onready var _map_container: VBoxContainer = $ScrollContainer/MapContainer
@onready var _title_label: Label = $TitleLabel
@onready var _info_label: Label = $InfoLabel


func _ready() -> void:
	_generate_map()
	_build_ui()
	_update_node_states()


func _generate_map() -> void:
	_map_nodes.clear()
	_connections.clear()

	var num_rows := randi_range(MIN_ROWS, MAX_ROWS)

	for row_idx in range(num_rows):
		var row := []
		var num_nodes: int

		# First and last rows have single nodes
		if row_idx == 0:
			num_nodes = 1
		elif row_idx == num_rows - 1:
			num_nodes = 1
		else:
			num_nodes = randi_range(MIN_NODES_PER_ROW, MAX_NODES_PER_ROW)

		for node_idx in range(num_nodes):
			var node_type := _generate_node_type(row_idx, num_rows)
			var node := {
				"id": "%d_%d" % [row_idx, node_idx],
				"row": row_idx,
				"col": node_idx,
				"type": node_type,
				"visited": false,
				"accessible": row_idx == 0  # Only first row accessible initially
			}
			row.append(node)

		_map_nodes.append(row)

	# Generate connections between rows
	_generate_connections()


func _generate_node_type(row_idx: int, total_rows: int) -> NodeType:
	# First node is always battle
	if row_idx == 0:
		return NodeType.BATTLE

	# Last node is always battle (boss)
	if row_idx == total_rows - 1:
		return NodeType.BATTLE

	# Weight distribution: 60% battle, 25% R&R, 15% shop
	var roll := randf()
	if roll < 0.60:
		return NodeType.BATTLE
	elif roll < 0.85:
		return NodeType.RANDR
	else:
		return NodeType.SHOP


func _generate_connections() -> void:
	for row_idx in range(_map_nodes.size() - 1):
		var current_row := _map_nodes[row_idx]
		var next_row := _map_nodes[row_idx + 1]

		# Each node in current row connects to at least one node in next row
		for node in current_row:
			var num_connections := randi_range(1, mini(2, next_row.size()))
			var connected_indices: Array = []

			# Prefer nearby nodes
			var col_center: float = float(node["col"]) / max(1, current_row.size() - 1) * (next_row.size() - 1)

			for _i in range(num_connections):
				var target_idx := _pick_connection_target(next_row.size(), col_center, connected_indices)
				if target_idx >= 0:
					connected_indices.append(target_idx)
					_connections.append({
						"from_id": node["id"],
						"to_id": next_row[target_idx]["id"]
					})

		# Ensure every node in next row has at least one incoming connection
		for next_node in next_row:
			var has_connection := false
			for conn in _connections:
				if conn["to_id"] == next_node["id"]:
					has_connection = true
					break

			if not has_connection:
				# Connect from a random node in current row
				var source_idx := randi() % current_row.size()
				_connections.append({
					"from_id": current_row[source_idx]["id"],
					"to_id": next_node["id"]
				})


func _pick_connection_target(row_size: int, col_center: float, excluded: Array) -> int:
	var candidates := []
	for i in range(row_size):
		if i not in excluded:
			candidates.append(i)

	if candidates.is_empty():
		return -1

	# Sort by distance to center and pick with bias toward closer nodes
	candidates.sort_custom(func(a, b): return abs(a - col_center) < abs(b - col_center))

	# 70% chance to pick closest, otherwise random
	if randf() < 0.7 or candidates.size() == 1:
		return candidates[0]
	else:
		return candidates[randi() % candidates.size()]


func _build_ui() -> void:
	# Clear existing children from map container
	for child in _map_container.get_children():
		child.queue_free()

	_node_buttons.clear()

	# Build rows from bottom to top (visually the map goes upward)
	for row_idx in range(_map_nodes.size() - 1, -1, -1):
		var row := _map_nodes[row_idx]

		var row_container := HBoxContainer.new()
		row_container.alignment = BoxContainer.ALIGNMENT_CENTER
		row_container.add_theme_constant_override("separation", 40)
		_map_container.add_child(row_container)

		for node in row:
			var btn := _create_node_button(node)
			row_container.add_child(btn)
			_node_buttons[node["id"]] = btn

		# Add spacer between rows except for the last
		if row_idx > 0:
			var spacer := Control.new()
			spacer.custom_minimum_size = Vector2(0, 20)
			_map_container.add_child(spacer)


func _create_node_button(node: Dictionary) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(100, 60)
	btn.text = NODE_TYPE_NAMES[node["type"]]

	# Store node ID in metadata
	btn.set_meta("node_id", node["id"])

	btn.pressed.connect(_on_node_pressed.bind(node["id"]))

	return btn


func _update_node_states() -> void:
	for row in _map_nodes:
		for node in row:
			var btn: Button = _node_buttons.get(node["id"])
			if btn == null:
				continue

			if node["visited"]:
				btn.disabled = true
				btn.modulate = VISITED_COLOR
			elif node["accessible"]:
				btn.disabled = false
				btn.modulate = NODE_TYPE_COLORS[node["type"]]
			else:
				btn.disabled = true
				btn.modulate = DISABLED_COLOR

	# Update info label
	if _current_row == -1:
		_info_label.text = "Select a node to begin your journey"
	else:
		_info_label.text = "Row %d / %d - Select your next destination" % [_current_row + 1, _map_nodes.size()]


func _on_node_pressed(node_id: String) -> void:
	var node := _get_node_by_id(node_id)
	if node == null:
		return

	# Mark node as visited
	node["visited"] = true
	_current_row = node["row"]

	# Cut off unreachable nodes and update accessibility
	_update_accessibility_after_selection(node_id)

	# Emit signal
	node_selected.emit(node)

	# Check if we reached the end
	if _current_row == _map_nodes.size() - 1:
		_info_label.text = "Journey Complete! Returning to main menu..."
		# Delay before returning to menu
		await get_tree().create_timer(2.0).timeout
		map_completed.emit()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return

	_update_node_states()


func _update_accessibility_after_selection(selected_id: String) -> void:
	# Mark all nodes as inaccessible first
	for row in _map_nodes:
		for node in row:
			node["accessible"] = false

	# Find nodes reachable from the selected node
	var reachable_in_next_row: Array = []
	for conn in _connections:
		if conn["from_id"] == selected_id:
			reachable_in_next_row.append(conn["to_id"])

	# Mark reachable nodes as accessible
	for node_id in reachable_in_next_row:
		var node := _get_node_by_id(node_id)
		if node != null:
			node["accessible"] = true


func _get_node_by_id(node_id: String) -> Dictionary:
	for row in _map_nodes:
		for node in row:
			if node["id"] == node_id:
				return node
	return {}


func _draw() -> void:
	# Draw connections between nodes
	for conn in _connections:
		var from_btn: Button = _node_buttons.get(conn["from_id"])
		var to_btn: Button = _node_buttons.get(conn["to_id"])

		if from_btn == null or to_btn == null:
			continue

		var from_node := _get_node_by_id(conn["from_id"])
		var to_node := _get_node_by_id(conn["to_id"])

		# Determine line color based on accessibility
		var line_color := Color(0.5, 0.5, 0.5, 0.3)  # Default dim

		if from_node.get("visited", false) and to_node.get("accessible", false):
			line_color = Color(1.0, 1.0, 1.0, 0.8)  # Bright for accessible paths
		elif from_node.get("visited", false) or to_node.get("visited", false):
			line_color = Color(0.6, 0.6, 0.6, 0.5)  # Medium for visited paths
		elif from_node.get("accessible", false):
			line_color = Color(0.8, 0.8, 0.8, 0.6)  # Lighter for currently accessible

		var from_pos := from_btn.global_position + from_btn.size / 2 - global_position
		var to_pos := to_btn.global_position + to_btn.size / 2 - global_position

		draw_line(from_pos, to_pos, line_color, 2.0)


func _process(_delta: float) -> void:
	# Request redraw for connection lines
	queue_redraw()
