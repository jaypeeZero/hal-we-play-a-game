class_name NewsScreen
extends Control

## Standalone News screen for the roguelike meta-layer. Renders the campaign
## dispatch feed (RoguelikeRun.news_feed) using the SAME row rendering as the
## map's Dispatches panel (DispatchesPanel.populate_feed), so the two stay
## identical. Shows an empty-state label when no dispatches exist yet.

const SCREEN_MARGIN := 40
const TOP_GAP := 16
const CONTENT_MIN_WIDTH := 760

var _nav_bar: NavBar
var _list: VBoxContainer


func _ready() -> void:
	"""Build the News screen UI and populate the dispatch feed."""
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.backdrop(UiKit.BG))
	_build_body()
	_populate()
	# Nav bar added last so it draws above the full-rect body, which would
	# otherwise swallow clicks in the top strip.
	_nav_bar = NavBar.attach(self, NavGraph.Screen.NEWS, true)


func _build_body() -> void:
	"""Build the scrollable dispatch list below the nav bar."""
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_top", NavBar.NAV_BAR_HEIGHT + TOP_GAP)
	margin.add_theme_constant_override("margin_left", SCREEN_MARGIN)
	margin.add_theme_constant_override("margin_right", SCREEN_MARGIN)
	margin.add_theme_constant_override("margin_bottom", SCREEN_MARGIN)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", TOP_GAP)
	col.custom_minimum_size = Vector2(CONTENT_MIN_WIDTH, 0)
	margin.add_child(col)

	col.add_child(UiKit.section_title("News & Dispatches"))

	# ScrollContainer with vertical expand-fill inside the VBox so it claims
	# the remaining height (a CenterContainer would collapse it to zero).
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)


func _populate() -> void:
	"""Render the campaign news feed into the list."""
	DispatchesPanel.populate_feed(RoguelikeRun.news_feed, _list)
