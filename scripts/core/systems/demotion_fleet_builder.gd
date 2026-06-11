class_name DemotionFleetBuilder
extends RefCounted

## Builds the "surviving remnant" of a wiped fleet for a demotion: a random
## share of the lost fleet limps into the lower sector in a damaged state,
## crews intact, alongside the fresh fleet from the saved config.

## Share of the lost fleet that survives the rout (at least one ship).
const MIN_SURVIVOR_FRACTION := 0.2
const MAX_SURVIVOR_FRACTION := 0.5
## Condition the survivors limp home in, as a fraction of each armor
## section's / internal component's maximum.
const MIN_CONDITION_FRACTION := 0.15
const MAX_CONDITION_FRACTION := 0.5


## Pick survivors from the lost fleet's final battle state. Ships keep
## their battle damage history but come back operational at a rolled
## fraction of max condition; each survivor's crew group (matched by ship
## type) carries over intact - crew_id, callsign, skills, known_patterns.
static func pick_survivors(lost_ships: Array, lost_crew_groups: Array,
		rng: RandomNumberGenerator) -> Dictionary:
	if lost_ships.is_empty():
		return {"ships": [], "crew_groups": []}

	var share := rng.randf_range(MIN_SURVIVOR_FRACTION, MAX_SURVIVOR_FRACTION)
	var survivor_count := clampi(roundi(lost_ships.size() * share), 1, lost_ships.size())
	var picks := _shuffled_indices(lost_ships.size(), rng).slice(0, survivor_count)

	var ships: Array = []
	var crew_groups: Array = []
	var remaining_groups: Array = lost_crew_groups.duplicate(true)
	for index in picks:
		var ship := _restore_to_damaged_state(lost_ships[index], rng)
		ships.append(ship)
		var group := _take_group_for_type(remaining_groups, ship.get("type", ""))
		if not group.is_empty():
			crew_groups.append(group)
	return {"ships": ships, "crew_groups": crew_groups}


static func _shuffled_indices(count: int, rng: RandomNumberGenerator) -> Array:
	var indices: Array = range(count)
	for i in range(count - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swapped = indices[i]
		indices[i] = indices[j]
		indices[j] = swapped
	return indices


## Bring a destroyed ship back as operational-but-battered: every armor
## section and internal component re-rolls to a fraction of its maximum,
## and effective stats are re-derived from the new component statuses.
static func _restore_to_damaged_state(lost_ship: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var ship: Dictionary = lost_ship.duplicate(true)
	ship["status"] = "operational"
	for section in ship.get("armor_sections", []):
		section["current_armor"] = _roll_condition(int(section.get("max_armor", 0)), rng)
	for component in ship.get("internals", []):
		component["current_health"] = _roll_condition(int(component.get("max_health", 0)), rng)
		component["status"] = "damaged"
	return DamageResolver.recompute_stats_from_components(ship)


## A condition roll strictly between zero and the maximum, so survivors are
## neither wrecks nor factory-fresh.
static func _roll_condition(max_value: int, rng: RandomNumberGenerator) -> int:
	var rolled := roundi(max_value * rng.randf_range(MIN_CONDITION_FRACTION, MAX_CONDITION_FRACTION))
	return clampi(rolled, 1, maxi(1, max_value - 1))


static func _take_group_for_type(groups: Array, ship_type: String) -> Dictionary:
	for i in groups.size():
		if groups[i].get("ship_type", "") == ship_type:
			return groups.pop_at(i)
	return {}
