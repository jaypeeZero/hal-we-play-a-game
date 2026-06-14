extends GutTest

## Tests for dismissal + bankruptcy - FUNCTIONALITY ONLY. Dismissing ships and
## crew cuts upkeep (no insurance), prunes doctrine, and opens vacancies;
## can_field_minimum decides whether a strapped run can still take the field;
## the DismissalDialog gates Confirm on affordability.

const PILOT_DOCTRINE := "charge_head_on"

var _saved_fleet_hulls: Array
var _saved_money: int
var _saved_doctrine: Dictionary
var _saved_active: bool
var _saved_run_roster: Array
var _saved_hired_ids: Array


func before_each() -> void:
	_saved_fleet_hulls = RoguelikeRun.fleet_hulls.duplicate(true)
	_saved_money = RoguelikeRun.money
	_saved_doctrine = RoguelikeRun.doctrine.duplicate(true)
	_saved_active = RoguelikeRun.active
	_saved_run_roster = RoguelikeRun.run_roster.duplicate(true)
	_saved_hired_ids = RoguelikeRun.hired_roster_ids.duplicate()


func after_each() -> void:
	RoguelikeRun.fleet_hulls = _saved_fleet_hulls
	RoguelikeRun.money = _saved_money
	RoguelikeRun.doctrine = _saved_doctrine
	RoguelikeRun.active = _saved_active
	RoguelikeRun.run_roster = _saved_run_roster
	RoguelikeRun.hired_roster_ids = _saved_hired_ids


func _counts(overrides: Dictionary = {}) -> Dictionary:
	var base := {"fighter": 0, "heavy_fighter": 0,
		"torpedo_boat": 0, "corvette": 0, "capital": 0}
	for key in overrides:
		base[key] = overrides[key]
	return base


func _upkeep() -> int:
	return EconomySystem.per_battle_upkeep(RoguelikeRun.fleet_hulls).total


# ============================================================================
# DISMISS HULL
# ============================================================================

func test_dismiss_hull_removes_it_and_everyone_aboard():
	RoguelikeRun.start_run(_counts({"fighter": 2}))
	var hull_id: String = RoguelikeRun.fleet_hulls[0].hull_id

	RoguelikeRun.dismiss_hull(hull_id)

	assert_eq(RoguelikeRun.fleet_hulls.size(), 1, "The dismissed hull is gone")
	assert_true(RoguelikeRun.hull_by_id(hull_id).is_empty(), "...and can no longer be found")


func test_dismiss_hull_cuts_its_upkeep():
	RoguelikeRun.start_run(_counts({"fighter": 2}))
	var before := _upkeep()

	RoguelikeRun.dismiss_hull(RoguelikeRun.fleet_hulls[0].hull_id)

	assert_lt(_upkeep(), before, "Dismissing a hull lowers the fleet's upkeep")


func test_dismiss_hull_prunes_doctrine_for_its_crew():
	RoguelikeRun.start_run(_counts({"fighter": 2}))
	var hull: Dictionary = RoguelikeRun.fleet_hulls[0]
	var crew_id: String = hull.crew[0].crew_id
	DoctrineSystem.set_instruction_in_place(
		RoguelikeRun.doctrine, DoctrineSystem.SCOPE_CREW, crew_id, PILOT_DOCTRINE)

	RoguelikeRun.dismiss_hull(hull.hull_id)

	assert_false(RoguelikeRun.doctrine[DoctrineSystem.SCOPE_CREW].has(crew_id),
		"A dismissed hull's crew doctrine is pruned")


# ============================================================================
# DISMISS CREW
# ============================================================================

func test_dismiss_crew_opens_a_vacancy_without_removing_the_hull():
	RoguelikeRun.start_run(_counts({"corvette": 1}))
	var hull: Dictionary = RoguelikeRun.fleet_hulls[0]
	var vacancies_before := RoguelikeRun.hull_vacancies(hull).size()
	var crew_id: String = hull.crew[0].crew_id

	RoguelikeRun.dismiss_crew(crew_id)

	assert_eq(RoguelikeRun.fleet_hulls.size(), 1, "The hull stays in the fleet")
	assert_eq(RoguelikeRun.hull_vacancies(hull).size(), vacancies_before + 1,
		"Dismissing a crew member opens a vacancy")


