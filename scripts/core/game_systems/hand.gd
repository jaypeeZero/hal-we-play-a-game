extends RefCounted
class_name Hand

signal card_played(slot: int, medallion: Medallion)
signal card_drawn(slot: int, medallion: Medallion)

const Medallion = preload("res://scripts/core/game_systems/medallion.gd")
const Satchel = preload("res://scripts/core/game_systems/satchel.gd")

const HAND_SIZE = 5

var _cards: Array[Medallion] = []
var _satchel: Satchel

func _init(satchel: Satchel) -> void:
	_satchel = satchel

func draw() -> Medallion:
	"""Draw a card from the satchel and add it to the hand."""
	var medallion: Medallion = _satchel.draw()
	if medallion and _cards.size() < HAND_SIZE:
		_cards.append(medallion)
	return medallion

func get_card(slot: int) -> Medallion:
	if slot < 0 or slot >= _cards.size():
		return null
	return _cards[slot]

func get_card_count() -> int:
	return _cards.size()

func play_card(slot: int) -> Medallion:
	if slot < 0 or slot >= _cards.size():
		return null

	var played_card: Medallion = _cards[slot]
	card_played.emit(slot, played_card)

	# Draw replacement
	var new_card: Medallion = _satchel.draw()
	if new_card:
		_cards[slot] = new_card
		card_drawn.emit(slot, new_card)

	return played_card
