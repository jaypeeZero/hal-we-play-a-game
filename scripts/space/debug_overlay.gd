class_name DebugOverlay
extends Node2D

## Toggleable debug overlay: draws ship focus lines, patrol areas, crew stats,
## and formation links. Each layer is independently gated by GameSettings so
## the user can enable only what they need. Toggle the panel with F1 in battle.
## Pure data consumer: reads SpaceBattleGame state, never mutates.

const TEAM_COLORS: Array = [
	Color(0.4, 0.7, 1.0, 0.6),  # team 0 — blue
	Color(1.0, 0.4, 0.4, 0.6),  # team 1 — red
]

const SQUADRON_COLORS: Array = [
	Color(0.3, 1.0, 0.4, 0.65),  # team 0 — green
	Color(1.0, 0.65, 0.2, 0.65), # team 1 — orange
]

# Six stats in column order. The plan locks this order (01_overview.md §3).
const STAT_NAMES: Array = [
	"aim", "piloting", "awareness", "tactics", "composure", "aggression"
]

# Which stats each role actually reads (per 01_overview.md §3.4). Other
# stats render dimmed gray to distinguish "high but unused" from "high and
# used."
const ROLE_READ_STATS: Dictionary = {
	"pilot":      ["piloting", "awareness", "aim", "composure", "aggression", "tactics"],
	"gunner":     ["aim", "awareness", "composure"],
	"captain":    ["tactics", "awareness", "composure", "aggression"],
	"squadron_leader": ["tactics", "awareness", "composure", "aggression"],
	"fleet_commander": ["tactics", "awareness", "composure"],
}

const TABLE_FONT_SIZE: int = 10
const TABLE_LINE_HEIGHT: int = 12
const TABLE_COL_WIDTH: int = 28
const TABLE_ROLE_COL_WIDTH: int = 36
const TABLE_PADDING: int = 4
const TABLE_BG_COLOR: Color = Color(0.0, 0.0, 0.0, 0.55)
const TABLE_HEADER_COLOR: Color = Color(0.85, 0.85, 0.85, 1.0)
const TABLE_ROLE_COLOR: Color = Color(0.85, 0.85, 0.85, 1.0)

var _game: Node = null  # SpaceBattleGame; set by parent on add_child
var _font: Font = null


func _ready() -> void:
	_font = ThemeDB.fallback_font


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _game == null:
		return

	if GameSettings.show_wing_lines:
		_draw_wing_lines()
	if GameSettings.show_squadron_lines:
		_draw_squadron_lines()

	for ship in _game._ships:
		if ship.get("status", "") == "destroyed":
			continue
		var team: int = int(ship.get("team", 0))
		var color: Color = TEAM_COLORS[team] if team >= 0 and team < TEAM_COLORS.size() else TEAM_COLORS[0]
		if GameSettings.show_target_lines:
			_draw_enemy_focus(ship, color)
		if GameSettings.show_patrol_areas:
			_draw_area_focus(ship, color)
		if GameSettings.show_crew_stats:
			_draw_crew_table(ship)


func _draw_enemy_focus(ship: Dictionary, color: Color) -> void:
	var orders: Dictionary = ship.get("orders", {})
	var target_id: String = orders.get("target_id") if orders.get("target_id") != null else ""
	if target_id == "":
		return
	var target: Dictionary = _game._find_ship_by_id(target_id)
	if target.is_empty() or target.get("status", "") == "destroyed":
		return
	if target.get("team", -1) == ship.get("team", -2):
		return
	DottedDraw.draw_dotted_line(self, ship.position, target.position, color)


func _draw_area_focus(ship: Dictionary, color: Color) -> void:
	var area = ship.get("assigned_area")
	if not (area is Dictionary):
		return
	var center: Vector2 = area.get("center", Vector2.ZERO)
	var radius: float = float(area.get("radius", 0.0))
	if radius <= 0.0:
		return
	# Line ends on the circle's rim (not the center) so the line and circle
	# read as one connected shape. If the ship is inside the circle, just
	# draw the line all the way to the center.
	var to_center: Vector2 = center - ship.position
	var dist: float = to_center.length()
	var line_end: Vector2 = center
	if dist > radius:
		line_end = ship.position + to_center / dist * (dist - radius)
	DottedDraw.draw_dotted_line(self, ship.position, line_end, color)
	DottedDraw.draw_dotted_circle(self, center, radius, color)


