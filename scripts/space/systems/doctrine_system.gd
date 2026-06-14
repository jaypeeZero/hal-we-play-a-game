class_name DoctrineSystem
extends RefCounted

## Fleet doctrine: player standing instructions for a roguelike run.
##
## Doctrine is run state (RoguelikeRun.doctrine). Players never author
## pattern text: they pick parameterized templates from the catalog in
## data/instruction_templates.json and assign them at one of three
## scopes — fleet-wide, a ship class, or an individual crew member.
## A template's `text`/`tags` describe the situations the order applies
## in; its `content` is what the crew member actually does there.
##
## At battle spawn compile_for_crew() resolves scopes (individual >
## class > fleet per template, per-crew disables honored), instantiates
## each template into a normal tactical pattern, registers it with the
## player-priority flag, and lands the ids in the crew member's
## known_patterns. The retrieval engine is unchanged.

const TEMPLATES_PATH := "res://data/instruction_templates.json"

## Doctrine scopes, most general to most specific. SCOPE_CLASS and
## SCOPE_CREW entries are keyed by ship type / crew_id respectively.
const SCOPE_FLEET := "fleet"
const SCOPE_CLASS := "classes"
const SCOPE_CREW := "crew"

## Compiled doctrine pattern ids carry this prefix so a later compile can
## strip instructions that were removed or re-parameterized between battles.
const DOCTRINE_PATTERN_PREFIX := "doctrine__"

## Which skill gates a role's pattern execution (mirrors the role AIs).
const ROLE_EXECUTION_SKILL := {
	CrewData.Role.PILOT: "piloting",
	CrewData.Role.GUNNER: "aim",
	CrewData.Role.CAPTAIN: "tactics",
	CrewData.Role.SQUADRON_LEADER: "tactics",
	CrewData.Role.FLEET_COMMANDER: "tactics",
	CrewData.Role.ENGINEER: "machinery",
}

static var _templates: Dictionary = {}
static var _templates_loaded := false


static func empty_doctrine() -> Dictionary:
	return {SCOPE_FLEET: {}, SCOPE_CLASS: {}, SCOPE_CREW: {}, "disabled": {}}


# ============================================================================
# TEMPLATE CATALOG
# ============================================================================

static func _ensure_templates_loaded() -> void:
	if _templates_loaded:
		return
	_templates_loaded = true
	var data = JSON.parse_string(FileAccess.get_file_as_string(TEMPLATES_PATH))
	if not data is Dictionary:
		push_error("DoctrineSystem: invalid JSON in %s" % TEMPLATES_PATH)
		return
	_templates = data.get("templates", {})


static func get_all_templates() -> Dictionary:
	_ensure_templates_loaded()
	return _templates


static func get_template(template_id: String) -> Dictionary:
	_ensure_templates_loaded()
	return _templates.get(template_id, {})


## Instantiate a template into a tactical pattern, substituting "{param}"
## tokens in tags, text, and content with the given (or default) values.
static func instantiate_template(template_id: String, params: Dictionary = {}) -> Dictionary:
	var template := get_template(template_id)
	if template.is_empty():
		return {}
	var filled := {}
	for key in template.get("params", {}):
		filled[key] = params.get(key, template.params[key].get("default"))
	return _substitute(template.get("pattern", {}), filled)


static func _substitute(value, params: Dictionary):
	if value is String:
		var s: String = value
		for key in params:
			s = s.replace("{%s}" % key, str(params[key]))
		return s
	if value is Array:
		var arr := []
		for v in value:
			arr.append(_substitute(v, params))
		return arr
	if value is Dictionary:
		var d := {}
		for k in value:
			d[_substitute(k, params)] = _substitute(value[k], params)
		return d
	return value


# ============================================================================
# DOCTRINE EDITING (one-owner state on RoguelikeRun, mutated in place)
# ============================================================================

