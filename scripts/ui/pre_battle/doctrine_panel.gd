class_name DoctrinePanel
extends PanelContainer

## Fleet doctrine editor on the pre-battle positioning screen (plan 06).
## Dropdown-driven: the ship dropdown selects the scope to edit — the
## entire fleet, a ship class, or a single hull — and a hull's crew are
## operated on only through the crew dropdown (never via the ship
## visual). Picking a hull in the dropdown also selects it on the map
## (hull_selected), and clicking a ship on the map syncs the dropdown
## (sync_to_entry); both stay in step without feedback loops because
## programmatic dropdown selection does not re-emit.
##
## All doctrine edits land in RoguelikeRun.doctrine via DoctrineSystem
## and take effect when the battle spawns (compile_for_crew).

signal hull_selected(entry_index: int)

const PANEL_WIDTH := 380.0
const PANEL_MARGIN := 10.0

const SCOPE_LABELS := {
	DoctrineSystem.SCOPE_FLEET: "[Fleet]",
	DoctrineSystem.SCOPE_CLASS: "[Class]",
	DoctrineSystem.SCOPE_CREW: "[Personal]",
}

## Ship-dropdown option kinds.
const KIND_FLEET := "fleet"
const KIND_CLASS := "class"
const KIND_HULL := "hull"

var _entries: Array = []
var _entry_to_group: Dictionary = {}
var _ship_options: Array = []
## True on the Edit Fleet screen: the panel is laid out by its parent
## container (not floated top-right) and has no battle map to sync with.
var _embedded: bool = false

var _ship_dropdown: OptionButton
var _crew_dropdown: OptionButton
var _instructions_box: VBoxContainer
var _template_dropdown: OptionButton
var _param_box: HBoxContainer
var _template_ids: Array = []


func setup(entries: Array) -> void:
	_entries = entries
	_entry_to_group = DoctrineSystem.map_entries_to_crew_groups(entries, RoguelikeRun.fleet_crew)
	_build_ui()
	_populate_ship_dropdown()
	_on_ship_selected(0)


## Map-less setup for the Edit Fleet screen: builds the panel straight from
## the current crew roster, with no battle plan and no map sync. Every crew
## group is offered as a hull so per-crew doctrine stays editable.
func setup_from_roster() -> void:
	_embedded = true
	_entries = []
	_entry_to_group = {}
	_build_ui()
	_populate_ship_dropdown()
	_on_ship_selected(0)


## Re-sync the panel to the current roster after a fleet reconcile.
func refresh_roster() -> void:
	_ship_dropdown.clear()
	_populate_ship_dropdown()
	_ship_dropdown.select(0)
	_on_ship_selected(0)


## Sync the dropdown to a ship clicked on the map. Team-1 ships have no
## dropdown entry and are ignored. select() does not emit item_selected,
## so this cannot loop back through hull_selected.
func sync_to_entry(entry_index: int) -> void:
	for i in range(_ship_options.size()):
		if _ship_options[i].kind == KIND_HULL and _ship_options[i].entry_index == entry_index:
			_ship_dropdown.select(i)
			_refresh_for_ship_option(i)
			return


# ============================================================================
# UI CONSTRUCTION
# ============================================================================

func _build_ui() -> void:
	if _embedded:
		# Laid out by the parent container; just reserve the panel's width.
		custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	else:
		# Float over the pre-battle map at top-right.
		anchor_left = 1.0
		anchor_right = 1.0
		offset_left = -(PANEL_WIDTH + PANEL_MARGIN)
		offset_right = -PANEL_MARGIN
		offset_top = PANEL_MARGIN

	var box := VBoxContainer.new()
	add_child(box)

	var title := Label.new()
	title.text = "Fleet Doctrine"
	box.add_child(title)

	_ship_dropdown = OptionButton.new()
	_ship_dropdown.item_selected.connect(_on_ship_selected)
	box.add_child(_ship_dropdown)

	_crew_dropdown = OptionButton.new()
	_crew_dropdown.item_selected.connect(_on_crew_selected)
	box.add_child(_crew_dropdown)

	_instructions_box = VBoxContainer.new()
	box.add_child(_instructions_box)

	box.add_child(HSeparator.new())

	var add_row := HBoxContainer.new()
	box.add_child(add_row)

	_template_dropdown = OptionButton.new()
	_template_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_template_dropdown.item_selected.connect(_on_template_selected)
	add_row.add_child(_template_dropdown)

	_param_box = HBoxContainer.new()
	add_row.add_child(_param_box)

	var add_button := Button.new()
	add_button.text = "Add"
	add_button.pressed.connect(_on_add_pressed)
	add_row.add_child(add_button)


