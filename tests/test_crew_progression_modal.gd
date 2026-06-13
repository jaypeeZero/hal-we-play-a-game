extends GutTest

## Behavior tests for CrewProgressionModal.

var _modal: CrewProgressionModal
var _saved_fleet_hulls: Array


func before_each() -> void:
	_saved_fleet_hulls = RoguelikeRun.fleet_hulls.duplicate(true)


func after_each() -> void:
	if _modal != null and is_instance_valid(_modal):
		_modal.queue_free()
	_modal = null
	RoguelikeRun.fleet_hulls = _saved_fleet_hulls


func _make_crew_member(role: int, crew_id: String, callsign: String) -> Dictionary:
	var skills := {}
	for name in CrewData.SKILL_NAMES:
		skills[name] = 0.6
	return {
		"crew_id": crew_id,
		"callsign": callsign,
		"role": role,
		"qualified_roles": [role],
		"stats": {"skills": skills},
		"command_chain": {"superior": null, "subordinates": []},
		"known_patterns": [],
		"awareness": {"known_entities": [], "last_update": 0.0, "threats": [], "opportunities": [],
			"tactical_memory": {"recent_events": [], "successful_tactics": {}, "failed_tactics": {}, "current_situation": ""}},
		"combat_state": {"locked_target_id": "", "lock_start_time": 0.0},
		"orders": {"received": null, "current": null, "issued": []},
		"next_decision_time": 0.0,
		"current_action": null,
	}


func _make_record(crew_id: String, callsign: String, skill_deltas: Array, mentor := "") -> Dictionary:
	return {
		"crew_id": crew_id,
		"callsign": callsign,
		"role": CrewData.Role.PILOT,
		"hull_id": "h1",
		"ship_type": "fighter",
		"commander_callsign": "",
		"coach_mult": 1.0,
		"skills": skill_deltas,
	}


func _count_labels_with_text(node: Node, text: String) -> int:
	var count := 0
	if node is Label and str(node.text).contains(text):
		count += 1
	for child in node.get_children():
		count += _count_labels_with_text(child, text)
	return count


func _has_child_of_class(node: Node, class_name_str: String) -> bool:
	if node.get_class() == class_name_str or node.get_script() != null:
		# Check via class_name
		pass
	for child in node.get_children():
		if child is CrewMemberView:
			return true
		if _has_child_of_class(child, class_name_str):
			return true
	return false


func _find_crew_member_views(node: Node) -> Array:
	var found := []
	if node is CrewMemberView:
		found.append(node)
	for child in node.get_children():
		found.append_array(_find_crew_member_views(child))
	return found


# --- Opens and lists changed skills ---

func test_modal_shows_skill_delta_rows() -> void:
	var record := _make_record("c1", "Ace", [
		{"skill": "piloting", "before": 0.50, "after": 0.51, "delta": 0.01,
		 "source": "used", "mentor_callsign": ""},
		{"skill": "awareness", "before": 0.40, "after": 0.41, "delta": 0.01,
		 "source": "used", "mentor_callsign": ""},
	])

	_modal = CrewProgressionModal.new()
	add_child_autofree(_modal)
	_modal.setup(record)
	await get_tree().process_frame

	assert_true(_count_labels_with_text(_modal, "Piloting") > 0,
		"Modal should show a row for piloting delta")
	assert_true(_count_labels_with_text(_modal, "Awareness") > 0,
		"Modal should show a row for awareness delta")


# --- Embeds crew sheet ---

func test_modal_embeds_crew_member_view_when_hull_available() -> void:
	var member := _make_crew_member(CrewData.Role.PILOT, "c1", "Ace")
	RoguelikeRun.fleet_hulls = [{"hull_id": "h1", "ship_type": "fighter", "crew": [member]}]

	var record := _make_record("c1", "Ace", [
		{"skill": "piloting", "before": 0.5, "after": 0.51, "delta": 0.01,
		 "source": "used", "mentor_callsign": ""},
	])

	_modal = CrewProgressionModal.new()
	add_child_autofree(_modal)
	_modal.setup(record)
	await get_tree().process_frame

	var views := _find_crew_member_views(_modal)
	assert_true(views.size() > 0,
		"Modal should embed a CrewMemberView for the crew sheet")


# --- Mentored annotation ---

func test_modal_shows_mentor_callsign_for_mentored_skill() -> void:
	var record := _make_record("c1", "Rookie", [
		{"skill": "piloting", "before": 0.4, "after": 0.4004, "delta": 0.0004,
		 "source": "mentored", "mentor_callsign": "Ace"},
	])

	_modal = CrewProgressionModal.new()
	add_child_autofree(_modal)
	_modal.setup(record)
	await get_tree().process_frame

	assert_true(_count_labels_with_text(_modal, "Ace") > 0,
		"Mentored skill row should name the mentor")
	assert_true(_count_labels_with_text(_modal, "mentored") > 0,
		"Mentored skill row should show 'mentored' annotation")
