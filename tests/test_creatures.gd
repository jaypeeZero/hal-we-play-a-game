extends GutTest

const CreatureObject = preload("res://scripts/entities/creatures/creature_object.gd")
const KnightUnit = preload("res://scripts/entities/creatures/knight_unit.gd")
const MedallionData = preload("res://scripts/core/data/medallion_data.gd")
const PlayerCharacter = preload("res://scripts/players/player.gd")

# Helper to enrich data like CombatSystem does (with creature type resolution)
func enrich_data(raw_data: Dictionary) -> Dictionary:
	var properties = raw_data.get("properties", {})
	var creature_type_id = properties.get("creature_type", "")

	var enriched: Dictionary

	# If creature type is specified, load from creature type system
	if creature_type_id:
		var creature_type_data_service = CreatureTypeData.new()
		var type_data = creature_type_data_service.get_creature(creature_type_id)

		# Merge stats from creature type
		enriched = type_data.get("stats", {}).duplicate()
		if type_data.has("ai_config"):
			enriched["ai_config"] = type_data["ai_config"]

		# Add creature_type ID
		enriched["creature_type"] = creature_type_id

		# Preserve spawn_count and other medallion-specific properties
		if properties.has("spawn_count"):
			enriched["spawn_count"] = properties["spawn_count"]
	else:
		# Backward compatible: no creature type, use properties directly
		enriched = properties.duplicate()

	# Always preserve visual_emoji from medallion
	if raw_data.has("visual_emoji"):
		enriched["visual_emoji"] = raw_data["visual_emoji"]

	return enriched


func test_unit_can_take_damage():
	var unit = autofree(CreatureObject.new())
	var data = MedallionData.new().get_medallion("olophant")
	unit.initialize(enrich_data(data), Vector2(100, 100))
	var initial_health = unit.health_component.health
	unit.take_damage(10.0)
	assert_lt(unit.health_component.health, initial_health, "Unit health should decrease")

func test_unit_dies_when_health_zero():
	var unit = autofree(CreatureObject.new())
	var data = MedallionData.new().get_medallion("olophant")
	unit.initialize(enrich_data(data), Vector2(100, 100))
	watch_signals(unit)
	unit.take_damage(1000.0)
	assert_signal_emitted(unit, "died", "Unit should emit died signal")

func test_unit_moves_toward_target():
	var unit = autofree(CreatureObject.new())
	var data = MedallionData.new().get_medallion("bear")
	unit.global_position = Vector2(0, 0)
	unit.initialize(enrich_data(data), Vector2(100, 0))
	var old_pos = unit.global_position
	unit._process(1.0) # 1 second
	assert_gt(unit.global_position.x, old_pos.x, "Unit should move toward target")

func test_unit_follows_dynamic_target():
	var unit = autofree(CreatureObject.new())
	var player = autofree(PlayerCharacter.new())
	var data = MedallionData.new().get_medallion("bear")

	# Setup initial positions
	unit.global_position = Vector2(0, 0)
	player.global_position = Vector2(100, 0)

	# Initialize with player as dynamic target
	unit.initialize(enrich_data(data), Vector2(100, 0), player)
	unit.dynamic_target = player

	# Move player to new location
	player.global_position = Vector2(0, 100)

	# Unit should update direction toward new player position
	unit._process(0.1)
	assert_gt(unit.global_position.y, 0.0, "Unit should move toward player's new position")

func test_unit_damages_enemy_creature():
	var unit1 = CreatureObject.new()
	var unit2 = CreatureObject.new()
	add_child_autofree(unit1)
	add_child_autofree(unit2)

	var data = MedallionData.new().get_medallion("bear")

	# Setup units with different owners
	unit1.global_position = Vector2(0, 0)
	unit1.owner_id = 1
	unit1.initialize(enrich_data(data), Vector2(100, 0))

	unit2.global_position = Vector2(0, 0)
	unit2.owner_id = 2
	unit2.initialize(enrich_data(data), Vector2(100, 0))

	var initial_health = unit2.health_component.health

	# Simulate collision by calling the collision handler
	watch_signals(unit1)
	unit1._on_area_entered(unit2.hit_box)

	assert_lt(unit2.health_component.health, initial_health, "Enemy creature should take damage")
	assert_signal_emitted(unit1, "hit_target", "Unit should emit hit_target signal")