func _populate_ship_dropdown() -> void:
	_ship_options = [{"kind": KIND_FLEET, "ship_type": "", "group_index": -1, "entry_index": -1}]
	_ship_dropdown.add_item("Entire fleet")

	var types_present: Array = []
	for group in RoguelikeRun.fleet_crew:
		if group.ship_type not in types_present:
			types_present.append(group.ship_type)
	for ship_type in types_present:
		_ship_options.append({"kind": KIND_CLASS, "ship_type": ship_type, "group_index": -1, "entry_index": -1})
		_ship_dropdown.add_item("All %ss" % _type_label(ship_type))

	var count_by_type := {}
	for pair in _hull_group_pairs():
		var group_index: int = pair.group_index
		var group: Dictionary = RoguelikeRun.fleet_crew[group_index]
		var n: int = count_by_type.get(group.ship_type, 0) + 1
		count_by_type[group.ship_type] = n
		_ship_options.append({
			"kind": KIND_HULL, "ship_type": group.ship_type,
			"group_index": group_index, "entry_index": pair.entry_index,
		})
		var lead: Dictionary = group.crew[0] if group.crew.size() > 0 else {}
		_ship_dropdown.add_item("%s %d — %s" % [_type_label(group.ship_type), n, lead.get("callsign", "?")])


## Hull dropdown source as {group_index, entry_index} pairs. In roster mode
## every crew group is a hull with no battle-plan entry (-1); with a battle
## plan, entries map to groups (and carry the index used for map sync).
func _hull_group_pairs() -> Array:
	var pairs: Array = []
	if _embedded:
		for g in range(RoguelikeRun.fleet_crew.size()):
			pairs.append({"group_index": g, "entry_index": -1})
	else:
		for entry_index in _entry_to_group:
			pairs.append({"group_index": _entry_to_group[entry_index], "entry_index": entry_index})
	return pairs


func _type_label(ship_type: String) -> String:
	return ship_type.replace("_", " ").capitalize()


# ============================================================================
# SELECTION STATE
# ============================================================================

func _current_ship_option() -> Dictionary:
	var i := _ship_dropdown.selected
	return _ship_options[i] if i >= 0 and i < _ship_options.size() else {}


func _current_crew_member() -> Dictionary:
	var option := _current_ship_option()
	if option.get("kind", "") != KIND_HULL:
		return {}
	var crew: Array = RoguelikeRun.fleet_crew[option.group_index].crew
	var i := _crew_dropdown.selected
	return crew[i] if i >= 0 and i < crew.size() else {}


## The doctrine scope the Add/Remove actions operate on.
func _current_scope() -> Dictionary:
	var option := _current_ship_option()
	match option.get("kind", ""):
		KIND_CLASS:
			return {"scope": DoctrineSystem.SCOPE_CLASS, "key": option.ship_type}
		KIND_HULL:
			return {"scope": DoctrineSystem.SCOPE_CREW, "key": _current_crew_member().get("crew_id", "")}
		_:
			return {"scope": DoctrineSystem.SCOPE_FLEET, "key": ""}


func _on_ship_selected(index: int) -> void:
	_refresh_for_ship_option(index)
	var option := _current_ship_option()
	# No map to sync in roster mode: hull options there carry entry_index -1.
	if option.get("kind", "") == KIND_HULL and option.get("entry_index", -1) >= 0:
		hull_selected.emit(option.entry_index)


func _refresh_for_ship_option(index: int) -> void:
	var option: Dictionary = _ship_options[index]
	_crew_dropdown.clear()
	_crew_dropdown.visible = option.kind == KIND_HULL
	if option.kind == KIND_HULL:
		for member in RoguelikeRun.fleet_crew[option.group_index].crew:
			_crew_dropdown.add_item("%s — %s" % [CrewData.get_role_name(member.role), member.get("callsign", member.crew_id)])
		_crew_dropdown.select(0)
	_refresh_template_dropdown()
	_refresh_instruction_list()


func _on_crew_selected(_index: int) -> void:
	_refresh_template_dropdown()
	_refresh_instruction_list()


# ============================================================================
# INSTRUCTION LIST
# ============================================================================

func _refresh_instruction_list() -> void:
	for child in _instructions_box.get_children():
		child.queue_free()

	var option := _current_ship_option()
	var rows: Array
	if option.get("kind", "") == KIND_HULL:
		var member := _current_crew_member()
		rows = DoctrineSystem.effective_instructions(RoguelikeRun.doctrine, member, option.ship_type)
	else:
		var scope := _current_scope()
		rows = DoctrineSystem.scope_view(RoguelikeRun.doctrine, scope.scope, scope.key)

	if rows.is_empty():
		var empty := Label.new()
		empty.text = "No standing instructions."
		_instructions_box.add_child(empty)
		return
	for entry in rows:
		_instructions_box.add_child(_build_instruction_row(entry))


