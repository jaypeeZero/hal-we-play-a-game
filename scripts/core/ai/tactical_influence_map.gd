extends Node
class_name TacticalInfluenceMap

## Spatial grid that receives TacticalSignals and maintains tactical state.
## Provides queries for creatures to make tactical decisions without direct communication.

# Grid configuration
const CELL_SIZE: int = 32  # Each cell is 32x32 pixels
var grid_width: int = 0
var grid_height: int = 0
var map_bounds: Rect2 = Rect2(0, 0, 1280, 720)  # Default, will be set from battlefield

# Cell data structure
class TacticalCell:
	var threat: float = 0.0           # Enemy presence/danger
	var ally_presence: float = 0.0    # Friendly units nearby
	var opportunity: float = 0.0      # Attackable targets
	var panic: float = 0.0            # Fear/retreat signals
	var interest: float = 0.0         # Areas needing attention

	const DECAY_RATE: float = 5.0

	func decay(delta: float) -> void:
		threat = max(0.0, threat - DECAY_RATE * delta)
		ally_presence = max(0.0, ally_presence - DECAY_RATE * delta)
		opportunity = max(0.0, opportunity - DECAY_RATE * delta)
		panic = max(0.0, panic - DECAY_RATE * delta)
		interest = max(0.0, interest - DECAY_RATE * delta)

	func get_safety_score() -> float:
		return ally_presence - threat - panic

	func get_aggression_score() -> float:
		return opportunity + interest - threat

var cells: Array = []  # 2D array of TacticalCell

# Active signals
var active_signals: Array[TacticalSignal] = []

# Signals (events)
signal signal_received(sig: TacticalSignal)
signal tactical_update(update_type: String, position: Vector2)


func _ready() -> void:
	initialize(map_bounds)


func initialize(bounds: Rect2) -> void:
	map_bounds = bounds
	grid_width = ceili(bounds.size.x / CELL_SIZE)
	grid_height = ceili(bounds.size.y / CELL_SIZE)

	cells = []
	for y in range(grid_height):
		var row = []
		for x in range(grid_width):
			row.append(TacticalCell.new())
		cells.append(row)


func _process(delta: float) -> void:
	_process_active_signals(delta)
	_decay_all_cells(delta)


# ========================================
# EVENT-DRIVEN API: Emit signals
# ========================================

func emit_signal_at(sig: TacticalSignal) -> void:
	"""Main entry point: creature emits a tactical signal"""
	active_signals.append(sig)
	_apply_signal_immediately(sig)
	signal_received.emit(sig)


# ========================================
# Signal Processing
# ========================================

func _process_active_signals(delta: float) -> void:
	var expired_indices: Array[int] = []

	for i in range(active_signals.size()):
		var sig = active_signals[i]
		sig.duration -= delta

		if sig.duration <= 0.0:
			expired_indices.append(i)
		else:
			# Update position for signals with moving targets
			if sig.target_entity and is_instance_valid(sig.target_entity):
				sig.position = sig.target_entity.global_position

	# Remove expired signals (reverse order to maintain indices)
	for i in range(expired_indices.size() - 1, -1, -1):
		active_signals.remove_at(expired_indices[i])


func _decay_all_cells(delta: float) -> void:
	for row in cells:
		for cell in row:
			cell.decay(delta)


func _apply_signal_immediately(sig: TacticalSignal) -> void:
	"""Apply signal influence to grid cells"""
	match sig.signal_type:
		TacticalSignal.Type.PRESENCE:
			_add_influence(sig.position, "ally_presence", sig.strength, sig.radius, sig.owner_id)

		TacticalSignal.Type.PANIC:
			_add_influence(sig.position, "panic", sig.strength, sig.radius, sig.owner_id)

		TacticalSignal.Type.NEAR_DEATH:
			_add_influence(sig.position, "interest", sig.strength, sig.radius, sig.owner_id)

		TacticalSignal.Type.TARGET_SPOTTED:
			_add_influence(sig.position, "opportunity", sig.strength, sig.radius, sig.owner_id)
			_add_influence(sig.position, "interest", sig.strength * 0.8, sig.radius, sig.owner_id)

		TacticalSignal.Type.ATTACKING:
			_add_influence(sig.position, "opportunity", sig.strength * 1.5, sig.radius, sig.owner_id)

		TacticalSignal.Type.NEED_SUPPORT:
			_add_influence(sig.position, "interest", sig.strength * 2.0, sig.radius, sig.owner_id)

		TacticalSignal.Type.FLANKING_OPPORTUNITY:
			# Add interest in the flanking direction
			var flank_pos = sig.position + sig.direction * 60.0
			_add_influence(flank_pos, "interest", sig.strength, sig.radius, sig.owner_id)

		TacticalSignal.Type.FOCUS_FIRE:
			_add_influence(sig.position, "opportunity", sig.strength, sig.radius, sig.owner_id)
			_add_influence(sig.position, "interest", sig.strength * 1.5, sig.radius, sig.owner_id)

		TacticalSignal.Type.RETREAT_SUGGESTED:
			_add_influence(sig.position, "panic", sig.strength, sig.radius, sig.owner_id)


