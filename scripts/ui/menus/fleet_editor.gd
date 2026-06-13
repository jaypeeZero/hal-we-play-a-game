extends OverlayScreen

## Fleet Editor: configure ship counts for each team and (during a roguelite
## run) edit crew doctrine. All chrome is code-built via OverlayScreen; the
## .tscn is a minimal root shell.
## Lifecycle: standalone scene — Back calls change_scene_to_file.

const SHIP_TYPES_TEAM := ["fighter", "heavy_fighter", "torpedo_boat", "corvette", "capital"]
const SHIP_TYPE_LABELS := {
	"fighter": "Fighters",
	"heavy_fighter": "Heavy Fighters",
	"torpedo_boat": "Torpedo Boats",
	"corvette": "Corvettes",
	"capital": "Capital Ships",
}
const SPINBOX_MAX := {
	"fighter": 20, "heavy_fighter": 15, "torpedo_boat": 15,
	"corvette": 10, "capital": 5
}

var _team0_spins: Dictionary = {}  # ship_type -> SpinBox
var _team1_spins: Dictionary = {}
var _status_label: Label
var _doctrine_panel: DoctrinePanel = null


func _ready() -> void:
	build_chrome()
	var topbar := _build_topbar()
	var body_node := _build_body()
	_build_footer_buttons()
	_finalize_chrome(topbar, body_node)
	_load_fleet_data()

	# Doctrine panel only makes sense during an active run.
	if RoguelikeRun.active:
		var doctrine_holder := body_node.get_child(2)  # third column
		_doctrine_panel = DoctrinePanel.new()
		doctrine_holder.add_child(_doctrine_panel)
		_doctrine_panel.setup_from_roster()


# UI CONSTRUCTION

func _build_topbar() -> Control:
	var bar := UiKit.card(UiKit.PANEL_2, UiKit.LINE, 14)
	bar.add_child(UiKit.label("EDIT FLEETS", UiKit.INK, 16))
	return bar


func _build_body() -> Control:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 40)

	hbox.add_child(_build_team_panel("TEAM 0 (Player)", _team0_spins, UiKit.GOOD))

	var vsep := VSeparator.new()
	hbox.add_child(vsep)

	hbox.add_child(_build_team_panel("TEAM 1 (Enemy)", _team1_spins, UiKit.BAD))

	# Third column: crew tactics (doctrine) — conditionally populated in _ready.
	var doctrine_holder := VBoxContainer.new()
	doctrine_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(doctrine_holder)

	return hbox


func _build_team_panel(title: String, spins: Dictionary, header_color: Color) -> Control:
	var panel := UiKit.card()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	panel.add_child(vbox)

	var header := UiKit.label(title, header_color, 24)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	for ship_type in SHIP_TYPES_TEAM:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 20)
		var lbl := UiKit.label(SHIP_TYPE_LABELS[ship_type], UiKit.INK)
		lbl.custom_minimum_size = Vector2(150, 0)
		row.add_child(lbl)
		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = SPINBOX_MAX[ship_type]
		spin.value = 0
		row.add_child(spin)
		spins[ship_type] = spin
		vbox.add_child(row)

	return panel


func _build_footer_buttons() -> void:
	_status_label = UiKit.label("", UiKit.GOOD)
	footer.add_child(_status_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)

	if RoguelikeRun.has_fleet():
		var manage := UiKit.style_button(_make_button("Manage Crew"), "ghost")
		manage.pressed.connect(func(): CrewManagementScreen.open(self))
		footer.add_child(manage)

	var back := UiKit.style_button(_make_button("Back"), "ghost")
	back.pressed.connect(_on_back_pressed)
	footer.add_child(back)

	var save := UiKit.style_button(_make_button("Save Fleets"), "primary")
	save.custom_minimum_size = Vector2(150, 40)
	save.pressed.connect(_on_save_pressed)
	footer.add_child(save)


# DATA

func _load_fleet_data() -> void:
	var team0_fleet := FleetDataManager.load_fleet(0)
	var team1_fleet := FleetDataManager.load_fleet(1)
	for ship_type in SHIP_TYPES_TEAM:
		_team0_spins[ship_type].value = team0_fleet.get(ship_type, 0)
		_team1_spins[ship_type].value = team1_fleet.get(ship_type, 0)


func _get_team_fleet(spins: Dictionary) -> Dictionary:
	var fleet := {}
	for ship_type in SHIP_TYPES_TEAM:
		fleet[ship_type] = int(spins[ship_type].value)
	return fleet


func _on_save_pressed() -> void:
	var team0_fleet := _get_team_fleet(_team0_spins)
	var team1_fleet := _get_team_fleet(_team1_spins)

	var team0_saved := FleetDataManager.save_fleet(0, team0_fleet)
	var team1_saved := FleetDataManager.save_fleet(1, team1_fleet)

	if team0_saved and team1_saved:
		_status_label.text = "Fleets saved successfully!"
		_status_label.add_theme_color_override("font_color", UiKit.GOOD)
		if RoguelikeRun.active:
			RoguelikeRun.reconcile_roster_to_counts(team0_fleet)
			RoguelikeRun.enemy_fleet = team1_fleet
			if _doctrine_panel != null:
				_doctrine_panel.refresh_roster()
	else:
		_status_label.text = "Error saving fleets!"
		_status_label.add_theme_color_override("font_color", UiKit.BAD)

	var timer := get_tree().create_timer(2.0)
	timer.timeout.connect(_clear_status)


func _clear_status() -> void:
	_status_label.text = ""


func _on_back_pressed() -> void:
	var return_scene := RoguelikeRun.editor_return_scene
	if return_scene != "":
		RoguelikeRun.editor_return_scene = ""
		get_tree().change_scene_to_file(return_scene)
	else:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _make_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	return btn
