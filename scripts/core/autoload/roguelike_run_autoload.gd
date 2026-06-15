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
## Count of battles fought this run. Drives event `requires.min_battles`
## (late-run events gate on a real count, not just "≥1 battle"). Persisted.
var battles_fought: int = 0
## The player fleet as per-hull records, each with a stable identity:
## {
##   "hull_id": String,          # stable for the run
##   "ship_type": String,
##   "iced": bool,               # mothballed: never sorties, no per-battle ship cost
##   "crew": Array,              # crew dicts; may be empty (purchased hull) or partial
##   "complement": Array,        # fixed standard crew slots [{role, weapon_id?}, ...]
##   "ship": Dictionary,         # persisted damage state, crew stripped; {} = pristine
## }
## Per-hull identity lets ships be moved, iced, lost, or purchased without the
## old type+order matching: survivors carry their hull_id back from battle.
var fleet_hulls: Array = []
## Player standing instructions for this run (see DoctrineSystem).
## Run state: reset at run start, wiped at run end.
var doctrine: Dictionary = DoctrineSystem.empty_doctrine()
## Player combat tactics for this run (see TacticsSystem).
## Holds the selected fleet preset id ({"preset": ...}); per-hull role/overrides
## live on each hull and are resolved at spawn by compile_player_tactics().
## Defaults to empty preset so resolution yields balanced engine defaults.
## Run state: reset at run start, wiped at run end.
var tactics: Dictionary = TacticsSystem.empty_tactics()
## The enemy fleet for the next/pending battle, set from the destination node
## when a battle is launched (the campaign map sets it). Empty until a battle node is selected.
var enemy_fleet: Dictionary = {}
## The multi-sector star chart (see CampaignGenerator.generate).
var campaign: Dictionary = {}
## Run economy: credits on hand, spent on ships/upkeep/insurance and earned
## from battle rewards (see EconomySystem). Rolled at run start.
var money: int = 0
## Summary of the most recent battle's economy (reward, insurance, casualties),
## kept so the map can report it once the player returns. Wiped after display.
var last_battle_summary: Dictionary = {}
var pending_battle_node_id: String = ""
## Battle outcome (CampaignSystem.RESULT_*) stashed by the battle scene
## and consumed by the campaign map's _resolve_pending_battle.
var pending_battle_result: String = ""
## True when the last recorded battle had at least one ship flee the field.
## Read by the campaign map to route a defeat-with-flee to a regroup-in-place
## instead of a total loss. Consumed by _resolve_pending_battle.
var pending_battle_fled: bool = false
## Final state of a wiped fleet (ships and crew groups at the moment of
## defeat), stashed for the post-battle summary.
var lost_fleet_final_ships: Array = []
var lost_fleet_final_crew: Array = []
var editor_return_scene: String = ""
var current_star_date: int = STAR_DATE_RUN_START
## Last jump's repair summary, kept so the map can report repairs that
## happened on the way into a battle once the player returns to the map.
var last_jump_repair_summary: Dictionary = {}
## Player-defined squadrons for this run (see SquadronSystem / SquadronData).
var squadrons: Array = []
## Per-crew skill-growth report from the most recent battle, for the post-battle
## overview. Transient display data — never saved, reset in start_run/end_run/load.
var last_battle_progression: Array = []

## Skill for throwaway template crews that only derive a hull's standard
## complement (slot roles + weapon bindings); template members are never
## fielded, so the value is irrelevant.
const COMPLEMENT_TEMPLATE_SKILL := 0.5

## Roster entry ids consumed from the hiring pool this run — by run-start
## crews and shop hires alike. Consumed ids never return
## to the pool, even when the crew member dies or is dismissed. Reset when a
## run starts or ends; persisted with the campaign save.
var hired_roster_ids: Array = []
## Generated roster entries for THIS run; the live hiring pool while a run
## is active. Replaces the static shipped roster as the hiring source.
## Generated at run start, persisted in the campaign save, cleared at run end.
var run_roster: Array = []
## Monotonic source of unique hull ids for the run.
var _next_hull_id: int = 0
## Resolved event records for the current run, newest first.
## Capped at WingConstants.NEWS_FEED_MAX_ENTRIES. Persisted with the save.
var news_feed: Array = []
## Active temp effects to be folded in at battle start.
## Each record: {kind, target:{kind,...}, field/skill/scope, value,
## expires_after_battles}. Decremented by EventSystem.tick_battle_effects
## after each battle. Persisted with the save.
var active_effects: Array = []


func start_run(initial_fleet: Dictionary) -> void:
	active = true
	started_first_battle = false
	battles_fought = 0
	hired_roster_ids = []
	_next_hull_id = 0
	run_roster = CrewGenerator.generate_run_roster(
		CrewRosterManager.load_roster(), WingConstants.RUN_ROSTER_SIZE, _new_rng())
	fleet_hulls = _create_fleet_roster(initial_fleet)
	doctrine = DoctrineSystem.empty_doctrine()
	tactics = TacticsSystem.empty_tactics()
	campaign = CampaignGenerator.generate(_new_rng())
	enemy_fleet = {}
	money = EconomySystem.roll_starting_money(fleet_hulls, _new_rng())
	last_battle_summary = {}
	pending_battle_node_id = ""
	pending_battle_result = ""
	pending_battle_fled = false
	lost_fleet_final_ships = []
	lost_fleet_final_crew = []
	current_star_date = STAR_DATE_RUN_START
	last_jump_repair_summary = {}
	squadrons = []
	last_battle_progression = []
	news_feed = []
	active_effects = []


