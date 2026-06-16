class_name CrewIntegrationSystem
extends RefCounted

## Integrates crew AI decisions with ship systems (movement, weapons)
## Translates crew decisions into ship_data modifications
## Following functional programming principles - all data is immutable

# =============================================================================
# TARGETING STYLE ENUM - Unlocked by gunner skill
# =============================================================================
enum TargetingStyle {
	SIMPLE,      # Aims at target center, no lead (low skill)
	LEADING,     # Basic velocity prediction (medium skill)
	PREDICTIVE,  # Full lead calculation, anticipates maneuvers (high skill)
	SUBSYSTEM    # Targets specific weak points (elite skill)
}

# =============================================================================
# COMMAND STYLE ENUM - Unlocked by captain skill
# =============================================================================
enum CommandStyle {
	REACTIVE,    # Only responds to immediate threats (low skill)
	STANDARD,    # Follows doctrine, reasonable priorities (medium skill)
	TACTICAL,    # Anticipates situations, coordinates crew (high skill)
	ADAPTIVE     # Reads battle, adjusts strategy dynamically (elite skill)
}

# =============================================================================
# COORDINATION STYLE ENUM - Unlocked by squadron leader skill
# =============================================================================
# Three tiers: independent fighting, loose mutual support, or full play-driven
# orchestration. The earlier PAIRED / COORDINATED split was decorative — the
# only behavior gate that mattered was whether plays could fire — so they
# collapsed into LOOSE.
enum CoordinationStyle {
	INDIVIDUAL,   # Ships fight independently (low skill)
	LOOSE,        # Basic wingman pairing, mutual support, focus fire (mid skill)
	ORCHESTRATED  # Play-driven coordinated maneuvers (elite skill)
}

# ============================================================================
# MAIN API - Apply crew decisions to ships
# ============================================================================

## Apply all crew decisions to ships
static func apply_crew_decisions_to_ships(ships: Array, crew_list: Array, decisions: Array) -> Dictionary:
	var updated_ships = ships.duplicate(true)

	for decision in decisions:
		var ship_id = decision.get("entity_id")
		if ship_id:
			var ship_index = find_ship_index(updated_ships, ship_id)
			if ship_index >= 0:
				var crew = find_crew_by_id(crew_list, decision.get("crew_id"))
				updated_ships[ship_index] = apply_decision_to_ship(updated_ships[ship_index], decision, crew, crew_list)

	return {
		"ships": updated_ships,
		"actions": extract_immediate_actions(decisions)
	}

## Apply single decision to ship.
## crew_list is the full live crew array; it is used to source gunner-claimed
## weapon-id sets so the pilot only stamps weapons that no live gunner mans.
static func apply_decision_to_ship(ship_data: Dictionary, decision: Dictionary, crew_data: Dictionary, crew_list: Array = []) -> Dictionary:
	match decision.get("type"):
		"maneuver":
			return apply_maneuver_decision(ship_data, decision, crew_data, crew_list)
		"fire":
			return apply_fire_decision(ship_data, decision, crew_data, crew_list)
		"tactical":
			return apply_tactical_decision(ship_data, decision, crew_data)
		"repair":
			return apply_repair_decision(ship_data, decision, crew_data)
		_:
			return ship_data

# ============================================================================
# MANEUVER DECISIONS (Pilot)
# ============================================================================

