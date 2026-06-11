extends Control

## Fleet Editor UI - Allows players to configure the ships for each team

@onready var _team0_fighter: SpinBox = %Team0FighterSpinBox
@onready var _team0_heavy_fighter: SpinBox = %Team0HeavyFighterSpinBox
@onready var _team0_torpedo_boat: SpinBox = %Team0TorpedoBoatSpinBox
@onready var _team0_corvette: SpinBox = %Team0CorvetteSpinBox
@onready var _team0_capital: SpinBox = %Team0CapitalSpinBox

@onready var _team1_fighter: SpinBox = %Team1FighterSpinBox
@onready var _team1_heavy_fighter: SpinBox = %Team1HeavyFighterSpinBox
@onready var _team1_torpedo_boat: SpinBox = %Team1TorpedoBoatSpinBox
@onready var _team1_corvette: SpinBox = %Team1CorvetteSpinBox
@onready var _team1_capital: SpinBox = %Team1CapitalSpinBox

@onready var _status_label: Label = %StatusLabel
@onready var _crew_tactics_holder: Control = %CrewTacticsHolder

var _doctrine_panel: DoctrinePanel = null


func _ready() -> void:
	_load_fleet_data()
	# Crew Tactics (doctrine) is run state: only show it during a Roguelike
	# run, where the crew roster and doctrine already exist.
	_crew_tactics_holder.visible = RoguelikeRun.active
	if RoguelikeRun.active:
		_doctrine_panel = DoctrinePanel.new()
		_crew_tactics_holder.add_child(_doctrine_panel)
		_doctrine_panel.setup_from_roster()


func _load_fleet_data() -> void:
	var team0_fleet := FleetDataManager.load_fleet(0)
	var team1_fleet := FleetDataManager.load_fleet(1)

	_team0_fighter.value = team0_fleet.get("fighter", 1)
	_team0_heavy_fighter.value = team0_fleet.get("heavy_fighter", 0)
	_team0_torpedo_boat.value = team0_fleet.get("torpedo_boat", 0)
	_team0_corvette.value = team0_fleet.get("corvette", 0)
	_team0_capital.value = team0_fleet.get("capital", 0)

	_team1_fighter.value = team1_fleet.get("fighter", 1)
	_team1_heavy_fighter.value = team1_fleet.get("heavy_fighter", 0)
	_team1_torpedo_boat.value = team1_fleet.get("torpedo_boat", 0)
	_team1_corvette.value = team1_fleet.get("corvette", 0)
	_team1_capital.value = team1_fleet.get("capital", 0)


func _get_team0_fleet() -> Dictionary:
	return {
		"fighter": int(_team0_fighter.value),
		"heavy_fighter": int(_team0_heavy_fighter.value),
		"torpedo_boat": int(_team0_torpedo_boat.value),
		"corvette": int(_team0_corvette.value),
		"capital": int(_team0_capital.value)
	}


func _get_team1_fleet() -> Dictionary:
	return {
		"fighter": int(_team1_fighter.value),
		"heavy_fighter": int(_team1_heavy_fighter.value),
		"torpedo_boat": int(_team1_torpedo_boat.value),
		"corvette": int(_team1_corvette.value),
		"capital": int(_team1_capital.value)
	}


func _on_save_pressed() -> void:
	var team0_fleet := _get_team0_fleet()
	var team1_fleet := _get_team1_fleet()

	var team0_saved := FleetDataManager.save_fleet(0, team0_fleet)
	var team1_saved := FleetDataManager.save_fleet(1, team1_fleet)

	if team0_saved and team1_saved:
		_status_label.text = "Fleets saved successfully!"
		_status_label.modulate = Color.GREEN
		# In a run, rebuild the crew roster to match the new counts (keeping
		# doctrine for surviving crew) and re-sync the Crew Tactics panel.
		if RoguelikeRun.active:
			RoguelikeRun.reconcile_roster_to_counts(team0_fleet)
			RoguelikeRun.enemy_fleet = team1_fleet
			if _doctrine_panel != null:
				_doctrine_panel.refresh_roster()
	else:
		_status_label.text = "Error saving fleets!"
		_status_label.modulate = Color.RED

	# Clear status after a delay
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
