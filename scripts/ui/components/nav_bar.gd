class_name NavBar
extends Control

## Persistent top navigation bar for the roguelike meta-layer.
## Drop an instance into each meta scene and set current_screen + tabs_enabled.
## Drives Nav.goto / Nav.back; never triggers scene switches directly.

## Which screen this bar instance lives on (determines active tab + Back state).
## Use NavGraph.Screen values (int). Set in the editor via @export.
@export var current_screen: int = NavGraph.Screen.FLEET_MANAGER

## When false, area tabs are disabled (Back still works).
## Set to false on pre_battle so deployment can't be abandoned by a stray tab.
@export var tabs_enabled: bool = true

## Optional override for the Back button action.
## When set, pressing Back calls this instead of Nav.back().
## Use when the scene has its own save-prompt or teardown logic.
var back_override: Callable = Callable()

# ---- layout constants ----
const NAV_BAR_HEIGHT := 48
const ICON_SIZE := Vector2(24, 24)
const BACK_ICON_SIZE := Vector2(20, 20)
const BUTTON_MIN_SIZE := Vector2(44, 36)
const BAR_SEPARATION := 4
const SIDE_PAD := 8

# ---- tab definitions ----
const TABS: Array = [
	{"screen": NavGraph.Screen.MAP,           "icon": "res://assets/icons/nav/map.svg",   "tip": "Map"},
	{"screen": NavGraph.Screen.FLEET_MANAGER, "icon": "res://assets/icons/nav/fleet.svg", "tip": "Fleet Manager"},
	{"screen": NavGraph.Screen.CREW,          "icon": "res://assets/icons/nav/crew.svg",  "tip": "Crew Manager"},
	{"screen": NavGraph.Screen.NEWS,          "icon": "res://assets/icons/nav/news.svg",  "tip": "News"},
]

const CREDITS_GLYPH := "₵"

var _back_btn: Button
var _tab_buttons: Array = []
var _credits_label: Label
var _shown_credits: int = -1


## Create and add a NavBar to `parent`, but only inside an active roguelike run.
## The meta nav is run-scoped: returns null (and adds nothing) when no run is
## active, so title/skirmish entries keep their own navigation. The bar is added
## as the parent's last child so it draws above the base screen UI; runtime
## modals added later still cover it, by design.
static func attach(parent: Node, screen: int, tabs_on: bool = true,
		back_cb: Callable = Callable()) -> NavBar:
	"""Attach a run-scoped NavBar to parent; null when no run is active."""
	if not RoguelikeRun.active:
		return null
	var bar := NavBar.new()
	bar.current_screen = screen
	bar.tabs_enabled = tabs_on
	bar.back_override = back_cb
	parent.add_child(bar)
	return bar


func _ready() -> void:
	"""Build the bar UI and configure button states."""
	_build_bar()
	_back_btn.disabled = not Nav.can_go_back(current_screen)
	_highlight_active()
	if not tabs_enabled:
		for btn in _tab_buttons:
			btn.disabled = true
	_refresh_credits()


func _process(_delta: float) -> void:
	"""Keep the credits readout in sync with the run's money."""
	_refresh_credits()


## Update the credits readout only when the value has changed.
func _refresh_credits() -> void:
	"""Refresh the credits label when RoguelikeRun.money changes."""
	if _credits_label == null:
		return
	var money: int = RoguelikeRun.money
	if money == _shown_credits:
		return
	_shown_credits = money
	_credits_label.text = "%s %s" % [CREDITS_GLYPH, _with_commas(money)]


## Format an integer with thousands separators (e.g. 12345 -> "12,345").
static func _with_commas(n: int) -> String:
	"""Return n as a string with comma thousands separators."""
	var s: String = str(absi(n))
	var out: String = ""
	var count: int = 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" + out) if n < 0 else out


func _build_bar() -> void:
	"""Construct PanelContainer → HBox with Back + tab buttons."""
	# Anchor bar to the top-full-width of its parent.
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	custom_minimum_size = Vector2(0, NAV_BAR_HEIGHT)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override(
		"panel", UiKit.panel_box(UiKit.PANEL_2, UiKit.LINE, 0, SIDE_PAD))
	add_child(panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", BAR_SEPARATION)
	hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	panel.add_child(hbox)

	# Back button
	_back_btn = _make_icon_button(
		"res://assets/icons/nav/back.svg", BACK_ICON_SIZE, "Back")
	_back_btn.pressed.connect(_on_back_pressed)
	hbox.add_child(_back_btn)

	# Separator spacer
	var sep := VSeparator.new()
	sep.add_theme_stylebox_override("separator",
		_vseparator_style())
	hbox.add_child(sep)

	# Tab buttons
	for tab in TABS:
		var btn := _make_icon_button(tab["icon"], ICON_SIZE, tab["tip"])
		btn.pressed.connect(_on_tab_pressed.bind(tab["screen"]))
		_tab_buttons.append(btn)
		hbox.add_child(btn)

	# Spacer pushes the credits readout to the right edge.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(spacer)

	_credits_label = UiKit.label("", UiKit.ACCENT, 14)
	_credits_label.tooltip_text = "Credits on hand"
	hbox.add_child(_credits_label)


func _make_icon_button(icon_path: String, icon_size: Vector2, tip: String) -> Button:
	"""Create a styled icon button with tooltip."""
	var btn := Button.new()
	btn.custom_minimum_size = BUTTON_MIN_SIZE
	btn.tooltip_text = tip
	btn.expand_icon = true
	btn.icon = load(icon_path)
	# icon_max_width constrains the icon within the button
	btn.add_theme_constant_override("icon_max_width", int(icon_size.x))
	UiKit.style_button(btn, "ghost")
	return btn


func _highlight_active() -> void:
	"""Disable + visually mark the tab matching current_screen."""
	for i in _tab_buttons.size():
		var btn: Button = _tab_buttons[i]
		var tab_screen: int = TABS[i]["screen"]
		if tab_screen == current_screen:
			btn.disabled = true
			# Apply accent tint to signal "you are here"
			btn.add_theme_color_override("icon_normal_color", UiKit.ACCENT)
			btn.add_theme_color_override("font_color", UiKit.ACCENT)
		else:
			btn.add_theme_color_override("icon_normal_color", UiKit.DIM)


func _on_tab_pressed(screen: int) -> void:
	"""Navigate to the selected tab screen."""
	if screen == current_screen:
		return
	Nav.goto(screen)


func _on_back_pressed() -> void:
	"""Navigate to the parent screen, or call back_override when set."""
	if back_override.is_valid():
		back_override.call()
	else:
		Nav.back(current_screen)


func _vseparator_style() -> StyleBoxFlat:
	"""Thin vertical rule between Back and tabs."""
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiKit.LINE
	sb.content_margin_left = 1
	sb.content_margin_right = 1
	return sb
