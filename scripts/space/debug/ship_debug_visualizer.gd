class_name ShipDebugVisualizer
extends Node2D

## Visual debugging tool for ship systems
## Shows armor sections, internals, weapon arcs, and velocity vectors

var debug_enabled: bool = true
var show_armor: bool = true
var show_internals: bool = true
var show_weapons: bool = true
var show_velocity: bool = true
var show_target_lines: bool = true

var _game: SpaceBattleGame = null

# Debug colors
const COLOR_ARMOR_FULL = Color.GREEN
const COLOR_ARMOR_HALF = Color.YELLOW
const COLOR_ARMOR_EMPTY = Color.RED
const COLOR_INTERNAL_OK = Color.CYAN
const COLOR_INTERNAL_DAMAGED = Color.ORANGE
const COLOR_INTERNAL_DESTROYED = Color.RED
const COLOR_WEAPON_ARC = Color(0, 1, 0, 0.2)
const COLOR_WEAPON_RANGE = Color(0, 1, 0, 0.1)
const COLOR_VELOCITY = Color.BLUE
const COLOR_TARGET_LINE = Color(1, 1, 0, 0.5)

func _ready() -> void:
	z_index = 100  # Draw on top

	# Find SpaceBattleGame
	_game = get_parent() as SpaceBattleGame
	if not _game:
		push_warning("ShipDebugVisualizer: No SpaceBattleGame parent found")

func _process(_delta: float) -> void:
	if debug_enabled:
		queue_redraw()

func _draw() -> void:
	if not debug_enabled or not _game:
		return

	var ships = _game.get_ships()
	for ship in ships:
		var ship_data = ship.get_ship_data()
		_draw_ship_debug(ship_data)

## Draw all debug info for a ship
func _draw_ship_debug(ship_data: Dictionary) -> void:
	if ship_data.is_empty():
		return

	var pos = ship_data.position
	var rot = ship_data.rotation

	if show_armor:
		_draw_armor_sections(ship_data, pos, rot)

	if show_internals:
		_draw_internal_components(ship_data, pos, rot)

	if show_weapons:
		_draw_weapon_arcs(ship_data, pos, rot)

	if show_velocity:
		_draw_velocity_vector(ship_data, pos)

## Draw armor sections
func _draw_armor_sections(ship_data: Dictionary, pos: Vector2, rot: float) -> void:
	for section in ship_data.armor_sections:
		var health_percent = float(section.current_armor) / float(section.max_armor)

		# Choose color based on health
		var color = COLOR_ARMOR_FULL
		if health_percent < 0.5:
			color = COLOR_ARMOR_HALF
		if health_percent <= 0.0:
			color = COLOR_ARMOR_EMPTY

		# Draw arc
		var start_angle = deg_to_rad(section.arc.start) + rot
		var end_angle = deg_to_rad(section.arc.end) + rot

		# Normalize angles
		while end_angle < start_angle:
			end_angle += TAU

		# Draw arc outline
		draw_arc(pos, section.size, start_angle, end_angle, 32, color, 2.0)

		# Draw section label
		var mid_angle = (start_angle + end_angle) / 2.0
		var label_pos = pos + Vector2.from_angle(mid_angle) * (section.size + 10)
		var text = "%s: %d/%d" % [section.section_id, section.current_armor, section.max_armor]
		draw_string(ThemeDB.fallback_font, label_pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, 10, color)

## Draw internal components
func _draw_internal_components(ship_data: Dictionary, pos: Vector2, rot: float) -> void:
	for internal in ship_data.internals:
		var world_pos = pos + internal.position_offset.rotated(rot)

		# Choose color based on status
		var color = COLOR_INTERNAL_OK
		match internal.status:
			"damaged":
				color = COLOR_INTERNAL_DAMAGED
			"destroyed":
				color = COLOR_INTERNAL_DESTROYED

		# Draw circle
		draw_circle(world_pos, 5, color)

		# Draw label
		var text = "%s: %d/%d" % [internal.component_id, internal.current_health, internal.max_health]
		draw_string(ThemeDB.fallback_font, world_pos + Vector2(8, -8), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, color)

		# Draw line to ship center
		draw_line(pos, world_pos, Color(color, 0.3), 1.0)

## Draw weapon arcs and ranges
func _draw_weapon_arcs(ship_data: Dictionary, pos: Vector2, rot: float) -> void:
	for weapon in ship_data.weapons:
		var weapon_pos = pos + weapon.position_offset.rotated(rot)
		var weapon_angle = rot + weapon.facing

		# Draw weapon position
		draw_circle(weapon_pos, 3, Color.GREEN)

		# Draw firing arc
		var arc_min = deg_to_rad(weapon.arc.min) + weapon_angle
		var arc_max = deg_to_rad(weapon.arc.max) + weapon_angle

		# Draw arc lines
		var arc_start_point = weapon_pos + Vector2.from_angle(arc_min) * weapon.stats.range
		var arc_end_point = weapon_pos + Vector2.from_angle(arc_max) * weapon.stats.range

		draw_line(weapon_pos, arc_start_point, COLOR_WEAPON_ARC.lightened(0.3), 1.0)
		draw_line(weapon_pos, arc_end_point, COLOR_WEAPON_ARC.lightened(0.3), 1.0)

		# Draw arc
		draw_arc(weapon_pos, weapon.stats.range, arc_min, arc_max, 32, COLOR_WEAPON_ARC, 1.0)

		# Draw weapon label
		var label_pos = weapon_pos + Vector2(0, -15)
		var cooldown_text = ""
		if weapon.cooldown_remaining > 0:
			cooldown_text = " (%.1fs)" % weapon.cooldown_remaining

		var text = "%s%s" % [weapon.weapon_id, cooldown_text]
		draw_string(ThemeDB.fallback_font, label_pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color.GREEN)

## Draw velocity vector
func _draw_velocity_vector(ship_data: Dictionary, pos: Vector2) -> void:
	if ship_data.velocity.length() < 1.0:
		return

	var vel_end = pos + ship_data.velocity
	draw_line(pos, vel_end, COLOR_VELOCITY, 2.0)

	# Draw arrow head
	var arrow_size = 10.0
	var arrow_angle = ship_data.velocity.angle()
	var arrow_left = vel_end + Vector2.from_angle(arrow_angle + 2.5) * arrow_size
	var arrow_right = vel_end + Vector2.from_angle(arrow_angle - 2.5) * arrow_size

	draw_line(vel_end, arrow_left, COLOR_VELOCITY, 2.0)
	draw_line(vel_end, arrow_right, COLOR_VELOCITY, 2.0)

	# Draw speed label
	var speed = ship_data.velocity.length()
	var text = "%.0f" % speed
	draw_string(ThemeDB.fallback_font, vel_end + Vector2(5, -5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COLOR_VELOCITY)

## Toggle debug visualization
func toggle_debug() -> void:
	debug_enabled = not debug_enabled

## Toggle specific visualizations
func toggle_armor() -> void:
	show_armor = not show_armor

func toggle_internals() -> void:
	show_internals = not show_internals

func toggle_weapons() -> void:
	show_weapons = not show_weapons

func toggle_velocity() -> void:
	show_velocity = not show_velocity

func toggle_target_lines() -> void:
	show_target_lines = not show_target_lines
