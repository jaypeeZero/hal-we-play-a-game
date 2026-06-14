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

const BOUNDARY_SEGMENTS: int = 96
const BOUNDARY_COLOR: Color = Color(1.0, 0.85, 0.2, 0.5)  # amber — distinct from team colors
const BOUNDARY_WIDTH: float = 4.0

const TABLE_FONT_SIZE: int = 10
const TABLE_LINE_HEIGHT: int = 12
const TABLE_COL_WIDTH: int = 28
const TABLE_ROLE_COL_WIDTH: int = 36
const TABLE_PADDING: int = 4
const TABLE_BG_COLOR: Color = Color(0.0, 0.0, 0.0, 0.55)
const TABLE_HEADER_COLOR: Color = Color(0.85, 0.85, 0.85, 1.0)
const TABLE_ROLE_COLOR: Color = Color(0.85, 0.85, 0.85, 1.0)

# Tactics state layer — per-ship block to the LEFT of the crew table.
const TACTICS_FONT_SIZE: int = 10
const TACTICS_LINE_HEIGHT: int = 12
const TACTICS_BLOCK_WIDTH: int = 160
const TACTICS_PADDING: int = 4
const TACTICS_LEFT_OFFSET: int = 8  # Gap between tactics block right edge and crew table left edge
const TACTICS_BG_COLOR: Color = Color(0.0, 0.0, 0.08, 0.6)
const TACTICS_LABEL_COLOR: Color = Color(0.75, 0.75, 0.75, 1.0)
const TACTICS_FIRE_OK_COLOR: Color = Color(0.35, 0.95, 0.35, 1.0)
const TACTICS_FIRE_WARN_COLOR: Color = Color(0.95, 0.55, 0.2, 1.0)
const TACTICS_FIRE_BAD_COLOR: Color = Color(0.95, 0.3, 0.3, 1.0)

# Tactics telemetry HUD — fixed screen position (bottom-left corner).
const TELEMETRY_FONT_SIZE: int = 10
const TELEMETRY_LINE_HEIGHT: int = 12
const TELEMETRY_PADDING: int = 6
const TELEMETRY_SCREEN_MARGIN: int = 10
const TELEMETRY_BG_COLOR: Color = Color(0.0, 0.0, 0.08, 0.65)
const TELEMETRY_TEAM_COLORS: Array = [
	Color(0.45, 0.75, 1.0, 1.0),   # team 0 — blue
	Color(1.0, 0.5, 0.5, 1.0),     # team 1 — red
]
const TELEMETRY_VALUE_COLOR: Color = Color(0.9, 0.9, 0.9, 1.0)
const TELEMETRY_SECTOR_COLOR: Color = Color(0.75, 0.85, 0.65, 1.0)

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
	if GameSettings.show_escape_boundary:
		_draw_escape_boundary()

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
		if GameSettings.show_tactics_state:
			_draw_tactics_state(ship)

	if GameSettings.show_tactics_telemetry:
		_draw_tactics_telemetry()


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


## Draw the escape boundary ovoid as a closed polyline (Godot has no ellipse
## stroke primitive). Sized off the game's battlefield via FleeBoundarySystem.
func _draw_escape_boundary() -> void:
	var size: Vector2 = _game._battlefield_size
	var c: Vector2 = FleeBoundarySystem.center(size)
	var ax: Vector2 = FleeBoundarySystem.semi_axes(size)
	var pts := PackedVector2Array()
	for i in range(BOUNDARY_SEGMENTS + 1):
		var t: float = TAU * float(i) / float(BOUNDARY_SEGMENTS)
		pts.append(c + Vector2(cos(t) * ax.x, sin(t) * ax.y))
	draw_polyline(pts, BOUNDARY_COLOR, BOUNDARY_WIDTH)


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


# TACTICS STATE LAYER

