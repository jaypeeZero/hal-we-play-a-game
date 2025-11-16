class_name ShipData
extends RefCounted

## Pure data container and factory for ship instances
## Provides templates for Fighter, Corvette, and Capital ships

static var _next_ship_id: int = 0

## Get ship template by type
static func get_ship_template(ship_type: String) -> Dictionary:
	match ship_type:
		"fighter":
			return _create_fighter_template()
		"corvette":
			return _create_corvette_template()
		"capital":
			return _create_capital_template()
		_:
			return {}

## Create a ship instance from template with crew
static func create_ship_instance(ship_type: String, team: int, position: Vector2, create_crew: bool = false, crew_skill: float = 0.5) -> Dictionary:
	var template = get_ship_template(ship_type)
	if template.is_empty():
		return {}

	var instance = template.duplicate(true)
	instance.ship_id = "ship_" + str(_next_ship_id)
	_next_ship_id += 1
	instance.team = team
	instance.position = position
	instance.rotation = 0.0 if team == 0 else PI  # Face opposing directions
	instance.velocity = Vector2.ZERO
	instance.angular_velocity = 0.0
	instance.status = "operational"

	# Create crew for ship if requested
	if create_crew:
		var crew = create_crew_for_ship(instance, crew_skill)
		instance.crew = crew

	return instance

## Create crew for ship based on type
static func create_crew_for_ship(ship_data: Dictionary, skill_level: float = 0.5) -> Array:
	match ship_data.type:
		"fighter":
			# Solo pilot for fighters
			var crew = CrewData.create_solo_fighter_crew(skill_level)
			for member in crew:
				member.assigned_to = ship_data.ship_id
			return crew
		"corvette":
			# Captain, pilot, and gunners for corvette
			var weapon_count = ship_data.weapons.size()
			var crew = CrewData.create_ship_crew(weapon_count, skill_level)
			for member in crew:
				member.assigned_to = ship_data.ship_id
			return crew
		"capital":
			# Full crew for capital ships
			var weapon_count = ship_data.weapons.size()
			var crew = CrewData.create_ship_crew(weapon_count, skill_level)
			for member in crew:
				member.assigned_to = ship_data.ship_id
			return crew
		_:
			return []

## Validate ship data structure
static func validate_ship_data(data: Dictionary) -> bool:
	if not data.has("ship_id"): return false
	if not data.has("type"): return false
	if not data.has("team"): return false
	if not data.has("position"): return false
	if not data.has("stats"): return false
	if not data.has("armor_sections"): return false
	if not data.has("internals"): return false
	if not data.has("weapons"): return false
	return true

## Fighter template - fast, weak armor, low damage
static func _create_fighter_template() -> Dictionary:
	return {
		"type": "fighter",
		"name": "Fighter",
		"stats": {
			"max_speed": 300.0,
			"acceleration": 100.0,
			"turn_rate": 3.0,  # radians per second
			"mass": 50.0,
			"size": 15.0  # visual/collision size
		},
		"armor_sections": [
			{
				"section_id": "nose",
				"position_offset": Vector2(0, -8),
				"arc": {"start": -60, "end": 60},  # degrees from forward
				"max_armor": 20,
				"current_armor": 20,
				"size": 8
			},
			{
				"section_id": "body",
				"position_offset": Vector2(0, 0),
				"arc": {"start": 60, "end": 300},  # sides and rear
				"max_armor": 30,
				"current_armor": 30,
				"size": 10
			},
			{
				"section_id": "tail",
				"position_offset": Vector2(0, 8),
				"arc": {"start": 300, "end": 420},  # rear arc (wraps around)
				"max_armor": 15,
				"current_armor": 15,
				"size": 6
			}
		],
		"internals": [
			{
				"component_id": "cockpit",
				"type": "control",
				"position_offset": Vector2(0, -3),
				"max_health": 20,
				"current_health": 20,
				"status": "operational",
				"effect_on_ship": {
					"on_damaged": {"turn_rate": 0.6, "accuracy": 0.7},
					"on_destroyed": {"ai_disabled": true}
				}
			},
			{
				"component_id": "engine",
				"type": "engine",
				"position_offset": Vector2(0, 6),
				"max_health": 25,
				"current_health": 25,
				"status": "operational",
				"effect_on_ship": {
					"on_damaged": {"max_speed": 0.6, "acceleration": 0.5},
					"on_destroyed": {"max_speed": 0.1, "acceleration": 0.1}
				}
			}
		],
		"weapons": [
			{
				"weapon_id": "guns",
				"type": "light_cannon",
				"position_offset": Vector2(0, -5),
				"facing": 0.0,
				"arc": {"min": -20, "max": 20},  # degrees
				"stats": {
					"damage": 5,
					"rate_of_fire": 5.0,  # shots per second
					"projectile_speed": 600,
					"range": 800,
					"accuracy": 0.85
				},
				"cooldown_remaining": 0.0,
				"operator_id": null
			}
		],
		"orders": {
			"current_order": "engage",
			"target_id": null,
			"patrol_points": []
		}
	}

