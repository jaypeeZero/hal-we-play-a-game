class_name FleetCommandScreen
extends Control

## Fleet Command Screen — Football-Manager-style unified screen for fleet
## composition, crew personnel, and per-ship tactics.
##
## Usage:
##   var screen := FleetCommandScreen.new()
##   screen.setup(SkirmishSource.new(0), "save")
##   add_child(screen)
##
## Modes:
##   "save"   — skirmish editor (footer: "Save Fleet")
##   "done"   — roguelite fleet management (footer: "Done")
##   "launch" — pre-battle final review (footer: "Launch Battle")

signal done()

# Layout constants
const PANEL_LEFT_WIDTH := 280
const PANEL_RIGHT_WIDTH := 380
const FOOTER_HEIGHT := 48
const SHIP_CARD_BIG_SIZE := Vector2(128, 160)
const SHIP_CARD_SMALL_SIZE := Vector2(80, 100)
const POOL_PORTRAIT_SIZE := Vector2(64, 76)
const SLOT_MIN_HEIGHT := 56
const CREW_POOL_MIN_HEIGHT := 200
const DRAG_DIM_MODULATE := Color(1.0, 1.0, 1.0, 0.35)
const DRAG_PREVIEW_WIDTH := 180

# Mode → button label
const MODE_BUTTON_LABELS := {
	"save": "Save Fleet",
	"done": "Done",
	"launch": "Launch Battle",
}

const MISSION_LABELS := {
	SquadronData.Mission.FREE:      "Free",
	SquadronData.Mission.PATROL:    "Patrol",
	SquadronData.Mission.INTERCEPT: "Intercept",
	SquadronData.Mission.ELIMINATE: "Eliminate",
	SquadronData.Mission.ESCORT:    "Escort",
	SquadronData.Mission.SCREEN:    "Screen",
	SquadronData.Mission.ASSAULT:   "Assault",
}

const MISSION_ORDER := [
	SquadronData.Mission.FREE,
	SquadronData.Mission.PATROL,
	SquadronData.Mission.INTERCEPT,
	SquadronData.Mission.ELIMINATE,
	SquadronData.Mission.ESCORT,
	SquadronData.Mission.SCREEN,
	SquadronData.Mission.ASSAULT,
]

const SHIP_TYPES := ["fighter", "heavy_fighter", "torpedo_boat", "corvette", "capital"]

# State
var _source: FleetSource
var _mode: String = "save"
var _selected_hull_id: String = ""

# Layout nodes
var _roster_scroll: ScrollContainer
var _roster_grid: VBoxContainer
var _right_panel: VBoxContainer
var _pool_flow: HFlowContainer

# Tracks hull-card nodes for drag dimming
var _hull_card_nodes: Array = []   # Array[{hull_id: String, node: Control}]


func setup(source: FleetSource, mode: String) -> void:
	_source = source
	_mode = mode
	_build_layout()
	_select_first_ship()


## Open a self-freeing Fleet Command overlay over an active run.
## Adds the screen to `parent`, auto-frees on done, returns the screen.
static func open_overlay(parent: Node) -> FleetCommandScreen:
	var screen := FleetCommandScreen.new()
	screen.setup(RunSource.new(), "done")
	parent.add_child(screen)
	screen.done.connect(screen.queue_free)
	return screen


# ── Layout construction ──────────────────────────────────────────────────────

func _build_layout() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.backdrop())

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	# Top bar
	root.add_child(_build_topbar())

	# Body (left + right)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	root.add_child(body)

	# Left — fleet roster
	var left := _build_left_panel()
	body.add_child(left)

	# Right — selected ship detail
	var right_wrap := _build_right_panel()
	right_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right_wrap)

	# Crew pool
	root.add_child(_build_pool_section())

	# Footer
	root.add_child(_build_footer())


func _build_topbar() -> Control:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UiKit.panel_box(UiKit.PANEL_2, UiKit.LINE, 0, 12))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	bar.add_child(row)
	var title := UiKit.label("Fleet Command", UiKit.ACCENT, 16)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	return bar


