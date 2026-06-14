extends GutTest

## Behavior tests for per-crew orders (plan 05):
## - SkirmishFleet doctrine persistence
## - current_doctrine() routing
## - Skirmish spawn compiles per-crew patterns
## - Role gating on template offers
## - add / remove instruction round-trips

const DOCTRINE_SAVE_PATH := "user://skirmish_doctrine.json"
const PILOT_TEMPLATE := "charge_head_on"
const GUNNER_TEMPLATE := "finish_damaged_targets"

var _saved_run_state: Dictionary


func before_each() -> void:
	_saved_run_state = {
		"active": RoguelikeRun.active,
		"fleet_hulls": RoguelikeRun.fleet_hulls.duplicate(true),
		"doctrine": RoguelikeRun.doctrine.duplicate(true),
	}
	_delete_if_exists(DOCTRINE_SAVE_PATH)


func after_each() -> void:
	RoguelikeRun.active = _saved_run_state.active
	RoguelikeRun.fleet_hulls = _saved_run_state.fleet_hulls
	RoguelikeRun.doctrine = _saved_run_state.doctrine
	_delete_if_exists(DOCTRINE_SAVE_PATH)
	# Remove any doctrine patterns compiled during the test.
	for pattern_id: String in TacticalKnowledgeSystem.knowledge_base.keys():
		if pattern_id.begins_with(DoctrineSystem.DOCTRINE_PATTERN_PREFIX):
			TacticalKnowledgeSystem.knowledge_base.erase(pattern_id)
	TacticalKnowledgeSystem._query_cache.clear()


# SKIRMISHFLEET DOCTRINE PERSISTENCE

func test_skirmish_doctrine_persists_across_save_and_reload() -> void:
	"""set_instruction + set_doctrine then get_doctrine returns the instruction."""
	var pilot := CrewData.create_crew_member(CrewData.Role.PILOT, 1.0)
	var doctrine: Dictionary = DoctrineSystem.empty_doctrine()
	DoctrineSystem.set_instruction_in_place(
		doctrine, DoctrineSystem.SCOPE_CREW, pilot.crew_id, PILOT_TEMPLATE)
	SkirmishFleet.set_doctrine(doctrine)

	var loaded: Dictionary = SkirmishFleet.get_doctrine()
	assert_true(
		loaded[DoctrineSystem.SCOPE_CREW].has(pilot.crew_id),
		"crew_id key must survive save/reload")
	assert_true(
		loaded[DoctrineSystem.SCOPE_CREW][pilot.crew_id].has(PILOT_TEMPLATE),
		"template_id must survive save/reload")


func test_get_doctrine_returns_empty_doctrine_when_no_file() -> void:
	"""get_doctrine with no save file returns empty_doctrine shape."""
	var result: Dictionary = SkirmishFleet.get_doctrine()
	assert_true(result.has(DoctrineSystem.SCOPE_FLEET), "has fleet key")
	assert_true(result.has(DoctrineSystem.SCOPE_CREW), "has crew key")
	assert_true(result[DoctrineSystem.SCOPE_CREW].is_empty(), "crew scope is empty")


# CURRENT_DOCTRINE ROUTING

func test_current_doctrine_returns_skirmish_store_when_no_run_active() -> void:
	"""With no roguelite run, current_doctrine() returns from the skirmish file."""
	RoguelikeRun.active = false
	var doctrine: Dictionary = DoctrineSystem.empty_doctrine()
	doctrine[DoctrineSystem.SCOPE_FLEET]["marker"] = {}
	SkirmishFleet.set_doctrine(doctrine)

	var result: Dictionary = SkirmishFleet.current_doctrine()
	assert_true(result[DoctrineSystem.SCOPE_FLEET].has("marker"),
		"current_doctrine should return the skirmish store when no run is active")