func _build_instruction_row(entry: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text = "%s %s%s" % [
		SCOPE_LABELS.get(entry.scope, ""),
		DoctrineSystem.instruction_display_name(entry.template_id, entry.params),
		_row_status_suffix(entry),
	]
	row.add_child(label)

	var scope := _current_scope()
	if entry.scope == scope.scope:
		var remove := Button.new()
		remove.text = "Remove"
		remove.pressed.connect(_on_remove_pressed.bind(entry.template_id))
		row.add_child(remove)
	elif _current_ship_option().get("kind", "") == KIND_HULL:
		# Inherited instruction on an individual: allow a personal opt-out.
		var toggle := Button.new()
		toggle.text = "Enable" if entry.disabled else "Disable"
		toggle.pressed.connect(_on_toggle_disabled_pressed.bind(entry.template_id, not entry.disabled))
		row.add_child(toggle)
	return row


func _row_status_suffix(entry: Dictionary) -> String:
	if entry.overridden:
		return " (overridden)"
	if entry.disabled:
		return " (disabled)"
	var member := _current_crew_member()
	if member.is_empty():
		return ""
	var pattern := DoctrineSystem.instantiate_template(entry.template_id, entry.params)
	var gap := DoctrineSystem.primary_maneuver_skill_gap(member, pattern)
	if gap > 0.0:
		var skill_name: String = DoctrineSystem.ROLE_EXECUTION_SKILL.get(member.get("role", -1), "tactics")
		return " — can't execute yet (needs %s +%.1f)" % [skill_name, gap]
	return ""


# ============================================================================
# ADD / REMOVE / DISABLE
# ============================================================================

func _refresh_template_dropdown() -> void:
	_template_dropdown.clear()
	_template_ids = []
	var member := _current_crew_member()
	for template_id in DoctrineSystem.get_all_templates():
		var template: Dictionary = DoctrineSystem.get_template(template_id)
		# A hull selection edits one crew member: offer only their role's
		# templates. Fleet/class selections offer everything, labeled.
		if not member.is_empty():
			if TacticalKnowledgeSystem.ROLE_NAMES.get(template.get("role", ""), -1) != member.get("role", -1):
				continue
			_template_dropdown.add_item(DoctrineSystem.instruction_display_name(template_id))
		else:
			_template_dropdown.add_item("%s (%ss)" % [DoctrineSystem.instruction_display_name(template_id), template.get("role", "")])
		_template_ids.append(template_id)
	_rebuild_param_dropdowns()


func _on_template_selected(_index: int) -> void:
	_rebuild_param_dropdowns()


func _rebuild_param_dropdowns() -> void:
	for child in _param_box.get_children():
		child.queue_free()
	var i := _template_dropdown.selected
	if i < 0 or i >= _template_ids.size():
		return
	var template: Dictionary = DoctrineSystem.get_template(_template_ids[i])
	for param_key in template.get("params", {}):
		var dropdown := OptionButton.new()
		dropdown.set_meta("param_key", param_key)
		for value in template.params[param_key].get("options", []):
			dropdown.add_item(str(value))
		_param_box.add_child(dropdown)


func _selected_params() -> Dictionary:
	var params := {}
	for child in _param_box.get_children():
		if child is OptionButton and child.selected >= 0:
			params[child.get_meta("param_key")] = child.get_item_text(child.selected)
	return params


func _on_add_pressed() -> void:
	var i := _template_dropdown.selected
	if i < 0 or i >= _template_ids.size():
		return
	var scope := _current_scope()
	DoctrineSystem.set_instruction_in_place(RoguelikeRun.doctrine, scope.scope, scope.key, _template_ids[i], _selected_params())
	_refresh_instruction_list()


func _on_remove_pressed(template_id: String) -> void:
	var scope := _current_scope()
	DoctrineSystem.remove_instruction_in_place(RoguelikeRun.doctrine, scope.scope, scope.key, template_id)
	_refresh_instruction_list()


func _on_toggle_disabled_pressed(template_id: String, disabled: bool) -> void:
	var member := _current_crew_member()
	if member.is_empty():
		return
	DoctrineSystem.set_disabled_in_place(RoguelikeRun.doctrine, member.crew_id, template_id, disabled)
	_refresh_instruction_list()
