extends Node3D
class_name CampaignMap3D

## 3D star-chart campaign map. Each sector is a concentric shell of star
## nodes (sector E outermost, sector A the core); winning a sector's exit
## battle promotes the player one shell inward. A total-loss defeat ends the
## run or resets the sector to a rebuild shop — the player never moves back a
## shell. This scene owns all campaign-flow branching: battle results land
## here via RoguelikeRun.pending_battle_result.

signal node_selected(node: Dictionary)
signal sector_changed(from_sector: String, to_sector: String)
signal campaign_ended(result: String)

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const PRE_BATTLE_SCENE := "res://scenes/pre_battle.tscn"

const NODE_TYPE_NAMES := {
	CampaignSystem.NODE_TYPE_BATTLE: "Battle",
	CampaignSystem.NODE_TYPE_RANDR: "R&R",
	CampaignSystem.NODE_TYPE_SHOP: "Shop",
}
const NODE_TYPE_COLORS := {
	CampaignSystem.NODE_TYPE_BATTLE: Color(0.9, 0.3, 0.3),
	CampaignSystem.NODE_TYPE_RANDR: Color(0.3, 0.9, 0.3),
	CampaignSystem.NODE_TYPE_SHOP: Color(0.3, 0.3, 0.9),
}
const VISITED_COLOR := Color(0.5, 0.5, 0.5)
const LOCKED_COLOR := Color(0.3, 0.3, 0.35)
const CURRENT_POSITION_COLOR := Color(1.0, 0.9, 0.4)

const BRIDGE_LINE_COLOR := Color(1.0, 0.85, 0.3, 0.9)
const LINE_OPEN_COLOR := Color(1.0, 1.0, 1.0, 0.8)
const LINE_VISITED_COLOR := Color(0.6, 0.6, 0.6, 0.5)
const LINE_DIM_COLOR := Color(0.5, 0.5, 0.5, 0.25)

## Non-current sectors render faded and unclickable: one rule solves both
## shell occlusion and click-through.
const DIMMED_SECTOR_ALPHA := 0.12

const STAR_RADIUS := 0.3
const STAR_PICK_RADIUS := 0.7
const STAR_LABEL_OFFSET := Vector3(0, 0.8, 0)
const STAR_LABEL_FONT_SIZE := 36
## With fixed_size, on-screen label height ~= font_size * pixel_size * viewport_height.
const STAR_LABEL_PIXEL_SIZE := 0.0005
const HOVERED_STAR_SCALE := 1.5
const CURRENT_NODE_PULSE_SPEED := 5.0
const CURRENT_NODE_PULSE_DEPTH := 0.5
const BASE_EMISSION_ENERGY := 1.0

const ORBIT_RADIANS_PER_PIXEL := 0.008
const CAMERA_PITCH_LIMIT := 1.4
const ZOOM_STEP := 2.0
const ZOOM_MIN := 5.0
const ZOOM_MAX := 80.0
const CAMERA_SHELL_MARGIN := 12.0
const CAMERA_TWEEN_SECONDS := 1.2

const END_BANNER_SECONDS := 3.0
const WINNER_BANNER_TEXT := "WINNER!\nSector A is yours, Commander."
const GAME_OVER_BANNER_TEXT := "GAME OVER\nYour fleet was destroyed and you cannot afford to rebuild."

@onready var _camera_rig: Node3D = $CameraRig
@onready var _camera: Camera3D = $CameraRig/Camera3D
@onready var _stars_root: Node3D = $Stars
@onready var _lines: MeshInstance3D = $ConnectionLines
@onready var _sector_label: Label = $UI/SectorLabel
@onready var _info_label: Label = $UI/InfoLabel
@onready var _banner_label: Label = $UI/BannerLabel
@onready var _ui_layer: CanvasLayer = $UI

var _star_materials: Dictionary = {}  # node_id -> StandardMaterial3D
var _star_areas: Dictionary = {}      # node_id -> Area3D
var _star_labels: Dictionary = {}     # node_id -> Label3D
var _dragging := false
var _zoom_distance := ZOOM_MAX
var _campaign_over := false
## One-shot transition report (promotion, revisit, sector reset) shown above
## the standing "select your destination" prompt on the next refresh.
var _status_message := ""

var _fleet_panel: FleetConditionPanel
var _destination_panel: DestinationPanel
var _dispatches_panel: DispatchesPanel
var _nav_bar: NavBar


