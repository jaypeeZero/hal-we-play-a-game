class_name EntityOverlays2D
extends RefCounted

## Gameplay-information overlays drawn in the 2D world regardless of how
## hulls are rendered: wing formation circles, repair pulses, and debug
## visuals. parent_node must be a direct child of the entity so overlays
## can counter-rotate against the entity's rotation.

## Update wing circle visual based on wing color
static func update_wing_circle(parent_node: Node2D, wing_color: Color) -> void:
	var wing_circle = parent_node.get_node_or_null("WingCircle")

	# If no wing (transparent color), hide/remove circle
	if wing_color.a < 0.01:
		if wing_circle:
			wing_circle.visible = false
		return

	# Create wing circle if it doesn't exist
	if not wing_circle:
		wing_circle = Line2D.new()
		wing_circle.name = "WingCircle"
		wing_circle.width = 2.0
		wing_circle.closed = true

		# Create circle points
		var points = PackedVector2Array()
		var segments = 24
		for i in range(segments):
			var angle = (float(i) / segments) * TAU
			points.append(Vector2(cos(angle), sin(angle)) * 35.0)
		wing_circle.points = points

		# Add behind other visuals (z_index or add first)
		wing_circle.z_index = -1
		parent_node.add_child(wing_circle)

	# Update color and visibility
	wing_circle.default_color = wing_color
	wing_circle.visible = true

## Update pilot direction line debug visual
static func update_pilot_direction_line(parent_node: Node2D, direction: Vector2) -> void:
	const DEBUG_LINE_LENGTH: float = 60.0
	const DEBUG_LINE_COLOR: Color = Color(1.0, 1.0, 0.0, 0.8)  # Yellow
	const DEBUG_LINE_WIDTH: float = 2.0

	var direction_line = parent_node.get_node_or_null("DebugDirectionLine")

	# If no direction (zero vector), hide/remove line
	if direction.length_squared() < 0.001:
		if direction_line:
			direction_line.visible = false
		return

	# Create direction line if it doesn't exist
	if not direction_line:
		direction_line = Line2D.new()
		direction_line.name = "DebugDirectionLine"
		direction_line.width = DEBUG_LINE_WIDTH
		direction_line.default_color = DEBUG_LINE_COLOR
		direction_line.z_index = 10  # Draw above other elements
		parent_node.add_child(direction_line)

	# Update line points - line goes from ship center in the direction
	# Need to account for ship rotation since the line is a child of the ship
	var ship_rotation = parent_node.get_parent().rotation if parent_node.get_parent() else 0.0
	var local_direction = direction.rotated(-ship_rotation)

	direction_line.clear_points()
	direction_line.add_point(Vector2.ZERO)
	direction_line.add_point(local_direction * DEBUG_LINE_LENGTH)
	direction_line.visible = true

## Green "+" above ships an engineer just repaired
static func update_repair_indicator(parent_node: Node2D, repairing: bool) -> void:
	const REPAIR_LABEL_OFFSET: Vector2 = Vector2(0, -35)  # Above the ship
	const REPAIR_LABEL_COLOR: Color = Color(0.3, 1.0, 0.4, 0.95)  # Green
	const REPAIR_LABEL_FONT_SIZE: int = 18

	var repair_label = parent_node.get_node_or_null("RepairIndicator")

	if not repairing:
		if repair_label:
			repair_label.visible = false
		return

	if not repair_label:
		repair_label = Label.new()
		repair_label.name = "RepairIndicator"
		repair_label.text = "+"
		repair_label.add_theme_color_override("font_color", REPAIR_LABEL_COLOR)
		repair_label.add_theme_font_size_override("font_size", REPAIR_LABEL_FONT_SIZE)
		repair_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		repair_label.z_index = 10  # Draw above other elements
		parent_node.add_child(repair_label)

	# Counter-rotate to keep the indicator upright on a rotating ship
	var ship_rotation = parent_node.get_parent().rotation if parent_node.get_parent() else 0.0
	repair_label.rotation = -ship_rotation
	repair_label.position = REPAIR_LABEL_OFFSET.rotated(-ship_rotation)
	repair_label.visible = true

## Update leader number debug visual
static func update_leader_number(parent_node: Node2D, leader_number: int) -> void:
	const LABEL_OFFSET: Vector2 = Vector2(0, -50)  # Above the ship
	const LABEL_COLOR: Color = Color(1.0, 1.0, 1.0, 0.9)  # White
	const LABEL_FONT_SIZE: int = 16

	var leader_label = parent_node.get_node_or_null("DebugLeaderLabel")

	# If not a leader (0), hide label
	if leader_number <= 0:
		if leader_label:
			leader_label.visible = false
		return

	# Create label if it doesn't exist
	if not leader_label:
		leader_label = Label.new()
		leader_label.name = "DebugLeaderLabel"
		leader_label.add_theme_color_override("font_color", LABEL_COLOR)
		leader_label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
		leader_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		leader_label.z_index = 10  # Draw above other elements
		parent_node.add_child(leader_label)

	# Update label text and position
	# Counter-rotate to keep text upright (since it's a child of rotating ship)
	var ship_rotation = parent_node.get_parent().rotation if parent_node.get_parent() else 0.0
	leader_label.rotation = -ship_rotation
	leader_label.position = LABEL_OFFSET.rotated(-ship_rotation)
	leader_label.text = str(leader_number)
	leader_label.visible = true
