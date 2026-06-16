extends GutTest

## Behavior tests for the crew-operator-driven firing model (Plan 06).
## Verifies intent stamping, intent gating, operator liveness, and compat default.

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_ship_with_weapon(weapon_id: String = "w1", cooldown: float = 0.0) -> Dictionary:
	var ship := TestFactories.make_armed_ship("light_cannon", cooldown)
	ship.weapons[0]["weapon_id"] = weapon_id
	return ship


func _make_gunner(crew_id: String, ship_id: String, weapon_id: String) -> Dictionary:
	var g := TestFactories.make_crew_gunner(0.8, ship_id)
	g["crew_id"] = crew_id
	g["weapon_id"] = weapon_id
	return g


func _make_pilot(crew_id: String, ship_id: String) -> Dictionary:
	var p := TestFactories.make_crew_member(CrewData.Role.PILOT, 0.8, ship_id)
	p["crew_id"] = crew_id
	return p


func _fire_decision(crew_id: String, ship_id: String, subtype: String = "fire", target_id: String = "t1") -> Dictionary:
	return {
		"type": "fire",
		"subtype": subtype,
		"crew_id": crew_id,
		"entity_id": ship_id,
		"target_id": target_id,
		"skill_factor": 0.5,
		"delay": 0.0,
		"timestamp": 0.0,
	}


func _enemy_in_arc() -> Dictionary:
	return TestFactories.make_fighter("t1", Vector2(0, -300), 1)


# ---------------------------------------------------------------------------
# Compat default: missing fire_intent still fires
# ---------------------------------------------------------------------------

func test_weapon_without_fire_intent_fires_by_default() -> void:
	"""Regression: existing WeaponSystem tests with no fire_intent field still fire."""
	var ship := _make_ship_with_weapon()
	# No fire_intent set — should behave as before (fire when able)
	assert_false(ship.weapons[0].has("fire_intent"),
		"Precondition: fire_intent must be absent")
	var target := _enemy_in_arc()
	var result := WeaponSystem.update_weapons(ship, [target], 0.1)
	assert_gt(result.fire_commands.size(), 0,
		"Weapon with no fire_intent (missing) should fire — compat default")


# ---------------------------------------------------------------------------
# Explicit false holds fire
# ---------------------------------------------------------------------------

func test_weapon_with_fire_intent_false_does_not_fire() -> void:
	"""Explicit fire_intent=false must silence the weapon regardless of readiness."""
	var ship := _make_ship_with_weapon()
	ship.weapons[0]["fire_intent"] = false
	var target := _enemy_in_arc()
	var result := WeaponSystem.update_weapons(ship, [target], 0.1)
	assert_eq(result.fire_commands.size(), 0,
		"fire_intent=false must prevent firing")


func test_weapon_with_fire_intent_true_fires() -> void:
	"""Explicit fire_intent=true allows the weapon to fire normally."""
	var ship := _make_ship_with_weapon()
	ship.weapons[0]["fire_intent"] = true
	var target := _enemy_in_arc()
	var result := WeaponSystem.update_weapons(ship, [target], 0.1)
	assert_gt(result.fire_commands.size(), 0,
		"fire_intent=true should allow firing")


# ---------------------------------------------------------------------------
# Gunner HoldFire stamps false; engage stamps true
# ---------------------------------------------------------------------------

func test_hold_fire_decision_stamps_false_on_gunner_weapon() -> void:
	"""apply_fire_decision with hold_fire subtype sets fire_intent=false on the bound weapon."""
	var ship := _make_ship_with_weapon("w1")
	var gunner := _make_gunner("g1", ship.ship_id, "w1")
	var decision := _fire_decision("g1", ship.ship_id, "hold_fire", "")

	var result := CrewIntegrationSystem.apply_fire_decision(ship, decision, gunner)

	assert_eq(result.weapons[0].get("fire_intent"), false,
		"HoldFire decision must set fire_intent=false on bound weapon")


