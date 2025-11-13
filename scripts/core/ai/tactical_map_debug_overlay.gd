extends Node2D
class_name TacticalMapDebugOverlay

## Debug visualization for TacticalInfluenceMap
## Shows influence map cells as colored overlays
## Toggle with F3 key

@export var enabled: bool = false
@export var show_threat: bool = true
@export var show_opportunity: bool = true
@export var show_panic: bool = true
@export var show_ally_presence: bool = true
@export var show_interest: bool = true
@export var opacity: float = 0.4

# AI Debug visualization
@export var show_ai_debug: bool = true
@export var show_awareness_radius: bool = true
@export var show_target_lines: bool = true
@export var show_behavior_text: bool = true
@export var show_emotional_state: bool = true


func _ready() -> void:
	# Set to draw on top
	z_index = 100


func _process(_delta: float) -> void:
	# Handle input for toggling
	if Input.is_action_just_pressed("ui_cancel"):  # ESC key - using existing action
		# Don't toggle if in menu, etc - could add check here
		pass

	# Queue redraw every frame when enabled
	if enabled:
		queue_redraw()


func _input(event: InputEvent) -> void:
	# Toggle with F3
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			toggle()
			get_viewport().set_input_as_handled()


func _draw() -> void:
	if not enabled:
		return

	# Draw influence map cells
	if TacticalMap:
		for y in range(TacticalMap.grid_height):
			for x in range(TacticalMap.grid_width):
				var cell = TacticalMap.cells[y][x]
				var world_pos = TacticalMap.grid_to_world(Vector2i(x, y))

				# Calculate color based on influence values
				var color = _get_cell_color(cell)

				if color.a > 0.01:  # Only draw if visible
					draw_rect(
						Rect2(
							world_pos - Vector2(TacticalMap.CELL_SIZE / 2.0, TacticalMap.CELL_SIZE / 2.0),
							Vector2(TacticalMap.CELL_SIZE, TacticalMap.CELL_SIZE)
						),
						color,
						true  # filled
					)

	# Draw AI debug info for creatures
	if show_ai_debug:
		_draw_creature_ai_debug()


func _get_cell_color(cell: TacticalInfluenceMap.TacticalCell) -> Color:
	var color = Color(0, 0, 0, 0)

	# Red = threat
	if show_threat and cell.threat > 0:
		color.r += clamp(cell.threat * 0.5, 0.0, 1.0)

	# Green = opportunity
	if show_opportunity and cell.opportunity > 0:
		color.g += clamp(cell.opportunity * 0.5, 0.0, 1.0)

	# Blue = panic
	if show_panic and cell.panic > 0:
		color.b += clamp(cell.panic * 0.5, 0.0, 1.0)

	# Cyan = ally presence
	if show_ally_presence and cell.ally_presence > 0:
		var strength = clamp(cell.ally_presence * 0.3, 0.0, 1.0)
		color.g += strength
		color.b += strength

	# Yellow = interest
	if show_interest and cell.interest > 0:
		var strength = clamp(cell.interest * 0.4, 0.0, 1.0)
		color.r += strength
		color.g += strength

	# Apply opacity
	if color.r > 0 or color.g > 0 or color.b > 0:
		color.a = opacity

	return color


## Toggle visualization on/off
func toggle() -> void:
	enabled = not enabled
	if enabled:
		print("Tactical Map Debug: ON (F3 to toggle)")
		print("  Red = Threat | Green = Opportunity | Blue = Panic")
		print("  Cyan = Allies | Yellow = Interest")
		print("  White Circles = Awareness Radius | Yellow Lines = Target")
	else:
		print("Tactical Map Debug: OFF (F3 to toggle)")
	queue_redraw()

## Draw AI debug info for all creatures
func _draw_creature_ai_debug() -> void:
	if not is_inside_tree():
		return

	var creatures = get_tree().get_nodes_in_group("creatures")
	for creature in creatures:
		if not creature is CreatureObject:
			continue

		var creature_obj = creature as CreatureObject
		if not creature_obj.ai_controller:
			continue

		var debug_info = creature_obj.ai_controller.get_debug_info()
		if debug_info.is_empty():
			continue

		var pos = creature_obj.global_position

		# Draw awareness radius
		if show_awareness_radius and "awareness_radius" in debug_info:
			var radius = debug_info.awareness_radius
			draw_arc(pos, radius, 0, TAU, 32, Color.WHITE, 2.0)

		# Draw line to target
		if show_target_lines and "target" in debug_info and debug_info.target:
			var target = debug_info.target
			if is_instance_valid(target):
				draw_line(pos, target.global_position, Color.YELLOW, 2.0)
				# Draw arrow head
				var dir = (target.global_position - pos).normalized()
				var arrow_size = 10.0
				var arrow_angle = PI / 6  # 30 degrees
				var arrow_left = target.global_position - dir.rotated(arrow_angle) * arrow_size
				var arrow_right = target.global_position - dir.rotated(-arrow_angle) * arrow_size
				draw_line(target.global_position, arrow_left, Color.YELLOW, 2.0)
				draw_line(target.global_position, arrow_right, Color.YELLOW, 2.0)

		# Draw behavior text and emotional state
		if show_behavior_text or show_emotional_state:
			var text_lines: Array[String] = []

			if show_behavior_text and "behavior" in debug_info:
				text_lines.append("Behavior: %s" % debug_info.behavior)

			if show_emotional_state:
				if "confidence" in debug_info:
					text_lines.append("Confidence: %.2f" % debug_info.confidence)
				if "fear" in debug_info:
					text_lines.append("Fear: %.2f" % debug_info.fear)
				if "aggression" in debug_info:
					text_lines.append("Aggression: %.2f" % debug_info.aggression)

			if "visible_enemies" in debug_info:
				text_lines.append("Enemies: %d" % debug_info.visible_enemies)
			if "visible_allies" in debug_info:
				text_lines.append("Allies: %d" % debug_info.visible_allies)

			# Draw text above creature
			var text_offset = Vector2(0, -30)
			for i in range(text_lines.size()):
				var line = text_lines[i]
				var line_pos = pos + text_offset + Vector2(0, i * -15)
				# Draw text
				draw_string(ThemeDB.fallback_font, line_pos, line, HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color.WHITE)

