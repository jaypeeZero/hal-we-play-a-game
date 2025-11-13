class_name SteeringBehaviors

# Seek: Steer toward a target position
static func seek(position: Vector2, target: Vector2, max_speed: float) -> Vector2:
	var desired_velocity: Vector2 = (target - position).normalized() * max_speed
	return desired_velocity

# Flee: Steer away from a threat
static func flee(position: Vector2, threat: Vector2, max_speed: float) -> Vector2:
	var desired_velocity: Vector2 = (position - threat).normalized() * max_speed
	return desired_velocity

# Arrive: Seek with deceleration near target
static func arrive(position: Vector2, target: Vector2, max_speed: float, slowdown_radius: float) -> Vector2:
	var distance: float = position.distance_to(target)
	var desired_speed: float = max_speed

	if distance < slowdown_radius:
		desired_speed = max_speed * (distance / slowdown_radius)

	var desired_velocity: Vector2 = (target - position).normalized() * desired_speed
	return desired_velocity

# Separate: Avoid crowding neighbors
static func separate(position: Vector2, neighbors: Array, radius: float, max_force: float) -> Vector2:
	var steering: Vector2 = Vector2.ZERO
	var count: int = 0

	for neighbor: Variant in neighbors:
		if is_instance_valid(neighbor) and neighbor is Object and "global_position" in neighbor:
			var neighbor_pos: Vector2 = (neighbor as Object).get("global_position")
			var distance: float = position.distance_to(neighbor_pos)
			if distance > 0.0 and distance < radius:
				# Calculate repulsive force (away from neighbor)
				var diff: Vector2 = (position - neighbor_pos).normalized()
				diff *= 1.0 / (distance + 0.1)  # Weight by distance
				steering += diff
				count += 1

	if count > 0:
		steering /= count
		steering = steering.normalized() * max_force

	return steering

# Cohesion: Move toward average position of neighbors
static func cohesion(position: Vector2, neighbors: Array, max_speed: float) -> Vector2:
	var center_of_mass: Vector2 = Vector2.ZERO
	var count: int = 0

	for neighbor: Variant in neighbors:
		if is_instance_valid(neighbor) and neighbor is Object and "global_position" in neighbor:
			center_of_mass += (neighbor as Object).get("global_position")
			count += 1

	if count == 0:
		return Vector2.ZERO

	center_of_mass /= count
	return seek(position, center_of_mass, max_speed)

# Alignment: Match direction/velocity of neighbors
static func alignment(neighbors: Array, max_speed: float) -> Vector2:
	var avg_velocity: Vector2 = Vector2.ZERO
	var count: int = 0

	for neighbor: Variant in neighbors:
		if is_instance_valid(neighbor) and neighbor is Object:
			# Use velocity if available, otherwise use direction
			if "velocity" in neighbor:
				avg_velocity += (neighbor as Object).get("velocity")
			elif "direction" in neighbor:
				var speed: float = (neighbor as Object).get("speed") if "speed" in neighbor else max_speed
				avg_velocity += (neighbor as Object).get("direction") * speed
			count += 1

	if count == 0:
		return Vector2.ZERO

	avg_velocity /= count

	# Return normalized velocity at max speed
	if avg_velocity.length() > 0:
		return avg_velocity.normalized() * max_speed

	return Vector2.ZERO

# Pursue: Predict target's future position and intercept
static func pursue(position: Vector2, target: Object, max_speed: float, prediction_time: float = 0.5) -> Vector2:
	if not target:
		return Vector2.ZERO

	if target is Node2D and not is_instance_valid(target as Node2D):
		return Vector2.ZERO

	var target_velocity: Vector2 = Vector2.ZERO
	if "velocity" in target:
		target_velocity = target.get("velocity")
	elif "direction" in target:
		var speed: float = target.get("speed") if "speed" in target else max_speed
		target_velocity = target.get("direction") * speed

	var target_pos: Vector2 = target.get("global_position") if "global_position" in target else Vector2.ZERO
	var predicted_position: Vector2 = target_pos + target_velocity * prediction_time
	return seek(position, predicted_position, max_speed)

# Evade: Predict threat's future position and escape
static func evade(position: Vector2, threat: Object, max_speed: float, prediction_time: float = 0.5) -> Vector2:
	if not threat:
		return Vector2.ZERO

	if threat is Node2D and not is_instance_valid(threat as Node2D):
		return Vector2.ZERO

	var threat_velocity: Vector2 = Vector2.ZERO
	if "velocity" in threat:
		threat_velocity = threat.get("velocity")
	elif "direction" in threat:
		var speed: float = threat.get("speed") if "speed" in threat else max_speed
		threat_velocity = threat.get("direction") * speed

	var threat_pos: Vector2 = threat.get("global_position") if "global_position" in threat else Vector2.ZERO
	var predicted_position: Vector2 = threat_pos + threat_velocity * prediction_time
	return flee(position, predicted_position, max_speed)

# Helper to check if object has a property
static func _has_property(obj: Object, prop: String) -> bool:
	return obj.get(prop) != null
