extends Node

## Headless-friendly visual smoke check: boots the battle scene, spawns a
## small fleet per team, and saves screenshots at far and near zoom.
## Run under a virtual display:
##   xvfb-run godot --path . res://tools/visual_check.tscn
## Output dir comes from the VISUAL_CHECK_OUT env var (default /tmp/visual_check).

const BATTLE_SCENE := "res://scenes/space_battle.tscn"
const DEFAULT_OUTPUT_DIR := "/tmp/visual_check"

const SETTLE_FRAMES_AFTER_SPAWN: int = 30
const FRAMES_BETWEEN_SHOTS: int = 60
const CLOSEUP_ZOOM: float = 1.0

const FLEET_CENTER_TEAM_0 := Vector2(2100, 1750)
const FLEET_CENTER_TEAM_1 := Vector2(2900, 1750)
const PATROL_RADIUS: float = 400.0
const FORMATION_SPACING: float = 120.0

func _ready() -> void:
	var output_dir := OS.get_environment("VISUAL_CHECK_OUT")
	if output_dir.is_empty():
		output_dir = DEFAULT_OUTPUT_DIR
	DirAccess.make_dir_recursive_absolute(output_dir)

	var battle: Node = load(BATTLE_SCENE).instantiate()
	add_child(battle)
	await get_tree().process_frame

	var game: Node = battle.get_node("SpaceBattleGame")
	_spawn_fleet(game, 0, FLEET_CENTER_TEAM_0)
	_spawn_fleet(game, 1, FLEET_CENTER_TEAM_1)

	for i in SETTLE_FRAMES_AFTER_SPAWN:
		await get_tree().process_frame
	await _save_screenshot(output_dir + "/battle_far.png")

	var camera: Camera2D = battle.get_node("SpaceBattleGame/Camera")
	camera.zoom = Vector2.ONE * CLOSEUP_ZOOM
	camera.position = FLEET_CENTER_TEAM_0
	camera.set("_target_zoom", camera.zoom)
	camera.set("_target_position", camera.position)

	for i in FRAMES_BETWEEN_SHOTS:
		await get_tree().process_frame
	await _save_screenshot(output_dir + "/battle_close.png")

	print("visual_check: screenshots saved to " + output_dir)
	get_tree().quit()

func _spawn_fleet(game: Node, team: int, center: Vector2) -> void:
	var ship_types := ["fighter", "fighter", "heavy_fighter", "torpedo_boat", "corvette", "capital"]
	for i in ship_types.size():
		var row_offset := Vector2((team * 2 - 1) * (i / 3) * FORMATION_SPACING * 2.0,
			(i % 3 - 1) * FORMATION_SPACING * 3.0)
		game.spawn_ship(ship_types[i], team, center + row_offset, center, PATROL_RADIUS)

func _save_screenshot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(path)
	print("visual_check: wrote " + path)