func end_run() -> void:
	active = false
	started_first_battle = false
	battles_fought = 0
	fleet_hulls = []
	doctrine = DoctrineSystem.empty_doctrine()
	tactics = TacticsSystem.empty_tactics()
	enemy_fleet = {}
	campaign = {}
	money = 0
	last_battle_summary = {}
	pending_battle_node_id = ""
	pending_battle_result = ""
	pending_battle_fled = false
	lost_fleet_final_ships = []
	lost_fleet_final_crew = []
	current_star_date = STAR_DATE_RUN_START
	last_jump_repair_summary = {}
	squadrons = []
	hired_roster_ids = []
	run_roster = []
	_next_hull_id = 0
	last_battle_progression = []
	news_feed = []
	active_effects = []


## The live hiring pool for this run: run_roster entries not yet consumed,
## optionally filtered to candidates qualified for one role.
## Mirrors CrewRosterManager.available_entries; use this during an active run.
func available_crew(role: int = -1) -> Array:
	var role_name: String = CrewData.role_to_name(role) if role >= 0 else ""
	var available: Array = []
	for entry in run_roster:
		if hired_roster_ids.has(entry.id):
			continue
		if role_name != "" and not entry.roles.has(role_name):
			continue
		available.append(entry)
	return available


## Every crew member currently serving aboard the fleet, flattened across all
## hulls. The read-only view of who has been hired/crewed this run.
func fielded_crew() -> Array:
	var crew: Array = []
	for hull in fleet_hulls:
		for member in hull.get("crew", []):
			crew.append(member)
	return crew


## The fleet assignment of crew member `crew_id`: {hull_id, ship_type, role}
## when serving aboard a hull, or {} when not aboard any ship. `role` is the
## serving-role int (the position held on that ship).
func assignment_of(crew_id: String) -> Dictionary:
	for hull in fleet_hulls:
		for member in hull.get("crew", []):
			if str(member.get("crew_id", "")) == crew_id:
				return {
					"hull_id": str(hull.get("hull_id", "")),
					"ship_type": str(hull.get("ship_type", "")),
					"role": int(member.get("role", -1)),
				}
	return {}


## Find one run-roster entry by id; falls back to CrewRosterManager so
## legacy or empty-roster saves still resolve.
func crew_entry_by_id(roster_id: String) -> Dictionary:
	for entry in run_roster:
		if entry.id == roster_id:
			return entry
	return CrewRosterManager.entry_by_id(roster_id)


## True when `id` names an unhired hire candidate in this run's pool (vs an
## owned crew member's crew_id). Lets the Fleet Command pool tell hire from
## transfer when crew are dragged onto a hull.
func is_pool_candidate(id: String) -> bool:
	if hired_roster_ids.has(id):
		return false
	for entry in run_roster:
		if str(entry.get("id", "")) == id:
			return true
	return false


## Whether pool candidate `roster_id` could be hired onto `dest_hull_id` —
## i.e. the hull has a vacant slot for a role the candidate qualifies for.
func can_hire_to_hull(roster_id: String, dest_hull_id: String) -> bool:
	return not _matching_hire_vacancy(roster_id, dest_hull_id).is_empty()


## Hire pool candidate `roster_id` into its first matching vacancy on
## `dest_hull_id`. Returns false when no matching vacancy exists.
func hire_to_hull(roster_id: String, dest_hull_id: String) -> bool:
	var slot := _matching_hire_vacancy(roster_id, dest_hull_id)
	if slot.is_empty():
		return false
	return fill_vacancy(dest_hull_id, slot, roster_id)


## The first vacant slot on `dest_hull_id` whose role the pool candidate
## `roster_id` qualifies for, or {} if none.
func _matching_hire_vacancy(roster_id: String, dest_hull_id: String) -> Dictionary:
	var entry := crew_entry_by_id(roster_id)
	if entry.is_empty():
		return {}
	var hull := hull_by_id(dest_hull_id)
	if hull.is_empty():
		return {}
	var wanted: Array = CrewData.roles_of(entry)
	for slot in hull_vacancies(hull):
		if wanted.has(int(slot.get("role", -1))):
			return slot
	return {}


## A freshly seeded RNG for economy rolls. Centralized so all run-economy
## randomness flows through one place.
func _new_rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng


func _create_fleet_roster(fleet_counts: Dictionary) -> Array:
	var roster: Array = []
	for ship_type in FleetDataManager.SHIP_TYPES:
		for _i in range(int(fleet_counts.get(ship_type, 0))):
			roster.append(_make_hull(ship_type))
	return roster


## Create one hull record for a ship type. With `with_crew`, the complement
## is crewed from the roster hiring pool (slots whose role is exhausted in
## the pool stay vacant); otherwise the hull arrives empty (a purchased bare
## hull). The standard `complement` is always derived so vacancies are known
## even for an empty hull.
func _make_hull(ship_type: String, with_crew := true) -> Dictionary:
	var weapons: Array = ShipData.get_ship_template(ship_type).get("weapons", [])
	var template_crew: Array = CrewData.create_crew_for_ship_type(
		ship_type, weapons.size(), COMPLEMENT_TEMPLATE_SKILL)
	template_crew = CrewData.bind_gunners_to_weapons(template_crew, weapons)
	var complement: Array = _complement_from_crew(template_crew)
	var crew: Array = _crew_from_pool(template_crew) if with_crew else []
	var hull_id := "hull_%d" % _next_hull_id
	_next_hull_id += 1
	return {
		"hull_id": hull_id,
		"ship_type": ship_type,
		"iced": false,
		"crew": crew,
		"complement": complement,
		"ship": {},
	}


## Crew a template complement from the roster hiring pool: each template
## member takes a drawn pool entry's identity and skills while keeping the
## template's structure (crew_id, command chain, weapon binding). Members
## whose role is exhausted in the pool are dropped — their slot stays a
## vacancy for the shop to fill later.
func _crew_from_pool(template_crew: Array) -> Array:
	var rng := _new_rng()
	var crew: Array = []
	for member in template_crew:
		var entry := _draw_from_pool(int(member.get("role", CrewData.Role.PILOT)), rng)
		if entry.is_empty():
			continue
		crew.append(CrewData.apply_roster_entry(member, entry))
	return _prune_command_chains(crew)


