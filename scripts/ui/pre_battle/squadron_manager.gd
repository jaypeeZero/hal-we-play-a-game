class_name SquadronManager
extends Control

## Pre-battle squadron management screen.
## Three-column layout: squadron list | ship assignment | mission config.
## All state lives in RoguelikeRun.squadrons; this UI reads and writes it
## via SquadronSystem pure functions.

signal done()

const MISSION_LABELS := {
	SquadronData.Mission.FREE:      "Free",
	SquadronData.Mission.PATROL:    "Patrol",
	SquadronData.Mission.INTERCEPT: "Intercept",
	SquadronData.Mission.ELIMINATE: "Eliminate",
	SquadronData.Mission.ESCORT:    "Escort",
	SquadronData.Mission.SCREEN:    "Screen",
	SquadronData.Mission.ASSAULT:   "Assault",
}

# Ordered for the dropdown.
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

var _selected_squadron_id: String = ""
var _doctrine_overlay: DoctrinePanel = null

# Layout nodes built once in _build_layout.
var _squad_list: VBoxContainer
var _ship_list: VBoxContainer
var _mission_panel: VBoxContainer


func setup() -> void:
	"""Populate from RoguelikeRun.squadrons, seeding defaults if empty."""
	if RoguelikeRun.squadrons.is_empty():
		RoguelikeRun.squadrons = SquadronSystem.default_squadrons_for_fleet(RoguelikeRun.fleet_hulls)
	if not RoguelikeRun.squadrons.is_empty():
		_selected_squadron_id = RoguelikeRun.squadrons[0].get("squadron_id", "")
	_rebuild_all()


func _build_layout() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.backdrop())

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	# Header row.
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := UiKit.label("Squadron Manager", UiKit.ACCENT, 16)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var battle_btn := Button.new()
	battle_btn.text = "Battle →"
	UiKit.style_button(battle_btn, "primary")
	battle_btn.pressed.connect(_on_battle_pressed)
	header.add_child(battle_btn)

	root.add_child(UiKit.separator())

	# Three-column body.
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 8)
	root.add_child(columns)

	# Left — squadron list.
	var left := UiKit.card()
	left.custom_minimum_size = Vector2(200, 0)
	columns.add_child(left)
	var left_inner := VBoxContainer.new()
	left.add_child(left_inner)
	left_inner.add_child(UiKit.section_title("Squadrons"))
	_squad_list = VBoxContainer.new()
	_squad_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_inner.add_child(_squad_list)
	left_inner.add_child(UiKit.separator())
	var new_btn := Button.new()
	new_btn.text = "+ New Squadron"
	new_btn.pressed.connect(_on_new_squadron_pressed)
	left_inner.add_child(new_btn)

	# Center — ship assignment.
	var center := UiKit.card()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(center)
	var center_inner := VBoxContainer.new()
	center.add_child(center_inner)
	center_inner.add_child(UiKit.section_title("Ships"))
	_ship_list = VBoxContainer.new()
	_ship_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center_inner.add_child(_ship_list)

	# Right — mission config.
	var right := UiKit.card()
	right.custom_minimum_size = Vector2(220, 0)
	columns.add_child(right)
	var right_inner := VBoxContainer.new()
	right.add_child(right_inner)
	right_inner.add_child(UiKit.section_title("Mission"))
	_mission_panel = VBoxContainer.new()
	_mission_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_inner.add_child(_mission_panel)


func _rebuild_all() -> void:
	if _squad_list == null:
		_build_layout()
	_rebuild_squadron_list()
	_rebuild_ship_list()
	_rebuild_mission_panel()


func _rebuild_squadron_list() -> void:
	for c in _squad_list.get_children():
		c.queue_free()

	for sq in RoguelikeRun.squadrons:
		var sq_id: String = sq.get("squadron_id", "")
		var count: int = sq.get("hull_ids", []).size()
		var is_selected: bool = sq_id == _selected_squadron_id

		var row := HBoxContainer.new()
		_squad_list.add_child(row)

		var name_btn := Button.new()
		name_btn.text = "%s (%d)" % [sq.get("name", "?"), count]
		name_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if is_selected:
			UiKit.style_button(name_btn, "primary")
		name_btn.pressed.connect(_on_squadron_clicked.bind(sq_id))
		row.add_child(name_btn)

		var del_btn := Button.new()
		del_btn.text = "×"
		UiKit.style_button(del_btn, "warn")
		del_btn.pressed.connect(_on_delete_squadron_pressed.bind(sq_id))
		row.add_child(del_btn)


