class_name CrewProgressionModal
extends ModalDialog

## Drill-down modal for one crew member's post-battle skill development.
##
## Shows:
##   1. CrewMemberView (after state — skills already mutated)
##   2. "This battle" skill-delta panel (one row per changed skill)
##   3. Coaching note when the crew member was coached by a commander.

const MODAL_WIDTH := 600
const SECTION_SEPARATION := 10
const ROW_SEPARATION := 6


## Build, attach to `parent`, and show the modal for one progression record.
static func open(parent: Node, record: Dictionary) -> CrewProgressionModal:
	var modal := CrewProgressionModal.new()
	parent.add_child(modal)
	modal.setup(record)
	return modal


func setup(record: Dictionary) -> void:
	build_chrome(MODAL_WIDTH)

	# 1. Crew sheet (after state — live crew skills already mutated by the system)
	var crew_id: String = str(record.get("crew_id", ""))
	var hull := _find_hull_for_crew(crew_id)
	if not hull.is_empty():
		var member := _find_member(hull, crew_id)
		if not member.is_empty():
			var entry := CrewData.entry_from_crew(member)
			var view := CrewMemberView.new()
			view.setup(entry, false)
			content.add_child(view)

	# 2. Development panel
	content.add_child(_build_delta_panel(record))

	# 3. Coaching note
	var commander_callsign: String = str(record.get("commander_callsign", ""))
	var coach_mult: float = float(record.get("coach_mult", 1.0))
	if commander_callsign != "" and not is_equal_approx(coach_mult, 1.0):
		content.add_child(UiKit.label(
			"Coached by %s (×%.2f)" % [commander_callsign, coach_mult], UiKit.DIM))

	add_footer()


func _build_delta_panel(record: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", ROW_SEPARATION)
	box.add_child(UiKit.section_title("This battle"))

	var skill_deltas: Array = record.get("skills", [])
	if skill_deltas.is_empty():
		box.add_child(UiKit.label("No skill changes this battle.", UiKit.DIM))
		return box

	for s in skill_deltas:
		box.add_child(_delta_row(s))

	return box


func _delta_row(s: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var skill_name: String = str(s.get("skill", ""))
	var before := float(s.get("before", 0.0))
	var after := float(s.get("after", 0.0))
	var delta := float(s.get("delta", 0.0))
	var source: String = str(s.get("source", ""))
	var mentor: String = str(s.get("mentor_callsign", ""))

	var before_pct := int(round(before * 100.0))
	var after_pct := int(round(after * 100.0))
	var diff := after_pct - before_pct
	var arrow := "▲" if delta >= 0 else "▼"
	var sign := "+" if diff >= 0 else ""
	var delta_color := UiKit.GOOD if delta >= 0 else UiKit.BAD

	var name_label := UiKit.label(skill_name.capitalize(), UiKit.INK, 12)
	name_label.custom_minimum_size = Vector2(80, 0)
	row.add_child(name_label)

	row.add_child(UiKit.label("%d%% → %d%%" % [before_pct, after_pct], UiKit.DIM, 11))
	row.add_child(UiKit.label("%s %s%d%%" % [arrow, sign, diff], delta_color, 11))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var source_text := ""
	match source:
		"used":
			source_text = "used"
		"mentored":
			source_text = "mentored by %s" % mentor if mentor != "" else "mentored"
		"adversity":
			if delta >= 0:
				source_text = "hardened under fire"
			else:
				source_text = "shaken"
	if source_text != "":
		row.add_child(UiKit.label(source_text, UiKit.DIM, 10))

	return row


func _find_hull_for_crew(crew_id: String) -> Dictionary:
	for hull in RoguelikeRun.fleet_hulls:
		for member in hull.get("crew", []):
			if member.get("crew_id", "") == crew_id:
				return hull
	return {}


func _find_member(hull: Dictionary, crew_id: String) -> Dictionary:
	for member in hull.get("crew", []):
		if member.get("crew_id", "") == crew_id:
			return member
	return {}