func test_dismiss_crew_cuts_only_a_salary():
	RoguelikeRun.start_run(_counts({"corvette": 1}))
	var before := _upkeep()
	var crew_id: String = RoguelikeRun.fleet_hulls[0].crew[0].crew_id

	RoguelikeRun.dismiss_crew(crew_id)

	assert_eq(_upkeep(), before - EconomySystem.crew_salary_per_battle(),
		"Dismissing one crew member drops exactly one salary from upkeep")


# ============================================================================
# BENCHED HULLS (pilotless ships left behind — surfaced before launch)
# ============================================================================

func _strip_pilots(hull: Dictionary) -> void:
	hull.crew = hull.crew.filter(func(m): return m.get("role", -1) != CrewData.Role.PILOT)


func test_benched_hulls_lists_active_pilotless_ships():
	RoguelikeRun.start_run(_counts({"fighter": 1, "capital": 1}))
	for hull in RoguelikeRun.fleet_hulls:
		if hull.ship_type == "capital":
			_strip_pilots(hull)  # as if its pilot was dismissed or killed

	var benched := RoguelikeRun.benched_hulls()

	assert_eq(benched.size(), 1, "Only the pilotless active hull is benched")
	assert_eq(benched[0].ship_type, "capital", "It's the capital that's staying behind")


func test_iced_hulls_are_not_counted_as_benched():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	_strip_pilots(RoguelikeRun.fleet_hulls[0])
	RoguelikeRun.set_hull_iced(RoguelikeRun.fleet_hulls[0].hull_id, true)

	assert_true(RoguelikeRun.benched_hulls().is_empty(),
		"A deliberately iced hull is expected to sit out — not a surprise benching")


func test_fully_crewed_fleet_benches_nobody():
	RoguelikeRun.start_run(_counts({"fighter": 2}))

	assert_true(RoguelikeRun.benched_hulls().is_empty(),
		"Every piloted, active hull sorties — nothing is left behind")


func test_launch_notice_proceed_and_cancel():
	RoguelikeRun.start_run(_counts({"capital": 1}))
	_strip_pilots(RoguelikeRun.fleet_hulls[0])
	var notice := LaunchNotice.new()
	add_child_autofree(notice)
	notice.setup(RoguelikeRun.benched_hulls())
	var captured := {"value": -1}
	notice.resolved.connect(func(launch: bool): captured.value = 1 if launch else 0)

	_find_buttons(notice, "Launch anyway", [])[0].pressed.emit()
	assert_eq(captured.value, 1, "Launch anyway resolves the notice to proceed")

	captured.value = -1
	_find_buttons(notice, "Cancel", [])[0].pressed.emit()
	assert_eq(captured.value, 0, "Cancel resolves the notice to abort the launch")


# ============================================================================
# CAN FIELD MINIMUM (bankruptcy gate)
# ============================================================================

func test_can_field_minimum_true_when_a_piloted_hull_is_affordable():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	RoguelikeRun.money = EconomySystem.ship_per_battle_cost("fighter") \
		+ EconomySystem.crew_salary_per_battle()

	assert_true(RoguelikeRun.can_field_minimum(),
		"A lone piloted fighter whose solo upkeep is covered can still take the field")


func test_can_field_minimum_false_when_even_one_hull_is_unaffordable():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	RoguelikeRun.money = 0

	assert_false(RoguelikeRun.can_field_minimum(),
		"With no money, not even a minimum force can sortie — the run is lost")


func test_can_field_minimum_false_without_a_piloted_hull():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	RoguelikeRun.fleet_hulls[0].crew = []  # no pilot anywhere
	RoguelikeRun.money = 1000000

	assert_false(RoguelikeRun.can_field_minimum(),
		"No pilot means nothing can fly, however much money is on hand")


# ============================================================================
# DISMISSAL GUARDS (no soft-lock: can't dismiss your last fieldable force)
# ============================================================================

