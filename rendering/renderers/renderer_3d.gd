class_name Renderer3D extends IVisualRenderer

## Renders entities as 3D models on a battle plane beneath the 2D game world.
##
## A single full-screen SubViewport hosts a 3D world whose orthographic
## top-down Camera3D is slaved to the game's Camera2D every frame, so 3D
## world coordinates land on screen exactly where 2D world coordinates do
## (see Space3DMapping). Gameplay-information overlays (wing circles,
## repair pulses, debug labels) stay in the 2D world via EntityOverlays2D.

const SHIP_VISUALS_PATH := "res://data/ship_visuals.json"

## Canvas layer below the default 2D world so overlays draw on top.
const VIEW_LAYER: int = -1

const CAMERA_HEIGHT: float = 1000.0
const CAMERA_NEAR: float = 10.0
const CAMERA_FAR: float = 4000.0

## Key light angled for readable top-lit hull forms.
const LIGHT_PITCH_DEG: float = -55.0
const LIGHT_YAW_DEG: float = -30.0
const LIGHT_ENERGY: float = 1.2
const AMBIENT_COLOR: Color = Color(0.55, 0.6, 0.75)
const AMBIENT_ENERGY: float = 0.8

## Team accent tints multiplied into hull albedo (team index -> tint).
const TEAM_TINTS: Array[Color] = [Color(0.8, 0.9, 1.25), Color(1.3, 0.75, 0.75)]

## Engine flame dimensions relative to the ship's base size.
const FLAME_LENGTH_FACTOR: float = 0.7
const FLAME_RADIUS_FACTOR: float = 0.18
const FLAME_COLOR: Color = Color(1.0, 0.6, 0.15)
const FLAME_EMISSION_ENERGY: float = 2.5

## Section damage effects: smoke below the first threshold, fire color
## below the second. Matches the "armor weakening" thresholds players
## previously read from section color shifts.
const SMOKE_ARMOR_THRESHOLD: float = 0.5
const FIRE_ARMOR_THRESHOLD: float = 0.2
const SMOKE_COLOR: Color = Color(0.25, 0.25, 0.28, 0.7)
const FIRE_COLOR: Color = Color(1.0, 0.45, 0.1, 0.85)
const SMOKE_PARTICLE_AMOUNT: int = 16
const SMOKE_LIFETIME: float = 1.4
const SMOKE_SCALE_FACTOR: float = 0.15

## Projectile visuals.
const PROJECTILE_RADIUS: float = 3.5
const TORPEDO_RADIUS: float = 6.0
const PROJECTILE_COLOR: Color = Color(0.5, 0.85, 1.0)
const TORPEDO_COLOR: Color = Color(1.0, 0.55, 0.2)
const PROJECTILE_EMISSION_ENERGY: float = 3.0

## Impact/explosion effect visuals (radius, color) per effect type.
const EFFECT_STYLES: Dictionary = {
	"effect_armor_hit": [8.0, Color(1.0, 0.9, 0.5)],
	"effect_armor_penetration": [12.0, Color(1.0, 0.6, 0.2)],
	"effect_internal_damage": [14.0, Color(1.0, 0.3, 0.15)],
	"effect_torpedo_explosion": [60.0, Color(1.0, 0.5, 0.1)],
}
const EFFECT_DEFAULT_RADIUS: float = 10.0
const EFFECT_DEFAULT_COLOR: Color = Color(1.0, 0.8, 0.4)

## Destruction effect timing.
const DESTRUCTION_FLASH_TIME: float = 0.15
const DESTRUCTION_FADE_TIME: float = 0.85
const DESTRUCTION_PARTICLE_AMOUNT: int = 48

const FALLBACK_BOX_SIZE: float = 20.0

var _canvas_layer: CanvasLayer
var _viewport: SubViewport
var _world: Node3D
var _camera_3d: Camera3D

var _ship_visual_config: Dictionary = {}
var _model_scene_cache: Dictionary = {}  # model path -> PackedScene
var _team_material_cache: Dictionary = {}  # "path|team|surface" -> Material

