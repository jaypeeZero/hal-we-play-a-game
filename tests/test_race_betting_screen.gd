extends GutTest

## Behavioral tests for the betting screen's core flow. Drives the real handlers
## (the same ones the buttons call) so a green test means the logic is sound and
## any in-game failure is presentation/input, not logic. You can bet on ANY
## racer — including your own pilots — and at least half the field is yours when
## you have the pilots for it.

var _orig_money: int
var _orig_fleet: Array


func before_each() -> void:
	_orig_money = RoguelikeRun.money
	_orig_fleet = RoguelikeRun.fleet_hulls
	RoguelikeRun.fleet_hulls = []   # default: NPC-only field
	RoguelikeRun.money = 1000


func after_each() -> void:
	RoguelikeRun.money = _orig_money
	RoguelikeRun.fleet_hulls = _orig_fleet


func _open_screen() -> RaceBettingScreen:
	var screen := RaceBettingScreen.new()
	add_child_autofree(screen)
	screen.persist = false        # never touch the campaign save in a test
	screen.visual_replay = false  # settle synchronously (no visible scene)
	screen.setup()
	return screen


func test_field_is_populated_and_every_racer_is_bettable() -> void:
	var screen := _open_screen()
	assert_gt(screen._entrants.size(), 0, "Betting field is populated")
	# Every racer has a bet button (you can bet on anyone).
	assert_eq(screen._bet_buttons.size(), screen._entrants.size(),
		"Every racer in the field is bettable")


func test_selecting_a_racer_records_the_bet_target() -> void:
	var screen := _open_screen()
	screen._on_bet_selected(0, true)
	assert_eq(screen._bet_entrant_index, 0, "Selecting a racer records it as the bet target")


func test_running_settles_the_bet_and_changes_money() -> void:
	var screen := _open_screen()
	screen._on_bet_selected(0, true)
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


func test_can_wager_full_balance() -> void:
	var screen := _open_screen()
	screen._on_bet_selected(0, true)
	screen._wager_input.text = str(RoguelikeRun.money)  # bet everything
	screen._on_run_pressed()
	assert_false(screen._results.is_empty(), "A full-balance wager is accepted and the race runs")


# ── Field composition: at least half yours when you have the pilots ───────────

func test_full_fleet_makes_majority_of_field_player_pilots() -> void:
	RoguelikeRun.fleet_hulls = _fleet_of_pilots(10)
	var screen := _open_screen()
	var mine := 0
	for e in screen._entrants:
		if e.get("is_player_pilot", false):
			mine += 1
	assert_gte(mine, int(ceil(screen._entrants.size() / 2.0)),
		"With a full fleet, at least half the field is the player's own pilots")


func test_can_bet_on_your_own_pilot() -> void:
	RoguelikeRun.fleet_hulls = _fleet_of_pilots(10)
	var screen := _open_screen()
	var mine_idx := -1
	for i in range(screen._entrants.size()):
		if screen._entrants[i].get("is_player_pilot", false):
			mine_idx = i
			break
	assert_gt(mine_idx, -1, "Field contains at least one of the player's pilots")
	screen._on_bet_selected(mine_idx, true)
	assert_eq(screen._bet_entrant_index, mine_idx, "Player can select their own pilot to bet on")
	screen._wager_input.text = "50"
	var before: int = RoguelikeRun.money
	screen._on_run_pressed()
	assert_ne(RoguelikeRun.money, before, "Betting on your own pilot settles and changes money")


func test_small_fleet_field_mixes_player_and_npc() -> void:
	RoguelikeRun.fleet_hulls = _fleet_of_pilots(2)
	var screen := _open_screen()
	var mine := 0
	var npc := 0
	for e in screen._entrants:
		if e.get("is_player_pilot", false):
			mine += 1
		else:
			npc += 1
	assert_eq(mine, 2, "Both of the player's pilots appear")
	assert_gt(npc, 0, "Remaining slots are filled with NPC racers")


# ── Visible replay path (launch → finish → settle) ───────────────────────────

func test_visible_replay_launches_runs_and_settles() -> void:
	var screen := RaceBettingScreen.new()
	add_child_autofree(screen)
	screen.persist = false
	screen.visual_replay = true   # exercise the real replay path
	screen.setup()
	screen._on_bet_selected(0, true)
	screen._wager_input.text = "50"
	var before: int = RoguelikeRun.money
	screen._on_run_pressed()
	assert_false(screen.visible, "Betting screen hides while the race plays")

	var race := _find_race_scene()
	assert_not_null(race, "A visible race scene is launched on Run")
	race.get_node("ShipRaceGame")._skip_to_finish()

	assert_false(screen._results.is_empty(), "Finishing the replay settles the bet")
	assert_ne(RoguelikeRun.money, before, "Money changes once the replay settles")
	assert_true(screen.visible, "Betting screen is restored after the replay")


func _find_race_scene() -> Node:
	for n in get_tree().root.get_children():
		if n.has_node("ShipRaceGame"):
			return n
	return null


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
