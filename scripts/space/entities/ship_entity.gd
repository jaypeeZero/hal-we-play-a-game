class_name ShipEntity
extends IRenderable

## Minimal ship entity for ECS architecture
## Only handles Godot physics/rendering integration
## All logic lives in Systems, all data in ship_data Dictionary

var entity_id: String = ""
var team: int = 0
var ship_type: String = ""

var _area: Area2D

## Initialize entity with ID and team for collision layers
func initialize(id: String, ship_team: int, size: float, ship_class: String = "") -> void:
	entity_id = id
	team = ship_team
	ship_type = ship_class
	_setup_collision(size)

	# Register with visual bridge for rendering
	if VisualBridgeAutoload.bridge:
		VisualBridgeAutoload.bridge.register_entity(self)

## Setup collision area
func _setup_collision(size: float) -> void:
	_area = Area2D.new()
	_area.name = "CollisionArea"
	add_child(_area)

	var shape = CircleShape2D.new()
	shape.radius = size
	var collision_shape = CollisionShape2D.new()
	collision_shape.shape = shape
	_area.add_child(collision_shape)

	# Set collision layers based on team
	if team == 0:
		_area.collision_layer = 4  # Player ships
		_area.collision_mask = 8 | 16  # Hit by enemy projectiles and ships
	else:
		_area.collision_layer = 8  # Enemy ships
		_area.collision_mask = 4 | 32  # Hit by player projectiles and ships

## Sync transform from ship_data (called by game loop)
func sync_transform(ship_data: Dictionary) -> void:
	global_position = ship_data.position
	rotation = ship_data.rotation

## Emit state for renderer (called by game loop)
func emit_state(ship_data: Dictionary) -> void:
	var state = _create_entity_state(ship_data)
	state_changed.emit(state)

## Create entity state for renderer
func _create_entity_state(ship_data: Dictionary) -> EntityState:
	var state = EntityState.new()
	state.velocity = ship_data.velocity
	state.facing_direction = Vector2.from_angle(ship_data.rotation)

	# Calculate health percent
	var total_health = 0.0
	var max_health = 0.0
	for internal in ship_data.internals:
		total_health += internal.current_health
		max_health += internal.max_health

	state.health_percent = total_health / max_health if max_health > 0 else 0.0

	# Add status flags
	match ship_data.status:
		"operational":
			if ship_data.velocity.length() > 10:
				state.add_flag("moving")
		"damaged":
			state.add_flag("damaged")
		"disabled":
			state.add_flag("disabled")
		"destroyed":
			state.add_flag("destroyed")

	# Add component status effects
	for internal in ship_data.internals:
		if internal.status == "damaged":
			state.status_effects.append(internal.component_id + "_damaged")
		elif internal.status == "destroyed":
			state.status_effects.append(internal.component_id + "_destroyed")

	# Calculate per-section damage data
	for section in ship_data.armor_sections:
		var armor_percent = section.current_armor / float(section.max_armor) if section.max_armor > 0 else 0.0

		# Find internals in this section and calculate average health
		var section_internals = ship_data.internals.filter(
			func(internal): return internal.get("section_id", "") == section.section_id
		)

		var internal_percent = 1.0
		if section_internals.size() > 0:
			var total_internal_health = 0.0
			var max_internal_health = 0.0
			for internal in section_internals:
				total_internal_health += internal.current_health
				max_internal_health += internal.max_health
			internal_percent = total_internal_health / max_internal_health if max_internal_health > 0 else 0.0

		state.section_damage.append({
			"section_id": section.section_id,
			"armor_percent": armor_percent,
			"internal_percent": internal_percent
		})

	# Add physicalized components (internals + weapons)
	for internal in ship_data.internals:
		state.components.append({
			"component_id": internal.component_id,
			"component_type": internal.type,
			"visual_type": _get_internal_visual_type(internal.type, ship_data.type),
			"position_offset": internal.position_offset,
			"rotation": 0.0,
			"status": internal.status
		})

	for weapon in ship_data.weapons:
		state.components.append({
			"component_id": weapon.weapon_id,
			"component_type": "weapon",
			"visual_type": _get_weapon_visual_type(weapon.type),
			"position_offset": weapon.position_offset,
			"rotation": weapon.get("facing", 0.0),
			"status": "operational"  # Weapons don't have damage status currently
		})

	return state

## Map internal component types to visual types
func _get_internal_visual_type(internal_type: String, ship_class: String) -> String:
	match internal_type:
		"engine":
			return "engine"
		"control":
			return "control"
		"power":
			return "power_core"
		_:
			return "generic_internal"

## Map weapon types to visual types
func _get_weapon_visual_type(weapon_type: String) -> String:
	match weapon_type:
		"light_cannon":
			return "light_weapon"
		"medium_cannon":
			return "medium_turret"
		"heavy_cannon":
			return "heavy_turret"
		"gatling_gun":
			return "gatling_turret"
		_:
			return "generic_weapon"

## IRenderable implementation
func get_entity_id() -> String:
	return entity_id

func get_visual_type() -> String:
	if ship_type.is_empty():
		return "ship"
	return "ship_" + ship_type

## Clean up
func _exit_tree() -> void:
	if VisualBridgeAutoload.bridge:
		VisualBridgeAutoload.bridge.unregister_entity(self)