# entity_id -> {root: Node3D, entity, type, overlay: Node2D, engines: Dictionary,
#               smoke: Dictionary, effect_material: Material, destroyed: bool}
var _visuals: Dictionary = {}

# Shared meshes/materials built once.
var _projectile_mesh: SphereMesh
var _torpedo_mesh: SphereMesh
var _flame_mesh: CylinderMesh
var _smoke_quad: QuadMesh
var _smoke_material: StandardMaterial3D
var _fire_material: StandardMaterial3D

# Projectiles render as two batched MultiMeshes (standard + torpedo) instead of
# one node per projectile — a single draw call each, refilled from data per frame.
var _projectile_multimesh: MultiMesh
var _torpedo_multimesh: MultiMesh

func initialize() -> void:
	name = "Renderer3D"
	_ship_visual_config = _load_ship_visual_config()
	_build_shared_resources()
	_build_view()

func cleanup() -> void:
	for entity_id in _visuals.keys():
		var visual: Dictionary = _visuals[entity_id]
		if is_instance_valid(visual.entity):
			detach_from_entity(visual.entity)
	_visuals.clear()
	if is_instance_valid(_canvas_layer):
		_canvas_layer.queue_free()

func attach_to_entity(entity: IRenderable) -> void:
	var entity_id: String = entity.get_entity_id()
	var visual_type: String = entity.get_visual_type()

	var root := Node3D.new()
	root.name = "Visual3D_" + entity_id

	if visual_type.begins_with("ship_"):
		_build_ship_visual(root, entity, visual_type)
	elif visual_type.begins_with("effect_"):
		pass  # Mesh added below; needs the per-instance material recorded
	else:
		_build_fallback_visual(root)

	_world.add_child(root)

	# 2D overlay container for gameplay info (wing circles, debug labels)
	var overlay := Node2D.new()
	overlay.name = "GameplayOverlays"
	entity.add_child(overlay)

	var visual := {
		"root": root,
		"entity": entity,
		"type": visual_type,
		"overlay": overlay,
		"engines": {},
		"smoke": {},
		"destroyed": false,
	}

	if visual_type.begins_with("effect_"):
		visual["effect_material"] = _build_effect_visual(root, visual_type)

	_visuals[entity_id] = visual
	_sync_visual_transform(visual)

func detach_from_entity(entity: IRenderable) -> void:
	var entity_id := entity.get_entity_id()
	if not _visuals.has(entity_id):
		return
	var visual: Dictionary = _visuals[entity_id]
	if is_instance_valid(visual.root):
		visual.root.queue_free()
	if is_instance_valid(visual.overlay):
		visual.overlay.queue_free()
	_visuals.erase(entity_id)

func update_state(entity_id: String, state: EntityState) -> void:
	if not _visuals.has(entity_id):
		return
	var visual: Dictionary = _visuals[entity_id]
	if not is_instance_valid(visual.root):
		return

	if visual.type.begins_with("ship_"):
		_update_engines(visual, state.components, state.is_main_engine_firing)
		_update_section_damage_effects(visual, state.section_damage)
		if state.has_flag("destroyed") and not visual.destroyed:
			visual.destroyed = true
			_play_destruction(visual)
		if is_instance_valid(visual.overlay):
			EntityOverlays2D.update_wing_circle(visual.overlay, state.wing_color)
			EntityOverlays2D.update_repair_indicator(visual.overlay, state.has_flag("repairing"))
			EntityOverlays2D.update_pilot_direction_line(visual.overlay, state.debug_pilot_direction)
			EntityOverlays2D.update_leader_number(visual.overlay, state.debug_leader_number)
	elif visual.type.begins_with("effect_"):
		_update_effect_fade(visual, state.health_percent)

func play_animation(_entity_id: String, _request: AnimationRequest) -> void:
	pass  # State changes drive all visuals in this renderer

func _process(_delta: float) -> void:
	_sync_camera()
	for entity_id in _visuals:
		_sync_visual_transform(_visuals[entity_id])

# ============================================================================
# VIEW SETUP
# ============================================================================

