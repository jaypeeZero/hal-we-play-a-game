extends GutTest

## CrewData.role_of / roles_of — the one normalization point for a crew member's
## role across every shape that has caused "Unknown role" / -1 bugs:
## live crew dict (int), JSON-loaded crew (float), and roster entry (name array).

func test_role_of_reads_int_role_from_crew_dict() -> void:
	assert_eq(CrewData.role_of({"role": CrewData.Role.GUNNER}), CrewData.Role.GUNNER)


func test_role_of_coerces_float_role_from_json_loaded_crew() -> void:
	# JSON loads enum ints as floats (2.0); role_of must still resolve them.
	assert_eq(CrewData.role_of({"role": 2.0}), 2)


func test_role_of_reads_name_array_from_roster_entry() -> void:
	# A roster entry has no `role` int — only a `roles` name array.
	assert_eq(CrewData.role_of({"roles": ["gunner"]}), CrewData.Role.GUNNER)


func test_role_of_defaults_to_pilot_for_missing_or_unknown() -> void:
	assert_eq(CrewData.role_of({}), CrewData.Role.PILOT, "missing role → pilot")
	assert_eq(CrewData.role_of({"role": 999}), CrewData.Role.PILOT, "out-of-range → pilot")
	assert_eq(CrewData.role_of({"roles": ["wizard"]}), CrewData.Role.PILOT, "unknown name → pilot")


func test_role_of_never_returns_unknown_role_name() -> void:
	# The bug class: a stray -1 rendered as "Unknown". role_of forbids it.
	for sample in [{}, {"role": -1}, {"role": 42}, {"roles": []}, {"roles": ["bogus"]}]:
		var name := CrewData.get_role_name(CrewData.role_of(sample))
		assert_ne(name, "Unknown", "role_of must resolve %s to a known role" % str(sample))


func test_roles_of_reads_qualified_roles_then_falls_back() -> void:
	assert_eq(CrewData.roles_of({"qualified_roles": [0, 1]}), [0, 1])
	# Roster entry: qualified roles come from the name array.
	assert_true(CrewData.roles_of({"roles": ["gunner", "pilot"]}).has(CrewData.Role.GUNNER))
	# Bare crew dict: falls back to the serving role.
	assert_eq(CrewData.roles_of({"role": CrewData.Role.ENGINEER}), [CrewData.Role.ENGINEER])
