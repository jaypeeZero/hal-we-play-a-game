extends GutTest
## Tests for DispatchesPanel — pure data helpers and feed-state behaviour.
## Widget-level tests are limited to what instantiates cleanly under GUT headless.


# ---- helpers for building effect and event fixtures ----

func _ship_modifier_effect(field: String, value: float, duration := "battles:2") -> Dictionary:
	return {"kind": "ship_modifier", "field": field, "value": value, "duration": duration}


func _crew_skill_effect(skill: String, value: float, duration := "battles:1") -> Dictionary:
	return {"kind": "crew_skill", "skill": skill, "value": value, "duration": duration}


func _ship_repair_effect(section: String, value: int) -> Dictionary:
	return {"kind": "ship_repair", "section": section, "value": value}


func _ship_damage_effect(section: String, value: int) -> Dictionary:
	return {"kind": "ship_damage", "section": section, "value": value}


func _money_effect(value: int) -> Dictionary:
	return {"kind": "money", "value": value}


func _intel_effect(scope: String, value: float, duration := "battles:1") -> Dictionary:
	return {"kind": "intel", "scope": scope, "value": value, "duration": duration}


func _make_event(polarity := "neutral", effects := [], seen := false) -> Dictionary:
	return {
		"id": "evt_test",
		"star_date": 2314,
		"category": "crew",
		"headline": "Something happened.",
		"body": "More details here.",
		"target": {"kind": "none"},
		"polarity": polarity,
		"effects": effects,
		"seen": seen,
	}


# ---- summarize_effect: sign and text shape ----

func test_negative_ship_modifier_contains_minus_sign():
	var effect := _ship_modifier_effect("pilot_accel_factor", -0.12, "battles:1")
	var result := DispatchesPanel.summarize_effect(effect)
	assert_true(result.text.contains("−") or result.text.contains("-"),
		"Negative ship_modifier text has a minus sign")


func test_positive_ship_modifier_contains_plus_sign():
	var effect := _ship_modifier_effect("pilot_accel_factor", 0.15, "battles:1")
	var result := DispatchesPanel.summarize_effect(effect)
	assert_true(result.text.contains("+"),
		"Positive ship_modifier text has a plus sign")


func test_ship_modifier_contains_duration():
	var effect := _ship_modifier_effect("pilot_accel_factor", -0.12, "battles:1")
	var result := DispatchesPanel.summarize_effect(effect)
	assert_true(result.text.contains("battle"),
		"ship_modifier with battles:1 duration mentions 'battle' in text")


func test_ship_modifier_polarity_negative_when_value_negative():
	var effect := _ship_modifier_effect("pilot_accel_factor", -0.05, "battles:2")
	var result := DispatchesPanel.summarize_effect(effect)
	assert_eq(result.polarity, "negative",
		"Negative ship_modifier yields negative polarity")


func test_ship_modifier_polarity_positive_when_value_positive():
	var effect := _ship_modifier_effect("pilot_turn_factor", 0.10, "permanent")
	var result := DispatchesPanel.summarize_effect(effect)
	assert_eq(result.polarity, "positive",
		"Positive ship_modifier yields positive polarity")


func test_ship_modifier_permanent_has_no_duration_text():
	var effect := _ship_modifier_effect("pilot_accel_factor", 0.10, "permanent")
	var result := DispatchesPanel.summarize_effect(effect)
	assert_false(result.text.contains("battle"),
		"Permanent ship_modifier does not mention 'battle' in text")


func test_crew_skill_negative_contains_minus():
	var effect := _crew_skill_effect("composure", -0.05, "battles:2")
	var result := DispatchesPanel.summarize_effect(effect)
	assert_true(result.text.contains("−") or result.text.contains("-"),
		"Negative crew_skill text has a minus sign")


func test_crew_skill_contains_duration():
	var effect := _crew_skill_effect("composure", -0.03, "battles:2")
	var result := DispatchesPanel.summarize_effect(effect)
	assert_true(result.text.contains("battle"),
		"crew_skill with battles:2 duration mentions 'battle'")


