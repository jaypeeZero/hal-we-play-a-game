class_name RaceBettingScreen
extends OverlayScreen

## R&R overlay: mixed race field, odds card, wager, visible replay, settle.
## Mirrors shop_screen.gd overlay pattern (build_chrome → setup → emit_closed).
## Money mutations and save use the exact same path as shop/battle.

const RACE_TRACKS := ["asteroid_sprint", "nebula_circuit"]
const NPC_SHIP_TYPES := ["fighter", "heavy_fighter", "corvette"]
const NPC_SKILL_MIN := 0.25
const NPC_SKILL_MAX := 0.85
## Callsigns for NPC racers.
const NPC_CALLSIGNS := [
	"Blaze", "Vector", "Torque", "Static", "Ember",
	"Flint", "Nova", "Quark", "Ripple", "Surge",
]

var _track: Dictionary = {}
var _entrants: Array = []       # Array of {ship, crew, is_player_pilot}
var _probs: Array = []          # Parallel implied probabilities
var _race_seed: int = 0
var _results: Dictionary = {}

var _wager_amount: int = 0
var _bet_entrant_index: int = -1
var _updating_buttons: bool = false
var _status_message: String = ""

var _money_label: Label
var _content: VBoxContainer
var _wager_input: LineEdit
var _bet_buttons: Array = []
var _status_label: Label
var _settle_button: Button
var _run_button: Button


## Open this screen as an overlay over `parent`. Returns the screen instance.
static func open_overlay(parent: Node) -> RaceBettingScreen:
	"""Create and attach the betting screen as an overlay."""
	var screen := RaceBettingScreen.new()
	parent.add_child(screen)
	screen.setup()
	return screen


func setup() -> void:
	"""Build UI, roll the race field and display it."""
	build_chrome()
	var topbar := _build_topbar()
	var body := _build_body()
	var leave_btn := UiKit.style_button(_make_button("Leave races"), "warn")
	leave_btn.pressed.connect(func() -> void: emit_closed())
	footer.add_child(leave_btn)
	_finalize_chrome(topbar, body)

	_roll_new_race()
	_rebuild()


func _build_topbar() -> Control:
	var bar := UiKit.card(UiKit.PANEL_2, UiKit.LINE, 14)
	var row := HBoxContainer.new()
	bar.add_child(row)

	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_child(UiKit.label("RACES", UiKit.INK, 16))
	title_box.add_child(UiKit.label("Bet on the field", UiKit.DIM, 11))
	row.add_child(title_box)

	var credits_box := VBoxContainer.new()
	credits_box.alignment = BoxContainer.ALIGNMENT_END
	_money_label = UiKit.label("", UiKit.GOLD, 26)
	_money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	credits_box.add_child(_money_label)
	var lbl := UiKit.label("CREDITS", UiKit.DIM, 10)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	credits_box.add_child(lbl)
	row.add_child(credits_box)
	return bar


func _build_body() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", OverlayScreen.SECTION_GAP)
	scroll.add_child(_content)
	return scroll


