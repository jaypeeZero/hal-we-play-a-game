extends Node

## Holds state for an active Roguelike campaign: the player's persistent
## fleet, the enemy's persistent fleet, and the multi-sector star chart.
## When `active` is true, the battle scene and map scene swap their behavior
## to use this state instead of the on-disk team fleets.

## Star dates: each jump advances the date by the destination node's gap;
## jump repairs scale with the gap (longer downtime, more repair time).
const STAR_DATE_RUN_START = 2300

var active: bool = false
var started_first_battle: bool = false
var fleet: Dictionary = {}
var fleet_ships: Array = []
## The run's crew roster, grouped by the hull type they crew:
## [{"ship_type": String, "crew": Array of crew dicts}]. Created at run
## start so crew are addressable (doctrine, pre-battle UI) before the
## first battle; each battle binds groups to hulls of the same type and
## battle end re-saves the survivors, so crew identity (crew_id,
## callsign, skills, known_patterns) persists across the run.
var fleet_crew: Array = []
## Player standing instructions for this run (see DoctrineSystem).
## Run state: reset at run start, wiped at run end.
var doctrine: Dictionary = DoctrineSystem.empty_doctrine()
var enemy_fleet: Dictionary = {}
## The multi-sector star chart (see CampaignGenerator.generate).
var campaign: Dictionary = {}
var pending_battle_node_id: String = ""
## Battle outcome (CampaignSystem.RESULT_*) stashed by the battle scene
## and consumed by the campaign map's _resolve_pending_battle.
var pending_battle_result: String = ""
## Final state of a wiped fleet (ships and crew groups at the moment of
## defeat), kept so a demotion can roll damaged survivors from it.
var lost_fleet_final_ships: Array = []
var lost_fleet_final_crew: Array = []
var editor_return_scene: String = ""
var current_star_date: int = STAR_DATE_RUN_START
## Last jump's repair summary, kept so the map can report repairs that
## happened on the way into a battle once the player returns to the map.
var last_jump_repair_summary: Dictionary = {}

## Matches the battle scene's team-0 crew skill.
const ROSTER_SKILL_LEVEL := 1.0

## Monotonic source of unique callsigns for the run. Persists across roster
## reconciles so crew added when the fleet grows never reuse a callsign.
var _callsign_counter: int = 0


func start_run(initial_fleet: Dictionary) -> void:
	active = true
	started_first_battle = false
	fleet = initial_fleet.duplicate(true)
	fleet_ships = []
	_callsign_counter = 0
	fleet_crew = _create_fleet_roster(fleet)
	doctrine = DoctrineSystem.empty_doctrine()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	campaign = CampaignGenerator.generate(rng)
	enemy_fleet = CampaignSystem.scaled_enemy_fleet(
		FleetDataManager.load_fleet(1), campaign["current_sector"])
	pending_battle_node_id = ""
	pending_battle_result = ""
	lost_fleet_final_ships = []
	lost_fleet_final_crew = []
	current_star_date = STAR_DATE_RUN_START
	last_jump_repair_summary = {}


func end_run() -> void:
	active = false
	started_first_battle = false
	fleet = {}
	fleet_ships = []
	fleet_crew = []
	doctrine = DoctrineSystem.empty_doctrine()
	enemy_fleet = {}
	campaign = {}
	pending_battle_node_id = ""
	pending_battle_result = ""
	lost_fleet_final_ships = []
	lost_fleet_final_crew = []
	current_star_date = STAR_DATE_RUN_START
	last_jump_repair_summary = {}
	_callsign_counter = 0


func _create_fleet_roster(fleet_counts: Dictionary) -> Array:
	var roster: Array = []
	for ship_type in FleetDataManager.SHIP_TYPES:
		for _i in range(int(fleet_counts.get(ship_type, 0))):
			roster.append(_make_crew_group(ship_type))
	return roster


## Create one crew group (a hull's worth of crew) for a ship type, drawing
## unique callsigns from the run's monotonic counter. Shared by initial
## roster creation and reconcile so both produce identical crew.
func _make_crew_group(ship_type: String) -> Dictionary:
	var weapon_count: int = ShipData.get_ship_template(ship_type).get("weapons", []).size()
	var crew: Array = CrewData.create_crew_for_ship_type(ship_type, weapon_count, ROSTER_SKILL_LEVEL)
	for member in crew:
		member.callsign = CrewData.callsign_for_index(_callsign_counter)
		_callsign_counter += 1
	return {"ship_type": ship_type, "crew": crew}