func _build_left_panel() -> Control:
	var outer := PanelContainer.new()
	outer.add_theme_stylebox_override("panel", UiKit.panel_box(UiKit.PANEL, UiKit.LINE, 0, 0))
	outer.custom_minimum_size = Vector2(PANEL_LEFT_WIDTH, 0)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	outer.add_child(vbox)

	var header := _padded(UiKit.section_title("Fleet Roster"), 12, 8)
	vbox.add_child(header)

	_roster_scroll = ScrollContainer.new()
	_roster_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_roster_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_roster_scroll)

	_roster_grid = VBoxContainer.new()
	_roster_grid.add_theme_constant_override("separation", 4)
	_roster_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_roster_scroll.add_child(_roster_grid)

	var add_ship_row := _padded(_build_add_ship_row(), 12, 8)
	vbox.add_child(add_ship_row)

	return outer


func _build_add_ship_row() -> Control:
	var row := HBoxContainer.new()
	for ship_type in SHIP_TYPES:
		var btn := Button.new()
		btn.text = "+ %s" % ship_type.replace("_", " ")
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiKit.style_button(btn, "ghost")
		var t: String = ship_type
		btn.pressed.connect(func() -> void:
			_source.add_ship(t)
			_rebuild_roster()
		)
		row.add_child(btn)
	return row


func _build_right_panel() -> Control:
	var outer := PanelContainer.new()
	outer.add_theme_stylebox_override("panel", UiKit.panel_box(UiKit.PANEL, UiKit.LINE, 0, 0))

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	_right_panel = VBoxContainer.new()
	_right_panel.add_theme_constant_override("separation", 12)
	_right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_right_panel)

	return outer


func _build_pool_section() -> Control:
	var outer := PanelContainer.new()
	outer.add_theme_stylebox_override("panel", UiKit.panel_box(UiKit.PANEL_2, UiKit.LINE, 0, 10))
	outer.custom_minimum_size = Vector2(0, CREW_POOL_MIN_HEIGHT)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	outer.add_child(vbox)

	vbox.add_child(UiKit.section_title("Crew Pool"))

	# BUG 4 fix: wrap in a vertical ScrollContainer so 52+ portraits wrap and
	# scroll down rather than running off the right edge of the screen.
	var pool_scroll := ScrollContainer.new()
	pool_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pool_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pool_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pool_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	vbox.add_child(pool_scroll)

	_pool_flow = HFlowContainer.new()
	_pool_flow.add_theme_constant_override("h_separation", 8)
	_pool_flow.add_theme_constant_override("v_separation", 8)
	_pool_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pool_scroll.add_child(_pool_flow)

	return outer


