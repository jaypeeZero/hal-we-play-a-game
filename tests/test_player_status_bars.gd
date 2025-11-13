extends GutTest

# Tests for PlayerStatusBars UI component

var PlayerStatusBars = load("res://scripts/ui/status_bars/player_status_bars.gd")
var status_bars: Node2D

func before_each():
	status_bars = PlayerStatusBars.new()
	add_child_autofree(status_bars)

func test_has_health_bar():
	assert_not_null(status_bars.health_bar, "Should have health_bar instance")
	assert_not_null(status_bars.health_bar.get_bar(), "HealthBar should have ProgressBar")

func test_has_mana_bar():
	assert_not_null(status_bars.mana_bar, "Should have mana_bar instance")
	assert_not_null(status_bars.mana_bar.get_bar(), "ManaBar should have ProgressBar")

func test_health_bar_shows_correct_value():
	status_bars.set_health(75, 100)
	var health_bar = status_bars.health_bar.get_bar()
	assert_eq(health_bar.value, 75.0, "Health bar should show 75")
	assert_eq(health_bar.max_value, 100.0, "Health bar max should be 100")

func test_mana_bar_shows_correct_value():
	status_bars.set_mana(50, 100)
	var mana_bar = status_bars.mana_bar.get_bar()
	assert_eq(mana_bar.value, 50.0, "Mana bar should show 50")
	assert_eq(mana_bar.max_value, 100.0, "Mana bar max should be 100")

func test_health_bar_updates():
	status_bars.set_health(100, 100)
	status_bars.set_health(25, 100)
	var health_bar = status_bars.health_bar.get_bar()
	assert_eq(health_bar.value, 25.0, "Health bar should update to 25")

func test_mana_bar_updates():
	status_bars.set_mana(100, 100)
	status_bars.set_mana(10, 100)
	var mana_bar = status_bars.mana_bar.get_bar()
	assert_eq(mana_bar.value, 10.0, "Mana bar should update to 10")

func test_bars_positioned_at_bottom_corners():
	var health_bar = status_bars.health_bar.get_bar()
	var mana_bar = status_bars.mana_bar.get_bar()
	# Health bar should be on the left
	assert_true(health_bar.position.x < 0, "Health bar should be positioned to the left")
	# Mana bar should be on the right
	assert_true(mana_bar.position.x > 0, "Mana bar should be positioned to the right")
	# Both should be at the bottom
	assert_true(health_bar.position.y > 0, "Health bar should be positioned below center")
	assert_true(mana_bar.position.y > 0, "Mana bar should be positioned below center")