## Corvette template - medium speed, heavy armor, medium damage
static func _create_corvette_template() -> Dictionary:
	return {
		"type": "corvette",
		"name": "Corvette",
		"stats": {
			"max_speed": 150.0,
			"acceleration": 50.0,
			"turn_rate": 1.5,
			"mass": 200.0,
			"size": 25.0
		},
		"armor_sections": [
			{
				"section_id": "front",
				"position_offset": Vector2(0, -15),
				"arc": {"start": -45, "end": 45},
				"max_armor": 100,
				"current_armor": 100,
				"size": 12
			},
			{
				"section_id": "left",
				"position_offset": Vector2(-10, 0),
				"arc": {"start": 45, "end": 135},
				"max_armor": 80,
				"current_armor": 80,
				"size": 15
			},
			{
				"section_id": "right",
				"position_offset": Vector2(10, 0),
				"arc": {"start": 225, "end": 315},
				"max_armor": 80,
				"current_armor": 80,
				"size": 15
			},
			{
				"section_id": "rear",
				"position_offset": Vector2(0, 15),
				"arc": {"start": 135, "end": 225},
				"max_armor": 60,
				"current_armor": 60,
				"size": 12
			}
		],
		"internals": [
			{
				"component_id": "power_core",
				"type": "power",
				"position_offset": Vector2(0, -8),
				"max_health": 50,
				"current_health": 50,
				"status": "operational",
				"effect_on_ship": {
					"on_damaged": {"weapon_power": 0.5},
					"on_destroyed": {"disabled": true}
				}
			},
			{
				"component_id": "bridge",
				"type": "control",
				"position_offset": Vector2(0, 0),
				"max_health": 40,
				"current_health": 40,
				"status": "operational",
				"effect_on_ship": {
					"on_damaged": {"turn_rate": 0.5, "accuracy": 0.7},
					"on_destroyed": {"ai_disabled": true}
				}
			},
			{
				"component_id": "engines",
				"type": "engine",
				"position_offset": Vector2(0, 10),
				"max_health": 60,
				"current_health": 60,
				"status": "operational",
				"effect_on_ship": {
					"on_damaged": {"max_speed": 0.6, "acceleration": 0.5},
					"on_destroyed": {"max_speed": 0.1, "acceleration": 0.1}
				}
			}
		],
		"weapons": [
			{
				"weapon_id": "turret_1",
				"type": "medium_cannon",
				"position_offset": Vector2(-8, -5),
				"facing": 0.0,
				"arc": {"min": -90, "max": 90},
				"stats": {
					"damage": 15,
					"rate_of_fire": 2.0,
					"projectile_speed": 500,
					"range": 1000,
					"accuracy": 0.80
				},
				"cooldown_remaining": 0.0,
				"operator_id": null
			},
			{
				"weapon_id": "turret_2",
				"type": "medium_cannon",
				"position_offset": Vector2(8, -5),
				"facing": 0.0,
				"arc": {"min": -90, "max": 90},
				"stats": {
					"damage": 15,
					"rate_of_fire": 2.0,
					"projectile_speed": 500,
					"range": 1000,
					"accuracy": 0.80
				},
				"cooldown_remaining": 0.0,
				"operator_id": null
			}
		],
		"orders": {
			"current_order": "engage",
			"target_id": null,
			"patrol_points": []
		}
	}

