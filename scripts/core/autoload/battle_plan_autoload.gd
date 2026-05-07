extends Node

## Transient cross-scene state describing the ships to spawn for the next
## battle. Pre-battle scenes write here; SpaceBattleGame reads and consumes
## on entry. Mirrors the RoguelikeRun autoload's pattern.
##
## entries[i] = {
##   "ship_type": String,
##   "team": int,
##   "position": Vector2,
##   "patrol_center": Vector2,
##   "patrol_radius": float,
## }

var battlefield_size: Vector2 = Vector2.ZERO
var entries: Array = []


func has_plan() -> bool:
	return not entries.is_empty()


func clear() -> void:
	battlefield_size = Vector2.ZERO
	entries = []
