class_name SquadronPlaySystem
extends RefCounted

## Pure functional squadron-play system.
##
## A "play" is a coordinated multi-fighter maneuver (pincer, bracket,
## kill-box) defined as data in `data/squadron_plays.json`. Squadron leaders
## with high enough `tactics` pick a play and assign each subordinate to a
## role (A, B, ...). Each role drives a sequence of phases, and each phase
## resolves to a per-fighter target offset relative to the play's target.
##
## Wingmen don't know what a "pincer" is — they just receive an offset and a
## phase tag and fly toward it. Leader tactics governs both *which* plays
## unlock and *how cleanly* they execute (see apply_jitter).

const PLAYS_PATH = "res://data/squadron_plays.json"

# =============================================================================
# OFFSETS (units relative to target along its facing)
# =============================================================================
# These are intentionally generous — the point is to look like a coordinated
# maneuver from a watching player's POV, not to hit metric perfection.
const FRONTAL_DISTANCE = 1500.0
const HOLD_PRESSURE_DISTANCE = 1200.0
const FLANK_DISTANCE = 1400.0
const SIX_OCLOCK_DISTANCE = 1100.0
const LOOP_WIDE_DISTANCE = 2200.0

# Cached parsed plays — loaded lazily on first use.
static var _plays_cache: Dictionary = {}
static var _plays_loaded: bool = false


# ============================================================================
# DATA LOADING
# ============================================================================

## Load plays from disk. Idempotent — safe to call repeatedly.
static func _ensure_plays_loaded() -> void:
	if _plays_loaded:
		return
	_plays_loaded = true
	if not FileAccess.file_exists(PLAYS_PATH):
		push_warning("Squadron plays file missing: " + PLAYS_PATH)
		_plays_cache = {}
		return
	var file = FileAccess.open(PLAYS_PATH, FileAccess.READ)
	var text = file.get_as_text()
	file.close()
	var json = JSON.new()
	if json.parse(text) != OK:
		push_error("Failed to parse squadron plays JSON")
		_plays_cache = {}
		return
	if json.data is Dictionary:
		_plays_cache = json.data
	else:
		_plays_cache = {}

## Force-reload (used by tests).
static func reload_plays() -> void:
	_plays_loaded = false
	_ensure_plays_loaded()

## Inject a play table directly (used by tests that don't want a file dep).
static func _inject_plays_for_test(plays: Dictionary) -> void:
	_plays_cache = plays.duplicate(true)
	_plays_loaded = true

## Public read-only view of the loaded play table.
static func get_all_plays() -> Dictionary:
	_ensure_plays_loaded()
	return _plays_cache


# ============================================================================
# SELECTION
# ============================================================================

## Choose a play for the leader to run. Returns:
##   {
##     "play_id": String,
##     "role_assignments": { ship_id: role_letter },
##     "target_id": String,
##   }
## or {} if nothing qualifies (rookie wing, no targets, geometry unfavorable).
static func select_play(leader_crew: Dictionary, wing_state: Dictionary, geometry: Dictionary) -> Dictionary:
	_ensure_plays_loaded()
	var tactics = _read_tactics(leader_crew)
	var fighters: Array = wing_state.get("fighters", [])
	var wing_size: int = fighters.size()
	var target_id: String = geometry.get("target_id", "")

	if target_id == "" or wing_size < 2:
		return {}

	# Iterate plays; pick the most ambitious (highest min_tactics) that qualifies.
	var best_play_id := ""
	var best_min_tactics := -1.0
	for play_id in _plays_cache.keys():
		var play: Dictionary = _plays_cache[play_id]
		var min_tactics: float = float(play.get("min_tactics", 0.0))
		var min_wing_size: int = int(play.get("min_wing_size", 2))
		if tactics < min_tactics:
			continue
		if wing_size < min_wing_size:
			continue
		if min_tactics > best_min_tactics:
			best_min_tactics = min_tactics
			best_play_id = play_id

	if best_play_id == "":
		return {}

	var role_letters := _role_letters_for_play(_plays_cache[best_play_id])
	var role_assignments := _assign_roles(fighters, role_letters)

	return {
		"play_id": best_play_id,
		"role_assignments": role_assignments,
		"target_id": target_id,
	}


## Initialize squadron_state for a freshly selected play. Stores phase
## timing baked with leader-tactics jitter so all subsequent ticks share a
## consistent schedule.
static func init_active_play(selection: Dictionary, leader_crew: Dictionary, game_time: float) -> Dictionary:
	if selection.is_empty():
		return {}
	_ensure_plays_loaded()
	var play_id: String = selection.get("play_id", "")
	var play: Dictionary = _plays_cache.get(play_id, {})
	var phases: Array = play.get("phases", [])
	var tactics = _read_tactics(leader_crew)

	var jittered_durations: Array = []
	for phase in phases:
		var base_duration: float = float(phase.get("duration", 0.0))
		jittered_durations.append(_jitter_phase_duration(base_duration, tactics))

	return {
		"play_id": play_id,
		"role_assignments": selection.get("role_assignments", {}),
		"target_id": selection.get("target_id", ""),
		"started_at": game_time,
		"phase_index": 0,
		"phase_started_at": game_time,
		"phase_durations": jittered_durations,
		"leader_tactics": tactics,
	}