## Draw one random available roster entry of `role` and consume it from the
## run's pool. {} when the pool has no one of that role left.
func _draw_from_pool(role: int, rng: RandomNumberGenerator) -> Dictionary:
	var candidates := available_crew(role)
	if candidates.is_empty():
		return {}
	var entry: Dictionary = candidates[rng.randi_range(0, candidates.size() - 1)]
	hired_roster_ids.append(entry.id)
	return entry


## Remove command-chain references to crew that were dropped (pool-exhausted
## slots), so nobody reports to or commands a member who never boarded.
func _prune_command_chains(crew: Array) -> Array:
	var kept := {}
	for member in crew:
		kept[member.crew_id] = true
	for member in crew:
		if member.command_chain.superior != null and not kept.has(member.command_chain.superior):
			member.command_chain.superior = null
		member.command_chain.subordinates = member.command_chain.subordinates.filter(
			func(crew_id): return kept.has(crew_id))
	return crew


## The fixed standard crew slots for a hull, derived from a freshly created
## crew. Drives vacancy detection when hiring or transferring.
func _complement_from_crew(crew: Array) -> Array:
	var complement: Array = []
	for member in crew:
		var slot := {"role": member.get("role", CrewData.Role.PILOT)}
		if member.has("weapon_id"):
			slot["weapon_id"] = member.weapon_id
		complement.append(slot)
	return complement


func hull_by_id(hull_id: String) -> Dictionary:
	for hull in fleet_hulls:
		if hull.get("hull_id", "") == hull_id:
			return hull
	return {}


## A hull sorties when it is not mothballed and has someone to fly it.
func _has_pilot(hull: Dictionary) -> bool:
	for member in hull.get("crew", []):
		if member.get("role", -1) == CrewData.Role.PILOT:
			return true
	return false


## Hulls that take the field this battle: active (not iced) and crewed by a
## pilot. Empty purchased hulls and mothballed hulls stay home.
func sortieable_hulls() -> Array:
	return fleet_hulls.filter(
		func(hull): return not hull.get("iced", false) and _has_pilot(hull))


## Hulls the player likely expects to fight but won't: active (not deliberately
## iced) yet with no pilot to fly them — a Capital whose pilot was dismissed or
## killed, or a bought hull never crewed. Surfaced before launch so a ship is
## never silently left behind.
func benched_hulls() -> Array:
	return fleet_hulls.filter(
		func(hull): return not hull.get("iced", false) and not _has_pilot(hull))


## Fleet composition counts by ship type. With `only_sortieable`, counts only
## the hulls that will actually take the field (drives the battle plan).
func fleet_counts(only_sortieable := false) -> Dictionary:
	var counts: Dictionary = {}
	for ship_type in FleetDataManager.SHIP_TYPES:
		counts[ship_type] = 0
	var hulls: Array = sortieable_hulls() if only_sortieable else fleet_hulls
	for hull in hulls:
		var t: String = hull.get("ship_type", "")
		if counts.has(t):
			counts[t] += 1
	return counts


## Fold a battle's outcome back into the persistent fleet. Survivors carry
## their hull_id and live crew; their damage state and crew replace the hull's
## records. Sortied hulls that did not survive are removed (and their doctrine
## pruned). Iced / uncrewed hulls never sortied and are left untouched.
func apply_battle_outcome(surviving_ships: Array) -> void:
	var survivors_by_id: Dictionary = {}
	for ship in surviving_ships:
		survivors_by_id[ship.get("hull_id", "")] = ship

	var rng := _new_rng()
	var new_hulls: Array = []
	var dropped_crew_ids: Array = []
	var death_count: int = 0
	var ship_deltas: Array = []
	for hull in fleet_hulls:
		var sortied: bool = not hull.get("iced", false) and _has_pilot(hull)
		if not sortied:
			new_hulls.append(hull)
			continue
		var hull_id: String = hull.get("hull_id", "")
		# Capture the sortie-time ship state before any mutation.
		var before_ship: Dictionary = hull.get("ship", {}).duplicate(true)
		if survivors_by_id.has(hull_id):
			var survivor: Dictionary = survivors_by_id[hull_id]
			var after: Dictionary = _strip_crew(survivor)
			# Crew aboard a surviving hull live or die by the components that
			# were destroyed this battle (sortie-time state vs the survivor).
			var live_crew: Array = survivor.get("crew", []).duplicate(true)
			var casualties: Dictionary = CasualtySystem.resolve_hull_casualties(
				live_crew, hull.get("ship", {}), after, rng)
			hull.crew = casualties.survivors
			hull.ship = after
			for dead in casualties.deaths:
				dropped_crew_ids.append(dead.get("crew_id", ""))
			death_count += casualties.deaths.size()
			new_hulls.append(hull)
			ship_deltas.append(_hull_delta_record(hull, before_ship, after, false))
		else:
			# A hull lost with all hands: everyone aboard is a casualty.
			for member in hull.get("crew", []):
				dropped_crew_ids.append(member.get("crew_id", ""))
				death_count += 1
			ship_deltas.append(_hull_delta_record(hull, before_ship, {}, true))

	var surviving_ids: Dictionary = {}
	for h in new_hulls:
		surviving_ids[h.get("hull_id", "")] = true
	var lost_hull_ids: Array = []
	for h in fleet_hulls:
		var hid: String = h.get("hull_id", "")
		if not surviving_ids.has(hid):
			lost_hull_ids.append(hid)
	fleet_hulls = new_hulls
	var insurance: int = EconomySystem.insurance_total(death_count)
	money -= insurance
	last_battle_summary = {"casualties": death_count, "insurance": insurance, "ship_deltas": ship_deltas}
	_prune_doctrine_for_roster(dropped_crew_ids, fleet_counts())
	squadrons = SquadronSystem.prune_for_roster(squadrons, lost_hull_ids)


