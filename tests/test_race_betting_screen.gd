extends GutTest

## Behavioral test for the betting screen's core flow: selecting a racer records
## the bet, and running settles it and changes the player's money. Drives the
## real handlers (the same ones the buttons call) so a working test means the
## logic is sound and any in-game failure is presentation/input, not logic.

var _orig_money: int
var _orig_fleet: Array


func before_each() -> void:
	_orig_money = RoguelikeRun.money
	_orig_fleet = RoguelikeRun.fleet_hulls
	# All-NPC field, plenty of credits, deterministic of "money changed".
	RoguelikeRun.fleet_hulls = []
	RoguelikeRun.money = 1000


func after_each() -> void:
	RoguelikeRun.money = _orig_money
	RoguelikeRun.fleet_hulls = _orig_fleet


func _open_screen() -> RaceBettingScreen:
	var screen := RaceBettingScreen.new()
	add_child_autofree(screen)
	screen.persist = false  # never touch the campaign save in a test
	screen.setup()
	return screen


func test_field_has_a_bettable_racer() -> void:
	var screen := _open_screen()
	assert_gt(screen._entrants.size(), 0, "Betting field is populated")
	var bettable := 0
	for e in screen._entrants:
		if not e.get("is_player_pilot", false):
			bettable += 1
	assert_gt(bettable, 0, "Field has at least one racer the player can bet on")


func test_selecting_a_racer_records_the_bet_target() -> void:
	var screen := _open_screen()
	var idx := _first_npc(screen)
	screen._on_bet_selected(idx, true)
	assert_eq(screen._bet_entrant_index, idx, "Selecting a racer records it as the bet target")


func test_running_settles_the_bet_and_changes_money() -> void:
	var screen := _open_screen()
	var idx := _first_npc(screen)
	screen._on_bet_selected(idx, true)
	screen._wager_input.text = "50"
	var before: int = RoguelikeRun.money
	screen._on_run_pressed()
	assert_false(screen._results.is_empty(), "Running the race produces results")
	assert_true(screen._results.has("winner_ship_id"), "Results name a winner")
	assert_ne(RoguelikeRun.money, before, "Settling the bet changes the player's money")


func test_running_without_a_selection_does_not_charge() -> void:
	var screen := _open_screen()
	screen._bet_entrant_index = -1
	screen._wager_input.text = "50"
	var before: int = RoguelikeRun.money
	screen._on_run_pressed()
	assert_eq(RoguelikeRun.money, before, "No bet selected ⇒ money is untouched")
	assert_true(screen._results.is_empty(), "No race is run without a selected racer")


func _first_npc(screen: RaceBettingScreen) -> int:
	for i in range(screen._entrants.size()):
		if not screen._entrants[i].get("is_player_pilot", false):
			return i
	return -1


# ── Regression: a full player fleet must still leave NPCs to bet on ───────────
# Previously the field added player pilots up to the WHOLE field size, so a real
# run (fleet full of pilots) produced an all-"[YOURS]" field with no bet target.

func test_full_player_fleet_still_has_bettable_npcs() -> void:
	RoguelikeRun.fleet_hulls = _fleet_of_pilots(10)
	var screen := _open_screen()
	var bettable := 0
	var mine := 0
	for e in screen._entrants:
		if e.get("is_player_pilot", false):
			mine += 1
		else:
			bettable += 1
	assert_gt(bettable, 0, "Even with a full fleet, there are NPC racers to bet on")
	assert_lt(mine, screen._entrants.size(), "The field is not entirely the player's own pilots")


func _fleet_of_pilots(n: int) -> Array:
	var hulls: Array = []
	for i in range(n):
		hulls.append({
			"hull_id": "h%d" % i,
			"ship_type": "fighter",
			"crew": [{
				"crew_id": "p%d" % i,
				"callsign": "Mine%d" % i,
				"role": CrewData.Role.PILOT,
				"qualified_roles": [CrewData.Role.PILOT],
				"stats": {"stress": 0.0, "fatigue": 0.0, "reaction_time": 0.15,
					"skills": {"piloting": 0.5, "awareness": 0.5, "composure": 0.5,
						"aggression": 0.5, "aim": 0.5, "tactics": 0.5, "machinery": 0.5}},
			}],
		})
	return hulls
