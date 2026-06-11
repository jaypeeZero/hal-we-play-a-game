class_name LogConsole
extends Control

## Quake-style dropdown log console for Battle mode.
##
## Tails the BattleEventLogger event stream live, lets the player scroll back
## through the whole battle, and filters the visible lines on the fly.
##
## Controls:
## - `~` (backtick)  toggles the console open/closed
## - `/`             (while open) opens a live filter textbox
## - `Esc`           closes the filter, or the console if no filter is open
##
## While the console is open it captures input: gameplay and camera ignore the
## keyboard (see `LogConsole.capturing_input`) so typing a filter never spawns
## ships or pans the camera.

# True whenever a console is open. Gameplay/camera read this to stop reacting to
# input while the player is interacting with the console. It is UI modality
# state, deliberately kept out of the game-logic data arrays.
static var capturing_input: bool = false

# Fraction of the viewport height the dropped console covers.
const CONSOLE_HEIGHT_RATIO: float = 0.45
# Seconds for the drop-down / retract slide.
const SLIDE_DURATION: float = 0.18
# Cap on retained lines so a long battle can't grow memory without bound. The
# oldest lines are dropped first; this is still far more than a battle produces.
const MAX_LOG_ENTRIES: int = 5000
const FONT_SIZE: int = 14
# Padding inside the panel around the text.
const PANEL_MARGIN: int = 8

# Toggle key (the `~`/backtick key) and the filter key.
const TOGGLE_KEY: int = KEY_QUOTELEFT
const FILTER_KEY: int = KEY_SLASH

# Per-category colors (hex, no leading '#').
const COLOR_DEFAULT: String = "d0d0d0"
const COLOR_DAMAGE: String = "ff6b6b"
const COLOR_AI: String = "8a8a8a"
const COLOR_WEAPON: String = "ffd166"
const COLOR_SPAWN: String = "06d6a0"
const COLOR_GAME: String = "4cc9f0"
const COLOR_ORDER: String = "c792ea"

# Backing store of formatted entries: {type, line, search}.
var _entries: Array[Dictionary] = []
var _filter: String = ""
var _filter_active: bool = false
var _is_open: bool = false
var _console_height: float = 0.0
var _slide_tween: Tween

var _panel: Panel
var _log_label: RichTextLabel
var _filter_row: HBoxContainer
var _filter_line: LineEdit

func _ready() -> void:
	_build_ui()
	_layout()
	get_viewport().size_changed.connect(_layout)

	# Seed history so the player can scroll back to the start of the battle,
	# then tail live. track_history must be on for the seed to be populated.
	var logger: Node = _logger()
	if logger:
		logger.track_history = true
		for event: Dictionary in logger.event_history:
			_entries.append(_make_entry(event))
		logger.event_occurred.connect(add_event)
	_render()

func _logger() -> Node:
	if BattleEventLoggerAutoload and BattleEventLoggerAutoload.service:
		return BattleEventLoggerAutoload.service
	return null

# ============================================================================
# UI CONSTRUCTION
# ============================================================================

func _build_ui() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true

	_panel = Panel.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.09, 0.92)
	style.border_color = Color(0.2, 0.8, 0.9, 0.6)
	style.border_width_bottom = 2
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, PANEL_MARGIN)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	margin.add_child(vbox)

	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = true
	_log_label.scroll_active = true
	_log_label.selection_enabled = true
	_log_label.focus_mode = Control.FOCUS_NONE
	_log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_label.add_theme_font_size_override("normal_font_size", FONT_SIZE)
	vbox.add_child(_log_label)

	_filter_row = HBoxContainer.new()
	_filter_row.visible = false
	var slash := Label.new()
	slash.text = "/"
	slash.add_theme_font_size_override("font_size", FONT_SIZE)
	_filter_row.add_child(slash)
	_filter_line = LineEdit.new()
	_filter_line.placeholder_text = "filter logs..."
	_filter_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filter_line.add_theme_font_size_override("font_size", FONT_SIZE)
	_filter_line.text_changed.connect(_on_filter_changed)
	_filter_row.add_child(_filter_line)
	vbox.add_child(_filter_row)

func _layout() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	_console_height = viewport_size.y * CONSOLE_HEIGHT_RATIO

	anchor_right = 1.0
	offset_left = 0.0
	offset_right = 0.0
	offset_top = 0.0
	offset_bottom = _console_height

	_panel.size = Vector2(viewport_size.x, _console_height)
	_panel.position.y = 0.0 if _is_open else -_console_height