func _hull_delta_record(hull: Dictionary, before_ship: Dictionary, after_ship: Dictionary, destroyed: bool) -> Dictionary:
	var before := HullConditionSystem.condition({"ship": before_ship})
	var after := {"armor": 0.0, "systems": 0.0} if destroyed \
		else HullConditionSystem.condition({"ship": after_ship})
	return {
		"hull_id": hull.get("hull_id", ""),
		"ship_type": hull.get("ship_type", ""),
		"armor_before": before.armor,
		"armor_after": after.armor,
		"systems_before": before.systems,
		"systems_after": after.systems,
		"destroyed": destroyed,
	}


## A survivor ship dict as it persists between battles: crew is stored on the
## hull, not inside the ship damage state.
func _strip_crew(ship: Dictionary) -> Dictionary:
	var stripped: Dictionary = ship.duplicate(true)
	stripped.erase("crew")
	return stripped


## Rebuild the fleet to match new ship counts while preserving the identity of
## hulls that remain. Existing hulls of each type are kept in order up to the
## new count; surplus counts spawn fresh hulls, shortfalls drop trailing hulls.
## Doctrine is reconciled for dropped crew. Used by the Edit Fleet screen so
## fleet edits mid-setup keep the doctrine already authored for survivors.
func reconcile_roster_to_counts(new_counts: Dictionary) -> void:
	var existing_by_type: Dictionary = {}
	for hull in fleet_hulls:
		var t: String = hull.get("ship_type", "")
		if not existing_by_type.has(t):
			existing_by_type[t] = []
		existing_by_type[t].append(hull)

	var new_hulls: Array = []
	var dropped_crew_ids: Array = []
	for ship_type in FleetDataManager.SHIP_TYPES:
		var desired: int = int(new_counts.get(ship_type, 0))
		var existing: Array = existing_by_type.get(ship_type, [])
		for i in range(desired):
			if i < existing.size():
				new_hulls.append(existing[i])
			else:
				new_hulls.append(_make_hull(ship_type))
		for i in range(desired, existing.size()):
			for member in existing[i].get("crew", []):
				dropped_crew_ids.append(member.get("crew_id", ""))

	fleet_hulls = new_hulls
	_prune_doctrine_for_roster(dropped_crew_ids, new_counts)

	# The run starts at the main menu, so the player can still edit the fleet
	# before the first battle. Keep starting money matched to the fleet they
	# actually launch with — but freeze it once the run is underway.
	if not started_first_battle:
		money = EconomySystem.roll_starting_money(fleet_hulls, _new_rng())


## Drop doctrine that no longer has a referent after a roster change.
func _prune_doctrine_for_roster(dropped_crew_ids: Array, new_counts: Dictionary) -> void:
	for crew_id in dropped_crew_ids:
		doctrine[DoctrineSystem.SCOPE_CREW].erase(crew_id)
		doctrine["disabled"].erase(crew_id)
	for ship_type in FleetDataManager.SHIP_TYPES:
		if int(new_counts.get(ship_type, 0)) == 0:
			doctrine[DoctrineSystem.SCOPE_CLASS].erase(ship_type)


# ============================================================================
# ROSTER OPS (shop screen: buy hulls, hire/transfer crew, ice ships)
# ============================================================================

## Buy a bare hull of `ship_type`: full standard complement, no crew aboard,
## price deducted from money. Returns the new hull record.
func add_purchased_hull(ship_type: String) -> Dictionary:
	var hull := _make_hull(ship_type, false)
	money -= EconomySystem.ship_purchase_price(ship_type)
	fleet_hulls.append(hull)
	return hull


## The unfilled crew slots on a hull: its standard complement minus the crew
## currently aboard. Gunner slots are matched by weapon_id (so a hull missing
## one specific gun's gunner shows exactly that vacancy); other roles match by
## count.
func hull_vacancies(hull: Dictionary) -> Array:
	var filled_weapon_ids: Dictionary = {}
	var remaining_role_counts: Dictionary = {}
	for member in hull.get("crew", []):
		var role: int = member.get("role", -1)
		if role == CrewData.Role.GUNNER and member.has("weapon_id"):
			filled_weapon_ids[member.weapon_id] = true
		else:
			remaining_role_counts[role] = remaining_role_counts.get(role, 0) + 1

	var vacancies: Array = []
	for slot in hull.get("complement", []):
		var role: int = slot.get("role", -1)
		if role == CrewData.Role.GUNNER and slot.has("weapon_id"):
			if not filled_weapon_ids.has(slot.weapon_id):
				vacancies.append(slot)
		elif remaining_role_counts.get(role, 0) > 0:
			remaining_role_counts[role] -= 1
		else:
			vacancies.append(slot)
	return vacancies


## Hire one roster candidate into one vacant slot on a hull (weapon bound for
## gunner slots, wired into the hull's command chain). The candidate serves
## in the slot's role even when unqualified for it — off-role service is a
## soft performance penalty, not a hard gate. Fails when the slot is not a
## real vacancy, the candidate is already consumed this run, or no longer
## exists in the roster (mid-run override edit).
func fill_vacancy(hull_id: String, slot: Dictionary, roster_id: String) -> bool:
	var hull := hull_by_id(hull_id)
	if hull.is_empty() or not _slot_is_vacant(hull, slot):
		return false
	if hired_roster_ids.has(roster_id):
		return false
	var entry := crew_entry_by_id(roster_id)
	if entry.is_empty():
		return false
	var slot_role: int = slot.get("role", CrewData.Role.PILOT)
	var member := CrewData.assign_role(CrewData.from_roster_entry(entry), slot_role)
	if slot_role == CrewData.Role.GUNNER and slot.has("weapon_id"):
		member["weapon_id"] = slot.weapon_id
	_wire_into_command_chain(hull, member)
	hull.crew.append(member)
	hired_roster_ids.append(roster_id)
	return true


