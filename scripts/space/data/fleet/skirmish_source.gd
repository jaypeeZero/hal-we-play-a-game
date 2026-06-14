class_name SkirmishSource
extends FleetSource

## FleetSource implementation over a working copy of a SkirmishFleet.
## Loads ships for the given team at construction; all ops mutate the in-memory
## list. commit() persists via SkirmishFleet.save_fleet().
##
## Crew pool: crew not currently assigned to any ship in the fleet.
## Populated from SkirmishFleet.best_pool() minus assigned crew at load time.
## assign/unassign/swap keep pool and ship crew arrays in sync.

var _team: int
var _ships: Array
var _pool: Array  # Array of crew dicts (same shape as ship crew members)
var _fleet_preset: String  # fleet-wide combat-tactics preset id


func _init(team: int) -> void:
	"""Load the fleet for team and build the initial pool of unassigned crew."""
	_team = team
	_ships = SkirmishFleet.get_fleet(team)
	_pool = _build_initial_pool()
	_fleet_preset = SkirmishFleet.get_fleet_preset(team)


## All ships for this team (live in-memory copy).
func ships() -> Array:
	return _ships


## Skirmish has no squadrons yet.
func squadrons() -> Array:
	return []


## Crew available to assign — not currently on any ship.
func crew_pool() -> Array:
	return _pool


## Add one new ship of ship_type to the fleet, crewed from the existing pool.
## The new hull starts crewless; each complement slot is filled by an eligible
## pool member via the same assign() path used for drag-and-drop, so crew come
## from the visible bench, the pool stays in sync, and no one is duplicated.
## Slots with no eligible pool member are left vacant for the player to fill.
func add_ship(ship_type: String) -> void:
	var new_hull: Dictionary = SkirmishFleet.empty_hull(ship_type, _next_hull_index())
	_ships.append(new_hull)
	var hull_id: String = str(new_hull.get("hull_id", ""))
	# Fill one vacancy per complement slot from the pool, while eligible crew exist.
	for _i in range(new_hull.get("complement", []).size()):
		var pick_id: String = ""
		for member in _pool:
			if can_assign(str(member.get("crew_id", "")), hull_id):
				pick_id = str(member.get("crew_id", ""))
				break
		if pick_id.is_empty():
			break
		assign(pick_id, hull_id)


## Remove a ship by hull_id; its crew returns to the pool.
func remove_ship(hull_id: String) -> void:
	var idx: int = _ship_index(hull_id)
	if idx < 0:
		push_error("SkirmishSource.remove_ship: hull not found: %s" % hull_id)
		return
	var hull: Dictionary = _ships[idx]
	for member in hull.get("crew", []):
		_pool.append(member)
	_ships.remove_at(idx)


## Whether crew_id can be assigned to a matching vacancy on hull_id.
func can_assign(crew_id: String, hull_id: String) -> bool:
	var crew: Dictionary = _pool_member(crew_id)
	if crew.is_empty():
		return false
	var hull: Dictionary = _hull(hull_id)
	if hull.is_empty():
		return false
	return CrewFit.can_fill(crew, hull)


## Move crew_id from the pool into the first matching vacant slot on hull_id.
## Rebinds weapon_id for gunner slots. No-op if crew not in pool or no vacancy.
func assign(crew_id: String, hull_id: String) -> void:
	if not can_assign(crew_id, hull_id):
		return
	var crew: Dictionary = _pool_member(crew_id)
	var hull: Dictionary = _hull(hull_id)
	var slot: Dictionary = CrewFit.matching_vacancy(hull, crew)
	if slot.is_empty():
		return
	# Rebind weapon_id if the slot is a gunner slot.
	if int(slot.get("role", -1)) == CrewData.Role.GUNNER and slot.has("weapon_id"):
		crew["weapon_id"] = str(slot["weapon_id"])
	elif crew.has("weapon_id"):
		crew.erase("weapon_id")
	hull.get("crew", []).append(crew)
	_pool.erase(crew)


## Remove crew_id from their current ship and add them back to the pool.
func unassign(crew_id: String) -> void:
	for hull in _ships:
		var crew_arr: Array = hull.get("crew", [])
		for i in range(crew_arr.size()):
			if str(crew_arr[i].get("crew_id", "")) == crew_id:
				var member: Dictionary = crew_arr[i]
				crew_arr.remove_at(i)
				_pool.append(member)
				return
	push_error("SkirmishSource.unassign: crew not found on any ship: %s" % crew_id)


