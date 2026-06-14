class_name CrewViewModal
extends ModalDialog

## Read-only CrewMemberView in a centered modal over a dimmed backdrop.
## One popup shared by every screen that shows a crew member: shop crew rows,
## hire candidates, and Fleet Command crew chips/assigned slots.
##
## Fleet Command passes orders_ctx = {"crew_id": String, "ship_type": String}
## to unlock the per-crew Orders section. Other callers pass nothing and see
## no change to the existing popup.

const MODAL_WIDTH := 560

# Orders-section state (populated only when orders_ctx is provided).
var _orders_crew_id: String = ""
var _orders_ship_type: String = ""
var _orders_template_ids: Array = []
var _orders_list_box: VBoxContainer = null
var _orders_param_box: HBoxContainer = null
var _orders_template_drop: OptionButton = null


## Build, attach to `parent`, and show the modal for one entry.
## orders_ctx: optional {crew_id, ship_type} to show the Orders section.
## When empty (default) the popup is unchanged — shop/hire callers are unaffected.
static func open(parent: Node, entry: Dictionary, orders_ctx: Dictionary = {}) -> CrewViewModal:
	var modal: CrewViewModal = CrewViewModal.new()
	parent.add_child(modal)
	modal.setup(entry, orders_ctx)
	return modal


func setup(entry: Dictionary, orders_ctx: Dictionary = {}) -> void:
	build_chrome(MODAL_WIDTH)
	var view := CrewMemberView.new()
	view.setup(entry, false)
	content.add_child(view)
	if not orders_ctx.is_empty():
		_maybe_add_orders_section(entry, orders_ctx)
	add_footer()


# ORDERS SECTION

## Add an Orders section if the crew's role has applicable templates.
func _maybe_add_orders_section(entry: Dictionary, orders_ctx: Dictionary) -> void:
	# Role comes from orders_ctx: entry_from_crew() yields roster shape (a `roles`
	# string array, no `role` int), so reading entry.role would always be -1.
	var role_int: int = int(orders_ctx.get("role", entry.get("role", -1)))
	_orders_crew_id = str(orders_ctx.get("crew_id", ""))
	_orders_ship_type = str(orders_ctx.get("ship_type", ""))
	_orders_template_ids = _templates_for_role(role_int)
	if _orders_template_ids.is_empty():
		return  # Relevance gate: no templates for this role — omit section.
	content.add_child(_build_orders_section())


## Return all template_ids whose role field matches role_int.
func _templates_for_role(role_int: int) -> Array:
	var result: Array = []
	for template_id: String in DoctrineSystem.get_all_templates():
		var template: Dictionary = DoctrineSystem.get_template(template_id)
		if TacticalKnowledgeSystem.ROLE_NAMES.get(template.get("role", ""), -1) == role_int:
			result.append(template_id)
	return result


## Build and return the Orders VBoxContainer.
func _build_orders_section() -> VBoxContainer:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 8)
	section.add_child(UiKit.label("Orders", UiKit.INK, 13))
	section.add_child(HSeparator.new())

	_orders_list_box = VBoxContainer.new()
	_orders_list_box.add_theme_constant_override("separation", 4)
	section.add_child(_orders_list_box)

	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 6)
	section.add_child(add_row)

	_orders_template_drop = OptionButton.new()
	_orders_template_drop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for tid: String in _orders_template_ids:
		_orders_template_drop.add_item(DoctrineSystem.instruction_display_name(tid))
	_orders_template_drop.item_selected.connect(_on_orders_template_selected)
	add_row.add_child(_orders_template_drop)

	_orders_param_box = HBoxContainer.new()
	_orders_param_box.add_theme_constant_override("separation", 4)
	add_row.add_child(_orders_param_box)

	var add_btn := Button.new()
	add_btn.text = "Add"
	UiKit.style_button(add_btn, "ghost")
	add_btn.pressed.connect(_on_orders_add_pressed)
	add_row.add_child(add_btn)

	_rebuild_orders_params()
	_rebuild_orders_list()
	return section


func _on_orders_template_selected(_idx: int) -> void:
	_rebuild_orders_params()


## Rebuild param sub-dropdowns for the currently selected template.
func _rebuild_orders_params() -> void:
	if _orders_param_box == null:
		return
	for child: Node in _orders_param_box.get_children():
		child.queue_free()
	var i: int = _orders_template_drop.selected
	if i < 0 or i >= _orders_template_ids.size():
		return
	var tmpl: Dictionary = DoctrineSystem.get_template(_orders_template_ids[i])
	for param_key: String in tmpl.get("params", {}):
		var pd := OptionButton.new()
		pd.set_meta("param_key", param_key)
		for opt: Variant in tmpl.params[param_key].get("options", []):
			pd.add_item(str(opt))
		_orders_param_box.add_child(pd)


## Rebuild the instruction list from the live doctrine store.
func _rebuild_orders_list() -> void:
	if _orders_list_box == null:
		return
	for child: Node in _orders_list_box.get_children():
		child.queue_free()
	var doctrine: Dictionary = SkirmishFleet.current_doctrine()
	var crew_instructions: Array = DoctrineSystem.scope_view(
		doctrine, DoctrineSystem.SCOPE_CREW, _orders_crew_id)
	if crew_instructions.is_empty():
		_orders_list_box.add_child(UiKit.label("No personal orders.", UiKit.DIM, 11))
		return
	for instr: Dictionary in crew_instructions:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var lbl := UiKit.label(
			DoctrineSystem.instruction_display_name(instr.template_id, instr.params),
			UiKit.INK, 12)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var rm_btn := Button.new()
		rm_btn.text = "✕"
		UiKit.style_button(rm_btn, "warn")
		var tid: String = instr.template_id
		rm_btn.pressed.connect(_on_orders_remove_pressed.bind(tid))
		row.add_child(rm_btn)
		_orders_list_box.add_child(row)


func _on_orders_add_pressed() -> void:
	var i: int = _orders_template_drop.selected
	if i < 0 or i >= _orders_template_ids.size():
		return
	var params: Dictionary = {}
	if _orders_param_box != null:
		for child: Node in _orders_param_box.get_children():
			if child is OptionButton and (child as OptionButton).selected >= 0:
				params[child.get_meta("param_key")] = \
					(child as OptionButton).get_item_text((child as OptionButton).selected)
	var d: Dictionary = SkirmishFleet.current_doctrine()
	DoctrineSystem.set_instruction_in_place(
		d, DoctrineSystem.SCOPE_CREW, _orders_crew_id, _orders_template_ids[i], params)
	if not RoguelikeRun.active:
		SkirmishFleet.set_doctrine(d)
	_rebuild_orders_list()


func _on_orders_remove_pressed(template_id: String) -> void:
	var d: Dictionary = SkirmishFleet.current_doctrine()
	DoctrineSystem.remove_instruction_in_place(
		d, DoctrineSystem.SCOPE_CREW, _orders_crew_id, template_id)
	if not RoguelikeRun.active:
		SkirmishFleet.set_doctrine(d)
	_rebuild_orders_list()