func _rebuild_ship_list() -> void:
	for c in _ship_list.get_children():
		c.queue_free()

	var sq: Dictionary = _current_squadron()

	if not sq.is_empty():
		_ship_list.add_child(UiKit.label(sq.get("name", ""), UiKit.ACCENT, 12))
		for hull_id in sq.get("hull_ids", []):
			_ship_list.add_child(_make_ship_row(hull_id, true))
		_ship_list.add_child(UiKit.separator())

	_ship_list.add_child(UiKit.label("Unassigned", UiKit.DIM, 12))
	var all_ids: Array = RoguelikeRun.fleet_hulls.map(func(h): return h.get("hull_id", ""))
	var unassigned := SquadronSystem.unassigned_hulls(RoguelikeRun.squadrons, all_ids)
	if unassigned.is_empty():
		_ship_list.add_child(UiKit.label("(none)", UiKit.DIM, 12))
	for hull_id in unassigned:
		_ship_list.add_child(_make_ship_row(hull_id, false))


func _make_ship_row(hull_id: String, in_squadron: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	var hull: Dictionary = _hull_by_id(hull_id)
	var ship_type: String = hull.get("ship_type", hull_id)
	var name_label := UiKit.label(hull_id, UiKit.INK)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	row.add_child(UiKit.badge(ship_type, UiKit.DIM))

	var adv_btn := Button.new()
	adv_btn.text = "⋯"
	adv_btn.pressed.connect(_on_ship_advanced_pressed.bind(hull_id))
	row.add_child(adv_btn)

	var assign_btn := Button.new()
	if in_squadron:
		assign_btn.text = "−"
		UiKit.style_button(assign_btn, "warn")
		assign_btn.pressed.connect(_on_remove_ship_pressed.bind(hull_id))
	else:
		assign_btn.text = "+"
		assign_btn.disabled = _selected_squadron_id.is_empty()
		assign_btn.pressed.connect(_on_add_ship_pressed.bind(hull_id))
	row.add_child(assign_btn)
	return row


func _rebuild_mission_panel() -> void:
	for c in _mission_panel.get_children():
		c.queue_free()

	var sq: Dictionary = _current_squadron()
	if sq.is_empty():
		_mission_panel.add_child(UiKit.label("Select a squadron.", UiKit.DIM))
		return

	var mission: String = sq.get("mission", SquadronData.Mission.FREE)
	var params: Dictionary = sq.get("mission_params", {})

	var mission_drop := OptionButton.new()
	for m in MISSION_ORDER:
		mission_drop.add_item(MISSION_LABELS.get(m, m))
	mission_drop.selected = MISSION_ORDER.find(mission)
	mission_drop.item_selected.connect(func(idx): _on_mission_selected(MISSION_ORDER[idx]))
	_mission_panel.add_child(mission_drop)

	_mission_panel.add_child(UiKit.separator())
	_build_param_controls(mission, params)


func _build_param_controls(mission: String, params: Dictionary) -> void:
	match mission:
		SquadronData.Mission.INTERCEPT:
			_mission_panel.add_child(UiKit.label("Priority class:", UiKit.DIM, 12))
			var drop := OptionButton.new()
			for st in SHIP_TYPES:
				drop.add_item(st)
			var current_class: String = params.get("priority_class", SHIP_TYPES[0])
			drop.selected = max(0, SHIP_TYPES.find(current_class))
			drop.item_selected.connect(func(idx): _on_param_changed("priority_class", SHIP_TYPES[idx]))
			_mission_panel.add_child(drop)

		SquadronData.Mission.ELIMINATE:
			_mission_panel.add_child(UiKit.label("Enemy target:", UiKit.DIM, 12))
			_mission_panel.add_child(UiKit.label("(set in battle)", UiKit.DIM, 11))

		SquadronData.Mission.ESCORT:
			_mission_panel.add_child(UiKit.label("Escort hull:", UiKit.DIM, 12))
			var all_ids: Array = RoguelikeRun.fleet_hulls.map(func(h): return h.get("hull_id", ""))
			var sq_ids: Array = _current_squadron().get("hull_ids", [])
			var candidates: Array = all_ids.filter(func(hid): return hid not in sq_ids)
			if candidates.is_empty():
				_mission_panel.add_child(UiKit.label("(no other hulls)", UiKit.DIM, 11))
			else:
				var drop := OptionButton.new()
				for hid in candidates:
					drop.add_item(hid)
				var current: String = params.get("escort_hull_id", candidates[0])
				drop.selected = max(0, candidates.find(current))
				drop.item_selected.connect(func(idx): _on_param_changed("escort_hull_id", candidates[idx]))
				_mission_panel.add_child(drop)

		SquadronData.Mission.SCREEN:
			_mission_panel.add_child(UiKit.label("Screen for hull:", UiKit.DIM, 12))
			var capitals: Array = RoguelikeRun.fleet_hulls.filter(
				func(h): return h.get("ship_type", "") == "capital"
			).map(func(h): return h.get("hull_id", ""))
			if capitals.is_empty():
				_mission_panel.add_child(UiKit.label("(no capitals in fleet)", UiKit.DIM, 11))
			else:
				var drop := OptionButton.new()
				for hid in capitals:
					drop.add_item(hid)
				var current: String = params.get("screen_for_hull_id", capitals[0])
				drop.selected = max(0, capitals.find(current))
				drop.item_selected.connect(func(idx): _on_param_changed("screen_for_hull_id", capitals[idx]))
				_mission_panel.add_child(drop)

		SquadronData.Mission.PATROL, SquadronData.Mission.ASSAULT:
			_mission_panel.add_child(UiKit.label("Zone center X:", UiKit.DIM, 12))
			var x_edit := LineEdit.new()
			x_edit.text = str(params.get("zone_center_x", "2500"))
			x_edit.text_changed.connect(func(v): _on_param_changed("zone_center_x", v))
			_mission_panel.add_child(x_edit)
			_mission_panel.add_child(UiKit.label("Zone center Y:", UiKit.DIM, 12))
			var y_edit := LineEdit.new()
			y_edit.text = str(params.get("zone_center_y", "1750"))
			y_edit.text_changed.connect(func(v): _on_param_changed("zone_center_y", v))
			_mission_panel.add_child(y_edit)
			if mission == SquadronData.Mission.PATROL:
				_mission_panel.add_child(UiKit.label("Zone radius:", UiKit.DIM, 12))
				var r_edit := LineEdit.new()
				r_edit.text = str(params.get("zone_radius", "800"))
				r_edit.text_changed.connect(func(v): _on_param_changed("zone_radius", v))
				_mission_panel.add_child(r_edit)

		_:
			_mission_panel.add_child(UiKit.label("Ships act autonomously.", UiKit.DIM, 12))


# --- event handlers ---

func _on_squadron_clicked(squadron_id: String) -> void:
	_selected_squadron_id = squadron_id
	_rebuild_all()


func _on_add_ship_pressed(hull_id: String) -> void:
	if _selected_squadron_id.is_empty():
		return
	RoguelikeRun.squadrons = SquadronSystem.add_hull(
		RoguelikeRun.squadrons, _selected_squadron_id, hull_id
	)
	_rebuild_all()


func _on_remove_ship_pressed(hull_id: String) -> void:
	RoguelikeRun.squadrons = SquadronSystem.remove_hull(RoguelikeRun.squadrons, hull_id)
	_rebuild_all()


func _on_new_squadron_pressed() -> void:
	RoguelikeRun.squadrons = SquadronSystem.create_squadron(
		RoguelikeRun.squadrons, "Squadron %d" % RoguelikeRun.squadrons.size()
	)
	_selected_squadron_id = RoguelikeRun.squadrons.back().get("squadron_id", "")
	_rebuild_all()


func _on_delete_squadron_pressed(squadron_id: String) -> void:
	RoguelikeRun.squadrons = SquadronSystem.delete_squadron(RoguelikeRun.squadrons, squadron_id)
	if _selected_squadron_id == squadron_id:
		_selected_squadron_id = RoguelikeRun.squadrons[0].get("squadron_id", "") if not RoguelikeRun.squadrons.is_empty() else ""
	_rebuild_all()


func _on_mission_selected(mission: String) -> void:
	if _selected_squadron_id.is_empty():
		return
	RoguelikeRun.squadrons = SquadronSystem.set_mission(
		RoguelikeRun.squadrons, _selected_squadron_id, mission, {}
	)
	_rebuild_all()


func _on_param_changed(key: String, value: Variant) -> void:
	if _selected_squadron_id.is_empty():
		return
	var sq: Dictionary = _current_squadron()
	var params: Dictionary = sq.get("mission_params", {}).duplicate()
	params[key] = value
	RoguelikeRun.squadrons = SquadronSystem.set_mission(
		RoguelikeRun.squadrons, _selected_squadron_id, sq.get("mission", SquadronData.Mission.FREE), params
	)


func _on_battle_pressed() -> void:
	done.emit()


func _on_ship_advanced_pressed(hull_id: String) -> void:
	if _doctrine_overlay != null:
		_doctrine_overlay.queue_free()
	_doctrine_overlay = DoctrinePanel.new()
	add_child(_doctrine_overlay)
	_doctrine_overlay.setup_from_roster()


# --- helpers ---

func _current_squadron() -> Dictionary:
	for sq in RoguelikeRun.squadrons:
		if sq.get("squadron_id", "") == _selected_squadron_id:
			return sq
	return {}


func _hull_by_id(hull_id: String) -> Dictionary:
	for hull in RoguelikeRun.fleet_hulls:
		if hull.get("hull_id", "") == hull_id:
			return hull
	return {}