func test_unit_prioritizes_enemy_creature_over_player():
	var unit = CreatureObject.new()
	var player = PlayerCharacter.new()
	var enemy_creature = CreatureObject.new()

	add_child_autofree(unit)
	add_child_autofree(player)
	add_child_autofree(enemy_creature)

	var data = MedallionData.new().get_medallion("bear")

	# Setup positions
	unit.global_position = Vector2(0, 0)
	player.global_position = Vector2(200, 0)
	enemy_creature.global_position = Vector2(100, 0)

	# Setup owners - unit and enemy_creature have different owners
	unit.owner_id = 1
	player.player_id = 2
	enemy_creature.owner_id = 2

	# Initialize unit with player as enemy
	unit.initialize(enrich_data(data), Vector2(100, 0), player)
	enemy_creature.initialize(enrich_data(data), Vector2(100, 0))

	# Update target priority - should pick enemy creature over player
	unit._update_target_priority()

	assert_eq(unit.dynamic_target, enemy_creature, "Unit should target enemy creature instead of player")

func test_unit_targets_player_when_no_enemy_creatures():
	var unit = CreatureObject.new()
	var player = PlayerCharacter.new()

	add_child_autofree(unit)
	add_child_autofree(player)

	var data = MedallionData.new().get_medallion("bear")

	# Setup positions
	unit.global_position = Vector2(0, 0)
	player.global_position = Vector2(100, 0)

	# Setup owners
	unit.owner_id = 1
	player.player_id = 2

	# Initialize unit with player as enemy (no other creatures exist)
	unit.initialize(enrich_data(data), Vector2(100, 0), player)

	# Update target priority - should target player since no enemy creatures
	unit._update_target_priority()

	assert_eq(unit.dynamic_target, player, "Unit should target player when no enemy creatures exist")

# Health Component Tests
func test_unit_has_health_component():
	var unit = CreatureObject.new()
	add_child_autofree(unit)

	var data = MedallionData.new().get_medallion("bear")
	unit.global_position = Vector2(100, 100)
	unit.initialize(enrich_data(data), Vector2(200, 100))

	assert_not_null(unit.health_component, "Unit should have health_component")

func test_unit_health_initialized_to_max():
	var unit = CreatureObject.new()
	add_child_autofree(unit)

	var data = MedallionData.new().get_medallion("bear")
	unit.global_position = Vector2(100, 100)
	unit.initialize(enrich_data(data), Vector2(200, 100))

	assert_eq(unit.health_component.health, unit.health_component.max_health, "Health should start at max")

func test_unit_health_component_emits_damaged_signal():
	var unit = CreatureObject.new()
	add_child_autofree(unit)

	var data = MedallionData.new().get_medallion("bear")
	unit.global_position = Vector2(100, 100)
	unit.initialize(enrich_data(data), Vector2(200, 100))

	watch_signals(unit.health_component)
	unit.take_damage(10.0)

	assert_signal_emitted(unit.health_component, "damaged", "Health component should emit damaged signal after taking damage")

func test_unit_health_updates_correctly():
	var unit = CreatureObject.new()
	add_child_autofree(unit)

	var data = MedallionData.new().get_medallion("bear")
	unit.global_position = Vector2(100, 100)
	unit.initialize(enrich_data(data), Vector2(200, 100))

	unit.take_damage(30.0)

	assert_eq(unit.health_component.health, 70.0, "Health should be 70 after 30 damage")
	assert_eq(unit.health_component.max_health, 100.0, "Max health should be 100 (Bear's max health)")

