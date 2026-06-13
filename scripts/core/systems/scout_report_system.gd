class_name ScoutReportSystem
extends RefCounted

## Deliberately fuzzy pre-battle intel — reveals approximate information
## about an enemy fleet without exposing exact composition.
## Deterministic (no RNG) so a node always reports the same result.

## Contact counts are rounded to this granularity.
const CONTACT_COUNT_GRANULARITY := 2

## Ship classes ordered from smallest to largest.
const CLASS_SIZE_ORDER := ["fighter", "heavy_fighter", "torpedo_boat", "corvette", "capital"]


## Returns an Array of Strings describing the enemy fleet in vague terms.
## Empty or zero-total fleet returns a single "no contacts" line.
static func report_lines(enemy_fleet: Dictionary) -> Array:
	var total := 0
	for count in enemy_fleet.values():
		total += int(count)

	if total == 0:
		return ["No contacts on long-range scan."]

	var lines := []

	# Approximate contact count rounded to granularity
	var rounded := int(round(float(total) / float(CONTACT_COUNT_GRANULARITY))) * CONTACT_COUNT_GRANULARITY
	rounded = max(rounded, CONTACT_COUNT_GRANULARITY)
	lines.append("Contacts: ~%d signatures" % rounded)

	# Largest hull class present
	var largest_class := ""
	for hull_class in CLASS_SIZE_ORDER:
		if enemy_fleet.get(hull_class, 0) > 0:
			largest_class = hull_class
	if largest_class != "":
		lines.append("Largest contact: %s class" % largest_class.capitalize())

	lines.append("Full composition unknown.")
	return lines
