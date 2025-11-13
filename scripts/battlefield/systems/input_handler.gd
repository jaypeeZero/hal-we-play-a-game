extends Node
class_name InputHandler

const PLAYER_SPEED = 200.0
const PLAYER_COLLISION_RADIUS = 10.0
const PLAYER_VISUAL_RADIUS = 15.0  # Visual size of player emoji (buffer for clamping)
const MedallionData = preload("res://scripts/core/data/medallion_data.gd")

# Hand UI boundaries (to prevent players from going under the cards)
const HAND_CARD_WIDTH = 80.0
const HAND_MARGIN = 10.0
# Add visual radius to boundaries so entire player visual stays within bounds
const BATTLEFIELD_LEFT_BOUNDARY = HAND_MARGIN + HAND_CARD_WIDTH + PLAYER_VISUAL_RADIUS  # 105 pixels from left
const BATTLEFIELD_RIGHT_BOUNDARY = 1280.0 - HAND_MARGIN - HAND_CARD_WIDTH - PLAYER_VISUAL_RADIUS  # 1175 pixels from left
const BATTLEFIELD_TOP_BOUNDARY = 20.0 + PLAYER_VISUAL_RADIUS  # 35 pixels from top
const BATTLEFIELD_BOTTOM_BOUNDARY = 720.0 - 20.0 - PLAYER_VISUAL_RADIUS  # 685 pixels from top

signal selection_changed(player_idx: int, slot: int)  # slot is -1 when deselected

var selected_slots: Array[int] = [-1, -1]  # Track selected slot for each player

var player_configs: Array[Dictionary] = [
	{
		"move_keys": {
			"up": KEY_W,
			"down": KEY_S,
			"left": KEY_A,
			"right": KEY_D
		},
		"hand_keys": [KEY_Z, KEY_X, KEY_C, KEY_Q, KEY_E],
		"hand_key_labels": ["Z", "X", "C", "Q", "E"]
	},
	{
		"move_keys": {
			"up": KEY_I,
			"down": KEY_K,
			"left": KEY_J,
			"right": KEY_L
		},
		"hand_keys": [KEY_COMMA, KEY_PERIOD, KEY_M, KEY_U, KEY_O],
		"hand_key_labels": [",", ".", "M", "U", "O"]
	}
]

func handle_movement(players: Array, delta: float) -> void:
	for player_idx: int in range(players.size()):
		var player: Node2D = players[player_idx]
		var config: Dictionary = player_configs[player_idx]
		var velocity: Vector2 = Vector2.ZERO

		var move_keys: Dictionary = config.move_keys
		if Input.is_key_pressed(move_keys.up):
			velocity.y -= 1
		if Input.is_key_pressed(move_keys.down):
			velocity.y += 1
		if Input.is_key_pressed(move_keys.left):
			velocity.x -= 1
		if Input.is_key_pressed(move_keys.right):
			velocity.x += 1

		if velocity.length() > 0:
			var desired_position: Vector2 = player.global_position + velocity.normalized() * PLAYER_SPEED * delta

			# Clamp position to battlefield boundaries (to prevent going under hand UIs)
			desired_position.x = clamp(desired_position.x, BATTLEFIELD_LEFT_BOUNDARY, BATTLEFIELD_RIGHT_BOUNDARY)
			desired_position.y = clamp(desired_position.y, BATTLEFIELD_TOP_BOUNDARY, BATTLEFIELD_BOTTOM_BOUNDARY)

			# Check for collision before moving
			if not _would_collide(player, desired_position):
				player.global_position = desired_position

func handle_casting_input(event: InputEvent, players: Array, combat_system) -> void:
	if not (event is InputEventKey and event.pressed):
		return

	var keycode: int = event.keycode

	for player_idx: int in range(players.size()):
		var config: Dictionary = player_configs[player_idx]

		for slot_idx: int in range(config.hand_keys.size()):
			if keycode == config.hand_keys[slot_idx]:
				var currently_selected: int = selected_slots[player_idx]

				# If this slot is already selected, cast it
				if currently_selected == slot_idx:
					var caster: Node = players[player_idx]
					var mouse_pos: Vector2 = caster.get_viewport().get_mouse_position()

					# Get the spell being cast and its range
					var medallion: Medallion = caster.hand.get_card(slot_idx)
					if medallion:
						var medallion_data_instance: MedallionData = MedallionData.new()
						var data: Dictionary = medallion_data_instance.get_medallion(medallion.id)
						var casting_range: float = data.get("casting_range", 200.0)
						var target_pos: Vector2 = get_clamped_target_position(caster.global_position, mouse_pos, casting_range)
						combat_system.cast_from_hand(caster, slot_idx, target_pos)

						# Deselect after casting
						selected_slots[player_idx] = -1
						selection_changed.emit(player_idx, -1)
				else:
					# Select this slot instead
					selected_slots[player_idx] = slot_idx
					selection_changed.emit(player_idx, slot_idx)

				return

func get_clamped_target_position(caster_pos: Vector2, mouse_pos: Vector2, max_range: float) -> Vector2:
	var direction: Vector2 = mouse_pos - caster_pos
	var distance: float = direction.length()

	if distance > max_range:
		# Clamp to circle edge
		return caster_pos + direction.normalized() * max_range
	else:
		return mouse_pos

func _would_collide(player: Node2D, target_position: Vector2) -> bool:
	# Get the physics world
	var space_state: PhysicsDirectSpaceState2D = player.get_world_2d().direct_space_state

	# Create a shape query (circle for player hitbox)
	var params: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = PLAYER_COLLISION_RADIUS
	params.shape = shape
	params.transform = Transform2D(0, target_position)
	params.collide_with_bodies = true
	params.collide_with_areas = false

	var result: Array[Dictionary] = space_state.intersect_shape(params, 1)
	return result.size() > 0