func _ready() -> void:
	if not RoguelikeRun.active or RoguelikeRun.campaign.is_empty():
		# Direct scene launch (developer preview) starts a fresh campaign.
		RoguelikeRun.start_run(FleetDataManager.load_fleet(0))

	_fleet_panel = FleetConditionPanel.new()
	_fleet_panel.hull_selected.connect(func(hull: Dictionary):
		ShipViewModal.open(_ui_layer, hull))
	_fleet_panel.manage_crew_requested.connect(_open_manage_crew)
	_ui_layer.add_child(_fleet_panel)

	_destination_panel = DestinationPanel.new()
	_destination_panel.launch_requested.connect(_travel_to_node)
	_ui_layer.add_child(_destination_panel)

	_dispatches_panel = DispatchesPanel.new()
	_ui_layer.add_child(_dispatches_panel)

	# Nav bar added after the base panels so it draws above them; runtime
	# modals (ship view, shop, rest) added later still cover it, by design.
	_nav_bar = NavBar.attach(_ui_layer, NavGraph.Screen.MAP)

	_build_stars()
	_build_line_mesh()
	_set_zoom(_current_shell_radius() + CAMERA_SHELL_MARGIN)
	await _resolve_pending_battle()
	if _campaign_over:
		return
	_refresh_map()
	_dispatches_panel.refresh(RoguelikeRun.news_feed)
	_show_repair_summary(RoguelikeRun.last_jump_repair_summary)
	RoguelikeRun.last_jump_repair_summary = {}
	# Report the economy outcome of the last battle (reward, casualties, insurance).
	_show_battle_summary(RoguelikeRun.last_battle_summary)
	RoguelikeRun.last_battle_summary = {}


func _process(_delta: float) -> void:
	_pulse_current_node()


# ============================================================================
# CAMPAIGN FLOW - battle results, promotion, defeat, campaign end
# ============================================================================

## The campaign-flow brain: consume the battle result stashed by the
## battle scene and branch into plain progress, promotion, defeat
## (sector reset or game over), or campaign victory.
func _resolve_pending_battle() -> void:
	var node_id: String = RoguelikeRun.pending_battle_node_id
	var result: String = RoguelikeRun.pending_battle_result
	RoguelikeRun.pending_battle_node_id = ""
	RoguelikeRun.pending_battle_result = ""
	if node_id == "" or result == "":
		return
	if result == CampaignSystem.RESULT_VICTORY:
		await _resolve_battle_victory(node_id)
	elif RoguelikeRun.pending_battle_fled:
		# Lost the engagement but ships escaped — takes precedence over a total loss.
		await _resolve_battle_fled_retreat()
	else:
		await _resolve_battle_defeat()
	RoguelikeRun.pending_battle_fled = false


func _resolve_battle_victory(node_id: String) -> void:
	var campaign: Dictionary = RoguelikeRun.campaign
	CampaignSystem.visit_node(campaign, node_id)
	var node := CampaignSystem.node_by_id(campaign, node_id)
	node_selected.emit(node)

	if CampaignSystem.is_sector_complete(campaign):
		if CampaignSystem.is_top_sector(campaign):
			await _end_campaign(WINNER_BANNER_TEXT, CampaignSystem.RESULT_VICTORY)
			return
		var from_sector: String = campaign["current_sector"]
		CampaignSystem.promote(campaign)
		sector_changed.emit(from_sector, campaign["current_sector"])
		_tween_camera_to_current_shell()
		_status_message = "Sector %s secured! Promoted to Sector %s." % [
			from_sector, campaign["current_sector"]]
	RoguelikeRun.save_campaign_to_disk()


func _resolve_battle_defeat() -> void:
	var campaign: Dictionary = RoguelikeRun.campaign
	if not RoguelikeRun.can_afford_rebuild():
		await _end_campaign(GAME_OVER_BANNER_TEXT, CampaignSystem.RESULT_DEFEAT)
		return

	var sector: String = campaign["current_sector"]
	CampaignSystem.reset_sector_to_shop(campaign, sector)
	_status_message = "Fleet lost in Sector %s. The sector entry has been converted to a shop — rebuild before re-engaging." % sector
	RoguelikeRun.save_campaign_to_disk()


