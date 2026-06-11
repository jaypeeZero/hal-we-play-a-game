class_name StandingInstructionsSystem
extends RefCounted

## Player standing instructions (DOCS/plans/06, increment 2).
##
## A standing instruction is a player-authored tactical pattern — same
## schema as the patterns in data/knowledge/*.json — saved in a JSON file
## per crew member of the roguelike run:
##
##   user://standing_instructions/{crew_id}.json
##   { "pattern_id": { "tags": [...], "text": "...", "content": {...} } }
##
## Applying instructions registers each pattern in TacticalKnowledgeSystem
## with the player-priority flag (a relevant instruction outranks role
## doctrine) and adds it to the crew member's known_patterns. No UI yet:
## the files are authored by hand or by tooling between battles.

const INSTRUCTIONS_DIR := "user://standing_instructions"

static func instruction_file_path(crew_id: String) -> String:
	return "%s/%s.json" % [INSTRUCTIONS_DIR, crew_id]

## Instruction ids are namespaced per crew member so two crew members can
## use the same pattern id without colliding in the shared knowledge base.
static func registered_pattern_id(crew_id: String, pattern_id: String) -> String:
	return "%s__%s" % [crew_id, pattern_id]

## Write a crew member's standing instructions to their file.
static func save_instructions(crew_id: String, patterns: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(INSTRUCTIONS_DIR)
	var file = FileAccess.open(instruction_file_path(crew_id), FileAccess.WRITE)
	if file == null:
		push_error("StandingInstructionsSystem: cannot write %s" % instruction_file_path(crew_id))
		return
	file.store_string(JSON.stringify(patterns, "\t"))

## Read a crew member's standing instructions; empty dict if none exist.
static func load_instructions(crew_id: String) -> Dictionary:
	var path = instruction_file_path(crew_id)
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		push_error("StandingInstructionsSystem: invalid JSON in %s" % path)
		return {}
	return data

## Register player patterns and add them to the crew member's knowledge
## set. Pure: returns an updated copy. A crew member whose known_patterns
## was empty (= full role baseline) keeps that baseline: it is expanded to
## explicit pattern ids before the instructions are added, so instructions
## extend doctrine rather than replace it. Idempotent across battles.
static func apply_instructions(crew: Dictionary, patterns: Dictionary) -> Dictionary:
	if patterns.is_empty():
		return crew

	var updated = crew.duplicate(true)
	var role: int = updated.get("role", -1)

	if updated.known_patterns.is_empty():
		for entry in TacticalKnowledgeSystem.get_patterns_for_role(role):
			updated.known_patterns.append(entry.id)

	for pattern_id in patterns:
		var p: Dictionary = patterns[pattern_id]
		var registered_id = registered_pattern_id(updated.crew_id, pattern_id)
		TacticalKnowledgeSystem.add_knowledge_pattern(
			registered_id, role,
			p.get("tags", []), p.get("text", ""), p.get("content", {}),
			true)
		if registered_id not in updated.known_patterns:
			updated.known_patterns.append(registered_id)

	return updated

## Load the crew member's saved instructions (if any) and apply them.
static func load_and_apply(crew: Dictionary) -> Dictionary:
	return apply_instructions(crew, load_instructions(crew.get("crew_id", "")))