func _build_footer() -> Control:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UiKit.panel_box(UiKit.PANEL_2, UiKit.LINE, 0, 10))
	bar.custom_minimum_size = Vector2(0, FOOTER_HEIGHT)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.add_child(row)

	var reset_btn := Button.new()
	reset_btn.text = "Reset Fleet"
	UiKit.style_button(reset_btn, "warn")
	reset_btn.pressed.connect(_on_reset_pressed)
	row.add_child(reset_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var back_btn := Button.new()
	back_btn.text = "Back"
	UiKit.style_button(back_btn, "ghost")
	back_btn.pressed.connect(func() -> void: done.emit())
	row.add_child(back_btn)

	var action_label: String = MODE_BUTTON_LABELS.get(_mode, "Done")
	var action_btn := Button.new()
	action_btn.text = action_label
	UiKit.style_button(action_btn, "primary")
	action_btn.pressed.connect(_on_action_pressed)
	row.add_child(action_btn)

	return bar


# ── Rebuild helpers ──────────────────────────────────────────────────────────

func _select_first_ship() -> void:
	var ships: Array = _source.ships()
	if not ships.is_empty():
		_selected_hull_id = str(ships[0].get("hull_id", ""))
	_rebuild_roster()
	_rebuild_right_panel()
	_rebuild_pool()


func _rebuild_roster() -> void:
	for child in _roster_grid.get_children():
		child.queue_free()
	_hull_card_nodes = []

	for hull in _source.ships():
		var hull_id: String = str(hull.get("hull_id", ""))
		var card: Control = _build_roster_card(hull)
		_roster_grid.add_child(card)
		_hull_card_nodes.append({"hull_id": hull_id, "node": card})


func _build_roster_card(hull: Dictionary) -> Control:
	var hull_id: String = str(hull.get("hull_id", ""))
	var ship_type: String = str(hull.get("ship_type", "fighter"))
	var is_selected: bool = hull_id == _selected_hull_id

	var card := PanelContainer.new()
	var bg: Color = UiKit.PANEL_2 if is_selected else UiKit.PANEL
	var border: Color = UiKit.ACCENT if is_selected else UiKit.LINE
	card.add_theme_stylebox_override("panel", UiKit.panel_box(bg, border, 6, 8))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)

	# Small ship card (sprite)
	var small_card := ShipCard.new()
	small_card.setup(ship_type, {"team": 0})
	small_card.set_card_size(SHIP_CARD_SMALL_SIZE)
	row.add_child(small_card)

	# Ship info
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	row.add_child(info)

	var explicit_name: String = str(hull.get("name", "")).strip_edges()
	var name_edit := LineEdit.new()
	name_edit.text = explicit_name
	name_edit.placeholder_text = _ship_display_name(hull)
	name_edit.add_theme_stylebox_override("normal", UiKit.panel_box(UiKit.PANEL_2, UiKit.LINE, 4, 4))
	name_edit.add_theme_color_override("font_color", UiKit.INK)
	name_edit.add_theme_color_override("caret_color", UiKit.ACCENT)
	var h: String = hull_id
	name_edit.text_submitted.connect(func(new_name: String) -> void:
		hull["name"] = new_name
	)
	info.add_child(name_edit)

	var type_lbl := UiKit.label(ship_type.replace("_", " ").capitalize(), UiKit.DIM, 11)
	info.add_child(type_lbl)

	var crew_count: int = hull.get("crew", []).size()
	var complement_count: int = hull.get("complement", []).size()
	var crew_lbl := UiKit.label("%d / %d crew" % [crew_count, complement_count], UiKit.INK, 11)
	info.add_child(crew_lbl)

	# Remove button
	var remove_btn := Button.new()
	remove_btn.text = "×"
	UiKit.style_button(remove_btn, "warn")
	remove_btn.pressed.connect(func() -> void:
		_source.remove_ship(h)
		if _selected_hull_id == h:
			_selected_hull_id = ""
		_rebuild_roster()
		_rebuild_right_panel()
		_rebuild_pool()
	)
	row.add_child(remove_btn)

	# Click to select
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
				and (event as InputEventMouseButton).pressed:
			_selected_hull_id = h
			_rebuild_roster()
			_rebuild_right_panel()
	)

	return card


