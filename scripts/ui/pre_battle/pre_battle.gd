extends Node2D

## Pre-battle preview screen. Builds the default battle plan from the
## active fleets (roguelike if present, else on-disk team fleets), spawns
## non-interactive ShipEntity nodes at their planned positions, and
## renders dotted patrol circles. Clicking Start Battle hands off to
## space_battle.tscn, which consumes BattlePlan.entries directly.
##
## Selection is multi: plain click picks a single ship, ctrl-click toggles
## a ship in/out of the selection, and shift-drag draws a box that replaces
## the selection with every ship inside. Dragging a selected ship moves the
## whole group in formation; dragging anywhere inside a selected ship's
## patrol disc collapses every selected ring to the cursor.

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
const BOX_FILL_COLOR: Color = Color(1.0, 1.0, 1.0, 0.08)
const BOX_BORDER_COLOR: Color = Color(1.0, 1.0, 1.0, 0.9)
const BOX_BORDER_WIDTH: float = 2.0

var _input: PreBattleInput
var _preview_entities: Dictionary = {}
var _doctrine_panel: DoctrinePanel = null


func _ready() -> void:
	var team0_fleet: Dictionary
	var team1_fleet: Dictionary
	if RoguelikeRun.active:
		team0_fleet = RoguelikeRun.fleet
		team1_fleet = RoguelikeRun.enemy_fleet
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

	# Doctrine (standing instructions) is roguelike run state; the panel
	# only exists when a run is active. Outside a run, say so instead of
	# showing nothing.
	if RoguelikeRun.active:
		_doctrine_panel = DoctrinePanel.new()
		$UI.add_child(_doctrine_panel)
		_doctrine_panel.setup(BattlePlan.entries)
		_doctrine_panel.hull_selected.connect(_on_doctrine_hull_selected)
	else:
		_add_doctrine_hint()

	queue_redraw()


## Shown where the doctrine panel would be when no run is active, so the
## feature is discoverable from the direct main-menu pre-battle path.
func _add_doctrine_hint() -> void:
	var hint := Label.new()
	hint.text = "Fleet doctrine: standing instructions are issued here\nduring a roguelike run (Main Menu → Fleet Management → Launch)."
	hint.anchor_left = 1.0
	hint.anchor_right = 1.0
	hint.offset_left = -(DoctrinePanel.PANEL_WIDTH + DoctrinePanel.PANEL_MARGIN)
	hint.offset_right = -DoctrinePanel.PANEL_MARGIN
	hint.offset_top = DoctrinePanel.PANEL_MARGIN
	$UI.add_child(hint)


## Picking a hull in the doctrine dropdown selects it on the map too.
func _on_doctrine_hull_selected(entry_index: int) -> void:
	_input.selected_indices.clear()
	_input.selected_indices.append(entry_index)
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
		if _input.selected_indices.size() > 0:
			_input.clear_selection()
			queue_redraw()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		var world_pos := get_global_mouse_position()
		if event.pressed:
			var result := _input.on_mouse_down(world_pos, event.shift_pressed, event.ctrl_pressed)
			if result != PreBattleInput.RESULT_NONE:
				# A plain single-ship click also syncs the doctrine dropdown.
				if result == PreBattleInput.RESULT_SELECTED and _doctrine_panel != null:
					_doctrine_panel.sync_to_entry(_input.selected_indices[0])
				queue_redraw()
				get_viewport().set_input_as_handled()
		else:
			var was_box_select := _input.state == PreBattleInput.STATE_BOX_SELECT
			var released := _input.on_mouse_up()
			if released >= 0 or was_box_select:
				queue_redraw()
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		_input.on_mouse_motion(get_global_mouse_position())
		if _input.state == PreBattleInput.STATE_DRAGGING_SHIP:
			for i in _input.ship_drag_offsets.keys():
				_preview_entities[i].global_position = BattlePlan.entries[i]["position"]
			queue_redraw()
		elif _input.state == PreBattleInput.STATE_DRAGGING_CIRCLE or _input.state == PreBattleInput.STATE_BOX_SELECT:
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

		if _input.is_selected(i):
			DottedDraw.draw_dotted_circle(self, center, radius, SELECTED_RING_COLOR, SELECTED_RING_LINE_WIDTH)

	if _input.state == PreBattleInput.STATE_BOX_SELECT:
		var rect := _input.get_box_rect()
		draw_rect(rect, BOX_FILL_COLOR, true)
		draw_rect(rect, BOX_BORDER_COLOR, false, BOX_BORDER_WIDTH)


func _on_start_battle_pressed() -> void:
	if _input != null:
		_input.clear_selection()
	get_tree().change_scene_to_file("res://scenes/space_battle.tscn")
