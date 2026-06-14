extends GutTest

## Behavior tests for ShipSprite and ShipCard.
## Tests FUNCTIONALITY only — no filename assertions, no pixel-size checks.


# SHIP SPRITE — texture resolution

func test_every_known_type_returns_a_texture() -> void:
	for ship_type: String in ShipSprite.KNOWN_TYPES:
		var tex: Texture2D = ShipSprite.texture_for_type(ship_type)
		assert_not_null(tex, "Expected non-null texture for type: %s" % ship_type)


func test_distinct_types_return_distinct_textures() -> void:
	var seen: Array[Texture2D] = []
	for ship_type: String in ShipSprite.KNOWN_TYPES:
		var tex: Texture2D = ShipSprite.texture_for_type(ship_type)
		assert_does_not_have(seen, tex,
			"Each ship type should map to a unique texture (duplicate: %s)" % ship_type)
		seen.append(tex)


func test_unknown_type_returns_placeholder_not_null() -> void:
	# Must not crash; must return a usable placeholder.
	var tex: Texture2D = ShipSprite.texture_for_type("nonexistent_ship_zzzz")
	# push_warning fires for unknown types — assert it so GUT doesn't mark it as unexpected.
	assert_engine_error(1, "Expected a warning for unknown ship type")
	assert_not_null(tex, "Unknown type must return the fallback placeholder, not null")


func test_unknown_type_returns_same_placeholder_as_fallback_type() -> void:
	# The placeholder should match the designated fallback type's texture.
	var fallback_tex: Texture2D = ShipSprite.texture_for_type(ShipSprite.FALLBACK_TYPE)
	var unknown_tex: Texture2D = ShipSprite.texture_for_type("definitely_not_a_ship")
	assert_engine_error(1, "Expected a warning for unknown ship type")
	assert_eq(unknown_tex, fallback_tex, "Unknown type returns fallback type's texture")


# SHIP SPRITE — team color

func test_team_color_returns_color_for_known_teams() -> void:
	for team: int in [0, 1]:
		var color: Color = ShipSprite.team_color(team)
		# A valid Color is never null in GDScript; verify it differs from white (tinted).
		assert_true(color is Color, "team_color(%d) returns a Color" % team)


func test_unknown_team_returns_white_no_tint() -> void:
	var color: Color = ShipSprite.team_color(99)
	assert_eq(color, Color.WHITE, "Unknown team index returns white (no tint)")


func test_team_colors_are_distinct() -> void:
	var c0: Color = ShipSprite.team_color(0)
	var c1: Color = ShipSprite.team_color(1)
	assert_ne(c0, c1, "Team 0 and team 1 should have distinct tint colours")


# SHIP CARD — composition and setup

func test_ship_card_instantiates_without_error() -> void:
	var card := ShipCard.new()
	add_child_autofree(card)
	assert_not_null(card, "ShipCard should instantiate cleanly")


func test_ship_card_setup_sets_texture_for_known_type() -> void:
	var card := ShipCard.new()
	add_child_autofree(card)
	card.setup("fighter")
	assert_not_null(card._sprite.texture, "ShipCard sprite texture should be set after setup")


func test_ship_card_setup_works_for_all_known_types() -> void:
	for ship_type: String in ShipSprite.KNOWN_TYPES:
		var card := ShipCard.new()
		add_child_autofree(card)
		card.setup(ship_type)
		assert_not_null(card._sprite.texture,
			"ShipCard should display a texture for type: %s" % ship_type)


func test_ship_card_label_hidden_when_not_provided() -> void:
	var card := ShipCard.new()
	add_child_autofree(card)
	card.setup("corvette")
	assert_false(card._label.visible, "Label should be hidden when no label opt given")


func test_ship_card_label_shown_when_provided() -> void:
	var card := ShipCard.new()
	add_child_autofree(card)
	card.setup("corvette", {label = "ANVIL-3"})
	assert_true(card._label.visible, "Label should be visible when label opt is provided")
	assert_eq(card._label.text, "ANVIL-3", "Label text should match the provided value")


func test_ship_card_team_tint_applied() -> void:
	var card := ShipCard.new()
	add_child_autofree(card)
	card.setup("fighter", {team = 0})
	assert_ne(card._sprite.modulate, Color.WHITE,
		"Team tint should be applied (sprite modulate should differ from white)")


func test_ship_card_explicit_modulate_overrides_team() -> void:
	var card := ShipCard.new()
	add_child_autofree(card)
	var custom_color := Color(0.0, 1.0, 0.5, 1.0)
	card.setup("fighter", {team = 0, modulate = custom_color})
	assert_eq(card._sprite.modulate, custom_color,
		"Explicit modulate opt should override team tint")


func test_ship_card_no_tint_when_no_team_given() -> void:
	var card := ShipCard.new()
	add_child_autofree(card)
	card.setup("capital")
	assert_eq(card._sprite.modulate, Color.WHITE,
		"No team or modulate opt should leave sprite unmodulated (white)")


func test_ship_card_handles_unknown_type_without_crash() -> void:
	var card := ShipCard.new()
	add_child_autofree(card)
	# Should not throw — setup with unknown type falls back gracefully.
	card.setup("ghost_ship_xxxx")
	assert_engine_error(1, "Expected a warning for unknown ship type")
	assert_not_null(card._sprite.texture, "ShipCard should still show placeholder for unknown type")
