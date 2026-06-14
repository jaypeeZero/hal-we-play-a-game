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


## Crew pool in a run is the hire roster (entries not yet consumed), rendered as
## crew dicts so the Fleet Command pool shows role/skills and drag works. Each
## member's crew_id carries its roster id; dragging onto a vacancy hires them
## (see assign / can_assign below).
func crew_pool() -> Array:
	var pool: Array = []
	for entry in RoguelikeRun.available_crew():
		var member := CrewData.from_roster_entry(entry)
		member["crew_id"] = str(entry.get("id", ""))
		pool.append(member)
	return pool


## Add a bare hull of ship_type to the run fleet (no crew aboard — use assign to staff it).
func add_ship(ship_type: String) -> void:
	RoguelikeRun.add_purchased_hull(ship_type)


## Remove a hull from the run, dismissing all aboard crew.
func remove_ship(hull_id: String) -> void:
	RoguelikeRun.dismiss_hull(hull_id)


## Whether the dragged crew can land on hull_id: a pool candidate hires into a
## matching vacancy; an owned crew member transfers.
func can_assign(crew_id: String, hull_id: String) -> bool:
	if RoguelikeRun.is_pool_candidate(crew_id):
		return RoguelikeRun.can_hire_to_hull(crew_id, hull_id)
	return RoguelikeRun.can_transfer(crew_id, hull_id)


## Land the dragged crew on hull_id: hire a pool candidate, or transfer an
## owned crew member to the matching vacancy.
func assign(crew_id: String, hull_id: String) -> void:
	if RoguelikeRun.is_pool_candidate(crew_id):
		RoguelikeRun.hire_to_hull(crew_id, hull_id)
	else:
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


## Set the fleet-wide combat-tactics preset id on the live run state.
## Stored on RoguelikeRun.tactics["preset"], which round-trips with the campaign save.
func set_fleet_preset(preset_id: String) -> void:
	RoguelikeRun.tactics["preset"] = preset_id


## The fleet-wide combat-tactics preset id for the active run.
func get_fleet_preset() -> String:
	return str(RoguelikeRun.tactics.get("preset", ""))


## Mark a hull's manual command hat ("" | "squadron_leader" | "commander").
func set_command_role(hull_id: String, role: String) -> void:
	var hull: Dictionary = RoguelikeRun.hull_by_id(hull_id)
	if hull.is_empty():
		push_error("RunSource.set_command_role: hull not found: %s" % hull_id)
		return
	hull["command_role"] = role


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