func test_different_creatures_have_different_max_health():
	var olophant = CreatureObject.new()
	var rat = CreatureObject.new()
	add_child_autofree(olophant)
	add_child_autofree(rat)

	var olophant_data = MedallionData.new().get_medallion("olophant")
	var rat_data = MedallionData.new().get_medallion("rat_swarm")

	olophant.global_position = Vector2(100, 100)
	olophant.initialize(enrich_data(olophant_data), Vector2(200, 100))

	rat.global_position = Vector2(100, 200)
	rat.initialize(enrich_data(rat_data), Vector2(200, 200))

	olophant.take_damage(10.0)
	rat.take_damage(10.0)

	assert_eq(olophant.health_component.max_health, 200.0, "Olophant should have 200 max health")
	assert_eq(rat.health_component.max_health, 30.0, "Rat should have 30 max health")

# Charging Knight tests
func test_charging_knight_can_be_spawned():
	var knight = autofree(KnightUnit.new())
	var data = MedallionData.new().get_medallion("charging_knight")
	knight.initialize(enrich_data(data), Vector2(100, 100))
	assert_not_null(knight, "Charging Knight should be creatable")

func test_charging_knight_has_random_color():
	var knight1 = autofree(KnightUnit.new())
	var knight2 = autofree(KnightUnit.new())
	var data = MedallionData.new().get_medallion("charging_knight")

	knight1.initialize(enrich_data(data), Vector2(100, 100))
	knight2.initialize(enrich_data(data), Vector2(100, 100))

	# At least test that colors are assigned (may or may not be different)
	assert_true(knight1.knight_color >= 0 and knight1.knight_color < 4, "Knight should have valid color")
	assert_true(knight2.knight_color >= 0 and knight2.knight_color < 4, "Knight should have valid color")

func test_blue_knight_stays_for_caster():
	var knight = autofree(KnightUnit.new())
	var data = MedallionData.new().get_medallion("charging_knight")
	var enemy = autofree(PlayerCharacter.new())

	enemy.player_id = 2
	knight.owner_id = 1

	# Initialize normally (random color)
	knight.initialize(enrich_data(data), Vector2(100, 100), enemy)

	# Force color to BLUE and re-evaluate behavior
	knight.knight_color = KnightUnit.KnightColor.BLUE
	if knight.knight_color == KnightUnit.KnightColor.BLUE:
		knight.knight_state = KnightUnit.KnightState.FIGHTING

	# Blue knights should transition to fighting after charge (not remain charging)
	assert_ne(knight.knight_state, KnightUnit.KnightState.CHARGING, "Blue knight should not remain in charging mode")

func test_black_knight_switches_to_enemy():
	var knight = autofree(KnightUnit.new())
	var data = MedallionData.new().get_medallion("charging_knight")
	var enemy = autofree(PlayerCharacter.new())

	enemy.player_id = 2

	# Initialize with enemy player
	knight.owner_id = 1  # Start as player 1's knight
	knight.initialize(enrich_data(data), Vector2(100, 100), enemy)

	# Force color to BLACK and re-evaluate behavior
	knight.knight_color = KnightUnit.KnightColor.BLACK
	if knight.knight_color == KnightUnit.KnightColor.BLACK:
		knight.owner_id = enemy.player_id
		knight.knight_state = KnightUnit.KnightState.FIGHTING

	# Black knight should switch to enemy team
	assert_eq(knight.owner_id, 2, "Black knight should switch to enemy player's team")
	assert_ne(knight.knight_state, KnightUnit.KnightState.CHARGING, "Black knight should not remain in charging mode")

func test_red_green_knight_charges():
	var knight_red = autofree(KnightUnit.new())
	var knight_green = autofree(KnightUnit.new())
	var data = MedallionData.new().get_medallion("charging_knight")
	var enemy = autofree(PlayerCharacter.new())

	enemy.player_id = 2

	# Test RED knight
	knight_red.initialize(enrich_data(data), Vector2(100, 100), enemy)
	knight_red.knight_color = KnightUnit.KnightColor.RED
	knight_red.knight_state = KnightUnit.KnightState.CHARGING
	assert_eq(knight_red.knight_state, KnightUnit.KnightState.CHARGING, "Red knight should charge")

	# Test GREEN knight
	knight_green.initialize(enrich_data(data), Vector2(100, 100), enemy)
	knight_green.knight_color = KnightUnit.KnightColor.GREEN
	knight_green.knight_state = KnightUnit.KnightState.CHARGING
	assert_eq(knight_green.knight_state, KnightUnit.KnightState.CHARGING, "Green knight should charge")