func _rebuild_right_panel() -> void:
	for child in _right_panel.get_children():
		child.queue_free()

	if _selected_hull_id.is_empty():
		_right_panel.add_child(_padded(UiKit.label("Select a ship.", UiKit.DIM), 12, 12))
		return

	var hull: Dictionary = _hull_by_id(_selected_hull_id)
	if hull.is_empty():
		_right_panel.add_child(_padded(UiKit.label("Ship not found.", UiKit.DIM), 12, 12))
		return

	# Padded body
	var body := _padded_vbox(0, 0)
	_right_panel.add_child(_padded(body, 12, 12))

	# Big ship card + name/type header
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 12)
	body.add_child(header_row)

	var big_card := ShipCard.new()
	big_card.setup(str(hull.get("ship_type", "fighter")), {"team": 0})
	big_card.set_card_size(SHIP_CARD_BIG_SIZE)
	big_card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	big_card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	header_row.add_child(big_card)

	var header_info := VBoxContainer.new()
	header_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_info.add_theme_constant_override("separation", 6)
	header_row.add_child(header_info)

	var explicit_name: String = str(hull.get("name", "")).strip_edges()
	var name_edit := LineEdit.new()
	name_edit.text = explicit_name
	name_edit.placeholder_text = _ship_display_name(hull)
	name_edit.add_theme_stylebox_override("normal", UiKit.panel_box(UiKit.PANEL_2, UiKit.LINE, 4, 6))
	name_edit.add_theme_color_override("font_color", UiKit.INK)
	name_edit.add_theme_color_override("caret_color", UiKit.ACCENT)
	name_edit.text_submitted.connect(func(new_name: String) -> void:
		hull["name"] = new_name
		_rebuild_roster()
	)
	header_info.add_child(name_edit)
	header_info.add_child(UiKit.label(str(hull.get("ship_type", "")).replace("_", " ").capitalize(), UiKit.DIM, 12))

	# Condition meters
	const CONDITION_LOW_RATIO := 0.6
	var cond := HullConditionSystem.condition(hull)
	var meter_row := HBoxContainer.new()
	meter_row.add_theme_constant_override("separation", 8)
	meter_row.add_child(UiKit.mini_meter("Arm", cond.armor, UiKit.ACCENT,
		cond.armor < CONDITION_LOW_RATIO))
	meter_row.add_child(UiKit.mini_meter("Sys", cond.systems, UiKit.GOLD,
		cond.systems < CONDITION_LOW_RATIO))
	header_info.add_child(meter_row)

	# Ice / Activate button + badge
	var is_iced: bool = hull.get("iced", false)
	var ice_row := HBoxContainer.new()
	ice_row.add_theme_constant_override("separation", 8)
	if is_iced:
		ice_row.add_child(UiKit.badge("On ice"))
	var hid_ice: String = str(hull.get("hull_id", ""))
	var ice_btn := Button.new()
	ice_btn.text = "Activate" if is_iced else "Put on ice"
	UiKit.style_button(ice_btn, "ghost")
	ice_btn.pressed.connect(func() -> void:
		_source.set_iced(hid_ice, not hull.get("iced", false))
		_rebuild_right_panel()
		_rebuild_roster()
	)
	ice_row.add_child(ice_btn)
	header_info.add_child(ice_row)

	body.add_child(UiKit.separator())

	# Positions (personnel) — BUG 1 fix: use slot_assignments for exact pairing.
	body.add_child(UiKit.section_title("Positions"))
	for assignment in _slot_assignments(hull):
		body.add_child(_build_position_row(
			hull,
			assignment["slot"] as Dictionary,
			assignment["crew"] as Dictionary))

	body.add_child(UiKit.separator())

	# Tactics
	body.add_child(UiKit.section_title("Tactics"))
	body.add_child(_build_tactics_panel(hull))


## BUG 1 fix: pure helper — pairs each complement slot to its specific crew member.
## Gunner slots match by weapon_id; other roles consume one matching crew member each.
## Returns Array of {slot: Dictionary, crew: Dictionary} (crew is {} when vacant).
func _slot_assignments(hull: Dictionary) -> Array:
	# Index assigned crew by weapon_id for gunners, and build a consumable list
	# for non-gunner roles so each crew member is used at most once.
	var gunner_by_weapon: Dictionary = {}       # weapon_id -> crew dict
	var role_pool: Dictionary = {}              # role int -> Array[crew dict]

	for member in hull.get("crew", []):
		var r: int = int(member.get("role", -1))
		if r == CrewData.Role.GUNNER and member.has("weapon_id"):
			gunner_by_weapon[str(member["weapon_id"])] = member
		else:
			if not role_pool.has(r):
				role_pool[r] = []
			(role_pool[r] as Array).append(member)

	var result: Array = []
	for slot in hull.get("complement", []):
		var r: int = int(slot.get("role", -1))
		var matched: Dictionary = {}
		if r == CrewData.Role.GUNNER and slot.has("weapon_id"):
			var wid: String = str(slot["weapon_id"])
			if gunner_by_weapon.has(wid):
				matched = gunner_by_weapon[wid]
		else:
			if role_pool.has(r) and not (role_pool[r] as Array).is_empty():
				matched = (role_pool[r] as Array).pop_front()
		result.append({"slot": slot, "crew": matched})
	return result


