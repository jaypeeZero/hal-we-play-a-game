class_name LaunchNotice
extends Control

## Pre-launch heads-up shown when one or more non-iced hulls will NOT sortie
## because they have no pilot (dismissed, killed, or never crewed). Lists the
## ships staying behind so a hull is never silently left out of a battle.
## `resolved(true)` launches anyway; `resolved(false)` returns to the map.

signal resolved(launch: bool)

const MODAL_WIDTH := 460


func setup(benched: Array) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(RogueliteUi.backdrop())

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var modal := PanelContainer.new()
	modal.custom_minimum_size = Vector2(MODAL_WIDTH, 0)
	modal.add_theme_stylebox_override("panel",
		RogueliteUi.panel_box(RogueliteUi.PANEL_2, Color("5a4a1a"), 14, 18))
	center.add_child(modal)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	modal.add_child(box)

	box.add_child(RogueliteUi.label("⚠ SHIPS STAYING BEHIND", RogueliteUi.GOLD, 12))
	box.add_child(RogueliteUi.label(
		"These hulls have no pilot and won't join the battle:", RogueliteUi.INK, 14))

	for hull in benched:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(RogueliteUi.label("•", RogueliteUi.DIM, 13))
		row.add_child(RogueliteUi.label(_type_label(hull.get("ship_type", "")), RogueliteUi.INK, 13))
		row.add_child(RogueliteUi.label("· no pilot", RogueliteUi.BAD, 11))
		box.add_child(row)

	box.add_child(RogueliteUi.label(
		"Crew them at a shop to bring them along.", RogueliteUi.DIM, 11))

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	var cancel := RogueliteUi.style_button(_button("Cancel"), "ghost")
	cancel.pressed.connect(func(): resolved.emit(false))
	buttons.add_child(cancel)
	var go := RogueliteUi.style_button(_button("Launch anyway"), "primary")
	go.pressed.connect(func(): resolved.emit(true))
	buttons.add_child(go)
	box.add_child(buttons)


func _button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	return btn


func _type_label(ship_type: String) -> String:
	return ship_type.replace("_", " ").capitalize()
