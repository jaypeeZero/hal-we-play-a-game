class_name DispatchesPanel
extends PanelContainer

## Left-anchored side panel for the 3D star map. Shows the campaign news feed
## grouped by star date (jump), most recent first. Mirrors DestinationPanel's
## construction style: built in code, added under CanvasLayer by the map.

const PANEL_WIDTH := 320
const SCREEN_MARGIN := 20

const COLLAPSE_GLYPH := "▾"
const EXPAND_GLYPH := "▸"

## Human-readable labels for ship_modifier field names.
const SHIP_FIELD_LABELS := {
	"pilot_accel_factor": "accel",
	"pilot_turn_factor": "turn rate",
	"fire_rate_factor": "fire rate",
	"accuracy_factor": "accuracy",
	"aggression_factor": "aggression",
	"composure_factor": "composure",
}

var _scroll: ScrollContainer
var _rows_box: VBoxContainer
var _toggle_btn: Button
var _badge_label: Label
var _collapsed := false
var _unseen_count := 0


func _ready() -> void:
	"""Build the panel UI tree."""
	custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	add_theme_stylebox_override("panel", UiKit.panel_box(UiKit.PANEL, UiKit.LINE))
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	offset_left = SCREEN_MARGIN
	offset_right = offset_left + PANEL_WIDTH
	visible = false

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	add_child(outer)

	# Header row: toggle + title + unseen badge
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	outer.add_child(header)

	_toggle_btn = Button.new()
	_toggle_btn.text = COLLAPSE_GLYPH
	UiKit.style_button(_toggle_btn, "ghost")
	_toggle_btn.pressed.connect(_on_toggle)
	header.add_child(_toggle_btn)

	var title_lbl := UiKit.label("Dispatches", UiKit.INK)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_lbl)

	_badge_label = UiKit.label("", UiKit.BAD, 11)
	_badge_label.visible = false
	header.add_child(_badge_label)

	# Scrollable body
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.custom_minimum_size = Vector2(0, 300)
	outer.add_child(_scroll)

	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 6)
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_rows_box)

	visible = true


## Rebuild dispatch rows from the feed (newest first). Clears all previous
## rows before rebuilding.
func refresh(feed: Array) -> void:
	"""Rebuild all rows from `feed`; groups entries by star_date."""
	for child in _rows_box.get_children():
		child.queue_free()

	if feed.is_empty():
		_rows_box.add_child(UiKit.label("No dispatches yet.", UiKit.DIM))
		_update_unseen_badge(0)
		return

	# Group entries by star_date, preserving newest-first order.
	var groups: Dictionary = {}   # star_date (int) -> Array of entries
	var date_order: Array = []    # star_date values in first-seen order

	for entry in feed:
		var sd: int = int(entry.get("star_date", 0))
		if not groups.has(sd):
			groups[sd] = []
			date_order.append(sd)
		groups[sd].append(entry)

	# Render each group with a section header.
	for sd in date_order:
		var section := UiKit.section_title("Stardate %d" % sd)
		_rows_box.add_child(section)

		for entry in groups[sd]:
			_rows_box.add_child(_build_row(entry))

	# Count unseen entries.
	var unseen: int = count_unseen(feed)
	_update_unseen_badge(unseen)
	_unseen_count = unseen


## Mark every entry in the feed as seen and refresh the badge.
func mark_all_seen(feed: Array) -> void:
	"""Set seen=true on all feed entries and update the unseen badge."""
	for entry in feed:
		entry["seen"] = true
	_unseen_count = 0
	_update_unseen_badge(0)


## Build a single dispatch row Control from a resolved event dict.
func _build_row(entry: Dictionary) -> Control:
	"""Build a card row for one event record."""
	var polarity: String = str(entry.get("polarity", "neutral"))
	var accent: Color = _polarity_color(polarity)

	var card := UiKit.card(UiKit.PANEL_2, UiKit.LINE)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)

	# Headline row: polarity badge + headline text.
	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 6)
	box.add_child(head_row)

	if polarity != "neutral":
		var pol_badge: PanelContainer = UiKit.badge(_polarity_glyph(polarity), accent)
		head_row.add_child(pol_badge)

	var headline: String = str(entry.get("headline", ""))
	var h_lbl := UiKit.label(headline, UiKit.INK, 13)
	h_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_row.add_child(h_lbl)

	# Effect summary badges.
	var effects: Array = entry.get("effects", [])
	if not effects.is_empty():
		var summaries: Array = summarize_effects(effects)
		if not summaries.is_empty():
			var fx_row := HBoxContainer.new()
			fx_row.add_theme_constant_override("separation", 4)
			box.add_child(fx_row)
			for s in summaries:
				var fx_color: Color = _polarity_color(s.get("polarity", "neutral"))
				fx_row.add_child(UiKit.badge(s.get("text", ""), fx_color))

	# Body text as a dim sub-label.
	var body: String = str(entry.get("body", ""))
	if not body.is_empty():
		var b_lbl := UiKit.label(body, UiKit.DIM, 11)
		b_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(b_lbl)

	return card