func test_engage_decision_stamps_true_on_gunner_weapon() -> void:
	"""apply_fire_decision with fire subtype sets fire_intent=true on the bound weapon."""
	var ship := _make_ship_with_weapon("w1")
	var gunner := _make_gunner("g1", ship.ship_id, "w1")
	var decision := _fire_decision("g1", ship.ship_id, "fire", "t1")

	var result := CrewIntegrationSystem.apply_fire_decision(ship, decision, gunner)

	assert_eq(result.weapons[0].get("fire_intent"), true,
		"Engage decision must set fire_intent=true on bound weapon")
	assert_eq(result.weapons[0].get("intent_target_id"), "t1",
		"intent_target_id must carry the designated target")


# ---------------------------------------------------------------------------
# Gunner HoldFire silences exactly that gunner's weapons
# ---------------------------------------------------------------------------

func test_hold_fire_silences_only_the_bound_weapon() -> void:
	"""A gunner's HoldFire silences exactly their weapon; the other gunner's weapon is unaffected."""
	var ship := TestFactories.make_armed_ship("light_cannon", 0.0)
	# Add a second weapon
	ship.weapons.append(TestFactories.make_weapon("light_cannon", "w2"))
	ship.weapons[0]["weapon_id"] = "w1"

	var g1 := _make_gunner("g1", ship.ship_id, "w1")
	var decision_hold := _fire_decision("g1", ship.ship_id, "hold_fire", "")

	var result := CrewIntegrationSystem.apply_fire_decision(ship, decision_hold, g1)

	assert_eq(result.weapons[0].get("fire_intent"), false,
		"g1's weapon (w1) must be silenced by HoldFire")
	assert_ne(result.weapons[1].get("fire_intent", true), false,
		"g2's weapon (w2) must not be affected by g1's HoldFire")


# ---------------------------------------------------------------------------
# Pepperbox: grouped gunner stamps both guns
# ---------------------------------------------------------------------------

func test_grouped_gunner_stamps_all_group_weapons() -> void:
	"""A gunner with weapon_ids group stamps intent on every weapon in the group."""
	var ship := TestFactories.make_armed_ship("light_cannon", 0.0)
	ship.weapons.append(TestFactories.make_weapon("light_cannon", "w2"))
	ship.weapons[0]["weapon_id"] = "w1"

	var gunner := TestFactories.make_crew_gunner(0.8, ship.ship_id)
	gunner["weapon_ids"] = ["w1", "w2"]
	gunner.erase("weapon_id")
	var decision := _fire_decision(gunner.crew_id, ship.ship_id, "fire", "t1")

	var result := CrewIntegrationSystem.apply_fire_decision(ship, decision, gunner)

	assert_eq(result.weapons[0].get("fire_intent"), true,
		"Grouped gunner should stamp w1 with engage intent")
	assert_eq(result.weapons[1].get("fire_intent"), true,
		"Grouped gunner should stamp w2 with engage intent")


func test_grouped_gunner_hold_fire_silences_both_guns() -> void:
	"""Killing/holding a pepperbox gunner silences both their guns."""
	var ship := TestFactories.make_armed_ship("light_cannon", 0.0)
	ship.weapons.append(TestFactories.make_weapon("light_cannon", "w2"))
	ship.weapons[0]["weapon_id"] = "w1"

	var gunner := TestFactories.make_crew_gunner(0.8, ship.ship_id)
	gunner["weapon_ids"] = ["w1", "w2"]
	gunner.erase("weapon_id")
	var decision := _fire_decision(gunner.crew_id, ship.ship_id, "hold_fire", "")

	var result := CrewIntegrationSystem.apply_fire_decision(ship, decision, gunner)

	assert_eq(result.weapons[0].get("fire_intent"), false,
		"Grouped hold_fire must silence w1")
	assert_eq(result.weapons[1].get("fire_intent"), false,
		"Grouped hold_fire must silence w2")


# ---------------------------------------------------------------------------
# Dead gunner silences their weapon; pilot still fires
# ---------------------------------------------------------------------------

