class_name AnimationSpec extends RefCounted

## Frame indices in sprite sheet
var frames: Array[int] = []

## Playback speed (frames per second)
var fps: int = 10

## Should animation loop?
var loop: bool = true

## Deserialize from theme JSON
static func from_dict(data: Dictionary) -> AnimationSpec:
	var spec = AnimationSpec.new()

	var frames_arr = data.get("frames", [])
	spec.frames.assign(frames_arr)

	spec.fps = data.get("fps", 10)
	spec.loop = data.get("loop", true)

	return spec
