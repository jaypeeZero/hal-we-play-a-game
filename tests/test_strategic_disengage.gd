extends GutTest

## Behavior tests: elite tacticians proactively disengage when damaged,
## outnumbered, and unsupported. Rookies do not have this capability.

func _make_crew(tactics: float, aggression: float = 0.5) -> Dictionary:
	return {
		"crew_id": "pilot_test",
		"role": CrewData.Role.PILOT,
		"assigned_to": "ship_me",
		"is_squadron_leader": false,
		"stats": {
			"reaction_time": 0.1,
			"stress": 0.0,
			"fatigue": 0.0,
			"skills": {
				"piloting": 0.8,
				"aim": 0.8,
				"awareness": 0.8,
				"tactics": tactics,
				"composure": 0.8,
				"aggression": aggression
			}
		},
		"awareness": {
			"threats": [],
			"opportunities": [],
			"known_entities": []
		},
		"combat_state": {}
	}

func _make_fighter(id: String, team: int, pos: Vector2) -> Dictionary:
	return {
		"ship_id": id,
		"type": "fighter",
		"team": team,
		"position": pos,
		"rotation": 0.0,
		"velocity": Vector2.ZERO,
		"status": "operational",
		"collision_radius": 15.0,
		"stats": {"max_speed": 300.0, "acceleration": 100.0, "turn_rate": 3.0, "mass": 50.0, "size": 15.0},
		"orders": {"current_order": "", "target_id": ""},
		"armor_sections": [{"section_id": "front", "current_armor": 100.0, "max_armor": 100.0, "arc": {"start": -90, "end": 90}}]
	}

func _set_armor(ship: Dictionary, ratio: float) -> Dictionary:
	ship["armor_sections"] = [{
		"section_id": "front",
		"current_armor": 100.0 * ratio,
		"max_armor": 100.0,
		"arc": {"start": -90, "end": 90}
	}]
	return ship

func test_elite_tactician_retreats_when_damaged_and_outnumbered_without_support():
	# BEHAVIOR: Elite tacticians proactively disengage when the situation is
	# tactically untenable — damaged, outnumbered, no support nearby.
	var crew = _make_crew(0.85, 0.5)
	var me = _make_fighter("me", 0, Vector2.ZERO)
	me = _set_armor(me, 0.35)  # Below SURVIVAL_TACTICAL_HULL_RATIO (0.40)

	var enemies = [
		_make_fighter("e1", 1, Vector2(800, 0)),
		_make_fighter("e2", 1, Vector2(0, 800))
	]
	var ships = [me] + enemies

	var mode = FighterPilotAI._assess_survival_state(crew, me, ships)
	assert_eq(mode, "retreat", "Elite tactician should retreat when damaged, outnumbered, and unsupported")

func test_rookie_does_not_tactical_disengage_in_same_conditions():
	# BEHAVIOR: The tactical disengage is an elite skill — a rookie with the same
	# hull damage and enemy count should NOT trigger the elite retreat path.
	# They may still evade from the normal outnumbered check, but NOT from
	# the tactical disengage threshold.
	var rookie = _make_crew(0.2, 0.5)
	var me = _make_fighter("me", 0, Vector2.ZERO)
	me = _set_armor(me, 0.35)

	var enemies = [
		_make_fighter("e1", 1, Vector2(800, 0)),
		_make_fighter("e2", 1, Vector2(0, 800))
	]
	var ships = [me] + enemies

	var mode = FighterPilotAI._assess_survival_state(rookie, me, ships)
	# Rookie does not have access to the "retreat" path via tactical disengage.
	# They may get "evade" from the outnumbered check, but NOT "retreat" unless
	# hull is below the critical threshold (which 35% is not for mid-aggression).
	assert_ne(mode, "retreat", "Rookie must NOT tactical-disengage to retreat")

func test_elite_tactician_at_full_health_does_not_tactical_disengage():
	# BEHAVIOR: Tactical disengage only fires when the pilot is actually damaged.
	# A fresh elite pilot in bad odds should rely on the normal outnumbered check,
	# not proactively flee.
	var crew = _make_crew(0.85, 0.5)
	var me = _make_fighter("me", 0, Vector2.ZERO)
	# Full armor — above SURVIVAL_TACTICAL_HULL_RATIO

	var enemies = [
		_make_fighter("e1", 1, Vector2(800, 0)),
		_make_fighter("e2", 1, Vector2(0, 800))
	]
	var ships = [me] + enemies

	var mode = FighterPilotAI._assess_survival_state(crew, me, ships)
	assert_ne(mode, "retreat", "Elite tactician at full health must not tactical-disengage")

func test_elite_tactician_with_friendly_support_does_not_disengage():
	# BEHAVIOR: The tactical disengage only fires when support is absent.
	# With a friendly wingman nearby, the elite pilot holds the line.
	var crew = _make_crew(0.85, 0.5)
	var me = _make_fighter("me", 0, Vector2.ZERO)
	me = _set_armor(me, 0.35)

	var friendly = _make_fighter("friend1", 0, Vector2(500, 0))
	var enemies = [
		_make_fighter("e1", 1, Vector2(800, 0)),
		_make_fighter("e2", 1, Vector2(0, 800))
	]
	var ships = [me, friendly] + enemies

	var mode = FighterPilotAI._assess_survival_state(crew, me, ships)
	assert_ne(mode, "retreat", "Elite tactician with friendly support must NOT tactical-disengage")
