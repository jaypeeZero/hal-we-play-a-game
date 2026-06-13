class_name TestFactories
extends GutTest

## Shared static factories for the ship/crew/weapon/projectile dictionaries
## used across the test suite (see DOCS/plans/03_test_consolidation.md).
## Defines no tests; it extends GutTest only so GUT's collector accepts the
## file living in tests/ without logging a warning.
##
## Values here are test fixtures, not game data: tests must assert behavior
## relative to these inputs, never the literal numbers below.

const DEFAULT_SKILL := 0.8
const DEFAULT_AGGRESSION := 0.5
const DEFAULT_CREW_SKILL := 0.7
const DEFAULT_REACTION_TIME := 0.1
const DEFAULT_DECISION_TIME := 0.3
# Armor and component health are ints because DamageResolver's armor API is
# int-typed; float fixtures would trip GUT's Float/Int comparison warnings.
const DEFAULT_ARMOR := 25
const DEFAULT_COMPONENT_HEALTH := 20
const CAPITAL_SECTION_ARMOR := 100
const TORPEDO_BOAT_ARMOR := 30
const DEFAULT_PROJECTILE_DAMAGE := 10.0
const DEFAULT_PROJECTILE_LIFETIME := 5.0
const DEFAULT_PROJECTILE_VELOCITY := Vector2(100, 0)

## Standard engine damage effects (mirrors the shape of real templates).
const ENGINE_DAMAGE_EFFECTS := {
	"on_damaged": {"max_speed": 0.7},
	"on_destroyed": {"max_speed": 0.2},
}

## Movement stats per ship class. Relative ordering (fighter fastest and most
## agile, capital slowest) mirrors the real templates.
const SHIP_CLASS_STATS := {
	"fighter": {"max_speed": 300.0, "acceleration": 100.0, "turn_rate": 3.0, "mass": 50.0, "size": 15.0},
	"torpedo_boat": {"max_speed": 250.0, "acceleration": 100.0, "turn_rate": 2.5, "mass": 60.0, "size": 18.0},
	"corvette": {"max_speed": 200.0, "acceleration": 100.0, "turn_rate": 1.5, "mass": 300.0, "size": 30.0},
	"capital": {"max_speed": 100.0, "acceleration": 60.0, "turn_rate": 1.0, "mass": 1000.0, "size": 60.0},
}

const WEAPON_CLASS_STATS := {
	"light_cannon": {"damage": 10, "rate_of_fire": 2.0, "projectile_speed": 600, "range": 1000, "accuracy": 0.85},
	"gatling_gun": {"damage": 3, "rate_of_fire": 8.0, "projectile_speed": 700, "range": 600, "accuracy": 0.8},
	"torpedo_launcher": {"damage": 15, "rate_of_fire": 0.3, "projectile_speed": 200, "range": 1200, "accuracy": 0.95, "size": 3, "explosion_radius": 80.0, "explosion_damage": 60.0},
}

const WEAPON_CLASS_ARCS := {
	"light_cannon": {"min": -45, "max": 45},
	"gatling_gun": {"min": -25, "max": 25},
	"torpedo_launcher": {"min": -10, "max": 10},
}

# ============================================================================
# SHIPS
# ============================================================================

## Generic ship dictionary. Pass `id == ""` for an auto-generated unique id.
## `overrides` replaces top-level keys (velocity, armor_sections, ...).
static func make_ship(id: String, type: String = "fighter", team: int = 0, pos: Vector2 = Vector2.ZERO, overrides: Dictionary = {}) -> Dictionary:
	var stats: Dictionary = SHIP_CLASS_STATS.get(type, SHIP_CLASS_STATS["fighter"]).duplicate(true)
	var ship := {
		"ship_id": id if id != "" else "%s_%d" % [type, randi()],
		"type": type,
		"team": team,
		"position": pos,
		"velocity": Vector2.ZERO,
		"rotation": 0.0,
		"status": "operational",
		"collision_radius": stats.size,
		"stats": stats,
		"armor_sections": [],
		"internals": [make_component("cockpit", "cockpit")],
		"weapons": [],
		"orders": {"current_order": "", "target_id": "", "maneuver_subtype": ""},
		# Generous battle repair pool so existing tests are unaffected.
		# Tests that exercise pool-exhaustion set this explicitly to 0.
		"repair_pool": 9999,
		"repair_pool_max": 9999,
	}
	for key in overrides:
		ship[key] = overrides[key]
	if not ship.has("base_stats"):
		ship["base_stats"] = ship["stats"].duplicate(true)
	return ship