## Move a crew member into a matching vacancy on another hull. Succeeds only
## when the destination has an unfilled slot of the same role; gunners rebind
## to that slot's weapon. The crew dict (identity, skills, doctrine) is intact.
func transfer_crew(crew_id: String, dest_hull_id: String) -> bool:
	var dest := hull_by_id(dest_hull_id)
	if dest.is_empty():
		return false

	var src: Dictionary = {}
	var member: Dictionary = {}
	for hull in fleet_hulls:
		for m in hull.get("crew", []):
			if m.get("crew_id", "") == crew_id:
				src = hull
				member = m
	if member.is_empty() or src.get("hull_id", "") == dest_hull_id:
		return false

	var slot := _matching_vacancy(dest, member)
	if slot.is_empty():
		return false

	src.crew.erase(member)
	_unwire_from_command_chain(src, member)
	if slot.get("role", -1) == CrewData.Role.GUNNER and slot.has("weapon_id"):
		member["weapon_id"] = slot.weapon_id
	elif member.has("weapon_id"):
		member.erase("weapon_id")
	_wire_into_command_chain(dest, member)
	dest.crew.append(member)
	return true


## Mothball or reactivate a hull. Iced hulls never sortie and cost no per-battle
## ship upkeep (their crew are still paid).
func set_hull_iced(hull_id: String, iced: bool) -> void:
	var hull := hull_by_id(hull_id)
	if not hull.is_empty():
		hull.iced = iced


## Dismiss a whole hull and everyone aboard (no insurance — they are let go,
## not lost). Used by the dismissal dialog to cut upkeep. Doctrine for the
## dismissed crew is pruned.
func dismiss_hull(hull_id: String) -> void:
	var hull := hull_by_id(hull_id)
	if hull.is_empty():
		return
	var dropped: Array = []
	for member in hull.get("crew", []):
		dropped.append(member.get("crew_id", ""))
	fleet_hulls.erase(hull)
	_prune_doctrine_for_roster(dropped, fleet_counts())


## Dismiss a single crew member, opening a vacancy on their hull (no insurance).
func dismiss_crew(crew_id: String) -> void:
	for hull in fleet_hulls:
		for member in hull.get("crew", []):
			if member.get("crew_id", "") == crew_id:
				_unwire_from_command_chain(hull, member)
				hull.crew.erase(member)
				_prune_doctrine_for_roster([crew_id], fleet_counts())
				return


## Whether the player can still field a minimum battle force: at least one
## piloted hull whose solo upkeep (its ship cost + one pilot's salary, every
## other hull and crew dismissed) is affordable. False ⇒ the run is lost.
func can_field_minimum() -> bool:
	return _can_field_minimum(fleet_hulls, money)


## Pure form: is a minimum affordable battle force fieldable from `hulls` with
## `funds`? Used both for the live check and to vet a prospective dismissal.
func _can_field_minimum(hulls: Array, funds: int) -> bool:
	var salary := EconomySystem.crew_salary_per_battle()
	var cheapest := -1
	for hull in hulls:
		if not _has_pilot(hull):
			continue
		var cost := EconomySystem.ship_per_battle_cost(hull.get("ship_type", "")) + salary
		if cheapest < 0 or cost < cheapest:
			cheapest = cost
	if cheapest < 0:
		return false
	return funds >= cheapest


## Whether this crew member may be dismissed without soft-locking the run —
## i.e. a minimum affordable force is still fieldable afterward. The dismissal
## dialog disables dismissals that would fail this (e.g. the last affordable
## pilot). Non-pilots and crew on a redundant hull are always safe.
func may_dismiss_crew(crew_id: String) -> bool:
	var hulls := fleet_hulls.duplicate(true)
	for hull in hulls:
		var crew: Array = hull.get("crew", [])
		for i in range(crew.size()):
			if crew[i].get("crew_id", "") == crew_id:
				crew.remove_at(i)
				return _can_field_minimum(hulls, money)
	return true


## Whether this whole hull may be dismissed without soft-locking the run.
func may_dismiss_hull(hull_id: String) -> bool:
	var hulls := fleet_hulls.filter(func(h): return h.get("hull_id", "") != hull_id)
	return _can_field_minimum(hulls, money)


func _slot_is_vacant(hull: Dictionary, slot: Dictionary) -> bool:
	for vacancy in hull_vacancies(hull):
		if vacancy.get("role", -2) == slot.get("role", -1) \
				and vacancy.get("weapon_id", "") == slot.get("weapon_id", ""):
			return true
	return false


func _matching_vacancy(hull: Dictionary, member: Dictionary) -> Dictionary:
	var role: int = member.get("role", -1)
	for slot in hull_vacancies(hull):
		if slot.get("role", -2) == role:
			return slot
	return {}


## A hull's commander is its captain, or its pilot on craft with no captain.
func _hull_commander(hull: Dictionary) -> Dictionary:
	var captain := _find_role(hull, CrewData.Role.CAPTAIN)
	return captain if not captain.is_empty() else _find_role(hull, CrewData.Role.PILOT)


func _find_role(hull: Dictionary, role: int) -> Dictionary:
	for member in hull.get("crew", []):
		if member.get("role", -1) == role:
			return member
	return {}


func _wire_into_command_chain(hull: Dictionary, member: Dictionary) -> void:
	var commander := _hull_commander(hull)
	if commander.is_empty() or commander.get("crew_id", "") == member.get("crew_id", ""):
		return
	member.command_chain.superior = commander.crew_id
	if member.crew_id not in commander.command_chain.subordinates:
		commander.command_chain.subordinates.append(member.crew_id)


func _unwire_from_command_chain(hull: Dictionary, member: Dictionary) -> void:
	var commander := _hull_commander(hull)
	if not commander.is_empty():
		commander.command_chain.subordinates.erase(member.get("crew_id", ""))


## The run is lost when no hulls remain at all.
func is_fleet_empty() -> bool:
	return fleet_hulls.is_empty()


