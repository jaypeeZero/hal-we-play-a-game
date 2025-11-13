extends GutTest

const Boulder = preload("res://scripts/entities/terrain/boulder.gd")
const TerrainData = preload("res://scripts/core/data/terrain_data.gd")
const CreatureObject = preload("res://scripts/entities/creatures/creature_object.gd")

var battlefield: Node2D
var boulder: Boulder

func before_each():
	battlefield = add_child_autofree(Node2D.new())
	boulder = Boulder.new()
	battlefield.add_child(boulder)
	var data = TerrainData.get_data(TerrainData.TerrainType.BOULDER)
	boulder.initialize(data, Vector2(400, 400))

func test_boulder_spawns_at_position():
	assert_eq(boulder.global_position, Vector2(400, 400))

func test_boulder_collision_radius():
	assert_eq(boulder.get_collision_radius(), 20.0)

func test_boulder_is_in_terrain_group():
	assert_true(boulder.is_in_group("terrain"))

func test_boulder_terrain_type():
	assert_eq(boulder.terrain_type, "boulder")

func test_boulder_collision_detection():
	# Create a mock creature
	var creature = CreatureObject.new()
	creature.name = "TestCreature"
	battlefield.add_child(creature)
	creature.global_position = Vector2(400, 400)

	# Add HitBox
	var hitbox = Area2D.new()
	hitbox.name = "HitBox"
	creature.add_child(hitbox)

	# Watch for signal
	watch_signals(boulder)

	# Simulate entering boulder
	boulder._on_area_entered(hitbox)

	# Should emit object_entered signal
	assert_signal_emitted(boulder, "object_entered")

	# Creature should NOT be deleted (unlike chasm)
	assert_true(is_instance_valid(creature), "Creature should not be deleted by boulder")