func _build_view() -> void:
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.name = "Renderer3DView"
	_canvas_layer.layer = VIEW_LAYER
	add_child(_canvas_layer)

	var container := SubViewportContainer.new()
	container.name = "ViewContainer"
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas_layer.add_child(container)

	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	container.add_child(_viewport)

	_world = Node3D.new()
	_world.name = "BattleWorld3D"
	_viewport.add_child(_world)

	_build_projectile_batches()

	_camera_3d = Camera3D.new()
	_camera_3d.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera_3d.position = Vector3(0.0, CAMERA_HEIGHT, 0.0)
	_camera_3d.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_camera_3d.near = CAMERA_NEAR
	_camera_3d.far = CAMERA_FAR
	_world.add_child(_camera_3d)
	_camera_3d.make_current()

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(LIGHT_PITCH_DEG, LIGHT_YAW_DEG, 0.0)
	light.light_energy = LIGHT_ENERGY
	_world.add_child(light)

	var environment := Environment.new()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = AMBIENT_COLOR
	environment.ambient_light_energy = AMBIENT_ENERGY
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_world.add_child(world_environment)

func _sync_camera() -> void:
	var camera_2d := get_viewport().get_camera_2d()
	var viewport_size := get_viewport().get_visible_rect().size
	if camera_2d:
		var center := camera_2d.get_screen_center_position()
		_camera_3d.position = Space3DMapping.to_3d_position(center, CAMERA_HEIGHT)
		_camera_3d.size = Space3DMapping.ortho_size_for_zoom(viewport_size.y, camera_2d.zoom.y)
	else:
		# No Camera2D (e.g. UI preview scenes): match the identity 2D view
		var center := viewport_size / 2.0
		_camera_3d.position = Space3DMapping.to_3d_position(center, CAMERA_HEIGHT)
		_camera_3d.size = Space3DMapping.ortho_size_for_zoom(viewport_size.y, 1.0)

func _sync_visual_transform(visual: Dictionary) -> void:
	var entity = visual.entity
	if not is_instance_valid(entity) or not is_instance_valid(visual.root):
		return
	visual.root.position = Space3DMapping.to_3d_position(entity.global_position)
	visual.root.rotation = Vector3(0.0, Space3DMapping.to_3d_yaw(entity.rotation), 0.0)

# ============================================================================
# SHIP VISUALS
# ============================================================================

func _load_ship_visual_config() -> Dictionary:
	var file := FileAccess.open(SHIP_VISUALS_PATH, FileAccess.READ)
	if file == null:
		push_error("Renderer3D: cannot open " + SHIP_VISUALS_PATH)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed == null or not parsed is Dictionary:
		push_error("Renderer3D: invalid JSON in " + SHIP_VISUALS_PATH)
		return {}
	return parsed

func _build_ship_visual(root: Node3D, entity: IRenderable, visual_type: String) -> void:
	var ship_type := visual_type.replace("ship_", "")
	var team: int = entity.get_ship_data().get("team", 0) if entity.has_method("get_ship_data") else 0

	if not _ship_visual_config.has(ship_type):
		push_warning("Renderer3D: no visual config for ship type " + ship_type)
		_build_fallback_visual(root)
		return

	var config: Dictionary = _ship_visual_config[ship_type]
	var model_path: String = config.model
	if not _model_scene_cache.has(model_path):
		_model_scene_cache[model_path] = load(model_path)
	var scene: PackedScene = _model_scene_cache[model_path]
	if scene == null:
		push_warning("Renderer3D: failed to load model " + model_path)
		_build_fallback_visual(root)
		return

	var model: Node3D = scene.instantiate()
	model.name = "Model"
	# Auto-fit the model to the ship's footprint so any model drops in at the
	# right size regardless of its authored scale; `scale` is a fine-tune
	# multiplier (1.0 = exactly the footprint).
	_fit_model_to_footprint(model, HullShapes.get_base_size(ship_type) * float(config.get("scale", 1.0)))
	model.rotation_degrees = Vector3(0.0, float(config.get("yaw_offset_deg", 0.0)), 0.0)
	root.add_child(model)

	_apply_team_tint(model, model_path, team)
	root.set_meta("ship_type", ship_type)