## True when the player can afford to buy the cheapest available hull.
## Used after a defeat to decide between game-over and reset_sector_to_shop.
func can_afford_rebuild() -> bool:
	var cheapest := -1
	for ship_type in FleetDataManager.SHIP_TYPES:
		var price := EconomySystem.ship_purchase_price(ship_type)
		if cheapest < 0 or price < cheapest:
			cheapest = price
	if cheapest < 0:
		return false
	return money >= cheapest


## True when an active run has at least one hull — the gate for showing crew
## management (crew instances only exist on fleet_hulls during a live run).
func has_fleet() -> bool:
	return active and not fleet_hulls.is_empty()


## Repair the fleet during a jump. Engineers use the downtime: each heals
## their ship by REPAIR_FRACTION_PER_STAR_DATE × machinery skill × date gap
## (× RNR_REPAIR_MULTIPLIER when the destination is an R&R stop). Pristine
## hulls (no recorded damage) and crewless hulls are skipped.
## Returns {ships_repaired, points_repaired, date_delta}.
func apply_jump_repairs(destination_star_date: int, is_rnr: bool) -> Dictionary:
	var date_delta: int = maxi(0, destination_star_date - current_star_date)
	current_star_date = destination_star_date

	var fraction: float = WingConstants.REPAIR_FRACTION_PER_STAR_DATE * date_delta
	if is_rnr:
		fraction *= WingConstants.RNR_REPAIR_MULTIPLIER

	var ships_repaired := 0
	var points_repaired := 0
	for hull in fleet_hulls:
		var saved: Dictionary = hull.get("ship", {})
		if saved.is_empty():
			continue
		var merged: Dictionary = saved.duplicate(true)
		merged["crew"] = hull.get("crew", [])
		var before := _ship_health_total(merged)
		var repaired: Dictionary = RepairSystem.apply_engineer_repairs(merged, fraction)
		var healed := _ship_health_total(repaired) - before
		if healed > 0:
			ships_repaired += 1
			points_repaired += healed
		hull.ship = _strip_crew(repaired)

	last_jump_repair_summary = {
		"ships_repaired": ships_repaired,
		"points_repaired": points_repaired,
		"date_delta": date_delta,
	}

	# Generate and apply jump events stamped with the new current_star_date.
	# Only fire when a real campaign is running (nodes exist). Tests that set
	# fleet_hulls directly without a campaign skip event generation.
	if active and not campaign.get("nodes", {}).is_empty():
		roll_jump_events(date_delta)

	return last_jump_repair_summary


func _ship_health_total(ship: Dictionary) -> int:
	return DamageResolver.calculate_total_armor(ship) + DamageResolver.calculate_total_internal_health(ship)


## Total bonus fraction from active intel effects, applied to the next victory
## reward (e.g. 0.25 = +25%). Read at battle end BEFORE temp effects tick.
## Intel events (spy convoy reports, intercepted orders) pay off here.
func next_battle_reward_bonus() -> float:
	var bonus: float = 0.0
	for effect in active_effects:
		if str(effect.get("kind", "")) == "intel":
			bonus += float(effect.get("value", 0.0))
	return bonus


## Build the run_state snapshot for EventSystem, generate jump events, apply
## effects (permanent mutations here; temp effects pushed onto active_effects),
## and prepend to news_feed.  Returns the new events Array.
func roll_jump_events(date_delta: int) -> Array:
	"""Generate and apply star-date events for a jump of `date_delta` star dates."""
	# Build flat crew list from all hull crews
	var all_crew: Array = []
	for hull in fleet_hulls:
		for member in hull.get("crew", []):
			all_crew.append(member)

	# Build place names from campaign nodes
	var places: Array = []
	for node_id in campaign.get("nodes", {}):
		var node: Dictionary = campaign["nodes"][node_id]
		var nname: String = str(node.get("name", ""))
		if not nname.is_empty():
			places.append(nname)

	var run_state: Dictionary = {
		"hulls": fleet_hulls,
		"crew": all_crew,
		"star_date": current_star_date,
		"places": places,
		"battle_count": battles_fought,
	}

	var rng := _new_rng()
	var events: Array = EventSystem.generate_for_jump(run_state, date_delta, rng)

	# Apply each event's effects
	for event in events:
		var classified: Dictionary = EventSystem.classify_effects(event)

		# Apply permanent effects in place
		for perm in classified.get("permanent", []):
			_apply_permanent_effect(perm, event)

		# Push temp effects onto active_effects
		for temp in classified.get("temp", []):
			active_effects.append(temp)

	# Prepend to news_feed, cap to ring-buffer size
	var combined: Array = events.duplicate() + news_feed
	if combined.size() > WingConstants.NEWS_FEED_MAX_ENTRIES:
		combined = combined.slice(0, WingConstants.NEWS_FEED_MAX_ENTRIES)
	news_feed = combined

	return events


## Apply one permanent effect from a resolved event onto run state.
func _apply_permanent_effect(effect: Dictionary, _event: Dictionary) -> void:
	"""Mutate run state for a single permanent effect descriptor."""
	var kind: String = str(effect.get("kind", ""))
	var target: Dictionary = effect.get("resolved_target", {})
	var target_kind: String = str(target.get("kind", ""))

	match kind:
		"crew_skill":
			var crew_id: String = str(target.get("crew_id", ""))
			var skill: String = str(effect.get("skill", ""))
			var value: float = float(effect.get("value", 0.0))
			for hull in fleet_hulls:
				for member in hull.get("crew", []):
					if member.get("crew_id", "") == crew_id:
						var current: float = float(member.get("stats", {}).get("skills", {}).get(skill, 0.0))
						member["stats"]["skills"][skill] = clampf(current + value, 0.0, 1.0)

		"add_attribute":
			var crew_id: String = str(target.get("crew_id", ""))
			var attr_id: String = str(effect.get("attribute", ""))
			for hull in fleet_hulls:
				for member in hull.get("crew", []):
					if member.get("crew_id", "") == crew_id:
						var attrs: Array = member.get("attributes", [])
						if not attrs.has(attr_id):
							attrs.append(attr_id)
						member["attributes"] = attrs

		"remove_attribute":
			var crew_id: String = str(target.get("crew_id", ""))
			var attr_id: String = str(effect.get("attribute", ""))
			for hull in fleet_hulls:
				for member in hull.get("crew", []):
					if member.get("crew_id", "") == crew_id:
						var attrs: Array = member.get("attributes", []).duplicate()
						attrs.erase(attr_id)
						member["attributes"] = attrs

		"ship_repair":
			_apply_hp_effect(target, target_kind, effect, 1)

		"ship_damage":
			_apply_hp_effect(target, target_kind, effect, -1)

		"money":
			money = maxi(0, money + int(effect.get("value", 0)))

		"intel":
			# intel effects are always temp (battles:N); permanent intel is a
			# no-op here — already pushed to active_effects via classify_effects.
			pass

		_:
			# Unknown permanent effect kind — safe to ignore; already validated.
			pass