## Apply pilot's maneuver decision.
## All fighter maneuvers use "fight_" prefix and are handled generically.
## crew_list is the full live crew array, used to determine which weapons
## are gunner-owned so the pilot only stamps the remainder.
static func apply_maneuver_decision(ship_data: Dictionary, decision: Dictionary, crew_data: Dictionary, crew_list: Array = []) -> Dictionary:
	var updated = ship_data.duplicate(true)
	var subtype = decision.get("subtype", "")

	# Handle special non-fighter cases
	if subtype == "flee_to_boundary" or subtype == "flee_turn_back":
		# Escape-boundary flee — shared by fighters and large ships. Steers to
		# orders.flee_target regardless of hull class (see MovementSystem).
		updated.orders.current_order = "flee"
		updated.orders.target_id = ""
		updated.orders.maneuver_subtype = subtype
	elif subtype == "evade":
		updated.orders.current_order = "evade"
		updated.orders.threat_id = decision.get("target_id", "")
	elif subtype == "pursue":
		updated.orders.current_order = "engage"
		updated.orders.target_id = decision.get("target_id", "")
	elif subtype == "idle":
		updated.orders.current_order = ""
		updated.orders.target_id = ""
	elif subtype == "tactical":
		# Blended steering directive from AttackAction / LargeShipPilotAI.
		# Copies all directive fields onto orders so MovementSystem can
		# re-blend them live each frame from current positions.
		updated.orders.current_order = "tactical"
		updated.orders.engagement_target = decision.get("engagement_target", "")
		updated.orders.goal_weights      = decision.get("goal_weights", {})
		updated.orders.preferred_range   = decision.get("preferred_range", 0.0)
		updated.orders.formation_slot    = decision.get("formation_slot",  Vector2.ZERO)
		updated.orders.anchor_position   = decision.get("anchor_position", Vector2.ZERO)
		# facing_mode: "auto"/"nose_on"/"broadside" — role-derived by SteeringBlender
		updated.orders.facing_mode       = decision.get("facing_mode", "auto")
		# Mirror target_id so leash / other systems that read orders.target_id still work
		updated.orders.target_id         = decision.get("target_id", "")

	elif subtype.begins_with("fight_"):
		# ALL fighter maneuvers (fight_*) - pass through everything automatically
		# This ensures new maneuvers don't get forgotten
		updated.orders.current_order = "fighter_engage"
		updated.orders.target_id = decision.get("target_id", "")
		updated.orders.maneuver_subtype = subtype
		# Copy ALL optional fields - new fields automatically pass through
		updated.orders.formation_offset = decision.get("formation_offset", Vector2.ZERO)
		updated.orders.behind_position = decision.get("behind_position", Vector2.ZERO)
		updated.orders.nearby_fighters = decision.get("nearby_fighters", 0)
		updated.orders.evasion_direction = decision.get("evasion_direction", 0)
		updated.orders.formation_position = decision.get("formation_position", Vector2.ZERO)
		updated.orders.lateral_thrust = decision.get("lateral_thrust", 0)
		updated.orders.position_side = decision.get("position_side", 0)
		updated.orders.skill_factor = decision.get("skill_factor", 0.5)
		# Survival-reflex flee mode ("retreat"/"evade", "" when not fleeing).
		# Read by FleeDecisionSystem as one flee-pressure input; defaulting to
		# "" makes it self-clearing when the next decision is no longer a
		# survival reflex.
		updated.orders.survival_mode = decision.get("survival_mode", "")
		# NEW: Skill-based approach data
		updated.orders.approach_style = decision.get("approach_style", 0)  # 0 = DIRECT
		updated.orders.position_advantage = decision.get("position_advantage", "neutral")
		updated.orders.jink_amplitude = decision.get("jink_amplitude", 0.0)
		updated.orders.jink_hold_ms = decision.get("jink_hold_ms", WingConstants.PILOT_JINK_HOLD_LOW_SKILL_MS)
		updated.orders.approach_angle = decision.get("approach_angle", 0.0)
	elif subtype.begins_with("large_ship_"):
		# ALL large ship maneuvers (large_ship_*) - corvettes and capitals
		updated.orders.current_order = "large_ship_engage"
		updated.orders.target_id = decision.get("target_id", "")
		updated.orders.maneuver_subtype = subtype
		updated.orders.skill_factor = decision.get("skill_factor", 0.5)

	# Lock the flee decision into orders. A flee maneuver carries the new value
	# (including "" to release the lock); any other maneuver preserves the
	# current lock so a committed ship isn't un-committed before it exits.
	updated.orders.flee_decision = decision.get("flee_decision",
		ship_data.get("orders", {}).get("flee_decision", ""))
	updated.orders.flee_target = decision.get("flee_target",
		ship_data.get("orders", {}).get("flee_target", Vector2.ZERO))

	# Stamp fire intent on pilot-operated weapons.
	# A live pilot always fires when the weapon arc/range allows — the weapon's own
	# can_fire_at_target check is the gate, not the maneuver subtype. Pass the
	# decision's target_id if present; an empty intent_target_id lets the weapon
	# pick its best in-arc target automatically.
	# crew_list is threaded in so we know which weapons live gunners own — the pilot
	# only stamps weapons that no gunner is assigned to.
	if crew_data and crew_data.get("role", -1) == CrewData.Role.PILOT:
		var target_id: String = decision.get("target_id", "")
		updated = _stamp_operator_intent(updated, crew_data, true, target_id, crew_list)

	# Apply crew skill modifiers to ship stats
	if crew_data and crew_data.has("stats"):
		updated = apply_pilot_skill_modifiers(updated, crew_data)
		updated = AttributeModifierSystem.apply_for_crew(updated, crew_data)

	return updated