# ============================================================================
# OPEN / CLOSE / FILTER
# ============================================================================

func toggle() -> void:
	if _is_open:
		_close()
	else:
		_open()

func is_open() -> bool:
	return _is_open

func _open() -> void:
	_is_open = true
	capturing_input = true
	_slide_to(0.0)

func _close() -> void:
	_is_open = false
	capturing_input = false
	_close_filter()
	_slide_to(-_console_height)

func _slide_to(target_y: float) -> void:
	if _slide_tween and _slide_tween.is_running():
		_slide_tween.kill()
	_slide_tween = create_tween()
	_slide_tween.tween_property(_panel, "position:y", target_y, SLIDE_DURATION) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _open_filter() -> void:
	_filter_active = true
	_filter_row.visible = true
	_filter_line.grab_focus()

func _close_filter() -> void:
	if not _filter_active:
		return
	_filter_active = false
	_filter_row.visible = false
	_filter_line.release_focus()
	_filter_line.text = ""
	apply_filter("")

func _on_filter_changed(text: String) -> void:
	apply_filter(text)

## Set the live filter (case-insensitive substring) and re-render.
func apply_filter(text: String) -> void:
	_filter = text.to_lower()
	_render()

# ============================================================================
# EVENTS & RENDERING
# ============================================================================

## Append a logged event to the console and tail to it when at the bottom.
func add_event(event: Dictionary) -> void:
	_entries.append(_make_entry(event))
	if _entries.size() > MAX_LOG_ENTRIES:
		_entries = _entries.slice(_entries.size() - MAX_LOG_ENTRIES)
	_render()

func _make_entry(event: Dictionary) -> Dictionary:
	var timestamp: float = event.get("timestamp", 0.0)
	var type: String = event.get("type", "?")
	var data: Dictionary = event.get("data", {})
	var line: String = "[%7.2fs] %-18s %s" % [timestamp, type, _format_data(data)]
	return {"type": type, "line": line, "search": line.to_lower()}

func _format_data(data: Dictionary) -> String:
	var parts: Array[String] = []
	for key: Variant in data:
		parts.append("%s=%s" % [key, str(data[key])])
	return " ".join(parts)

func _render() -> void:
	if not is_instance_valid(_log_label):
		return
	var was_at_bottom: bool = _is_at_bottom()
	var lines := PackedStringArray()
	for entry: Dictionary in _entries:
		if _filter != "" and not entry.search.contains(_filter):
			continue
		lines.append("[color=#%s]%s[/color]" % [_color_for_type(entry.type), _escape_bbcode(entry.line)])
	_log_label.text = "\n".join(lines)
	if was_at_bottom:
		call_deferred("_scroll_to_bottom")

func _is_at_bottom() -> bool:
	var bar: VScrollBar = _log_label.get_v_scroll_bar()
	if not bar:
		return true
	return bar.value >= bar.max_value - bar.page - 1.0

func _scroll_to_bottom() -> void:
	var bar: VScrollBar = _log_label.get_v_scroll_bar()
	if bar:
		bar.value = bar.max_value

func _color_for_type(type: String) -> String:
	if type.contains("damage") or type.contains("destroyed"):
		return COLOR_DAMAGE
	if type.begins_with("ai_"):
		return COLOR_AI
	if type == "weapon_fired":
		return COLOR_WEAPON
	if type.contains("spawn"):
		return COLOR_SPAWN
	if type == "order_issued":
		return COLOR_ORDER
	if type.begins_with("game_"):
		return COLOR_GAME
	return COLOR_DEFAULT

# RichTextLabel reads '[' as a bbcode tag; '[lb]' renders a literal '['.
func _escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]")

# Test helpers ---------------------------------------------------------------

func entry_count() -> int:
	return _entries.size()

## Number of entries that pass the current filter (i.e. currently shown).
func visible_entry_count() -> int:
	var count := 0
	for entry: Dictionary in _entries:
		if _filter == "" or entry.search.contains(_filter):
			count += 1
	return count

# ============================================================================
# INPUT
# ============================================================================

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key: int = event.keycode

	if key == TOGGLE_KEY:
		toggle()
		get_viewport().set_input_as_handled()
		return

	if not _is_open:
		return

	if key == KEY_ESCAPE:
		if _filter_active:
			_close_filter()
		else:
			_close()
		get_viewport().set_input_as_handled()
		return

	if key == FILTER_KEY and not _filter_active:
		_open_filter()
		get_viewport().set_input_as_handled()
		return