# ============================================================================
# TICK
# ============================================================================

## Advance phase if elapsed; recompute per-fighter target offsets.
## Returns updated squadron_state with `fighter_offsets` (ship_id → Vector2)
## populated in world space relative to the target.
static func tick_play(squadron_state: Dictionary, game_time: float, geometry: Dictionary) -> Dictionary:
	if squadron_state.is_empty():
		return squadron_state
	_ensure_plays_loaded()
	var updated = squadron_state.duplicate(true)
	var play: Dictionary = _plays_cache.get(updated.get("play_id", ""), {})
	var phases: Array = play.get("phases", [])
	if phases.is_empty():
		return updated

	# Advance phases that have elapsed (skip past zero-duration phases too).
	var phase_index: int = int(updated.get("phase_index", 0))
	var phase_started_at: float = float(updated.get("phase_started_at", game_time))
	var durations: Array = updated.get("phase_durations", [])
	while phase_index < phases.size() - 1:
		var dur: float = float(durations[phase_index]) if phase_index < durations.size() else 0.0
		if dur <= 0.0 or game_time - phase_started_at < dur:
			break
		phase_started_at += dur
		phase_index += 1
	updated.phase_index = phase_index
	updated.phase_started_at = phase_started_at

	# Compute per-fighter offsets for the current phase.
	var current_phase: Dictionary = phases[phase_index]
	var roles: Dictionary = current_phase.get("roles", {})
	var assignments: Dictionary = updated.get("role_assignments", {})
	var target_pos: Vector2 = geometry.get("target_position", Vector2.ZERO)
	var target_facing: Vector2 = geometry.get("target_facing", Vector2.RIGHT)
	if target_facing == Vector2.ZERO:
		target_facing = Vector2.RIGHT

	var fighter_offsets: Dictionary = {}
	var fighter_actions: Dictionary = {}
	var tactics: float = float(updated.get("leader_tactics", 0.5))
	for ship_id in assignments.keys():
		var role: String = assignments[ship_id]
		var action: String = roles.get(role, "merge_attack")
		var base_offset := _resolve_action_offset(action, target_facing)
		var jitter := _deterministic_jitter(ship_id, phase_index, tactics)
		fighter_offsets[ship_id] = target_pos + base_offset + jitter
		fighter_actions[ship_id] = action

	updated.fighter_offsets = fighter_offsets
	updated.fighter_actions = fighter_actions
	updated.is_complete = (phase_index >= phases.size() - 1) \
		and (game_time - phase_started_at >= float(durations[phase_index]) if phase_index < durations.size() else true)
	return updated


# ============================================================================
# JITTER (execution quality scatter)
# ============================================================================

## Scatter an offset by (1 - tactics) * PLAY_JITTER_MAX_OFFSET. Stochastic
## form — used when caller wants raw randomness.
static func apply_jitter(offset: Vector2, leader_tactics: float) -> Vector2:
	var amplitude: float = (1.0 - clamp(leader_tactics, 0.0, 1.0)) * WingConstants.PLAY_JITTER_MAX_OFFSET
	if amplitude <= 0.0:
		return offset
	var jx := randf_range(-amplitude, amplitude)
	var jy := randf_range(-amplitude, amplitude)
	return offset + Vector2(jx, jy)


# ============================================================================
# INTERNAL HELPERS
# ============================================================================

static func _read_tactics(crew: Dictionary) -> float:
	var stats: Dictionary = crew.get("stats", {})
	var skills: Dictionary = stats.get("skills", {})
	if skills.has("tactics"):
		return float(skills["tactics"])
	# Fall back to the legacy aggregate while phases 02/03 are still rolling
	# in. After the rename pass this branch becomes unreachable.
	return float(stats.get("skill", 0.5))

## Distinct role letters used across all phases of a play.
static func _role_letters_for_play(play: Dictionary) -> Array:
	var letters: Dictionary = {}
	for phase in play.get("phases", []):
		for letter in phase.get("roles", {}).keys():
			letters[letter] = true
	var sorted: Array = letters.keys()
	sorted.sort()
	return sorted

## Distribute fighters across role letters as evenly as possible, in a
## stable order so test assertions can rely on it.
static func _assign_roles(fighters: Array, role_letters: Array) -> Dictionary:
	var assignments: Dictionary = {}
	if role_letters.is_empty():
		return assignments
	for i in fighters.size():
		var letter: String = role_letters[i % role_letters.size()]
		assignments[fighters[i]] = letter
	return assignments