## Apply pilot skill modifiers to ship performance.
## Writes factor fields directly onto ship_data.crew_modifiers; MovementSystem
## reads these in its hot path. No intermediate aggregate (e.g. raw skill)
## is kept around — that just begs to be ignored downstream.
##
## Solo fighter pilots are also their own gunner — their forward-fixed
## weapons read crew_modifiers.aim_skill / targeting_style / lead_accuracy,
## and nothing else writes those for fighters since fighter_pilot_ai only
## produces "maneuver" decisions. So the pilot path writes the gunner-side
## fields too. A real gunner on a heavier ship overwrites these via their
## own fire decision (last writer wins, one shared modifier set per ship).
static func apply_pilot_skill_modifiers(ship_data: Dictionary, crew_data: Dictionary) -> Dictionary:
	var updated = ship_data.duplicate(true)
	var skill_factor = CrewAISystem.calculate_effective_skill(crew_data)

	if not updated.has("crew_modifiers"):
		updated.crew_modifiers = {}

	updated.crew_modifiers.pilot_turn_factor = lerp(WingConstants.PILOT_TURN_RATE_MIN,
													WingConstants.PILOT_TURN_RATE_MAX, skill_factor)
	updated.crew_modifiers.pilot_accel_factor = lerp(WingConstants.PILOT_ACCEL_MIN,
													 WingConstants.PILOT_ACCEL_MAX, skill_factor)
	updated.crew_modifiers.pilot_lateral_factor = lerp(WingConstants.PILOT_LATERAL_MIN,
													   WingConstants.PILOT_LATERAL_MAX, skill_factor)
	updated.crew_modifiers.pilot_damp_factor = lerp(WingConstants.PILOT_DAMPENING_MIN,
													WingConstants.PILOT_DAMPENING_MAX, skill_factor)
	updated.crew_modifiers.pilot_reaction = crew_data.stats.reaction_time

	# Aggression is the leash dial: low aggression hugs the patrol area,
	# high aggression chases targets anywhere. MovementSystem.apply_area_leash
	# reads this. Falls back to the legacy aggregate skill so unconfigured
	# crew get baseline behavior.
	var skills: Dictionary = crew_data.get("stats", {}).get("skills", {})
	updated.crew_modifiers.pilot_aggression = float(skills.get("aggression", skill_factor))

	# Anticipation: how fully a pilot flies the *ideal* aim point the nav brain
	# computes (lead a moving target / clip the geometric apex through a gate)
	# vs. just aiming at where the goal is right now. Read by MovementSystem's
	# nav aim. Blend of piloting + awareness.
	var piloting: float = float(skills.get("piloting", skill_factor))
	var awareness: float = float(skills.get("awareness", skill_factor))
	updated.crew_modifiers.pilot_anticipation = clampf(0.6 * piloting + 0.4 * awareness, 0.0, 1.0)

	# Pilot-as-gunner fields for solo fighters. See function doc. Off-role
	# pilots aim worse too — the penalty hits all areas, including the raw
	# aim read that stress/fatigue deliberately leave alone.
	var aim_skill: float = float(skills.get("aim", skill_factor)) \
		* CrewData.role_performance_multiplier(crew_data)
	var composure: float = float(skills.get("composure", skill_factor))
	var stress: float = float(crew_data.get("stats", {}).get("stress", 0.0))
	var effective_composure: float = composure * (1.0 - stress * 0.5)
	updated.crew_modifiers.aim_skill = aim_skill
	updated.crew_modifiers.gunner_panicking = effective_composure < WingConstants.GUNNER_PANIC_COMPOSURE
	updated.crew_modifiers.gunner_reaction = crew_data.stats.reaction_time
	updated.crew_modifiers.targeting_style = _select_targeting_style(aim_skill)
	updated.crew_modifiers.lead_accuracy = lerp(WingConstants.GUNNER_LEAD_MIN,
												WingConstants.GUNNER_LEAD_MAX, aim_skill)

	return updated

