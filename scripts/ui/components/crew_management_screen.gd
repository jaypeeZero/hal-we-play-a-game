class_name CrewManagementScreen
extends OverlayScreen

## Shared overlay for drag-and-drop crew reassignment.
## Reachable from every fleet screen during an active roguelike run.
## Lifecycle: static open() adds to parent and self-frees on close;
##   or caller can use new()+setup() and manage lifetime directly.

var title_text := "MANAGE CREW"
var leave_text := "Close"


func setup() -> void:
	build_chrome()
	var topbar := _build_topbar()
	var body_node := _build_body()
	var leave := UiKit.style_button(_make_button(leave_text), "warn")
	leave.pressed.connect(func(): emit_closed())
	footer.add_child(leave)
	_finalize_chrome(topbar, body_node)


func _build_topbar() -> Control:
	var bar := UiKit.card(UiKit.PANEL_2, UiKit.LINE, 14)
	bar.add_child(UiKit.label(title_text, UiKit.INK, 16))
	return bar


func _build_body() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var board := CrewAssignmentBoard.new()
	board.show_ice = true
	board.modal_host = self
	board.setup()
	scroll.add_child(board)
	return scroll


func _make_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	return btn


## Open as a self-freeing overlay parented to `parent`.
## Returns the screen so callers can connect additional signals.
static func open(parent: Node) -> CrewManagementScreen:
	var screen := CrewManagementScreen.new()
	parent.add_child(screen)
	screen.closed.connect(screen.queue_free)
	screen.setup()
	return screen