func test_ship_repair_polarity_is_positive():
	var effect := _ship_repair_effect("body", 15)
	var result := DispatchesPanel.summarize_effect(effect)
	assert_eq(result.polarity, "positive", "ship_repair is always positive")


func test_ship_repair_text_contains_plus():
	var effect := _ship_repair_effect("body", 15)
	var result := DispatchesPanel.summarize_effect(effect)
	assert_true(result.text.contains("+"), "ship_repair text contains a plus sign")


func test_ship_damage_polarity_is_negative():
	var effect := _ship_damage_effect("nose", 8)
	var result := DispatchesPanel.summarize_effect(effect)
	assert_eq(result.polarity, "negative", "ship_damage is always negative")


func test_ship_damage_text_contains_minus():
	var effect := _ship_damage_effect("nose", 8)
	var result := DispatchesPanel.summarize_effect(effect)
	assert_true(result.text.contains("−") or result.text.contains("-"),
		"ship_damage text contains a minus sign")


func test_money_negative_contains_minus_and_credit_symbol():
	var effect := _money_effect(-200)
	var result := DispatchesPanel.summarize_effect(effect)
	assert_true(result.text.contains("−") or result.text.contains("-"),
		"Negative money text has a minus sign")
	assert_true(result.text.contains("₵"), "Money text contains credit symbol")
	assert_eq(result.polarity, "negative", "Negative money yields negative polarity")


func test_money_positive_contains_plus_and_credit_symbol():
	var effect := _money_effect(500)
	var result := DispatchesPanel.summarize_effect(effect)
	assert_true(result.text.contains("+"), "Positive money text has a plus sign")
	assert_true(result.text.contains("₵"), "Money text contains credit symbol")
	assert_eq(result.polarity, "positive", "Positive money yields positive polarity")


func test_intel_effect_contains_duration():
	var effect := _intel_effect("next_battle_reward", 0.25, "battles:1")
	var result := DispatchesPanel.summarize_effect(effect)
	assert_true(result.text.contains("battle"),
		"intel with battles:1 duration mentions 'battle'")


func test_intel_positive_polarity():
	var effect := _intel_effect("next_battle_reward", 0.25, "battles:1")
	var result := DispatchesPanel.summarize_effect(effect)
	assert_eq(result.polarity, "positive", "Positive intel yields positive polarity")


func test_add_attribute_text_contains_trait_label():
	# This effect requires an attribute id — use a known one or an unknown one
	# (both paths must produce a non-empty text without crashing).
	var effect := {"kind": "add_attribute", "attribute": "unknown_attr_for_test"}
	var result := DispatchesPanel.summarize_effect(effect)
	assert_true(result.text.contains("Trait"),
		"add_attribute text contains 'Trait' label")
	assert_true(result.text.contains("+"), "add_attribute text contains '+'")


func test_remove_attribute_text_contains_trait_label():
	var effect := {"kind": "remove_attribute", "attribute": "unknown_attr_for_test"}
	var result := DispatchesPanel.summarize_effect(effect)
	assert_true(result.text.contains("Trait"),
		"remove_attribute text contains 'Trait' label")
	assert_true(result.text.contains("−") or result.text.contains("-"),
		"remove_attribute text contains a minus sign")


func test_unknown_kind_returns_empty_text():
	var effect := {"kind": "totally_unknown_kind", "value": 1}
	var result := DispatchesPanel.summarize_effect(effect)
	assert_eq(result.text, "", "Unknown effect kind returns empty text")


# ---- summarize_effects array helper ----

func test_summarize_effects_returns_one_entry_per_non_empty_effect():
	var effects := [
		_money_effect(-200),
		_ship_repair_effect("body", 10),
	]
	var results := DispatchesPanel.summarize_effects(effects)
	assert_eq(results.size(), 2, "Two non-empty effects produce two summaries")


func test_summarize_effects_skips_unknown_kind():
	var effects := [
		{"kind": "totally_unknown", "value": 1},
		_money_effect(100),
	]
	var results := DispatchesPanel.summarize_effects(effects)
	assert_eq(results.size(), 1, "Unknown-kind effects are omitted from summaries")