# ============================================================================
# FIRE DECISIONS (Gunner)
# ============================================================================

## Apply gunner's fire decision, stamping fire_intent onto the weapons this
## operator mans (scalar weapon_id, list weapon_ids, or pilot forward weapons).
## crew_list is the full live crew array; used when the caller is a pilot so
## only unclaimed weapons are stamped.
static func apply_fire_decision(ship_data: Dictionary, decision: Dictionary, crew_data: Dictionary, crew_list: Array = []) -> Dictionary:
	var updated = ship_data.duplicate(true)

	var subtype: String = decision.get("subtype", "fire")
	var engaging: bool = subtype != "hold_fire"
	var target_id: String = decision.get("target_id", "")

	# Set ship-level target for fallback targeting.
	updated.orders.target_id = target_id

	# Stamp fire_intent onto every weapon this operator mans.
	updated = _stamp_operator_intent(updated, crew_data, engaging, target_id, crew_list)

	# Apply gunner skill to weapon accuracy
	if crew_data and crew_data.has("stats"):
		updated = apply_gunner_skill_modifiers(updated, crew_data)
		updated = AttributeModifierSystem.apply_for_crew(updated, crew_data)

	return updated


## Stamp fire_intent / intent_target_id onto all weapons operated by this crew member.
## Returns the updated ship_data dictionary (pure function — does not mutate in place).
## Handles all crew shapes: scalar weapon_id, list weapon_ids (pepperbox), and
## pilot-operated forward weapons (solo fighter — no bound gunner on those weapons).
##
## crew_list: the full live crew array. Used for the PILOT branch to determine
## which weapons are claimed by a live gunner so the pilot only stamps the rest.
## For the GUNNER branch, only crew_data's own weapon bindings are used — the
## gunner always stamps exactly their own weapon(s).
static func _stamp_operator_intent(ship_data: Dictionary, crew_data: Dictionary,
		engaging: bool, target_id: String, crew_list: Array = []) -> Dictionary:
	var weapons: Array = ship_data.get("weapons", []).duplicate(true)
	if weapons.is_empty():
		return ship_data

	var role: int = crew_data.get("role", -1)

	if role == CrewData.Role.GUNNER:
		if crew_data.has("weapon_ids"):
			# Grouped pepperbox gunner: stamp every weapon in the group.
			var ids: Array = crew_data.get("weapon_ids", []).map(func(x): return str(x))
			for i in weapons.size():
				if str(weapons[i].get("weapon_id", "")) in ids:
					weapons[i] = _set_weapon_intent(weapons[i], engaging, target_id)
		elif crew_data.has("weapon_id"):
			# Standard 1:1 gunner.
			var wid: String = str(crew_data.get("weapon_id", ""))
			for i in weapons.size():
				if str(weapons[i].get("weapon_id", "")) == wid:
					weapons[i] = _set_weapon_intent(weapons[i], engaging, target_id)
		# Gunner with no binding: no stamping — no weapon is theirs.
	elif role == CrewData.Role.PILOT:
		# Pilot operates all weapons that have no live gunner assigned.
		# Source the claimed-id set from the LIVE crew_list so this is correct
		# even when ship_data has no embedded "crew" key (the normal runtime case:
		# ShipData.create_ship_instance is called with create_crew=false and crew
		# lives in space_battle_game._crew_list instead).
		var ship_id: String = ship_data.get("ship_id", "")
		var gunner_claimed: Dictionary = _build_gunner_claimed_ids_from_crew_list(crew_list, ship_id)
		for i in weapons.size():
			var wid: String = str(weapons[i].get("weapon_id", ""))
			if not gunner_claimed.has(wid):
				weapons[i] = _set_weapon_intent(weapons[i], engaging, target_id)

	var updated: Dictionary = ship_data.duplicate(true)
	updated["weapons"] = weapons

	# When a gunner stamps, persist their weapon claim set in ship_data so that
	# reconcile_weapon_intents can detect dead-gunner weapons even after the gunner
	# is removed from the live crew_list.  We merge into the existing set (never
	# remove entries) so a second gunner stamping after the first gunner died still
	# knows the first gunner's weapon was gunner-operated.
	if role == CrewData.Role.GUNNER:
		var all_claimed: Dictionary = updated.get("_gunner_weapon_ids", {}).duplicate()
		if crew_data.has("weapon_ids"):
			for wid in crew_data.get("weapon_ids", []):
				all_claimed[str(wid)] = true
		elif crew_data.has("weapon_id"):
			all_claimed[str(crew_data.get("weapon_id", ""))] = true
		updated["_gunner_weapon_ids"] = all_claimed

	return updated