func test_reconcile_silences_weapon_when_gunner_removed() -> void:
	"""After a gunner is removed from crew_list, reconcile_weapon_intents silences their weapon."""
	var ship := _make_ship_with_weapon("w1")
	# Embed crew in ship_data so reconcile knows w1 is a gunner weapon.
	var gunner := _make_gunner("g1", ship.ship_id, "w1")
	ship["crew"] = [gunner]

	# Stamp intent as engage (gunner was alive and firing).
	ship.weapons[0]["fire_intent"] = true
	ship.weapons[0]["intent_target_id"] = "t1"

	# Now the gunner is gone from the crew list.
	var crew_list: Array = []

	var result := CrewIntegrationSystem.reconcile_weapon_intents(ship, crew_list)

	assert_eq(result.weapons[0].get("fire_intent"), false,
		"Weapon should be silenced when its gunner is removed")


func test_reconcile_leaves_pilot_weapon_firing_when_pilot_alive() -> void:
	"""Solo fighter forward weapon stays active when the pilot is alive."""
	var ship := _make_ship_with_weapon("w1")
	var pilot := _make_pilot("p1", ship.ship_id)
	# No gunners — no crew embedded, so w1 is pilot-operated.
	ship["crew"] = [pilot]
	ship.weapons[0]["fire_intent"] = true
	ship.weapons[0]["intent_target_id"] = "t1"

	var crew_list: Array = [pilot]

	var result := CrewIntegrationSystem.reconcile_weapon_intents(ship, crew_list)

	assert_eq(result.weapons[0].get("fire_intent"), true,
		"Pilot-operated weapon must keep intent when pilot is alive")


func test_dead_gunner_weapon_goes_silent_other_gunner_keeps_firing() -> void:
	"""Killing one of two gunners silences only that gunner's weapon."""
	var ship := TestFactories.make_armed_ship("light_cannon", 0.0)
	ship.weapons.append(TestFactories.make_weapon("light_cannon", "w2"))
	ship.weapons[0]["weapon_id"] = "w1"
	ship.weapons[0]["fire_intent"] = true
	ship.weapons[0]["intent_target_id"] = "t1"
	ship.weapons[1]["fire_intent"] = true
	ship.weapons[1]["intent_target_id"] = "t1"

	var g1 := _make_gunner("g1", ship.ship_id, "w1")
	var g2 := _make_gunner("g2", ship.ship_id, "w2")
	ship["crew"] = [g1, g2]

	# g1 dies — only g2 survives.
	var crew_list: Array = [g2]

	var result := CrewIntegrationSystem.reconcile_weapon_intents(ship, crew_list)

	assert_eq(result.weapons[0].get("fire_intent"), false,
		"g1's weapon (w1) must be silenced after g1 removed")
	assert_eq(result.weapons[1].get("fire_intent"), true,
		"g2's weapon (w2) must keep intent — g2 is alive")


# ---------------------------------------------------------------------------
# Rate of fire: intent gates whether, cooldown gates how fast
# ---------------------------------------------------------------------------

func test_intent_does_not_affect_cooldown_on_fired_weapon() -> void:
	"""Firing a weapon resets its cooldown normally when intent=true."""
	var ship := _make_ship_with_weapon("w1")
	ship.weapons[0]["fire_intent"] = true
	var target := _enemy_in_arc()

	var result := WeaponSystem.update_weapons(ship, [target], 0.1)

	if result.fire_commands.size() > 0:
		assert_gt(result.ship_data.weapons[0].cooldown_remaining, 0.0,
			"Cooldown must be set after firing — rate of fire unchanged")


func test_intent_false_does_not_reset_cooldown() -> void:
	"""A held weapon does not fire, so its cooldown continues to count down normally."""
	var ship := _make_ship_with_weapon("w1", 0.5)
	ship.weapons[0]["fire_intent"] = false
	var target := _enemy_in_arc()

	var result := WeaponSystem.update_weapons(ship, [target], 0.2)

	assert_eq(result.fire_commands.size(), 0,
		"Held weapon must not fire")
	assert_almost_eq(result.ship_data.weapons[0].cooldown_remaining, 0.3, 0.01,
		"Cooldown still counts down while weapon is held")


# ---------------------------------------------------------------------------
# intent_target_id is preferred over default target selection
# ---------------------------------------------------------------------------

