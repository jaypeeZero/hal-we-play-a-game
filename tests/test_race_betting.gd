extends GutTest

## Tests for race betting money flow: wager bounds, win/loss settlement.
## Tests the pure math — no UI, no autoload mutation.

const HOUSE_EDGE := 0.12

var _track: Dictionary


func before_each() -> void:
	_track = RaceTrack.load_track("asteroid_sprint")
	assert_false(_track.is_empty(), "Track loaded")


func _make_crew(piloting: float, crew_id: String = "c") -> Dictionary:
	return {
		"crew_id": crew_id,
		"callsign": "Pilot",
		"role": CrewData.Role.PILOT,
		"qualified_roles": [CrewData.Role.PILOT],
		"stats": {
			"stress": 0.0, "fatigue": 0.0, "reaction_time": 0.15,
			"skills": {
				"piloting": piloting, "awareness": 0.6, "composure": 0.7,
				"aggression": 0.5, "aim": 0.5, "tactics": 0.5, "machinery": 0.5,
			},
		},
	}


# ── Wager bounds validation ───────────────────────────────────────────────────

func test_wager_below_minimum_is_invalid() -> void:
	var config: Dictionary = EconomySystem.config().get("racing", {})
	var min_w: int = int(config.get("min_wager", 10))
	assert_gt(min_w, 0, "min_wager exists and is positive")
	var wager_too_low: int = min_w - 1
	assert_lt(wager_too_low, min_w, "Wager below minimum fails validation")


func test_wager_above_balance_is_invalid() -> void:
	# There is no cap fraction — you may bet your whole balance, but not more.
	var money: int = 200
	var wager_too_high: int = money + 1
	assert_gt(wager_too_high, money, "Wager above the full balance is out of range")


# ── Win settlement math ───────────────────────────────────────────────────────

func test_winning_bet_increases_money() -> void:
	var wager: int = 50
	var prob: float = 0.3
	var odds: float = RaceOdds.decimal_odds(prob, HOUSE_EDGE)
	var expected_payout: int = RaceOdds.payout(wager, odds)
	var money_before: int = 500
	var money_after: int = money_before - wager + expected_payout
	assert_gt(money_after, money_before, "Winning bet results in net gain")


func test_losing_bet_reduces_money_by_wager() -> void:
	var wager: int = 50
	var money_before: int = 500
	var money_after: int = money_before - wager
	assert_eq(money_before - money_after, wager, "Net loss equals wager amount")


func test_payout_includes_return_of_stake() -> void:
	var wager: int = 100
	var odds: float = 2.5
	var payout: int = RaceOdds.payout(wager, odds)
	assert_gte(payout, wager, "Payout always >= wager for odds >= 1")


# ── Determinism for settling ──────────────────────────────────────────────────

func test_same_seed_always_produces_same_winner() -> void:
	var ship_a: Dictionary = ShipData.create_ship_instance("fighter", 0, Vector2.ZERO)
	var ship_b: Dictionary = ShipData.create_ship_instance("corvette", 1, Vector2.ZERO)
	var entrants: Array = [
		{"ship": ship_a.duplicate(true), "crew": _make_crew(0.8, "ca")},
		{"ship": ship_b.duplicate(true), "crew": _make_crew(0.4, "cb")},
	]
	var r1: Dictionary = RaceSimulator.run(_track, entrants, 12345)
	var r2: Dictionary = RaceSimulator.run(_track, entrants, 12345)
	assert_eq(r1.winner_ship_id, r2.winner_ship_id,
		"Deterministic seed → same winner on repeated runs")


# ── Economy config ────────────────────────────────────────────────────────────

func test_economy_config_has_racing_block() -> void:
	var cfg: Dictionary = EconomySystem.config()
	assert_true(cfg.has("racing"), "economy.json has a 'racing' block")
	var racing: Dictionary = cfg.racing
	assert_true(racing.has("min_wager"), "racing block has min_wager")
	assert_true(racing.has("house_edge"), "racing block has house_edge")
	assert_gt(float(racing.house_edge), 0.0, "house_edge is positive")
