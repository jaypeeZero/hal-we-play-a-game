extends Node
class_name AIOpponentController

const PLAYER_SPEED = 200.0
const PLAYER_VISUAL_RADIUS = 15.0  # Visual size of player emoji (buffer for clamping)
# Arena bounds to prevent going under hand UIs
const HAND_CARD_WIDTH = 80.0
const HAND_MARGIN = 10.0
# Add visual radius so entire player visual stays within bounds
const ARENA_MIN = Vector2(HAND_MARGIN + HAND_CARD_WIDTH + PLAYER_VISUAL_RADIUS, 20.0 + PLAYER_VISUAL_RADIUS)  # 105, 35
const ARENA_MAX = Vector2(1280.0 - HAND_MARGIN - HAND_CARD_WIDTH - PLAYER_VISUAL_RADIUS, 720.0 - 20.0 - PLAYER_VISUAL_RADIUS)  # 1175, 685
const TREE_AVOIDANCE_MARGIN = 20.0  # Stay this far from trees

# Casting behavior
var cast_cooldown: float = 0.0
const CAST_INTERVAL = 0.5  # Seconds between cast attempts

func handle_movement(player: PlayerCharacter, delta: float) -> void:
	var enemy_creatures: Array = _get_enemy_creatures(player)

	# If no threats, stay in current position
	if enemy_creatures.is_empty():
		return

	# Find nearest threat
	var nearest: Node2D = _get_nearest_threat(player.global_position, enemy_creatures)
	if not nearest:
		return

	# Calculate flee direction (away from threat)
	var flee_direction: Vector2 = (player.global_position - nearest.global_position).normalized()

	# Calculate desired new position
	var desired_position: Vector2 = player.global_position + flee_direction * PLAYER_SPEED * delta

	# Check if movement would collide with trees
	if _is_position_blocked(player, desired_position):
		# Try perpendicular directions
		var perpendicular1: Vector2 = Vector2(-flee_direction.y, flee_direction.x)
		var perpendicular2: Vector2 = Vector2(flee_direction.y, -flee_direction.x)

		var pos1: Vector2 = player.global_position + perpendicular1 * PLAYER_SPEED * delta
		var pos2: Vector2 = player.global_position + perpendicular2 * PLAYER_SPEED * delta

		if not _is_position_blocked(player, pos1):
			desired_position = pos1
		elif not _is_position_blocked(player, pos2):
			desired_position = pos2
		else:
			# Can't move, stay put
			desired_position = player.global_position

	# Move to desired position
	player.global_position = desired_position

	# Clamp to arena bounds
	player.global_position = player.global_position.clamp(ARENA_MIN, ARENA_MAX)


func handle_casting(player: PlayerCharacter, enemy: PlayerCharacter,
					combat_system: CombatSystem, delta: float) -> void:
	cast_cooldown -= delta
	if cast_cooldown > 0:
		return

	# Scan hand for castable card
	for slot: int in range(5):
		var card: Medallion = player.hand.get_card(slot)
		if not card:
			continue

		var cost: float = card.get_medallion_cost()
		if player.mana >= cost:
			# Cast toward enemy player position
			combat_system.cast_from_hand(player, slot, enemy.global_position)
			cast_cooldown = CAST_INTERVAL
			return


func _get_enemy_creatures(player: PlayerCharacter) -> Array:
	var enemies: Array = []

	if not player.is_inside_tree():
		return enemies

	var all_creatures: Array = get_tree().get_nodes_in_group("creatures")

	for creature: Variant in all_creatures:
		# Only include enemy creatures (different owner_id)
		if creature.owner_id != player.player_id:
			enemies.append(creature)

	return enemies


func _get_nearest_threat(position: Vector2, creatures: Array) -> Node2D:
	var nearest: Node2D = null
	var nearest_distance: float = INF

	for creature: Variant in creatures:
		if not is_instance_valid(creature):
			continue

		var distance: float = position.distance_to(creature.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = creature

	return nearest

func _is_position_blocked(player: PlayerCharacter, position: Vector2) -> bool:
	# Check if position is too close to any tree
	if not player.is_inside_tree():
		return false

	var trees: Array = get_tree().get_nodes_in_group("terrain")
	for terrain: Variant in trees:
		if not is_instance_valid(terrain):
			continue

		var distance: float = position.distance_to(terrain.global_position)
		var min_distance: float = terrain.get_collision_radius() + TREE_AVOIDANCE_MARGIN

		if distance < min_distance:
			return true

	return false