## BUG 1/3 fix: receives the pre-matched crew for this specific slot.
func _build_position_row(hull: Dictionary, slot: Dictionary, assigned_member: Dictionary) -> Control:
	var role: int = int(slot.get("role", -1))
	var role_name: String = CrewData.get_role_name(role)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.custom_minimum_size = Vector2(0, SLOT_MIN_HEIGHT)

	# Role label
	var role_lbl := UiKit.label(role_name.to_upper(), UiKit.DIM, 11)
	role_lbl.custom_minimum_size = Vector2(64, 0)
	row.add_child(role_lbl)

	if not assigned_member.is_empty():
		# Occupied: show portrait + callsign, make draggable
		var slot_node: _AssignedSlot = _AssignedSlot.new()
		slot_node.setup(assigned_member, hull, self)
		row.add_child(slot_node)

		# Unassign button
		var crew_id: String = str(assigned_member.get("crew_id", ""))
		var unassign_btn := Button.new()
		unassign_btn.text = "−"
		UiKit.style_button(unassign_btn, "warn")
		unassign_btn.pressed.connect(func() -> void:
			_source.unassign(crew_id)
			_rebuild_right_panel()
			_rebuild_pool()
			_rebuild_roster()
		)
		row.add_child(unassign_btn)
	else:
		# Vacant: show drop target frame
		var vacant: _VacantSlot = _VacantSlot.new()
		vacant.setup(hull, slot, self)
		row.add_child(vacant)

	return row


func _build_tactics_panel(hull: Dictionary) -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)

	var hull_id: String = str(hull.get("hull_id", ""))
	var tactics: Dictionary = hull.get("tactics", {})
	var current_mission: String = tactics.get("mission", SquadronData.Mission.FREE)

	var mission_row := HBoxContainer.new()
	mission_row.add_theme_constant_override("separation", 8)
	mission_row.add_child(UiKit.label("Mission", UiKit.DIM, 12))

	var mission_drop := OptionButton.new()
	for m in MISSION_ORDER:
		mission_drop.add_item(MISSION_LABELS.get(m, m))
	mission_drop.selected = max(0, MISSION_ORDER.find(current_mission))
	mission_drop.item_selected.connect(func(idx: int) -> void:
		var new_mission: String = MISSION_ORDER[idx]
		var new_tactics: Dictionary = {"mission": new_mission, "mission_params": {}}
		_source.set_tactics(hull_id, new_tactics)
		_rebuild_right_panel()
	)
	mission_row.add_child(mission_drop)
	vbox.add_child(mission_row)

	return vbox


func _rebuild_pool() -> void:
	for child in _pool_flow.get_children():
		child.queue_free()

	for member in _source.crew_pool():
		var chip: _PoolChip = _PoolChip.new()
		chip.setup(member, self)
		_pool_flow.add_child(chip)

	if _source.crew_pool().is_empty():
		_pool_flow.add_child(UiKit.label("(all crew assigned)", UiKit.DIM, 12))


# ── Drag/drop notifications ──────────────────────────────────────────────────

## Dim hull cards in the roster that can't accept the dragged crew.
func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		var vp: Viewport = get_viewport()
		if vp == null:
			return
		var data: Variant = vp.gui_get_drag_data()
		for entry in _hull_card_nodes:
			var hull_id: String = str(entry.get("hull_id", ""))
			var node: Control = entry.get("node") as Control
			if node != null:
				node.modulate = (Color.WHITE if _hull_accepts(hull_id, data)
					else DRAG_DIM_MODULATE)
	elif what == NOTIFICATION_DRAG_END:
		for entry in _hull_card_nodes:
			var node: Control = entry.get("node") as Control
			if node != null:
				node.modulate = Color.WHITE


func _hull_accepts(hull_id: String, data: Variant) -> bool:
	if not (data is Dictionary and data.get("kind", "") == "crew"):
		return false
	return _source.can_assign(str(data.get("crew_id", "")), hull_id)


# ── Event handlers ──────────────────────────────────────────────────────────

func _on_action_pressed() -> void:
	_source.commit()
	done.emit()


func _on_reset_pressed() -> void:
	if _mode != "save":
		return
	# SkirmishSource does not expose reset; reload fresh from disk.
	# Re-init by re-running setup with a fresh source.
	var fresh: SkirmishSource = SkirmishSource.new(0)
	_source = fresh
	_selected_hull_id = ""
	_rebuild_roster()
	_rebuild_right_panel()
	_rebuild_pool()


# ── Helpers ──────────────────────────────────────────────────────────────────

func on_assign_changed() -> void:
	_rebuild_right_panel()
	_rebuild_pool()
	_rebuild_roster()


