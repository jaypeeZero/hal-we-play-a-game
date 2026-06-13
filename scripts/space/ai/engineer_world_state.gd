class_name EngineerWorldState
extends RefCounted

## Snapshot of an engineer's repair situation, built once per decision tick.
## Absorbs pick_repair_target's two scan loops.

# Raw inputs
var crew_data: Dictionary
var game_time: float

# Ship to repair
var ship: Dictionary           # resolved via find_ship_by_id; empty if not found

# Pre-scored repair targets (computed once)
var worst_internal: Dictionary  # {subtype, component_id, ratio} — lowest-health-ratio damaged internal; empty if none
var worst_armor: Dictionary     # {subtype, section_id, ratio} — lowest-ratio damaged armor section; empty if none

# Skill
var effective_skill: float


static func build(crew_data: Dictionary, game_time: float, ships: Array) -> EngineerWorldState:
	var ws := EngineerWorldState.new()
	ws.crew_data       = crew_data
	ws.game_time       = game_time
	ws.effective_skill = CrewAISystem.calculate_effective_skill(crew_data)
	ws.ship            = find_ship_by_id(crew_data.get("assigned_to", ""), ships)
	ws.worst_internal  = _find_worst_internal(ws.ship)
	ws.worst_armor     = _find_worst_armor(ws.ship)
	return ws


# --- Shared static helper (public for action subclasses) ---

static func find_ship_by_id(ship_id: String, ships: Array) -> Dictionary:
	for s in ships:
		if s != null and s.get("ship_id", "") == ship_id:
			return s
	return {}


# --- Private scan helpers ---

static func _find_worst_internal(ship: Dictionary) -> Dictionary:
	var best := {}
	var best_ratio := 1.0
	for component in ship.get("internals", []):
		if component.get("status", "") != "damaged":
			continue
		var max_health: int = component.get("max_health", 0)
		if max_health <= 0:
			continue
		var ratio := float(component.get("current_health", 0)) / float(max_health)
		if ratio < best_ratio or best.is_empty():
			best_ratio = ratio
			best = {
				"subtype": EngineerAction.REPAIR_SUBTYPE_PREFIX + component.get("type", "component"),
				"component_id": component.get("component_id", ""),
				"ratio": ratio,
			}
	return best


static func _find_worst_armor(ship: Dictionary) -> Dictionary:
	var best := {}
	var best_ratio := 1.0
	for section in ship.get("armor_sections", []):
		var max_armor: int = section.get("max_armor", 0)
		if max_armor <= 0 or section.get("current_armor", 0) >= max_armor:
			continue
		var ratio := float(section.get("current_armor", 0)) / float(max_armor)
		if ratio < best_ratio or best.is_empty():
			best_ratio = ratio
			best = {
				"subtype": EngineerAction.ARMOR_REPAIR_SUBTYPE,
				"section_id": section.get("section_id", ""),
				"ratio": ratio,
			}
	return best
