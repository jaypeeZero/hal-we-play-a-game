class_name OverlayScreen
extends Control

## Shared chrome scaffold for full-screen overlays (Shop, R&R, Crew Manager,
## Fleet Editor). Provides backdrop + margin + root VBox with three region slots
## that subclasses fill: topbar_slot, body, and footer.
##
## Two lifecycles:
##   Overlay (Shop, R&R): caller frees via queue_free(); emit_closed() only
##     emits `closed` — does NOT self-free.
##   Standalone scene (Crew Manager, Fleet Editor): Back button calls
##     change_scene_to_file; no `closed` signal needed.

signal closed

const SCREEN_MARGIN := 40
const SECTION_GAP := 16

## Subclasses inject their own topbar card here.
var topbar_slot: Control
## Subclasses inject the main body (scroll or two-pane HBox) here.
var body: Control
## Subclasses add buttons (Leave / Back+Reset+Save / etc.) here.
var footer: HBoxContainer

var _root: VBoxContainer


func build_chrome() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.backdrop())

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, SCREEN_MARGIN)
	add_child(margin)

	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", SECTION_GAP)
	margin.add_child(_root)

	# footer exists immediately so subclasses can add buttons to it; topbar_slot
	# and body are set when the subclass calls _finalize_chrome(), which then
	# adds all three regions to the root in order.
	footer = HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", SECTION_GAP)


## Subclass calls this after setting topbar, body, and populating footer.
## Adds all three regions to the root VBox in order.
func _finalize_chrome(topbar: Control, body_node: Control) -> void:
	topbar_slot = topbar
	body = body_node
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_child(topbar_slot)
	_root.add_child(body)
	_root.add_child(footer)


## Signal-only close — the caller (campaign_map_3d) frees overlay screens.
func emit_closed() -> void:
	closed.emit()
