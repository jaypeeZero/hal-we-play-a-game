extends GutTest

## Tests for Layer A — press-to-effective-range maneuver vs capitals.
## Asserts BEHAVIOR: posture selects closing maneuver, movement system closes,
## no regression when posture is absent.

const GAME_TIME := 100.0


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_fighter_with_posture(press: bool, expires_at: float = 9999.0) -> Dictionary:
	var crew := TestFactories.make_pilot("p1", "fighter_1")
	if press:
		crew["combat_posture"] = {
			"subtype": "press_attack",
			"target_id": "",
			"expires_at": expires_at,
			"player_override": false,
		}
	return crew


func _make_capital(id: String = "cap1", pos: Vector2 = Vector2(3000, 0)) -> Dictionary:
	return TestFactories.make_capital(id, pos, 1)  # enemy team


func _make_fighter_ship(id: String = "fighter_1", pos: Vector2 = Vector2.ZERO) -> Dictionary:
	return TestFactories.make_fighter(id, pos)


func _build_ws(crew: Dictionary, fighter: Dictionary, capital: Dictionary) -> FighterWorldState:
	return FighterWorldState.build(
		crew, fighter, [fighter, capital], [], GAME_TIME, []
	)


# ---------------------------------------------------------------------------
# AttackAction._vs_capital selects maneuver based on posture
# ---------------------------------------------------------------------------

func test_press_attack_posture_drives_aggressive_blend():
	# Press-attack now routes through the blender (subtype "tactical") with the
	# "press" posture: pursue dominant, keep_range/evade minimal — close and brawl.
	var crew := _make_fighter_with_posture(true)
	var fighter := _make_fighter_ship()
	var capital := _make_capital("cap1", Vector2(2000, 0))
	var ws := _build_ws(crew, fighter, capital)

	var action := AttackAction.new()
	var decision := action.execute(ws)

	assert_eq(decision.get("subtype", ""), "tactical",
		"Press posture routes through the blender, not a discrete maneuver")
	var gw: Dictionary = decision.get("goal_weights", {})
	assert_gt(gw.get("pursue", 0.0), gw.get("keep_range", 1.0),
		"Press posture makes pursue dominant — the fighter commits and closes")
	assert_gt(gw.get("pursue", 0.0), gw.get("evade", 1.0),
		"Press posture commits despite incoming fire (pursue >> evade)")


func test_no_posture_does_not_select_press_attack():
	# Without a posture, the fighter must never pick fight_press_attack regardless
	# of which specific maneuver the knowledge/fallback system selects.
	var crew := _make_fighter_with_posture(false)
	var fighter := _make_fighter_ship()
	var capital := _make_capital("cap1", Vector2(2000, 0))
	var ws := _build_ws(crew, fighter, capital)

	assert_false(ws.press_attack,
		"Without a posture, press_attack should be false in the world state")

	var action := AttackAction.new()
	var decision := action.execute(ws)

	# All non-reflex engage decisions are "tactical" now; without a press posture
	# the blender uses tactics-derived weights, not the aggressive press set.
	assert_eq(decision.get("subtype", ""), "tactical",
		"Without posture, the fighter still emits a normal blended decision")


func test_expired_posture_does_not_press():
	var crew := _make_fighter_with_posture(true, GAME_TIME - 1.0)  # expired
	var fighter := _make_fighter_ship()
	var capital := _make_capital("cap1", Vector2(2000, 0))
	var ws := _build_ws(crew, fighter, capital)

	assert_false(ws.press_attack,
		"An expired posture should not activate press_attack")

	var action := AttackAction.new()
	var decision := action.execute(ws)
	var gw: Dictionary = decision.get("goal_weights", {})
	# Expired posture → press_attack is false → blender uses normal weights, so
	# pursue is NOT forced to the press-dominant value.
	assert_lt(gw.get("pursue", 1.0), 0.9,
		"Expired posture must not drive the aggressive press blend")


func test_player_override_ignores_expiry():
	var crew := _make_fighter_with_posture(false)
	crew["combat_posture"] = {
		"subtype": "press_attack",
		"target_id": "",
		"expires_at": GAME_TIME - 100.0,  # long expired
		"player_override": true,
	}
	var fighter := _make_fighter_ship()
	var capital := _make_capital("cap1", Vector2(2000, 0))
	var ws := _build_ws(crew, fighter, capital)

	assert_true(ws.press_attack,
		"A player_override posture should remain active past expires_at")


# Note: press-attack closing is no longer a discrete movement function
# (calculate_press_attack was removed). It is now the "press" steering posture —
# pursue-dominant, low keep_range — covered by
# test_press_attack_posture_drives_aggressive_blend above and the SteeringBlender
# posture tests.


# ---------------------------------------------------------------------------
# Posture absorption
# ---------------------------------------------------------------------------

func test_posture_order_absorbed_into_combat_posture():
	var crew := TestFactories.make_pilot("p1", "ship_1")
	crew.orders["received"] = {
		"type": "posture",
		"subtype": "press_attack",
		"target_id": "cap1",
		"expires_at": GAME_TIME + 30.0,
		"player_override": false,
		"timestamp": GAME_TIME,
	}

	var updated := CrewAISystem._absorb_posture_order(crew)

	assert_true(updated.has("combat_posture"),
		"Absorbed posture order should populate combat_posture slot")
	assert_eq(updated.combat_posture.get("subtype", ""), "press_attack",
		"combat_posture.subtype should be 'press_attack'")
	assert_null(updated.orders.received,
		"orders.received should be cleared after absorption")


func test_non_posture_order_not_absorbed():
	var crew := TestFactories.make_pilot("p1", "ship_1")
	crew.orders["received"] = {
		"type": "engage",
		"target_id": "cap1",
	}

	var updated := CrewAISystem._absorb_posture_order(crew)

	assert_false(updated.has("combat_posture"),
		"Non-posture orders must not be absorbed as combat_posture")
	assert_not_null(updated.orders.received,
		"orders.received should be untouched for non-posture orders")


func test_posture_target_id_overrides_fighter_target():
	# When posture carries a target_id that is valid, the fighter should focus on it.
	var crew := _make_fighter_with_posture(false)
	crew["combat_posture"] = {
		"subtype": "press_attack",
		"target_id": "cap1",
		"expires_at": GAME_TIME + 30.0,
		"player_override": false,
	}
	var fighter := _make_fighter_ship()
	var capital := TestFactories.make_capital("cap1", Vector2(1500, 0), 1)  # enemy team
	var ws := _build_ws(crew, fighter, capital)

	assert_eq(ws.target_id, "cap1",
		"Posture's target_id should override normal target resolution")