## Build a set of weapon_ids claimed by any live gunner assigned to ship_id in crew_list.
## This is the authoritative source for "which weapons does a pilot NOT operate":
## it reads the LIVE crew list (not ship_data.crew, which is empty at runtime).
static func _build_gunner_claimed_ids_from_crew_list(crew_list: Array, ship_id: String) -> Dictionary:
	var claimed: Dictionary = {}
	for member in crew_list:
		if member.get("assigned_to", "") != ship_id:
			continue
		if int(member.get("role", -1)) != CrewData.Role.GUNNER:
			continue
		if member.has("weapon_ids"):
			for wid in member.get("weapon_ids", []):
				claimed[str(wid)] = true
		elif member.has("weapon_id"):
			claimed[str(member.get("weapon_id", ""))] = true
	return claimed


## Return a copy of a weapon dict with intent fields set.
static func _set_weapon_intent(weapon: Dictionary, engaging: bool, target_id: String) -> Dictionary:
	var w: Dictionary = weapon.duplicate()
	w["fire_intent"] = engaging
	w["intent_target_id"] = target_id if engaging else ""
	return w


## Clear fire_intent on any weapon whose bound gunner is no longer in crew_list.
## Pilot-operated weapons (not claimed by any gunner in crew_list) are left
## alone — a live pilot keeps them firing.
## Call this before _process_weapons so dead-gunner weapons go silent.
static func reconcile_weapon_intents(ship_data: Dictionary, crew_list: Array) -> Dictionary:
	var weapons: Array = ship_data.get("weapons", [])
	if weapons.is_empty():
		return ship_data

	var ship_id: String = ship_data.get("ship_id", "")

	# Build sets of live crew on this ship.
	var live_pilots: bool = false
	var live_gunner_weapon_ids: Dictionary = {}
	for crew in crew_list:
		if crew.get("assigned_to", "") != ship_id:
			continue
		var role: int = int(crew.get("role", -1))
		if role == CrewData.Role.PILOT:
			live_pilots = true
		elif role == CrewData.Role.GUNNER:
			if crew.has("weapon_ids"):
				for wid in crew.get("weapon_ids", []):
					live_gunner_weapon_ids[str(wid)] = true
			elif crew.has("weapon_id"):
				live_gunner_weapon_ids[str(crew.get("weapon_id", ""))] = true

	# Build the complete set of gunner-owned weapon ids.  Prefer the persistent
	# cache stamped onto ship_data by _stamp_operator_intent each time a gunner
	# fires — this survives crew death and does not rely on ship_data.crew (which
	# is empty at runtime).  Fall back to the live crew_list if the cache is
	# absent (e.g. first frame before any gunner decision has been applied).
	var all_gunner_weapon_ids: Dictionary
	if ship_data.has("_gunner_weapon_ids"):
		all_gunner_weapon_ids = ship_data["_gunner_weapon_ids"]
	else:
		all_gunner_weapon_ids = _build_gunner_claimed_ids_from_crew_list(crew_list, ship_id)

	var changed := false
	var updated_weapons: Array = weapons.duplicate(true)
	for i in updated_weapons.size():
		var w: Dictionary = updated_weapons[i]
		if not w.has("fire_intent"):
			continue  # No intent stamped yet; compat default (fire) applies.
		var wid: String = str(w.get("weapon_id", ""))
		if all_gunner_weapon_ids.has(wid):
			# This weapon belongs to a gunner; silence it if that gunner is gone.
			if not live_gunner_weapon_ids.has(wid):
				updated_weapons[i] = _set_weapon_intent(w, false, "")
				changed = true
		else:
			# Pilot-operated weapon: keep intent as long as a pilot is alive.
			if not live_pilots and w.get("fire_intent", false) != false:
				updated_weapons[i] = _set_weapon_intent(w, false, "")
				changed = true

	if not changed:
		return ship_data

	var result: Dictionary = ship_data.duplicate(true)
	result["weapons"] = updated_weapons
	return result