## Assign a template at a scope. One instance per template per scope:
## re-assigning replaces the params. scope_key is the ship type for
## SCOPE_CLASS, the crew_id for SCOPE_CREW, and ignored for SCOPE_FLEET.
static func set_instruction_in_place(doctrine: Dictionary, scope: String, scope_key: String, template_id: String, params: Dictionary = {}) -> void:
	if scope == SCOPE_FLEET:
		doctrine[SCOPE_FLEET][template_id] = params
		return
	if not doctrine[scope].has(scope_key):
		doctrine[scope][scope_key] = {}
	doctrine[scope][scope_key][template_id] = params


static func remove_instruction_in_place(doctrine: Dictionary, scope: String, scope_key: String, template_id: String) -> void:
	if scope == SCOPE_FLEET:
		doctrine[SCOPE_FLEET].erase(template_id)
		return
	if doctrine[scope].has(scope_key):
		doctrine[scope][scope_key].erase(template_id)


## Disable (or re-enable) an inherited instruction for one crew member.
static func set_disabled_in_place(doctrine: Dictionary, crew_id: String, template_id: String, disabled: bool) -> void:
	var list: Array = doctrine["disabled"].get(crew_id, [])
	if disabled and template_id not in list:
		list.append(template_id)
	elif not disabled:
		list.erase(template_id)
	doctrine["disabled"][crew_id] = list


# ============================================================================
# SCOPE RESOLUTION
# ============================================================================

## The instructions affecting one crew member, every matching scope layer
## included for provenance display. Entry shape:
##   {template_id, params, scope, overridden, disabled}
## An entry is overridden when a more specific scope redefines the same
## template; the active set is the entries that are neither overridden
## nor disabled.
static func effective_instructions(doctrine: Dictionary, crew: Dictionary, ship_type: String) -> Array:
	var crew_id: String = crew.get("crew_id", "")
	var entries := _layered_entries([
		{"scope": SCOPE_FLEET, "instances": doctrine.get(SCOPE_FLEET, {})},
		{"scope": SCOPE_CLASS, "instances": doctrine.get(SCOPE_CLASS, {}).get(ship_type, {})},
		{"scope": SCOPE_CREW, "instances": doctrine.get(SCOPE_CREW, {}).get(crew_id, {})},
	], crew.get("role", -1))
	var disabled: Array = doctrine.get("disabled", {}).get(crew_id, [])
	for entry in entries:
		entry.disabled = entry.template_id in disabled
	return entries


## The instructions visible when editing a scope directly (fleet or class
## selection in the UI): the scope's own entries plus inherited ones, no
## role filtering and no per-crew disables.
static func scope_view(doctrine: Dictionary, scope: String, scope_key: String = "") -> Array:
	var layers := [{"scope": SCOPE_FLEET, "instances": doctrine.get(SCOPE_FLEET, {})}]
	if scope == SCOPE_CLASS:
		layers.append({"scope": SCOPE_CLASS, "instances": doctrine.get(SCOPE_CLASS, {}).get(scope_key, {})})
	return _layered_entries(layers, -1)


## Walk scope layers general -> specific; a later layer's instance of the
## same template marks the earlier one overridden. role -1 = no filter.
static func _layered_entries(layers: Array, role: int) -> Array:
	var entries: Array = []
	var most_specific := {}
	for layer in layers:
		for template_id in layer.instances:
			var template := get_template(template_id)
			if template.is_empty():
				continue
			if role >= 0 and not _template_applies_to_role(template, role):
				continue
			if most_specific.has(template_id):
				entries[most_specific[template_id]].overridden = true
			most_specific[template_id] = entries.size()
			entries.append({
				"template_id": template_id,
				"params": layer.instances[template_id],
				"scope": layer.scope,
				"overridden": false,
				"disabled": false,
			})
	return entries


static func _template_applies_to_role(template: Dictionary, role: int) -> bool:
	return TacticalKnowledgeSystem.ROLE_NAMES.get(template.get("role", ""), -1) == role


# ============================================================================
# COMPILATION (battle spawn)
# ============================================================================

