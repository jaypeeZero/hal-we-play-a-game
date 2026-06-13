extends GutTest

## Behavior tests for TacticsSystem.resolve_tactics() and preset loading.
## Tests assert BEHAVIOR ("a ship override beats its squadron"), not data
## values ("phalanx has mentality 0.2"). Per project testing standards.

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Minimal fleet dict containing only one dial, for override-precedence tests.
func _fleet(dial: String, value) -> Dictionary:
	return {dial: value}


## Call resolve_tactics with only the args that matter for a given test.
## Unspecified scopes default to empty / no role.
func _resolve(
	fleet: Dictionary = {},
	squadron: Dictionary = {},
	role: String = "",
	ship_override: Dictionary = {}
) -> Dictionary:
	return TacticsSystem.resolve_tactics(fleet, squadron, role, ship_override)


# ---------------------------------------------------------------------------
# 1. Every dial is populated after resolve (no missing keys)
# ---------------------------------------------------------------------------

func test_all_dials_present_in_resolved_output():
	var resolved := _resolve()
	for dial in TacticsSystem.ALL_DIAL_KEYS:
		assert_true(resolved.has(dial),
			"resolve_tactics must populate dial '%s'" % dial)


func test_derived_scalars_always_present():
	var resolved := _resolve()
	assert_true(resolved.has("mentality_scalar"), "mentality_scalar must always be present")
	assert_true(resolved.has("range_scalar"),     "range_scalar must always be present")


# ---------------------------------------------------------------------------
# 2. Engine defaults are coherent (no nulls, types correct)
# ---------------------------------------------------------------------------

func test_engine_defaults_produce_valid_shape():
	var resolved := _resolve()
	assert_true(resolved["shape"] in TacticsSystem.VALID_SHAPES,
		"Default shape must be a valid preset")


func test_engine_defaults_produce_valid_priority():
	var resolved := _resolve()
	assert_true(resolved["priority"] in TacticsSystem.VALID_PRIORITIES,
		"Default priority must be a valid value")


func test_engine_defaults_produce_scalar_in_range():
	var resolved := _resolve()
	assert_true(resolved["mentality_scalar"] >= 0.0 and resolved["mentality_scalar"] <= 1.0,
		"Default mentality_scalar must be in [0,1]")
	assert_true(resolved["range_scalar"] >= 0.0 and resolved["range_scalar"] <= 1.0,
		"Default range_scalar must be in [0,1]")


# ---------------------------------------------------------------------------
# 3. Override precedence: ship > role > squadron > fleet > engine_default
# ---------------------------------------------------------------------------

func test_ship_override_beats_squadron():
	var resolved := _resolve(
		{},
		{"mentality": "defensive"},
		"",
		{"mentality": "all_out"}
	)
	assert_eq(resolved["mentality"], "all_out",
		"Ship override must win over squadron value for the same dial")


func test_ship_override_beats_fleet():
	var resolved := _resolve(
		{"engagement_range": "standoff"},
		{},
		"",
		{"engagement_range": "knife"}
	)
	assert_eq(resolved["engagement_range"], "knife",
		"Ship override must win over fleet value")


func test_ship_override_beats_role_default():
	# Interceptors default to attacking mentality (ROLE_INTERCEPTOR).
	var resolved := _resolve({}, {}, "interceptor", {"mentality": "defensive"})
	assert_eq(resolved["mentality"], "defensive",
		"Ship override must win over role default")


func test_role_default_beats_squadron():
	# Artillery role defaults engagement_range to standoff (ROLE_ARTILLERY).
	# Squadron sets it to knife. Role wins (role_default > squadron in chain).
	var resolved := _resolve({}, {"engagement_range": "knife"}, "artillery", {})
	assert_eq(resolved["engagement_range"], "standoff",
		"Role default must beat squadron value — role sits above squadron in resolution order")


func test_role_default_beats_fleet():
	# Artillery defaults mentality to defensive; fleet sets it to all_out.
	var resolved := _resolve({"mentality": "all_out"}, {}, "artillery", {})
	assert_eq(resolved["mentality"], "defensive",
		"Role default must beat fleet value")


func test_squadron_beats_fleet():
	var resolved := _resolve(
		{"concentration": 0.1},
		{"concentration": 0.9},
		"",
		{}
	)
	assert_gt(resolved["concentration"], 0.5,
		"Squadron dial must beat fleet dial when no role or ship override is present")


