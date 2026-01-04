class_name BaseStats
extends RefCounted

## Base stats for weapons and internals
## Ship templates only need to specify the TYPE to get these base stats
## Any additional data in the JSON overrides these values

# Weapon base stats by type
const WEAPONS := {
	"light_cannon": {
		"damage": 5.0,
		"range": 4000.0,
		"rate_of_fire": 5.0,
		"accuracy": 0.85,
		"projectile_speed": 600.0,
		"size": 1.0
	},
	"medium_cannon": {
		"damage": 12.0,
		"range": 6000.0,
		"rate_of_fire": 3.0,
		"accuracy": 0.8,
		"projectile_speed": 550.0,
		"size": 2.0
	},
	"heavy_cannon": {
		"damage": 50.0,
		"range": 10000.0,
		"rate_of_fire": 0.5,
		"accuracy": 0.75,
		"projectile_speed": 450.0,
		"size": 3.0
	},
	"gatling_gun": {
		"damage": 3.0,
		"range": 7200.0,
		"rate_of_fire": 10.0,
		"accuracy": 0.7,
		"projectile_speed": 700.0,
		"size": 2.0
	},
	"torpedo_launcher": {
		"damage": 15.0,
		"range": 10000.0,
		"rate_of_fire": 0.3,
		"accuracy": 0.95,
		"projectile_speed": 200.0,
		"size": 3.0,
		"explosion_radius": 80.0,
		"explosion_damage": 60.0
	}
}

# Engine base stats by type
const ENGINES := {
	"engine": {
		"max_health": 50.0,
		"effect_on_ship": {
			"on_damaged": {
				"acceleration": 0.5,
				"max_speed": 0.7
			},
			"on_destroyed": {
				"acceleration": 0.2,
				"max_speed": 0.3
			}
		}
	}
}

# Default weapon placement values (not stats, just defaults)
const WEAPON_DEFAULTS := {
	"cooldown_remaining": 0.0,
	"facing": 0.0,
	"operator_id": null,
	"arc": {
		"min": -30.0,
		"max": 30.0
	}
}

# Default internal placement values
const INTERNAL_DEFAULTS := {
	"status": "operational"
}


## Get base stats for a weapon type, returns empty dict if unknown type
static func get_weapon_stats(weapon_type: String) -> Dictionary:
	if WEAPONS.has(weapon_type):
		return WEAPONS[weapon_type].duplicate(true)
	push_warning("Unknown weapon type: " + weapon_type)
	return {}


## Get base stats for an engine type, returns empty dict if unknown type
static func get_engine_stats(engine_type: String) -> Dictionary:
	if ENGINES.has(engine_type):
		return ENGINES[engine_type].duplicate(true)
	push_warning("Unknown engine type: " + engine_type)
	return {}


## Apply base stats to a weapon, with JSON data as overrides
## Returns the weapon with full stats (base + overrides)
static func apply_weapon_base_stats(weapon_data: Dictionary) -> Dictionary:
	var weapon_type: String = weapon_data.get("type", "")
	var base_stats := get_weapon_stats(weapon_type)

	if base_stats.is_empty():
		return weapon_data

	var result := weapon_data.duplicate(true)

	# Apply default placement values if not specified
	for key in WEAPON_DEFAULTS.keys():
		if not result.has(key):
			result[key] = WEAPON_DEFAULTS[key] if not WEAPON_DEFAULTS[key] is Dictionary else WEAPON_DEFAULTS[key].duplicate(true)

	# Start with base stats, then override with any stats from JSON
	if not result.has("stats"):
		result.stats = {}

	var json_stats: Dictionary = result.stats
	result.stats = base_stats.duplicate(true)

	# Apply JSON overrides on top of base stats
	for key in json_stats.keys():
		result.stats[key] = json_stats[key]

	return result


## Apply base stats to an internal component (engine), with JSON data as overrides
static func apply_internal_base_stats(internal_data: Dictionary) -> Dictionary:
	var internal_type: String = internal_data.get("type", "")
	var base_stats := get_engine_stats(internal_type)

	if base_stats.is_empty():
		return internal_data

	var result := internal_data.duplicate(true)

	# Apply default values if not specified
	for key in INTERNAL_DEFAULTS.keys():
		if not result.has(key):
			result[key] = INTERNAL_DEFAULTS[key]

	# Apply base stats with JSON overrides
	for key in base_stats.keys():
		if key == "effect_on_ship":
			# Deep merge for effect_on_ship
			if not result.has("effect_on_ship"):
				result.effect_on_ship = base_stats.effect_on_ship.duplicate(true)
			else:
				var base_effects: Dictionary = base_stats.effect_on_ship.duplicate(true)
				var json_effects: Dictionary = result.effect_on_ship
				for effect_key in json_effects.keys():
					if base_effects.has(effect_key) and json_effects[effect_key] is Dictionary:
						for stat_key in json_effects[effect_key].keys():
							base_effects[effect_key][stat_key] = json_effects[effect_key][stat_key]
					else:
						base_effects[effect_key] = json_effects[effect_key]
				result.effect_on_ship = base_effects
		else:
			# For other keys (like max_health), only apply base if not in JSON
			if not result.has(key):
				result[key] = base_stats[key]

	# Set current_health from max_health if not specified
	if not result.has("current_health") and result.has("max_health"):
		result.current_health = result.max_health

	return result