func test_intent_target_id_used_when_present() -> void:
	"""When intent_target_id matches a valid target, that target is used."""
	var ship := _make_ship_with_weapon("w1")
	ship.weapons[0]["fire_intent"] = true
	ship.weapons[0]["intent_target_id"] = "preferred_target"

	var preferred := _enemy_in_arc()
	preferred["ship_id"] = "preferred_target"
	preferred.position = Vector2(0, -200)

	var other := TestFactories.make_fighter("other_target", Vector2(0, -100), 1)

	var result := WeaponSystem.update_weapons(ship, [preferred, other], 0.1)

	if result.fire_commands.size() > 0:
		assert_eq(result.fire_commands[0].target_id, "preferred_target",
			"intent_target_id should override best-target selection")


# Pilot maneuver subtype never silences pilot-operated weapons

func _make_maneuver_decision(subtype: String, target_id: String = "") -> Dictionary:
	"""Build a minimal maneuver decision dict for apply_maneuver_decision tests."""
	return {
		"type": "maneuver",
		"subtype": subtype,
		"crew_id": "p1",
		"entity_id": "test_ship",
		"target_id": target_id,
	}


func test_evading_pilot_still_stamps_fire_intent_true() -> void:
	"""A live pilot on an evasion maneuver must not silence forward weapons."""
	var ship := _make_ship_with_weapon("w1")
	ship["crew"] = []  # Solo fighter — no gunners.
	var pilot := _make_pilot("p1", ship.ship_id)

	var decision := _make_maneuver_decision("evade", "t1")
	var result := CrewIntegrationSystem.apply_maneuver_decision(ship, decision, pilot)

	assert_ne(result.weapons[0].get("fire_intent", true), false,
		"Evading pilot must not set fire_intent=false on forward weapon")


func test_idle_pilot_still_stamps_fire_intent_true() -> void:
	"""A live pilot in idle maneuver must not silence forward weapons."""
	var ship := _make_ship_with_weapon("w1")
	ship["crew"] = []
	var pilot := _make_pilot("p1", ship.ship_id)

	var decision := _make_maneuver_decision("idle", "")
	var result := CrewIntegrationSystem.apply_maneuver_decision(ship, decision, pilot)

	assert_ne(result.weapons[0].get("fire_intent", true), false,
		"Idle pilot must not set fire_intent=false on forward weapon")


func test_flee_pilot_still_stamps_fire_intent_true() -> void:
	"""A live pilot fleeing must not silence forward weapons."""
	var ship := _make_ship_with_weapon("w1")
	ship["crew"] = []
	var pilot := _make_pilot("p1", ship.ship_id)

	var decision := _make_maneuver_decision("flee_to_boundary", "")
	var result := CrewIntegrationSystem.apply_maneuver_decision(ship, decision, pilot)

	assert_ne(result.weapons[0].get("fire_intent", true), false,
		"Fleeing pilot must not set fire_intent=false on forward weapon")


func test_dead_pilot_silences_pilot_operated_weapon_via_reconcile() -> void:
	"""A dead/removed pilot causes reconcile_weapon_intents to silence pilot-operated weapons."""
	var ship := _make_ship_with_weapon("w1")
	var pilot := _make_pilot("p1", ship.ship_id)
	ship["crew"] = [pilot]
	# Pilot was alive and firing.
	ship.weapons[0]["fire_intent"] = true
	ship.weapons[0]["intent_target_id"] = "t1"

	# Pilot removed from crew list (dead).
	var result := CrewIntegrationSystem.reconcile_weapon_intents(ship, [])

	assert_eq(result.weapons[0].get("fire_intent"), false,
		"Dead pilot must cause reconcile to silence pilot-operated weapon")


# ============================================================================
# BUG 1 regression: ship_data has NO crew key; crew lives in a separate list
# ============================================================================

## Build a ship with a gunner weapon AND a pilot weapon, with NO embedded crew.
## This mirrors the live runtime shape (create_ship_instance with create_crew=false).
func _make_ship_no_crew(pilot_wid: String, gunner_wid: String) -> Dictionary:
	"""Ship dict with two weapons and NO 'crew' key — the live runtime shape."""
	var ship := TestFactories.make_armed_ship("light_cannon", 0.0)
	ship.weapons[0]["weapon_id"] = pilot_wid
	ship.weapons.append(TestFactories.make_weapon("light_cannon", gunner_wid))
	ship.weapons[1]["weapon_id"] = gunner_wid
	# Deliberately do NOT set ship["crew"] — that key must be absent at runtime.
	ship.erase("crew")
	return ship