func test_current_doctrine_returns_run_doctrine_when_run_active() -> void:
	"""With an active roguelite run, current_doctrine() returns RoguelikeRun.doctrine."""
	RoguelikeRun.active = true
	RoguelikeRun.doctrine = DoctrineSystem.empty_doctrine()
	RoguelikeRun.doctrine[DoctrineSystem.SCOPE_FLEET]["run_marker"] = {}

	# Skirmish store has different content.
	var skirmish_doc: Dictionary = DoctrineSystem.empty_doctrine()
	skirmish_doc[DoctrineSystem.SCOPE_FLEET]["skirmish_marker"] = {}
	SkirmishFleet.set_doctrine(skirmish_doc)

	var result: Dictionary = SkirmishFleet.current_doctrine()
	assert_true(result[DoctrineSystem.SCOPE_FLEET].has("run_marker"),
		"current_doctrine should return run doctrine when active")
	assert_false(result[DoctrineSystem.SCOPE_FLEET].has("skirmish_marker"),
		"current_doctrine must not return skirmish store during a run")


# SKIRMISH SPAWN COMPILES DOCTRINE

func test_skirmish_compile_for_crew_applies_pilot_instruction() -> void:
	"""compile_for_crew with a skirmish pilot instruction lands a known_pattern."""
	var pilot := CrewData.create_crew_member(CrewData.Role.PILOT, 1.0)
	var doctrine: Dictionary = DoctrineSystem.empty_doctrine()
	DoctrineSystem.set_instruction_in_place(
		doctrine, DoctrineSystem.SCOPE_CREW, pilot.crew_id, PILOT_TEMPLATE)

	var compiled: Dictionary = DoctrineSystem.compile_for_crew(pilot, "fighter", doctrine)
	var doctrine_ids: Array = _doctrine_ids(compiled)

	assert_eq(doctrine_ids.size(), 1,
		"A pilot instruction should land exactly one doctrine pattern")
	assert_true(
		doctrine_ids[0].contains(PILOT_TEMPLATE),
		"The compiled pattern id should reference the template")


func test_roguelite_compile_path_unchanged() -> void:
	"""compile_for_crew with RoguelikeRun.doctrine still works (regression guard)."""
	RoguelikeRun.active = true
	RoguelikeRun.doctrine = DoctrineSystem.empty_doctrine()
	var pilot := CrewData.create_crew_member(CrewData.Role.PILOT, 1.0)
	DoctrineSystem.set_instruction_in_place(
		RoguelikeRun.doctrine, DoctrineSystem.SCOPE_FLEET, "", PILOT_TEMPLATE)

	var compiled: Dictionary = DoctrineSystem.compile_for_crew(
		pilot, "fighter", RoguelikeRun.doctrine)
	assert_gt(_doctrine_ids(compiled).size(), 0,
		"Roguelite compile path must still add doctrine patterns")


# ROLE GATING
# Tested via DoctrineSystem directly: the role filter is the source of truth
# and determines whether the Orders section appears in the popup.

func _templates_for_role(role_int: int) -> Array:
	"""Return template_ids applicable to role_int (mirrors CrewViewModal logic)."""
	var result: Array = []
	for template_id: String in DoctrineSystem.get_all_templates():
		var template: Dictionary = DoctrineSystem.get_template(template_id)
		if TacticalKnowledgeSystem.ROLE_NAMES.get(template.get("role", ""), -1) == role_int:
			result.append(template_id)
	return result


func test_pilot_templates_offered_only_for_pilots() -> void:
	"""Templates for pilots are not offered to gunners and vice versa."""
	var pilot_templates: Array = _templates_for_role(CrewData.Role.PILOT)
	var gunner_templates: Array = _templates_for_role(CrewData.Role.GUNNER)

	assert_true(pilot_templates.has(PILOT_TEMPLATE),
		"charge_head_on should be in pilot templates")
	assert_false(gunner_templates.has(PILOT_TEMPLATE),
		"charge_head_on must not appear in gunner templates")
	assert_true(gunner_templates.has(GUNNER_TEMPLATE),
		"finish_damaged_targets should be in gunner templates")
	assert_false(pilot_templates.has(GUNNER_TEMPLATE),
		"finish_damaged_targets must not appear in pilot templates")