## Apply gunner skill modifiers to weapons.
## Writes raw aim skill onto ship_data.crew_modifiers; WeaponSystem reads it
## for the spread cone. Also written by fighter pilots whose forward-fixed
## weapons aim with piloting+aim — caller picks crew based on weapon type.
## DRAMATIC skill differences: 0-skill sprays wildly, 1.0-skill lands precise shots.
static func apply_gunner_skill_modifiers(ship_data: Dictionary, crew_data: Dictionary) -> Dictionary:
	var updated = ship_data.duplicate(true)
	var skill_factor = CrewAISystem.calculate_effective_skill(crew_data)

	if not updated.has("crew_modifiers"):
		updated.crew_modifiers = {}

	# Panic state: low composure under stress overrides the skill curve.
	var composure = crew_data.get("stats", {}).get("skills", {}).get("composure", skill_factor)
	var stress = crew_data.get("stats", {}).get("stress", 0.0)
	var effective_composure = composure * (1.0 - stress * 0.5)
	var is_panicking = effective_composure < WingConstants.GUNNER_PANIC_COMPOSURE

	# Raw aim skill drives the spread cone. Stress/fatigue degrade
	# `skill_factor` for other downstream effects, but the cone uses raw aim
	# so a 20-aim crew stays tight even under fire — composure gates panic.
	# The off-role penalty DOES hit the cone: it degrades all areas.
	updated.crew_modifiers.aim_skill = float(crew_data.get("stats", {}).get("skills", {}).get("aim", skill_factor)) \
		* CrewData.role_performance_multiplier(crew_data)
	updated.crew_modifiers.gunner_panicking = is_panicking
	updated.crew_modifiers.gunner_reaction = crew_data.stats.reaction_time

	# Select targeting style based on skill
	updated.crew_modifiers.targeting_style = _select_targeting_style(skill_factor)

	# Calculate lead accuracy (how well gunner predicts target position)
	updated.crew_modifiers.lead_accuracy = lerp(WingConstants.GUNNER_LEAD_MIN,
												WingConstants.GUNNER_LEAD_MAX, skill_factor)

	# Skilled gunners hold fire until within preferred range for a sure shot.
	# Threshold < 0.70 has no effect (all in-range targets already qualify).
	updated.crew_modifiers.min_range_factor = updated.crew_modifiers.aim_skill * WingConstants.GUNNER_MIN_RANGE_FACTOR

	return updated

## Select targeting style based on gunner skill
static func _select_targeting_style(skill: float) -> int:
	if skill >= WingConstants.GUNNER_SUBSYSTEM_SKILL:
		return TargetingStyle.SUBSYSTEM
	elif skill >= WingConstants.GUNNER_PREDICTIVE_SKILL:
		return TargetingStyle.PREDICTIVE
	elif skill >= WingConstants.GUNNER_LEADING_SKILL:
		return TargetingStyle.LEADING
	else:
		return TargetingStyle.SIMPLE

# ============================================================================
# TACTICAL DECISIONS (Captain)
# ============================================================================

## Apply captain's tactical decision
static func apply_tactical_decision(ship_data: Dictionary, decision: Dictionary, crew_data: Dictionary) -> Dictionary:
	var updated = ship_data.duplicate(true)

	match decision.get("subtype"):
		"engage":
			updated.orders.current_order = "engage"
			updated.orders.target_id = decision.get("target_id", "")
		"hold":
			updated.orders.current_order = "hold"
		"withdraw":
			updated.orders.current_order = "withdraw"
		_:
			pass

	# Captain's skill affects overall ship coordination
	if crew_data and crew_data.has("stats"):
		updated = apply_captain_skill_modifiers(updated, crew_data)
		updated = AttributeModifierSystem.apply_for_crew(updated, crew_data)

	return updated

