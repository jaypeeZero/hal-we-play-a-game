class_name RepairSystem
extends RefCounted

## Pure functional repair — the inverse of DamageResolver. Every function
## returns new data. Effective stats are re-derived through
## DamageResolver.recompute_stats_from_components, so damage and repair
## share a single component-effect path.

## Skill-scaled fractions of small maximums still repair something.
const MINIMUM_REPAIR_AMOUNT = 1

static func fraction_to_amount(max_value: int, fraction: float) -> int:
	return maxi(MINIMUM_REPAIR_AMOUNT, int(max_value * fraction))

## Restore armor on one section, clamped to its maximum.
static func repair_armor_section(ship_data: Dictionary, section_id: String, amount: int) -> Dictionary:
	if amount <= 0:
		return ship_data
	var section = find_armor_section_by_id(ship_data, section_id)
	if section.is_empty():
		return ship_data
	var healed = mini(section.get("max_armor", 0), section.get("current_armor", 0) + amount)
	if healed == section.get("current_armor", 0):
		return ship_data
	var repaired = DamageResolver.set_section_armor(section, healed)
	return DamageResolver.replace_armor_section(ship_data, repaired)

## Restore health on one internal component, clamped to its maximum.
## Destroyed components are only repairable when `include_destroyed` is true
## (roguelike downtime); in battle they stay destroyed.
static func repair_component(ship_data: Dictionary, component_id: String, amount: int, include_destroyed: bool = false) -> Dictionary:
	if amount <= 0:
		return ship_data
	var component = DamageResolver.find_internal_by_id(ship_data, component_id)
	if component.is_empty():
		return ship_data
	if component.get("status", "") == "destroyed" and not include_destroyed:
		return ship_data

	var max_health = component.get("max_health", 0)
	var new_health = mini(max_health, component.get("current_health", 0) + amount)
	if new_health == component.get("current_health", 0):
		return ship_data

	var new_status = "operational" if new_health == max_health else "damaged"
	var repaired = DamageResolver.set_component_health_and_status(component, new_health, new_status)
	var updated = DamageResolver.replace_internal_component(ship_data, repaired)
	if new_status != component.get("status", ""):
		updated = DamageResolver.recompute_stats_from_components(updated)
	return updated

## Heal every armor section and internal component by a fraction of its
## maximum. Used by roguelike jump/R&R repairs.
static func repair_ship_fraction(ship_data: Dictionary, fraction: float, include_destroyed: bool = false) -> Dictionary:
	if fraction <= 0.0:
		return ship_data
	var updated = ship_data
	for section in ship_data.get("armor_sections", []):
		var amount = fraction_to_amount(section.get("max_armor", 0), fraction)
		updated = repair_armor_section(updated, section.get("section_id", ""), amount)
	for component in ship_data.get("internals", []):
		var amount = fraction_to_amount(component.get("max_health", 0), fraction)
		updated = repair_component(updated, component.get("component_id", ""), amount, include_destroyed)
	if include_destroyed:
		updated = restore_disabled_status(updated)
	return updated

## Roguelike between-jump repair: each Engineer aboard contributes
## base_fraction × their machinery skill. Crew in other roles never
## contribute, whatever their machinery skill.
static func apply_engineer_repairs(ship_data: Dictionary, base_fraction: float) -> Dictionary:
	var total_fraction := 0.0
	for crew_member in ship_data.get("crew", []):
		if crew_member.get("role", -1) != CrewData.Role.ENGINEER:
			continue
		total_fraction += base_fraction * float(crew_member.stats.skills.machinery)
	if total_fraction <= 0.0:
		return ship_data
	return repair_ship_fraction(ship_data, total_fraction, true)

## A ship disabled by a destroyed component becomes operational again once
## no destroyed component with a disabling effect remains.
static func restore_disabled_status(ship_data: Dictionary) -> Dictionary:
	if ship_data.get("status", "") != "disabled":
		return ship_data
	for component in ship_data.get("internals", []):
		if component.get("status", "") != "destroyed":
			continue
		if component.get("effect_on_ship", {}).get("on_destroyed", {}).get("disabled", false):
			return ship_data
	return DictUtils.merge_dict(ship_data, {"status": "operational"})

static func find_armor_section_by_id(ship_data: Dictionary, section_id: String) -> Dictionary:
	for section in ship_data.get("armor_sections", []):
		if section.get("section_id", "") == section_id:
			return section
	return {}