static func make_fighter(id: String = "", pos: Vector2 = Vector2.ZERO, team: int = 0, overrides: Dictionary = {}) -> Dictionary:
	return make_ship(id, "fighter", team, pos, overrides)

static func make_corvette(id: String = "", pos: Vector2 = Vector2.ZERO, team: int = 0, overrides: Dictionary = {}) -> Dictionary:
	return make_ship(id, "corvette", team, pos, overrides)

## Capitals carry full armor sections and an engine internal so that
## self-preservation logic (critical armor, engine damage) has real inputs.
static func make_capital(id: String = "", pos: Vector2 = Vector2.ZERO, team: int = 0, rotation: float = 0.0, overrides: Dictionary = {}) -> Dictionary:
	var merged := overrides.duplicate()
	if not merged.has("rotation"):
		merged["rotation"] = rotation
	if not merged.has("armor_sections"):
		merged["armor_sections"] = [
			make_armor_section("front", CAPITAL_SECTION_ARMOR),
			make_armor_section("port", CAPITAL_SECTION_ARMOR),
			make_armor_section("starboard", CAPITAL_SECTION_ARMOR),
			make_armor_section("rear", CAPITAL_SECTION_ARMOR),
		]
	if not merged.has("internals"):
		merged["internals"] = [make_component("eng_main", "engine", Vector2.ZERO, DEFAULT_COMPONENT_HEALTH, ENGINE_DAMAGE_EFFECTS)]
	return make_ship(id, "capital", team, pos, merged)

## Ship with a single front armor section (the common damage-test target).
static func make_armored_ship(type: String, pos: Vector2 = Vector2.ZERO, team: int = 0, armor: int = DEFAULT_ARMOR, id: String = "") -> Dictionary:
	return make_ship(id, type, team, pos, {"armor_sections": [make_armor_section("front", armor)]})

## Ship carrying one ready-to-fire weapon of the given type.
static func make_armed_ship(weapon_type: String = "light_cannon", cooldown: float = 0.0, id: String = "test_ship", ship_type: String = "fighter") -> Dictionary:
	return make_ship(id, ship_type, 0, Vector2.ZERO, {"weapons": [make_weapon(weapon_type, "weapon_1", cooldown)]})

## Torpedo boat with front armor, a gatling gun, and a torpedo launcher.
static func make_torpedo_boat(pos: Vector2 = Vector2.ZERO, team: int = 0, id: String = "") -> Dictionary:
	var ship := make_ship(id, "torpedo_boat", team, pos, {
		"armor_sections": [make_armor_section("front", TORPEDO_BOAT_ARMOR)],
		"weapons": [
			make_weapon("gatling_gun", "gatling"),
			make_weapon("torpedo_launcher", "torpedo_tube"),
		],
	})
	ship.rotation = 0.0 if team == 0 else PI
	return ship

# ============================================================================
# SHIP PARTS
# ============================================================================

static func make_armor_section(section_id: String = "front", armor: int = DEFAULT_ARMOR, arc_start: float = -90.0, arc_end: float = 90.0) -> Dictionary:
	return {
		"section_id": section_id,
		"current_armor": armor,
		"max_armor": armor,
		"size": 1.0,
		"arc": {"start": arc_start, "end": arc_end},
	}

static func make_component(component_id: String, type: String = "", offset: Vector2 = Vector2.ZERO, health: int = DEFAULT_COMPONENT_HEALTH, effects: Dictionary = {}) -> Dictionary:
	return {
		"component_id": component_id,
		"type": type if type != "" else component_id,
		"position_offset": offset,
		"max_health": health,
		"current_health": health,
		"status": "operational",
		"effect_on_ship": effects,
	}