## Draw a compact per-ship tactics block anchored to the LEFT of the crew table.
## Reads ship orders, pilot crew["tactics"] dials, and WeaponSystem.diagnose_firing.
## Pure consumer — never mutates ship or crew.
func _draw_tactics_state(ship: Dictionary) -> void:
	if _game == null:
		return

	# Anchor to the LEFT of the crew table so they don't overlap.
	# Crew table starts at _table_anchor(ship); our block ends just before it.
	var crew_anchor: Vector2 = _table_anchor(ship)
	var block_x: float = crew_anchor.x - TACTICS_LEFT_OFFSET - TACTICS_BLOCK_WIDTH
	var block_y: float = crew_anchor.y

	var orders: Dictionary = ship.get("orders", {})
	var current_order: String = orders.get("current_order", "")
	var maneuver_subtype: String = orders.get("maneuver_subtype", "")
	var engagement_target: String = orders.get("engagement_target", orders.get("target_id", ""))

	# Find pilot crew for this ship.
	var pilot_tactics: Dictionary = {}
	var command_hat: String = ""
	var pilot_name: String = "—"
	var pilot_posture: String = ""
	var pilot_has_support: bool = false
	var crew_list: Array = _game.get("_crew_list") if _game.get("_crew_list") is Array else []
	var ship_id: String = ship.get("ship_id", "")
	for crew in crew_list:
		if crew.get("assigned_to") != ship_id:
			continue
		if int(crew.get("role", -1)) == CrewData.Role.PILOT:
			pilot_tactics = crew.get("tactics", {})
			command_hat = crew.get("command_hat", "")
			pilot_name = str(crew.get("callsign", crew.get("crew_id", "—")))
			pilot_posture = crew.get("posture", "")
			pilot_has_support = crew.get("support_assignment", "") != ""
			break

	# Formation
	var formation: Dictionary = orders.get("formation_assignment", {})
	var formation_str: String
	if formation.is_empty():
		formation_str = "—"
	else:
		var shape: String = formation.get("shape", "")
		var lead_id: String = formation.get("lead_ship_id", "")
		formation_str = "%s [lead:%s]" % [shape, lead_id] if lead_id != "" else shape

	# Firing diagnosis
	var diag: Dictionary = WeaponSystem.diagnose_firing(ship, _game._ships)
	var fire_label: String
	var fire_color: Color
	if diag.get("firing", false):
		fire_label = "FIRE: yes"
		fire_color = TACTICS_FIRE_OK_COLOR
	else:
		var reason: String = diag.get("reason", "")
		fire_label = "FIRE: %s" % reason
		match reason:
			WeaponSystem.DIAG_OUT_OF_RANGE, WeaponSystem.DIAG_OUT_OF_ARC:
				fire_color = TACTICS_FIRE_WARN_COLOR
			_:
				fire_color = TACTICS_FIRE_BAD_COLOR

	# Build lines. Ships have no display name, so identify by type + id; the
	# pilot is named by callsign (falls back to crew_id).
	var ship_line: String = "%s  %s" % [ship.get("type", "ship"), ship_id]
	var pilot_line: String = "Pilot: %s" % pilot_name
	var intent_line: String = "Intent: %s" % current_order
	if maneuver_subtype != "":
		intent_line += " (%s)" % maneuver_subtype
	var target_line: String = "Target: %s" % (engagement_target if engagement_target != "" else "none")
	var formation_line: String = "Formation: %s" % formation_str
	var dials_line: String = ""
	if not pilot_tactics.is_empty():
		var role_d: String = pilot_tactics.get("role", "?")
		var duty_d: String = pilot_tactics.get("duty", "?")
		var ment_d: String = pilot_tactics.get("mentality", "?")
		var range_s: float  = float(pilot_tactics.get("range_scalar", pilot_tactics.get("mentality_scalar", 0.0)))
		dials_line = "Dials: %s/%s/%s r:%.2f" % [role_d, duty_d, ment_d, range_s]
		if command_hat == "commander":
			dials_line += " [CMDR]"
		elif command_hat == "squadron_leader":
			dials_line += " [LEAD]"
		# Posture and escort markers (4b: activated brain outputs)
		if pilot_posture != "":
			dials_line += " pos:%s" % pilot_posture
		if pilot_has_support:
			dials_line += " [SUP]"

	var lines: Array = [ship_line, pilot_line, intent_line, target_line, fire_label, formation_line]
	if dials_line != "":
		lines.append(dials_line)

	var block_height: float = TACTICS_LINE_HEIGHT * lines.size() + TACTICS_PADDING * 2
	draw_rect(
		Rect2(Vector2(block_x - TACTICS_PADDING, block_y - TACTICS_PADDING),
		      Vector2(TACTICS_BLOCK_WIDTH + TACTICS_PADDING * 2, block_height)),
		TACTICS_BG_COLOR, true
	)

	var row_y: float = block_y + TACTICS_LINE_HEIGHT - 2
	for i in lines.size():
		var line: String = lines[i]
		var color: Color = fire_color if line.begins_with("FIRE:") else TACTICS_LABEL_COLOR
		_draw_text_tactics(line, Vector2(block_x, row_y), color)
		row_y += TACTICS_LINE_HEIGHT


