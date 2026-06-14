class_name AttackAction
extends FighterAction

## Standard attack action — the dominant non-reflex engage action.
## Converted in Phase 1b to emit a blended directive (subtype:"tactical") instead
## of a discrete fight_* maneuver, so combat becomes continuous brawl-vs-kite
## driven by each ship's resolved tactics block.
##
## Reflexes still emit fight_* subtypes (they run before FighterBrain.decide).
## This action is only reachable AFTER all reflexes have declined to fire.
##
## Always available when a valid target exists (highest base cost = last choice).

const BASE_COST = 1.0

## Fallback tactics used when crew["tactics"] is absent (un-configured ships).
## Produces coherent mid-range behavior — same as the TacticsSystem engine default.
const FALLBACK_TACTICS := {
	"mentality_scalar": 0.5,
	"range_scalar":     0.5,
}


func action_id() -> String: return "attack"

func cost(ws: FighterWorldState) -> float:
	# Aggressive pilots slightly prefer attacking over any other option
	return BASE_COST - ws.aggression * 0.15

func precondition(ws: FighterWorldState) -> bool:
	return not ws.target_ship.is_empty()


func execute(ws: FighterWorldState) -> Dictionary:
	# Read the crew's resolved tactics block (stamped at spawn by TacticsSystem.compile_for_crew).
	# Fall back to mid-range balanced defaults so an un-configured crew is still coherent.
	var tactics: Dictionary = ws.crew_data.get("tactics", FALLBACK_TACTICS)

	# Weapon optimal range: real max range over this ship's operational weapons.
	# Using actual weapon stats (not hull-class heuristics) ensures preferred_range
	# stays inside the firing envelope — the blender multipliers (0.35–0.9×) then
	# place the ship at brawl-to-far-edge, all within weapon reach.
	var weapon_optimal: float = WeaponSystem.get_effective_range(ws.my_ship)

	# Build threat list in the format SteeringBlender expects:
	# each entry may carry .target_id (for "am I being targeted?") and .position.
	var threats: Array = _build_threats(ws)

	# Pass support_pos from ship.orders so the blender adds an escort-pull goal
	# when a support_ally order is active.  Null when no escort assignment.
	var support_pos: Variant = ws.my_ship.get("orders", {}).get("support_pos", null)

	# A live press-attack posture (#79 commit / all-out, surfaced as ws.press_attack)
	# maps to the aggressive "press" steering posture. Otherwise use any
	# commander-set posture (withdraw/hold) on the crew.
	var posture: String = "press" if ws.press_attack else ws.crew_data.get("posture", "")

	var directive: Dictionary = SteeringBlender.build_directive(
		ws.my_ship, tactics, ws.target_ship, threats, weapon_optimal,
		posture,
		support_pos
	)

	return {
		"type":       "maneuver",
		"subtype":    "tactical",
		# Directive fields (copied wholesale; CrewIntegrationSystem fans them onto orders)
		"engagement_target": directive.get("engagement_target", ""),
		"goal_weights":      directive.get("goal_weights", {}),
		"preferred_range":   directive.get("preferred_range", weapon_optimal),
		"formation_slot":    directive.get("formation_slot",  Vector2.ZERO),
		"anchor_position":   directive.get("anchor_position", Vector2.ZERO),
		"support_pos":       directive.get("support_pos",     null),
		# Standard decision metadata
		"crew_id":    ws.crew_data.get("crew_id", ""),
		"entity_id":  ws.my_ship.get("ship_id", ""),
		"target_id":  ws.target_id,
		"skill_factor": ws.skill,
		"delay":      ws.crew_data.get("stats", {}).get("reaction_time", 0.1),
		"timestamp":  ws.game_time,
	}


## Build a minimal threat array from ws.all_ships for SteeringBlender.
## Each entry carries .position and .target_id so the blender can detect
## when this ship is being targeted (raises evade weight).
func _build_threats(ws: FighterWorldState) -> Array:
	var my_team: int    = ws.my_ship.get("team", -1)
	var threats: Array  = []
	for s in ws.all_ships:
		if s.get("team", -1) == my_team: continue
		if s.get("status", "") != "operational": continue
		# Include target_id so blender can detect if we're being aimed at
		threats.append({
			"position":  s.get("position", Vector2.ZERO),
			"target_id": s.get("orders", {}).get("target_id", ""),
		})
	return threats