## Capital template - slow, very heavy armor, high damage
static func _create_capital_template() -> Dictionary:
	return {
		"type": "capital",
		"name": "Capital Ship",
		"stats": {
			"max_speed": 80.0,
			"acceleration": 20.0,
			"turn_rate": 0.5,
			"mass": 1000.0,
			"size": 50.0
		},
		"armor_sections": [
			{
				"section_id": "front_upper",
				"position_offset": Vector2(0, -25),
				"arc": {"start": -30, "end": 30},
				"max_armor": 200,
				"current_armor": 200,
				"size": 20
			},
			{
				"section_id": "front_lower",
				"position_offset": Vector2(0, -15),
				"arc": {"start": -50, "end": 50},
				"max_armor": 200,
				"current_armor": 200,
				"size": 18
			},
			{
				"section_id": "left_fore",
				"position_offset": Vector2(-20, -10),
				"arc": {"start": 50, "end": 110},
				"max_armor": 150,
				"current_armor": 150,
				"size": 22
			},
			{
				"section_id": "left_aft",
				"position_offset": Vector2(-20, 10),
				"arc": {"start": 110, "end": 170},
				"max_armor": 150,
				"current_armor": 150,
				"size": 22
			},
			{
				"section_id": "right_fore",
				"position_offset": Vector2(20, -10),
				"arc": {"start": 250, "end": 310},
				"max_armor": 150,
				"current_armor": 150,
				"size": 22
			},
			{
				"section_id": "right_aft",
				"position_offset": Vector2(20, 10),
				"arc": {"start": 190, "end": 250},
				"max_armor": 150,
				"current_armor": 150,
				"size": 22
			},
			{
				"section_id": "rear",
				"position_offset": Vector2(0, 25),
				"arc": {"start": 170, "end": 190},
				"max_armor": 100,
				"current_armor": 100,
				"size": 15
			}
		],
		"internals": [
			{
				"component_id": "power_core",
				"type": "power",
				"position_offset": Vector2(0, -12),
				"max_health": 200,
				"current_health": 200,
				"status": "operational",
				"effect_on_ship": {
					"on_damaged": {"weapon_power": 0.5},
					"on_destroyed": {"disabled": true}
				}
			},
			{
				"component_id": "bridge",
				"type": "control",
				"position_offset": Vector2(0, 0),
				"max_health": 100,
				"current_health": 100,
				"status": "operational",
				"effect_on_ship": {
					"on_damaged": {"turn_rate": 0.5, "accuracy": 0.7},
					"on_destroyed": {"ai_disabled": true}
				}
			},
			{
				"component_id": "engines_main",
				"type": "engine",
				"position_offset": Vector2(0, 20),
				"max_health": 150,
				"current_health": 150,
				"status": "operational",
				"effect_on_ship": {
					"on_damaged": {"max_speed": 0.6, "acceleration": 0.5},
					"on_destroyed": {"max_speed": 0.1, "acceleration": 0.1}
				}
			}
		],
		"weapons": [
			{
				"weapon_id": "turret_1",
				"type": "heavy_cannon",
				"position_offset": Vector2(-15, -10),
				"facing": 0.0,
				"arc": {"min": -120, "max": 120},
				"stats": {
					"damage": 50,
					"rate_of_fire": 0.5,
					"projectile_speed": 450,
					"range": 1500,
					"accuracy": 0.75
				},
				"cooldown_remaining": 0.0,
				"operator_id": null
			},
			{
				"weapon_id": "turret_2",
				"type": "heavy_cannon",
				"position_offset": Vector2(15, -10),
				"facing": 0.0,
				"arc": {"min": -120, "max": 120},
				"stats": {
					"damage": 50,
					"rate_of_fire": 0.5,
					"projectile_speed": 450,
					"range": 1500,
					"accuracy": 0.75
				},
				"cooldown_remaining": 0.0,
				"operator_id": null
			},
			{
				"weapon_id": "turret_3",
				"type": "medium_cannon",
				"position_offset": Vector2(-12, 5),
				"facing": 0.0,
				"arc": {"min": -90, "max": 90},
				"stats": {
					"damage": 15,
					"rate_of_fire": 2.0,
					"projectile_speed": 500,
					"range": 1000,
					"accuracy": 0.80
				},
				"cooldown_remaining": 0.0,
				"operator_id": null
			},
			{
				"weapon_id": "turret_4",
				"type": "medium_cannon",
				"position_offset": Vector2(12, 5),
				"facing": 0.0,
				"arc": {"min": -90, "max": 90},
				"stats": {
					"damage": 15,
					"rate_of_fire": 2.0,
					"projectile_speed": 500,
					"range": 1000,
					"accuracy": 0.80
				},
				"cooldown_remaining": 0.0,
				"operator_id": null
			}
		],
		"orders": {
			"current_order": "engage",
			"target_id": null,
			"patrol_points": []
		}
	}