## Apply a ship_repair (sign_dir +1) or ship_damage (sign_dir -1) effect to the
## resolved target. Fleet-targeted effects hit every hull; ship-targeted effects
## hit the matching hull_id. Magnitude is the effect's `value`.
func _apply_hp_effect(target: Dictionary, target_kind: String, effect: Dictionary, sign_dir: int) -> void:
	"""Route a repair/damage effect to all hulls (fleet) or the targeted hull (ship)."""
	var section: String = str(effect.get("section", "body"))
	var delta: int = int(effect.get("value", 0)) * sign_dir
	if target_kind == "fleet":
		for hull in fleet_hulls:
			_apply_ship_hp_delta(hull, section, delta)
	else:
		var hull_id: String = str(target.get("hull_id", ""))
		for hull in fleet_hulls:
			if hull.get("hull_id", "") == hull_id:
				_apply_ship_hp_delta(hull, section, delta)


## Adjust armor HP on a hull's persisted ship record. Positive delta repairs
## (up to max_armor), negative damages (down to 0). `section` names one armor
## section, or "body" to apply across every section. Hulls with no persisted
## ship record (pristine / never-damaged) are skipped so events never fabricate
## partial battle state.
func _apply_ship_hp_delta(hull: Dictionary, section: String, delta: int) -> void:
	"""Apply an armor HP delta to one named section, or every section when "body"."""
	var saved: Dictionary = hull.get("ship", {})
	if saved.is_empty():
		return

	var ship: Dictionary = saved.duplicate(true)
	for sec in ship.get("armor_sections", []):
		if section != "body" and sec.get("section", "") != section:
			continue
		var cur: int = int(sec.get("current_armor", 0))
		if delta >= 0:
			var max_val: int = int(sec.get("max_armor", cur))
			sec["current_armor"] = mini(max_val, cur + delta)
		else:
			sec["current_armor"] = maxi(0, cur + delta)

	hull["ship"] = ship


## Record a battle's outcome for the campaign map to resolve. Victory folds
## the survivors back into the persistent hull fleet (damage, casualties,
## insurance, doctrine pruning all via apply_battle_outcome). Defeat stashes
## the wiped fleet's final state for the post-battle summary, then empties
## the hull fleet. `final_ships` is every team-0 ship's
## end-of-battle state, each carrying its hull_id and its live crew.
func record_battle_result(result: String, final_ships: Array) -> void:
	# Expire temp effects whose battle count reaches zero after this battle.
	active_effects = EventSystem.tick_battle_effects(active_effects)
	battles_fought += 1

	pending_battle_result = result
	var fled: Array = final_ships.filter(func(ship): return ship.get("fled", false))
	pending_battle_fled = not fled.is_empty()

	if result == CampaignSystem.RESULT_VICTORY:
		# Fled ships are non-destroyed, so they fold in as survivors here —
		# recovered with their flee-time damage (Decision 5: recovered on win).
		apply_battle_outcome(final_ships.filter(
			func(ship): return ship.get("status", "") != "destroyed"))
		lost_fleet_final_ships = []
		lost_fleet_final_crew = []
	elif pending_battle_fled:
		# Defeat, but ships escaped → carry ONLY the fled hulls forward.
		_carry_forward_fled(fled)
		lost_fleet_final_ships = []
		lost_fleet_final_crew = []
	else:
		# Defeat, total loss → fleet is wiped. The campaign map then either
		# ends the run or resets the sector to a shop (see can_afford_rebuild).
		lost_fleet_final_ships = final_ships.duplicate(true)
		lost_fleet_final_crew = []
		fleet_hulls = []


## Rebuild fleet_hulls to contain only the fled hulls, reconciled by hull_id
## against the pre-battle records (keeping complement, iced, identity). Each
## fled hull folds in its flee-time damage and live crew — a clean escape takes
## no new casualties beyond who was already aboard. Crew on hulls lost with the
## battle are pruned from doctrine, and squadrons are pruned for the lost hulls.
func _carry_forward_fled(fled_ships: Array) -> void:
	var fled_by_id: Dictionary = {}
	for ship in fled_ships:
		fled_by_id[ship.get("hull_id", "")] = ship

	var kept: Array = []
	var dropped_crew_ids: Array = []
	for hull in fleet_hulls:
		var hull_id: String = hull.get("hull_id", "")
		if fled_by_id.has(hull_id):
			var ship: Dictionary = fled_by_id[hull_id]
			hull.crew = ship.get("crew", []).duplicate(true)
			hull.ship = _strip_crew(ship)
			kept.append(hull)
		else:
			for member in hull.get("crew", []):
				dropped_crew_ids.append(member.get("crew_id", ""))

	var kept_ids: Dictionary = {}
	for h in kept:
		kept_ids[h.get("hull_id", "")] = true
	var lost_hull_ids: Array = []
	for h in fleet_hulls:
		var hid: String = h.get("hull_id", "")
		if not kept_ids.has(hid):
			lost_hull_ids.append(hid)

	fleet_hulls = kept
	_prune_doctrine_for_roster(dropped_crew_ids, fleet_counts())
	squadrons = SquadronSystem.prune_for_roster(squadrons, lost_hull_ids)