func _add_influence(world_pos: Vector2, influence_type: String, strength: float, radius: float, _owner_id: int) -> void:
	"""Add influence to grid cells in radius around position"""
	var center = world_to_grid(world_pos)
	var radius_cells = int(radius / CELL_SIZE)

	for dy in range(-radius_cells, radius_cells + 1):
		for dx in range(-radius_cells, radius_cells + 1):
			var x = center.x + dx
			var y = center.y + dy

			if not _is_valid_cell(x, y):
				continue

			var distance = sqrt(dx * dx + dy * dy) * CELL_SIZE
			if distance > radius:
				continue

			# Falloff: closer = stronger
			var falloff = 1.0 - (distance / radius)
			var value = strength * falloff

			var cell = cells[y][x]
			match influence_type:
				"threat":
					cell.threat += value
				"ally_presence":
					cell.ally_presence += value
				"opportunity":
					cell.opportunity += value
				"panic":
					cell.panic += value
				"interest":
					cell.interest += value


# ========================================
# Query API: Creatures read tactical state
# ========================================

func get_cell_at(world_pos: Vector2) -> TacticalCell:
	"""Get tactical info at a specific position"""
	var grid_pos = world_to_grid(world_pos)
	if not _is_valid_cell(grid_pos.x, grid_pos.y):
		return TacticalCell.new()  # Return neutral cell
	return cells[grid_pos.y][grid_pos.x]


func find_safest_position_near(world_pos: Vector2, search_radius: float, _owner_id: int) -> Vector2:
	"""Find the safest nearby position (high ally_presence, low threat/panic)"""
	return _find_best_position_near(world_pos, search_radius, func(cell): return cell.get_safety_score())


func find_best_attack_position_near(world_pos: Vector2, search_radius: float, _owner_id: int) -> Vector2:
	"""Find the best attack position (high opportunity, moderate threat)"""
	return _find_best_position_near(world_pos, search_radius, func(cell): return cell.get_aggression_score())


func find_high_interest_positions(_owner_id: int, min_interest: float = 1.0) -> Array[Vector2]:
	"""Find all positions with high interest (targets, flanking opportunities)"""
	var positions: Array[Vector2] = []

	for y in range(grid_height):
		for x in range(grid_width):
			if cells[y][x].interest >= min_interest:
				positions.append(grid_to_world(Vector2i(x, y)))

	return positions


func get_active_signals_near(world_pos: Vector2, radius: float, owner_id: int, signal_type: TacticalSignal.Type = -1, coordination_group_id: String = "") -> Array[TacticalSignal]:
	"""Get active signals near position (optionally filtered by type, owner, and coordination group)"""
	var nearby: Array[TacticalSignal] = []

	for sig in active_signals:
		if sig.owner_id != owner_id:
			continue

		if signal_type >= 0 and sig.signal_type != signal_type:
			continue

		# Filter by coordination group if specified
		if coordination_group_id != "" and sig.coordination_group_id != coordination_group_id:
			continue

		if sig.position.distance_to(world_pos) <= radius:
			nearby.append(sig)

	return nearby


# ========================================
# Helpers
# ========================================

func world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		int((world_pos.x - map_bounds.position.x) / CELL_SIZE),
		int((world_pos.y - map_bounds.position.y) / CELL_SIZE)
	)


func grid_to_world(grid_pos: Vector2i) -> Vector2:
	return Vector2(
		map_bounds.position.x + grid_pos.x * CELL_SIZE + CELL_SIZE / 2.0,
		map_bounds.position.y + grid_pos.y * CELL_SIZE + CELL_SIZE / 2.0
	)


func _is_valid_cell(x: int, y: int) -> bool:
	return x >= 0 and x < grid_width and y >= 0 and y < grid_height


func _find_best_position_near(world_pos: Vector2, search_radius: float, score_func: Callable) -> Vector2:
	var center = world_to_grid(world_pos)
	var radius_cells = int(search_radius / CELL_SIZE)

	var best_pos = world_pos
	var best_score = -INF

	for dy in range(-radius_cells, radius_cells + 1):
		for dx in range(-radius_cells, radius_cells + 1):
			var x = center.x + dx
			var y = center.y + dy

			if not _is_valid_cell(x, y):
				continue

			var score = score_func.call(cells[y][x])
			if score > best_score:
				best_score = score
				best_pos = grid_to_world(Vector2i(x, y))

	return best_pos
