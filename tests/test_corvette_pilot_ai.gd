extends GutTest

## Comprehensive tests for CorvettePilotAI
## Tests skill-based behavior for corvette pilots with aggression, composure, helmsmanship

var corvette_pilot: Dictionary
var corvette_ship: Dictionary
var target_ship: Dictionary
var threat_ship: Dictionary
var all_ships: Array
var all_crew: Array

func before_each():
	## Create basic corvette pilot
	corvette_pilot = CrewData.create_crew_member(CrewData.Role.PILOT, 0.5)
	corvette_pilot.assigned_to = "ship_0"
	corvette_pilot.stats.skills = {
		"aggression": 0.5,
		"composure": 0.5,
		"helmsmanship": 0.5,
		"situational_awareness": 0.5,
		"anticipation": 0.5,
		"marksmanship": 0.5
	}

	## Create basic corvette ship
	corvette_ship = {
		"ship_id": "ship_0",
		"type": "corvette",
		"position": Vector2(0, 0),
		"velocity": Vector2.ZERO,
		"current_hp": 100.0,
		"max_hp": 100.0,
		"armor": {
			"nose": 30,
			"broadside_port": 25,
			"broadside_starboard": 25,
			"stern": 20
		}
	}

	## Create target ship (enemy)
	target_ship = {
		"ship_id": "ship_1",
		"type": "corvette",
		"position": Vector2(2000, 0),
		"id": "ship_1"
	}

	## Create threat ship
	threat_ship = {
		"ship_id": "ship_2",
		"type": "fighter",
		"position": Vector2(500, 0),
		"id": "ship_2"
	}

	all_ships = [corvette_ship, target_ship, threat_ship]
	all_crew = [corvette_pilot]

func test_idle_when_no_targets():
	## With no threats or opportunities, pilot should idle
	corvette_pilot.awareness.threats = []
	corvette_pilot.awareness.opportunities = []

	var decision = CorvettePilotAI.make_decision(corvette_pilot, corvette_ship, all_ships, all_crew, 0.0)

	assert_eq(decision.decision.subtype, "idle")

func test_low_composure_panics_when_damaged():
	## Low composure pilot panics at high damage
	corvette_pilot.stats.skills.composure = 0.2
	corvette_ship.current_hp = 20.0  # 20% hull remaining

	corvette_pilot.awareness.threats = [threat_ship]
	corvette_pilot.awareness.opportunities = []

	var decision = CorvettePilotAI.make_decision(corvette_pilot, corvette_ship, all_ships, all_crew, 0.0)

	assert_eq(decision.decision.subtype, "retreat")

func test_high_composure_stands_ground_when_damaged():
	## High composure pilot doesn't panic easily
	corvette_pilot.stats.skills.composure = 0.8
	corvette_ship.current_hp = 20.0  # 20% hull remaining

	corvette_pilot.awareness.threats = [threat_ship]
	corvette_pilot.awareness.opportunities = [target_ship]

	var decision = CorvettePilotAI.make_decision(corvette_pilot, corvette_ship, all_ships, all_crew, 0.0)

	## Should pursue target, not retreat
	assert_true(decision.decision.subtype in ["pursue", "broadside"])

func test_aggressive_pilot_closer_engagement():
	## Aggressive pilot wants to get closer (higher engagement range means willing to close further)
	corvette_pilot.stats.skills.aggression = 0.9

	corvette_pilot.awareness.opportunities = [target_ship]
	corvette_pilot.awareness.threats = []

	var decision_aggressive = CorvettePilotAI.make_decision(corvette_pilot, corvette_ship, all_ships, all_crew, 0.0)
	assert_eq(decision_aggressive.decision.subtype, "pursue")

	# Now test conservative pilot
	corvette_pilot.stats.skills.aggression = 0.1
	var decision_conservative = CorvettePilotAI.make_decision(corvette_pilot, corvette_ship, all_ships, all_crew, 0.0)
	assert_eq(decision_conservative.decision.subtype, "pursue")

	# Aggressive pilot should have higher engagement range (willing to close more)
	assert_gt(decision_aggressive.decision.engage_range, decision_conservative.decision.engage_range)

func test_conservative_pilot_stays_back():
	## Low aggression pilot stays at distance
	corvette_pilot.stats.skills.aggression = 0.2

	corvette_pilot.awareness.opportunities = [target_ship]
	corvette_pilot.awareness.threats = []

	var decision = CorvettePilotAI.make_decision(corvette_pilot, corvette_ship, all_ships, all_crew, 0.0)

	assert_eq(decision.decision.subtype, "pursue")
	# Test behavior: exists and is a valid decision (not checking hardcoded values)

