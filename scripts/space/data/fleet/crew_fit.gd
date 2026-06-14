class_name CrewFit
extends RefCounted

## Pure static crew-fit rules shared by all FleetSource implementations.
## No node dependencies; fully unit-testable.
##
## Rule source: mirrors RoguelikeRun.hull_vacancies / _matching_vacancy / can_transfer.
## Gunner slots are matched by weapon_id; all other roles match by count only.


## Vacant complement slots on a hull — slots not currently filled by any crew member.
## Gunner slots matched by weapon_id; non-gunner roles matched by remaining count.
## Mirrors RoguelikeRun.hull_vacancies exactly.
static func vacant_slots(hull: Dictionary) -> Array:
	var filled_weapon_ids: Dictionary = {}
	var remaining_role_counts: Dictionary = {}

	for member in hull.get("crew", []):
		var role: int = int(member.get("role", -1))
		if role == CrewData.Role.GUNNER and member.has("weapon_id"):
			filled_weapon_ids[str(member["weapon_id"])] = true
		else:
			remaining_role_counts[role] = int(remaining_role_counts.get(role, 0)) + 1

	var vacancies: Array = []
	for slot in hull.get("complement", []):
		var role: int = int(slot.get("role", -1))
		if role == CrewData.Role.GUNNER and slot.has("weapon_id"):
			if not filled_weapon_ids.has(str(slot["weapon_id"])):
				vacancies.append(slot)
		elif int(remaining_role_counts.get(role, 0)) > 0:
			remaining_role_counts[role] = int(remaining_role_counts.get(role, 0)) - 1
		else:
			vacancies.append(slot)

	return vacancies


## Whether crew can fill at least one vacant slot on hull.
## Returns true if a role-qualified vacancy exists.
## Off-role placement is handled by the caller (assign); this is the gate check.
## Mirrors RoguelikeRun._matching_vacancy / can_transfer role-match rule.
static func can_fill(crew: Dictionary, hull: Dictionary) -> bool:
	return not _matching_vacancy(hull, crew).is_empty()


## First vacant slot on hull that matches crew's assigned role.
## Gunner slots require a weapon_id in the vacancy; role int must match exactly.
## Returns {} when no matching vacancy exists.
static func matching_vacancy(hull: Dictionary, crew: Dictionary) -> Dictionary:
	return _matching_vacancy(hull, crew)


## Whether two crew members can swap: both exist, different hulls, same role.
## This is a pure check over two hull dicts — no source-specific state needed.
static func can_swap_members(member_a: Dictionary, member_b: Dictionary, hull_id_a: String, hull_id_b: String) -> bool:
	if member_a.is_empty() or member_b.is_empty():
		return false
	if hull_id_a == hull_id_b:
		return false
	return int(member_a.get("role", -1)) == int(member_b.get("role", -2))


# Internal

static func _matching_vacancy(hull: Dictionary, member: Dictionary) -> Dictionary:
	var role: int = int(member.get("role", -1))
	for slot in vacant_slots(hull):
		if int(slot.get("role", -2)) == role:
			return slot
	return {}
