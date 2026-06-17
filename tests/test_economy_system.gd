extends GutTest

## Tests for EconomySystem - FUNCTIONALITY ONLY.
## Verifies upkeep, rewards, insurance, starting money, and shop stock behave
## by their rules (monotonic where they should be, data-driven) without
## asserting specific credit values, which live in data/economy.json.

func _seeded_rng(s: int = 12345) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	return rng


## A minimal hull record: only the fields the economy reads (type, iced, crew).
func _hull(ship_type: String, crew_size: int, iced: bool = false) -> Dictionary:
	var crew: Array = []
	for i in range(crew_size):
		crew.append({"crew_id": "c%d" % i})
	return {"ship_type": ship_type, "iced": iced, "crew": crew}


# ============================================================================
# PER-BATTLE UPKEEP
# ============================================================================

func test_upkeep_totals_ship_cost_plus_salaries():
	var upkeep := EconomySystem.per_battle_upkeep([_hull("fighter", 2)])

	assert_gt(upkeep.ship_cost, 0, "A sortieing ship has a per-battle cost")
	assert_gt(upkeep.salary_cost, 0, "Crew aboard draw a salary")
	assert_eq(upkeep.total, upkeep.ship_cost + upkeep.salary_cost,
		"Total upkeep is ship cost plus salaries")


func test_iced_hull_is_excluded_from_ship_cost():
	var active := EconomySystem.per_battle_upkeep([_hull("corvette", 0)])
	var iced := EconomySystem.per_battle_upkeep([_hull("corvette", 0, true)])

	assert_gt(active.ship_cost, 0, "An active hull is charged a per-battle ship cost")
	assert_eq(iced.ship_cost, 0, "An iced hull does not sortie, so no ship cost")


func test_iced_hull_still_pays_crew_salaries():
	var iced := EconomySystem.per_battle_upkeep([_hull("corvette", 3, true)])

	assert_gt(iced.salary_cost, 0, "Hired crew are paid even while their hull is iced")
	assert_eq(iced.ship_cost, 0, "But the iced hull itself costs nothing to keep")


func test_more_crew_means_more_salary():
	var few := EconomySystem.per_battle_upkeep([_hull("fighter", 1)])
	var many := EconomySystem.per_battle_upkeep([_hull("fighter", 4)])

	assert_gt(many.salary_cost, few.salary_cost,
		"Salary cost grows with the number of crew aboard")


# ============================================================================
# STARTING MONEY
# ============================================================================

func test_starting_money_is_positive():
	var money := EconomySystem.roll_starting_money([_hull("fighter", 1)], _seeded_rng())

	assert_gt(money, 0, "A new run should begin with some credits")


func test_starting_money_grows_with_fleet_upkeep():
	# Same seed => same number of battles-worth, so a costlier fleet yields more
	# starting money. Crews are large enough that rolled upkeep clears the floor,
	# so the proportional behavior is what's under test (not the minimum).
	var lean := EconomySystem.roll_starting_money([_hull("fighter", 80)], _seeded_rng(7))
	var rich := EconomySystem.roll_starting_money(
		[_hull("fighter", 80), _hull("capital", 50)], _seeded_rng(7))

	assert_gt(rich, lean,
		"A fleet with higher upkeep should start with proportionally more money")


func test_starting_money_respects_minimum_floor():
	# A tiny fleet's rolled upkeep is well below the floor, so the run still
	# begins with a usable bankroll.
	var money := EconomySystem.roll_starting_money([_hull("fighter", 1)], _seeded_rng())
	var floor_value := int(EconomySystem.config().get("starting_money", {}).get("minimum", 0))

	assert_gte(money, floor_value,
		"Starting money never drops below the configured minimum")


# ============================================================================
# BATTLE REWARD
# ============================================================================

func test_no_kills_earns_no_reward():
	assert_eq(EconomySystem.battle_reward({}), 0,
		"Destroying nothing earns nothing")


func test_reward_grows_with_kills():
	var one := EconomySystem.battle_reward({"fighter": 1})
	var two := EconomySystem.battle_reward({"fighter": 2})

	assert_gt(one, 0, "Destroying an enemy earns a reward")
	assert_gt(two, one, "More kills of a type earn more")


func test_reward_sums_across_enemy_types():
	var fighters := EconomySystem.battle_reward({"fighter": 1})
	var capitals := EconomySystem.battle_reward({"capital": 1})
	var mixed := EconomySystem.battle_reward({"fighter": 1, "capital": 1})

	assert_eq(mixed, fighters + capitals,
		"A mixed bag of kills rewards the sum of its parts")


# ============================================================================
# INSURANCE
# ============================================================================

func test_no_deaths_owes_no_insurance():
	assert_eq(EconomySystem.insurance_total(0), 0,
		"No casualties means no insurance owed")


func test_insurance_scales_with_deaths():
	assert_gt(EconomySystem.insurance_total(2), EconomySystem.insurance_total(1),
		"Each crew death adds to the insurance owed")


# ============================================================================
# SHOP STOCK
# ============================================================================

func test_shop_stock_size_within_configured_bounds():
	var cfg: Dictionary = EconomySystem.config().get("shop_stock", {})
	var lo: int = int(cfg.get("min_ships", 0))
	var hi: int = int(cfg.get("max_ships", 0))
	var valid_types: Array = FleetDataManager.SHIP_TYPES

	for seed in range(20):
		var stock := EconomySystem.roll_shop_stock(_seeded_rng(seed))
		assert_between(stock.size(), lo, hi,
			"Shop stock count should stay within the configured bounds")
		for ship_type in stock:
			assert_true(ship_type in valid_types,
				"Every stocked ship should be a real ship type")


func test_shop_stock_roll_is_deterministic_for_a_seed():
	var first := EconomySystem.roll_shop_stock(_seeded_rng(99))
	var second := EconomySystem.roll_shop_stock(_seeded_rng(99))

	assert_eq(first, second, "The same seed should roll the same stock")


# ============================================================================
# PRICING (data-driven)
# ============================================================================

func test_every_ship_type_has_a_positive_purchase_price():
	for ship_type in FleetDataManager.SHIP_TYPES:
		assert_gt(EconomySystem.ship_purchase_price(ship_type), 0,
			"Every buyable ship type should have a price: %s" % ship_type)
