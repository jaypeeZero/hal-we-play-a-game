class_name CrewPortrait
extends TextureRect

## Crew "headshot": one of the pre-sliced sci-fi portrait faces, chosen
## deterministically from the crew member's stable id so a given crew member
## always shows the same face. Faces live in `assets/portraits/` as
## face_001.png .. face_NNN.png (sliced from the source portrait sheets).

const PORTRAIT_SIZE := Vector2(96, 112)
const PORTRAIT_DIR := "res://assets/portraits/"
const PORTRAIT_COUNT := 200


func _init() -> void:
	custom_minimum_size = PORTRAIT_SIZE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED


## Pick this crew member's face. `entry` is a roster entry ({id, callsign, ...}).
func setup(entry: Dictionary) -> void:
	texture = load(portrait_path_for(entry))


## Stable face path for an entry: hashes its id (callsign as fallback) into the
## 1..PORTRAIT_COUNT range so the mapping is deterministic and well-distributed.
static func portrait_path_for(entry: Dictionary) -> String:
	var key := str(entry.get("id", ""))
	if key.is_empty():
		key = str(entry.get("callsign", ""))
	var index: int = abs(key.hash()) % PORTRAIT_COUNT + 1
	return PORTRAIT_DIR + "face_%03d.png" % index