# ---- duration label ----

func test_duration_label_battles_1_is_singular():
	var result := DispatchesPanel._duration_label("battles:1")
	assert_true(result.contains("1"), "1-battle duration label contains '1'")
	# Should be singular "battle" not "battles"
	assert_false(result.ends_with("battles"), "1-battle label is singular")


func test_duration_label_battles_plural():
	var result := DispatchesPanel._duration_label("battles:3")
	assert_true(result.contains("3"), "3-battle duration label contains '3'")
	assert_true(result.contains("battles"), "3-battle label uses plural")


func test_duration_label_permanent_returns_empty():
	var result := DispatchesPanel._duration_label("permanent")
	assert_eq(result, "", "Permanent duration returns empty label")


# ---- count_unseen ----

func test_count_unseen_all_unseen():
	var feed := [
		_make_event("positive", [], false),
		_make_event("negative", [], false),
	]
	assert_eq(DispatchesPanel.count_unseen(feed), 2, "All unseen entries counted")


func test_count_unseen_mixed():
	var feed := [
		_make_event("positive", [], true),   # seen
		_make_event("negative", [], false),  # unseen
		_make_event("neutral", [], false),   # unseen
	]
	assert_eq(DispatchesPanel.count_unseen(feed), 2, "Only unseen entries counted")


func test_count_unseen_all_seen_is_zero():
	var feed := [
		_make_event("positive", [], true),
		_make_event("negative", [], true),
	]
	assert_eq(DispatchesPanel.count_unseen(feed), 0, "All seen yields zero unseen")


func test_count_unseen_empty_feed_is_zero():
	assert_eq(DispatchesPanel.count_unseen([]), 0, "Empty feed yields zero unseen")


# ---- mark_all_seen ----

func test_mark_all_seen_flips_all_entries():
	var panel := DispatchesPanel.new()
	add_child_autofree(panel)
	var feed := [
		_make_event("positive", [], false),
		_make_event("negative", [], false),
	]
	panel.mark_all_seen(feed)
	for entry in feed:
		assert_true(entry.get("seen", false), "mark_all_seen sets seen=true on each entry")


func test_mark_all_seen_unseen_count_becomes_zero():
	var panel := DispatchesPanel.new()
	add_child_autofree(panel)
	var feed := [
		_make_event("positive", [], false),
		_make_event("negative", [], false),
	]
	panel.mark_all_seen(feed)
	assert_eq(panel._unseen_count, 0, "Unseen count is zero after mark_all_seen")


# ---- panel widget behaviour (headless-safe) ----

func test_refresh_empty_feed_does_not_crash():
	var panel := DispatchesPanel.new()
	add_child_autofree(panel)
	panel.refresh([])
	# No assertion needed beyond not crashing; verify via row count.
	assert_eq(panel._rows_box.get_child_count(), 1,
		"Empty feed renders exactly one child (the empty-state label)")


func test_refresh_single_event_adds_rows():
	var panel := DispatchesPanel.new()
	add_child_autofree(panel)
	var feed := [_make_event("positive", [_money_effect(100)], false)]
	panel.refresh(feed)
	# Expect at least one section header + one row card.
	assert_true(panel._rows_box.get_child_count() >= 2,
		"Single-event feed renders section header and at least one row")


func test_refresh_updates_unseen_badge_visibility():
	var panel := DispatchesPanel.new()
	add_child_autofree(panel)
	var feed := [_make_event("positive", [], false)]
	panel.refresh(feed)
	assert_true(panel._badge_label.visible,
		"Unseen badge is visible when feed has unseen entries")


func test_refresh_hides_badge_when_all_seen():
	var panel := DispatchesPanel.new()
	add_child_autofree(panel)
	var feed := [_make_event("positive", [], true)]
	panel.refresh(feed)
	assert_false(panel._badge_label.visible,
		"Unseen badge is hidden when all entries are seen")
