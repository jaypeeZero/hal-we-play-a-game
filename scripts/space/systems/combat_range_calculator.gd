## CombatRangeCalculator - Pure functional range calculation system
##
## All combat ranges derive from weapon data - single source of truth.
## Ranges are expressed as ratios of max weapon range, not hardcoded distances.
## Skills act as modifiers on base values, preserving skill-based variation.
##
## Critical Invariant: Detection Range >= Engagement Range >= Weapon Range * safety_factor

class_name CombatRangeCalculator
extends RefCounted

# Ratio multipliers - all ranges are derived from max weapon range
const ENGAGEMENT_FACTOR = 0.85       # Engage at 85% of max weapon range (stay in effective range)
const DETECTION_FACTOR = 1.5         # Detect at 150% of max weapon range (see before engage)
const FAR_APPROACH_FACTOR = 3.0      # Fighter far approach at 3x weapon range
const MID_APPROACH_FACTOR = 1.5      # Fighter tactical maneuvering at 1.5x
const CLOSE_COMBAT_FACTOR = 1.0      # Close combat at weapon range
const MIN_COMBAT_FACTOR = 0.4        # Don't get closer than 40% of range
const BROADSIDE_FACTOR = 0.8         # Corvette broadside at 80% of weapon range
const VS_CAPITAL_FACTOR = 3.0        # Safe distance vs capitals at 3x own weapon range

# Default fallback for ships without weapons (tests, edge cases)
const DEFAULT_WEAPON_RANGE = 800.0


## Get maximum weapon range from ship data
## Returns the highest range among all weapons the ship carries
static func get_max_weapon_range(ship_data: Dictionary) -> float:
	var weapons = ship_data.get("weapons", [])
	if weapons.is_empty():
		return DEFAULT_WEAPON_RANGE

	var max_range = 0.0
	for weapon in weapons:
		var weapon_range = weapon.get("stats", {}).get("range", 0.0)
		max_range = max(max_range, weapon_range)
	return max_range


## Base engagement range before skill modifiers
## This is the raw distance where AI decides to fight
static func get_base_engagement_range(ship_data: Dictionary) -> float:
	return get_max_weapon_range(ship_data) * ENGAGEMENT_FACTOR


## Base detection range before skill modifiers
## Ships can see this far
static func get_base_detection_range(ship_data: Dictionary) -> float:
	return get_max_weapon_range(ship_data) * DETECTION_FACTOR


## Effective engagement range with aggression modifier
## Aggression skill scales engagement distance:
## - 0.0 aggression -> 140% (cautious, stays far)
## - 0.5 aggression -> 100% (normal)
## - 1.0 aggression -> 60% (aggressive, closes fast)
static func get_engagement_range(ship_data: Dictionary, aggression: float = 0.5) -> float:
	var base = get_base_engagement_range(ship_data)
	return base * (1.4 - aggression * 0.8)


## Effective detection range with awareness modifier
## CRITICAL: Guaranteed to exceed engagement range (maintains invariant)
## Awareness skill scales detection:
## - 0.0 awareness -> 70%
## - 0.5 awareness -> 100%
## - 1.0 awareness -> 130%
## But with floor: must be 20% higher than max possible engagement (when aggression=1.0)
static func get_detection_range(ship_data: Dictionary, awareness: float = 0.5) -> float:
	var base = get_base_detection_range(ship_data)
	var effective = base * (0.7 + awareness * 0.6)

	# INVARIANT: Detection must exceed max possible engagement range
	# Use aggression=1.0 (closest engagement) to calculate floor
	var min_detection = get_engagement_range(ship_data, 1.0) * 1.2
	return max(effective, min_detection)


# =============================================================================
# FIGHTER-SPECIFIC RANGES
# =============================================================================

## Far range - distance beyond which fighter approaches at full speed
static func get_fighter_far_range(ship_data: Dictionary) -> float:
	return get_max_weapon_range(ship_data) * FAR_APPROACH_FACTOR


## Mid range - distance threshold for tactical maneuvering
static func get_fighter_mid_range(ship_data: Dictionary) -> float:
	return get_max_weapon_range(ship_data) * MID_APPROACH_FACTOR


## Close range - ideal weapons range / dogfighting distance
static func get_fighter_close_range(ship_data: Dictionary) -> float:
	return get_max_weapon_range(ship_data) * CLOSE_COMBAT_FACTOR


## Minimum combat range - don't get closer than this
static func get_fighter_min_combat_range(ship_data: Dictionary) -> float:
	return get_max_weapon_range(ship_data) * MIN_COMBAT_FACTOR


## Safe distance when engaging capital ships
## Fighters maintain this distance to avoid concentrated fire
static func get_safe_distance_vs_capital(ship_data: Dictionary) -> float:
	return get_max_weapon_range(ship_data) * VS_CAPITAL_FACTOR


# =============================================================================
# CORVETTE-SPECIFIC RANGES
# =============================================================================

## Optimal broadside distance for corvette broadsides
static func get_broadside_optimal_distance(ship_data: Dictionary) -> float:
	return get_max_weapon_range(ship_data) * BROADSIDE_FACTOR


## Evasion range - when to start evading threats
static func get_evasion_range(ship_data: Dictionary) -> float:
	return get_max_weapon_range(ship_data) * DETECTION_FACTOR