func _rebuild() -> void:
	"""Rebuild the entire body with current field/wager state."""
	for child in _content.get_children():
		child.queue_free()

	_money_label.text = str(RoguelikeRun.money)

	# Track header.
	var track_name: String = _track.get("name", "Unknown Track")
	var laps: int = _track.get("laps", 3)
	_content.add_child(UiKit.label("%s — %d laps" % [track_name, laps], UiKit.INK, 14))

	# Field card.
	_bet_buttons.clear()
	var house_edge: float = _racing_config("house_edge", 0.12)
	for i in range(_entrants.size()):
		var e: Dictionary = _entrants[i]
		var is_player: bool = e.get("is_player_pilot", false)
		var odds: float = RaceOdds.decimal_odds(_probs[i], house_edge)
		var win_pct: int = int(round(_probs[i] * 100.0))
		var callsign: String = e.crew.get("callsign", "Unknown")
		var stype: String = e.ship.get("type", "?")

		var row := HBoxContainer.new()
		var name_lbl := UiKit.label(callsign, UiKit.INK, 12)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)
		row.add_child(UiKit.label(stype, UiKit.DIM, 11))
		row.add_child(UiKit.label("%.2fx  (%d%%)" % [odds, win_pct], UiKit.GOLD, 12))

		if is_player:
			row.add_child(UiKit.label("[YOURS]", UiKit.DIM, 10))
		else:
			var btn := Button.new()
			btn.text = "Bet"
			btn.toggle_mode = true
			btn.button_pressed = (i == _bet_entrant_index)
			UiKit.style_button(btn, "ghost")
			btn.set_meta("entrant_idx", i)
			var idx := i
			btn.toggled.connect(func(on: bool) -> void: _on_bet_selected(idx, on))
			_bet_buttons.append(btn)
			row.add_child(btn)

		_content.add_child(row)

	_content.add_child(UiKit.separator())

	# Status / result message (persists across rebuilds).
	_status_label = UiKit.label(_status_message, UiKit.DIM, 11)

	# New field / track is always available.
	var new_btn := Button.new()
	new_btn.text = "New field / track"
	UiKit.style_button(new_btn, "ghost")
	new_btn.pressed.connect(_on_new_field_pressed)

	# Wager + run only before the race is run; after, the bet is settled.
	if _results.is_empty():
		var min_w: int = int(_racing_config("min_wager", 10))
		var max_w: int = _max_wager()
		var wager_row := HBoxContainer.new()
		wager_row.add_child(UiKit.label("Wager (%d–%d cr):" % [min_w, max_w], UiKit.INK, 12))
		_wager_input = LineEdit.new()
		_wager_input.placeholder_text = str(min_w)
		_wager_input.text = str(_wager_amount) if _wager_amount > 0 else ""
		_wager_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wager_row.add_child(_wager_input)
		_content.add_child(wager_row)
		_content.add_child(_status_label)
		_run_button = Button.new()
		_run_button.text = "Run Race & Settle Bet"
		UiKit.style_button(_run_button, "primary")
		_run_button.pressed.connect(_on_run_pressed)
		_content.add_child(_run_button)
	else:
		_content.add_child(_status_label)
	_content.add_child(new_btn)

	# Show results if available.
	if not _results.is_empty():
		_content.add_child(UiKit.separator())
		_content.add_child(UiKit.label("— Final Standings —", UiKit.INK, 13))
		for entry in _results.get("standings", []):
			var status_str := "DNF" if entry.dnf else ("%.1fs" % entry.finish_time)
			var eff_str := "eff %.2f" % entry.path_efficiency
			var row2 := HBoxContainer.new()
			row2.add_child(UiKit.label("[%d]" % entry.rank, UiKit.INK, 12))
			var n_lbl := UiKit.label(entry.callsign, UiKit.INK, 12)
			n_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row2.add_child(n_lbl)
			row2.add_child(UiKit.label(status_str, UiKit.DIM, 11))
			row2.add_child(UiKit.label(eff_str, UiKit.DIM, 10))
			_content.add_child(row2)


func _on_bet_selected(entrant_idx: int, on: bool) -> void:
	"""Select a single racer to bet on; clears any other toggled bet button."""
	if _updating_buttons:
		return
	if on:
		_bet_entrant_index = entrant_idx
		_updating_buttons = true
		for btn in _bet_buttons:
			if int(btn.get_meta("entrant_idx", -1)) != entrant_idx:
				btn.button_pressed = false
		_updating_buttons = false
		if _status_label != null:
			var picked: String = _entrants[entrant_idx].crew.get("callsign", "racer")
			_status_label.text = "Betting on %s — set a wager, then Run Race & Settle Bet." % picked
	elif _bet_entrant_index == entrant_idx:
		_bet_entrant_index = -1
		if _status_label != null:
			_status_label.text = ""


func _on_run_pressed() -> void:
	"""Validate, deduct wager, run simulator, settle bet."""
	# Parse wager.
	var wager_text: String = _wager_input.text.strip_edges()
	if not wager_text.is_valid_int():
		_status_label.text = "Enter a valid wager amount."
		return
	_wager_amount = int(wager_text)
	var min_w: int = int(_racing_config("min_wager", 10))
	var max_w: int = _max_wager()
	if _wager_amount < min_w:
		_status_label.text = "Minimum wager is %d cr." % min_w
		return
	if _wager_amount > max_w:
		_status_label.text = "Maximum wager is %d cr." % max_w
		return
	if _bet_entrant_index < 0:
		_status_label.text = "Select a racer to bet on."
		return

	# Deduct wager.
	RoguelikeRun.money -= _wager_amount

	# Run simulator (authoritative result).
	_results = RaceSimulator.run(_track, _entrants, _race_seed)

	# Settle.
	var winner_id: String = _results.get("winner_ship_id", "")
	var bet_ship_id: String = _entrants[_bet_entrant_index].ship.ship_id
	var house_edge: float = _racing_config("house_edge", 0.12)
	var won: bool = winner_id == bet_ship_id

	if won:
		var odds: float = RaceOdds.decimal_odds(_probs[_bet_entrant_index], house_edge)
		var winnings: int = RaceOdds.payout(_wager_amount, odds)
		RoguelikeRun.money += winnings
		_status_message = "You won! +%d cr (paid %.2fx)" % [winnings - _wager_amount, odds]
	else:
		_status_message = "You lost %d cr. Better luck next time." % _wager_amount

	RoguelikeRun.save_campaign_to_disk()
	_rebuild()