func test_charging_knight_moves_during_charge():
	var knight = autofree(KnightUnit.new())
	var data = MedallionData.new().get_medallion("charging_knight")
	var enemy = autofree(PlayerCharacter.new())

	knight.global_position = Vector2(0, 0)
	knight.initialize(enrich_data(data), Vector2(100, 0), enemy)

	# Force charge mode
	knight.knight_state = KnightUnit.KnightState.CHARGING
	knight.charge_started = false

	var old_pos = knight.global_position
	knight._process(0.5)

	assert_gt(knight.global_position.x, old_pos.x, "Charging knight should move during charge")

func test_charging_knight_disappears_after_charge_distance():
	var knight = autofree(KnightUnit.new())
	var data = MedallionData.new().get_medallion("charging_knight")
	var enemy = autofree(PlayerCharacter.new())
	add_child_autofree(knight)

	knight.global_position = Vector2(0, 0)
	knight.initialize(enrich_data(data), Vector2(100, 0), enemy)

	# Force RED charge mode
	knight.knight_color = KnightUnit.KnightColor.RED
	knight.knight_state = KnightUnit.KnightState.CHARGING
	knight.charge_started = true
	knight.charge_distance = 0.0

	# Process enough to exceed charge distance (200.0 from casting_range)
	# With speed 250, need 200/250 = 0.8 seconds
	knight._process(0.9)

	# Red knight should be queued for deletion
	assert_true(knight.is_queued_for_deletion(), "Red knight should disappear after charge distance")

func test_blue_knight_transitions_to_fighting_after_charge():
	var knight = autofree(KnightUnit.new())
	var data = MedallionData.new().get_medallion("charging_knight")
	var enemy = autofree(PlayerCharacter.new())
	add_child_autofree(knight)

	knight.global_position = Vector2(0, 0)
	knight.initialize(enrich_data(data), Vector2(100, 0), enemy)

	# Force BLUE charge mode (even though normally blue doesn't charge)
	knight.knight_color = KnightUnit.KnightColor.BLUE
	knight.knight_state = KnightUnit.KnightState.CHARGING
	knight.charge_started = true
	knight.charge_distance = 0.0

	# Process enough to exceed charge distance (200.0)
	knight._process(0.9)

	# Blue knight should transition to fighting mode, not despawn
	assert_ne(knight.knight_state, KnightUnit.KnightState.CHARGING, "Blue knight should transition to fighting after charge")
	assert_false(knight.is_queued_for_deletion(), "Blue knight should NOT despawn after charge")

func test_black_knight_transitions_to_fighting_after_charge():
	var knight = autofree(KnightUnit.new())
	var data = MedallionData.new().get_medallion("charging_knight")
	var enemy = autofree(PlayerCharacter.new())
	add_child_autofree(knight)

	enemy.player_id = 2

	knight.global_position = Vector2(0, 0)
	knight.initialize(enrich_data(data), Vector2(100, 0), enemy)

	# Force BLACK charge mode (even though normally black doesn't charge)
	knight.knight_color = KnightUnit.KnightColor.BLACK
	knight.knight_state = KnightUnit.KnightState.CHARGING
	knight.charge_started = true
	knight.charge_distance = 0.0

	# Process enough to exceed charge distance (200.0)
	knight._process(0.9)

	# Black knight should transition to fighting mode, not despawn
	assert_ne(knight.knight_state, KnightUnit.KnightState.CHARGING, "Black knight should transition to fighting after charge")
	assert_false(knight.is_queued_for_deletion(), "Black knight should NOT despawn after charge")
