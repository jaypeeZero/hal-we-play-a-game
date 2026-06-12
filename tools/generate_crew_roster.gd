extends SceneTree

## One-off dev tool: generates the shipped crew roster at
## res://data/crew_roster.json. Deterministic — rerunning with the same
## GENERATION_SEED reproduces the same file. The output is checked in;
## players override it via user://crew_roster.json (see CrewRosterManager).
##
## Usage:
##   godot --headless --script tools/generate_crew_roster.gd

const GENERATION_SEED := 20260611
const OUTPUT_PATH := "res://data/crew_roster.json"
const ROSTER_VERSION := 1

## Role mix weighted to a run's hiring demand (pilots and gunners dominate).
const ROLE_COUNTS := {
	"pilot": 60,
	"gunner": 70,
	"engineer": 30,
	"captain": 20,
	"squadron_leader": 12,
	"fleet_commander": 8,
}

## Each role's signature skill gets a small upward bias.
const PRIMARY_SKILL := {
	"pilot": "piloting",
	"gunner": "aim",
	"engineer": "machinery",
	"captain": "tactics",
	"squadron_leader": "tactics",
	"fleet_commander": "tactics",
}

const SKILL_VARIANCE := 0.15
const PRIMARY_SKILL_BIAS := 0.1
const SKILL_STEP := 0.01

## Two-word callsigns: 20 x 10 = 200 unique names, distinct from the rank
## callsigns ("Alpha".."Zeta") that squadron factories assign.
const CALLSIGN_FIRST := [
	"Iron", "Crimson", "Silent", "Ghost", "Solar", "Night", "Static", "Drift",
	"Ember", "Halo", "Razor", "Cobalt", "Lunar", "Storm", "Void", "Argent",
	"Amber", "Slate", "Feral", "Gilded",
]
const CALLSIGN_SECOND := [
	"Viper", "Wolf", "Raven", "Comet", "Lance", "Saber", "Jackal", "Falcon",
	"Mantis", "Harrier",
]

var _started := false


func _init() -> void:
	process_frame.connect(_run)


func _run() -> void:
	if _started:
		return
	_started = true
	quit(_generate())


func _generate() -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = GENERATION_SEED
	var callsigns := _build_callsigns(rng)
	var entries: Array = []
	for role_name in ROLE_COUNTS:
		var count: int = ROLE_COUNTS[role_name]
		for i in count:
			# Stratified base skill guarantees each role cohort spans 0..1.
			var base := float(i) / float(count - 1)
			entries.append(_make_entry(entries.size(), role_name, base, callsigns, rng))

	var payload := {"version": ROSTER_VERSION, "entries": entries}
	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write %s" % OUTPUT_PATH)
		return 1
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	print("Wrote %d roster entries to %s" % [entries.size(), OUTPUT_PATH])
	return 0


func _make_entry(index: int, role_name: String, base: float, callsigns: Array, rng: RandomNumberGenerator) -> Dictionary:
	var skills := {}
	for skill_name in CrewData.SKILL_NAMES:
		if skill_name == CrewData.PERSONALITY_SKILL:
			skills[skill_name] = snappedf(rng.randf(), SKILL_STEP)
			continue
		var value := base + rng.randf_range(-SKILL_VARIANCE, SKILL_VARIANCE)
		if skill_name == PRIMARY_SKILL[role_name]:
			value += PRIMARY_SKILL_BIAS
		skills[skill_name] = snappedf(clampf(value, 0.0, 1.0), SKILL_STEP)
	return {
		"id": "roster_%03d" % index,
		"callsign": callsigns[index],
		"role": role_name,
		"skills": skills,
	}


## All FIRST x SECOND combinations, Fisher-Yates shuffled with the seeded rng
## (Array.shuffle would use the unseeded global RNG and break determinism).
func _build_callsigns(rng: RandomNumberGenerator) -> Array:
	var combos: Array = []
	for second in CALLSIGN_SECOND:
		for first in CALLSIGN_FIRST:
			combos.append("%s %s" % [first, second])
	for i in range(combos.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap = combos[i]
		combos[i] = combos[j]
		combos[j] = swap
	return combos
