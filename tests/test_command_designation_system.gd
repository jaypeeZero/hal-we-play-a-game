extends GutTest

## Tests for CommandDesignationSystem — command hat designation.
##
## Tests cover behavior only: hat assignment, subordinate lists, immutability.
## No specific data values are asserted; all assertions are structural.


# ── Helpers ──────────────────────────────────────────────────────────────────

## Minimal fighter ship — no armor sections (integrity = 0).
func make_fighter(id: String, team: int = 0) -> Dictionary:
	return {
		"ship_id": id,
		"type": "fighter",
		"team": team,
		"status": "operational",
		"armor_sections": [],
		"position": Vector2.ZERO,
	}

## Ship with a specific hull class (and optional armor for integrity).
func make_ship(id: String, type: String, team: int = 0, armor: int = 0) -> Dictionary:
	var sections := []
	if armor > 0:
		sections = [{"section_id": "front", "current_armor": armor, "max_armor": armor}]
	return {
		"ship_id": id,
		"type": type,
		"team": team,
		"status": "operational",
		"armor_sections": sections,
		"position": Vector2.ZERO,
	}

## Pilot crew member (PILOT role).
func make_pilot(id: String, ship_id: String, skill: float = 0.5) -> Dictionary:
	return {
		"crew_id": id,
		"role": CrewData.Role.PILOT,
		"assigned_to": ship_id,
		"stats": {"skills": {"piloting": skill}},
		"command_chain": {"superior": null, "subordinates": []},
	}

## Captain crew member (CAPTAIN role).
func make_captain(id: String, ship_id: String) -> Dictionary:
	return {
		"crew_id": id,
		"role": CrewData.Role.CAPTAIN,
		"assigned_to": ship_id,
		"stats": {"skills": {"piloting": 0.3}},
		"command_chain": {"superior": null, "subordinates": []},
	}

## Wing dict shaped like WingFormationSystem output.
func make_wing(lead_crew_id: String, lead_ship_id: String, team: int, wingmen: Array) -> Dictionary:
	return {
		"lead_crew_id": lead_crew_id,
		"lead_ship_id": lead_ship_id,
		"team": team,
		"wingmen": wingmen,
	}

## Wingman entry in a wing.
func make_wingman(crew_id: String, ship_id: String) -> Dictionary:
	return {"crew_id": crew_id, "ship_id": ship_id}

## Find crew by id in a result list.
func find_crew(result: Array, crew_id: String) -> Dictionary:
	for c in result:
		if c.get("crew_id", "") == crew_id:
			return c
	return {}


# ── Tests ────────────────────────────────────────────────────────────────────

func test_wing_lead_gets_squadron_leader_hat_and_wingmen_as_subordinates():
	var ships := [make_fighter("s1", 0), make_fighter("s2", 0)]
	var crew  := [make_pilot("p1", "s1", 0.8), make_pilot("p2", "s2", 0.5)]
	var wings := [make_wing("p1", "s1", 0, [make_wingman("p2", "s2")])]

	var result := CommandDesignationSystem.designate(crew, ships, wings)

	var lead := find_crew(result, "p1")
	assert_eq(lead.get("command_hat", ""), "squadron_leader",
		"Wing lead should receive the squadron_leader hat")
	assert_true(lead.get("command_chain", {}).get("subordinates", []).has("p2"),
		"Wing lead's subordinates should contain the wingman crew_id")

	var wingman := find_crew(result, "p2")
	assert_eq(wingman.get("command_hat", ""), "",
		"Wingman should not receive a command hat")


func test_captain_of_highest_class_ship_gets_commander_hat():
	# Team has a capital (rank 5) and a corvette (rank 4).
	var ships := [
		make_ship("s_cap", "capital",  0),
		make_ship("s_cor", "corvette", 0),
	]
	var crew := [
		make_captain("cap_captain", "s_cap"),
		make_captain("cor_captain", "s_cor"),
	]
	var wings: Array = []

	var result := CommandDesignationSystem.designate(crew, ships, wings)

	var commander := find_crew(result, "cap_captain")
	assert_eq(commander.get("command_hat", ""), "commander",
		"Captain of the capital (highest class) should get the commander hat")

	var other := find_crew(result, "cor_captain")
	assert_ne(other.get("command_hat", ""), "commander",
		"Captain of the lower-class ship must not get the commander hat")