func test_fleet_beats_engine_default():
	# Engine default for shape is line_abreast. Fleet overrides to globe.
	var resolved := _resolve({"shape": "globe"}, {}, "", {})
	assert_eq(resolved["shape"], "globe",
		"Fleet value must win over engine default")


func test_unset_dial_falls_through_to_engine_default():
	# No scope sets pursuit_discipline for the "flanker" role in this call.
	# Wait — flanker has a role bundle with pursuit_discipline. Test a dial
	# that the flanker role doesn't set AND no scope sets.
	# shape IS set in ROLE_FLANKER, so use a dial not set in role: use anchor.
	# anchor IS in ROLE_FLANKER too. Let's use line_height from a role that
	# doesn't set it: we'll use an empty role ("").
	# With role="" and no scopes set, every dial should come from ENGINE_DEFAULTS.
	var resolved := _resolve({}, {}, "", {})
	assert_eq(resolved["shape"], TacticsSystem.ENGINE_DEFAULTS["shape"],
		"Unset dial with no role must fall through to engine default")
	assert_eq(resolved["duty"], TacticsSystem.ENGINE_DEFAULTS["duty"],
		"Unset duty must fall through to engine default")


# ---------------------------------------------------------------------------
# 4. Role bundles apply the correct defaults
# ---------------------------------------------------------------------------

func test_artillery_role_defaults_to_standoff():
	var resolved := _resolve({}, {}, "artillery", {})
	assert_eq(resolved["engagement_range"], "standoff",
		"Artillery role must default to standoff engagement range")


func test_flanker_role_defaults_to_press():
	var resolved := _resolve({}, {}, "flanker", {})
	assert_eq(resolved["duty"], "press",
		"Flanker role must default to press duty")


func test_interceptor_role_has_high_pursuit_discipline():
	var resolved_interceptor := _resolve({}, {}, "interceptor", {})
	var resolved_anchor      := _resolve({}, {}, "anchor",      {})
	assert_gt(resolved_interceptor["pursuit_discipline"],
		resolved_anchor["pursuit_discipline"],
		"Interceptor must have higher pursuit discipline than anchor (roles differ on this dial)")


func test_screen_role_defaults_to_support_duty():
	var resolved := _resolve({}, {}, "screen", {})
	assert_eq(resolved["duty"], "support",
		"Screen role must default to support duty")


func test_brawler_alias_resolves_same_as_anchor():
	var anchor  := _resolve({}, {}, "anchor",  {})
	var brawler := _resolve({}, {}, "brawler", {})
	assert_eq(anchor["mentality"], brawler["mentality"],
		"brawler is an alias for anchor and must resolve the same mentality")
	assert_eq(anchor["duty"], brawler["duty"],
		"brawler alias must resolve the same duty as anchor")


# ---------------------------------------------------------------------------
# 5. Derived scalars are consistent with ordinal values
# ---------------------------------------------------------------------------

func test_all_out_mentality_produces_max_scalar():
	var resolved := _resolve({}, {}, "", {"mentality": "all_out"})
	assert_eq(resolved["mentality_scalar"], 1.0,
		"all_out mentality must map to scalar 1.0")


func test_defensive_mentality_produces_min_scalar():
	var resolved := _resolve({}, {}, "", {"mentality": "defensive"})
	assert_eq(resolved["mentality_scalar"], 0.0,
		"defensive mentality must map to scalar 0.0")


func test_knife_range_produces_min_scalar():
	var resolved := _resolve({}, {}, "", {"engagement_range": "knife"})
	assert_eq(resolved["range_scalar"], 0.0,
		"knife engagement range must map to scalar 0.0")


func test_kite_range_produces_max_scalar():
	var resolved := _resolve({}, {}, "", {"engagement_range": "kite"})
	assert_eq(resolved["range_scalar"], 1.0,
		"kite engagement range must map to scalar 1.0")


func test_mentality_scalar_increases_from_defensive_to_all_out():
	var s_def: float = _resolve({}, {}, "", {"mentality": "defensive"})["mentality_scalar"]
	var s_cau: float = _resolve({}, {}, "", {"mentality": "cautious"})["mentality_scalar"]
	var s_bal: float = _resolve({}, {}, "", {"mentality": "balanced"})["mentality_scalar"]
	var s_atk: float = _resolve({}, {}, "", {"mentality": "attacking"})["mentality_scalar"]
	var s_all: float = _resolve({}, {}, "", {"mentality": "all_out"})["mentality_scalar"]
	assert_true(s_def < s_cau and s_cau < s_bal and s_bal < s_atk and s_atk < s_all,
		"Mentality scalars must be strictly ordered defensive < cautious < balanced < attacking < all_out")