## Scale and recenter a model so its largest horizontal extent equals the target
## footprint (game units == world units here), centered on the ship's origin.
func _fit_model_to_footprint(model: Node3D, footprint: float) -> void:
	var aabb: AABB = _merged_aabb(model, Transform3D.IDENTITY)
	var extent: float = maxf(aabb.size.x, aabb.size.z)
	if extent <= 0.0:
		return
	var factor: float = footprint / extent
	model.scale = Vector3.ONE * factor
	model.position = -aabb.get_center() * factor

## Merge the AABBs of every MeshInstance3D under a node, in the node's local space.
func _merged_aabb(node: Node, xform: Transform3D) -> AABB:
	var result := AABB()
	var has_any := false
	if node is MeshInstance3D and node.mesh != null:
		result = xform * node.mesh.get_aabb()
		has_any = true
	for child in node.get_children():
		var child_xform := xform
		if child is Node3D:
			child_xform = xform * child.transform
		var child_box := _merged_aabb(child, child_xform)
		if child_box.size != Vector3.ZERO:
			result = result.merge(child_box) if has_any else child_box
			has_any = true
	return result

func _apply_team_tint(model: Node3D, model_path: String, team: int) -> void:
	var tint: Color = TEAM_TINTS[clampi(team, 0, TEAM_TINTS.size() - 1)]
	for mesh_instance in model.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh_instance.get_surface_override_material_count():
			var cache_key := "%s|%d|%d" % [model_path, team, surface]
			if not _team_material_cache.has(cache_key):
				var material = mesh_instance.get_active_material(surface)
				if not material is BaseMaterial3D:
					continue
				var tinted: BaseMaterial3D = material.duplicate()
				tinted.albedo_color = tint
				_team_material_cache[cache_key] = tinted
			mesh_instance.set_surface_override_material(surface, _team_material_cache[cache_key])

func _update_engines(visual: Dictionary, components: Array[Dictionary], is_main_engine_firing: bool) -> void:
	var engines: Dictionary = visual.engines
	var ship_type: String = visual.root.get_meta("ship_type", "fighter")
	var flame_scale := HullShapes.get_base_size(ship_type)

	for component_data in components:
		if component_data.component_type != "engine":
			continue
		var component_id: String = component_data.component_id
		if not engines.has(component_id):
			engines[component_id] = _create_engine_flame(visual.root, flame_scale)
		var flame: MeshInstance3D = engines[component_id]
		if not is_instance_valid(flame):
			continue
		var offset: Vector2 = component_data.position_offset
		# Flame extends backward (+Z in ship-local space); anchor at the engine
		flame.position = Space3DMapping.to_3d_local_offset(offset) \
			+ Vector3(0.0, 0.0, flame_scale * FLAME_LENGTH_FACTOR / 2.0)
		flame.visible = is_main_engine_firing and component_data.status != "destroyed"

func _create_engine_flame(root: Node3D, flame_scale: float) -> MeshInstance3D:
	var flame := MeshInstance3D.new()
	flame.mesh = _flame_mesh
	# Cylinder axis is Y; rotate so the cone points backward along +Z
	flame.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	flame.scale = Vector3.ONE * flame_scale
	flame.visible = false
	root.add_child(flame)
	return flame

func _update_section_damage_effects(visual: Dictionary, section_damage: Array[Dictionary]) -> void:
	if visual.destroyed:
		return
	var ship_type: String = visual.root.get_meta("ship_type", "")
	for section in section_damage:
		var armor_percent: float = section.armor_percent
		var section_id: String = section.section_id
		var smoke: GPUParticles3D = visual.smoke.get(section_id)

		if armor_percent >= SMOKE_ARMOR_THRESHOLD:
			if is_instance_valid(smoke):
				smoke.emitting = false
			continue

		if smoke == null:
			smoke = _create_section_smoke(visual.root, ship_type, section_id)
			visual.smoke[section_id] = smoke
		if not is_instance_valid(smoke):
			continue
		smoke.material_override = _fire_material if armor_percent < FIRE_ARMOR_THRESHOLD else _smoke_material
		smoke.emitting = true