## Human-readable ship name. Uses the hull's explicit `name` when the player has
## set one; otherwise derives a real-sounding label from the ship type and the
## hull number, e.g. hull_0 fighter → "Fighter 1" (1-based). Never "Ship name".
func _ship_display_name(hull: Dictionary) -> String:
	var explicit: String = str(hull.get("name", "")).strip_edges()
	if not explicit.is_empty():
		return explicit
	var type_label: String = str(hull.get("ship_type", "ship")).replace("_", " ").capitalize()
	var hull_id: String = str(hull.get("hull_id", ""))
	var digits: String = ""
	for i in range(hull_id.length() - 1, -1, -1):
		if hull_id[i] >= "0" and hull_id[i] <= "9":
			digits = hull_id[i] + digits
		elif not digits.is_empty():
			break
	if digits.is_empty():
		return type_label
	return "%s %d" % [type_label, int(digits) + 1]


func _hull_by_id(hull_id: String) -> Dictionary:
	for hull in _source.ships():
		if str(hull.get("hull_id", "")) == hull_id:
			return hull
	return {}


## Wrap a control in a MarginContainer with uniform padding.
func _padded(content: Control, h_pad: int, v_pad: int) -> Control:
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_left", h_pad)
	wrap.add_theme_constant_override("margin_right", h_pad)
	wrap.add_theme_constant_override("margin_top", v_pad)
	wrap.add_theme_constant_override("margin_bottom", v_pad)
	wrap.add_child(content)
	return wrap


func _padded_vbox(h_pad: int, v_pad: int) -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	# Note: margin constants on VBoxContainer are not supported;
	# callers should wrap in _padded() if outer margins are needed.
	return vbox


# ── Inner classes ─────────────────────────────────────────────────────────────

## A draggable occupied crew slot in the positions panel.
class _AssignedSlot extends HBoxContainer:
	var _member: Dictionary = {}
	var _screen: FleetCommandScreen
	var _ship_type: String = ""

	func setup(member: Dictionary, hull: Dictionary, screen: FleetCommandScreen) -> void:
		_member = member
		_screen = screen
		_ship_type = str(hull.get("ship_type", ""))
		add_theme_constant_override("separation", 6)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var portrait := CrewPortrait.new()
		portrait.custom_minimum_size = Vector2(40, 48)
		portrait.setup(CrewData.entry_from_crew(member))
		# BUG 2 fix: TextureRect defaults to MOUSE_FILTER_STOP, which eats
		# drag events before they reach the parent HBoxContainer drag source.
		portrait.mouse_filter = Control.MOUSE_FILTER_PASS
		add_child(portrait)

		var name_lbl := UiKit.label(str(member.get("callsign", "?")), UiKit.INK, 12)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
		add_child(name_lbl)

		if CrewData.is_off_role(member):
			var badge: Control = UiKit.badge("off-role", UiKit.BAD)
			badge.mouse_filter = Control.MOUSE_FILTER_PASS
			add_child(badge)

	func _get_drag_data(_pos: Vector2) -> Variant:
		var preview := PanelContainer.new()
		preview.add_theme_stylebox_override("panel", UiKit.panel_box(UiKit.CHIP, UiKit.ACCENT))
		preview.add_child(UiKit.label(str(_member.get("callsign", "")), UiKit.ACCENT, 12))
		preview.custom_minimum_size = Vector2(FleetCommandScreen.DRAG_PREVIEW_WIDTH, 0)
		var vp: Viewport = get_viewport()
		if vp != null and vp.gui_is_dragging():
			set_drag_preview(preview)
		return {"kind": "crew", "crew_id": str(_member.get("crew_id", "")),
			"role": int(_member.get("role", CrewData.Role.PILOT))}

	func _gui_input(event: InputEvent) -> void:
		# A left click (not a drag) opens the crew stats popup. Drag is initiated
		# via _get_drag_data on motion, which sets gui_is_dragging() — so guarding
		# on that keeps click and drag-and-drop independent.
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
				and not event.pressed:
			var vp: Viewport = get_viewport()
			if vp != null and not vp.gui_is_dragging():
				var orders_ctx: Dictionary = {
					"crew_id": str(_member.get("crew_id", "")),
					"ship_type": _ship_type,
					"role": int(_member.get("role", -1)),
				}
				CrewViewModal.open(_screen, CrewData.entry_from_crew(_member), orders_ctx)


