class_name SurrenderSystem
extends RefCounted

## Surrender win condition for fleeing fleets.
##
## When most of a side's surviving ships are actively fleeing, a countdown
## starts; if the fleeing majority holds until it expires, that side
## surrenders and the other side wins. If the side rallies (fleeing fraction
## drops back to half or below), the countdown cancels.
##
## Pure functions only — state lives in a plain Dictionary owned by
## SpaceBattleGame and is advanced by tick().
##
## Flee signals (see fighter_pilot_ai.gd / fighter_brain.gd /
## large_ship_pilot_ai.gd):
##   - ship.orders.survival_mode == "retreat"/"evade" — written by
##     CrewIntegrationSystem from the pilot's survival-reflex decision
##   - crew.combat_state.locked_action_id == "evade_outnumbered" — the GOAP
##     brain's tactical disengage action lock
##   - ship.orders.maneuver_subtype == "large_ship_fighting_withdrawal" —
##     capital/corvette withdrawal phase
## NOTE: engagement_phase "extending" is a normal firing-pass phase and is
## deliberately NOT treated as fleeing.

const SURRENDER_COUNTDOWN_SECONDS := 20.0
## "Most" = strictly more than half of the side's alive ships.
const FLEEING_MAJORITY_FRACTION := 0.5
## A side's last lone ship fleeing shouldn't auto-surrender into a loss.
const MIN_SHIPS_FOR_SURRENDER := 2
const TEAMS := [0, 1]
const NO_SURRENDER := -1

const FLEEING_SURVIVAL_MODES := ["retreat", "evade"]
const FLEEING_LOCKED_ACTION_ID := "evade_outnumbered"
const FLEEING_LARGE_SHIP_SUBTYPE := "large_ship_fighting_withdrawal"
const SHIP_STATUS_DESTROYED := "destroyed"


## Fresh per-team countdown state: no countdown running for either team.
static func initial_state() -> Dictionary:
	var state := {}
	for team in TEAMS:
		state[team] = _idle_team_state()
	return state


## True when this ship is actively fleeing the battle.
## crew_for_ship: crew dicts whose assigned_to matches this ship.
static func is_ship_fleeing(ship: Dictionary, crew_for_ship: Array) -> bool:
	var orders: Dictionary = ship.get("orders", {})
	if orders.get("survival_mode", "") in FLEEING_SURVIVAL_MODES:
		return true
	if orders.get("maneuver_subtype", "") == FLEEING_LARGE_SHIP_SUBTYPE:
		return true
	for crew in crew_for_ship:
		var combat_state: Dictionary = crew.get("combat_state", {})
		if combat_state.get("locked_action_id", "") == FLEEING_LOCKED_ACTION_ID:
			return true
	return false


## Advance the surrender state by delta. Per team: compute the fleeing
## fraction among alive ships; a strict majority fleeing starts/continues
## that team's countdown, otherwise the countdown clears.
static func tick(state: Dictionary, ships: Array, crew_list: Array, delta: float) -> Dictionary:
	var crew_by_ship := _group_crew_by_ship(crew_list)
	var new_state := {}
	for team in TEAMS:
		var alive := 0
		var fleeing := 0
		for ship in ships:
			if ship == null or ship.is_empty():
				continue
			if ship.get("team", -1) != team:
				continue
			if ship.get("status", "") == SHIP_STATUS_DESTROYED:
				continue
			alive += 1
			if is_ship_fleeing(ship, crew_by_ship.get(ship.get("ship_id", ""), [])):
				fleeing += 1

		var majority_fleeing: bool = alive >= MIN_SHIPS_FOR_SURRENDER \
			and float(fleeing) > float(alive) * FLEEING_MAJORITY_FRACTION
		if majority_fleeing:
			var prev: Dictionary = state.get(team, _idle_team_state())
			var remaining: float = prev.time_remaining if prev.countdown_active \
				else SURRENDER_COUNTDOWN_SECONDS
			new_state[team] = {
				"countdown_active": true,
				"time_remaining": maxf(remaining - delta, 0.0),
			}
		else:
			new_state[team] = _idle_team_state()
	return new_state


## Team whose countdown has expired, or NO_SURRENDER (-1).
static func surrendered_team(state: Dictionary) -> int:
	for team in state:
		var team_state: Dictionary = state[team]
		if team_state.get("countdown_active", false) \
				and team_state.get("time_remaining", SURRENDER_COUNTDOWN_SECONDS) <= 0.0:
			return team
	return NO_SURRENDER


static func _idle_team_state() -> Dictionary:
	return {"countdown_active": false, "time_remaining": SURRENDER_COUNTDOWN_SECONDS}


static func _group_crew_by_ship(crew_list: Array) -> Dictionary:
	var grouped := {}
	for crew in crew_list:
		var ship_id: String = crew.get("assigned_to", "")
		if ship_id == "":
			continue
		if not grouped.has(ship_id):
			grouped[ship_id] = []
		grouped[ship_id].append(crew)
	return grouped