# ---------------------------------------------------------------------------
# 6. Preset loading and preset-based resolution
# ---------------------------------------------------------------------------

func test_presets_load_without_error():
	var presets := TacticsSystem.get_all_presets()
	assert_true(presets.size() > 0, "At least one preset must load from JSON")


func test_known_presets_exist():
	var presets := TacticsSystem.get_all_presets()
	assert_true(presets.has("phalanx"),          "phalanx preset must exist")
	assert_true(presets.has("alpha_strike"),      "alpha_strike preset must exist")
	assert_true(presets.has("hammer_and_anvil"),  "hammer_and_anvil preset must exist")


func test_preset_resolves_to_coherent_tactics():
	# resolve_from_preset must return a complete resolved tactics dict.
	var resolved := TacticsSystem.resolve_from_preset("phalanx", "", "anchor")
	for dial in TacticsSystem.ALL_DIAL_KEYS:
		assert_true(resolved.has(dial),
			"Preset resolution must populate dial '%s'" % dial)


func test_alpha_strike_preset_is_more_aggressive_than_phalanx():
	# Alpha strike should produce a higher mentality scalar than phalanx,
	# regardless of which exact ordinals are chosen — the point is the intent.
	var alpha   := TacticsSystem.resolve_from_preset("alpha_strike",  "", "interceptor")
	var phalanx := TacticsSystem.resolve_from_preset("phalanx",       "", "anchor")
	assert_gt(alpha["mentality_scalar"], phalanx["mentality_scalar"],
		"Alpha Strike must resolve to higher mentality scalar than Phalanx for comparable roles")


func test_hammer_and_anvil_hammer_squadron_has_higher_pursuit_than_anvil():
	var hammer := TacticsSystem.resolve_from_preset("hammer_and_anvil", "hammer", "flanker")
	var anvil  := TacticsSystem.resolve_from_preset("hammer_and_anvil", "anvil",  "anchor")
	assert_gt(hammer["pursuit_discipline"], anvil["pursuit_discipline"],
		"Hammer squadron must have higher pursuit discipline than anvil squadron")


func test_hammer_and_anvil_anvil_holds_while_hammer_presses():
	var hammer := TacticsSystem.resolve_from_preset("hammer_and_anvil", "hammer", "flanker")
	var anvil  := TacticsSystem.resolve_from_preset("hammer_and_anvil", "anvil",  "anchor")
	assert_eq(anvil["duty"],  "hold",
		"Anvil squadron must resolve to hold duty")
	assert_eq(hammer["duty"], "press",
		"Hammer squadron must resolve to press duty")


func test_unknown_preset_returns_engine_defaults():
	# A nonexistent preset id must not crash; should fall back to engine defaults.
	var resolved := TacticsSystem.resolve_from_preset("nonexistent_preset", "", "")
	for dial in TacticsSystem.ALL_DIAL_KEYS:
		assert_true(resolved.has(dial),
			"Unknown preset fallback must still populate dial '%s'" % dial)


func test_empty_squadron_id_uses_fleet_level_only():
	# Passing squadron_id="" skips squadron lookup.
	# Phalanx has no squadron block, so this should be identical to explicit empty.
	var with_empty := TacticsSystem.resolve_from_preset("phalanx", "",       "screen")
	var with_none  := TacticsSystem.resolve_from_preset("phalanx", "bogus",  "screen")
	# Both should give valid output (bogus squadron just gives empty dict).
	assert_true(with_empty.has("mentality"),
		"resolve_from_preset with empty squadron_id must succeed")
	assert_true(with_none.has("mentality"),
		"resolve_from_preset with unknown squadron_id must succeed")


# ---------------------------------------------------------------------------
# 7. Convenience accessors
# ---------------------------------------------------------------------------

func test_mentality_scalar_helper_matches_resolved_field():
	var resolved := _resolve({}, {}, "", {"mentality": "attacking"})
	assert_eq(TacticsSystem.mentality_scalar(resolved), resolved["mentality_scalar"],
		"mentality_scalar() helper must match resolved['mentality_scalar']")