## A vacant position slot: drop target that calls source.assign.
class _VacantSlot extends PanelContainer:
	var _hull_id: String = ""
	var _slot: Dictionary = {}
	var _screen: FleetCommandScreen

	func setup(hull: Dictionary, slot: Dictionary, screen: FleetCommandScreen) -> void:
		_hull_id = str(hull.get("hull_id", ""))
		_slot = slot
		_screen = screen
		custom_minimum_size = Vector2(120, FleetCommandScreen.SLOT_MIN_HEIGHT)
		add_theme_stylebox_override("panel", UiKit.panel_box(UiKit.CHIP, UiKit.LINE, 4, 6))
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		add_child(row)

		row.add_child(UiKit.label("VACANT", UiKit.DIM, 10))
		if _slot.has("weapon_id"):
			row.add_child(UiKit.label(str(_slot.get("weapon_id", "")), UiKit.ACCENT, 10))

	func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
		if not (data is Dictionary and data.get("kind", "") == "crew"):
			return false
		return _screen._source.can_assign(str(data.get("crew_id", "")), _hull_id)

	func _drop_data(_pos: Vector2, data: Variant) -> void:
		_screen._source.assign(str(data.get("crew_id", "")), _hull_id)
		_screen.on_assign_changed()


## A draggable pool crew chip.
class _PoolChip extends PanelContainer:
	var _member: Dictionary = {}
	var _screen: FleetCommandScreen

	func setup(member: Dictionary, screen: FleetCommandScreen) -> void:
		_member = member
		_screen = screen
		add_theme_stylebox_override("panel", UiKit.panel_box(UiKit.CHIP, UiKit.LINE, 6, 6))

		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		col.mouse_filter = Control.MOUSE_FILTER_PASS
		add_child(col)

		var portrait := CrewPortrait.new()
		portrait.custom_minimum_size = FleetCommandScreen.POOL_PORTRAIT_SIZE
		portrait.setup(CrewData.entry_from_crew(member))
		# Pass mouse events through to this chip so the WHOLE chip is a drag
		# source and a click target (not just bare areas).
		portrait.mouse_filter = Control.MOUSE_FILTER_PASS
		col.add_child(portrait)

		var name_lbl := UiKit.label(str(member.get("callsign", "?")), UiKit.INK, 10)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.clip_contents = true
		name_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
		col.add_child(name_lbl)

		var role_lbl := UiKit.label(CrewData.get_role_name(int(member.get("role", -1))), UiKit.DIM, 9)
		role_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		role_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
		col.add_child(role_lbl)

	func _get_drag_data(_pos: Vector2) -> Variant:
		var preview := PanelContainer.new()
		preview.add_theme_stylebox_override("panel", UiKit.panel_box(UiKit.CHIP, UiKit.ACCENT))
		var lbl := UiKit.label(
			"%s · %s" % [str(_member.get("callsign", "")),
				CrewData.get_role_name(int(_member.get("role", -1)))],
			UiKit.ACCENT, 12)
		preview.add_child(lbl)
		preview.custom_minimum_size = Vector2(FleetCommandScreen.DRAG_PREVIEW_WIDTH, 0)
		var vp: Viewport = get_viewport()
		if vp != null and vp.gui_is_dragging():
			set_drag_preview(preview)
		return {"kind": "crew", "crew_id": str(_member.get("crew_id", "")),
			"role": int(_member.get("role", CrewData.Role.PILOT))}

	func _gui_input(event: InputEvent) -> void:
		# Left click (not drag) → crew stats popup. See _AssignedSlot._gui_input.
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
				and not event.pressed:
			var vp: Viewport = get_viewport()
			if vp != null and not vp.gui_is_dragging():
				var orders_ctx: Dictionary = {
					"crew_id": str(_member.get("crew_id", "")),
					"ship_type": "",
					"role": int(_member.get("role", -1)),
				}
				CrewViewModal.open(_screen, CrewData.entry_from_crew(_member), orders_ctx)
