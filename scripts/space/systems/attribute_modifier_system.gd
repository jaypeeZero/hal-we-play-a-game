class_name AttributeModifierSystem
extends RefCounted

## Pure system that folds each crew member's attribute combat effects onto
## ship_data.crew_modifiers. Called once per decision cycle, after
## CrewIntegrationSystem has written the base skill modifiers.
##
## Attribute effects layer on top of — not instead of — skill-derived values.
## Returns a new ship_data dict; never mutates the argument.

## Apply every combat-bearing attribute from crew_data onto ship_data.crew_modifiers.
## Pure: input ship_data is unchanged; a deep-duplicated copy is returned.
static func apply_for_crew(ship_data: Dictionary, crew_data: Dictionary) -> Dictionary:
	"""Return updated ship_data with crew attribute combat effects applied to crew_modifiers."""
	var updated: Dictionary = ship_data.duplicate(true)
	if not updated.has("crew_modifiers"):
		updated["crew_modifiers"] = {}

	var attributes: Array = crew_data.get("attributes", [])
	for attr_id in attributes:
		var defn: Dictionary = AttributeLibrary.get_def(str(attr_id))
		if defn.is_empty():
			continue
		var combat = defn.get("combat")
		if combat == null:
			continue
		var kind: String = str(combat.get("kind", ""))
		var value: float = float(combat.get("value", 0.0))
		_apply_kind(updated, crew_data, kind, value)

	return updated


## Apply a single combat effect kind onto updated["crew_modifiers"].
static func _apply_kind(updated: Dictionary, crew_data: Dictionary, kind: String, value: float) -> void:
	"""Apply one combat effect kind onto updated.crew_modifiers in place."""
	var cm: Dictionary = updated["crew_modifiers"]
	match kind:
		"lead_accuracy":
			cm["lead_accuracy"] = float(cm.get("lead_accuracy", 0.0)) + value

		"composure_factor":
			# Re-derive gunner_panicking with composure scaled by (1 + value).
			var skills: Dictionary = crew_data.get("stats", {}).get("skills", {})
			var composure: float = float(skills.get("composure", 0.5))
			var stress: float = float(crew_data.get("stats", {}).get("stress", 0.0))
			var effective_composure: float = composure * (1.0 + value) * (1.0 - stress * 0.5)
			cm["gunner_panicking"] = effective_composure < WingConstants.GUNNER_PANIC_COMPOSURE

		"turn_rate":
			cm["pilot_turn_factor"] = float(cm.get("pilot_turn_factor", 1.0)) * (1.0 + value)

		"aggression":
			cm["pilot_aggression"] = clampf(float(cm.get("pilot_aggression", 0.5)) + value, 0.0, 1.0)

		"accel":
			cm["pilot_accel_factor"] = float(cm.get("pilot_accel_factor", 1.0)) * (1.0 + value)

		"close_range_fire_rate":
			cm["close_range_fire_bonus"] = float(cm.get("close_range_fire_bonus", 0.0)) + value

		"last_stand":
			cm["low_hp_aim_bonus"] = float(cm.get("low_hp_aim_bonus", 0.0)) + value
