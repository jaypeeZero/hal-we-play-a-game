class_name TacticalKnowledgeSystem
extends RefCounted

## Pure functional tactical knowledge system
## Provides BM25-style knowledge retrieval for crew decision-making.
##
## Patterns live in JSON files under data/knowledge/ (one file per crew
## role) and are loaded lazily on first query. Editing those files changes
## AI behavior directly: each pattern's content carries the maneuvers or
## actions a crew member may pick and the skill they require.
## See DOCS/tactical_knowledge_system.md.

# ============================================================================
# PERFORMANCE CACHE
# ============================================================================

# PERFORMANCE TOGGLE - Set to false to disable knowledge queries entirely
static var enable_knowledge_queries: bool = true

# Query cache to avoid re-computing same queries
static var _query_cache: Dictionary = {}
const MAX_CACHE_SIZE = 50  # Keep cache small

# ============================================================================
# KNOWLEDGE BASE - loaded from data/knowledge/*.json
# ============================================================================

## Directory of per-role pattern files
const KNOWLEDGE_DIR = "res://data/knowledge"

## Role names used in the JSON files
const ROLE_NAMES = {
	"pilot": CrewData.Role.PILOT,
	"gunner": CrewData.Role.GUNNER,
	"captain": CrewData.Role.CAPTAIN,
	"squadron_leader": CrewData.Role.SQUADRON_LEADER,
	"fleet_commander": CrewData.Role.FLEET_COMMANDER,
}

## pattern_id -> {role, tags, text, content}; populated on first query
static var knowledge_base: Dictionary = {}
static var _loaded := false

## Load all pattern files once; merges into knowledge_base so patterns
## added at runtime via add_knowledge_pattern() are preserved.
static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var dir = DirAccess.open(KNOWLEDGE_DIR)
	if dir == null:
		push_error("TacticalKnowledgeSystem: cannot open %s" % KNOWLEDGE_DIR)
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			_load_pattern_file("%s/%s" % [KNOWLEDGE_DIR, file_name])
		file_name = dir.get_next()
	dir.list_dir_end()

static func _load_pattern_file(path: String) -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		push_error("TacticalKnowledgeSystem: invalid JSON in %s" % path)
		return
	var role_name: String = data.get("role", "")
	if not ROLE_NAMES.has(role_name):
		push_error("TacticalKnowledgeSystem: unknown role '%s' in %s" % [role_name, path])
		return
	var role: int = ROLE_NAMES[role_name]
	var patterns: Dictionary = data.get("patterns", {})
	for pattern_id in patterns:
		var p: Dictionary = patterns[pattern_id]
		knowledge_base[pattern_id] = {
			"role": role,
			"tags": p.get("tags", []),
			"text": p.get("text", ""),
			"content": p.get("content", {}),
		}

# ============================================================================
# BM25 IMPLEMENTATION - Lightweight text similarity
# ============================================================================

## Query knowledge base for relevant patterns
## Returns array of matches sorted by relevance.
##
## `known_patterns` restricts retrieval to the pattern ids a specific crew
## member knows; an empty array means the full role baseline. This is the
## per-crew knowledge axis: a rookie who doesn't know "fighter_flank_mid"
## never flanks, and training adds ids to a crew member's set.
static func query_knowledge(situation: String, role: int, top_k: int = 3, known_patterns: Array = []) -> Array:
	# PERFORMANCE: Skip if disabled
	if not enable_knowledge_queries:
		return []

	if situation.is_empty():
		return []

	_ensure_loaded()

	# Check cache first
	var cache_key = str(situation) + "_" + str(role) + "_" + str(top_k) + "_" + str(known_patterns.hash())
	if _query_cache.has(cache_key):
		return _query_cache[cache_key]

	var scored_patterns = []

	# Score each pattern
	for pattern_id in knowledge_base:
		var pattern = knowledge_base[pattern_id]

		# Filter by role (or include general patterns)
		if pattern.role != role:
			continue

		# Filter to this crew member's known patterns (empty = role baseline)
		if not known_patterns.is_empty() and pattern_id not in known_patterns:
			continue

		var score = calculate_relevance_score(situation, pattern)
		if score > 0.0:
			scored_patterns.append({
				"pattern_id": pattern_id,
				"score": score,
				"content": pattern.content,
				"tags": pattern.tags
			})

	# Sort by score descending
	scored_patterns.sort_custom(func(a, b): return a.score > b.score)

	# Return top K
	var result = scored_patterns.slice(0, min(top_k, scored_patterns.size()))

	# Cache result (limit cache size)
	if _query_cache.size() >= MAX_CACHE_SIZE:
		_query_cache.clear()  # Simple cache eviction
	_query_cache[cache_key] = result

	return result

