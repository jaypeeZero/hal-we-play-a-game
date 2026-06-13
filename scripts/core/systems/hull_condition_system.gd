class_name HullConditionSystem
extends RefCounted

## Shared home for armor/systems condition math, reused across shop and
## campaign screens. Avoids duplicating the same aggregation logic.


## Returns {"armor": float, "systems": float} as 0..1 ratios from the
## hull's persisted `ship` damage state. A pristine hull (ship is empty)
## or any zero-max total returns 1.0 for that metric.
static func condition(hull: Dictionary) -> Dictionary:
	var ship: Dictionary = hull.get("ship", {})
	if ship.is_empty():
		return {"armor": 1.0, "systems": 1.0}

	var armor_current := 0.0
	var armor_max := 0.0
	for section in ship.get("armor_sections", []):
		armor_current += float(section.get("current_armor", 0))
		armor_max += float(section.get("max_armor", 0))

	var systems_current := 0.0
	var systems_max := 0.0
	for component in ship.get("internals", []):
		systems_current += float(component.get("current_health", 0))
		systems_max += float(component.get("max_health", 0))

	return {
		"armor": armor_current / armor_max if armor_max > 0.0 else 1.0,
		"systems": systems_current / systems_max if systems_max > 0.0 else 1.0,
	}