## Lost the engagement but ships escaped: no sector reset, no game-over. The
## fled fleet regroups in place; the node is NOT marked visited (the battle
## wasn't won) so the player re-attempts or picks another.
## Fleeing is the deliberate escape hatch from a total loss.
func _resolve_battle_fled_retreat() -> void:
	_status_message = "Engagement lost — %d ship(s) escaped and regrouped." % \
		RoguelikeRun.fleet_hulls.size()
	RoguelikeRun.save_campaign_to_disk()


func _end_campaign(banner_text: String, result: String) -> void:
	_campaign_over = true
	_destination_panel.dismiss()
	_refresh_map()
	_banner_label.text = banner_text
	_banner_label.visible = true
	campaign_ended.emit(result)
	CampaignSaveManager.delete_save()
	RoguelikeRun.end_run()
	await get_tree().create_timer(END_BANNER_SECONDS).timeout
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


# ============================================================================
# NODE SELECTION
# ============================================================================

func _on_star_input_event(_camera: Node, event: InputEvent, _position: Vector3,
		_normal: Vector3, _shape_idx: int, node_id: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_on_node_clicked(node_id)


## Open the destination side panel for the clicked star. All pickable stars
## (current-sector only) are selectable; travel happens via Launch.
func _on_node_clicked(node_id: String) -> void:
	if _campaign_over:
		return
	var node := CampaignSystem.node_by_id(RoguelikeRun.campaign, node_id)
	if node.is_empty():
		return
	_destination_panel.show_node(node, node_id == RoguelikeRun.campaign.get("current_node_id", ""))


## Execute the jump: apply repairs, then branch into battle/shop/R&R flow.
## Connected to DestinationPanel.launch_requested.
func _travel_to_node(node_id: String) -> void:
	if _campaign_over:
		return
	var node := CampaignSystem.node_by_id(RoguelikeRun.campaign, node_id)
	if node.is_empty() or not node.get("accessible", false):
		return

	# The jump itself is downtime: engineers repair in proportion to the
	# star-date gap, with R&R stops multiplying the effect.
	var destination: int = RoguelikeRun.current_star_date + int(node["star_date_gap"])
	var repair_summary: Dictionary = RoguelikeRun.apply_jump_repairs(
		destination, node["type"] == CampaignSystem.NODE_TYPE_RANDR)

	if node.get("visited", false):
		_complete_revisit(node, repair_summary)
		return

	if node["type"] == CampaignSystem.NODE_TYPE_BATTLE:
		_enter_battle_node(node)
		return

	# Shop nodes open the shop overlay first; the visit completes when it
	# closes (purchases/hires/transfers persist on RoguelikeRun and the node).
	if node["type"] == CampaignSystem.NODE_TYPE_SHOP:
		_open_shop(node, repair_summary)
		return

	# R&R nodes open the rest overlay; the visit completes when it closes.
	if node["type"] == CampaignSystem.NODE_TYPE_RANDR:
		_open_rest(node, repair_summary)
		return

	_complete_node_visit(node, repair_summary)


## Mark a non-battle node visited and refresh the map. Shared by R&R stops
## (immediate) and shop nodes (after the overlay closes).
func _complete_node_visit(node: Dictionary, repair_summary: Dictionary) -> void:
	CampaignSystem.visit_node(RoguelikeRun.campaign, node["id"])
	node_selected.emit(node)
	RoguelikeRun.save_campaign_to_disk()
	_refresh_map()
	_dispatches_panel.refresh(RoguelikeRun.news_feed)
	_show_repair_summary(repair_summary)
	RoguelikeRun.last_jump_repair_summary = {}


## Handle a jump to a node the player has already visited: reposition without
## triggering events again. Repair time still passes; the visit is idempotent.
func _complete_revisit(node: Dictionary, repair_summary: Dictionary) -> void:
	CampaignSystem.visit_node(RoguelikeRun.campaign, node["id"])
	RoguelikeRun.save_campaign_to_disk()
	_refresh_map()
	_status_message = "Returned to %s — %d star dates passed. No new events." % [
		node.get("name", node["id"]), repair_summary.get("date_delta", 0)]
	_show_repair_summary(repair_summary)
	RoguelikeRun.last_jump_repair_summary = {}


## Open the crew management overlay from the campaign map fleet panel.
func _open_manage_crew() -> void:
	_fleet_panel.visible = false
	var screen := FleetCommandScreen.open_overlay(_ui_layer)
	screen.done.connect(func() -> void:
		_fleet_panel.visible = true
		_update_fleet_status())


## Open the R&R overlay for a rest node. Presents a menu: "Manage Fleet"
## (existing crew management) or "Go to the Races" (betting overlay).
## The 3× repair multiplier already ran via apply_jump_repairs before this.
func _open_rest(node: Dictionary, repair_summary: Dictionary) -> void:
	_fleet_panel.visible = false
	_destination_panel.dismiss()
	_open_rest_menu(node, repair_summary)


## Show the R&R activity choice: fleet management or racing.
func _open_rest_menu(node: Dictionary, repair_summary: Dictionary) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "R&R — What will you do?"
	dialog.ok_button_text = "Manage Fleet"
	dialog.cancel_button_text = "Go to the Races"
	add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		dialog.queue_free()
		var screen := FleetCommandScreen.open_overlay(self)
		screen.done.connect(func() -> void:
			_fleet_panel.visible = true
			_complete_node_visit(node, repair_summary)))
	dialog.canceled.connect(func() -> void:
		dialog.queue_free()
		var betting := RaceBettingScreen.open_overlay(self)
		betting.closed.connect(func() -> void:
			betting.queue_free()
			_fleet_panel.visible = true
			_complete_node_visit(node, repair_summary)))
	dialog.popup_centered()


