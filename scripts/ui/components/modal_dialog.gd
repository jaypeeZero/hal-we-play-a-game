class_name ModalDialog
extends Control

## Shared chrome for centered-panel modals. Subclasses call build_chrome(),
## fill `content`, then call add_footer() to wire the Close button.
## Lifecycle: modals self-free on close (closed.emit(); queue_free()).

signal closed

const BACKDROP_ALPHA := 0.85
const FOOTER_GAP := 10
const DEFAULT_WIDTH := 560

## Subclasses append their own widgets here after build_chrome().
var content: VBoxContainer


func build_chrome(width := DEFAULT_WIDTH) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := UiKit.BG
	dim.a = BACKDROP_ALPHA
	add_child(UiKit.backdrop(dim))

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, 0)
	panel.add_theme_stylebox_override("panel", UiKit.panel_box(UiKit.PANEL_2, UiKit.LINE))
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", FOOTER_GAP)
	panel.add_child(box)
	content = box


func add_footer() -> void:
	var close := UiKit.style_button(_make_button("Close"), "ghost")
	close.pressed.connect(_on_close)
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_child(close)
	content.add_child(footer)


func _on_close() -> void:
	closed.emit()
	queue_free()


func _make_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	return btn
