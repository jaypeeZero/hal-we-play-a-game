class_name FleetSource
extends RefCounted

## Abstract base for fleet data sources. Two implementations exist:
## RunSource (wraps RoguelikeRun) and SkirmishSource (wraps SkirmishFleet).
## All methods push_error when called on the base class — override in subclasses.


## All ships in the fleet as unified ship records
## ({hull_id, ship_type, name, crew[], complement[], tactics{}, iced, ship{}}).
func ships() -> Array:
	push_error("FleetSource.ships() not implemented")
	return []


## Squadron groupings ({squadron_id, name, hull_ids, mission, ...}).
## May return an empty array for sources without squadron support (e.g. skirmish).
func squadrons() -> Array:
	push_error("FleetSource.squadrons() not implemented")
	return []


## Crew available to assign — not currently serving on any ship.
func crew_pool() -> Array:
	push_error("FleetSource.crew_pool() not implemented")
	return []


## Add a new ship of the given type to the fleet.
func add_ship(ship_type: String) -> void:
	push_error("FleetSource.add_ship() not implemented for type: %s" % ship_type)


## Remove a ship by hull_id; its crew returns to the pool.
func remove_ship(hull_id: String) -> void:
	push_error("FleetSource.remove_ship() not implemented for hull: %s" % hull_id)


## Whether crew_id can be assigned to a vacant slot on hull_id.
func can_assign(crew_id: String, hull_id: String) -> bool:
	push_error("FleetSource.can_assign() not implemented")
	return false


## Assign crew_id to a matching vacant slot on hull_id.
func assign(crew_id: String, hull_id: String) -> void:
	push_error("FleetSource.assign() not implemented crew=%s hull=%s" % [crew_id, hull_id])


## Remove crew_id from their current ship; they return to the pool.
func unassign(crew_id: String) -> void:
	push_error("FleetSource.unassign() not implemented for crew: %s" % crew_id)


## Swap two crew members between their respective ships (same-role constraint).
func swap(crew_id_a: String, crew_id_b: String) -> void:
	push_error("FleetSource.swap() not implemented for %s / %s" % [crew_id_a, crew_id_b])


## Set the per-ship tactics dict for a given hull.
func set_tactics(hull_id: String, tactics: Dictionary) -> void:
	push_error("FleetSource.set_tactics() not implemented for hull: %s" % hull_id)


## Set the mission for a squadron (roguelite only; no-op on sources that lack squadrons).
func set_squadron_mission(squadron_id: String, mission: String, params: Dictionary) -> void:
	push_error("FleetSource.set_squadron_mission() not implemented squad=%s mission=%s" % [squadron_id, mission])


## Ice or activate a hull (benched vs. sortieable).
func set_iced(hull_id: String, iced: bool) -> void:
	push_error("FleetSource.set_iced() not implemented hull=%s iced=%s" % [hull_id, str(iced)])


## Persist all in-memory changes (save to disk or update RoguelikeRun state).
func commit() -> void:
	push_error("FleetSource.commit() not implemented")