func test_cannot_dismiss_the_last_fieldable_pilot():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	RoguelikeRun.money = EconomySystem.ship_per_battle_cost("fighter") \
		+ EconomySystem.crew_salary_per_battle()
	var pilot_id: String = RoguelikeRun.fleet_hulls[0].crew[0].crew_id

	assert_false(RoguelikeRun.may_dismiss_crew(pilot_id),
		"Dismissing the only affordable pilot would soft-lock the run, so it's barred")


func test_cannot_dismiss_the_last_fieldable_hull():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	var hull_id: String = RoguelikeRun.fleet_hulls[0].hull_id

	assert_false(RoguelikeRun.may_dismiss_hull(hull_id),
		"Dismissing the last fieldable hull would soft-lock the run, so it's barred")


func test_can_dismiss_a_pilot_when_another_affordable_hull_remains():
	RoguelikeRun.start_run(_counts({"fighter": 2}))
	RoguelikeRun.money = 100000  # both fighters comfortably affordable
	var pilot_id: String = RoguelikeRun.fleet_hulls[0].crew[0].crew_id

	assert_true(RoguelikeRun.may_dismiss_crew(pilot_id),
		"A pilot may go while another piloted, affordable hull still stands")


func test_can_dismiss_a_non_pilot_on_the_last_hull():
	RoguelikeRun.start_run(_counts({"corvette": 1}))
	RoguelikeRun.money = 100000
	var gunner_id := ""
	for member in RoguelikeRun.fleet_hulls[0].crew:
		if member.get("role", -1) == CrewData.Role.GUNNER:
			gunner_id = member.crew_id
			break

	assert_true(RoguelikeRun.may_dismiss_crew(gunner_id),
		"Dismissing a gunner leaves the pilot — the hull is still fieldable")


func test_dialog_disables_dismissing_the_last_pilot_and_hull():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	RoguelikeRun.money = EconomySystem.ship_per_battle_cost("fighter") \
		+ EconomySystem.crew_salary_per_battle()
	var dialog := DismissalDialog.new()
	add_child_autofree(dialog)
	dialog.setup()

	var crew_btn: Button = _find_buttons(dialog, "Dismiss", [])[0]
	var ship_btn: Button = _find_buttons(dialog, "Dismiss ship", [])[0]
	assert_true(crew_btn.disabled, "The last pilot's Dismiss button is disabled")
	assert_true(ship_btn.disabled, "The last fieldable hull's Dismiss ship button is disabled")


# ============================================================================
# DISMISSAL DIALOG (Confirm affordability gate)
# ============================================================================

func _find_buttons(node: Node, text: String, acc: Array) -> Array:
	for child in node.get_children():
		if child is Button and child.text == text:
			acc.append(child)
		_find_buttons(child, text, acc)
	return acc


func test_dialog_confirm_unlocks_after_dismissing_to_affordable():
	RoguelikeRun.start_run(_counts({"fighter": 2}))
	# Enough for one fighter's upkeep, not two: Confirm starts locked.
	RoguelikeRun.money = EconomySystem.ship_per_battle_cost("fighter") \
		+ EconomySystem.crew_salary_per_battle()
	var dialog := DismissalDialog.new()
	add_child_autofree(dialog)
	dialog.setup()

	var confirm: Button = _find_buttons(dialog, "Launch battle", [])[0]
	assert_true(confirm.disabled, "Confirm is locked while upkeep is unaffordable")

	# Dismiss one fighter; the remaining hull's upkeep now fits the budget.
	_find_buttons(dialog, "Dismiss ship", [])[0].pressed.emit()

	assert_false(confirm.disabled,
		"Confirm unlocks once the remaining fleet's upkeep is affordable")


func test_dialog_confirm_emits_resolved_launched():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	RoguelikeRun.money = 1000000  # already affordable
	var dialog := DismissalDialog.new()
	add_child_autofree(dialog)
	dialog.setup()
	var captured := {"emitted": false, "launched": false}
	dialog.resolved.connect(func(launched: bool):
		captured.emitted = true
		captured.launched = launched)

	_find_buttons(dialog, "Launch battle", [])[0].pressed.emit()

	assert_true(captured.emitted, "Confirming the dialog emits resolved")
	assert_true(captured.launched, "...signalling the map to launch the battle")
