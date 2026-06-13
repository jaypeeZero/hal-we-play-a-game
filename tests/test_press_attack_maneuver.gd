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

func test_press_attack_posture_selects_closing_maneuver():
	var crew := _make_fighter_with_posture(true)
	var fighter := _make_fighter_ship()
	var capital := _make_capital("cap1", Vector2(2000, 0))
	var ws := _build_ws(crew, fighter, capital)

	var action := AttackAction.new()
	var decision := action.execute(ws)

	assert_eq(decision.get("subtype", ""), "fight_press_attack",
		"Fighter with press_attack posture vs capital should select fight_press_attack")


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

	assert_ne(decision.get("subtype", ""), "fight_press_attack",
		"Without posture, fighter must not select fight_press_attack vs capital")


func test_expired_posture_does_not_press():
	var crew := _make_fighter_with_posture(true, GAME_TIME - 1.0)  # expired
	var fighter := _make_fighter_ship()
	var capital := _make_capital("cap1", Vector2(2000, 0))
	var ws := _build_ws(crew, fighter, capital)

	assert_false(ws.press_attack,
		"An expired posture should not activate press_attack")

	var action := AttackAction.new()
	var decision := action.execute(ws)
	assert_ne(decision.get("subtype", ""), "fight_press_attack",
		"Expired posture must not select the press maneuver")


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


# ---------------------------------------------------------------------------
# Movement system: calculate_press_attack behavior
# ---------------------------------------------------------------------------

func _ship_with_pos(pos: Vector2) -> Dictionary:
	return TestFactories.make_fighter("s", pos)


func test_press_attack_far_from_target_applies_main_thrust():
	# Fighter is well beyond PRESS_ATTACK_RANGE — should thrust toward target.
	var fighter := _ship_with_pos(Vector2.ZERO)
	var capital := _make_capital("cap1", Vector2(WingConstants.PRESS_ATTACK_RANGE * 3, 0))

	var ctrl := MovementSystem.calculate_press_attack(fighter, capital, GAME_TIME)

	assert_gt(ctrl.get("throttle", 0.0), 0.0,
		"Fighter far outside effective range should apply main thrust to close")


func test_press_attack_inside_range_stops_closing():
	# Fighter is well inside PRESS_ATTACK_RANGE — should brake, not thrust.
	var fighter := _ship_with_pos(Vector2.ZERO)
	var capital := _make_capital("cap1", Vector2(WingConstants.PRESS_ATTACK_RANGE * 0.3, 0))

	var ctrl := MovementSystem.calculate_press_attack(fighter, capital, GAME_TIME)

	assert_eq(ctrl.get("throttle", 1.0), 0.0,
		"Fighter inside effective range should not apply closing thrust")
	assert_true(ctrl.get("is_braking", false),
		"Fighter inside effective range should brake")


func test_press_attack_within_band_holds_position():
	# Fighter is exactly at PRESS_ATTACK_RANGE — no thrust, no brake.
	var fighter := _ship_with_pos(Vector2.ZERO)
	var capital := _make_capital("cap1", Vector2(WingConstants.PRESS_ATTACK_RANGE, 0))

	var ctrl := MovementSystem.calculate_press_attack(fighter, capital, GAME_TIME)

	assert_eq(ctrl.get("throttle", 1.0), 0.0,
		"Fighter at PRESS_ATTACK_RANGE should not apply thrust")
	assert_false(ctrl.get("is_braking", true),
		"Fighter at PRESS_ATTACK_RANGE should not brake")


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
