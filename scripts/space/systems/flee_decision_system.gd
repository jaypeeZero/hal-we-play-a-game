class_name FleeDecisionSystem
extends RefCounted

## The one-time "commit to flee?" decision a ship makes when it nears the escape
## boundary. Pure — shared by fighter and large-ship pilot AI so the rule is
## identical across hull classes.
##
## A ship commits when the pressure to run (low hull, outnumbered, already in a
## survival reflex, a captain retreat order) outweighs its composure/aggression
## resolve to stay. The survival reflex is an INPUT here, not the trigger: a
## panicking ship is likelier to commit, but a steady pilot who merely strayed
## to the edge while evading turns back.

## A ship commits when (pressure - resolve) reaches this margin.
const FLEE_COMMIT_THRESHOLD := 0.5
## How much low armor pushes toward fleeing.
const W_HULL := 0.4
## How much being locally outnumbered pushes toward fleeing.
const W_OUTNUMBERED := 0.3
## How much an active survival reflex (retreat/evade) pushes toward fleeing.
const W_SURVIVAL_MODE := 0.2

## Composure and aggression each contribute half the resolve to stay.
const RESOLVE_COMPOSURE_SHARE := 0.5
const RESOLVE_AGGRESSION_SHARE := 0.5
const SKILL_DEFAULT := 0.5

## Enemies/friends are counted within this radius for the outnumbered factor.
const OUTNUMBERED_RADIUS := 2000.0
## Outnumbered factor saturates to 1.0 once enemies outnumber friends by this many.
const OUTNUMBERED_SATURATION := 3.0

const SURVIVAL_FLEE_MODES := ["retreat", "evade"]
const CAPTAIN_RETREAT_TYPES := ["withdraw", "evade"]

const COMMITTED := "committed"
const RETURNING := "returning"


## Returns COMMITTED or RETURNING. Called ONCE per edge approach; the result is
## locked into ship.orders.flee_decision by the caller.
static func decide(crew_data: Dictionary, ship_data: Dictionary, all_ships: Array) -> String:
	# A fleet retreat order is decisive: it forces a commit regardless of the
	# pilot's own resolve.
	if _captain_orders_retreat(crew_data, ship_data):
		return COMMITTED

	var skills: Dictionary = crew_data.get("stats", {}).get("skills", {})
	var resolve: float = skills.get("composure", SKILL_DEFAULT) * RESOLVE_COMPOSURE_SHARE \
		+ skills.get("aggression", SKILL_DEFAULT) * RESOLVE_AGGRESSION_SHARE

	var pressure := 0.0
	pressure += W_HULL * (1.0 - _armor_ratio(ship_data))
	pressure += W_OUTNUMBERED * _outnumbered_factor(ship_data, all_ships)
	if ship_data.get("orders", {}).get("survival_mode", "") in SURVIVAL_FLEE_MODES:
		pressure += W_SURVIVAL_MODE

	return COMMITTED if (pressure - resolve) >= FLEE_COMMIT_THRESHOLD else RETURNING


## Fraction of armor remaining across all sections (1.0 = pristine, 0.0 = gone).
static func _armor_ratio(ship_data: Dictionary) -> float:
	var sections: Array = ship_data.get("armor_sections", [])
	if sections.is_empty():
		return 1.0
	var current := 0.0
	var maximum := 0.0
	for section in sections:
		current += float(section.get("current_armor", 0))
		maximum += float(section.get("max_armor", 0))
	return current / maximum if maximum > 0.0 else 1.0


## 0.0 when not outnumbered, ramping to 1.0 as nearby enemies exceed friends.
static func _outnumbered_factor(ship_data: Dictionary, all_ships: Array) -> float:
	var my_team: int = ship_data.get("team", -1)
	var my_id: String = ship_data.get("ship_id", "")
	var my_pos: Vector2 = ship_data.get("position", Vector2.ZERO)
	var enemies := 0
	var friends := 0
	for ship in all_ships:
		if ship.get("ship_id", "") == my_id:
			continue
		if ship.get("status", "") == "destroyed":
			continue
		if my_pos.distance_to(ship.get("position", Vector2.ZERO)) > OUTNUMBERED_RADIUS:
			continue
		if ship.get("team", -1) == my_team:
			friends += 1
		elif ship.get("team", -1) >= 0:
			enemies += 1
	var advantage: float = float(enemies - friends)
	if advantage <= 0.0:
		return 0.0
	return clamp(advantage / OUTNUMBERED_SATURATION, 0.0, 1.0)


## True when this ship's commander has been handed a fleet retreat order. The
## captain/squadron order channel is crew-level (crew.orders.received); a ship
## driven into a withdraw posture (orders.current_order) counts too.
static func _captain_orders_retreat(crew_data: Dictionary, ship_data: Dictionary) -> bool:
	var received = crew_data.get("orders", {}).get("received", null)
	if received != null and received is Dictionary:
		if received.get("type", "") in CAPTAIN_RETREAT_TYPES:
			return true
	return ship_data.get("orders", {}).get("current_order", "") == "withdraw"
