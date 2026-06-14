class_name TacticsTelemetry
extends RefCounted

## DEV-ONLY tactical telemetry — pure functions over a ships snapshot.
##
## Purpose: validate that distinct doctrine presets produce measurably distinct
## combat patterns so we can prove emergence without player-facing UI.
## Nothing here modifies game state or wires into the live sim loop.
##
## All functions take the full ships Array[Dictionary] and operate over a
## consistent snapshot — callers must not mutate ships between calls in a
## single telemetry frame.

## Half-width (in world units) of the "center" lateral sector.
## Ships within this distance of the team→anchor axis midline count as center;
## beyond it they are left or right.
const CENTER_SECTOR_HALF_WIDTH := 100.0

# ---------------------------------------------------------------------------
# CENTROID HELPERS
# ---------------------------------------------------------------------------

## Mean position of all ships on `team`. Returns Vector2.ZERO if team is empty.
static func team_centroid(ships: Array, team: int) -> Vector2:
	var sum := Vector2.ZERO
	var count := 0
	for ship in ships:
		if ship.get("team", -1) == team and _is_active(ship):
			sum += ship.position
			count += 1
	if count == 0:
		return Vector2.ZERO
	return sum / float(count)

## Mean position of all ships NOT on `team`. Doubles as default anchor for
## sector_mass_distribution (the enemy-fleet centroid).
static func enemy_centroid(ships: Array, team: int) -> Vector2:
	var sum := Vector2.ZERO
	var count := 0
	for ship in ships:
		if ship.get("team", -1) != team and _is_active(ship):
			sum += ship.position
			count += 1
	if count == 0:
		return Vector2.ZERO
	return sum / float(count)

# ---------------------------------------------------------------------------
# METRIC FUNCTIONS
# ---------------------------------------------------------------------------

## Mean distance from each of `team`'s ships to its current target.
## Uses orders.target_id; falls back to the nearest active enemy when no target
## is set or the named target is not found. Low = brawling, high = kiting.
static func mean_engagement_range(ships: Array, team: int) -> float:
	var total := 0.0
	var count := 0
	for ship in ships:
		if ship.get("team", -1) != team or not _is_active(ship):
			continue
		var target := _resolve_target(ships, ship, team)
		if target.is_empty():
			continue
		total += ship.position.distance_to(target.position)
		count += 1
	if count == 0:
		return 0.0
	return total / float(count)

## Mean distance of `team`'s ships from their team centroid.
## Low = tight formation, high = dispersed. Distinguishes wall vs spread.
static func formation_dispersion(ships: Array, team: int) -> float:
	var centroid := team_centroid(ships, team)
	var total := 0.0
	var count := 0
	for ship in ships:
		if ship.get("team", -1) != team or not _is_active(ship):
			continue
		total += ship.position.distance_to(centroid)
		count += 1
	if count == 0:
		return 0.0
	return total / float(count)

## Herfindahl-Hirschman Index over which enemy each of `team`'s ships targets.
## Returns ~1.0 when everyone focus-fires a single enemy; approaches 1/N when
## targeting is spread evenly across N enemies. Returns 0.0 if no one targets.
##
## Why HHI: it captures *concentration* in one number without needing to know
## how many enemies exist — a single dominant target reads as near-1.0 regardless
## of fleet size.
static func focus_concentration(ships: Array, team: int) -> float:
	# Count how many of team's ships target each enemy id.
	var target_counts: Dictionary = {}
	var total_targeters := 0
	for ship in ships:
		if ship.get("team", -1) != team or not _is_active(ship):
			continue
		var tid: String = ship.get("orders", {}).get("target_id", "")
		if tid == "":
			continue
		target_counts[tid] = target_counts.get(tid, 0) + 1
		total_targeters += 1
	if total_targeters == 0:
		return 0.0
	# HHI = sum of squared market-share fractions.
	var hhi := 0.0
	for tid in target_counts:
		var share: float = float(target_counts[tid]) / float(total_targeters)
		hhi += share * share
	return hhi

