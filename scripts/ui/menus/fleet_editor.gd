extends Control

## Fleet Editor UI - Allows players to configure the ships for each team

@onready var _team0_fighter: SpinBox = %Team0FighterSpinBox
@onready var _team0_corvette: SpinBox = %Team0CorvetteSpinBox
@onready var _team0_capital: SpinBox = %Team0CapitalSpinBox

@onready var _team1_fighter: SpinBox = %Team1FighterSpinBox
@onready var _team1_corvette: SpinBox = %Team1CorvetteSpinBox
@onready var _team1_capital: SpinBox = %Team1CapitalSpinBox

@onready var _status_label: Label = %StatusLabel


func _ready() -> void:
	_load_fleet_data()


func _load_fleet_data() -> void:
	var team0_fleet := FleetDataManager.load_fleet(0)
	var team1_fleet := FleetDataManager.load_fleet(1)

	_team0_fighter.value = team0_fleet.get("fighter", 1)
	_team0_corvette.value = team0_fleet.get("corvette", 0)
	_team0_capital.value = team0_fleet.get("capital", 0)

	_team1_fighter.value = team1_fleet.get("fighter", 1)
	_team1_corvette.value = team1_fleet.get("corvette", 0)
	_team1_capital.value = team1_fleet.get("capital", 0)


func _get_team0_fleet() -> Dictionary:
	return {
		"fighter": int(_team0_fighter.value),
		"corvette": int(_team0_corvette.value),
		"capital": int(_team0_capital.value)
	}


func _get_team1_fleet() -> Dictionary:
	return {
		"fighter": int(_team1_fighter.value),
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
	else:
		_status_label.text = "Error saving fleets!"
		_status_label.modulate = Color.RED

	# Clear status after a delay
	var timer := get_tree().create_timer(2.0)
	timer.timeout.connect(_clear_status)


func _clear_status() -> void:
	_status_label.text = ""


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
