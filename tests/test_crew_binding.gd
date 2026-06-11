extends GutTest

## Tests for CrewData.bind_gunners_to_weapons - FUNCTIONALITY ONLY.
## Gunners are bound to weapons (from the end of the array backwards) so a
## destroyed mount can kill exactly the gunner who manned it; pilots and
## captains stay unbound; the binding persists across a battle reset.

func _crew(role: int, id: String) -> Dictionary:
	return {"role": role, "crew_id": id}


func _weapons(ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		out.append({"weapon_id": id})
	return out


func test_each_gunner_binds_to_a_distinct_weapon():
	var crew := [
		_crew(CrewData.Role.CAPTAIN, "cap"),
		_crew(CrewData.Role.PILOT, "pil"),
		_crew(CrewData.Role.GUNNER, "g1"),
		_crew(CrewData.Role.GUNNER, "g2"),
	]

	CrewData.bind_gunners_to_weapons(crew, _weapons(["w1", "w2"]))

	var bound: Array = []
	for member in crew:
		if member.role == CrewData.Role.GUNNER:
			assert_true(member.has("weapon_id"), "Every gunner with a weapon should be bound")
			bound.append(member.weapon_id)
	assert_eq(bound.size(), 2, "Both gunners should bind")
	assert_ne(bound[0], bound[1], "No two gunners should share a weapon")


func test_pilots_and_captains_are_left_unbound():
	var crew := [
		_crew(CrewData.Role.CAPTAIN, "cap"),
		_crew(CrewData.Role.PILOT, "pil"),
		_crew(CrewData.Role.GUNNER, "g1"),
	]

	CrewData.bind_gunners_to_weapons(crew, _weapons(["w1"]))

	assert_false(crew[0].has("weapon_id"), "Captains do not man a specific gun")
	assert_false(crew[1].has("weapon_id"), "Pilots do not man a specific gun")


func test_lone_gunner_takes_the_rear_weapon():
	# Heavy-fighter shape: pilot works the forward guns, the single gunner mans
	# the rear turret (last in the weapons array).
	var crew := [
		_crew(CrewData.Role.PILOT, "pil"),
		_crew(CrewData.Role.GUNNER, "g1"),
	]

	CrewData.bind_gunners_to_weapons(crew, _weapons(["front_guns", "rear_turret"]))

	assert_eq(crew[1].weapon_id, "rear_turret",
		"A lone gunner binds to the rear/secondary weapon")


func test_extra_gunners_stay_unbound():
	var crew := [
		_crew(CrewData.Role.GUNNER, "g1"),
		_crew(CrewData.Role.GUNNER, "g2"),
	]

	CrewData.bind_gunners_to_weapons(crew, _weapons(["only"]))

	var bound := 0
	for member in crew:
		if member.has("weapon_id"):
			bound += 1
	assert_eq(bound, 1, "With one weapon, only one gunner can be bound")


func test_weapon_binding_survives_a_battle_reset():
	var saved := CrewData.create_crew_member(CrewData.Role.GUNNER)
	saved["weapon_id"] = "rear_turret"

	var restored := CrewData.reset_for_battle(saved)

	assert_eq(restored.get("weapon_id", ""), "rear_turret",
		"A gunner's weapon binding is persistent identity across battles")