## Fraction of `team`'s ships in left / center / right lateral sectors relative
## to the axis from team centroid → `anchor` (normally the enemy-fleet centroid).
##
## The axis is the forward direction from the team toward the enemy. "Right" and
## "left" are from the perspective of a ship facing the enemy. Ships within
## CENTER_SECTOR_HALF_WIDTH of the axis midline are "center"; beyond that they
## are "left" or "right" depending on which side of the axis they fall.
##
## Returns {"left": f, "center": f, "right": f} summing to ~1.0.
## All zero dict if team has no active ships.
static func sector_mass_distribution(ships: Array, team: int, anchor: Vector2) -> Dictionary:
	var centroid := team_centroid(ships, team)
	# Forward axis: team centroid → enemy anchor. If the two points are the same
	# (degenerate case), no meaningful axis exists — return equal thirds.
	var axis := anchor - centroid
	if axis.length_squared() < 0.001:
		return {"left": 1.0 / 3.0, "center": 1.0 / 3.0, "right": 1.0 / 3.0}
	# Perpendicular (rightward from the team's perspective facing the enemy).
	var right_dir := Vector2(-axis.y, axis.x).normalized()

	var left_count := 0
	var center_count := 0
	var right_count := 0
	for ship in ships:
		if ship.get("team", -1) != team or not _is_active(ship):
			continue
		var offset: Vector2 = ship.position - centroid
		var lateral: float = offset.dot(right_dir)
		if lateral > CENTER_SECTOR_HALF_WIDTH:
			right_count += 1
		elif lateral < -CENTER_SECTOR_HALF_WIDTH:
			left_count += 1
		else:
			center_count += 1

	var total := float(left_count + center_count + right_count)
	if total == 0.0:
		return {"left": 0.0, "center": 0.0, "right": 0.0}
	return {
		"left": float(left_count) / total,
		"center": float(center_count) / total,
		"right": float(right_count) / total,
	}

## Bundles all metrics into one Dictionary for a single log call.
## `anchor` defaults to the enemy centroid when Vector2.ZERO is passed — call
## enemy_centroid() explicitly if you need to cache it.
static func snapshot(ships: Array, team: int, anchor: Vector2 = Vector2.ZERO) -> Dictionary:
	var effective_anchor := anchor if anchor != Vector2.ZERO else enemy_centroid(ships, team)
	return {
		"team": team,
		"mean_engagement_range": mean_engagement_range(ships, team),
		"formation_dispersion": formation_dispersion(ships, team),
		"focus_concentration": focus_concentration(ships, team),
		"sector_mass_distribution": sector_mass_distribution(ships, team, effective_anchor),
	}

# ---------------------------------------------------------------------------
# INTERNAL HELPERS
# ---------------------------------------------------------------------------

## Ship is considered active (counts toward metrics) when not fled/destroyed.
static func _is_active(ship: Dictionary) -> bool:
	var status: String = ship.get("status", "operational")
	return status != "destroyed" and status != "fled"

## Resolve the target for `ship`: prefer orders.target_id, fall back to nearest
## active enemy. Returns an empty Dictionary when no enemy exists.
static func _resolve_target(ships: Array, ship: Dictionary, team: int) -> Dictionary:
	var tid: String = ship.get("orders", {}).get("target_id", "")
	if tid != "":
		for candidate in ships:
			if candidate.get("ship_id", "") == tid and _is_active(candidate):
				return candidate
	# Fallback: nearest active enemy.
	var nearest: Dictionary = {}
	var best_dist := INF
	for candidate in ships:
		if candidate.get("team", -1) == team or not _is_active(candidate):
			continue
		var d: float = ship.position.distance_to(candidate.position)
		if d < best_dist:
			best_dist = d
			nearest = candidate
	return nearest
