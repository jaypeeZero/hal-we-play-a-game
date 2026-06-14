class_name RunSource
extends FleetSource

## FleetSource adapter over RoguelikeRun. Delegates all crew ops to the
## existing RoguelikeRun public API — this is a thin adapter, not a reimplementation.
## commit() is a no-op: RoguelikeRun is the live source of truth for the run.
##
## RoguelikeRun methods used:
##   fleet_hulls          (Array — the ship records)
##   squadrons            (Array — squadron groupings)
##   hull_by_id(id)       -> Dictionary
##   hull_vacancies(hull) -> Array
##   can_transfer(crew_id, hull_id) -> bool
##   transfer_crew(crew_id, hull_id) -> bool
##   can_swap(crew_id_a, crew_id_b) -> bool
##   swap_crew(crew_id_a, crew_id_b) -> bool
##   add_purchased_hull(ship_type) -> Dictionary  (used for add_ship)
##   dismiss_hull(hull_id)                        (used for remove_ship)
##   dismiss_crew(crew_id)                        (used for unassign — removes from hull)
##   fill_vacancy(hull_id, slot, roster_id)       (used by hire_crew path, not directly here)
##   set_hull_iced(hull_id, iced)


## All player fleet hulls from the active run.
func ships() -> Array:
	return RoguelikeRun.fleet_hulls


## Squadron groupings for this run.
func squadrons() -> Array:
	return RoguelikeRun.squadrons


## Crew pool in a run is the entire available roster minus already-hired ids.
## Returns roster entries not yet consumed this run (same pool the shop shows).
func crew_pool() -> Array:
	return CrewRosterManager.available_entries(RoguelikeRun.hired_roster_ids, -1)


## Add a bare hull of ship_type to the run fleet (no crew aboard — use assign to staff it).
func add_ship(ship_type: String) -> void:
	RoguelikeRun.add_purchased_hull(ship_type)


## Remove a hull from the run, dismissing all aboard crew.
func remove_ship(hull_id: String) -> void:
	RoguelikeRun.dismiss_hull(hull_id)


## Whether crew_id can move to a matching vacancy on hull_id.
func can_assign(crew_id: String, hull_id: String) -> bool:
	return RoguelikeRun.can_transfer(crew_id, hull_id)


## Move crew_id to the matching vacancy on hull_id.
func assign(crew_id: String, hull_id: String) -> void:
	RoguelikeRun.transfer_crew(crew_id, hull_id)


## Remove crew_id from their hull. In the run context, dismissing a crew member
## opens their vacancy (they leave the run). There is no free-floating crew pool
## in a run — unassigned crew are dismissed back to the roster.
func unassign(crew_id: String) -> void:
	RoguelikeRun.dismiss_crew(crew_id)


## Swap two crew members between their ships (same-role rule enforced by RoguelikeRun).
func swap(crew_id_a: String, crew_id_b: String) -> void:
	RoguelikeRun.swap_crew(crew_id_a, crew_id_b)


## Write per-ship tactics onto the hull record.
func set_tactics(hull_id: String, tactics: Dictionary) -> void:
	var hull: Dictionary = RoguelikeRun.hull_by_id(hull_id)
	if hull.is_empty():
		push_error("RunSource.set_tactics: hull not found: %s" % hull_id)
		return
	hull["tactics"] = tactics


## Ice or activate a hull via RoguelikeRun.
func set_iced(hull_id: String, iced: bool) -> void:
	RoguelikeRun.set_hull_iced(hull_id, iced)


## Set the mission for a squadron, delegating to SquadronSystem.
func set_squadron_mission(squadron_id: String, mission: String, params: Dictionary) -> void:
	RoguelikeRun.squadrons = SquadronSystem.set_mission(
		RoguelikeRun.squadrons, squadron_id, mission, params)


## No-op: RoguelikeRun is the live in-memory state; changes are immediate.
## The caller should invoke RoguelikeRun.save_campaign_to_disk() explicitly if persistence is needed.
func commit() -> void:
	pass
