class_name FlankAction
extends FighterAction

## Approach the target from the least-crowded angular sector.
## Requires display skill ≥ 8 (internal 0.4) AND at least one ally already
## engaging the target. This creates natural multi-ship coordination: pilots
## spread across the target without explicit coordination messages.

const MIN_SKILL  = 0.4    # display 8
const BASE_COST  = 0.8
const NUM_SECTORS = 8


func action_id() -> String: return "flank"

func cost(ws: FighterWorldState) -> float:
	# Cheaper when more allies are already engaging (clearer flanking opportunity)
	var ally_bonus: float = clamp(ws.allies_engaging_target * 0.08, 0.0, 0.20)
	# Cheaper with higher skill (better execution)
	var skill_bonus: float = clamp((ws.skill - MIN_SKILL) * 0.1, 0.0, 0.06)
	return BASE_COST - ally_bonus - skill_bonus


func precondition(ws: FighterWorldState) -> bool:
	return (
		ws.skill >= MIN_SKILL
		and not ws.target_ship.is_empty()
		and ws.allies_engaging_target >= 1
	)


func execute(ws: FighterWorldState) -> Dictionary:
	var flank_angle := _pick_flank_angle(ws)
	var t_pos: Vector2     = ws.target_ship.get("position", Vector2.ZERO)
	var approach_dist: float = 600.0
	var flank_dest := t_pos + Vector2(cos(flank_angle), sin(flank_angle)) * approach_dist

	# Sync phase with lead when in a wing
	var phase := "approach"
	if ws.wing_role == "wingman" and ws.lead_phase != "":
		phase = ws.lead_phase

	var maneuver := FighterAction.phase_to_maneuver(phase)
	if maneuver == "": maneuver = "fight_pursue_tactical"

	return {
		"type": "maneuver",
		"subtype": maneuver,
		"crew_id": ws.crew_data.get("crew_id", ""),
		"entity_id": ws.my_ship.get("ship_id", ""),
		"target_id": ws.target_id,
		"skill_factor": ws.skill,
		"delay": ws.crew_data.get("stats", {}).get("reaction_time", 0.1),
		"timestamp": ws.game_time,
		"formation_position": flank_dest,
		"approach_angle": flank_angle,
		"approach_style": FighterAction.approach_style_for(ws.skill, ws.position_advantage, ws.aggression),
	}


## Divide 360° into NUM_SECTORS, count ally approach vectors per sector,
## return the centre angle of the least-occupied sector.
func _pick_flank_angle(ws: FighterWorldState) -> float:
	var sector_counts := []
	sector_counts.resize(NUM_SECTORS)
	sector_counts.fill(0)
	var sector_size: float = TAU / float(NUM_SECTORS)

	for ally_dir in ws.ally_approach_angles:
		var a: float = fmod(ally_dir.angle() + TAU, TAU)
		var idx: int = int(a / sector_size) % NUM_SECTORS
		sector_counts[idx] += 1

	var best_idx: int = 0
	var best_count: int = sector_counts[0]
	for i in range(1, NUM_SECTORS):
		if sector_counts[i] < best_count:
			best_count = sector_counts[i]
			best_idx = i

	# Centre of the chosen sector, with small skill-scaled randomness
	var base_angle: float = (float(best_idx) + 0.5) * sector_size
	var jitter: float = sector_size * 0.3 * (1.0 - ws.skill)
	return base_angle + randf_range(-jitter, jitter)
