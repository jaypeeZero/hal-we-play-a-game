class_name CrewProgressionSystem
extends RefCounted

## Pure/static system — develops surviving crew skills after a roguelike battle
## and returns a per-crew report for the post-battle overview scene.
##
## Mutates each crew member's stats.skills in place (clamped 0..1); growth
## persists automatically via fleet_hulls -> save_campaign_to_disk.

# Role -> used skills: primary first (grows at USED_PRIMARY_WEIGHT), then
# secondary (USED_SECONDARY_WEIGHT). aggression is never here — personality only.
const ROLE_SKILLS := {
	CrewData.Role.PILOT:           ["piloting", "awareness", "composure"],
	CrewData.Role.GUNNER:          ["aim", "awareness", "composure"],
	CrewData.Role.ENGINEER:        ["machinery", "composure"],
	CrewData.Role.CAPTAIN:         ["tactics", "awareness", "composure"],
	CrewData.Role.SQUADRON_LEADER: ["tactics", "awareness", "composure"],
	CrewData.Role.FLEET_COMMANDER: ["tactics", "awareness", "composure"],
}


## Develop the surviving crew on every hull and return a per-crew report.
## Mutates each crew member's stats.skills in place (clamped 0..1).
## `hulls`       : RoguelikeRun.fleet_hulls AFTER apply_battle_outcome (survivors only).
## `events`      : BattleEventLogger event_history (Array); may be [].
## `ship_deltas` : last_battle_summary.ship_deltas; may be [].
## `rng`         : seeded RandomNumberGenerator.
## Returns: Array of progression records, one per surviving crew member.
static func award_experience(
	hulls: Array,
	events: Array,
	ship_deltas: Array,
	rng: RandomNumberGenerator
) -> Array:
	var report: Array = []
	for hull in hulls:
		var commander := _hull_commander(hull)
		var commander_id: String = commander.get("crew_id", "")
		var leadership: float = float(commander.get("stats", {}).get("skills", {}).get("tactics", 0.5))
		var adversity: float = _hull_adversity(hull.get("hull_id", ""), ship_deltas)
		var exceptional := _exceptional_skills_on_hull(hull, "")  # computed per-member below

		for member in hull.get("crew", []):
			var crew_id: String = member.get("crew_id", "")
			var is_commander: bool = (crew_id == commander_id)
			var coach_mult: float = 1.0 if is_commander \
				else lerpf(WingConstants.LEADER_MULT_MIN, WingConstants.LEADER_MULT_MAX, leadership)

			# Per-member exceptional skills: exclude this member from their own mentoring
			var member_exceptional := _exceptional_skills_on_hull(hull, crew_id)

			var skills: Dictionary = member.get("stats", {}).get("skills", {})
			# Snapshot composure before any mutation — aggression response must not
			# depend on processing order.
			var composure_before: float = float(skills.get("composure", 0.5))

			var role: int = int(member.get("role", CrewData.Role.PILOT))
			var used_skills: Array = ROLE_SKILLS.get(role, [])
			var primary_skill: String = used_skills[0] if not used_skills.is_empty() else ""

			var skill_deltas: Array = []

			# --- competence skills ---
			for skill_name in CrewData.SKILL_NAMES:
				if skill_name == CrewData.PERSONALITY_SKILL:
					continue
				var before: float = float(skills.get(skill_name, 0.0))
				var gain := 0.0
				var source := ""
				var mentor_callsign := ""

				if skill_name in used_skills:
					var weight: float = WingConstants.USED_PRIMARY_WEIGHT \
						if skill_name == primary_skill else WingConstants.USED_SECONDARY_WEIGHT
					var raw := rng.randf_range(WingConstants.USED_GAIN_MIN, WingConstants.USED_GAIN_MAX)
					var scaled := raw * weight * coach_mult
					gain = clampf(scaled, WingConstants.USED_GAIN_MIN, WingConstants.USED_GAIN_MAX)
					gain *= _mastery_taper(before)
					source = "used"
				elif member_exceptional.has(skill_name):
					gain = rng.randf_range(WingConstants.TRICKLE_GAIN_MIN, WingConstants.TRICKLE_GAIN_MAX) \
						* coach_mult
					gain *= _mastery_taper(before)
					source = "mentored"
					mentor_callsign = str(member_exceptional[skill_name])

				if gain > 0.0:
					var after := clampf(before + gain, 0.0, 1.0)
					skills[skill_name] = after
					skill_deltas.append({
						"skill": skill_name,
						"before": before,
						"after": after,
						"delta": after - before,
						"source": source,
						"mentor_callsign": mentor_callsign,
					})

			# --- aggression: adversity response only ---
			if adversity > 0.0:
				var agg_before: float = float(skills.get(CrewData.PERSONALITY_SKILL, 0.5))
				var magnitude := lerpf(
					WingConstants.AGGRESSION_SHIFT_MIN, WingConstants.AGGRESSION_SHIFT_MAX, adversity)
				var direction := 1 if composure_before >= WingConstants.COMPOSURE_PIVOT else -1
				var agg_after := clampf(agg_before + magnitude * direction, 0.0, 1.0)
				skills[CrewData.PERSONALITY_SKILL] = agg_after
				if agg_after != agg_before:
					skill_deltas.append({
						"skill": CrewData.PERSONALITY_SKILL,
						"before": agg_before,
						"after": agg_after,
						"delta": agg_after - agg_before,
						"source": "adversity",
						"mentor_callsign": "",
					})

			var commander_callsign := "" if is_commander \
				else str(commander.get("callsign", commander_id))

			report.append({
				"crew_id": crew_id,
				"callsign": str(member.get("callsign", crew_id)),
				"role": role,
				"hull_id": str(hull.get("hull_id", "")),
				"ship_type": str(hull.get("ship_type", "")),
				"commander_callsign": commander_callsign,
				"coach_mult": coach_mult,
				"skills": skill_deltas,
			})

	return report