## Rebuild the crew roster to match new fleet counts while preserving the
## identity (crew_id, callsign, skills, known_patterns) of crew on ships
## that remain. Existing groups of each type are kept in order up to the
## new count; surplus counts spawn fresh groups, shortfalls drop trailing
## groups. Doctrine is reconciled: per-crew and disabled entries for
## dropped crew are purged and class doctrine for types reduced to zero is
## removed; fleet doctrine is untouched. Used by the Edit Fleet screen so
## fleet edits mid-setup keep the doctrine already authored for survivors.
func reconcile_roster_to_counts(new_counts: Dictionary) -> void:
	var existing_by_type := {}
	for group in fleet_crew:
		var t: String = group.get("ship_type", "")
		if not existing_by_type.has(t):
			existing_by_type[t] = []
		existing_by_type[t].append(group)

	var new_roster: Array = []
	var dropped_crew_ids: Array = []
	for ship_type in FleetDataManager.SHIP_TYPES:
		var desired: int = int(new_counts.get(ship_type, 0))
		var existing: Array = existing_by_type.get(ship_type, [])
		for i in range(desired):
			if i < existing.size():
				new_roster.append(existing[i])
			else:
				new_roster.append(_make_crew_group(ship_type))
		for i in range(desired, existing.size()):
			for member in existing[i].get("crew", []):
				dropped_crew_ids.append(member.get("crew_id", ""))

	fleet_crew = new_roster
	fleet = {}
	for ship_type in FleetDataManager.SHIP_TYPES:
		fleet[ship_type] = int(new_counts.get(ship_type, 0))

	_prune_doctrine_for_roster(dropped_crew_ids, new_counts)


## Drop doctrine that no longer has a referent after a roster change.
func _prune_doctrine_for_roster(dropped_crew_ids: Array, new_counts: Dictionary) -> void:
	for crew_id in dropped_crew_ids:
		doctrine[DoctrineSystem.SCOPE_CREW].erase(crew_id)
		doctrine["disabled"].erase(crew_id)
	for ship_type in FleetDataManager.SHIP_TYPES:
		if int(new_counts.get(ship_type, 0)) == 0:
			doctrine[DoctrineSystem.SCOPE_CLASS].erase(ship_type)


func update_fleet_after_battle(surviving_ships: Array, surviving_crew: Array = []) -> void:
	fleet_ships = surviving_ships.duplicate(true)
	fleet_crew = surviving_crew.duplicate(true)
	fleet = {}
	for ship_type in FleetDataManager.SHIP_TYPES:
		fleet[ship_type] = 0
	for ship in fleet_ships:
		var t: String = ship.get("type", "")
		if fleet.has(t):
			fleet[t] += 1


## Take the saved crew group for a hull of this type (first match wins,
## mirroring how _apply_roguelike_damage_states matches ships by type).
## Empty array if no saved crew remain for the type.
func take_saved_crew(ship_type: String) -> Array:
	for i in range(fleet_crew.size()):
		if fleet_crew[i].get("ship_type", "") == ship_type:
			var group: Dictionary = fleet_crew.pop_at(i)
			return group.get("crew", [])
	return []


func is_fleet_empty() -> bool:
	return fleet_ships.is_empty()


## Repair the fleet during a jump. Engineers use the downtime: each heals
## their ship by REPAIR_FRACTION_PER_STAR_DATE × machinery skill × date gap
## (× RNR_REPAIR_MULTIPLIER when the destination is an R&R stop).
## Returns {ships_repaired, points_repaired, date_delta}.
func apply_jump_repairs(destination_star_date: int, is_rnr: bool) -> Dictionary:
	var date_delta: int = maxi(0, destination_star_date - current_star_date)
	current_star_date = destination_star_date

	var fraction: float = WingConstants.REPAIR_FRACTION_PER_STAR_DATE * date_delta
	if is_rnr:
		fraction *= WingConstants.RNR_REPAIR_MULTIPLIER

	var ships_repaired := 0
	var points_repaired := 0
	for i in fleet_ships.size():
		var before := _ship_health_total(fleet_ships[i])
		var repaired: Dictionary = RepairSystem.apply_engineer_repairs(fleet_ships[i], fraction)
		var healed := _ship_health_total(repaired) - before
		if healed > 0:
			ships_repaired += 1
			points_repaired += healed
		fleet_ships[i] = repaired

	last_jump_repair_summary = {
		"ships_repaired": ships_repaired,
		"points_repaired": points_repaired,
		"date_delta": date_delta,
	}
	return last_jump_repair_summary


