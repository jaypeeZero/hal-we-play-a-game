class_name CommandDesignationSystem
extends RefCounted

## CommandDesignationSystem — per-tick designation of command hats onto crew.
##
## Command roles are HATS, not crew: a Squadron Leader is a pilot who ALSO
## leads a wing; a Commander is a captain who ALSO leads the team's fleet.
## Neither hat creates a new crew member.  All-static, pure: inputs are never
## mutated; a modified copy is returned.
##
## Designed to run immediately after WingFormationSystem.form_wings() each tick
## so it always reflects fresh wing membership.  The hats it stamps drive
## command-brain dispatch in CrewAISystem (CommanderBrain / SquadronLeaderBrain).


## Hull-class rank: higher = better.  Used as the primary sort key when
## choosing which ship's captain becomes Commander.  Ties broken by integrity.
const HULL_CLASS_RANK: Dictionary = {
	"capital":       5,
	"corvette":      4,
	"heavy_fighter": 3,
	"torpedo_boat":  2,
	"fighter":       1,
}

## Designate command hats for every crew member.
##
## Returns a COPY of crew_list with the following fields stamped on every
## crew dict:
##   command_hat          : String  — "squadron_leader" | "commander" | ""
##   is_fleet_commander   : bool    — true when a pilot holds BOTH hats
##   command_chain.subordinates : Array[String] — crew_ids of direct reports
##
## Hat semantics:
##   "squadron_leader" — wing lead crew member.
##       subordinates  = wingmen crew_ids.
##   "commander"       — captain of the team's best large ship.
##       subordinates  = wing-lead crew_ids + ship-captain crew_ids on the team
##                       (excluding self).
##   If a team has NO captain, the highest-piloting wing lead also becomes
##   Commander.  Their command_hat stays "squadron_leader" and
##   is_fleet_commander is set true so callers can query both roles cleanly.
##
## Every pass clears stale hats so re-designation is idempotent.
static func designate(crew_list: Array, ships: Array, wings: Array) -> Array:
	# Work on a deep copy — pure function contract.
	var result: Array = _deep_copy_crew(crew_list)

	# Build fast lookup: crew_id -> index in result
	var crew_index: Dictionary = {}
	for i in range(result.size()):
		crew_index[result[i].get("crew_id", "")] = i

	# Clear all hats first so stale data never persists across re-designation.
	for c in result:
		c["command_hat"] = ""
		c["is_fleet_commander"] = false
		# Only clear the wing/fleet subordinates we manage here; preserve any
		# per-ship command_chain subordinates set elsewhere (e.g. gunner→pilot).
		# We overwrite the full list for hatted crew below, so clearing here is
		# safe: non-hatted crew keep empty-after-clear, hatted crew get refilled.
		c["command_chain"]["subordinates"] = []

	# Collect teams present across ships
	var teams: Array = []
	for ship in ships:
		var t: int = ship.get("team", -1)
		if t >= 0 and not teams.has(t):
			teams.append(t)

	for team in teams:
		_designate_team(result, crew_index, ships, wings, team)

	return result


