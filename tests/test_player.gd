extends GutTest

const Player = preload("res://scripts/players/player.gd")

var player: Node2D

func before_each():
	player = autofree(Player.new())
	player._ready()


func test_player_can_take_damage():
	player.take_damage(20.0)
	assert_eq(player.health_component.health, 80.0, "Player should have 80 health after taking 20 damage")

func test_player_emits_damaged_signal():
	watch_signals(player.health_component)
	player.take_damage(10.0)
	assert_signal_emitted(player.health_component, "damaged", "Player should emit damaged signal")

func test_player_dies_when_health_reaches_zero():
	watch_signals(player.health_component)
	player.take_damage(100.0)
	assert_signal_emitted(player.health_component, "died", "Player should emit died signal when health reaches 0")

func test_player_health_cannot_go_below_zero():
	player.take_damage(150.0)
	assert_eq(player.health_component.health, 0.0, "Player health should not go below 0")

func test_player_mana_regenerates():
	player.mana = 0.0
	player._process(1.0) # Simulate 1 second
	assert_gt(player.mana, 0.0, "Mana should regenerate over time")

func test_player_mana_does_not_exceed_max():
	player.mana = 95.0
	player._process(10.0) # Simulate 10 seconds
	assert_eq(player.mana, 100.0, "Mana should not exceed max_mana")
