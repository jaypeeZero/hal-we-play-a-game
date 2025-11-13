extends GutTest

func test_animation_spec_default_values():
	var spec = AnimationSpec.new()

	assert_eq(spec.frames.size(), 0, "Frames should be empty")
	assert_eq(spec.fps, 10, "FPS should default to 10")
	assert_true(spec.loop, "Should loop by default")

func test_from_dict_basic():
	var dict = {
		"frames": [0, 1, 2, 3],
		"fps": 12,
		"loop": true
	}

	var spec = AnimationSpec.from_dict(dict)

	assert_eq(spec.frames, [0, 1, 2, 3], "Should set frames")
	assert_eq(spec.fps, 12, "Should set FPS")
	assert_true(spec.loop, "Should set loop")

func test_from_dict_non_looping():
	var dict = {
		"frames": [10, 11, 12],
		"fps": 8,
		"loop": false
	}

	var spec = AnimationSpec.from_dict(dict)

	assert_eq(spec.frames, [10, 11, 12], "Should set frames")
	assert_eq(spec.fps, 8, "Should set FPS")
	assert_false(spec.loop, "Should not loop")

func test_from_dict_with_missing_fields():
	var dict = {}

	var spec = AnimationSpec.from_dict(dict)

	assert_eq(spec.frames.size(), 0, "Should have empty frames")
	assert_eq(spec.fps, 10, "Should use default FPS")
	assert_true(spec.loop, "Should use default loop")

func test_from_dict_single_frame():
	var dict = {
		"frames": [5],
		"fps": 1,
		"loop": true
	}

	var spec = AnimationSpec.from_dict(dict)

	assert_eq(spec.frames, [5], "Should handle single frame")
	assert_eq(spec.fps, 1, "Should set FPS to 1")
	assert_true(spec.loop, "Should loop")

func test_from_dict_many_frames():
	var frames_array = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
	var dict = {
		"frames": frames_array,
		"fps": 15,
		"loop": true
	}

	var spec = AnimationSpec.from_dict(dict)

	assert_eq(spec.frames.size(), 10, "Should have 10 frames")
	assert_eq(spec.frames, frames_array, "Should preserve all frames")
	assert_eq(spec.fps, 15, "Should set FPS")

func test_from_dict_partial_data():
	var dict = {
		"frames": [2, 4, 6]
	}

	var spec = AnimationSpec.from_dict(dict)

	assert_eq(spec.frames, [2, 4, 6], "Should set frames")
	assert_eq(spec.fps, 10, "Should use default FPS")
	assert_true(spec.loop, "Should use default loop")
