class_name SquadronSystem
extends RefCounted

## Pure functional squadron management. All mutation functions return new
## arrays rather than modifying their inputs.


## Return the squadron containing hull_id, or {} if none.
static func get_squadron_for_hull(squadrons: Array, hull_id: String) -> Dictionary:
	for sq in squadrons:
		if hull_id in sq.get("hull_ids", []):
			return sq
	return {}


## Return {mission, params} for hull_id, or {mission: FREE, params: {}} if unassigned.
static func get_mission(squadrons: Array, hull_id: String) -> Dictionary:
	var sq: Dictionary = get_squadron_for_hull(squadrons, hull_id)
	if sq.is_empty():
		return {"mission": SquadronData.Mission.FREE, "params": {}}
	return {"mission": sq.get("mission", SquadronData.Mission.FREE), "params": sq.get("mission_params", {})}


## Return hull_ids that appear in no squadron.
static func unassigned_hulls(squadrons: Array, all_hull_ids: Array) -> Array:
	var assigned: Dictionary = {}
	for sq in squadrons:
		for hid in sq.get("hull_ids", []):
			assigned[hid] = true
	var result: Array = []
	for hid in all_hull_ids:
		if not assigned.has(hid):
			result.append(hid)
	return result


## Add hull_id to squadron_id, removing it from any other squadron first.
static func add_hull(squadrons: Array, squadron_id: String, hull_id: String) -> Array:
	var without: Array = remove_hull(squadrons, hull_id)
	var result: Array = []
	for sq in without:
		if sq.get("squadron_id", "") == squadron_id:
			var updated: Dictionary = sq.duplicate(true)
			if hull_id not in updated["hull_ids"]:
				updated["hull_ids"].append(hull_id)
			result.append(updated)
		else:
			result.append(sq)
	return result


## Remove hull_id from whichever squadron contains it.
static func remove_hull(squadrons: Array, hull_id: String) -> Array:
	var result: Array = []
	for sq in squadrons:
		if hull_id in sq.get("hull_ids", []):
			var updated: Dictionary = sq.duplicate(true)
			updated["hull_ids"] = updated["hull_ids"].filter(func(h): return h != hull_id)
			result.append(updated)
		else:
			result.append(sq)
	return result


## Set mission and params for a squadron.
static func set_mission(squadrons: Array, squadron_id: String, mission: String, params: Dictionary) -> Array:
	var result: Array = []
	for sq in squadrons:
		if sq.get("squadron_id", "") == squadron_id:
			var updated: Dictionary = sq.duplicate(true)
			updated["mission"] = mission
			updated["mission_params"] = params.duplicate(true)
			result.append(updated)
		else:
			result.append(sq)
	return result


## Rename a squadron.
static func rename_squadron(squadrons: Array, squadron_id: String, new_name: String) -> Array:
	var result: Array = []
	for sq in squadrons:
		if sq.get("squadron_id", "") == squadron_id:
			var updated: Dictionary = sq.duplicate(true)
			updated["name"] = new_name
			result.append(updated)
		else:
			result.append(sq)
	return result


## Append a new squadron with the given name.
static func create_squadron(squadrons: Array, name: String) -> Array:
	var result: Array = squadrons.duplicate(true)
	result.append(SquadronData.create(name))
	return result


## Remove a squadron by id (hull assignments are dropped).
static func delete_squadron(squadrons: Array, squadron_id: String) -> Array:
	return squadrons.filter(func(sq): return sq.get("squadron_id", "") != squadron_id)


## Remove lost hull_ids from all squadrons, then delete any now-empty squadrons.
static func prune_for_roster(squadrons: Array, lost_hull_ids: Array) -> Array:
	if lost_hull_ids.is_empty():
		return squadrons.duplicate(true)
	var pruned: Array = []
	for sq in squadrons:
		var updated: Dictionary = sq.duplicate(true)
		updated["hull_ids"] = updated["hull_ids"].filter(
			func(hid): return hid not in lost_hull_ids
		)
		if not updated["hull_ids"].is_empty():
			pruned.append(updated)
	return pruned


## Build one squadron per ship_type from fleet_hulls, assigning every hull.
static func default_squadrons_for_fleet(fleet_hulls: Array) -> Array:
	var by_type: Dictionary = {}
	for hull in fleet_hulls:
		var ship_type: String = hull.get("ship_type", "unknown")
		if not by_type.has(ship_type):
			by_type[ship_type] = []
		by_type[ship_type].append(hull.get("hull_id", ""))

	var result: Array = []
	for ship_type in by_type:
		var sq: Dictionary = SquadronData.create(ship_type.capitalize() + " Squadron")
		sq["hull_ids"] = by_type[ship_type].duplicate()
		result.append(sq)
	return result