func _create_section_smoke(root: Node3D, ship_type: String, section_id: String) -> GPUParticles3D:
	var smoke := GPUParticles3D.new()
	smoke.name = "Smoke_" + section_id
	smoke.amount = SMOKE_PARTICLE_AMOUNT
	smoke.lifetime = SMOKE_LIFETIME
	smoke.local_coords = false
	smoke.draw_pass_1 = _smoke_quad
	smoke.material_override = _smoke_material

	var base_size := HullShapes.get_base_size(ship_type)
	var process := ParticleProcessMaterial.new()
	process.gravity = Vector3.ZERO
	process.initial_velocity_min = base_size * 0.1
	process.initial_velocity_max = base_size * 0.3
	process.spread = 180.0
	process.scale_min = base_size * SMOKE_SCALE_FACTOR * 0.5
	process.scale_max = base_size * SMOKE_SCALE_FACTOR
	smoke.process_material = process

	smoke.position = Space3DMapping.to_3d_local_offset(_section_centroid(ship_type, section_id))
	root.add_child(smoke)
	return smoke

## Anchor point for a section's damage effects: centroid of its hull polygon.
func _section_centroid(ship_type: String, section_id: String) -> Vector2:
	for section in HullShapes.get_sections(ship_type):
		if section.section_id != section_id:
			continue
		var sum := Vector2.ZERO
		var points: Array = section.points
		for point in points:
			sum += Vector2(point.x, point.y)
		return sum / points.size() if points.size() > 0 else Vector2.ZERO
	return Vector2.ZERO

func _play_destruction(visual: Dictionary) -> void:
	var root: Node3D = visual.root

	# Silence ongoing effects
	for flame in visual.engines.values():
		if is_instance_valid(flame):
			flame.visible = false
	for smoke in visual.smoke.values():
		if is_instance_valid(smoke):
			smoke.emitting = false

	# One-shot explosion burst
	var ship_type: String = root.get_meta("ship_type", "fighter")
	var base_size := HullShapes.get_base_size(ship_type)
	var explosion := GPUParticles3D.new()
	explosion.one_shot = true
	explosion.emitting = true
	explosion.amount = DESTRUCTION_PARTICLE_AMOUNT
	explosion.lifetime = DESTRUCTION_FLASH_TIME + DESTRUCTION_FADE_TIME
	explosion.local_coords = false
	explosion.draw_pass_1 = _smoke_quad
	explosion.material_override = _fire_material
	var process := ParticleProcessMaterial.new()
	process.gravity = Vector3.ZERO
	process.initial_velocity_min = base_size * 0.8
	process.initial_velocity_max = base_size * 2.0
	process.spread = 180.0
	process.scale_min = base_size * SMOKE_SCALE_FACTOR
	process.scale_max = base_size * SMOKE_SCALE_FACTOR * 2.0
	explosion.process_material = process
	root.add_child(explosion)

	# Hull flashes then collapses
	var model: Node3D = root.get_node_or_null("Model")
	if model:
		var tween := root.create_tween()
		tween.tween_property(model, "scale", model.scale * 1.15, DESTRUCTION_FLASH_TIME)
		tween.tween_property(model, "scale", Vector3.ONE * 0.001, DESTRUCTION_FADE_TIME)

# ============================================================================
# PROJECTILES, EFFECTS, FALLBACK
# ============================================================================

## Build the two projectile MultiMeshes (standard + torpedo) and their instances
## in the 3D world. Each is a single draw call; per-frame work is just writing
## instance transforms in update_projectiles().
func _build_projectile_batches() -> void:
	_projectile_multimesh = _make_projectile_multimesh(_projectile_mesh)
	_torpedo_multimesh = _make_projectile_multimesh(_torpedo_mesh)
	_add_multimesh_instance(_projectile_multimesh, PROJECTILE_COLOR, "Projectiles")
	_add_multimesh_instance(_torpedo_multimesh, TORPEDO_COLOR, "Torpedoes")