## Apply captain skill modifiers
## DRAMATIC skill differences: 0-skill issues confused orders, 1.0-skill orchestrates perfectly
static func apply_captain_skill_modifiers(ship_data: Dictionary, crew_data: Dictionary) -> Dictionary:
	var updated = ship_data.duplicate(true)
	var skill_factor = CrewAISystem.calculate_effective_skill(crew_data)

	if not updated.has("crew_modifiers"):
		updated.crew_modifiers = {}

	updated.crew_modifiers.captain_skill = skill_factor

	# Coordination bonus: -10% to +30% (was 0-20%)
	updated.crew_modifiers.captain_coordination = lerp(WingConstants.CAPTAIN_COORDINATION_MIN,
													   WingConstants.CAPTAIN_COORDINATION_MAX, skill_factor)

	# Select command style based on skill
	updated.crew_modifiers.command_style = _select_command_style(skill_factor)

	# Decision delay: 1.5s (low skill) to 0.3s (high skill)
	updated.crew_modifiers.captain_decision_delay = lerp(WingConstants.CAPTAIN_DECISION_DELAY_MAX,
														 WingConstants.CAPTAIN_DECISION_DELAY_MIN, skill_factor)

	# Order clarity: 60% to 100% effectiveness
	updated.crew_modifiers.order_clarity = lerp(WingConstants.CAPTAIN_ORDER_CLARITY_MIN,
												WingConstants.CAPTAIN_ORDER_CLARITY_MAX, skill_factor)

	# Threat assessment accuracy: 40% to 100%
	updated.crew_modifiers.threat_assessment = lerp(WingConstants.CAPTAIN_THREAT_ASSESSMENT_MIN,
													WingConstants.CAPTAIN_THREAT_ASSESSMENT_MAX, skill_factor)

	# Damage control effectiveness: 50% to 120%
	updated.crew_modifiers.damage_control = lerp(WingConstants.CAPTAIN_DAMAGE_CONTROL_MIN,
												 WingConstants.CAPTAIN_DAMAGE_CONTROL_MAX, skill_factor)

	return updated

# ============================================================================
# REPAIR DECISIONS (Engineer)
# ============================================================================

## Apply an engineer's repair decision. The heal is a machinery-skill-scaled
## fraction of the target's maximum, boosted by the captain's damage-control
## modifier. Destroyed components are beyond in-battle field repair.
## Draws from the ship's battle-scoped repair_pool (Layer D); returns ship
## unchanged when the pool is exhausted.
static func apply_repair_decision(ship_data: Dictionary, decision: Dictionary, _crew_data: Dictionary) -> Dictionary:
	# Layer D: pool gate — no pool, no repair.
	var pool: int = ship_data.get("repair_pool", 0)
	if pool <= 0:
		return ship_data

	var skill_factor: float = decision.get("skill_factor", 0.5)
	var damage_control: float = ship_data.get("crew_modifiers", {}).get("damage_control", 1.0)
	var fraction: float = lerpf(WingConstants.ENGINEER_REPAIR_FRACTION_MIN,
								WingConstants.ENGINEER_REPAIR_FRACTION_MAX, skill_factor) * damage_control

	var updated: Dictionary
	var amount: int
	if decision.has("component_id"):
		var component = DamageResolver.find_internal_by_id(ship_data, decision.component_id)
		if component.is_empty():
			return ship_data
		amount = RepairSystem.fraction_to_amount(component.get("max_health", 0), fraction)
		amount = mini(amount, pool)   # clamp to remaining pool
		if amount <= 0:
			return ship_data
		updated = RepairSystem.repair_component(ship_data, decision.component_id, amount)
	elif decision.has("section_id"):
		var section = RepairSystem.find_armor_section_by_id(ship_data, decision.section_id)
		if section.is_empty():
			return ship_data
		amount = RepairSystem.fraction_to_amount(section.get("max_armor", 0), fraction)
		amount = mini(amount, pool)   # clamp to remaining pool
		if amount <= 0:
			return ship_data
		updated = RepairSystem.repair_armor_section(ship_data, decision.section_id, amount)
	else:
		return ship_data

	# Draw down the pool.
	updated["repair_pool"] = pool - amount

	# Stamp the repair pulse so the renderer can show the heal landing.
	updated = DictUtils.merge_dict(updated, {
		"_repair_flash_until": decision.get("timestamp", 0.0) + WingConstants.ENGINEER_REPAIR_FLASH_SECONDS
	})

	if BattleEventLoggerAutoload.service:
		BattleEventLoggerAutoload.service.log_event("repair_applied", {
			"ship_id": ship_data.get("ship_id", ""),
			"crew_id": decision.get("crew_id", ""),
			"subtype": decision.get("subtype", ""),
			"amount": amount,
			"repair_pool_remaining": updated["repair_pool"],
		})
	return updated

