extends GutTest

## Tests for RaceOdds: probability ordering, house edge, payout math.

const HOUSE_EDGE := 0.12

var _track: Dictionary


func before_each() -> void:
	_track = RaceTrack.load_track("asteroid_sprint")
	assert_false(_track.is_empty(), "Track loaded")


func _make_crew(piloting: float) -> Dictionary:
	return {
		"crew_id": "c",
		"callsign": "R",
		"role": CrewData.Role.PILOT,
		"qualified_roles": [CrewData.Role.PILOT],
		"stats": {
			"stress": 0.0, "fatigue": 0.0, "reaction_time": 0.15,
			"skills": {
				"piloting": piloting, "awareness": piloting, "composure": piloting,
				"aggression": 0.5, "aim": 0.5, "tactics": 0.5, "machinery": 0.5,
			},
		},
	}


# ── Probability ordering ──────────────────────────────────────────────────────

func test_implied_probabilities_sum_to_approximately_one() -> void:
	var entrants: Array = [
		{"ship": ShipData.create_ship_instance("fighter", 0, Vector2.ZERO),
			"crew": _make_crew(0.8)},
		{"ship": ShipData.create_ship_instance("corvette", 1, Vector2.ZERO),
			"crew": _make_crew(0.3)},
	]
	var probs: Array = RaceOdds.implied_probabilities(entrants, _track)
	var total: float = 0.0
	for p: float in probs:
		total += p
	assert_almost_eq(total, 1.0, 0.001, "Implied probabilities sum to ~1.0")


func test_stronger_entrant_has_higher_win_probability() -> void:
	var entrants: Array = [
		{"ship": ShipData.create_ship_instance("fighter", 0, Vector2.ZERO),
			"crew": _make_crew(0.9)},
		{"ship": ShipData.create_ship_instance("corvette", 1, Vector2.ZERO),
			"crew": _make_crew(0.2)},
	]
	var probs: Array = RaceOdds.implied_probabilities(entrants, _track)
	assert_gt(float(probs[0]), float(probs[1]),
		"Stronger entrant has higher implied probability")


# ── Decimal odds ─────────────────────────────────────────────────────────────

func test_decimal_odds_decrease_as_probability_increases() -> void:
	var odds_long: float  = RaceOdds.decimal_odds(0.1, HOUSE_EDGE)
	var odds_short: float = RaceOdds.decimal_odds(0.7, HOUSE_EDGE)
	assert_gt(odds_long, odds_short, "Longer-shot has higher decimal odds")


func test_house_edge_makes_book_over_one() -> void:
	var entrants: Array = [
		{"ship": ShipData.create_ship_instance("fighter", 0, Vector2.ZERO),
			"crew": _make_crew(0.7)},
		{"ship": ShipData.create_ship_instance("corvette", 1, Vector2.ZERO),
			"crew": _make_crew(0.4)},
	]
	var probs: Array = RaceOdds.implied_probabilities(entrants, _track)
	var total_implied: float = 0.0
	for p: float in probs:
		var o: float = RaceOdds.decimal_odds(p, HOUSE_EDGE)
		total_implied += 1.0 / o
	assert_gt(total_implied, 1.0, "Book > 1 when house edge > 0")


# ── Payout math ───────────────────────────────────────────────────────────────

func test_payout_greater_than_wager_for_odds_above_one() -> void:
	var wager: int = 50
	var odds: float = RaceOdds.decimal_odds(0.2, HOUSE_EDGE)
	assert_gt(odds, 1.0, "Odds > 1 for non-certainty")
	assert_gt(RaceOdds.payout(wager, odds), wager,
		"Payout exceeds wager when odds > 1")


func test_payout_scales_with_wager() -> void:
	var odds: float = 3.5
	var small: int = RaceOdds.payout(10, odds)
	var large: int = RaceOdds.payout(100, odds)
	assert_gt(large, small, "Larger wager yields larger payout")