## Build a list of {text, polarity} summary dicts for an effects array.
## Pure — no scene tree access.
static func summarize_effects(effects: Array) -> Array:
	"""Return an Array of {text: String, polarity: String} for each effect in `effects`."""
	var result: Array = []
	for effect in effects:
		var s: Dictionary = summarize_effect(effect)
		if not s.get("text", "").is_empty():
			result.append(s)
	return result


## Map a single effect descriptor to a short human-readable summary.
## Returns {text: String, polarity: String} — no widgets, pure function.
static func summarize_effect(effect: Dictionary) -> Dictionary:
	"""Map one effect dict to {text, polarity}. All kinds handled; no hard-coded values."""
	var kind: String = str(effect.get("kind", ""))
	var value = effect.get("value", null)
	var duration: String = str(effect.get("duration", "permanent"))
	var dur_str: String = _duration_label(duration)

	match kind:
		"ship_modifier":
			var field: String = str(effect.get("field", ""))
			var field_label: String = SHIP_FIELD_LABELS.get(field, field)
			var pct: float = float(value) * 100.0 if value != null else 0.0
			var sign: String = "+" if pct >= 0.0 else ""
			var text: String = "%s%.0f%% %s" % [sign, pct, field_label]
			if not dur_str.is_empty():
				text += " · %s" % dur_str
			var pol: String = "positive" if pct >= 0.0 else "negative"
			return {"text": text, "polarity": pol}

		"crew_skill":
			var skill: String = str(effect.get("skill", ""))
			var pct: float = float(value) * 100.0 if value != null else 0.0
			var sign: String = "+" if pct >= 0.0 else ""
			var text: String = "%s%.0f%% %s" % [sign, pct, skill.replace("_", " ")]
			if not dur_str.is_empty():
				text += " · %s" % dur_str
			var pol: String = "positive" if pct >= 0.0 else "negative"
			return {"text": text, "polarity": pol}

		"ship_repair":
			var section: String = str(effect.get("section", ""))
			var amt: int = int(value) if value != null else 0
			var text: String = "+%d repair (%s)" % [amt, section]
			return {"text": text, "polarity": "positive"}

		"ship_damage":
			var section: String = str(effect.get("section", ""))
			var amt: int = int(value) if value != null else 0
			var text: String = "−%d damage (%s)" % [amt, section]
			return {"text": text, "polarity": "negative"}

		"add_attribute":
			var attr_id: String = str(effect.get("attribute", ""))
			var defn: Dictionary = AttributeLibrary.get_def(attr_id)
			var display: String = defn.get("display_name", attr_id) if not defn.is_empty() else attr_id
			return {"text": "+Trait: %s" % display, "polarity": "positive"}

		"remove_attribute":
			var attr_id: String = str(effect.get("attribute", ""))
			var defn: Dictionary = AttributeLibrary.get_def(attr_id)
			var display: String = defn.get("display_name", attr_id) if not defn.is_empty() else attr_id
			return {"text": "−Trait: %s" % display, "polarity": "neutral"}

		"money":
			var amt: int = int(value) if value != null else 0
			var sign: String = "+" if amt >= 0 else ""
			var text: String = "%s%d₵" % [sign, amt]
			var pol: String = "positive" if amt >= 0 else "negative"
			return {"text": text, "polarity": pol}

		"intel":
			var scope: String = str(effect.get("scope", ""))
			var pct: float = float(value) * 100.0 if value != null else 0.0
			var sign: String = "+" if pct >= 0.0 else ""
			var text: String = "%s%.0f%% %s" % [sign, pct, scope.replace("_", " ")]
			if not dur_str.is_empty():
				text += " · %s" % dur_str
			var pol: String = "positive" if pct >= 0.0 else "negative"
			return {"text": text, "polarity": pol}

		_:
			return {"text": "", "polarity": "neutral"}


## Count entries in the feed that have seen == false.
static func count_unseen(feed: Array) -> int:
	"""Return the number of entries in `feed` where seen is false."""
	var n: int = 0
	for entry in feed:
		if not entry.get("seen", true):
			n += 1
	return n


# ---- private helpers ----

func _on_toggle() -> void:
	_collapsed = not _collapsed
	_scroll.visible = not _collapsed
	_toggle_btn.text = EXPAND_GLYPH if _collapsed else COLLAPSE_GLYPH


func _update_unseen_badge(count: int) -> void:
	"""Show or hide the unseen-count badge in the header."""
	if count > 0:
		_badge_label.text = "(%d new)" % count
		_badge_label.visible = true
	else:
		_badge_label.visible = false


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


static func _duration_label(duration: String) -> String:
	"""Convert a duration string ('permanent' or 'battles:N') to a display label."""
	if duration == "permanent" or duration.is_empty():
		return ""
	if duration.begins_with("battles:"):
		var parts: Array = duration.split(":")
		if parts.size() == 2:
			var n: int = int(parts[1])
			return "%d battle%s" % [n, "s" if n != 1 else ""]
	return duration
