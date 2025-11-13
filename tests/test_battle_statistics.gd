extends GutTest

## Simple battle observation - run one battle and watch what happens

const HeadlessBattleSimulator = preload("res://scripts/test_utils/headless_battle_simulator.gd")

func test_observe_single_battle() -> void:
	var sim = HeadlessBattleSimulator.new()
	sim.time_scale = 1000.0
	add_child(sim)

	# Setup: 3 creatures per team
	sim.spawn_creature("rat", 1, Vector2(300, 300))
	sim.spawn_creature("rat", 1, Vector2(300, 360))
	sim.spawn_creature("rat", 1, Vector2(300, 420))

	sim.spawn_creature("rat", 2, Vector2(900, 300))
	sim.spawn_creature("rat", 2, Vector2(900, 360))
	sim.spawn_creature("rat", 2, Vector2(900, 420))

	# Watch the battle
	sim.start_battle()
	var result = await sim.battle_ended

	print("\n=== BATTLE RESULT ===")
	print("Outcome: %s" % result.outcome)
	print("Duration: %.2fs" % result.duration)
	print("====================\n")

	sim.queue_free()