## True when `crew_id` can be moved to `dest_hull_id`: the member exists,
## the source and destination differ, and the destination has a same-role vacancy.
func can_transfer(crew_id: String, dest_hull_id: String) -> bool:
	var dest := hull_by_id(dest_hull_id)
	if dest.is_empty():
		return false
	for hull in fleet_hulls:
		for member in hull.get("crew", []):
			if member.get("crew_id", "") == crew_id:
				if hull.get("hull_id", "") == dest_hull_id:
					return false  # same hull
				return not _matching_vacancy(dest, member).is_empty()
	return false  # crew not found


## True when two crew members can swap ships: both exist, they are on different
## hulls, and they share the same role (cross-role swaps would break each hull's
## complement).
func can_swap(crew_id_a: String, crew_id_b: String) -> bool:
	if crew_id_a == crew_id_b:
		return false
	var hull_a: Dictionary = {}
	var member_a: Dictionary = {}
	var hull_b: Dictionary = {}
	var member_b: Dictionary = {}
	for hull in fleet_hulls:
		for member in hull.get("crew", []):
			var cid: String = member.get("crew_id", "")
			if cid == crew_id_a:
				hull_a = hull
				member_a = member
			elif cid == crew_id_b:
				hull_b = hull
				member_b = member
	if member_a.is_empty() or member_b.is_empty():
		return false
	if hull_a.get("hull_id", "") == hull_b.get("hull_id", ""):
		return false  # same hull
	return member_a.get("role", -1) == member_b.get("role", -2)


## Exchange two crew members between ships. Both command chains are rewired;
## gunners inherit each other's weapon_id. Returns false when can_swap fails.
func swap_crew(crew_id_a: String, crew_id_b: String) -> bool:
	if not can_swap(crew_id_a, crew_id_b):
		return false

	var hull_a: Dictionary = {}
	var member_a: Dictionary = {}
	var hull_b: Dictionary = {}
	var member_b: Dictionary = {}
	for hull in fleet_hulls:
		for member in hull.get("crew", []):
			var cid: String = member.get("crew_id", "")
			if cid == crew_id_a:
				hull_a = hull
				member_a = member
			elif cid == crew_id_b:
				hull_b = hull
				member_b = member

	_unwire_from_command_chain(hull_a, member_a)
	_unwire_from_command_chain(hull_b, member_b)

	# Gunners exchange weapon bindings so each serves the gun that was
	# already mounted on the destination hull.
	if member_a.get("role", -1) == CrewData.Role.GUNNER:
		var wid_a: String = member_a.get("weapon_id", "")
		var wid_b: String = member_b.get("weapon_id", "")
		if wid_b != "":
			member_a["weapon_id"] = wid_b
		elif member_a.has("weapon_id"):
			member_a.erase("weapon_id")
		if wid_a != "":
			member_b["weapon_id"] = wid_a
		elif member_b.has("weapon_id"):
			member_b.erase("weapon_id")

	hull_a.crew.erase(member_a)
	hull_b.crew.erase(member_b)
	hull_a.crew.append(member_b)
	hull_b.crew.append(member_a)

	_wire_into_command_chain(hull_a, member_b)
	_wire_into_command_chain(hull_b, member_a)
	return true


func save_campaign_to_disk() -> bool:
	return CampaignSaveManager.save_campaign({
		"campaign": campaign,
		"fleet_hulls": fleet_hulls,
		"doctrine": doctrine,
		"tactics": tactics,
		"enemy_fleet": enemy_fleet,
		"money": money,
		"current_star_date": current_star_date,
		"hired_roster_ids": hired_roster_ids,
		"run_roster": run_roster,
		"next_hull_id": _next_hull_id,
		"squadrons": squadrons,
		"news_feed": news_feed,
		"active_effects": active_effects,
		"battles_fought": battles_fought,
	})


## Resume a saved campaign. Returns false (leaving the run untouched)
## when no usable save exists.
func load_campaign_from_disk() -> bool:
	var data := CampaignSaveManager.load_campaign()
	if data.is_empty():
		return false
	campaign = data.get("campaign", {})
	fleet_hulls = data.get("fleet_hulls", [])
	doctrine = data.get("doctrine", DoctrineSystem.empty_doctrine())
	tactics = data.get("tactics", TacticsSystem.empty_tactics())
	enemy_fleet = data.get("enemy_fleet", {})
	money = int(data.get("money", 0))
	current_star_date = data.get("current_star_date", STAR_DATE_RUN_START)
	# Older saves have no consumed-pool list: an unconsumed pool is correct
	# for them, since their crews predate roster hiring.
	hired_roster_ids = data.get("hired_roster_ids", [])
	# v2 saves have no run_roster; default to [] so the fallback to
	# CrewRosterManager in crew_entry_by_id still resolves legacy hires.
	run_roster = data.get("run_roster", [])
	_next_hull_id = data.get("next_hull_id", fleet_hulls.size())
	squadrons = data.get("squadrons", [])
	# v2/v3 saves without news_feed/active_effects: default to empty (permanent
	# effects already live in crew/ship/money state — no replay needed).
	news_feed = data.get("news_feed", [])
	active_effects = data.get("active_effects", [])
	battles_fought = int(data.get("battles_fought", 0))
	last_battle_summary = {}
	pending_battle_node_id = ""
	pending_battle_result = ""
	pending_battle_fled = false
	lost_fleet_final_ships = []
	lost_fleet_final_crew = []
	last_jump_repair_summary = {}
	last_battle_progression = []
	started_first_battle = not fleet_hulls.is_empty()
	active = true
	return true