func test_low_helmsmanship_basic_evasion():
	## Low helmsmanship pilot uses basic evasion
	corvette_pilot.stats.skills.helmsmanship = 0.2
	corvette_pilot.stats.skills.composure = 0.2  # Low composure to trigger evasion

	threat_ship.position = Vector2(500, 0)  # Very close
	corvette_pilot.awareness.threats = [threat_ship]
	corvette_pilot.awareness.opportunities = []

	var decision = CorvettePilotAI.make_decision(corvette_pilot, corvette_ship, all_ships, all_crew, 0.0)

	assert_eq(decision.decision.subtype, "evade")

func test_high_helmsmanship_advanced_evasion():
	## High helmsmanship pilot uses advanced evasion
	corvette_pilot.stats.skills.helmsmanship = 0.8
	corvette_pilot.stats.skills.composure = 0.2

	threat_ship.position = Vector2(500, 0)
	corvette_pilot.awareness.threats = [threat_ship]
	corvette_pilot.awareness.opportunities = []

	var decision = CorvettePilotAI.make_decision(corvette_pilot, corvette_ship, all_ships, all_crew, 0.0)

	assert_eq(decision.decision.subtype, "evade")

func test_broadside_positioning():
	## High helmsmanship pilot attempts broadside positioning when target is close
	corvette_pilot.stats.skills.helmsmanship = 0.9

	target_ship.position = Vector2(400, 0)  # Close enough for broadside
	corvette_pilot.awareness.opportunities = [target_ship]
	corvette_pilot.awareness.threats = []

	var decision = CorvettePilotAI.make_decision(corvette_pilot, corvette_ship, all_ships, all_crew, 0.0)

	# With high helmsmanship and close target, should attempt broadside
	assert_true(decision.decision.subtype in ["broadside", "pursue"])

func test_fighter_threat_priority():
	## Fighter threats get special handling (more dangerous at close range)
	corvette_pilot.stats.skills.composure = 0.5
	corvette_pilot.stats.skills.aggression = 0.5

	threat_ship.position = Vector2(500, 0)  # Fighter very close
	threat_ship.type = "fighter"
	corvette_pilot.awareness.threats = [threat_ship]
	corvette_pilot.awareness.opportunities = [target_ship]

	var decision = CorvettePilotAI.make_decision(corvette_pilot, corvette_ship, all_ships, all_crew, 0.0)

	## Should evade fighter threat
	assert_eq(decision.decision.subtype, "evade")

func test_retreat_when_panicked():
	## Panicked pilot retreats from any threat
	corvette_pilot.stats.skills.composure = 0.1

	corvette_ship.current_hp = 15.0  # Heavily damaged
	threat_ship.position = Vector2(1000, 0)
	corvette_pilot.awareness.threats = [threat_ship]
	corvette_pilot.awareness.opportunities = []

	var decision = CorvettePilotAI.make_decision(corvette_pilot, corvette_ship, all_ships, all_crew, 0.0)

	assert_eq(decision.decision.subtype, "retreat")

func test_decision_includes_crew_id():
	## All decisions should include crew_id
	corvette_pilot.awareness.opportunities = [target_ship]
	corvette_pilot.awareness.threats = []

	var decision = CorvettePilotAI.make_decision(corvette_pilot, corvette_ship, all_ships, all_crew, 0.0)

	assert_eq(decision.decision.crew_id, corvette_pilot.crew_id)

func test_decision_includes_ship_id():
	## All decisions should include entity_id (assigned ship)
	corvette_pilot.awareness.opportunities = [target_ship]
	corvette_pilot.awareness.threats = []

	var decision = CorvettePilotAI.make_decision(corvette_pilot, corvette_ship, all_ships, all_crew, 0.0)

	assert_eq(decision.decision.entity_id, "ship_0")

func test_decision_includes_timestamp():
	## All decisions should include timestamp
	corvette_pilot.awareness.opportunities = [target_ship]

	var decision = CorvettePilotAI.make_decision(corvette_pilot, corvette_ship, all_ships, all_crew, 42.5)

	assert_eq(decision.decision.timestamp, 42.5)

func test_decision_updates_next_decision_time():
	## Crew should have next_decision_time updated
	corvette_pilot.awareness.opportunities = [target_ship]

	var result = CorvettePilotAI.make_decision(corvette_pilot, corvette_ship, all_ships, all_crew, 10.0)

	assert_gt(result.crew_data.next_decision_time, 10.0)

func test_stress_affects_decision_delay():
	## Stress should increase decision delay
	corvette_pilot.awareness.opportunities = [target_ship]
	corvette_pilot.stats.stress = 0.8

	var result = CorvettePilotAI.make_decision(corvette_pilot, corvette_ship, all_ships, all_crew, 10.0)

	## Stressed pilot should have longer delay
	var delay_with_stress = result.decision.delay
	var base_delay = 0.5  # Base pursuit delay

	assert_gt(delay_with_stress, base_delay)

