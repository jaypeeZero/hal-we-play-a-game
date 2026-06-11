extends GutTest

## Tests for CasualtySystem - FUNCTIONALITY ONLY.
## Crew die from components destroyed *this* battle: a gunner with their gun's
## mount, an engineer rolling against each engine/mount loss (machinery skill
## is their shield). Pre-existing destruction kills no one. Seeded RNG keeps
## the probabilistic tests deterministic.

func _seeded_rng(s: int = 1) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	return rng


func _mount(weapon_id: String, status: String) -> Dictionary:
	return {
		"component_id": "mount_%s" % weapon_id, "type": "weapon_mount",
		"weapon_id": weapon_id, "status": status,
	}


func _engine(id: String, status: String) -> Dictionary:
	return {"component_id": id, "type": "engine", "status": status}


func _ship(internals: Array) -> Dictionary:
	return {"internals": internals}


func _gunner(weapon_id: String) -> Dictionary:
	return {"role": CrewData.Role.GUNNER, "crew_id": "g_%s" % weapon_id, "weapon_id": weapon_id}


func _engineer(machinery: float) -> Dictionary:
	return {"role": CrewData.Role.ENGINEER, "crew_id": "eng",
		"stats": {"skills": {"machinery": machinery}}}


func _has_crew(list: Array, crew_id: String) -> bool:
	for member in list:
		if member.get("crew_id", "") == crew_id:
			return true
	return false


# ============================================================================
# NEWLY DESTROYED DIFF
# ============================================================================

func test_diff_counts_only_new_destruction():
	var before := _ship([_mount("a", "destroyed"), _engine("e", "operational")])
	var after := _ship([_mount("a", "destroyed"), _engine("e", "destroyed")])

	var newly := CasualtySystem.newly_destroyed_components(before, after)

	var ids: Array = newly.map(func(c): return c.component_id)
	assert_eq(newly.size(), 1, "Only the engine newly failed this battle")
	assert_true("e" in ids, "The engine destroyed this battle should be counted")
	assert_false("mount_a" in ids, "A mount already destroyed before the battle is not re-counted")


# ============================================================================
# GUNNER CASUALTIES
# ============================================================================

func test_gunner_dies_when_their_mount_is_newly_destroyed():
	var before := _ship([_mount("a", "operational")])
	var after := _ship([_mount("a", "destroyed")])

	var result := CasualtySystem.resolve_hull_casualties([_gunner("a")], before, after, _seeded_rng())

	assert_true(_has_crew(result.deaths, "g_a"), "A gunner dies with their gun's mount")
	assert_false(_has_crew(result.survivors, "g_a"), "...and is not among the survivors")


func test_gunner_survives_when_their_mount_is_intact():
	var ship := _ship([_mount("a", "operational")])

	var result := CasualtySystem.resolve_hull_casualties([_gunner("a")], ship, ship, _seeded_rng())

	assert_true(_has_crew(result.survivors, "g_a"), "A gunner whose mount survives lives")


func test_gunner_survives_when_a_different_mount_is_destroyed():
	var before := _ship([_mount("a", "operational"), _mount("b", "operational")])
	var after := _ship([_mount("a", "operational"), _mount("b", "destroyed")])

	var result := CasualtySystem.resolve_hull_casualties([_gunner("a")], before, after, _seeded_rng())

	assert_true(_has_crew(result.survivors, "g_a"),
		"Losing another gun's mount does not kill this gunner")


func test_predestroyed_mount_kills_no_gunner():
	var before := _ship([_mount("a", "destroyed")])
	var after := _ship([_mount("a", "destroyed")])

	var result := CasualtySystem.resolve_hull_casualties([_gunner("a")], before, after, _seeded_rng())

	assert_true(_has_crew(result.survivors, "g_a"),
		"A mount destroyed in a previous battle does not kill its gunner again")


# ============================================================================
# ENGINEER CASUALTIES (machinery skill)
# ============================================================================

func test_maxed_machinery_engineer_never_dies():
	var before := _ship([_engine("e", "operational")])
	var after := _ship([_engine("e", "destroyed")])

	var deaths := 0
	for seed in range(50):
		var result := CasualtySystem.resolve_hull_casualties(
			[_engineer(1.0)], before, after, _seeded_rng(seed))
		deaths += result.deaths.size()

	assert_eq(deaths, 0, "An engineer with maxed machinery survives every component loss")


func test_unskilled_engineer_sometimes_dies():
	var before := _ship([_engine("e", "operational")])
	var after := _ship([_engine("e", "destroyed")])

	var deaths := 0
	for seed in range(50):
		var result := CasualtySystem.resolve_hull_casualties(
			[_engineer(0.0)], before, after, _seeded_rng(seed))
		deaths += result.deaths.size()

	assert_gt(deaths, 0,
		"A zero-machinery engineer is sometimes killed when a component explodes")


func test_engineer_with_no_new_destruction_survives():
	var ship := _ship([_engine("e", "operational")])

	var result := CasualtySystem.resolve_hull_casualties([_engineer(0.0)], ship, ship, _seeded_rng())

	assert_true(_has_crew(result.survivors, "eng"),
		"With nothing destroyed this battle, even an unskilled engineer is safe")


# ============================================================================
# NON-COMBAT ROLES
# ============================================================================

func test_pilots_and_captains_survive_a_surviving_hull():
	var before := _ship([_engine("e", "operational"), _mount("a", "operational")])
	var after := _ship([_engine("e", "destroyed"), _mount("a", "destroyed")])
	var crew := [
		{"role": CrewData.Role.PILOT, "crew_id": "pilot"},
		{"role": CrewData.Role.CAPTAIN, "crew_id": "captain"},
	]

	var result := CasualtySystem.resolve_hull_casualties(crew, before, after, _seeded_rng())

	assert_eq(result.deaths.size(), 0,
		"Pilots and captains aboard a surviving hull are never casualties")
