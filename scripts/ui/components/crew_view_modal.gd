class_name CrewViewModal
extends Control

## Read-only CrewMemberView in a centered modal over a dimmed backdrop
## (DismissalDialog chrome). One popup shared by every screen that shows a
## crew member: shop crew rows, hire candidates, and anywhere else.

signal closed

const MODAL_WIDTH := 560
const BACKDROP_ALPHA := 0.85
const FOOTER_GAP := 10


## Build, attach to `parent`, and show the modal for one entry
## (roster-entry shape; adapt crew dicts with CrewData.entry_from_crew).
static func open(parent: Node, entry: Dictionary) -> CrewViewModal:
	var modal: CrewViewModal = CrewViewModal.new()
	parent.add_child(modal)
	modal.setup(entry)
	return modal


func setup(entry: Dictionary) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := UiKit.BG
	dim.a = BACKDROP_ALPHA
	add_child(UiKit.backdrop(dim))

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(MODAL_WIDTH, 0)
	panel.add_theme_stylebox_override("panel", UiKit.panel_box(UiKit.PANEL_2, UiKit.LINE))
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", FOOTER_GAP)
	panel.add_child(box)

	var view := CrewMemberView.new()
	view.setup(entry, false)
	box.add_child(view)

	var close := UiKit.style_button(_make_button("Close"), "ghost")
	close.pressed.connect(_on_close)
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_child(close)
	box.add_child(footer)


func _on_close() -> void:
	closed.emit()
	queue_free()


func _make_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	return btn
