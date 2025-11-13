class_name CollisionUtils

# Utility for shared collision validation logic
# Extracts the common pattern of validating collision targets

static func get_valid_target(
	area: Area2D,
	self_hit_box: Area2D,
	exclude_list: Array = []
) -> Node2D:
	"""
	Validates if an area collision should result in a valid target.

	Performs common validation checks:
	- Skip self collision (checks self_hit_box)
	- Get parent as target
	- Validate target has take_damage method
	- Exclude list check

	Returns the target if valid, null otherwise.
	"""
	# Skip self collision
	if area == self_hit_box:
		return null

	# Get parent as target
	var target: Node = area.get_parent()

	# Check if target can take damage (supports both Damageable and CreatureObject)
	if not target.has_method("take_damage"):
		return null

	# Check exclude list
	if target in exclude_list:
		return null

	return target
