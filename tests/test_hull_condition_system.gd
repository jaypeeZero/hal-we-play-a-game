extends GutTest

## Tests for HullConditionSystem — behavior only, no specific data values.


func test_pristine_hull_reads_fully_intact():
	var hull := {"ship": {}}
	var cond := HullConditionSystem.condition(hull)
	assert_eq(cond.armor, 1.0, "Pristine hull armor is 1.0")
	assert_eq(cond.systems, 1.0, "Pristine hull systems is 1.0")


func test_hull_with_no_ship_key_reads_fully_intact():
	var hull := {}
	var cond := HullConditionSystem.condition(hull)
	assert_eq(cond.armor, 1.0, "Missing ship key armor is 1.0")
	assert_eq(cond.systems, 1.0, "Missing ship key systems is 1.0")


func test_fully_damaged_armor_reads_zero():
	var hull := {
		"ship": {
			"armor_sections": [
				{"current_armor": 0.0, "max_armor": 10.0},
				{"current_armor": 0.0, "max_armor": 10.0},
			],
			"internals": [],
		}
	}
	var cond := HullConditionSystem.condition(hull)
	assert_eq(cond.armor, 0.0, "Fully destroyed armor reads 0.0")


func test_partially_damaged_armor_produces_proportional_ratio():
	var hull := {
		"ship": {
			"armor_sections": [
				{"current_armor": 5.0, "max_armor": 10.0},
				{"current_armor": 5.0, "max_armor": 10.0},
			],
			"internals": [],
		}
	}
	var cond := HullConditionSystem.condition(hull)
	assert_eq(cond.armor, 0.5, "Half-destroyed armor reads 0.5")


func test_partially_damaged_systems_produces_proportional_ratio():
	var hull := {
		"ship": {
			"armor_sections": [],
			"internals": [
				{"current_health": 3.0, "max_health": 4.0},
				{"current_health": 1.0, "max_health": 4.0},
			],
		}
	}
	var cond := HullConditionSystem.condition(hull)
	assert_eq(cond.systems, 0.5, "Half-destroyed systems reads 0.5")


func test_zero_max_armor_does_not_divide_by_zero():
	var hull := {
		"ship": {
			"armor_sections": [
				{"current_armor": 0.0, "max_armor": 0.0},
			],
			"internals": [],
		}
	}
	var cond := HullConditionSystem.condition(hull)
	assert_eq(cond.armor, 1.0, "Zero-max armor returns 1.0 (no divide by zero)")


func test_zero_max_systems_does_not_divide_by_zero():
	var hull := {
		"ship": {
			"armor_sections": [],
			"internals": [
				{"current_health": 0.0, "max_health": 0.0},
			],
		}
	}
	var cond := HullConditionSystem.condition(hull)
	assert_eq(cond.systems, 1.0, "Zero-max systems returns 1.0 (no divide by zero)")


func test_result_aggregates_multiple_sections():
	var hull := {
		"ship": {
			"armor_sections": [
				{"current_armor": 8.0, "max_armor": 10.0},
				{"current_armor": 4.0, "max_armor": 10.0},
			],
			"internals": [
				{"current_health": 6.0, "max_health": 10.0},
				{"current_health": 2.0, "max_health": 10.0},
			],
		}
	}
	var cond := HullConditionSystem.condition(hull)
	assert_eq(cond.armor, 0.6, "Armor averages 12/20 = 0.6")
	assert_eq(cond.systems, 0.4, "Systems averages 8/20 = 0.4")
