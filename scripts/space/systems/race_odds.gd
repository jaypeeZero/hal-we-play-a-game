class_name RaceOdds
extends RefCounted

## Rating-model odds: ship envelope + pilot skill → implied win probability → decimal odds.
## No Monte-Carlo. Instant. Odds correlate with but don't perfectly predict results
## (composure variance creates upsets).

## Skill weight relative to ship stats in the overall rating.
const SKILL_WEIGHT := 0.55
const SHIP_WEIGHT := 0.45

## Within skill, weights per skill (must sum to 1.0).
const SKILL_WEIGHTS := {
	"piloting":  0.40,
	"awareness": 0.25,
	"composure": 0.25,
	"aggression": 0.10,
}

## Technical tracks reward turn/piloting more; oval tracks reward speed.
## Track "technical" flag adds this bonus weight to turn-related factors.
const TECHNICAL_PILOTING_BONUS := 0.15
const TECHNICAL_SPEED_PENALTY := -0.10

## Minimum implied probability (prevents division by zero / extreme odds).
const MIN_IMPLIED_PROBABILITY := 0.02
## Minimum decimal odds (cannot pay out less than you wagered).
const MIN_DECIMAL_ODDS := 1.01


## Power rating for one entrant. Higher = stronger favourite.
static func rate_entrant(ship: Dictionary, crew: Dictionary, track: Dictionary) -> float:
	"""Blend ship performance envelope with pilot skills, track-weighted."""
	var stats: Dictionary = ship.get("stats", {})
	var skills: Dictionary = crew.get("stats", {}).get("skills", {})
	var is_technical: bool = track.get("technical", false)

	# Ship performance score (normalized to [0,1] using known stat ranges).
	var max_speed_norm: float = clamp(float(stats.get("max_speed", 200.0)) / 400.0, 0.0, 1.0)
	var accel_norm: float    = clamp(float(stats.get("acceleration", 80.0)) / 150.0, 0.0, 1.0)
	var turn_norm: float     = clamp(float(stats.get("turn_rate", 2.0)) / 6.0, 0.0, 1.0)
	var lateral_norm: float  = clamp(float(stats.get("lateral_acceleration", 0.5)) / 1.0, 0.0, 1.0)

	var speed_weight: float = 0.4 + (TECHNICAL_SPEED_PENALTY if is_technical else 0.0)
	var turn_weight: float  = 0.35 + (TECHNICAL_PILOTING_BONUS if is_technical else 0.0)
	var accel_weight: float = 0.15
	var lateral_weight: float = 0.10
	# Normalize weights.
	var total_ship_w: float = speed_weight + turn_weight + accel_weight + lateral_weight
	var ship_score: float = (max_speed_norm * speed_weight
		+ turn_norm * turn_weight
		+ accel_norm * accel_weight
		+ lateral_norm * lateral_weight) / total_ship_w

	# Pilot skill score.
	var skill_score: float = 0.0
	for skill_name in SKILL_WEIGHTS:
		var w: float = float(SKILL_WEIGHTS[skill_name])
		var val: float = clamp(float(skills.get(skill_name, 0.5)), 0.0, 1.0)
		if is_technical and skill_name == "piloting":
			w += TECHNICAL_PILOTING_BONUS
		skill_score += val * w

	return SHIP_WEIGHT * ship_score + SKILL_WEIGHT * skill_score


## Compute implied win probabilities for the whole field.
## entrants: Array of {ship, crew}. Returns parallel Array of floats summing to 1.
static func implied_probabilities(entrants: Array, track: Dictionary) -> Array:
	"""Convert ratings to normalized win probabilities."""
	var ratings: Array = []
	for e in entrants:
		ratings.append(rate_entrant(e.ship, e.crew, track))
	var total: float = 0.0
	for r in ratings:
		total += r
	if total <= 0.0:
		# Uniform distribution as fallback.
		var n: float = float(max(entrants.size(), 1))
		var probs: Array = []
		for _i in range(entrants.size()):
			probs.append(1.0 / n)
		return probs
	var probs: Array = []
	for r in ratings:
		probs.append(max(r / total, MIN_IMPLIED_PROBABILITY))
	return probs


## Convert a win probability and house edge to decimal odds.
## decimal_odds = (1/prob) * (1 - house_edge). Payoff is odds × wager (includes stake).
static func decimal_odds(prob: float, house_edge: float) -> float:
	"""Compute decimal odds from implied probability and house edge."""
	if prob <= 0.0:
		return MIN_DECIMAL_ODDS
	var fair_odds: float = 1.0 / max(prob, MIN_IMPLIED_PROBABILITY)
	return max(fair_odds * (1.0 - clamp(house_edge, 0.0, 0.99)), MIN_DECIMAL_ODDS)


## Compute integer payout for a winning bet. Includes return of the wager.
static func payout(wager: int, odds: float) -> int:
	"""Floor(wager × odds). Always >= wager for odds > 1."""
	return int(floor(float(wager) * odds))