## Draw dotted lines between each wing lead and its wingmen, using the wing's
## assigned color so they visually match the wing circles on the ships.
func _draw_wing_lines() -> void:
	for wing in _game._previous_wings:
		var lead_id: String = wing.get("lead_ship_id", "")
		var lead_ship: Dictionary = _game._find_ship_by_id(lead_id)
		if lead_ship.is_empty() or lead_ship.get("status", "") == "destroyed":
			continue
		var color: Color = wing.get("wing_color", Color(1.0, 1.0, 1.0, 0.5))
		color.a = 0.7
		for wingman in wing.get("wingmen", []):
			var wm_ship: Dictionary = _game._find_ship_by_id(wingman.get("ship_id", ""))
			if wm_ship.is_empty() or wm_ship.get("status", "") == "destroyed":
				continue
			DottedDraw.draw_dotted_line(self, lead_ship.position, wm_ship.position, color)


## Draw hub-and-spoke dotted lines from each squadron leader to its members.
## Uses crew command chain: non-leaders point to their leader via superior.
func _draw_squadron_lines() -> void:
	# squadrons: leader_crew_id -> {leader_pos, team, members: [Vector2]}
	var squadrons: Dictionary = {}

	for crew in _game._crew_list:
		if not crew.has("squadron_rank"):
			continue
		var ship_id: String = crew.get("assigned_to", "")
		if ship_id == "":
			continue
		var ship: Dictionary = _game._find_ship_by_id(ship_id)
		if ship.is_empty() or ship.get("status", "") == "destroyed":
			continue

		var root_id: String
		if crew.get("is_squadron_leader", false):
			root_id = crew.get("crew_id", "")
		else:
			root_id = crew.get("command_chain", {}).get("superior", "")
		if root_id == "":
			continue

		if not squadrons.has(root_id):
			squadrons[root_id] = {
				"leader_pos": Vector2.ZERO,
				"leader_found": false,
				"members": [],
				"team": ship.get("team", 0),
			}
		if crew.get("is_squadron_leader", false):
			squadrons[root_id]["leader_pos"] = ship.position
			squadrons[root_id]["leader_found"] = true
		else:
			squadrons[root_id]["members"].append(ship.position)

	for root_id in squadrons.keys():
		var entry: Dictionary = squadrons[root_id]
		if not entry.get("leader_found", false):
			continue
		var team: int = entry.get("team", 0)
		var color: Color = SQUADRON_COLORS[team] if team >= 0 and team < SQUADRON_COLORS.size() else SQUADRON_COLORS[0]
		var leader_pos: Vector2 = entry.get("leader_pos", Vector2.ZERO)
		for member_pos: Vector2 in entry.get("members", []):
			DottedDraw.draw_dotted_line(self, leader_pos, member_pos, color)


# ============================================================================
# CREW STAT TABLE
# ============================================================================

func _draw_crew_table(ship: Dictionary) -> void:
	var crew_rows: Array = _collect_crew_rows(ship)
	if crew_rows.is_empty():
		return

	var anchor: Vector2 = _table_anchor(ship)
	var header_x: float = anchor.x + TABLE_ROLE_COL_WIDTH
	var row_y: float = anchor.y

	# Background panel
	var width: float = TABLE_ROLE_COL_WIDTH + TABLE_COL_WIDTH * STAT_NAMES.size() + TABLE_PADDING * 2
	var height: float = TABLE_LINE_HEIGHT * (crew_rows.size() + 1) + TABLE_PADDING * 2
	draw_rect(Rect2(anchor - Vector2(TABLE_PADDING, TABLE_PADDING), Vector2(width, height)), TABLE_BG_COLOR, true)

	# Header
	for i in STAT_NAMES.size():
		var col_x: float = header_x + i * TABLE_COL_WIDTH
		_draw_text_centered(STAT_NAMES[i], Vector2(col_x + TABLE_COL_WIDTH * 0.5, row_y + TABLE_LINE_HEIGHT - 2), TABLE_HEADER_COLOR)
	row_y += TABLE_LINE_HEIGHT

	# Rows: one per crew member assigned to the ship.
	for row in crew_rows:
		var role_label: String = row.role_label
		var role_key: String = row.role_key
		var skills: Dictionary = row.skills
		var read_set: Dictionary = _role_read_set(role_key)

		_draw_text(role_label, Vector2(anchor.x, row_y + TABLE_LINE_HEIGHT - 2), TABLE_ROLE_COLOR)

		for i in STAT_NAMES.size():
			var stat_name: String = STAT_NAMES[i]
			var raw: float = float(skills.get(stat_name, 0.5))
			var value_int: int = int(round(clamp(raw, 0.0, 1.0) * 20.0))
			var is_read: bool = read_set.get(stat_name, false)
			var color: Color = _stat_color(value_int, is_read)
			var col_x: float = header_x + i * TABLE_COL_WIDTH
			_draw_text_centered(str(value_int), Vector2(col_x + TABLE_COL_WIDTH * 0.5, row_y + TABLE_LINE_HEIGHT - 2), color)

		row_y += TABLE_LINE_HEIGHT