## Resolve the doctrine for one crew member and land it in their
## known_patterns. Pure: returns an updated copy. Previously compiled
## doctrine ids are stripped first, so instructions removed between
## battles do not linger; re-compiling is idempotent.
static func compile_for_crew(crew: Dictionary, ship_type: String, doctrine: Dictionary) -> Dictionary:
	var updated = crew.duplicate(true)

	var kept: Array = []
	for pattern_id in updated.known_patterns:
		if not str(pattern_id).begins_with(DOCTRINE_PATTERN_PREFIX):
			kept.append(pattern_id)
	updated.known_patterns = kept

	var patterns := {}
	for entry in effective_instructions(doctrine, updated, ship_type):
		if entry.overridden or entry.disabled:
			continue
		var pattern_id := doctrine_pattern_id(updated.crew_id, entry.template_id)
		patterns[pattern_id] = instantiate_template(entry.template_id, entry.params)
	return _apply_patterns(updated, patterns)


## Compiled pattern ids are namespaced per crew member so two crew with
## the same template (different params) never collide in the knowledge base.
static func doctrine_pattern_id(crew_id: String, template_id: String) -> String:
	return "%s%s__%s" % [DOCTRINE_PATTERN_PREFIX, crew_id, template_id]


## Register compiled patterns with player priority and add them to the
## crew member's knowledge set. A crew member whose known_patterns was
## empty (= full role baseline) keeps that baseline: it is expanded to
## explicit ids first, so doctrine extends role doctrine rather than
## replacing it. `crew` is the caller's already-duplicated copy.
static func _apply_patterns(crew: Dictionary, patterns: Dictionary) -> Dictionary:
	if patterns.is_empty():
		return crew

	var role: int = crew.get("role", -1)
	if crew.known_patterns.is_empty():
		for entry in TacticalKnowledgeSystem.get_patterns_for_role(role):
			# Role doctrine only: other crew members' compiled player
			# patterns share the role and must not enter this baseline.
			if entry.pattern.get("player_priority", false):
				continue
			crew.known_patterns.append(entry.id)

	for pattern_id in patterns:
		var p: Dictionary = patterns[pattern_id]
		TacticalKnowledgeSystem.add_knowledge_pattern(
			pattern_id, role,
			p.get("tags", []), p.get("text", ""), p.get("content", {}),
			true)
		if pattern_id not in crew.known_patterns:
			crew.known_patterns.append(pattern_id)

	return crew


# ============================================================================
# UI SUPPORT
# ============================================================================

## How far the crew member's execution skill falls short of the pattern's
## primary (first-listed) maneuver gate; 0.0 means they can execute it.
static func primary_maneuver_skill_gap(crew: Dictionary, pattern: Dictionary) -> float:
	var content: Dictionary = pattern.get("content", {})
	var maneuvers: Array = content.get("maneuvers", [])
	if maneuvers.is_empty():
		return 0.0
	var required: float = content.get("skill_requirements", {}).get(maneuvers[0], 0.0)
	var skill_name: String = ROLE_EXECUTION_SKILL.get(crew.get("role", -1), "tactics")
	var skill: float = crew.get("stats", {}).get("skills", {}).get(skill_name, 0.0)
	return max(0.0, required - skill)


## Display name for an assigned instruction, with params substituted into
## the template name ("Keep clear of capitals").
static func instruction_display_name(template_id: String, params: Dictionary = {}) -> String:
	var template := get_template(template_id)
	if template.is_empty():
		return template_id
	var filled := {}
	for key in template.get("params", {}):
		filled[key] = params.get(key, template.params[key].get("default"))
	return _substitute(template.get("name", template_id), filled)


## Map team-0 battle-plan entry indices to hull indices in
## RoguelikeRun.fleet_hulls, matched by the entry's hull_id (assigned by
## BattlePlanner.assign_hull_ids). Entries without a hull_id (or for a hull
## no longer present) are left unmapped.
static func map_entries_to_hulls(entries: Array, fleet_hulls: Array) -> Dictionary:
	var index_by_id := {}
	for h in range(fleet_hulls.size()):
		index_by_id[fleet_hulls[h].get("hull_id", "")] = h

	var mapping := {}
	for i in range(entries.size()):
		var entry: Dictionary = entries[i]
		if int(entry.get("team", -1)) != 0:
			continue
		var hull_id: String = entry.get("hull_id", "")
		if index_by_id.has(hull_id):
			mapping[i] = index_by_id[hull_id]
	return mapping
