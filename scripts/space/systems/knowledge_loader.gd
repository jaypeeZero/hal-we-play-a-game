class_name KnowledgeLoader
extends RefCounted

## Loads knowledge base from JSON files and populates TacticalKnowledgeSystem
## Converts JSON format to TacticalKnowledgeSystem format
##
## NOTE: Uses manifest file instead of DirAccess because DirAccess.open()
## does not work on res:// paths in exported builds (files are packed into PCK)

# Path to the manifest file listing all knowledge files
const MANIFEST_PATH = "res://data/knowledgebase/manifest.json"

# ============================================================================
# KNOWLEDGE LOADING
# ============================================================================

## Load all knowledge files listed in the manifest
static func load_knowledge_from_manifest() -> int:
	var file = FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if not file:
		push_error("Failed to open knowledge manifest: " + MANIFEST_PATH)
		return 0

	var json_text = file.get_as_text()
	file.close()

	var json = JSON.new()
	var parse_result = json.parse(json_text)
	if parse_result != OK:
		push_error("Failed to parse knowledge manifest JSON")
		return 0

	var manifest = json.data
	if not manifest is Dictionary or not manifest.has("files"):
		push_error("Invalid manifest format - expected {files: [...]}")
		return 0

	var loaded_count = 0
	var base_path = manifest.get("base_path", "res://data/knowledgebase/annotated")

	for file_name in manifest.files:
		var file_path = base_path + "/" + file_name
		if load_knowledge_file(file_path):
			loaded_count += 1

	print("Loaded %d knowledge entries from manifest" % loaded_count)
	return loaded_count

## Load single knowledge file and add to TacticalKnowledgeSystem
static func load_knowledge_file(file_path: String) -> bool:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("Failed to open knowledge file: " + file_path)
		return false

	var json_text = file.get_as_text()
	file.close()

	var json = JSON.new()
	var parse_result = json.parse(json_text)
	if parse_result != OK:
		push_error("Failed to parse JSON in file: " + file_path)
		return false

	var data = json.data
	if not data is Dictionary:
		push_error("JSON root is not a dictionary in file: " + file_path)
		return false

	# Convert to TacticalKnowledgeSystem format
	convert_and_add_knowledge(data)
	return true

## Convert JSON knowledge entry to TacticalKnowledgeSystem format
static func convert_and_add_knowledge(data: Dictionary) -> void:
	var entry_id = data.get("id", "unknown")
	var title = data.get("title", "")
	var category = data.get("category", "")
	var summary = data.get("summary", "")
	var details = data.get("details", "")
	var annotations = data.get("annotations", [])

	# Combine text for BM25 indexing
	var text_parts = [summary, details]
	if annotations is Array:
		for annotation in annotations:
			text_parts.append(annotation)

	var full_text = " ".join(text_parts).to_lower()

	# Extract keywords from details
	var keywords = extract_keywords(full_text)

	# Determine role based on content analysis
	var role = determine_role_from_content(full_text, keywords)

	# Determine tags from content
	var tags = determine_tags_from_content(full_text, keywords)

	# Create content dictionary
	var content = {
		"title": title,
		"summary": summary,
		"details": details,
		"annotations": annotations if annotations is Array else [],
		"category": category,
		"keywords": keywords
	}

	# Add to TacticalKnowledgeSystem
	TacticalKnowledgeSystem.add_knowledge_pattern(
		entry_id,
		role,
		tags,
		full_text,
		content
	)

## Extract keywords from text
static func extract_keywords(text: String) -> Array:
	# Common keywords to look for
	var keywords = []

	# Piloting keywords
	if "thrust" in text or "maneuver" in text or "velocity" in text:
		keywords.append("maneuvering")
	if "collision" in text or "avoid" in text:
		keywords.append("avoidance")
	if "inertia" in text or "vector" in text:
		keywords.append("physics")

	# Combat keywords
	if "weapon" in text or "fire" in text or "firing" in text:
		keywords.append("weapons")
	if "target" in text or "targeting" in text:
		keywords.append("targeting")
	if "evasion" in text or "evade" in text:
		keywords.append("evasion")

	# Tactical keywords
	if "tactical" in text or "strategy" in text:
		keywords.append("tactics")
	if "coordinate" in text or "coordination" in text:
		keywords.append("coordination")
	if "predictive" in text or "predict" in text:
		keywords.append("prediction")

	return keywords

## Determine crew role based on content
static func determine_role_from_content(text: String, keywords: Array) -> int:
	# Score each role
	var pilot_score = 0
	var gunner_score = 0
	var captain_score = 0
	var squadron_score = 0
	var commander_score = 0

	# Pilot indicators
	if "thrust" in text: pilot_score += 3
	if "maneuver" in text: pilot_score += 3
	if "velocity" in text: pilot_score += 2
	if "collision" in text: pilot_score += 2
	if "trajectory" in text: pilot_score += 2
	if "rotational" in text: pilot_score += 2
	if "evasion" in text: pilot_score += 1

	# Gunner indicators
	if "weapon" in text: gunner_score += 3
	if "firing" in text: gunner_score += 3
	if "target" in text: gunner_score += 2
	if "predictive targeting" in text: gunner_score += 3
	if "firing solution" in text: gunner_score += 3

	# Captain indicators
	if "tactical" in text: captain_score += 3
	if "combat" in text: captain_score += 2
	if "awareness" in text: captain_score += 2
	if "state coherence" in text: captain_score += 2
	if "decision" in text: captain_score += 1

	# Squadron indicators
	if "multi-ship" in text: squadron_score += 4
	if "coordination" in text: squadron_score += 3
	if "fleet" in text: squadron_score += 2

	# Commander indicators
	if "strategic" in text: commander_score += 4
	if "fleet" in text: commander_score += 3

	# Find highest score
	var scores = {
		CrewData.Role.PILOT: pilot_score,
		CrewData.Role.GUNNER: gunner_score,
		CrewData.Role.CAPTAIN: captain_score,
		CrewData.Role.SQUADRON_LEADER: squadron_score,
		CrewData.Role.FLEET_COMMANDER: commander_score
	}

	var best_role = CrewData.Role.PILOT  # Default
	var best_score = 0

	for role in scores:
		if scores[role] > best_score:
			best_score = scores[role]
			best_role = role

	# If all scores are equal or very low, default to Captain (general tactical knowledge)
	if best_score < 3:
		return CrewData.Role.CAPTAIN

	return best_role

## Determine tags from content
static func determine_tags_from_content(text: String, keywords: Array) -> Array:
	var tags = []

	# Add category tag
	tags.append("space_combat")

	# Add keyword tags
	for keyword in keywords:
		if keyword not in tags:
			tags.append(keyword)

	# Add specific tags based on content
	if "piloting" in text or "pilot" in text:
		tags.append("piloting")
	if "combat" in text:
		tags.append("combat")
	if "awareness" in text:
		tags.append("awareness")
	if "physics" in text or "inertia" in text:
		tags.append("physics")
	if "multi-step" in text or "planning" in text:
		tags.append("planning")

	return tags

# ============================================================================
# INITIALIZATION
# ============================================================================

## Initialize knowledge base from manifest file
## Call this at game startup
static func initialize_knowledge_base() -> void:
	print("Loading knowledge base...")

	# Load from manifest file (works in both editor and exports)
	var loaded = load_knowledge_from_manifest()

	if loaded == 0:
		push_warning("No external knowledge loaded, using built-in placeholder knowledge")

	print("Knowledge base initialization complete. Total patterns: %d" % TacticalKnowledgeSystem.knowledge_base.size())
