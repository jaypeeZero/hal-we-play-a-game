class_name PostBattleOverview
extends Control

## Post-battle summary: economy, fleet health before/after, crew development.
## Always shown after a roguelike battle (victory and defeat alike).
## The Continue button forwards to the campaign map so the map's
## _resolve_pending_battle still runs (promotion / defeat / game-over).

const CAMPAIGN_MAP_SCENE := "res://scenes/campaign_map_3d.tscn"
const CONDITION_LOW_RATIO := 0.4
const SCROLL_MAX_HEIGHT := 600
const SECTION_SEPARATION := 12
const ROW_SEPARATION := 8
const CREW_ROW_PORTRAIT_SIZE := Vector2(36, 42)


func _ready() -> void:
	_build()


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.backdrop(UiKit.BG))

	var outer := CenterContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(outer)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 0)
	panel.add_theme_stylebox_override("panel", UiKit.panel_box(UiKit.PANEL_2, UiKit.LINE))
	outer.add_child(panel)

	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", SECTION_SEPARATION)
	panel.add_child(root_box)

	# Header
	root_box.add_child(_build_header())

	# Scrollable content
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, SCROLL_MAX_HEIGHT)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_box.add_child(scroll)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", SECTION_SEPARATION)
	scroll.add_child(content)

	content.add_child(_build_earnings())
	content.add_child(_build_fleet())
	content.add_child(_build_crew_development())

	# Footer
	root_box.add_child(_build_footer())


func _build_header() -> Control:
	var victory: bool = RoguelikeRun.pending_battle_result == "victory"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var outcome_text := "VICTORY" if victory else "DEFEAT"
	var outcome_color := UiKit.GOOD if victory else UiKit.BAD
	row.add_child(UiKit.label(outcome_text, outcome_color, 22))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(UiKit.label("Star Date %d" % RoguelikeRun.current_star_date, UiKit.DIM, 13))
	return row


func _build_earnings() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", ROW_SEPARATION)
	box.add_child(UiKit.section_title("Earnings"))

	var victory: bool = RoguelikeRun.pending_battle_result == "victory"
	var summary: Dictionary = RoguelikeRun.last_battle_summary
	var reward: int = int(summary.get("reward", 0))
	var insurance: int = int(summary.get("insurance", 0))
	var casualties: int = int(summary.get("casualties", 0))
	var net: int = reward - insurance

	if victory and reward > 0:
		var enemies: Dictionary = summary.get("destroyed_enemies", {})
		var enemy_count := 0
		for k in enemies:
			enemy_count += int(enemies[k])
		var earned_row := HBoxContainer.new()
		earned_row.add_child(UiKit.label("Earned", UiKit.DIM))
		var esp := Control.new(); esp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		earned_row.add_child(esp)
		earned_row.add_child(UiKit.label(
			"+%s cr  (%d enemies destroyed)" % [_fmt_credits(reward), enemy_count], UiKit.GOLD))
		box.add_child(earned_row)

	if insurance > 0:
		var spent_row := HBoxContainer.new()
		spent_row.add_child(UiKit.label("Spent", UiKit.DIM))
		var ssp := Control.new(); ssp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spent_row.add_child(ssp)
		spent_row.add_child(UiKit.label(
			"-%s cr  (%d casualt%s — insurance)" % [
				_fmt_credits(insurance), casualties, "ies" if casualties != 1 else "y"],
			UiKit.BAD))
		box.add_child(spent_row)

	box.add_child(UiKit.separator())

	var net_row := HBoxContainer.new()
	net_row.add_theme_constant_override("separation", 16)
	var net_color := UiKit.GOOD if net >= 0 else UiKit.BAD
	var net_str := ("+%s" % _fmt_credits(net)) if net >= 0 else ("-%s" % _fmt_credits(-net))
	net_row.add_child(UiKit.label("Net  %s cr" % net_str, net_color))
	var nsp := Control.new(); nsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	net_row.add_child(nsp)
	net_row.add_child(UiKit.label("Balance  %s cr" % _fmt_credits(RoguelikeRun.money), UiKit.INK))
	box.add_child(net_row)

	if not victory:
		box.add_child(UiKit.label("Fleet lost — no battle reward", UiKit.BAD))

	return box


func _build_fleet() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", ROW_SEPARATION)
	box.add_child(UiKit.section_title("Fleet"))

	var deltas: Array = RoguelikeRun.last_battle_summary.get("ship_deltas", [])
	if deltas.is_empty():
		box.add_child(UiKit.label("No fleet data available.", UiKit.DIM))
		return box

	for delta in deltas:
		box.add_child(_fleet_row(delta))

	return box