## Resolve an action keyword to an offset in the target's local frame.
## target_facing is a unit vector pointing along the target's nose.
static func _resolve_action_offset(action: String, target_facing: Vector2) -> Vector2:
	var forward := target_facing.normalized()
	var left := Vector2(-forward.y, forward.x)  # 90° CCW (screen-space "left")
	match action:
		"engage_frontal":
			return forward * FRONTAL_DISTANCE
		"hold_pressure":
			return forward * HOLD_PRESSURE_DISTANCE
		"loop_wide_left":
			return left * LOOP_WIDE_DISTANCE
		"loop_wide_right":
			return -left * LOOP_WIDE_DISTANCE
		"flank_left":
			return left * FLANK_DISTANCE
		"flank_right":
			return -left * FLANK_DISTANCE
		"approach_target_six":
			return -forward * SIX_OCLOCK_DISTANCE
		"merge_attack":
			return Vector2.ZERO
		_:
			return Vector2.ZERO

## Deterministic per-ship jitter so tests can compare elite vs rookie
## execution on the same seed input. Uses a hash of (ship_id, phase) as the
## random source so the scatter is stable per fighter per phase but differs
## across the wing.
static func _deterministic_jitter(ship_id: String, phase_index: int, tactics: float) -> Vector2:
	var amplitude: float = (1.0 - clamp(tactics, 0.0, 1.0)) * WingConstants.PLAY_JITTER_MAX_OFFSET
	if amplitude <= 0.0:
		return Vector2.ZERO
	var seed: int = hash(ship_id) ^ (phase_index * 2654435761)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var jx := rng.randf_range(-amplitude, amplitude)
	var jy := rng.randf_range(-amplitude, amplitude)
	return Vector2(jx, jy)

## Add (1-tactics)-scaled noise to a phase's planned duration. Symmetric
## around the base — elites converge on the planned duration; rookies arrive
## at the merge with the wing strung out.
static func _jitter_phase_duration(base_duration: float, tactics: float) -> float:
	if base_duration <= 0.0:
		return base_duration
	var amplitude: float = (1.0 - clamp(tactics, 0.0, 1.0)) * WingConstants.PLAY_JITTER_MAX_TIMING
	if amplitude <= 0.0:
		return base_duration
	var jitter := randf_range(-amplitude, amplitude)
	return max(0.1, base_duration + jitter)


# ============================================================================
# LEADER-SIDE INTEGRATION
# ============================================================================

## High-level entry: take a leader crew, current game state, and either pick
## a fresh play or advance the active one. Returns a dictionary with
## { "crew_data": updated_crew, "orders": Array of play orders to issue,
##   "selected": bool — true if a play is currently driving the wing }.
##
## Geometry shape: { "target_id", "target_position", "target_facing" }.
## Wing state shape: { "fighters": Array[crew_id] }.
##
## The function manages `crew_data.squadron_state.active_play` lifecycle:
## init on first run, replan after PLAY_REPLAN_INTERVAL, clear when complete.
static func tick_squadron_play(leader_crew: Dictionary, wing_state: Dictionary, geometry: Dictionary, game_time: float) -> Dictionary:
	var updated = leader_crew.duplicate(true)
	if not updated.has("squadron_state"):
		updated.squadron_state = {}
	var squadron_state: Dictionary = updated.squadron_state
	var active_play: Dictionary = squadron_state.get("active_play", {})

	var should_replan := false
	if active_play.is_empty():
		should_replan = true
	else:
		# Replan when the active play has finished, or when the periodic
		# replan window has elapsed (so the leader can switch tactics if
		# the picture has changed).
		var started_at: float = float(active_play.get("started_at", game_time))
		if active_play.get("is_complete", false):
			should_replan = true
		elif game_time - started_at >= WingConstants.PLAY_REPLAN_INTERVAL:
			should_replan = true

	if should_replan:
		var selection := select_play(updated, wing_state, geometry)
		if selection.is_empty():
			squadron_state.erase("active_play")
			updated.squadron_state = squadron_state
			return {"crew_data": updated, "orders": [], "selected": false}
		active_play = init_active_play(selection, updated, game_time)

	active_play = tick_play(active_play, game_time, geometry)
	squadron_state.active_play = active_play
	updated.squadron_state = squadron_state

	var orders := _build_play_orders(active_play, geometry, game_time)
	return {"crew_data": updated, "orders": orders, "selected": true}


## Build per-fighter orders from the active play.
static func _build_play_orders(active_play: Dictionary, geometry: Dictionary, game_time: float) -> Array:
	var orders: Array = []
	var fighter_offsets: Dictionary = active_play.get("fighter_offsets", {})
	var fighter_actions: Dictionary = active_play.get("fighter_actions", {})
	var assignments: Dictionary = active_play.get("role_assignments", {})
	var phase_index: int = int(active_play.get("phase_index", 0))
	var play_id: String = active_play.get("play_id", "")
	var target_id: String = active_play.get("target_id", geometry.get("target_id", ""))
	for crew_id in assignments.keys():
		orders.append({
			"to": crew_id,
			"type": "play",
			"play_id": play_id,
			"play_role": assignments[crew_id],
			"phase": phase_index,
			"action": fighter_actions.get(crew_id, "merge_attack"),
			"target_offset": fighter_offsets.get(crew_id, Vector2.ZERO),
			"target_id": target_id,
			"timestamp": game_time,
		})
	return orders