static func make_weapon(type: String = "light_cannon", weapon_id: String = "weapon_1", cooldown: float = 0.0) -> Dictionary:
	var stats: Dictionary = WEAPON_CLASS_STATS.get(type, WEAPON_CLASS_STATS["light_cannon"]).duplicate(true)
	return {
		"weapon_id": weapon_id,
		"type": type,
		"position_offset": Vector2.ZERO,
		"facing": 0.0,
		"arc": WEAPON_CLASS_ARCS.get(type, WEAPON_CLASS_ARCS["light_cannon"]).duplicate(true),
		"stats": stats,
		"base_stats": stats.duplicate(true),
		"cooldown_remaining": cooldown,
	}

# ============================================================================
# CREW
# ============================================================================

## Raw pilot dictionary for AI-level tests (FighterPilotAI / LargeShipPilotAI).
## `skill` seeds every skill; `aggression` is separate because doctrine tests
## vary it independently. `superior` null means a solo (fighter) pilot.
static func make_pilot(id: String, ship_id: String, skill: float = DEFAULT_SKILL, aggression: float = DEFAULT_AGGRESSION, superior = null) -> Dictionary:
	return {
		"crew_id": id,
		"role": CrewData.Role.PILOT,
		"assigned_to": ship_id,
		"stats": {
			"reaction_time": DEFAULT_REACTION_TIME,
			"decision_time": DEFAULT_DECISION_TIME,
			"stress": 0.0,
			"fatigue": 0.0,
			"skills": {
				"aim": skill, "piloting": skill, "awareness": skill,
				"tactics": skill, "composure": skill, "aggression": aggression,
				"machinery": skill,
			},
		},
		"awareness": {"threats": [], "opportunities": [], "known_entities": []},
		"orders": {"received": null, "current": null},
		"command_chain": {"superior": superior, "subordinates": []},
		"combat_state": {},
		"current_action": "idle",
		"next_decision_time": 0.0,
	}

## Crew built through the production CrewData factory (full stat schema).
static func make_crew_member(role: int, skill: float = DEFAULT_CREW_SKILL, ship_id: String = "ship_1", superior = null, subordinates: Array = []) -> Dictionary:
	var crew = CrewData.create_crew_member(role, skill)
	crew.assigned_to = ship_id
	if superior != null:
		crew.command_chain.superior = superior
	if not subordinates.is_empty():
		crew.command_chain.subordinates = subordinates
	return crew

## Multi-crew pilot (has a superior) so decisions use evade/pursue subtypes.
static func make_crew_pilot(skill: float = DEFAULT_CREW_SKILL, ship_id: String = "ship_1") -> Dictionary:
	return make_crew_member(CrewData.Role.PILOT, skill, ship_id, "captain_x")

static func make_crew_gunner(skill: float = DEFAULT_CREW_SKILL, ship_id: String = "ship_1") -> Dictionary:
	return make_crew_member(CrewData.Role.GUNNER, skill, ship_id, "captain_x")

static func make_crew_captain(skill: float = DEFAULT_CREW_SKILL, ship_id: String = "ship_1") -> Dictionary:
	return make_crew_member(CrewData.Role.CAPTAIN, skill, ship_id, null, ["pilot_x", "gunner_x"])

## Engineer with a specific machinery skill (other skills track `skill`).
static func make_crew_engineer(machinery: float = DEFAULT_CREW_SKILL, ship_id: String = "ship_1", skill: float = DEFAULT_CREW_SKILL) -> Dictionary:
	var crew = make_crew_member(CrewData.Role.ENGINEER, skill, ship_id, "captain_x")
	crew.stats.skills.machinery = machinery
	return crew

# ============================================================================
# AWARENESS ENTRIES AND PROJECTILES
# ============================================================================

static func make_threat(id: String, priority: float) -> Dictionary:
	return {"id": id, "type": "ship", "_threat_priority": priority}

static func make_opportunity(id: String, score: float) -> Dictionary:
	return {"id": id, "type": "ship", "_opportunity_score": score}

static func make_projectile(pos: Vector2 = Vector2.ZERO, team: int = 0, damage: float = DEFAULT_PROJECTILE_DAMAGE) -> Dictionary:
	return {
		"projectile_id": "proj_%d" % randi(),
		"position": pos,
		"velocity": DEFAULT_PROJECTILE_VELOCITY,
		"team": team,
		"damage": damage,
		"source_id": "ship_test",
		"lifetime": DEFAULT_PROJECTILE_LIFETIME,
	}
