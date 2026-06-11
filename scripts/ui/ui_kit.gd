class_name UiKit
extends RefCounted

## The game's design system: one palette, styleboxes, and pre-styled widgets
## so every screen reads as one console UI without duplicating theme code.
## Ported from design/*.mockup.html (the visual reference).
##
## Two ways to consume it:
## - build_theme() is applied to the scene tree root at startup
##   (UiThemeAutoload), so plain Labels/Buttons/Panels in any scene get the
##   base look with no per-node overrides.
## - The static factories below (card, section_title, badge, meter_bar, ...)
##   build the composite widgets for code-constructed screens.

# ---- palette ----
const BG         := Color("0a0e14")
const PANEL      := Color("121822")
const PANEL_2    := Color("161e2b")
const LINE       := Color("243140")
const INK        := Color("dfe8f2")
const DIM        := Color("8595a8")
const ACCENT     := Color("43d1ff")
const ACCENT_DIM := Color("1d6f8c")
const GOLD       := Color("ffce5c")
const GOOD       := Color("5cff9d")
const BAD        := Color("ff6b6b")
const CHIP       := Color("1c2735")
const DISABLED_INK := Color("4a5567")
const TRACK_BG   := Color("0c121b")
const WARN_BORDER := Color("5a2a2a")
const GOLD_BORDER := Color("5a4a1a")
const PRIMARY_INK := Color("04222c")

const RADIUS := 10
const CARD_PAD := 12
const FONT_BODY := 14


# ============================================================================
# STYLEBOXES
# ============================================================================

static func panel_box(bg: Color, border: Color, radius := RADIUS, pad := CARD_PAD) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(1)
	sb.border_color = border
	sb.set_content_margin_all(pad)
	return sb


static func _button_box(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(6)
	if border.a > 0.0:
		sb.set_border_width_all(1)
		sb.border_color = border
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


# ============================================================================
# WIDGETS
# ============================================================================

## Full-screen opaque backdrop so the scene behind doesn't bleed through.
static func backdrop(color := BG) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return rect


## A bordered card panel (the standard container for ships, hulls, ledgers).
static func card(bg := PANEL, border := LINE, pad := CARD_PAD) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_box(bg, border, RADIUS, pad))
	return p


static func label(text: String, color := INK, size := FONT_BODY) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	return l


## An accent section header with an underline rule, e.g. "SHIPS FOR SALE".
static func section_title(text: String, note := "") -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var head := HBoxContainer.new()
	var title := label(text.to_upper(), ACCENT, 13)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	if note != "":
		head.add_child(label(note, DIM, 11))
	row.add_child(head)
	var rule := _rule()
	row.add_child(rule)
	return row


## A 1px horizontal divider in the line colour.
static func _rule() -> Control:
	var sep := HSeparator.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = LINE
	sb.content_margin_top = 1
	sep.add_theme_stylebox_override("separator", sb)
	return sep


static func separator() -> Control:
	return _rule()


## Styleboxes and font colour for one button kind; shared by style_button
## and build_theme so per-node styling and the root theme can't drift apart.
static func _button_styles(kind: String) -> Dictionary:
	var fg: Color
	var bg: Color
	var border := Color(0, 0, 0, 0)
	match kind:
		"ghost":
			fg = ACCENT
			bg = Color(0, 0, 0, 0)
			border = ACCENT_DIM
		"warn":
			fg = BAD
			bg = Color(0, 0, 0, 0)
			border = WARN_BORDER
		_:
			fg = PRIMARY_INK
			bg = ACCENT

	var hover := bg.lightened(0.08) if kind == "primary" else Color(fg.r, fg.g, fg.b, 0.10)
	return {
		"normal": _button_box(bg, border),
		"hover": _button_box(hover, border),
		"pressed": _button_box(hover, border),
		"disabled": _button_box(CHIP, LINE),
		"fg": fg,
	}


## Style a button in one of three kinds: "primary" (filled accent),
## "ghost" (accent outline), "warn" (red outline). Preserves the button's
## existing text and disabled behaviour.
static func style_button(btn: Button, kind := "primary") -> Button:
	var styles := _button_styles(kind)
	btn.add_theme_stylebox_override("normal", styles.normal)
	btn.add_theme_stylebox_override("hover", styles.hover)
	btn.add_theme_stylebox_override("pressed", styles.pressed)
	btn.add_theme_stylebox_override("disabled", styles.disabled)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", styles.fg)
	btn.add_theme_color_override("font_hover_color", styles.fg)
	btn.add_theme_color_override("font_pressed_color", styles.fg)
	btn.add_theme_color_override("font_disabled_color", DISABLED_INK)
	return btn


