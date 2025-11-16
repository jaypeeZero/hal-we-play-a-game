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
			"acceleration": 100.0,  # Forward thrust (main engines)
			"lateral_acceleration": 30.0,  # Lateral/reverse thrust (maneuvering thrusters)
			"turn_rate": 3.0,  # radians per second
			"mass": 50.0,
			"size": 15.0  # visual/collision size
		},
		"armor_sections": [
			{
				"section_id": "front",
				"position_offset": Vector2(0, -8),
				"arc": {"start": -90, "end": 90},  # front 180 degrees
				"max_armor": 25,
				"current_armor": 25,
				"size": 1
			},
			{
				"section_id": "back",
				"position_offset": Vector2(0, 8),
				"arc": {"start": 90, "end": 270},  # back 180 degrees
				"max_armor": 20,
				"current_armor": 20,
				"size": 1
			}
		],
		"internals": [
			{
				"component_id": "cockpit",
				"type": "control",
				"section_id": "front",
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
				"section_id": "back",
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
					"accuracy": 0.85,
					"size": 1
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
			"acceleration": 50.0,  # Forward thrust (main engines)
			"lateral_acceleration": 15.0,  # Lateral/reverse thrust (maneuvering thrusters)
			"turn_rate": 1.5,
			"mass": 200.0,
			"size": 25.0
		},
		"armor_sections": [
			{
				"section_id": "front",
				"position_offset": Vector2(0, -15),
				"arc": {"start": -60, "end": 60},  # front 120 degrees
				"max_armor": 100,
				"current_armor": 100,
				"size": 2
			},
			{
				"section_id": "middle",
				"position_offset": Vector2(0, 0),
				"arc": {"start": 60, "end": 300},  # middle 240 degrees (sides)
				"max_armor": 90,
				"current_armor": 90,
				"size": 2
			},
			{
				"section_id": "back",
				"position_offset": Vector2(0, 15),
				"arc": {"start": 300, "end": 420},  # back 120 degrees (wraps around)
				"max_armor": 70,
				"current_armor": 70,
				"size": 2
			}
		],
		"internals": [
			{
				"component_id": "power_core",
				"type": "power",
				"section_id": "front",
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
				"section_id": "middle",
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
				"section_id": "back",
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
					"accuracy": 0.80,
					"size": 2
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
					"accuracy": 0.80,
					"size": 2
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
			"acceleration": 20.0,  # Forward thrust (main engines)
			"lateral_acceleration": 5.0,  # Lateral/reverse thrust (maneuvering thrusters)
			"turn_rate": 0.5,
			"mass": 1000.0,
			"size": 50.0
		},
		"armor_sections": [
			{
				"section_id": "front_left",
				"position_offset": Vector2(-10, -20),
				"arc": {"start": 300, "end": 360},  # front left 60 degrees
				"max_armor": 180,
				"current_armor": 180,
				"size": 3
			},
			{
				"section_id": "front_right",
				"position_offset": Vector2(10, -20),
				"arc": {"start": 0, "end": 60},  # front right 60 degrees
				"max_armor": 180,
				"current_armor": 180,
				"size": 3
			},
			{
				"section_id": "middle_right",
				"position_offset": Vector2(20, 0),
				"arc": {"start": 60, "end": 120},  # right side 60 degrees
				"max_armor": 150,
				"current_armor": 150,
				"size": 3
			},
			{
				"section_id": "back_right",
				"position_offset": Vector2(10, 20),
				"arc": {"start": 120, "end": 180},  # back right 60 degrees
				"max_armor": 120,
				"current_armor": 120,
				"size": 3
			},
			{
				"section_id": "back_left",
				"position_offset": Vector2(-10, 20),
				"arc": {"start": 180, "end": 240},  # back left 60 degrees
				"max_armor": 120,
				"current_armor": 120,
				"size": 3
			},
			{
				"section_id": "middle_left",
				"position_offset": Vector2(-20, 0),
				"arc": {"start": 240, "end": 300},  # left side 60 degrees
				"max_armor": 150,
				"current_armor": 150,
				"size": 3
			}
		],
		"internals": [
			{
				"component_id": "power_core",
				"type": "power",
				"section_id": "front_left",
				"position_offset": Vector2(-5, -12),
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
				"section_id": "front_right",
				"position_offset": Vector2(5, -8),
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
				"section_id": "back_left",
				"position_offset": Vector2(-5, 20),
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
					"accuracy": 0.75,
					"size": 3
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
					"accuracy": 0.75,
					"size": 3
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
					"accuracy": 0.80,
					"size": 3
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
					"accuracy": 0.80,
					"size": 3
				},
				"cooldown_remaining": 0.0,
				"operator_id": null
			},
			{
				"weapon_id": "gatling_1",
				"type": "gatling_gun",
				"position_offset": Vector2(-20, 0),
				"facing": 0.0,
				"arc": {"min": -180, "max": 180},  # Full 360° coverage for point defense
				"stats": {
					"damage": 3,
					"rate_of_fire": 12.0,  # Fast firing for anti-fighter
					"projectile_speed": 700,  # Faster projectiles
					"range": 600,  # Shorter range, close defense
					"accuracy": 0.70,  # Lower accuracy due to rapid fire
					"size": 3
				},
				"cooldown_remaining": 0.0,
				"operator_id": null
			},
			{
				"weapon_id": "gatling_2",
				"type": "gatling_gun",
				"position_offset": Vector2(20, 0),
				"facing": 0.0,
				"arc": {"min": -180, "max": 180},  # Full 360° coverage for point defense
				"stats": {
					"damage": 3,
					"rate_of_fire": 12.0,  # Fast firing for anti-fighter
					"projectile_speed": 700,  # Faster projectiles
					"range": 600,  # Shorter range, close defense
					"accuracy": 0.70,  # Lower accuracy due to rapid fire
					"size": 3
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
