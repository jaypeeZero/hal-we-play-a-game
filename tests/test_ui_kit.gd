extends GutTest

## Tests for UiKit - FUNCTIONALITY ONLY.
## Verifies the design system's widget factories and theme behave correctly
## (clamping, state preservation, styled node types) without asserting
## specific palette values, which are visual-design decisions.


# BUTTONS

func test_style_button_preserves_text_and_disabled_state():
	var btn := Button.new()
	btn.text = "Buy ship"
	btn.disabled = true

	var styled := UiKit.style_button(btn, "primary")

	assert_same(styled, btn, "Styles the given button in place")
	assert_eq(styled.text, "Buy ship", "Styling does not touch the label")
	assert_true(styled.disabled, "Styling does not re-enable the button")
	btn.free()


func test_style_button_styles_every_interaction_state():
	for kind in ["primary", "ghost", "warn"]:
		var btn := UiKit.style_button(Button.new(), kind)
		for state in ["normal", "hover", "pressed", "disabled"]:
			assert_true(btn.has_theme_stylebox_override(state),
				"%s button has a %s stylebox" % [kind, state])
		btn.free()


func test_button_kinds_are_visually_distinct():
	var primary := UiKit.style_button(Button.new())
	var warn := UiKit.style_button(Button.new(), "warn")

	assert_ne(primary.get_theme_color("font_color"), warn.get_theme_color("font_color"),
		"Primary and warn buttons must not look identical")
	primary.free()
	warn.free()


# METERS

func test_meter_bar_clamps_ratio_to_valid_range():
	for widget in [_find_progress_bar(UiKit.meter_bar("armor", 1.7, UiKit.GOOD)),
			_find_progress_bar(UiKit.mini_meter("sys", -0.3, UiKit.BAD))]:
		assert_not_null(widget, "Meter contains a progress bar")
		assert_between(widget.value, 0.0, 1.0, "Ratio is clamped to 0..1")


func _find_progress_bar(root: Control) -> ProgressBar:
	add_child_autofree(root)
	return root.find_children("*", "ProgressBar", true, false).front()


# WIDGET FACTORIES

func test_factories_return_usable_control_types():
	var widgets := {
		"backdrop": UiKit.backdrop(),
		"card": UiKit.card(),
		"label": UiKit.label("hi"),
		"section_title": UiKit.section_title("SHIPS"),
		"badge": UiKit.badge("On ice"),
	}
	for name in widgets:
		assert_true(widgets[name] is Control, "%s returns a Control" % name)
		widgets[name].free()


func test_label_applies_requested_text():
	var l := UiKit.label("Leave shop")
	assert_eq(l.text, "Leave shop")
	l.free()


# THEME

func test_build_theme_styles_core_control_types():
	var theme := UiKit.build_theme()

	assert_true(theme.has_color("font_color", "Label"), "Labels get a font colour")
	assert_true(theme.has_stylebox("normal", "Button"), "Buttons get a base stylebox")
	assert_true(theme.has_stylebox("disabled", "Button"), "Buttons get a disabled stylebox")
	assert_true(theme.has_stylebox("panel", "PanelContainer"), "Panels get a stylebox")
	assert_true(theme.has_stylebox("fill", "ProgressBar"), "Progress bars get a fill")
	assert_true(theme.has_stylebox("normal", "LineEdit"), "Line edits get a stylebox")


func test_theme_button_matches_a_style_button_kind():
	# The root theme's default button must be one of style_button's kinds so
	# .tscn buttons and code-built buttons can't drift apart.
	var theme := UiKit.build_theme()
	var themed_fg: Color = theme.get_color("font_color", "Button")

	var kinds_fg: Array[Color] = []
	for kind in ["primary", "ghost", "warn"]:
		var btn := UiKit.style_button(Button.new(), kind)
		kinds_fg.append(btn.get_theme_color("font_color"))
		btn.free()

	assert_has(kinds_fg, themed_fg, "Theme default button is one of the styled kinds")
