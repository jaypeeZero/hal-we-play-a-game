extends GutTest

## Behavior tests for CrewFit — the pure crew vacancy / role-match rules.
## Tests are constructed from synthetic hull and crew dicts; no game state needed.


# --- vacant_slots ---

func test_vacant_slots_empty_hull_has_all_slots_vacant() -> void:
	"""A hull with no crew reports all complement slots as vacant."""
	var hull: Dictionary = _hull_with_crew([], [_slot(CrewData.Role.PILOT), _slot(CrewData.Role.GUNNER, "gun_1")])
	var vacancies: Array = CrewFit.vacant_slots(hull)
	assert_eq(vacancies.size(), 2, "both slots vacant when no crew")


func test_vacant_slots_filled_pilot_slot_not_vacant() -> void:
	"""A pilot slot filled by a pilot crew member is not reported as vacant."""
	var pilot: Dictionary = _crew(CrewData.Role.PILOT, "c1")
	var hull: Dictionary = _hull_with_crew([pilot], [_slot(CrewData.Role.PILOT)])
	var vacancies: Array = CrewFit.vacant_slots(hull)
	assert_eq(vacancies.size(), 0, "no vacancies when pilot slot is filled")


func test_vacant_slots_gunner_matched_by_weapon_id() -> void:
	"""A gunner slot matched by weapon_id is not vacant even when another gunner is aboard."""
	var gunner1: Dictionary = _crew(CrewData.Role.GUNNER, "g1")
	gunner1["weapon_id"] = "gun_1"
	var hull: Dictionary = _hull_with_crew(
		[gunner1],
		[_slot(CrewData.Role.GUNNER, "gun_1"), _slot(CrewData.Role.GUNNER, "gun_2")])
	var vacancies: Array = CrewFit.vacant_slots(hull)
	assert_eq(vacancies.size(), 1, "only gun_2 slot is vacant")
	assert_eq(str(vacancies[0].get("weapon_id", "")), "gun_2", "vacant slot is gun_2")


func test_vacant_slots_role_count_matching() -> void:
	"""Two engineer slots — one filled, one vacant — report correctly."""
	var eng: Dictionary = _crew(CrewData.Role.ENGINEER, "e1")
	var hull: Dictionary = _hull_with_crew(
		[eng],
		[_slot(CrewData.Role.ENGINEER), _slot(CrewData.Role.ENGINEER)])
	var vacancies: Array = CrewFit.vacant_slots(hull)
	assert_eq(vacancies.size(), 1, "one engineer slot still vacant")


func test_vacant_slots_fully_crewed_hull_has_no_vacancies() -> void:
	"""A hull where every slot has a matching crew member reports no vacancies."""
	var pilot: Dictionary = _crew(CrewData.Role.PILOT, "p1")
	var eng: Dictionary = _crew(CrewData.Role.ENGINEER, "e1")
	var hull: Dictionary = _hull_with_crew(
		[pilot, eng],
		[_slot(CrewData.Role.PILOT), _slot(CrewData.Role.ENGINEER)])
	var vacancies: Array = CrewFit.vacant_slots(hull)
	assert_eq(vacancies.size(), 0, "no vacancies on fully crewed hull")


# --- can_fill ---

func test_can_fill_true_when_role_matches_vacant_slot() -> void:
	"""can_fill returns true when a crew's role matches a vacant slot."""
	var pilot: Dictionary = _crew(CrewData.Role.PILOT, "p1")
	var hull: Dictionary = _hull_with_crew([], [_slot(CrewData.Role.PILOT)])
	assert_true(CrewFit.can_fill(pilot, hull), "pilot can fill vacant pilot slot")


func test_can_fill_false_when_role_does_not_match() -> void:
	"""can_fill returns false when no vacant slot matches the crew's role."""
	var eng: Dictionary = _crew(CrewData.Role.ENGINEER, "e1")
	var hull: Dictionary = _hull_with_crew([], [_slot(CrewData.Role.PILOT)])
	assert_false(CrewFit.can_fill(eng, hull), "engineer cannot fill a pilot-only slot")


func test_can_fill_false_when_all_slots_filled() -> void:
	"""can_fill returns false when the hull has no vacancies at all."""
	var pilot1: Dictionary = _crew(CrewData.Role.PILOT, "p1")
	var pilot2: Dictionary = _crew(CrewData.Role.PILOT, "p2")
	var hull: Dictionary = _hull_with_crew([pilot1], [_slot(CrewData.Role.PILOT)])
	assert_false(CrewFit.can_fill(pilot2, hull), "no vacancy for another pilot")


# --- can_swap_members ---

func test_can_swap_true_when_same_role_different_hulls() -> void:
	"""can_swap_members returns true for two crew of the same role on different hulls."""
	var a: Dictionary = _crew(CrewData.Role.PILOT, "p1")
	var b: Dictionary = _crew(CrewData.Role.PILOT, "p2")
	assert_true(CrewFit.can_swap_members(a, b, "hull_0", "hull_1"), "same-role swap allowed")


func test_can_swap_false_when_different_roles() -> void:
	"""can_swap_members returns false when roles differ."""
	var pilot: Dictionary = _crew(CrewData.Role.PILOT, "p1")
	var eng: Dictionary = _crew(CrewData.Role.ENGINEER, "e1")
	assert_false(CrewFit.can_swap_members(pilot, eng, "hull_0", "hull_1"), "cross-role swap forbidden")


func test_can_swap_false_when_same_hull() -> void:
	"""can_swap_members returns false when both crew are on the same hull."""
	var a: Dictionary = _crew(CrewData.Role.PILOT, "p1")
	var b: Dictionary = _crew(CrewData.Role.PILOT, "p2")
	assert_false(CrewFit.can_swap_members(a, b, "hull_0", "hull_0"), "same-hull swap forbidden")


func test_can_swap_false_when_either_member_empty() -> void:
	"""can_swap_members returns false when either dict is empty."""
	var pilot: Dictionary = _crew(CrewData.Role.PILOT, "p1")
	assert_false(CrewFit.can_swap_members(pilot, {}, "hull_0", "hull_1"), "empty member b")
	assert_false(CrewFit.can_swap_members({}, pilot, "hull_0", "hull_1"), "empty member a")


# --- Helpers ---

func _crew(role: int, crew_id: String) -> Dictionary:
	"""Minimal crew dict for testing."""
	return {"crew_id": crew_id, "role": role, "qualified_roles": [role]}


func _slot(role: int, weapon_id: String = "") -> Dictionary:
	"""A complement slot dict."""
	var s: Dictionary = {"role": role}
	if weapon_id != "":
		s["weapon_id"] = weapon_id
	return s


func _hull_with_crew(crew: Array, complement: Array) -> Dictionary:
	"""Minimal hull dict for testing."""
	return {
		"hull_id": "test_hull",
		"ship_type": "fighter",
		"crew": crew,
		"complement": complement,
	}
