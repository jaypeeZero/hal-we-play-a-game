extends GutTest

func test_animation_request_default_values():
	var request = AnimationRequest.new()

	assert_eq(request.animation_name, "", "Animation name should default to empty")
	assert_eq(request.blend_time, 0.1, "Blend time should default to 0.1")
	assert_eq(request.priority, AnimationRequest.Priority.NORMAL, "Priority should default to NORMAL")
	assert_true(request.interruptible, "Should be interruptible by default")

func test_create_factory_method_default_priority():
	var request = AnimationRequest.create("walk")

	assert_eq(request.animation_name, "walk", "Should set animation name")
	assert_eq(request.priority, AnimationRequest.Priority.NORMAL, "Should default to NORMAL priority")
	assert_true(request.interruptible, "Should be interruptible")

func test_create_factory_method_with_priority():
	var request = AnimationRequest.create("attack", AnimationRequest.Priority.HIGH)

	assert_eq(request.animation_name, "attack", "Should set animation name")
	assert_eq(request.priority, AnimationRequest.Priority.HIGH, "Should set HIGH priority")
	assert_true(request.interruptible, "Should be interruptible")

func test_create_factory_method_critical_priority():
	var request = AnimationRequest.create("death", AnimationRequest.Priority.CRITICAL)

	assert_eq(request.animation_name, "death", "Should set animation name")
	assert_eq(request.priority, AnimationRequest.Priority.CRITICAL, "Should set CRITICAL priority")
	assert_false(request.interruptible, "CRITICAL priority should not be interruptible")

func test_to_dict_serialization():
	var request = AnimationRequest.new()
	request.animation_name = "cast_spell"
	request.blend_time = 0.2
	request.priority = AnimationRequest.Priority.HIGH
	request.interruptible = false

	var dict = request.to_dict()

	assert_eq(dict["animation_name"], "cast_spell", "Animation name should serialize")
	assert_eq(dict["blend_time"], 0.2, "Blend time should serialize")
	assert_eq(dict["priority"], "HIGH", "Priority should serialize as string")
	assert_false(dict["interruptible"], "Interruptible should serialize")

func test_priority_levels():
	assert_eq(AnimationRequest.Priority.LOW, 0, "LOW should be 0")
	assert_eq(AnimationRequest.Priority.NORMAL, 1, "NORMAL should be 1")
	assert_eq(AnimationRequest.Priority.HIGH, 2, "HIGH should be 2")
	assert_eq(AnimationRequest.Priority.CRITICAL, 3, "CRITICAL should be 3")

func test_manual_configuration():
	var request = AnimationRequest.new()
	request.animation_name = "idle"
	request.blend_time = 0.5
	request.priority = AnimationRequest.Priority.LOW
	request.interruptible = true

	assert_eq(request.animation_name, "idle", "Should set animation name")
	assert_eq(request.blend_time, 0.5, "Should set blend time")
	assert_eq(request.priority, AnimationRequest.Priority.LOW, "Should set LOW priority")
	assert_true(request.interruptible, "Should be interruptible")
