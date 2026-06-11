extends Node

## Temporary dev harness: boots a roguelike run, loads the pre-battle
## screen, drives the doctrine panel to a hull selection, and saves a
## screenshot for visual verification.

const OUTPUT_PATH := "/tmp/doctrine_panel.png"
const SETTLE_FRAMES := 15
const FIRST_HULL_OPTION := 3  # after Entire fleet, All Fighters, All Corvettes


func _ready() -> void:
	RoguelikeRun.start_run({"fighter": 3, "heavy_fighter": 0,
		"torpedo_boat": 0, "corvette": 1, "capital": 0})
	DoctrineSystem.set_instruction_in_place(
		RoguelikeRun.doctrine, DoctrineSystem.SCOPE_FLEET, "", "charge_head_on")
	DoctrineSystem.set_instruction_in_place(
		RoguelikeRun.doctrine, DoctrineSystem.SCOPE_CLASS, "fighter",
		"keep_clear_of", {"target_class": "capital"})

	var scene: Node = load("res://scenes/pre_battle.tscn").instantiate()
	add_child(scene)
	await _settle()

	var panel := _find_panel(scene)
	if panel == null:
		push_error("Harness: doctrine panel not found in pre-battle UI")
	else:
		panel._ship_dropdown.select(FIRST_HULL_OPTION)
		panel._on_ship_selected(FIRST_HULL_OPTION)
	await _settle()

	get_viewport().get_texture().get_image().save_png(OUTPUT_PATH)
	print("HARNESS_SCREENSHOT_SAVED panel_found=%s" % (panel != null))
	get_tree().quit()


func _settle() -> void:
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame


func _find_panel(scene: Node) -> DoctrinePanel:
	for child in scene.get_node("UI").get_children():
		if child is DoctrinePanel:
			return child
	return null
