extends GutTest

const Chasm = preload("res://scripts/entities/terrain/chasm.gd")
const TerrainData = preload("res://scripts/core/data/terrain_data.gd")
const CreatureObject = preload("res://scripts/entities/creatures/creature_object.gd")

var battlefield: Node2D
var chasm: Chasm

func before_each():
	battlefield = add_child_autofree(Node2D.new())
	chasm = Chasm.new()
	battlefield.add_child(chasm)
	var data = TerrainData.get_data(TerrainData.TerrainType.CHASM)
	chasm.initialize(data, Vector2(300, 300))

func test_chasm_spawns_at_position():
	assert_eq(chasm.global_position, Vector2(300, 300))

func test_chasm_has_collision_area():
	assert_not_null(chasm.collision_area)
	assert_eq(chasm.get_collision_radius(), 30.0)

func test_chasm_is_in_terrain_group():
	assert_true(chasm.is_in_group("terrain"))

func test_chasm_has_visual_children():
	# Should have collision area and visual components
	assert_gt(chasm.get_child_count(), 0)

func test_chasm_removes_creature():
	# Create a mock creature with CreatureObject type
	var creature = CreatureObject.new()
	creature.name = "TestCreature"
	battlefield.add_child(creature)
	creature.global_position = Vector2(300, 300)

	# Add HitBox to creature
	var hitbox = Area2D.new()
	hitbox.name = "HitBox"
	creature.add_child(hitbox)

	# Watch for signal
	watch_signals(chasm)

	# Simulate entering chasm
	chasm._on_area_entered(hitbox)

	# Creature should be queued for deletion
	assert_signal_emitted(chasm, "object_entered")

	# Queue the frame to let queue_free take effect
	await get_tree().process_frame
	assert_false(is_instance_valid(creature), "Creature should be queued for deletion")

func test_chasm_terrain_type():
	assert_eq(chasm.terrain_type, "chasm")
