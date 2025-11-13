extends Control
class_name EndGameScreen

@onready var winner_label: Label = %WinnerLabel
@onready var duration_label: Label = %DurationLabel
@onready var p1_damage_label: Label = %P1DamageLabel
@onready var p2_damage_label: Label = %P2DamageLabel
@onready var p1_creatures_label: Label = %P1CreaturesLabel
@onready var p2_creatures_label: Label = %P2CreaturesLabel
@onready var p1_spells_label: Label = %P1SpellsLabel
@onready var p2_spells_label: Label = %P2SpellsLabel
@onready var play_again_button: Button = %PlayAgainButton
@onready var main_menu_button: Button = %MainMenuButton

# Player colors matching game theme
const PLAYER1_COLOR: Color = Color(0.3, 0.5, 1.0)  # Blue
const PLAYER2_COLOR: Color = Color(1.0, 0.3, 0.3)  # Red

func _ready() -> void:
	play_again_button.pressed.connect(_on_play_again_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)

func setup(winner_id: int, stats: Dictionary) -> void:
	# Set winner text with color
	winner_label.text = "Player %d Wins!" % winner_id
	winner_label.modulate = PLAYER1_COLOR if winner_id == 1 else PLAYER2_COLOR

	# Format and display duration
	var duration: float = stats.get("duration", 0.0) as float
	var minutes: int = int(duration / 60.0)
	var seconds: float = fmod(duration, 60.0)
	duration_label.text = "Match Duration: %d:%05.2f" % [minutes, seconds]

	# Display stats
	p1_damage_label.text = "%.0f damage dealt" % (stats.get("player1_damage_dealt", 0.0) as float)
	p2_damage_label.text = "%.0f damage dealt" % (stats.get("player2_damage_dealt", 0.0) as float)
	p1_creatures_label.text = "%d creatures summoned" % (stats.get("player1_creatures_spawned", 0) as int)
	p2_creatures_label.text = "%d creatures summoned" % (stats.get("player2_creatures_spawned", 0) as int)
	p1_spells_label.text = "%d spells cast" % (stats.get("player1_spells_cast", 0) as int)
	p2_spells_label.text = "%d spells cast" % (stats.get("player2_spells_cast", 0) as int)

func _on_play_again_pressed() -> void:
	# Defer scene change to ensure this screen is freed first
	get_tree().call_deferred("change_scene_to_file", "res://scenes/battlefield.tscn")
	queue_free()

func _on_main_menu_pressed() -> void:
	# Defer scene change to ensure this screen is freed first
	get_tree().call_deferred("change_scene_to_file", "res://scenes/main_menu.tscn")
	queue_free()
