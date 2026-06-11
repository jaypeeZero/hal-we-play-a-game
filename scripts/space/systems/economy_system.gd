class_name EconomySystem
extends RefCounted

## Pure, data-driven economy for a roguelike run: ship/crew pricing, per-battle
## upkeep, battle rewards, insurance, starting money, and shop stock rolls.
## Config lives in data/economy.json (no magic numbers here). Every random
## roll takes an explicit RandomNumberGenerator so callers control seeding and
## tests stay deterministic.

const CONFIG_PATH := "res://data/economy.json"

static var _config: Dictionary = {}


## The parsed economy config (cached). A deep copy is returned so callers can
## never mutate the shared table.
static func config() -> Dictionary:
	if _config.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		if data is Dictionary:
			_config = data
		else:
			push_error("EconomySystem: invalid JSON in %s" % CONFIG_PATH)
			_config = {}
	return _config.duplicate(true)


# ============================================================================
# PRICING LOOKUPS
# ============================================================================

static func ship_purchase_price(ship_type: String) -> int:
	return int(config().get("ships", {}).get(ship_type, {}).get("purchase_price", 0))


static func ship_per_battle_cost(ship_type: String) -> int:
	return int(config().get("ships", {}).get(ship_type, {}).get("per_battle_cost", 0))


static func crew_salary_per_battle() -> int:
	return int(config().get("crew", {}).get("salary_per_battle", 0))


static func crew_insurance_payout() -> int:
	return int(config().get("crew", {}).get("insurance_payout", 0))


# ============================================================================
# UPKEEP / REWARDS / INSURANCE
# ============================================================================

## Per-battle upkeep for a fleet of hull records. Ship costs are charged only
## for hulls that sortie (not iced); crew salaries are paid for every hired
## crew member aboard any hull, iced or not. Returns
## {ship_cost, salary_cost, total}.
static func per_battle_upkeep(hulls: Array) -> Dictionary:
	var ship_cost := 0
	var salary_cost := 0
	var salary := crew_salary_per_battle()
	for hull in hulls:
		if not hull.get("iced", false):
			ship_cost += ship_per_battle_cost(hull.get("ship_type", ""))
		salary_cost += hull.get("crew", []).size() * salary
	return {
		"ship_cost": ship_cost,
		"salary_cost": salary_cost,
		"total": ship_cost + salary_cost,
	}


## Random starting money: enough to cover the current fleet's upkeep for a
## random number of battles (config starting_money.{min,max}_upkeep_battles).
static func roll_starting_money(hulls: Array, rng: RandomNumberGenerator) -> int:
	var cfg: Dictionary = config().get("starting_money", {})
	var battles := rng.randi_range(
		int(cfg.get("min_upkeep_battles", 0)),
		int(cfg.get("max_upkeep_battles", 0)))
	return per_battle_upkeep(hulls).total * battles


## Reward for the enemies destroyed this battle, keyed by ship type.
static func battle_reward(destroyed_enemy_counts: Dictionary) -> int:
	var rewards: Dictionary = config().get("battle_rewards", {})
	var total := 0
	for ship_type in destroyed_enemy_counts:
		total += int(destroyed_enemy_counts[ship_type]) * int(rewards.get(ship_type, 0))
	return total


## Total insurance the player owes for crew lost this battle.
static func insurance_total(death_count: int) -> int:
	return death_count * crew_insurance_payout()


# ============================================================================
# SHOP STOCK
# ============================================================================

## Roll the ships a shop node offers: a random count (config shop_stock
## .{min,max}_ships) of random ship types. Returns an Array of ship-type
## strings (duplicates allowed — the same hull can appear twice).
static func roll_shop_stock(rng: RandomNumberGenerator) -> Array:
	var cfg: Dictionary = config().get("shop_stock", {})
	var count := rng.randi_range(
		int(cfg.get("min_ships", 0)),
		int(cfg.get("max_ships", 0)))
	var types: Array = config().get("ships", {}).keys()
	var stock: Array = []
	if types.is_empty():
		return stock
	for _i in range(count):
		stock.append(types[rng.randi_range(0, types.size() - 1)])
	return stock