func _make_projectile_multimesh(mesh: Mesh) -> MultiMesh:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = 0
	return multimesh

func _add_multimesh_instance(multimesh: MultiMesh, color: Color, node_name: String) -> void:
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.material_override = _make_emissive_material(color, PROJECTILE_EMISSION_ENERGY)
	_world.add_child(instance)

## Refill both projectile MultiMeshes from the live projectile data each frame.
func update_projectiles(projectiles: Array) -> void:
	var standard_count := 0
	var torpedo_count := 0
	for projectile in projectiles:
		if projectile == null:
			continue
		if projectile.get("projectile_type", "standard") == "explosive":
			torpedo_count += 1
		else:
			standard_count += 1

	# Grow the instance buffer only when needed; visible_instance_count caps what
	# actually draws this frame, so shrinking never reallocates.
	if _projectile_multimesh.instance_count < standard_count:
		_projectile_multimesh.instance_count = standard_count
	if _torpedo_multimesh.instance_count < torpedo_count:
		_torpedo_multimesh.instance_count = torpedo_count
	_projectile_multimesh.visible_instance_count = standard_count
	_torpedo_multimesh.visible_instance_count = torpedo_count

	var standard_index := 0
	var torpedo_index := 0
	for projectile in projectiles:
		if projectile == null:
			continue
		var xform := Transform3D(Basis(), Space3DMapping.to_3d_position(projectile.position))
		if projectile.get("projectile_type", "standard") == "explosive":
			_torpedo_multimesh.set_instance_transform(torpedo_index, xform)
			torpedo_index += 1
		else:
			_projectile_multimesh.set_instance_transform(standard_index, xform)
			standard_index += 1

func _build_effect_visual(root: Node3D, effect_type: String) -> Material:
	var style: Array = EFFECT_STYLES.get(effect_type, [EFFECT_DEFAULT_RADIUS, EFFECT_DEFAULT_COLOR])
	var mesh := SphereMesh.new()
	mesh.radius = style[0]
	mesh.height = style[0] * 2.0
	var material := _make_emissive_material(style[1], PROJECTILE_EMISSION_ENERGY)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var body := MeshInstance3D.new()
	body.mesh = mesh
	body.material_override = material
	root.add_child(body)
	return material

## Effects expand and fade as their remaining life (health_percent) drains.
func _update_effect_fade(visual: Dictionary, health_percent: float) -> void:
	var material: StandardMaterial3D = visual.get("effect_material")
	if material:
		var color: Color = material.albedo_color
		color.a = health_percent
		material.albedo_color = color
	var age := 1.0 - health_percent
	visual.root.scale = Vector3.ONE * (0.3 + 0.7 * age)

func _build_fallback_visual(root: Node3D) -> void:
	var body := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * FALLBACK_BOX_SIZE
	body.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.4, 0.4, 0.45)
	body.material_override = material
	root.add_child(body)

# ============================================================================
# SHARED RESOURCES
# ============================================================================

func _build_shared_resources() -> void:
	_projectile_mesh = SphereMesh.new()
	_projectile_mesh.radius = PROJECTILE_RADIUS
	_projectile_mesh.height = PROJECTILE_RADIUS * 2.0

	_torpedo_mesh = SphereMesh.new()
	_torpedo_mesh.radius = TORPEDO_RADIUS
	_torpedo_mesh.height = TORPEDO_RADIUS * 2.0

	_flame_mesh = CylinderMesh.new()
	_flame_mesh.top_radius = FLAME_RADIUS_FACTOR
	_flame_mesh.bottom_radius = 0.0
	_flame_mesh.height = FLAME_LENGTH_FACTOR
	var flame_material := _make_emissive_material(FLAME_COLOR, FLAME_EMISSION_ENERGY)
	_flame_mesh.material = flame_material

	_smoke_quad = QuadMesh.new()
	_smoke_quad.size = Vector2.ONE

	_smoke_material = _make_particle_material(SMOKE_COLOR)
	_fire_material = _make_particle_material(FIRE_COLOR)

func _make_emissive_material(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material

func _make_particle_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = false
	return material
