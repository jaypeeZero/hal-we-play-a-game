class_name CasualtySystem
extends RefCounted

## Pure post-battle casualty resolution. Crew die from the components destroyed
## *this* battle (a before/after status diff — components already destroyed in
## an earlier battle don't re-kill anyone):
##   - A gunner dies if their weapon's mount was newly destroyed.
##   - An engineer rolls once per newly destroyed engine/mount; higher machinery
##     skill means a better chance of surviving each.
## Every roll takes an explicit RandomNumberGenerator so callers control
## seeding and tests stay deterministic.

## Base per-component death chance for an engineer with zero machinery skill.
## Actual chance is ENGINEER_DEATH_BASE_CHANCE * (1.0 - machinery).
const ENGINEER_DEATH_BASE_CHANCE := 0.25


## Internal components that went from intact to destroyed between the sortie
## state and the post-battle state, matched by component_id. Components already
## destroyed before the battle are excluded.
static func newly_destroyed_components(ship_before: Dictionary, ship_after: Dictionary) -> Array:
	var was_destroyed := {}
	for component in ship_before.get("internals", []):
		was_destroyed[component.get("component_id", "")] = component.get("status", "") == "destroyed"

	var newly: Array = []
	for component in ship_after.get("internals", []):
		var id: String = component.get("component_id", "")
		if component.get("status", "") == "destroyed" and not was_destroyed.get(id, false):
			newly.append(component)
	return newly


## Resolve which crew aboard a surviving hull live or die, given the hull's
## sortie-time state (`ship_before`) and its post-battle state (`ship_after`).
## Returns {survivors: Array, deaths: Array}; pilots, captains, and other roles
## always survive a surviving hull.
static func resolve_hull_casualties(crew: Array, ship_before: Dictionary, ship_after: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var newly := newly_destroyed_components(ship_before, ship_after)
	var destroyed_mount_weapons := {}
	for component in newly:
		if component.get("type", "") == BaseStats.WEAPON_MOUNT_TYPE:
			destroyed_mount_weapons[component.get("weapon_id", "")] = true

	var survivors: Array = []
	var deaths: Array = []
	for member in crew:
		if _is_casualty(member, destroyed_mount_weapons, newly.size(), rng):
			deaths.append(member)
		else:
			survivors.append(member)
	return {"survivors": survivors, "deaths": deaths}


static func _is_casualty(member: Dictionary, destroyed_mount_weapons: Dictionary, newly_destroyed_count: int, rng: RandomNumberGenerator) -> bool:
	match member.get("role", -1):
		CrewData.Role.GUNNER:
			# A gunner dies when their mount is shot off. Pepperbox gunners carry
			# a `weapon_ids` group; they die if ANY gun in the group loses its mount.
			if member.has("weapon_ids"):
				for wid in member.get("weapon_ids", []):
					if destroyed_mount_weapons.has(str(wid)):
						return true
				return false
			# Standard 1:1 binding
			return destroyed_mount_weapons.has(member.get("weapon_id", ""))
		CrewData.Role.ENGINEER:
			return _engineer_dies(member, newly_destroyed_count, rng)
		_:
			return false


## An engineer braves each newly destroyed engine/mount once. Per-component
## death chance falls to zero at machinery 1.0 and peaks at the base rate at
## machinery 0.0.
static func _engineer_dies(engineer: Dictionary, newly_destroyed_count: int, rng: RandomNumberGenerator) -> bool:
	var machinery: float = clamp(
		engineer.get("stats", {}).get("skills", {}).get("machinery", 0.0), 0.0, 1.0)
	var chance := ENGINEER_DEATH_BASE_CHANCE * (1.0 - machinery)
	for _i in range(newly_destroyed_count):
		if rng.randf() < chance:
			return true
	return false