## Open the shop overlay for a shop node, completing the node visit once the
## player closes it. Stock is rolled lazily on first visit and stored on the
## node so it persists (and stays stable) through the campaign save.
func _open_shop(node: Dictionary, repair_summary: Dictionary) -> void:
	if not node.has("shop_stock"):
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		node["shop_stock"] = EconomySystem.roll_shop_stock(rng)
	var shop := ShopScreen.new()
	add_child(shop)
	# The shop carries per-hull condition in its roster headers, so the
	# fleet panel is redundant (and would show through) while open.
	_fleet_panel.visible = false
	_destination_panel.dismiss()
	shop.closed.connect(func():
		shop.queue_free()
		_fleet_panel.visible = true
		_complete_node_visit(node, repair_summary))
	shop.setup(node)


# ============================================================================
# BATTLE LAUNCH - per-battle upkeep gate, dismissal, bankruptcy, benched notice
# ============================================================================

## Gate a battle on per-battle upkeep. Affordable ⇒ pay and launch. Short but
## the player can still dismiss down to an affordable minimum ⇒ dismissal
## dialog. Short and even a minimum force is unaffordable ⇒ the run is lost.
func _enter_battle_node(node: Dictionary) -> void:
	var upkeep: int = EconomySystem.per_battle_upkeep(RoguelikeRun.fleet_hulls).total
	if RoguelikeRun.money >= upkeep:
		_confirm_then_launch(node, upkeep)
	elif RoguelikeRun.can_field_minimum():
		_open_dismissal_dialog(node)
	else:
		_lose_run_to_bankruptcy()


func _open_dismissal_dialog(node: Dictionary) -> void:
	var dialog := DismissalDialog.new()
	add_child(dialog)
	dialog.resolved.connect(func(launched: bool):
		dialog.queue_free()
		if launched:
			# Upkeep shrank as the player dismissed; charge the new total.
			_confirm_then_launch(node, EconomySystem.per_battle_upkeep(RoguelikeRun.fleet_hulls).total))
	dialog.setup()


## Charge upkeep and launch — but first, if any non-iced hull will sit the
## battle out for lack of a pilot, surface them so a ship is never silently
## left behind. Upkeep is only spent if the player proceeds.
func _confirm_then_launch(node: Dictionary, upkeep: int) -> void:
	var benched := RoguelikeRun.benched_hulls()
	if benched.is_empty():
		RoguelikeRun.money -= upkeep
		_launch_battle(node)
		return
	var notice := LaunchNotice.new()
	add_child(notice)
	notice.resolved.connect(func(launch: bool):
		notice.queue_free()
		if launch:
			RoguelikeRun.money -= upkeep
			_launch_battle(node))
	notice.setup(benched)


func _lose_run_to_bankruptcy() -> void:
	_info_label.text = "Bankrupt — the fleet is impounded. The run is over."
	await get_tree().create_timer(END_BANNER_SECONDS).timeout
	CampaignSaveManager.delete_save()
	RoguelikeRun.end_run()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _launch_battle(node: Dictionary) -> void:
	RoguelikeRun.started_first_battle = true
	RoguelikeRun.pending_battle_node_id = node["id"]
	# Store the per-node enemy fleet so the battle pipeline can read it.
	RoguelikeRun.enemy_fleet = node.get("enemy_fleet", {}).duplicate(true)
	RoguelikeRun.save_campaign_to_disk()
	node_selected.emit(node)
	get_tree().change_scene_to_file(PRE_BATTLE_SCENE)


