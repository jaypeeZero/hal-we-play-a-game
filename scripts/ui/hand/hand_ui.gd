extends Control
class_name HandUI

const CardUI = preload("res://scripts/ui/hand/card_ui.gd")
const Hand = preload("res://scripts/core/game_systems/hand.gd")

const BASE_CARD_SPACING = 5
const BASE_MARGIN_FROM_EDGE = 10

var _hand: Hand
var _cards: Array[CardUI] = []
var _is_left_side: bool = true
var _keybinds: Array[String] = []
var _player_idx: int = -1
var _viewport_size: Vector2 = Vector2(1280, 720)  # Default battlefield size

func _ready() -> void:
	get_viewport().size_changed.connect(_on_viewport_resized)

func _exit_tree() -> void:
	if _hand:
		_hand.card_played.disconnect(_on_card_played)
		_hand.card_drawn.disconnect(_on_card_drawn)

func initialize(hand: Hand, is_left: bool, keybinds: Array[String], player_idx: int = -1, input_handler: InputHandler = null, viewport_size: Vector2 = Vector2.ZERO) -> void:
	_hand = hand
	_is_left_side = is_left
	_keybinds = keybinds
	_player_idx = player_idx

	# Use provided viewport size or default to actual viewport
	if viewport_size != Vector2.ZERO:
		_viewport_size = viewport_size
	else:
		_viewport_size = get_viewport_rect().size

	# Set size to cover the entire viewport (don't clip children)
	custom_minimum_size = _viewport_size
	size = _viewport_size

	# Connect to hand signals
	_hand.card_played.connect(_on_card_played)
	_hand.card_drawn.connect(_on_card_drawn)

	# Connect to input handler selection changes if provided
	if input_handler and player_idx >= 0:
		input_handler.selection_changed.connect(_on_selection_changed)

	_setup_cards()
	_position_hand()

func _get_ui_scale() -> float:
	var viewport_height: float = _viewport_size.y
	return viewport_height / 720.0

func _get_card_dimensions() -> Vector2:
	var scale_factor: float = _get_ui_scale()
	return Vector2(80, 110) * scale_factor

func _get_card_spacing() -> float:
	return BASE_CARD_SPACING * _get_ui_scale()

func _get_margin() -> float:
	return BASE_MARGIN_FROM_EDGE * _get_ui_scale()

func _on_viewport_resized() -> void:
	_position_hand()
	for card: CardUI in _cards:
		if card:
			card.update_scale(_get_ui_scale())

func _setup_cards() -> void:
	for i: int in range(5):
		var card_ui: CardUI = CardUI.new()
		add_child(card_ui)
		_cards.append(card_ui)
		card_ui.update_scale(_get_ui_scale())

		var medallion: Medallion = _hand.get_card(i)
		if medallion:
			card_ui.set_medallion(medallion)

		if i < _keybinds.size():
			card_ui.set_keybind(_keybinds[i])

func _position_hand() -> void:
	# Get viewport size and scaled dimensions
	var viewport_size: Vector2 = _viewport_size
	var card_dimensions: Vector2 = _get_card_dimensions()
	var card_height: float = card_dimensions.y
	var card_width: float = card_dimensions.x
	var spacing: float = _get_card_spacing()
	var margin: float = _get_margin()
	var total_height: float = (card_height + spacing) * 5 - spacing

	# Center vertically
	var start_y: float = (viewport_size.y - total_height) / 2

	for i: int in range(_cards.size()):
		var card: CardUI = _cards[i]
		var y_pos: float = start_y + i * (card_height + spacing)

		if _is_left_side:
			card.position = Vector2(margin, y_pos)
		else:
			card.position = Vector2(viewport_size.x - card_width - margin, y_pos)

func _on_card_played(slot: int, medallion: Medallion) -> void:
	if slot < 0 or slot >= _cards.size():
		return

	# Animate suck out
	await _cards[slot].animate_suck_out()

func _on_card_drawn(slot: int, medallion: Medallion) -> void:
	if slot < 0 or slot >= _cards.size():
		return

	# Update the card with new medallion
	_cards[slot].set_medallion(medallion)

	# Animate blorp in
	await _cards[slot].animate_blorp_in()

func _on_selection_changed(player_idx: int, slot: int) -> void:
	# Only update if this signal is for our player
	if player_idx != _player_idx:
		return

	# Deselect all cards
	for card: CardUI in _cards:
		if card:
			card.set_selected(false)

	# Select the specified slot (slot is -1 if deselecting all)
	if slot >= 0 and slot < _cards.size():
		_cards[slot].set_selected(true)