## Designate hats for one team.
static func _designate_team(
		crew: Array, crew_index: Dictionary,
		ships: Array, wings: Array, team: int) -> void:

	# ── Squadron Leader hats ─────────────────────────────────────────────────
	# Each wing lead gets the hat; its subordinates are the wingmen crew_ids.
	var wing_lead_crew_ids: Array = []

	for wing in wings:
		if wing.get("team", -1) != team:
			continue

		var lead_id: String = wing.get("lead_crew_id", "")
		if lead_id == "":
			continue

		var wingmen_ids: Array = []
		for wm in wing.get("wingmen", []):
			var wm_id: String = wm.get("crew_id", "")
			if wm_id != "":
				wingmen_ids.append(wm_id)

		if crew_index.has(lead_id):
			var c = crew[crew_index[lead_id]]
			c["command_hat"] = "squadron_leader"
			c["command_chain"]["subordinates"] = wingmen_ids.duplicate()

		wing_lead_crew_ids.append(lead_id)

	# ── Commander hat ────────────────────────────────────────────────────────
	# Find the captain of the team's best ship (highest class rank, tie-break
	# by hull integrity).  If no captain exists, the best wing lead doubles up.

	var team_ships: Array = ships.filter(func(s): return s.get("team", -1) == team)
	var flagship: Dictionary = best_ship(ships, team)

	# Collect captain crew_ids on this team (for Commander's subordinate list).
	var captain_crew_ids: Array = []
	for c in crew:
		if c.get("assigned_to", "") == "":
			continue
		# Check this crew member is on a team ship
		var c_ship: Dictionary = _ship_by_id(c.get("assigned_to", ""), team_ships)
		if c_ship.is_empty():
			continue
		if c.get("role", -1) == CrewData.Role.CAPTAIN:
			captain_crew_ids.append(c.get("crew_id", ""))

	# Commander subordinates = wing leads + captains, excluding self.
	# We'll splice out self once we know who becomes Commander.
	var commander_crew_id: String = ""
	var is_pilot_commander: bool = false

	if not flagship.is_empty():
		# Find the captain assigned to the flagship.
		for c in crew:
			if c.get("assigned_to", "") == flagship.get("ship_id", "") \
					and c.get("role", -1) == CrewData.Role.CAPTAIN:
				commander_crew_id = c.get("crew_id", "")
				break

	if commander_crew_id == "" and not wing_lead_crew_ids.is_empty():
		# All-fighter team: promote the highest-piloting wing lead.
		# WingFormationSystem already sorted by piloting descending, so the
		# first wing lead in formation order is the best pilot.
		commander_crew_id = _highest_piloting_among(wing_lead_crew_ids, crew)
		is_pilot_commander = true

	if commander_crew_id != "" and crew_index.has(commander_crew_id):
		var c = crew[crew_index[commander_crew_id]]

		# Build subordinate list: wing leads + captains, minus self.
		var sub_ids: Array = []
		for id in wing_lead_crew_ids:
			if id != commander_crew_id:
				sub_ids.append(id)
		for id in captain_crew_ids:
			if id != commander_crew_id and not sub_ids.has(id):
				sub_ids.append(id)

		if is_pilot_commander:
			# Pilot holds both hats: command_hat stays "squadron_leader",
			# is_fleet_commander flags the dual role.  Subordinates for the
			# fleet-commander role are merged into command_chain.subordinates
			# (wingmen already set above, add the rest).
			c["is_fleet_commander"] = true
			# Merge fleet subordinates without duplicating wingmen.
			var existing: Array = c["command_chain"]["subordinates"].duplicate()
			for id in sub_ids:
				if not existing.has(id):
					existing.append(id)
			c["command_chain"]["subordinates"] = existing
		else:
			c["command_hat"] = "commander"
			c["command_chain"]["subordinates"] = sub_ids


## Return the best ship for a team: highest HULL_CLASS_RANK, tie-break by
## total current_armor (hull integrity proxy).  Returns {} if no ships found.
static func best_ship(ships: Array, team: int) -> Dictionary:
	var best: Dictionary = {}
	var best_rank: int = -1
	var best_integrity: float = -1.0

	for ship in ships:
		if ship.get("team", -1) != team:
			continue
		if ship.get("status", "operational") != "operational":
			continue

		var rank: int = HULL_CLASS_RANK.get(ship.get("type", ""), 0)
		var integrity: float = _ship_integrity(ship)

		if rank > best_rank or (rank == best_rank and integrity > best_integrity):
			best = ship
			best_rank = rank
			best_integrity = integrity

	return best


# ── Private helpers ──────────────────────────────────────────────────────────

## Sum of current_armor across all armor sections — used as an integrity proxy
## for tie-breaking.  Ships with no armor sections return 0.0.
static func _ship_integrity(ship: Dictionary) -> float:
	var total: float = 0.0
	for section in ship.get("armor_sections", []):
		total += float(section.get("current_armor", 0))
	return total


## Return the crew_id with the highest piloting skill among a list of ids.
static func _highest_piloting_among(crew_ids: Array, crew: Array) -> String:
	var best_id: String = ""
	var best_skill: float = -1.0
	for c in crew:
		var id: String = c.get("crew_id", "")
		if not crew_ids.has(id):
			continue
		var skill: float = c.get("stats", {}).get("skills", {}).get("piloting", 0.0)
		if skill > best_skill:
			best_skill = skill
			best_id = id
	return best_id


## Find a ship in a pre-filtered list by ship_id.
static func _ship_by_id(ship_id: String, ships: Array) -> Dictionary:
	for s in ships:
		if s.get("ship_id", "") == ship_id:
			return s
	return {}


## Shallow-copy each crew dict (one level deep) so mutations don't bleed back
## to the caller's list.  Nested Dictionaries that CommandDesignation writes
## (command_chain) are duplicated explicitly.
static func _deep_copy_crew(crew_list: Array) -> Array:
	var out: Array = []
	for c in crew_list:
		var copy: Dictionary = c.duplicate(false)
		# Duplicate command_chain so we can mutate subordinates safely.
		if copy.has("command_chain"):
			copy["command_chain"] = copy["command_chain"].duplicate(true)
		out.append(copy)
	return out