## Select command style based on captain skill
static func _select_command_style(skill: float) -> int:
	if skill >= WingConstants.CAPTAIN_ADAPTIVE_SKILL:
		return CommandStyle.ADAPTIVE
	elif skill >= WingConstants.CAPTAIN_TACTICAL_SKILL:
		return CommandStyle.TACTICAL
	elif skill >= WingConstants.CAPTAIN_STANDARD_SKILL:
		return CommandStyle.STANDARD
	else:
		return CommandStyle.REACTIVE

## Select coordination style based on squadron leader skill
static func _select_coordination_style(skill: float) -> int:
	if skill >= WingConstants.SQUADRON_ORCHESTRATED_SKILL:
		return CoordinationStyle.ORCHESTRATED
	elif skill >= WingConstants.SQUADRON_LOOSE_SKILL:
		return CoordinationStyle.LOOSE
	else:
		return CoordinationStyle.INDIVIDUAL

# ============================================================================
# CREW AWARENESS TO TARGET SELECTION
# ============================================================================

## Get preferred targets from crew awareness
static func get_crew_preferred_targets(ship_id: String, crew_list: Array) -> Array:
	# Find captain or highest-ranking crew for this ship
	var ship_commander = find_ship_commander(ship_id, crew_list)
	if ship_commander.is_empty():
		return []

	# Return their prioritized opportunities
	return ship_commander.awareness.opportunities

## Find the commanding crew member for a ship
static func find_ship_commander(ship_id: String, crew_list: Array) -> Dictionary:
	# Look for captain first, then pilot
	var captain = find_crew_by_role_and_ship(CrewData.Role.CAPTAIN, ship_id, crew_list)
	if not captain.is_empty():
		return captain

	var pilot = find_crew_by_role_and_ship(CrewData.Role.PILOT, ship_id, crew_list)
	return pilot

## Find crew by role assigned to specific ship
static func find_crew_by_role_and_ship(role: int, ship_id: String, crew_list: Array) -> Dictionary:
	for crew in crew_list:
		if crew.role == role and crew.assigned_to == ship_id:
			return crew
	return {}

# ============================================================================
# IMMEDIATE ACTIONS EXTRACTION
# ============================================================================

## Extract actions that need immediate processing
static func extract_immediate_actions(decisions: Array) -> Array:
	var actions = []

	for decision in decisions:
		match decision.get("type"):
			"fire":
				# Convert to fire command for weapon system
				actions.append(create_fire_action(decision))
			_:
				pass  # Other decisions modify ship state

	return actions

## Create fire action from decision
static func create_fire_action(decision: Dictionary) -> Dictionary:
	return {
		"type": "crew_fire_command",
		"entity_id": decision.get("entity_id", ""),
		"target_id": decision.get("target_id", ""),
		"crew_id": decision.get("crew_id", ""),
		"skill_factor": decision.get("skill_factor", 0.5),
		"delay": decision.get("delay", 0.2)
	}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

## Find ship index by ID
static func find_ship_index(ships: Array, ship_id: String) -> int:
	for i in ships.size():
		if ships[i].ship_id == ship_id:
			return i
	return -1

## Find crew by ID
static func find_crew_by_id(crew_list: Array, crew_id: String) -> Dictionary:
	for crew in crew_list:
		if crew.crew_id == crew_id:
			return crew
	return {}

## Check if ship has crew assigned
static func has_crew_assigned(ship_data: Dictionary, crew_list: Array) -> bool:
	return not get_ship_crew(ship_data.ship_id, crew_list).is_empty()

## Get all crew assigned to a ship
static func get_ship_crew(ship_id: String, crew_list: Array) -> Array:
	return crew_list.filter(func(crew): return crew.assigned_to == ship_id)

## Create crew assignments for ship
static func assign_crew_to_ship(ship_data: Dictionary, crew: Array) -> Dictionary:
	var updated = ship_data.duplicate(true)

	if not updated.has("crew_assignments"):
		updated.crew_assignments = {}

	for crew_member in crew:
		var role_name = CrewData.get_role_name(crew_member.role)
		updated.crew_assignments[role_name] = crew_member.crew_id

	return updated