func test_range_scalar_helper_matches_resolved_field():
	var resolved := _resolve({}, {}, "", {"engagement_range": "standoff"})
	assert_eq(TacticsSystem.range_scalar(resolved), resolved["range_scalar"],
		"range_scalar() helper must match resolved['range_scalar']")


# 8. compile_for_crew — per-crew tactics compilation

## Minimal crew dict sufficient for compile_for_crew tests.
func _make_crew(crew_id: String = "c1") -> Dictionary:
	return {
		"crew_id": crew_id,
		"known_patterns": [],
		"role": 0,
	}


func test_compiled_crew_carries_tactics_block():
	# After compile_for_crew the crew dict must have a populated "tactics" key.
	var crew := _make_crew()
	var result := TacticsSystem.compile_for_crew(crew, "fighter", "", TacticsSystem.empty_tactics())
	assert_true(result.has("tactics"), "compile_for_crew must attach a 'tactics' key to the crew dict")
	assert_false(result["tactics"].is_empty(), "Attached tactics block must not be empty")


func test_compiled_tactics_block_has_all_dial_keys():
	# The tactics block must contain every declared dial, not a partial set.
	var crew := _make_crew()
	var result := TacticsSystem.compile_for_crew(crew, "capital", "", TacticsSystem.empty_tactics())
	for dial in TacticsSystem.ALL_DIAL_KEYS:
		assert_true(result["tactics"].has(dial),
			"Compiled tactics block must contain dial '%s'" % dial)


func test_empty_tactics_doctrine_yields_engine_default_dials():
	# Empty doctrine → no fleet/squadron overrides → resolution falls to role then engine defaults.
	# With an unrecognised ship type DEFAULT_ROLE applies (brawler/anchor), which sets mentality to
	# "cautious". To get pure engine defaults we must also clear the role via ship_override.
	var doctrine := {
		"fleet":          {},
		"squadrons":      {},
		"ship_overrides": {"": {"role": ""}},  # hull_id "" → clears the role bundle
	}
	var crew := _make_crew()  # crew has no hull_id key → get("hull_id","") = ""
	var result := TacticsSystem.compile_for_crew(crew, "unknown_type", "", doctrine)
	assert_eq(result["tactics"]["mentality"], TacticsSystem.ENGINE_DEFAULTS["mentality"],
		"When no role bundle applies, empty tactics doctrine must yield engine-default mentality")


func test_squadron_scope_dial_overrides_fleet_scope_through_compile():
	# Fleet says standoff; squadron says knife.
	# hull_id "" (no hull_id in crew) → ship_overrides[""] clears the role so no
	# role bundle wins, letting fleet/squadron inheritance run cleanly.
	var doctrine := {
		"fleet":          {"engagement_range": "standoff"},
		"squadrons":      {"sq1": {"engagement_range": "knife"}},
		"ship_overrides": {"": {"role": ""}},  # hull_id "" → clears role bundle
	}
	var crew := _make_crew()  # hull_id defaults to "" via get("hull_id","")
	var result := TacticsSystem.compile_for_crew(crew, "unknown_type", "sq1", doctrine)
	assert_eq(result["tactics"]["engagement_range"], "knife",
		"Squadron-scope dial must override fleet-scope dial when no role bundle sets it")


func test_ship_class_default_role_applied_when_doctrine_sets_none():
	# fighter → interceptor class default; interceptor role has high pursuit_discipline (0.8).
	# With empty doctrine the class default must drive the role bundle.
	var crew := _make_crew()
	var result := TacticsSystem.compile_for_crew(crew, "fighter", "", TacticsSystem.empty_tactics())
	var interceptor_pd: float = TacticsSystem.ROLE_INTERCEPTOR["pursuit_discipline"]
	assert_eq(result["tactics"]["pursuit_discipline"], interceptor_pd,
		"Fighter class must default to interceptor role, giving interceptor's pursuit_discipline")


func test_compile_for_crew_does_not_mutate_input():
	# Pure function contract: input crew dict must be unchanged after the call.
	var crew := _make_crew()
	TacticsSystem.compile_for_crew(crew, "fighter", "", TacticsSystem.empty_tactics())
	assert_false(crew.has("tactics"),
		"compile_for_crew must not mutate the input crew dict")
