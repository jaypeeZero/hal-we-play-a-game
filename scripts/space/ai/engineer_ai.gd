class_name EngineerAI
extends RefCounted

## Engineer crew decisions — triage and repair the assigned ship.
##
## Each wake the engineer picks the worst-off damaged internal component
## (destroyed is beyond field repair), falling back to the most-damaged
## armor section, and emits a "repair" decision. CrewIntegrationSystem
## turns it into a machinery-skill-scaled heal on the ship.

const REPAIR_SUBTYPE_PREFIX = "fix_"
const ARMOR_REPAIR_SUBTYPE = "fix_armor"

static func make_decision(crew_data: Dictionary, game_time: float, ships: Array) -> Dictionary:
	var updated = crew_data.duplicate(true)
	var ship = find_ship_by_id(crew_data.get("assigned_to", ""), ships)

	var target := {}
	if not ship.is_empty():
		target = pick_repair_target(ship)

	if target.is_empty():
		updated.current_action = "idle"
		updated.next_decision_time = game_time + randf_range(
			WingConstants.ENGINEER_IDLE_CADENCE_MIN, WingConstants.ENGINEER_IDLE_CADENCE_MAX)
		return {"crew_data": updated}

	var decision = {
		"type": "repair",
		"subtype": target.subtype,
		"crew_id": crew_data.crew_id,
		"entity_id": crew_data.assigned_to,
		"skill_factor": CrewAISystem.calculate_effective_skill(crew_data),
		"timestamp": game_time,
	}
	if target.has("component_id"):
		decision["component_id"] = target.component_id
	else:
		decision["section_id"] = target.section_id

	updated.orders.current = decision
	updated.current_action = decision.subtype
	updated.next_decision_time = game_time + randf_range(
		WingConstants.ENGINEER_REPAIR_CADENCE_MIN, WingConstants.ENGINEER_REPAIR_CADENCE_MAX)
	return {"crew_data": updated, "decision": decision}

## Triage: the damaged internal with the lowest health ratio first
## (internals carry effects on ship performance), then the armor section
## with the lowest armor ratio. Destroyed internals are beyond field repair.
static func pick_repair_target(ship_data: Dictionary) -> Dictionary:
	var best := {}
	var best_ratio := 1.0

	for component in ship_data.get("internals", []):
		if component.get("status", "") != "damaged":
			continue
		var max_health = component.get("max_health", 0)
		if max_health <= 0:
			continue
		var ratio = float(component.get("current_health", 0)) / float(max_health)
		if ratio < best_ratio or best.is_empty():
			best_ratio = ratio
			best = {
				"subtype": REPAIR_SUBTYPE_PREFIX + component.get("type", "component"),
				"component_id": component.get("component_id", ""),
			}
	if not best.is_empty():
		return best

	best_ratio = 1.0
	for section in ship_data.get("armor_sections", []):
		var max_armor = section.get("max_armor", 0)
		if max_armor <= 0 or section.get("current_armor", 0) >= max_armor:
			continue
		var ratio = float(section.get("current_armor", 0)) / float(max_armor)
		if ratio < best_ratio or best.is_empty():
			best_ratio = ratio
			best = {
				"subtype": ARMOR_REPAIR_SUBTYPE,
				"section_id": section.get("section_id", ""),
			}
	return best

static func find_ship_by_id(ship_id: String, ships: Array) -> Dictionary:
	for ship in ships:
		if ship != null and ship.get("ship_id", "") == ship_id:
			return ship
	return {}