func _fleet_row(delta: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var ship_type: String = str(delta.get("ship_type", "ship")).capitalize()
	row.add_child(UiKit.label("[%s]" % ship_type, UiKit.INK))

	if bool(delta.get("destroyed", false)):
		row.add_child(UiKit.badge("DESTROYED", UiKit.BAD))
	else:
		var armor_before := float(delta.get("armor_before", 1.0))
		var armor_after := float(delta.get("armor_after", 1.0))
		var sys_before := float(delta.get("systems_before", 1.0))
		var sys_after := float(delta.get("systems_after", 1.0))

		row.add_child(UiKit.label("Armor", UiKit.DIM, 11))
		row.add_child(_before_after_label(armor_before, armor_after, UiKit.ACCENT))
		row.add_child(UiKit.label("Systems", UiKit.DIM, 11))
		row.add_child(_before_after_label(sys_before, sys_after, UiKit.GOLD))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	# Drill-down: open ShipViewModal for this hull
	var hull_id: String = str(delta.get("hull_id", ""))
	var drill_btn := Button.new()
	drill_btn.text = "⋯"
	UiKit.style_button(drill_btn, "ghost")
	drill_btn.pressed.connect(func(): _open_ship_modal(hull_id))
	row.add_child(drill_btn)

	return row


func _before_after_label(before: float, after: float, color: Color) -> Label:
	var low := after < CONDITION_LOW_RATIO
	var text := "%d%%→%d%%" % [int(round(before * 100.0)), int(round(after * 100.0))]
	return UiKit.label(text, UiKit.BAD if low else color, 11)


func _open_ship_modal(hull_id: String) -> void:
	var hull := RoguelikeRun.hull_by_id(hull_id)
	if hull.is_empty():
		return
	ShipViewModal.open(self, hull)


func _build_crew_development() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", ROW_SEPARATION)
	box.add_child(UiKit.section_title("Crew Development"))

	var progression: Array = RoguelikeRun.last_battle_progression
	if progression.is_empty():
		var msg := "No survivors to debrief." if RoguelikeRun.pending_battle_result != "victory" \
			else "No crew development this battle."
		box.add_child(UiKit.label(msg, UiKit.DIM))
		return box

	for rec in progression:
		box.add_child(_crew_dev_row(rec))

	return box


func _crew_dev_row(rec: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	# Portrait face: keyed off the crew's stable id (or callsign) so a given
	# crew member always shows the same face here as elsewhere.
	var portrait := CrewPortrait.new()
	portrait.custom_minimum_size = CREW_ROW_PORTRAIT_SIZE
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	portrait.setup(_portrait_entry(rec))
	row.add_child(portrait)

	var role_name := CrewData.get_role_name(int(rec.get("role", CrewData.Role.PILOT)))
	row.add_child(UiKit.label(role_name, UiKit.DIM, 11))
	row.add_child(UiKit.label(str(rec.get("callsign", "")), UiKit.INK))

	# Find the largest delta to show as the headline skill
	var skill_deltas: Array = rec.get("skills", [])
	var largest_delta := 0.0
	var largest_name := ""
	var largest_before := 0.0
	var largest_after := 0.0
	for s in skill_deltas:
		var d := absf(float(s.get("delta", 0.0)))
		if d > largest_delta:
			largest_delta = d
			largest_name = str(s.get("skill", ""))
			largest_before = float(s.get("before", 0.0))
			largest_after = float(s.get("after", 0.0))

	if largest_name != "":
		var before_pct := int(round(largest_before * 100.0))
		var after_pct := int(round(largest_after * 100.0))
		var diff := after_pct - before_pct
		var arrow := "▲" if diff >= 0 else "▼"
		var sign := "+" if diff >= 0 else ""
		var color := UiKit.GOOD if diff >= 0 else UiKit.BAD
		row.add_child(UiKit.label(
			"%s %s %s%d%%" % [largest_name.capitalize(), arrow, sign, diff], color, 11))

	if skill_deltas.size() > 1:
		row.add_child(UiKit.label("(+%d more)" % (skill_deltas.size() - 1), UiKit.DIM, 10))

	var coach_mult := float(rec.get("coach_mult", 1.0))
	if not is_equal_approx(coach_mult, 1.0):
		row.add_child(UiKit.label("coached ×%.2f" % coach_mult, UiKit.DIM, 10))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var drill_btn := Button.new()
	drill_btn.text = "⋯"
	UiKit.style_button(drill_btn, "ghost")
	drill_btn.pressed.connect(func(): CrewProgressionModal.open(self, rec))
	row.add_child(drill_btn)

	return row


## Build a minimal roster-shaped entry for CrewPortrait from a progression
## record. CrewPortrait keys the face off `id` (crew_id) then `callsign`, so a
## crew member's face stays stable across screens.
func _portrait_entry(rec: Dictionary) -> Dictionary:
	return {
		"id": str(rec.get("crew_id", "")),
		"callsign": str(rec.get("callsign", "")),
	}


func _build_footer() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END

	if RoguelikeRun.has_fleet():
		var manage_btn := Button.new()
		manage_btn.text = "Manage Crew"
		UiKit.style_button(manage_btn, "ghost")
		manage_btn.pressed.connect(func() -> void: FleetCommandScreen.open_overlay(self))
		row.add_child(manage_btn)

	var continue_btn := Button.new()
	continue_btn.text = "Continue →"
	UiKit.style_button(continue_btn, "primary")
	continue_btn.pressed.connect(_on_continue)
	row.add_child(continue_btn)

	return row


func _on_continue() -> void:
	RoguelikeRun.last_battle_progression = []
	RoguelikeRun.last_battle_summary.erase("ship_deltas")
	get_tree().change_scene_to_file(CAMPAIGN_MAP_SCENE)


func _fmt_credits(amount: int) -> String:
	# Format with comma thousands separator
	var s := str(abs(amount))
	var result := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = s[i] + result
		count += 1
	return result
