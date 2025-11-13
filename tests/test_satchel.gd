extends GutTest

const Satchel = preload("res://scripts/core/game_systems/satchel.gd")

var satchel: Satchel

func before_each():
	# Use empty string to trigger default loadout (not tied to mutable game data)
	satchel = Satchel.new()

func test_satchel_initializes_with_31_medallions():
	assert_eq(satchel.get_remaining_count(), 31, "Satchel should start with 31 medallions (default loadout)")


func test_draw_returns_medallion():
	var medallion = satchel.draw()
	assert_not_null(medallion, "Draw should return a medallion")

func test_draw_reduces_count():
	var initial_count = satchel.get_remaining_count()
	satchel.draw()
	assert_eq(satchel.get_remaining_count(), initial_count - 1, "Drawing should reduce count")

func test_draw_returns_null_when_empty():
	var total_cards = satchel.get_remaining_count()
	for i in range(total_cards):
		satchel.draw()
	var empty_draw = satchel.draw()
	assert_null(empty_draw, "Drawing from empty satchel should return null")

func test_draw_is_random():
	var first_id = satchel.draw().id
	var found_different = false

	# Try up to 10 draws to find a different type (statistically very likely)
	for i in range(10):
		var next_id = satchel.draw().id
		if next_id != first_id:
			found_different = true
			break

	assert_true(found_different, "Draws should be random (not always same type)")
