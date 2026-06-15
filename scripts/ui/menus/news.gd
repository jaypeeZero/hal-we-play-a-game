class_name NewsScreen
extends Control

## Standalone News screen for the roguelike meta-layer.
## Owns the dispatch/mail content (moved here from FleetManagement).
## Shows campaign news feed (RoguelikeRun.news_feed) via DispatchesPanel
## rendering, plus a static placeholder mail list when the feed is empty.

const PLACEHOLDER_MESSAGES: Array = [
	{"from": "Admiral Chen",    "title": "Fleet Status Report",      "message": "All ships report combat ready. Awaiting your orders, Commander."},
	{"from": "Intel Division",  "title": "Enemy Movement Detected",  "message": "Long-range sensors have detected hostile fleet activity in Sector 7."},
	{"from": "Supply Command",  "title": "Resupply Complete",        "message": "Ammunition and fuel reserves have been replenished to full capacity."},
	{"from": "Science Officer", "title": "Anomaly Detected",         "message": "Unusual energy signatures detected near the jump gate. Recommend caution."},
	{"from": "Flight Command",  "title": "Pilot Reports",            "message": "All fighter squadrons report green across the board. Ready for deployment."},
]

const MESSAGE_BODY_MIN_WIDTH := 300
const CONTENT_MAX_WIDTH := 720
const SECTION_SEP := 16

var _nav_bar: NavBar
var _scroll: ScrollContainer
var _list: VBoxContainer


func _ready() -> void:
	"""Build the full News screen UI."""
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.backdrop(UiKit.BG))
	_build_body()
	_populate()
	# Nav bar added last so it draws above the full-rect body, which would
	# otherwise swallow clicks in the top strip.
	_build_nav_bar()


func _build_nav_bar() -> void:
	"""Instantiate the run-scoped NavBar pinned to screen top."""
	_nav_bar = NavBar.attach(self, NavGraph.Screen.NEWS, true)


func _build_body() -> void:
	"""Build scrollable content area offset below the nav bar."""
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_top", NavBar.NAV_BAR_HEIGHT + SECTION_SEP)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_child(center)

	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(CONTENT_MAX_WIDTH, 0)
	col.add_theme_constant_override("separation", SECTION_SEP)
	center.add_child(col)

	col.add_child(UiKit.section_title("News & Dispatches"))

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)


func _populate() -> void:
	"""Populate the list with campaign feed entries or placeholder messages."""
	for child in _list.get_children():
		child.queue_free()

	# Prefer live campaign news feed if available.
	var feed: Array = RoguelikeRun.news_feed if RoguelikeRun.active else []

	if not feed.is_empty():
		_populate_from_feed(feed)
	else:
		_populate_placeholder()


func _populate_from_feed(feed: Array) -> void:
	"""Render live campaign dispatches grouped by star date."""
	var groups: Dictionary = {}
	var date_order: Array = []
	for entry in feed:
		var sd: int = int(entry.get("star_date", 0))
		if not groups.has(sd):
			groups[sd] = []
			date_order.append(sd)
		groups[sd].append(entry)

	for sd in date_order:
		_list.add_child(UiKit.section_title("Stardate %d" % sd))
		for entry in groups[sd]:
			_list.add_child(_build_feed_row(entry))


func _build_feed_row(entry: Dictionary) -> Control:
	"""Build a card row for one campaign news entry."""
	var polarity: String = str(entry.get("polarity", "neutral"))
	var accent: Color = _polarity_color(polarity)

	var card := UiKit.card(UiKit.PANEL_2, UiKit.LINE)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)

	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 6)
	box.add_child(head_row)
	if polarity != "neutral":
		head_row.add_child(UiKit.badge(_polarity_glyph(polarity), accent))
	var h_lbl := UiKit.label(str(entry.get("headline", "")), UiKit.INK, 13)
	h_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_row.add_child(h_lbl)

	var body: String = str(entry.get("body", ""))
	if not body.is_empty():
		var b_lbl := UiKit.label(body, UiKit.DIM, 11)
		b_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(b_lbl)

	return card


func _populate_placeholder() -> void:
	"""Show the static placeholder messages when no campaign is active."""
	for msg in PLACEHOLDER_MESSAGES:
		_list.add_child(_build_message_card(msg))


func _build_message_card(msg: Dictionary) -> PanelContainer:
	"""Build a card for a static placeholder message."""
	var panel := UiKit.card()

	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 4)
	panel.add_child(container)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	container.add_child(header)
	header.add_child(UiKit.label(msg["from"], UiKit.ACCENT, 13))
	header.add_child(UiKit.label(msg["title"], UiKit.INK, 13))

	var body := UiKit.label(msg["message"], UiKit.DIM, 12)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD
	body.custom_minimum_size = Vector2(MESSAGE_BODY_MIN_WIDTH, 0)
	container.add_child(body)

	return panel


func _polarity_color(polarity: String) -> Color:
	"""Return the UiKit colour for a polarity string."""
	match polarity:
		"positive": return UiKit.GOOD
		"negative": return UiKit.BAD
		_: return UiKit.DIM


func _polarity_glyph(polarity: String) -> String:
	"""Return a short text glyph for a polarity string."""
	match polarity:
		"positive": return "+"
		"negative": return "−"
		_: return "·"