## Build per-crew rows for the table from the ship's assigned crew.
func _collect_crew_rows(ship: Dictionary) -> Array:
	if _game == null:
		return []
	var crew_list: Array = _game.get("_crew_list")
	if not (crew_list is Array):
		return []
	var ship_id: String = ship.get("ship_id", "")
	if ship_id == "":
		return []

	var rows: Array = []
	for crew in crew_list:
		if crew.get("assigned_to") != ship_id:
			continue
		var role_int: int = int(crew.get("role", -1))
		var role_label: String = _role_label(role_int)
		var role_key: String = _role_key(role_int)
		var stats: Dictionary = crew.get("stats", {})
		rows.append({
			"role_label": role_label,
			"role_key": role_key,
			"skills": stats.get("skills", {}),
		})
	return rows


## Anchor the table to the bottom-right of the ship's hull bbox plus a small
## pixel offset, then clamp into the viewport so it never clips off-screen.
func _table_anchor(ship: Dictionary) -> Vector2:
	var ship_pos: Vector2 = ship.get("position", Vector2.ZERO)
	var size: float = float(ship.get("stats", {}).get("size", 16.0))
	# Bottom-right of the hull in world space is approximately +size/+size from
	# center; the overlay is unrotated so the visual offset reads consistently.
	var corner: Vector2 = ship_pos + Vector2(size, size)
	var anchor: Vector2 = corner + WingConstants.OVERLAY_HULL_OFFSET_PX
	return anchor


func _role_read_set(role_key: String) -> Dictionary:
	var listed: Array = ROLE_READ_STATS.get(role_key, STAT_NAMES)
	var set: Dictionary = {}
	for stat in listed:
		set[stat] = true
	return set


func _stat_color(value_0_20: int, is_read: bool) -> Color:
	if not is_read:
		return WingConstants.OVERLAY_STAT_COLOR_DIM
	if value_0_20 <= WingConstants.OVERLAY_STAT_LOW_MAX:
		return WingConstants.OVERLAY_STAT_COLOR_LOW
	if value_0_20 <= WingConstants.OVERLAY_STAT_MID_MAX:
		return WingConstants.OVERLAY_STAT_COLOR_MID
	return WingConstants.OVERLAY_STAT_COLOR_HIGH


func _role_label(role_int: int) -> String:
	match role_int:
		CrewData.Role.PILOT: return "pilot"
		CrewData.Role.GUNNER: return "gunner"
		CrewData.Role.CAPTAIN: return "captain"
		CrewData.Role.SQUADRON_LEADER: return "sqd ldr"
		CrewData.Role.FLEET_COMMANDER: return "fleet"
		CrewData.Role.ENGINEER: return "engineer"
		_: return "crew"


func _role_key(role_int: int) -> String:
	match role_int:
		CrewData.Role.PILOT: return "pilot"
		CrewData.Role.GUNNER: return "gunner"
		CrewData.Role.CAPTAIN: return "captain"
		CrewData.Role.SQUADRON_LEADER: return "squadron_leader"
		CrewData.Role.FLEET_COMMANDER: return "fleet_commander"
		CrewData.Role.ENGINEER: return "engineer"
		_: return ""


func _draw_text(text: String, pos: Vector2, color: Color) -> void:
	if _font == null:
		return
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, TABLE_FONT_SIZE, color)


func _draw_text_centered(text: String, pos: Vector2, color: Color) -> void:
	if _font == null:
		return
	var size: Vector2 = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, TABLE_FONT_SIZE)
	draw_string(_font, pos - Vector2(size.x * 0.5, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, TABLE_FONT_SIZE, color)