func test_role_with_no_templates_returns_empty() -> void:
	"""An engineer or captain role returns an empty template list (no Orders section)."""
	assert_true(_templates_for_role(CrewData.Role.ENGINEER).is_empty(),
		"Engineer role has no applicable templates")
	assert_true(_templates_for_role(CrewData.Role.CAPTAIN).is_empty(),
		"Captain role has no applicable templates")


# ADD / REMOVE ROUND-TRIP

func test_add_then_remove_instruction_round_trips_in_store() -> void:
	"""set_instruction then remove_instruction leaves the crew entry clean."""
	var pilot := CrewData.create_crew_member(CrewData.Role.PILOT, 1.0)
	var doctrine: Dictionary = DoctrineSystem.empty_doctrine()

	DoctrineSystem.set_instruction_in_place(
		doctrine, DoctrineSystem.SCOPE_CREW, pilot.crew_id, PILOT_TEMPLATE)
	assert_true(
		doctrine[DoctrineSystem.SCOPE_CREW].has(pilot.crew_id),
		"Instruction should be stored after add")

	DoctrineSystem.remove_instruction_in_place(
		doctrine, DoctrineSystem.SCOPE_CREW, pilot.crew_id, PILOT_TEMPLATE)
	var crew_entry: Dictionary = doctrine[DoctrineSystem.SCOPE_CREW].get(pilot.crew_id, {})
	assert_false(crew_entry.has(PILOT_TEMPLATE),
		"Template id should be absent after remove")


func test_add_remove_persists_through_skirmish_store() -> void:
	"""Adding then removing via set_doctrine/get_doctrine leaves clean state on reload."""
	var pilot := CrewData.create_crew_member(CrewData.Role.PILOT, 1.0)
	var doctrine: Dictionary = DoctrineSystem.empty_doctrine()
	DoctrineSystem.set_instruction_in_place(
		doctrine, DoctrineSystem.SCOPE_CREW, pilot.crew_id, PILOT_TEMPLATE)
	SkirmishFleet.set_doctrine(doctrine)

	var loaded: Dictionary = SkirmishFleet.get_doctrine()
	DoctrineSystem.remove_instruction_in_place(
		loaded, DoctrineSystem.SCOPE_CREW, pilot.crew_id, PILOT_TEMPLATE)
	SkirmishFleet.set_doctrine(loaded)

	var reloaded: Dictionary = SkirmishFleet.get_doctrine()
	var crew_entry: Dictionary = reloaded[DoctrineSystem.SCOPE_CREW].get(pilot.crew_id, {})
	assert_false(crew_entry.has(PILOT_TEMPLATE),
		"Removed instruction must not reappear after a second save/reload cycle")


# Helpers

func _doctrine_ids(crew: Dictionary) -> Array:
	"""Extract the doctrine-namespaced pattern ids from a compiled crew member."""
	var ids: Array = []
	for pattern_id: String in crew.known_patterns:
		if pattern_id.begins_with(DoctrineSystem.DOCTRINE_PATTERN_PREFIX):
			ids.append(pattern_id)
	return ids


func _delete_if_exists(path: String) -> void:
	"""Delete a user:// file if it exists."""
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_scope_view_surfaces_a_crews_personal_orders() -> void:
	# Regression: scope_view had no SCOPE_CREW branch, so a crew's own orders
	# were never returned and the Orders list always rendered empty.
	var doctrine: Dictionary = DoctrineSystem.empty_doctrine()
	DoctrineSystem.set_instruction_in_place(
		doctrine, DoctrineSystem.SCOPE_CREW, "crew_x", PILOT_TEMPLATE, {})
	var view: Array = DoctrineSystem.scope_view(
		doctrine, DoctrineSystem.SCOPE_CREW, "crew_x")
	assert_eq(view.size(), 1, "crew's own instruction is visible in its scope view")
	var other: Array = DoctrineSystem.scope_view(
		doctrine, DoctrineSystem.SCOPE_CREW, "crew_other")
	assert_eq(other.size(), 0, "a different crew sees none of crew_x's orders")
