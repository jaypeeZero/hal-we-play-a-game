extends Node2D

## Pre-battle preview screen. Builds the default battle plan from the
## active fleets (roguelike if present, else on-disk team fleets), spawns
## non-interactive ShipEntity nodes at their planned positions, and
## renders dotted patrol circles. Clicking Start Battle hands off to
## space_battle.tscn, which consumes BattlePlan.entries directly.
##
## Phase 4: ships are draggable and selectable. The selected ship's
## patrol ring renders prominently and can be dragged to relocate the
## patrol center. PreBattleInput owns the state machine; this controller
## just translates events, repositions ShipEntity nodes, and triggers
## redraws.

const ShipEntity = preload("res://scripts/space/entities/ship_entity.gd")

# Mirrors SpaceBattleGame's _battlefield_size; the planner needs to know
# where the edges are.
const BATTLEFIELD_SIZE: Vector2 = Vector2(5000, 3500)

const TEAM_COLORS: Array = [
	Color(0.4, 0.7, 1.0, 0.6),  # team 0 — blue
	Color(1.0, 0.4, 0.4, 0.6),  # team 1 — red
]
const SELECTED_RING_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const SELECTED_RING_LINE_WIDTH: float = 3.0

var _input: PreBattleInput
var _preview_entities: Dictionary = {}


func _ready() -> void:
	var team0_fleet: Dictionary
	var team1_fleet: Dictionary
	if RoguelikeRun.active:
		team0_fleet = RoguelikeRun.fleet
		team1_fleet = RoguelikeRun.ENEMY_FLEET
	else:
		team0_fleet = FleetDataManager.load_fleet(0)
		team1_fleet = FleetDataManager.load_fleet(1)

	BattlePlan.battlefield_size = BATTLEFIELD_SIZE
	BattlePlan.entries = BattlePlanner.build_default_plan(team0_fleet, team1_fleet, BATTLEFIELD_SIZE)

	for i in range(BattlePlan.entries.size()):
		_preview_entities[i] = _spawn_preview_ship(BattlePlan.entries[i])

	var margin: float = BattlePlanner.MARGIN
	var bounds := Rect2(
		Vector2(margin, margin),
		BATTLEFIELD_SIZE - Vector2(margin * 2.0, margin * 2.0)
	)
	_input = PreBattleInput.new(BattlePlan.entries, bounds)

	queue_redraw()


func _spawn_preview_ship(entry: Dictionary) -> ShipEntity:
	var ship_type: String = entry["ship_type"]
	var team: int = entry["team"]
	var collision_radius: float = HullShapes.get_collision_radius(ship_type)
	var entity := ShipEntity.new()
	# Generate a stable preview id so VisualBridge can register the entity;
	# the real battle generates its own ids when it spawns from the plan.
	var preview_id := "preview_%d_%s_%d" % [team, ship_type, get_child_count()]
	entity.initialize(preview_id, team, collision_radius, ship_type)
	entity.global_position = entry["position"]
	entity.rotation = 0.0 if team == 0 else PI
	add_child(entity)
	return entity


func _unhandled_input(event: InputEvent) -> void:
	if _input == null:
		return

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _input.selected_index >= 0:
			_input.clear_selection()
			queue_redraw()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		var world_pos := get_global_mouse_position()
		if event.pressed:
			var result := _input.on_mouse_down(world_pos)
			if result != PreBattleInput.RESULT_NONE:
				queue_redraw()
				get_viewport().set_input_as_handled()
		else:
			var released := _input.on_mouse_up()
			if released >= 0:
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var idx := _input.on_mouse_motion(get_global_mouse_position())
		if idx >= 0:
			if _input.state == PreBattleInput.STATE_DRAGGING_SHIP:
				_preview_entities[idx].global_position = BattlePlan.entries[idx]["position"]
			queue_redraw()


func _draw() -> void:
	for i in range(BattlePlan.entries.size()):
		var entry: Dictionary = BattlePlan.entries[i]
		var team: int = int(entry.get("team", 0))
		var color: Color = TEAM_COLORS[team] if team >= 0 and team < TEAM_COLORS.size() else TEAM_COLORS[0]
		var center: Vector2 = entry["patrol_center"]
		var radius: float = float(entry["patrol_radius"])
		var ship_pos: Vector2 = entry["position"]

		var to_center: Vector2 = center - ship_pos
		var dist: float = to_center.length()
		var line_end: Vector2 = center
		if dist > radius:
			line_end = ship_pos + to_center / dist * (dist - radius)
		DottedDraw.draw_dotted_line(self, ship_pos, line_end, color)
		DottedDraw.draw_dotted_circle(self, center, radius, color)

		if i == _input.selected_index:
			DottedDraw.draw_dotted_circle(self, center, radius, SELECTED_RING_COLOR, SELECTED_RING_LINE_WIDTH)


func _on_start_battle_pressed() -> void:
	if _input != null:
		_input.clear_selection()
	get_tree().change_scene_to_file("res://scenes/space_battle.tscn")