func _on_new_field_pressed() -> void:
	"""Roll a new race field and track."""
	_results = {}
	_bet_entrant_index = -1
	_wager_amount = 0
	_status_message = ""
	_roll_new_race()
	_rebuild()


func _roll_new_race() -> void:
	"""Generate a new mixed field and pick a random track."""
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_race_seed = rng.randi()

	# Pick a track.
	var track_id: String = RACE_TRACKS[rng.randi() % RACE_TRACKS.size()]
	_track = RaceTrack.load_track(track_id)

	# Determine field size.
	var field_min: int = int(_racing_config("field_size_min", 4))
	var field_max: int = int(_racing_config("field_size_max", 6))
	var field_size: int = field_min + rng.randi() % (field_max - field_min + 1)

	_entrants.clear()

	# Add player's own pilots first.
	for hull in RoguelikeRun.fleet_hulls:
		if _entrants.size() >= field_size:
			break
		for crew_member in hull.get("crew", []):
			if crew_member.get("role", -1) == CrewData.Role.PILOT:
				var ship := ShipData.create_ship_instance(hull.ship_type, 0, Vector2.ZERO)
				if ship.is_empty():
					continue
				_entrants.append({
					"ship": ship,
					"crew": crew_member.duplicate(true),
					"is_player_pilot": true,
				})
				break

	# Fill remaining slots with NPC racers.
	var used_callsigns: Dictionary = {}
	while _entrants.size() < field_size:
		var stype: String = NPC_SHIP_TYPES[rng.randi() % NPC_SHIP_TYPES.size()]
		var ship := ShipData.create_ship_instance(stype, 1, Vector2.ZERO)
		if ship.is_empty():
			continue
		var skill: float = NPC_SKILL_MIN + rng.randf() * (NPC_SKILL_MAX - NPC_SKILL_MIN)
		var crew := _make_npc_pilot(rng, skill, used_callsigns)
		_entrants.append({
			"ship": ship,
			"crew": crew,
			"is_player_pilot": false,
		})

	# Compute odds.
	_probs = RaceOdds.implied_probabilities(_entrants, _track)


func _make_npc_pilot(rng: RandomNumberGenerator, skill: float,
		used_callsigns: Dictionary) -> Dictionary:
	"""Generate a single NPC pilot crew member."""
	var callsign: String = "Racer"
	for _i in range(10):
		var candidate: String = NPC_CALLSIGNS[rng.randi() % NPC_CALLSIGNS.size()]
		if not used_callsigns.has(candidate):
			callsign = candidate
			used_callsigns[candidate] = true
			break

	return {
		"crew_id": "npc_%d" % rng.randi(),
		"callsign": callsign,
		"role": CrewData.Role.PILOT,
		"qualified_roles": [CrewData.Role.PILOT],
		"stats": {
			"stress": 0.0,
			"fatigue": 0.0,
			"reaction_time": 0.15,
			"skills": {
				"piloting": clamp(skill + rng.randf_range(-0.15, 0.15), 0.1, 1.0),
				"awareness": clamp(skill + rng.randf_range(-0.15, 0.15), 0.1, 1.0),
				"composure": clamp(skill + rng.randf_range(-0.2, 0.2), 0.1, 1.0),
				"aggression": rng.randf(),
				"aim": 0.5,
				"tactics": 0.5,
				"machinery": 0.5,
			},
		},
	}


func _max_wager() -> int:
	"""Maximum wager: min(money, money × max_wager_fraction)."""
	var frac: float = _racing_config("max_wager_fraction", 0.5)
	return max(0, min(RoguelikeRun.money, int(float(RoguelikeRun.money) * frac)))


func _racing_config(key: String, default_val) -> float:
	"""Read a value from economy.json racing block."""
	return float(EconomySystem.config().get("racing", {}).get(key, default_val))


func _make_button(text: String) -> Button:
	"""Create a plain button."""
	var btn := Button.new()
	btn.text = text
	return btn