## Per hull: fraction of combined armor+systems lost this battle (0..1).
static func _hull_adversity(hull_id: String, ship_deltas: Array) -> float:
	for delta in ship_deltas:
		if delta.get("hull_id", "") != hull_id:
			continue
		var armor_lost := float(delta.get("armor_before", 1.0)) - float(delta.get("armor_after", 1.0))
		var systems_lost := float(delta.get("systems_before", 1.0)) - float(delta.get("systems_after", 1.0))
		# Average of armor and systems loss fractions, clamped.
		return clampf((armor_lost + systems_lost) * 0.5, 0.0, 1.0)
	return 0.0


## Returns a dict of {skill_name: mentor_callsign} for skills where any crew
## member aboard (excluding `excluding_crew_id`) exceeds EXCEPTIONAL_SKILL_THRESHOLD.
## The highest-value mentor's callsign is stored per skill.
static func _exceptional_skills_on_hull(hull: Dictionary, excluding_crew_id: String) -> Dictionary:
	var result: Dictionary = {}
	for member in hull.get("crew", []):
		if member.get("crew_id", "") == excluding_crew_id:
			continue
		var skills: Dictionary = member.get("stats", {}).get("skills", {})
		var callsign: String = str(member.get("callsign", member.get("crew_id", "")))
		for skill_name in CrewData.SKILL_NAMES:
			if skill_name == CrewData.PERSONALITY_SKILL:
				continue
			if float(skills.get(skill_name, 0.0)) >= WingConstants.EXCEPTIONAL_SKILL_THRESHOLD:
				# Keep first found (could rank by value, but any exceptional mentor is valid)
				if not result.has(skill_name):
					result[skill_name] = callsign
	return result


## Soft taper: returns a multiplier that reduces gains near mastery.
## Linear from 1.0 at MASTERY_TAPER_START down to MASTERY_TAPER_FLOOR at 1.0.
static func _mastery_taper(skill: float) -> float:
	if skill <= WingConstants.MASTERY_TAPER_START:
		return 1.0
	var t := (skill - WingConstants.MASTERY_TAPER_START) / (1.0 - WingConstants.MASTERY_TAPER_START)
	return lerpf(1.0, WingConstants.MASTERY_TAPER_FLOOR, t)


## A hull's commander is its captain, or its pilot on craft with no captain.
## Mirrors RoguelikeRun._hull_commander without the autoload dependency.
static func _hull_commander(hull: Dictionary) -> Dictionary:
	for member in hull.get("crew", []):
		if member.get("role", -1) == CrewData.Role.CAPTAIN:
			return member
	for member in hull.get("crew", []):
		if member.get("role", -1) == CrewData.Role.PILOT:
			return member
	return {}