func _ship_health_total(ship: Dictionary) -> int:
	return DamageResolver.calculate_total_armor(ship) + DamageResolver.calculate_total_internal_health(ship)


## Record a battle's outcome for the campaign map to resolve. Victory
## keeps the surviving ships and crews; defeat stashes the wiped fleet's
## final state so a demotion can roll damaged survivors from it. Crew
## groups are derived from the live crew the battle scene attaches to
## each ship dict.
func record_battle_result(result: String, final_ships: Array) -> void:
	pending_battle_result = result
	if result == CampaignSystem.RESULT_VICTORY:
		var survivors: Array = final_ships.filter(
			func(ship): return ship.get("status", "") != "destroyed")
		update_fleet_after_battle(survivors, _crew_groups_for_ships(survivors))
		lost_fleet_final_ships = []
		lost_fleet_final_crew = []
	else:
		lost_fleet_final_ships = final_ships.duplicate(true)
		lost_fleet_final_crew = _crew_groups_for_ships(final_ships)
		fleet_ships = []


## Crew groups (fleet_crew shape) rebuilt from the crew attached to each
## ship dict.
func _crew_groups_for_ships(ships: Array) -> Array:
	var groups: Array = []
	for ship in ships:
		var members: Array = ship.get("crew", [])
		if not members.is_empty():
			groups.append({"ship_type": ship.get("type", ""), "crew": members.duplicate(true)})
	return groups


## Rebuild the run's fleet for a demotion: the saved fleet config plus the
## rolled survivors of the lost fleet. Fresh hulls spawn undamaged with
## fresh crews (callsigns stay unique via the run's monotonic counter);
## survivor hulls keep their damage and their crews. Doctrine authored for
## crew that did not survive is pruned.
func apply_demotion(survivors: Dictionary, fleet_config: Dictionary) -> void:
	var survivor_ships: Array = survivors.get("ships", [])
	var survivor_crew_groups: Array = survivors.get("crew_groups", [])

	fleet = {}
	for ship_type in FleetDataManager.SHIP_TYPES:
		fleet[ship_type] = int(fleet_config.get(ship_type, 0))
	for ship in survivor_ships:
		var t: String = ship.get("type", "")
		if fleet.has(t):
			fleet[t] += 1

	fleet_ships = survivor_ships.duplicate(true)
	fleet_crew = _create_fleet_roster(fleet_config)
	for group in survivor_crew_groups:
		fleet_crew.append(group.duplicate(true))

	_prune_doctrine_for_roster(_dead_crew_ids(survivor_crew_groups), fleet)
	# The stash is consumed: the demotion is its only reader.
	lost_fleet_final_ships = []
	lost_fleet_final_crew = []


## Crew ids present in the lost fleet's final state but absent from the
## demotion survivors: their doctrine no longer has a referent.
func _dead_crew_ids(survivor_crew_groups: Array) -> Array:
	var survived := {}
	for group in survivor_crew_groups:
		for member in group.get("crew", []):
			survived[member.get("crew_id", "")] = true
	var dead: Array = []
	for group in lost_fleet_final_crew:
		for member in group.get("crew", []):
			var crew_id: String = member.get("crew_id", "")
			if not survived.has(crew_id):
				dead.append(crew_id)
	return dead


func save_campaign_to_disk() -> bool:
	return CampaignSaveManager.save_campaign({
		"campaign": campaign,
		"fleet": fleet,
		"fleet_ships": fleet_ships,
		"fleet_crew": fleet_crew,
		"doctrine": doctrine,
		"enemy_fleet": enemy_fleet,
		"current_star_date": current_star_date,
		"callsign_counter": _callsign_counter,
	})


## Resume a saved campaign. Returns false (leaving the run untouched)
## when no usable save exists.
func load_campaign_from_disk() -> bool:
	var data := CampaignSaveManager.load_campaign()
	if data.is_empty():
		return false
	campaign = data.get("campaign", {})
	fleet = data.get("fleet", {})
	fleet_ships = data.get("fleet_ships", [])
	fleet_crew = data.get("fleet_crew", [])
	doctrine = data.get("doctrine", DoctrineSystem.empty_doctrine())
	enemy_fleet = data.get("enemy_fleet", {})
	current_star_date = data.get("current_star_date", STAR_DATE_RUN_START)
	_callsign_counter = data.get("callsign_counter", 0)
	pending_battle_node_id = ""
	pending_battle_result = ""
	lost_fleet_final_ships = []
	lost_fleet_final_crew = []
	last_jump_repair_summary = {}
	started_first_battle = not fleet_ships.is_empty()
	active = true
	return true