## Calculate relevance score between query and pattern
## Simple BM25-style scoring: term matching with tag boosting
static func calculate_relevance_score(query: String, pattern: Dictionary) -> float:
	var query_terms = tokenize(query)
	var pattern_terms = tokenize(pattern.text)

	if query_terms.is_empty():
		return 0.0

	# Count matching terms
	var matches = 0
	for term in query_terms:
		if term in pattern_terms:
			matches += 1

	# Base score: match ratio
	var base_score = float(matches) / float(query_terms.size())

	# Tag boost: if query contains pattern tags, add bonus (additive not multiplicative)
	var tag_bonus = 0.0
	for tag in pattern.tags:
		if tag in query.to_lower():
			tag_bonus += 0.2  # Each matching tag adds 0.2 to score

	return base_score + tag_bonus

## Tokenize text into lowercase words
static func tokenize(text: String) -> Array:
	return text.to_lower().split(" ", false)

# ============================================================================
# CONVENIENCE QUERIES BY ROLE
# ============================================================================

## Query knowledge for pilot situations
static func query_pilot_knowledge(situation: String, top_k: int = 2, known_patterns: Array = []) -> Array:
	return query_knowledge(situation, CrewData.Role.PILOT, top_k, known_patterns)

## Query knowledge for gunner situations
static func query_gunner_knowledge(situation: String, top_k: int = 2, known_patterns: Array = []) -> Array:
	return query_knowledge(situation, CrewData.Role.GUNNER, top_k, known_patterns)

## Query knowledge for captain situations
static func query_captain_knowledge(situation: String, top_k: int = 2, known_patterns: Array = []) -> Array:
	return query_knowledge(situation, CrewData.Role.CAPTAIN, top_k, known_patterns)

## Query knowledge for squadron leader situations
static func query_squadron_knowledge(situation: String, top_k: int = 2, known_patterns: Array = []) -> Array:
	return query_knowledge(situation, CrewData.Role.SQUADRON_LEADER, top_k, known_patterns)

## Query knowledge for fleet commander situations
static func query_commander_knowledge(situation: String, top_k: int = 2, known_patterns: Array = []) -> Array:
	return query_knowledge(situation, CrewData.Role.FLEET_COMMANDER, top_k, known_patterns)

# ============================================================================
# KNOWLEDGE BASE EXTENSION
# ============================================================================

## Add new knowledge pattern to database (runtime extension; tests use this)
static func add_knowledge_pattern(pattern_id: String, role: int, tags: Array, text: String, content: Dictionary) -> void:
	knowledge_base[pattern_id] = {
		"role": role,
		"tags": tags,
		"text": text,
		"content": content
	}
	_query_cache.clear()

## Get all patterns for a specific role
static func get_patterns_for_role(role: int) -> Array:
	_ensure_loaded()
	var patterns = []
	for pattern_id in knowledge_base:
		var pattern = knowledge_base[pattern_id]
		if pattern.role == role:
			patterns.append({
				"id": pattern_id,
				"pattern": pattern
			})
	return patterns

## Get pattern by ID
static func get_pattern(pattern_id: String) -> Dictionary:
	_ensure_loaded()
	return knowledge_base.get(pattern_id, {})