func _draw_text_tactics(text: String, pos: Vector2, color: Color) -> void:
	if _font == null:
		return
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, TACTICS_FONT_SIZE, color)


# TACTICS TELEMETRY HUD

## Draw a fixed-position telemetry panel in the bottom-left screen corner.
## Shows snapshot metrics for each team. Pure consumer — never mutates anything.
func _draw_tactics_telemetry() -> void:
	if _game == null:
		return

	# Collect teams present in the battle.
	var teams_seen: Dictionary = {}
	for ship in _game._ships:
		teams_seen[ship.get("team", 0)] = true
	var teams: Array = teams_seen.keys()
	teams.sort()

	# Build all lines first so we can size the background.
	var sections: Array = []  # Array of {team, lines: Array[{text, color}]}
	for team in teams:
		var snap: Dictionary = TacticsTelemetry.snapshot(_game._ships, team)
		var smd: Dictionary = snap.get("sector_mass_distribution", {})
		var tcolor: Color = TELEMETRY_TEAM_COLORS[team] if team < TELEMETRY_TEAM_COLORS.size() else TELEMETRY_VALUE_COLOR
		var team_lines: Array = [
			{"text": "— Team %d —" % team, "color": tcolor},
			{"text": "  Eng range: %.0f" % snap.get("mean_engagement_range", 0.0), "color": TELEMETRY_VALUE_COLOR},
			{"text": "  Dispersion: %.0f" % snap.get("formation_dispersion", 0.0),  "color": TELEMETRY_VALUE_COLOR},
			{"text": "  Focus: %.2f" % snap.get("focus_concentration", 0.0),        "color": TELEMETRY_VALUE_COLOR},
			{"text": "  Sector L/C/R: %.0f%%/%.0f%%/%.0f%%" % [
				smd.get("left", 0.0) * 100.0,
				smd.get("center", 0.0) * 100.0,
				smd.get("right", 0.0) * 100.0,
			], "color": TELEMETRY_SECTOR_COLOR},
		]
		sections.append({"team": team, "lines": team_lines})

	if sections.is_empty():
		return

	var total_lines: int = 0
	for sec in sections:
		total_lines += sec.lines.size()
	# Add one blank separator line between teams (except after last).
	total_lines += maxi(sections.size() - 1, 0)

	var panel_width: float = 200.0
	var panel_height: float = float(total_lines) * TELEMETRY_LINE_HEIGHT + TELEMETRY_PADDING * 2
	var viewport_size: Vector2 = get_viewport_rect().size
	var panel_pos: Vector2 = Vector2(
		TELEMETRY_SCREEN_MARGIN,
		viewport_size.y - TELEMETRY_SCREEN_MARGIN - panel_height
	)

	draw_rect(Rect2(panel_pos, Vector2(panel_width, panel_height)), TELEMETRY_BG_COLOR, true)

	var row_y: float = panel_pos.y + TELEMETRY_PADDING + TELEMETRY_LINE_HEIGHT - 2
	for s_idx in sections.size():
		var sec: Dictionary = sections[s_idx]
		for line_data in sec.lines:
			draw_string(_font, Vector2(panel_pos.x + TELEMETRY_PADDING, row_y),
				line_data.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
				TELEMETRY_FONT_SIZE, line_data.color)
			row_y += TELEMETRY_LINE_HEIGHT
		# Blank separator between teams.
		if s_idx < sections.size() - 1:
			row_y += TELEMETRY_LINE_HEIGHT


func _draw_text(text: String, pos: Vector2, color: Color) -> void:
	if _font == null:
		return
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, TABLE_FONT_SIZE, color)


func _draw_text_centered(text: String, pos: Vector2, color: Color) -> void:
	if _font == null:
		return
	var size: Vector2 = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, TABLE_FONT_SIZE)
	draw_string(_font, pos - Vector2(size.x * 0.5, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, TABLE_FONT_SIZE, color)