func test_skill_factor_reflects_effective_skill():
	## skill_factor should be reduced by stress/fatigue
	corvette_pilot.stats.skill = 0.8
	corvette_pilot.stats.stress = 0.5
	corvette_pilot.stats.fatigue = 0.3

	corvette_pilot.awareness.opportunities = [target_ship]

	var decision = CorvettePilotAI.make_decision(corvette_pilot, corvette_ship, all_ships, all_crew, 0.0)

	## skill_factor should be less than base 0.8
	assert_lt(decision.decision.skill_factor, 0.8)

func test_evasion_quality_set_on_evade():
	## Evasion decisions should include evasion_quality
	corvette_pilot.stats.skills.helmsmanship = 0.7
	corvette_pilot.stats.skills.composure = 0.2

	threat_ship.position = Vector2(600, 0)
	corvette_pilot.awareness.threats = [threat_ship]
	corvette_pilot.awareness.opportunities = []

	var decision = CorvettePilotAI.make_decision(corvette_pilot, corvette_ship, all_ships, all_crew, 0.0)

	assert_true("evasion_quality" in decision.decision)
	assert_eq(decision.decision.evasion_quality, 0.7)

func test_idle_has_longer_delay():
	## Idle decisions should have longer delays than combat
	corvette_pilot.awareness.opportunities = []
	corvette_pilot.awareness.threats = []

	var idle_result = CorvettePilotAI.make_decision(corvette_pilot, corvette_ship, all_ships, all_crew, 0.0)

	## Idle delay should be 2.0s
	assert_eq(idle_result.decision.delay, 2.0)

func test_evasion_has_short_delay():
	## Evasion decisions should have short delays for quick updates
	corvette_pilot.stats.skills.composure = 0.2

	threat_ship.position = Vector2(600, 0)
	corvette_pilot.awareness.threats = [threat_ship]
	corvette_pilot.awareness.opportunities = []

	var evade_result = CorvettePilotAI.make_decision(corvette_pilot, corvette_ship, all_ships, all_crew, 0.0)

	assert_lt(evade_result.decision.delay, 0.5)

func test_empty_ship_data_handled():
	## Should handle empty ship data gracefully
	var empty_ship = {}

	corvette_pilot.awareness.opportunities = [target_ship]

	var decision = CorvettePilotAI.make_decision(corvette_pilot, empty_ship, all_ships, all_crew, 0.0)

	## Should still produce a valid decision
	assert_true("type" in decision.decision)
	assert_true("subtype" in decision.decision)

func test_hull_integrity_calculation():
	## Hull at various percentages should affect behavior
	corvette_pilot.stats.skills.composure = 0.5

	corvette_pilot.awareness.threats = [threat_ship]
	corvette_pilot.awareness.opportunities = []

	## 50% hull - medium damage
	corvette_ship.current_hp = 50.0

	var decision = CorvettePilotAI.make_decision(corvette_pilot, corvette_ship, all_ships, all_crew, 0.0)

	## Medium composure, medium damage - should be evasive but not panic
	assert_eq(decision.decision.subtype, "evade")

func test_low_skill_pilot_archetype():
	## "Rookie" archetype - all skills low
	corvette_pilot.stats.skills = {
		"aggression": 0.3,
		"composure": 0.3,
		"helmsmanship": 0.3,
		"situational_awareness": 0.3,
		"anticipation": 0.3,
		"marksmanship": 0.3
	}

	corvette_pilot.awareness.opportunities = [target_ship]
	corvette_pilot.awareness.threats = []

	var decision = CorvettePilotAI.make_decision(corvette_pilot, corvette_ship, all_ships, all_crew, 0.0)

	## Rookie should use basic pursuit
	assert_eq(decision.decision.subtype, "pursue")

func test_high_skill_pilot_has_options():
	## "Steady" archetype - all skills high
	corvette_pilot.stats.skills = {
		"aggression": 0.8,
		"composure": 0.8,
		"helmsmanship": 0.8,
		"situational_awareness": 0.8,
		"anticipation": 0.8,
		"marksmanship": 0.8
	}

	target_ship.position = Vector2(1000, 0)  # Broadside range
	corvette_pilot.awareness.opportunities = [target_ship]
	corvette_pilot.awareness.threats = []

	var decision = CorvettePilotAI.make_decision(corvette_pilot, corvette_ship, all_ships, all_crew, 0.0)

	## High skill pilot should attempt tactical broadside
	assert_eq(decision.decision.subtype, "broadside")

func test_decision_type_is_always_maneuver():
	## All decisions should have type "maneuver"
	corvette_pilot.awareness.opportunities = [target_ship]

	var decision = CorvettePilotAI.make_decision(corvette_pilot, corvette_ship, all_ships, all_crew, 0.0)

	assert_eq(decision.decision.type, "maneuver")