func _on_star_mouse_entered(node_id: String) -> void:
	# All pickable stars (current-sector only) respond to hover.
	_star_areas[node_id].scale = Vector3.ONE * HOVERED_STAR_SCALE


func _on_star_mouse_exited(node_id: String) -> void:
	_star_areas[node_id].scale = Vector3.ONE


# ============================================================================
# CAMERA - drag to orbit, wheel to zoom
# ============================================================================

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_dragging = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_set_zoom(_zoom_distance - ZOOM_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_set_zoom(_zoom_distance + ZOOM_STEP)
	elif event is InputEventMouseMotion and _dragging:
		_camera_rig.rotation.y -= event.relative.x * ORBIT_RADIANS_PER_PIXEL
		_camera_rig.rotation.x = clampf(
			_camera_rig.rotation.x - event.relative.y * ORBIT_RADIANS_PER_PIXEL,
			-CAMERA_PITCH_LIMIT, CAMERA_PITCH_LIMIT)


func _set_zoom(distance: float) -> void:
	_zoom_distance = clampf(distance, ZOOM_MIN, ZOOM_MAX)
	_camera.position = Vector3(0, 0, _zoom_distance)


func _current_shell_radius() -> float:
	var sector_index := CampaignSystem.SECTORS.find(
		RoguelikeRun.campaign.get("current_sector", CampaignSystem.SECTORS[0]))
	return CampaignGenerator.SHELL_RADIUS_CORE \
		+ (CampaignSystem.SECTORS.size() - 1 - sector_index) * CampaignGenerator.SHELL_RADIUS_STEP


## Promotion burrows the camera inward to the next shell.
func _tween_camera_to_current_shell() -> void:
	create_tween().tween_method(_set_zoom, _zoom_distance,
		_current_shell_radius() + CAMERA_SHELL_MARGIN, CAMERA_TWEEN_SECONDS) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


# ============================================================================
# STAR AND LINE RENDERING
# ============================================================================

func _build_stars() -> void:
	for node in RoguelikeRun.campaign["nodes"].values():
		var star := _create_star(node)
		_stars_root.add_child(star)


func _create_star(node: Dictionary) -> Area3D:
	var node_id: String = node["id"]
	var area := Area3D.new()
	area.name = node_id
	area.position = CampaignSystem.node_position(node)
	area.input_ray_pickable = true
	area.input_event.connect(_on_star_input_event.bind(node_id))
	area.mouse_entered.connect(_on_star_mouse_entered.bind(node_id))
	area.mouse_exited.connect(_on_star_mouse_exited.bind(node_id))

	var collision := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = STAR_PICK_RADIUS
	collision.shape = sphere
	area.add_child(collision)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission_energy_multiplier = BASE_EMISSION_ENERGY

	var mesh_instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = STAR_RADIUS
	mesh.height = STAR_RADIUS * 2.0
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	area.add_child(mesh_instance)

	var label := Label3D.new()
	# Node name on top line; type + jump cost below.
	label.text = "%s\n%s  +%d" % [node["name"], NODE_TYPE_NAMES[node["type"]], int(node["star_date_gap"])]
	label.position = STAR_LABEL_OFFSET
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Constant on-screen size so labels stay readable at any orbit distance.
	label.fixed_size = true
	label.pixel_size = STAR_LABEL_PIXEL_SIZE
	label.font_size = STAR_LABEL_FONT_SIZE
	area.add_child(label)

	_star_areas[node_id] = area
	_star_materials[node_id] = material
	_star_labels[node_id] = label
	return area


func _build_line_mesh() -> void:
	_lines.mesh = ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_lines.material_override = material


func _refresh_map() -> void:
	_update_star_visuals()
	_rebuild_connection_lines()
	_update_ui_labels()
	_update_fleet_status()


func _update_star_visuals() -> void:
	var campaign: Dictionary = RoguelikeRun.campaign
	var current_sector: String = campaign["current_sector"]
	for node in campaign["nodes"].values():
		var node_id: String = node["id"]
		# The current node stays bright even when it sits in the previous
		# sector (just after a promotion), so the player can see where the
		# bridge jump starts.
		var in_current_sector: bool = node["sector"] == current_sector \
			or node_id == campaign["current_node_id"]
		var color := _star_color(node, campaign)
		color.a = 1.0 if in_current_sector else DIMMED_SECTOR_ALPHA
		_star_materials[node_id].albedo_color = color
		_star_materials[node_id].emission = Color(color.r, color.g, color.b)
		_star_areas[node_id].input_ray_pickable = in_current_sector
		_star_labels[node_id].modulate = Color(1, 1, 1,
			1.0 if in_current_sector else DIMMED_SECTOR_ALPHA)
		_star_labels[node_id].text = "%s\n%s  +%d" % [
			node["name"], NODE_TYPE_NAMES[node["type"]], int(node["star_date_gap"])]


func _star_color(node: Dictionary, campaign: Dictionary) -> Color:
	if node["id"] == campaign["current_node_id"]:
		return CURRENT_POSITION_COLOR
	if node["visited"]:
		return VISITED_COLOR
	if node["accessible"]:
		return NODE_TYPE_COLORS[node["type"]]
	return LOCKED_COLOR


func _rebuild_connection_lines() -> void:
	var mesh: ImmediateMesh = _lines.mesh
	mesh.clear_surfaces()
	var campaign: Dictionary = RoguelikeRun.campaign
	if campaign["connections"].is_empty():
		return
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for connection in campaign["connections"]:
		var from_node := CampaignSystem.node_by_id(campaign, connection["from_id"])
		var to_node := CampaignSystem.node_by_id(campaign, connection["to_id"])
		var color := _line_color(connection, from_node, to_node, campaign)
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(CampaignSystem.node_position(from_node))
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(CampaignSystem.node_position(to_node))
	mesh.surface_end()


func _line_color(connection: Dictionary, from_node: Dictionary, to_node: Dictionary,
		campaign: Dictionary) -> Color:
	var color := LINE_DIM_COLOR
	if connection["bridge"]:
		color = BRIDGE_LINE_COLOR
	elif from_node["visited"] and to_node["accessible"]:
		color = LINE_OPEN_COLOR
	elif from_node["visited"] or to_node["visited"]:
		color = LINE_VISITED_COLOR

	var current_sector: String = campaign["current_sector"]
	if from_node["sector"] != current_sector and to_node["sector"] != current_sector:
		color.a = minf(color.a, DIMMED_SECTOR_ALPHA)
	return color


func _pulse_current_node() -> void:
	var current_id: String = RoguelikeRun.campaign.get("current_node_id", "")
	if current_id == "" or not _star_materials.has(current_id):
		return
	var pulse := 1.0 + CURRENT_NODE_PULSE_DEPTH * sin(
		Time.get_ticks_msec() / 1000.0 * CURRENT_NODE_PULSE_SPEED)
	_star_materials[current_id].emission_energy_multiplier = BASE_EMISSION_ENERGY * pulse


# ============================================================================
# UI PANEL
# ============================================================================

func _update_ui_labels() -> void:
	_sector_label.text = "Sector %s" % RoguelikeRun.campaign["current_sector"]
	var text := "Stardate %d - select your next destination" % RoguelikeRun.current_star_date
	if _status_message != "":
		text = _status_message + "\n" + text
		_status_message = ""
	_info_label.text = text


func _show_repair_summary(summary: Dictionary) -> void:
	if summary.get("ships_repaired", 0) <= 0:
		return
	_info_label.text += "\nEngineers repaired %d ship(s) (+%d) over %d star dates." % [
		summary["ships_repaired"], summary["points_repaired"], summary["date_delta"]]


## Report the economy outcome of the last battle: credits earned for enemies
## destroyed, and insurance paid out for crew lost.
func _show_battle_summary(summary: Dictionary) -> void:
	if summary.is_empty():
		return
	var reward: int = summary.get("reward", 0)
	if reward > 0:
		_info_label.text += "\nBattle reward: +%d credits." % reward
	var casualties: int = summary.get("casualties", 0)
	if casualties > 0:
		_info_label.text += "\nCrew lost: %d." % casualties
	var insurance: int = summary.get("insurance", 0)
	if insurance > 0:
		_info_label.text += "\nInsurance paid out: -%d credits." % insurance


## Delegate fleet condition rendering to FleetConditionPanel.
func _update_fleet_status() -> void:
	_fleet_panel.refresh(RoguelikeRun.money, RoguelikeRun.fleet_hulls)