## Swap two crew members between their ships.
## Both must be on ships (not in pool), on different ships, and share the same role.
func swap(crew_id_a: String, crew_id_b: String) -> void:
	var loc_a: Dictionary = _find_on_ship(crew_id_a)
	var loc_b: Dictionary = _find_on_ship(crew_id_b)
	if loc_a.is_empty() or loc_b.is_empty():
		push_error("SkirmishSource.swap: one or both crew not found on any ship")
		return
	var hull_a: Dictionary = loc_a["hull"]
	var member_a: Dictionary = loc_a["member"]
	var hull_b: Dictionary = loc_b["hull"]
	var member_b: Dictionary = loc_b["member"]
	if not CrewFit.can_swap_members(
			member_a, member_b,
			str(hull_a.get("hull_id", "")),
			str(hull_b.get("hull_id", ""))):
		push_error("SkirmishSource.swap: cannot swap %s / %s" % [crew_id_a, crew_id_b])
		return

	# Exchange weapon bindings for gunner slots (mirrors RoguelikeRun.swap_crew).
	if int(member_a.get("role", -1)) == CrewData.Role.GUNNER:
		var wid_a: String = str(member_a.get("weapon_id", ""))
		var wid_b: String = str(member_b.get("weapon_id", ""))
		if wid_b != "":
			member_a["weapon_id"] = wid_b
		elif member_a.has("weapon_id"):
			member_a.erase("weapon_id")
		if wid_a != "":
			member_b["weapon_id"] = wid_a
		elif member_b.has("weapon_id"):
			member_b.erase("weapon_id")

	hull_a.get("crew", []).erase(member_a)
	hull_b.get("crew", []).erase(member_b)
	hull_a.get("crew", []).append(member_b)
	hull_b.get("crew", []).append(member_a)


## Write the tactics dict onto the given hull.
func set_tactics(hull_id: String, tactics: Dictionary) -> void:
	var hull: Dictionary = _hull(hull_id)
	if hull.is_empty():
		push_error("SkirmishSource.set_tactics: hull not found: %s" % hull_id)
		return
	hull["tactics"] = tactics


## Set the fleet-wide combat-tactics preset id (persisted on commit).
func set_fleet_preset(preset_id: String) -> void:
	_fleet_preset = preset_id


## The fleet-wide combat-tactics preset id for this team.
func get_fleet_preset() -> String:
	return _fleet_preset


## Mark a hull's manual command hat ("" | "squadron_leader" | "commander").
func set_command_role(hull_id: String, role: String) -> void:
	var hull: Dictionary = _hull(hull_id)
	if hull.is_empty():
		push_error("SkirmishSource.set_command_role: hull not found: %s" % hull_id)
		return
	hull["command_role"] = role


## Ice or activate a hull in the working copy.
func set_iced(hull_id: String, iced: bool) -> void:
	var hull: Dictionary = _hull(hull_id)
	if hull.is_empty():
		push_error("SkirmishSource.set_iced: hull not found: %s" % hull_id)
		return
	hull["iced"] = iced


## Skirmish has no squadrons; this is a no-op.
func set_squadron_mission(_squadron_id: String, _mission: String, _params: Dictionary) -> void:
	pass


## Persist the in-memory fleet (and fleet preset) back to disk.
func commit() -> void:
	SkirmishFleet.save_fleet(_team, _ships)
	SkirmishFleet.save_fleet_preset(_team, _fleet_preset)


# Internal helpers

## Build the initial pool: best_pool entries not already on any ship.
## Creates crew-member dicts from roster entries using CrewData.
func _build_initial_pool() -> Array:
	# Map callsigns already on ships so we can skip them.
	var assigned_callsigns: Dictionary = {}
	for hull in _ships:
		for member in hull.get("crew", []):
			assigned_callsigns[str(member.get("callsign", ""))] = true

	var pool_entries: Array = SkirmishFleet.best_pool()
	var pool: Array = []
	for entry in pool_entries:
		var callsign: String = str(entry.get("callsign", ""))
		if assigned_callsigns.has(callsign):
			continue
		# Build a crew-member dict from this roster entry (primary role from entry).
		var roles: Array = CrewData.qualified_roles_from_entry(entry)
		var primary_role: int = int(roles[0]) if not roles.is_empty() else CrewData.Role.PILOT
		var member: Dictionary = CrewData.create_crew_member(primary_role, 0.5)
		member = CrewData.apply_roster_entry(member, entry)
		pool.append(member)
	return pool


## The next hull_id index: max existing hull index + 1, ensuring uniqueness.
func _next_hull_index() -> int:
	var max_idx: int = -1
	for hull in _ships:
		var hid: String = str(hull.get("hull_id", ""))
		if hid.begins_with("hull_"):
			var n: int = int(hid.trim_prefix("hull_"))
			if n > max_idx:
				max_idx = n
	return max_idx + 1


## Find a ship by hull_id; returns {} if not found.
func _hull(hull_id: String) -> Dictionary:
	for hull in _ships:
		if str(hull.get("hull_id", "")) == hull_id:
			return hull
	return {}


## Index of a ship by hull_id; returns -1 if not found.
func _ship_index(hull_id: String) -> int:
	for i in range(_ships.size()):
		if str(_ships[i].get("hull_id", "")) == hull_id:
			return i
	return -1


## Find a crew member in the pool by crew_id; returns {} if not found.
func _pool_member(crew_id: String) -> Dictionary:
	for member in _pool:
		if str(member.get("crew_id", "")) == crew_id:
			return member
	return {}


## Find a crew member on any ship; returns {hull, member} or {} if not found.
func _find_on_ship(crew_id: String) -> Dictionary:
	for hull in _ships:
		for member in hull.get("crew", []):
			if str(member.get("crew_id", "")) == crew_id:
				return {"hull": hull, "member": member}
	return {}