func test_bug1_pilot_maneuver_does_not_override_gunner_hold_fire() -> void:
	"""BUG 1 regression: when crew lives in a separate list (no ship.crew key), the
	pilot's maneuver decision must NOT stamp fire_intent on the gunner's weapon.
	Previously _build_gunner_claimed_ids read ship_data.crew=[] so the claimed set
	was always empty and the pilot stamped every weapon."""
	var ship := _make_ship_no_crew("pilot_w", "gunner_w")
	var pilot := _make_pilot("p1", ship.ship_id)
	var gunner := _make_gunner("g1", ship.ship_id, "gunner_w")

	# Gunner has previously stamped HoldFire on their weapon.
	ship.weapons[1]["fire_intent"] = false
	ship.weapons[1]["intent_target_id"] = ""

	# Live crew list contains both — the separate data source for crew.
	var crew_list: Array = [pilot, gunner]

	# Pilot makes a maneuver decision; we thread crew_list through.
	var decision := _make_maneuver_decision("evade", "t1")
	var result := CrewIntegrationSystem.apply_maneuver_decision(ship, decision, pilot, crew_list)

	assert_eq(result.weapons[1].get("fire_intent"), false,
		"Pilot maneuver must NOT override gunner's HoldFire on the gunner's weapon")
	assert_ne(result.weapons[0].get("fire_intent", true), false,
		"Pilot's own forward weapon must remain enabled by the maneuver stamp")


func test_bug1_reconcile_silences_dead_gunner_weapon_live_crew_list() -> void:
	"""BUG 1 regression: reconcile_weapon_intents must detect a dead gunner and
	silence their weapon when crew lives in crew_list (no ship.crew key).
	The reconcile reads _gunner_weapon_ids stamped by prior gunner fire decisions."""
	var ship := _make_ship_no_crew("pilot_w", "gunner_w")
	var pilot := _make_pilot("p1", ship.ship_id)
	var gunner := _make_gunner("g1", ship.ship_id, "gunner_w")
	var full_crew: Array = [pilot, gunner]

	# Simulate the gunner having stamped engage (which persists _gunner_weapon_ids).
	var fire_dec := _fire_decision("g1", ship.ship_id, "fire", "t1")
	ship = CrewIntegrationSystem.apply_fire_decision(ship, fire_dec, gunner, full_crew)
	# Pilot weapon was also firing.
	ship.weapons[0]["fire_intent"] = true
	ship.weapons[0]["intent_target_id"] = "t1"

	# Gunner dies — removed from live crew_list; pilot survives.
	var live_crew: Array = [pilot]

	var result := CrewIntegrationSystem.reconcile_weapon_intents(ship, live_crew)

	assert_eq(result.weapons[1].get("fire_intent"), false,
		"Dead gunner's weapon must be silenced by reconcile")
	assert_eq(result.weapons[0].get("fire_intent"), true,
		"Pilot's weapon must keep firing while pilot is alive")


func test_bug1_pilot_weapon_still_fires_on_solo_ship_no_crew_key() -> void:
	"""On a solo fighter with no crew key, the pilot's forward weapon must be stamped
	as engaging (all weapons are pilot-operated, no gunners in crew_list)."""
	var ship := _make_ship_with_weapon("fw1")
	ship.erase("crew")  # No embedded crew — live runtime shape.
	var pilot := _make_pilot("p1", ship.ship_id)
	var crew_list: Array = [pilot]

	var decision := _make_maneuver_decision("fight_attack", "t1")
	var result := CrewIntegrationSystem.apply_maneuver_decision(ship, decision, pilot, crew_list)

	assert_ne(result.weapons[0].get("fire_intent", true), false,
		"Solo fighter forward weapon must be stamped engage when no gunners in crew_list")