func test_capital_wins_over_corvette_and_tie_broken_by_integrity():
	# Two capitals — one with higher armor integrity wins the tie-break.
	var ships := [
		make_ship("s_low",  "capital", 0, 50),
		make_ship("s_high", "capital", 0, 200),
	]
	var crew := [
		make_captain("cap_low",  "s_low"),
		make_captain("cap_high", "s_high"),
	]
	var wings: Array = []

	var result := CommandDesignationSystem.designate(crew, ships, wings)

	var winner := find_crew(result, "cap_high")
	assert_eq(winner.get("command_hat", ""), "commander",
		"Capital with higher armor integrity should be the flagship and its captain Commander")

	var loser := find_crew(result, "cap_low")
	assert_ne(loser.get("command_hat", ""), "commander",
		"Capital with lower armor integrity must not be Commander")


func test_all_fighter_team_designates_best_pilot_as_fleet_commander():
	# No captain on the team — best wing lead becomes fleet commander.
	var ships := [make_fighter("s1", 0), make_fighter("s2", 0)]
	var crew  := [make_pilot("p_best", "s1", 0.9), make_pilot("p_other", "s2", 0.4)]
	var wings := [make_wing("p_best", "s1", 0, [make_wingman("p_other", "s2")])]

	var result := CommandDesignationSystem.designate(crew, ships, wings)

	var best := find_crew(result, "p_best")
	assert_true(best.get("is_fleet_commander", false),
		"Best pilot wing lead should be flagged as fleet commander")
	# Hat stays squadron_leader, not overwritten.
	assert_eq(best.get("command_hat", ""), "squadron_leader",
		"Dual-role pilot retains the squadron_leader hat")


func test_crew_losing_leadership_has_hat_cleared_on_redesignation():
	# First pass: p1 is wing lead.
	var ships := [make_fighter("s1", 0), make_fighter("s2", 0)]
	var crew  := [make_pilot("p1", "s1", 0.8), make_pilot("p2", "s2", 0.5)]
	var wings_first := [make_wing("p1", "s1", 0, [make_wingman("p2", "s2")])]

	var after_first := CommandDesignationSystem.designate(crew, ships, wings_first)
	var p1_first := find_crew(after_first, "p1")
	assert_eq(p1_first.get("command_hat", ""), "squadron_leader",
		"p1 should be squadron_leader after first designation")

	# Second pass: wing dissolved (no wings), p1 loses lead role.
	var wings_empty: Array = []
	var after_second := CommandDesignationSystem.designate(after_first, ships, wings_empty)

	var p1_second := find_crew(after_second, "p1")
	assert_eq(p1_second.get("command_hat", ""), "",
		"p1 hat should be cleared when its wing is dissolved on re-designation")


func test_designate_does_not_mutate_input_crew_list():
	var ships := [make_fighter("s1", 0), make_fighter("s2", 0)]
	var crew  := [make_pilot("p1", "s1", 0.8), make_pilot("p2", "s2", 0.5)]
	var wings := [make_wing("p1", "s1", 0, [make_wingman("p2", "s2")])]

	# Snapshot input state.
	var original_hat_p1: String = crew[0].get("command_hat", "<unset>")
	var original_subs_p1: Array = crew[0].get("command_chain", {}).get("subordinates", []).duplicate()

	CommandDesignationSystem.designate(crew, ships, wings)

	# Input must be unchanged.
	assert_eq(crew[0].get("command_hat", "<unset>"), original_hat_p1,
		"designate must not mutate command_hat on input crew")
	var subs_after: Array = crew[0].get("command_chain", {}).get("subordinates", [])
	assert_eq(subs_after, original_subs_p1,
		"designate must not mutate command_chain.subordinates on input crew")