## A small uppercase status badge (e.g. "ON ICE") in an accent outline.
static func badge(text: String, color := ACCENT) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_corner_radius_all(4)
	sb.set_border_width_all(1)
	sb.border_color = Color(color.r, color.g, color.b, 0.5)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(label(text.to_upper(), color, 10))
	return p


## The bordered track + clamped fill of a condition meter; shared by
## meter_bar and mini_meter. `width` 0 leaves sizing to the caller.
static func _meter_track(ratio: float, fill: Color, height: int, width := 0) -> PanelContainer:
	var track := PanelContainer.new()
	track.custom_minimum_size = Vector2(width, height)
	var track_box := StyleBoxFlat.new()
	track_box.bg_color = TRACK_BG
	track_box.set_corner_radius_all(4)
	track_box.set_border_width_all(1)
	track_box.border_color = LINE
	track.add_theme_stylebox_override("panel", track_box)

	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = clampf(ratio, 0.0, 1.0)
	bar.show_percentage = false
	var under := StyleBoxFlat.new()
	under.bg_color = Color(0, 0, 0, 0)
	bar.add_theme_stylebox_override("background", under)
	var fg_box := StyleBoxFlat.new()
	fg_box.bg_color = fill
	fg_box.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fg_box)
	track.add_child(bar)
	return track


## A labelled progress bar (armor/systems condition). `ratio` is 0..1.
static func meter_bar(key: String, ratio: float, fill: Color, low := false) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(label(key.to_upper(), DIM, 10))

	var track := _meter_track(ratio, fill, 9)
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(track)

	row.add_child(label("%d%%" % int(round(ratio * 100.0)), BAD if low else INK, 11))
	return row


## Compact inline condition meter for a header row: a fixed-width track and a
## right-aligned percent, so several fit on one line beside other widgets.
static func mini_meter(key: String, ratio: float, fill: Color, low := false, track_width := 60) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(label(key, DIM, 10))
	row.add_child(_meter_track(ratio, fill, 7, track_width))

	var pct := label("%d%%" % int(round(ratio * 100.0)), BAD if low else INK, 11)
	pct.custom_minimum_size = Vector2(34, 0)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(pct)
	return row


# THEME

## The project-wide Theme, applied to the scene-tree root at startup by
## UiThemeAutoload. Gives plain controls (.tscn screens included) the base
## console look; the factories above remain for composite widgets. Buttons
## default to the "ghost" kind — use style_button() for primary/warn.
static func build_theme() -> Theme:
	var theme := Theme.new()

	theme.set_color("font_color", "Label", INK)
	theme.set_font_size("font_size", "Label", FONT_BODY)

	var btn := _button_styles("ghost")
	theme.set_stylebox("normal", "Button", btn.normal)
	theme.set_stylebox("hover", "Button", btn.hover)
	theme.set_stylebox("pressed", "Button", btn.pressed)
	theme.set_stylebox("disabled", "Button", btn.disabled)
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_color("font_color", "Button", btn.fg)
	theme.set_color("font_hover_color", "Button", btn.fg)
	theme.set_color("font_pressed_color", "Button", btn.fg)
	theme.set_color("font_disabled_color", "Button", DISABLED_INK)
	theme.set_font_size("font_size", "Button", FONT_BODY)

	theme.set_stylebox("panel", "Panel", panel_box(PANEL, LINE))
	theme.set_stylebox("panel", "PanelContainer", panel_box(PANEL, LINE))

	var rule := StyleBoxFlat.new()
	rule.bg_color = LINE
	rule.content_margin_top = 1
	theme.set_stylebox("separator", "HSeparator", rule)

	theme.set_stylebox("background", "ProgressBar", panel_box(TRACK_BG, LINE, 4, 0))
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = ACCENT
	bar_fill.set_corner_radius_all(3)
	theme.set_stylebox("fill", "ProgressBar", bar_fill)

	theme.set_stylebox("normal", "LineEdit", panel_box(PANEL_2, LINE, 6, 8))
	theme.set_color("font_color", "LineEdit", INK)
	theme.set_color("caret_color", "LineEdit", ACCENT)

	return theme
