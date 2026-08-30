extends Node
## Headless end-to-end check of the season + battle engines.
## Run: godot --headless --path . res://tools/sim_check.tscn
## Prints "SIM CHECK OK" and exits 0 on success; exits 1 on any failure.
## The player's real user://save.json is backed up and restored around the run.

const SaveGuard := preload("res://tools/save_guard.gd")

var _fail := false


func _ready() -> void:
	# run deferred so autoloads are fully ready
	_run.call_deferred()


func _check(cond: bool, what: String) -> void:
	if cond:
		print("  ok: %s" % what)
	else:
		printerr("  FAIL: %s" % what)
		_fail = true


const TMP_SERVICE_PATH := "res://shared/sim/services/_tmp_simcheck_service.gd"
const TMP_SERVICE_SRC := """extends RefCounted
var days := 0
var last_date := ""
func on_day(_gs, date: String) -> void:
	days += 1
	last_date = date
func save_state() -> Dictionary:
	return {"days": days, "last_date": last_date}
func load_state(s: Dictionary) -> void:
	days = int(s.get("days", 0))
	last_date = str(s.get("last_date", ""))
"""


func _run() -> void:
	print("=== sim_check: battle engine determinism ===")
	SaveGuard.backup()   # never clobber the player's real career
	GameState.delete_save()
	# drop a probe service in BEFORE career start to exercise the auto-load
	# services convention (discovery, daily tick, save/load state)
	var sf := FileAccess.open(TMP_SERVICE_PATH, FileAccess.WRITE)
	sf.store_string(TMP_SERVICE_SRC)
	sf.close()
	GameState.new_career(424242)

	var clubs: Array = GameState.world["clubs"]
	var team_a: Array = Season.pick_team(clubs[0])
	var team_b: Array = Season.pick_team(clubs[1])
	_check(team_a.size() == 6 and team_b.size() == 6, "pick_team returns 6 battlers")

	var e1 := BattleEngine.new(team_a, team_b, 777)
	var log1 := e1.run_to_end()
	var e2 := BattleEngine.new(team_a, team_b, 777)
	var log2 := e2.run_to_end()
	_check(e1.is_over() and e1.winner() in [0, 1], "battle finishes with a winner (winner=%d, turns=%d)" % [e1.winner(), e1.turn])
	_check(log1.size() == log2.size() and e1.winner() == e2.winner(),
		"same seed => identical battle (%d events)" % log1.size())
	var e3 := BattleEngine.new(team_a, team_b, 778)
	e3.run_to_end()
	print("  info: seed 778 winner=%d turns=%d" % [e3.winner(), e3.turn])
	var kinds := {}
	for ev in log1:
		kinds[ev["t"]] = kinds.get(ev["t"], 0) + 1
	_check(kinds.has("move_used") and kinds.has("damage") and kinds.has("faint")
		and kinds.has("battle_end") and kinds.has("commentary_hook"),
		"event log has move_used/damage/faint/battle_end/commentary_hook: %s" % str(kinds))

	# step-mode API
	var e4 := BattleEngine.new(team_a, team_b, 999)
	var steps := 0
	while not e4.is_over() and steps < 400:
		var acts := e4.legal_actions(0)
		var evs := e4.step_turn(acts[0], null)  # player always uses first legal action
		_check_quiet(evs.size() > 0, "step_turn returns events")
		steps += 1
	_check(e4.is_over(), "step-mode battle finishes (turns=%d)" % e4.turn)

	_doubles_checks()

	print("=== sim_check: items — held effects, use_item, determinism ===")
	_check(DataStore.items.size() >= 40, "item catalog loaded (%d items)" % DataStore.items.size())
	var held_n: int = DataStore.items_list("held").size()
	var usable_n: int = DataStore.items_list("usable").size()
	_check(held_n >= 20 and usable_n >= 15, "both classes present (%d held / %d usable)" % [held_n, usable_n])

	# held effect fires: damaged Leftovers holder regains HP at end of turn
	var e5 := BattleEngine.new([_mk(113, 60, "leftovers")], [_mk(129, 10, null), _mk(129, 10, null)], 4242)
	e5.active_battler(0)["hp"] = int(e5.active_battler(0)["max_hp"] / 2.0)
	var hp_before: int = int(e5.active_battler(0)["hp"])
	var evs5 := e5.step_turn({"type": "move", "index": 0}, {"type": "move", "index": 0})
	_check(evs5.any(func(ev): return ev["t"] == "held_item" and ev["effect"] == "end_turn_heal"),
		"Leftovers emits held_item at end of turn")
	_check(int(e5.active_battler(0)["hp"]) > hp_before, "Leftovers holder regained HP")

	# use_item: legal action, costs the turn, consumes from the battle bag
	var e6 := BattleEngine.new([_mk(113, 50, null)], [_mk(129, 10, null), _mk(129, 10, null)], 555)
	e6.set_inventory(0, {"super_potion": 2})
	e6.active_battler(0)["hp"] = 100
	var la6 := e6.legal_actions(0)
	_check(la6.any(func(a): return a["type"] == "use_item" and a["item"] == "super_potion"),
		"legal_actions offers use_item when stocked")
	var evs6 := e6.step_turn({"type": "use_item", "item": "super_potion", "target": 0}, {"type": "move", "index": 0})
	_check(evs6.any(func(ev): return ev["t"] == "item_used" and ev["item"] == "super_potion"),
		"use_item emits item_used")
	_check(not evs6.any(func(ev): return ev["t"] == "move_used" and int(ev["side"]) == 0),
		"use_item costs the side's turn (no move used)")
	_check(int(e6.active_battler(0)["hp"]) > 100, "potion healed the target")
	_check(int(e6.inventory(0).get("super_potion", 0)) == 1, "battle bag decremented")
	_check(e6.items_used(0) == 1, "items_used counter tracks usage")

	# Choice item locks the first move used
	var e7 := BattleEngine.new([_mk(6, 50, "choice_band")], [_mk(113, 50, null)], 777)
	e7.step_turn({"type": "move", "index": 1}, {"type": "move", "index": 0})
	var move_acts7: Array = e7.legal_actions(0).filter(func(a): return a["type"] == "move")
	_check(move_acts7.size() == 1 and int(move_acts7[0]["index"]) == 1,
		"Choice Band locks legal moves to the first used")

	# determinism with held items + AI trainer-item usage
	var bag := {"super_potion": 2, "full_heal": 1}
	var d_events := []
	var d_winner := []
	var d_used := []
	for rep in 2:
		var ti1: Array = [_mk(6, 50, "life_orb"), _mk(9, 50, "leftovers"), _mk(65, 50, "focus_sash")]
		var ti2: Array = [_mk(59, 50, "choice_band"), _mk(103, 50, "sitrus_berry"), _mk(131, 50, "assault_vest")]
		var d := BattleEngine.new(ti1, ti2, 31337)
		d.set_inventory(0, bag)
		d.set_inventory(1, bag)
		d.run_to_end()
		d_events.append(d.events.size())
		d_winner.append(d.winner())
		d_used.append(d.items_used(0) + d.items_used(1))
		if rep == 0:
			_check(d.events.any(func(ev): return ev["t"] == "held_item"),
				"held-item effects fire in an AI battle")
			_check(d.items_used(0) <= 2 and d.items_used(1) <= 2, "AI respects item budget (max 2)")
	_check(d_events[0] == d_events[1] and d_winner[0] == d_winner[1] and d_used[0] == d_used[1],
		"same seed + same bags => identical battle with items (%d events, %d items used)" % [d_events[0], d_used[0]])

	print("=== sim_check: natures ===")
	var n_ad := BattleEngine.new([_mkx(66, 50, ["Karate Chop"], "Adamant", null)],
		[_mkx(66, 50, ["Karate Chop"], "Modest", null)], 1)
	var n_ha := BattleEngine.new([_mkx(66, 50, ["Karate Chop"], "Hardy", null)],
		[_mkx(66, 50, ["Karate Chop"], "Hardy", null)], 1)
	var sa: Dictionary = n_ad.active_battler(0)["stats"]   # Adamant: +atk -spa
	var sm: Dictionary = n_ad.active_battler(1)["stats"]   # Modest:  +spa -atk
	var sh: Dictionary = n_ha.active_battler(0)["stats"]   # Hardy: neutral
	_check(int(sa["atk"]) == int(floor(float(sh["atk"]) * 1.1))
		and int(sa["spa"]) == int(floor(float(sh["spa"]) * 0.9)),
		"Adamant = +10%% atk / -10%% spa (atk %d->%d, spa %d->%d)" % [sh["atk"], sa["atk"], sh["spa"], sa["spa"]])
	_check(int(sm["spa"]) > int(sh["spa"]) and int(sm["atk"]) < int(sh["atk"]),
		"Modest mirrors it on the special side")
	_check(int(sa["hp"]) == int(sh["hp"]), "natures never touch HP")

	print("=== sim_check: abilities ===")
	# Intimidate: entry drop on the foe's Attack
	var ab1 := BattleEngine.new([_mkx(130, 50, ["Surf"], "Hardy", null)],
		[_mkx(66, 50, ["Karate Chop"], "Hardy", null)], 11)
	_check(int(ab1.active_battler(1)["stages"]["atk"]) == -1
		and ab1.events.any(func(ev): return ev["t"] == "ability_triggered" and ev["ability"] == "intimidate"),
		"Intimidate drops the foe's Attack on entry")
	# Levitate: full immunity to Ground moves
	var ab2 := BattleEngine.new([_mkx(66, 50, ["Earthquake"], "Hardy", null)],
		[_mkx(94, 50, ["Splash"], "Hardy", null)], 12)
	ab2.step_turn({"type": "move", "index": 0}, {"type": "move", "index": 0})
	_check(int(ab2.active_battler(1)["hp"]) == int(ab2.active_battler(1)["max_hp"])
		and ab2.events.any(func(ev): return ev["t"] == "ability_triggered" and ev["ability"] == "levitate" and ev["effect"] == "immune"),
		"Levitate no-sells Earthquake")
	# Flash Fire: absorbs fire, boosts own fire moves (Vulpix — Ninetales
	# now carries Drought so ability-set weather is reachable in careers)
	var ab3 := BattleEngine.new([_mkx(66, 50, ["Ember"], "Hardy", null)],
		[_mkx(37, 50, ["Splash"], "Hardy", null)], 13)
	ab3.step_turn({"type": "move", "index": 0}, {"type": "move", "index": 0})
	var nine: Dictionary = ab3.active_battler(1)
	_check(int(nine["hp"]) == int(nine["max_hp"]) and bool(nine["flash_fire"])
		and ab3.events.any(func(ev): return ev["t"] == "ability_triggered" and ev["ability"] == "flash_fire"),
		"Flash Fire absorbs Ember and charges up")
	_check(absf(ab3._offense_mult(1, nine, DataStore.move("Ember"), false) - 1.5) < 0.001,
		"charged Flash Fire boosts its own Fire moves x1.5")
	# Water Absorb: heals instead of taking water damage
	var ab4 := BattleEngine.new([_mkx(66, 50, ["Water Gun"], "Hardy", null)],
		[_mkx(60, 50, ["Splash"], "Hardy", null)], 14)
	ab4.active_battler(1)["hp"] = int(ab4.active_battler(1)["max_hp"] / 2.0)
	var wa_hp: int = int(ab4.active_battler(1)["hp"])
	ab4.step_turn({"type": "move", "index": 0}, {"type": "move", "index": 0})
	_check(int(ab4.active_battler(1)["hp"]) > wa_hp
		and ab4.events.any(func(ev): return ev["t"] == "ability_triggered" and ev["ability"] == "water_absorb"),
		"Water Absorb turns Water Gun into healing")
	# Static: contact paralysis
	var ab5 := BattleEngine.new([_mkx(66, 5, ["Karate Chop"], "Hardy", null)],
		[_mkx(25, 50, ["Splash"], "Hardy", null)], 15)
	for i in 30:
		if ab5.is_over() or str(ab5.active_battler(0)["status"]) == "para":
			break
		ab5.step_turn({"type": "move", "index": 0}, {"type": "move", "index": 0})
	_check(str(ab5.active_battler(0)["status"]) == "para"
		and ab5.events.any(func(ev): return ev["t"] == "ability_triggered" and ev["ability"] == "static"),
		"Static paralyzes the attacker on contact")
	# Sturdy: survives a one-hit KO from full HP
	var ab6 := BattleEngine.new([_mkx(6, 100, ["Flamethrower"], "Hardy", null)],
		[_mkx(74, 5, ["Tackle"], "Hardy", null)], 16)
	ab6.step_turn({"type": "move", "index": 0}, {"type": "move", "index": 0})
	_check(ab6.events.any(func(ev): return ev["t"] == "ability_triggered" and ev["ability"] == "sturdy"),
		"Sturdy triggers against a would-be OHKO (hp_left=%d)" % int(ab6.team_state(1)[0]["hp"]))
	# Speed Boost: end-of-turn stage gain
	var ab7 := BattleEngine.new([_mkx(193, 50, ["Tackle"], "Hardy", null)],
		[_mkx(66, 50, ["Splash"], "Hardy", null)], 17)
	ab7.step_turn({"type": "move", "index": 0}, {"type": "move", "index": 0})
	_check(int(ab7.active_battler(0)["stages"]["spe"]) >= 1
		and ab7.events.any(func(ev): return ev["t"] == "ability_triggered" and ev["ability"] == "speed_boost"),
		"Speed Boost raises Speed at end of turn")
	# Guts: burned attacker hits harder, not softer
	var ab8 := BattleEngine.new([_mkx(66, 50, ["Karate Chop"], "Hardy", null)],
		[_mkx(66, 50, ["Splash"], "Hardy", null)], 18)
	var guts_b: Dictionary = ab8.active_battler(0)
	var atk_clean: float = ab8._eff_stat(guts_b, "atk")
	guts_b["status"] = "burn"
	_check(absf(ab8._eff_stat(guts_b, "atk") - atk_clean * 1.5) < 0.01,
		"Guts: burn means Attack x1.5, burn halving ignored")
	# Thick Fat: halves fire/ice damage taken
	var ab9 := BattleEngine.new([_mkx(143, 50, ["Tackle"], "Hardy", null)],
		[_mkx(66, 50, ["Splash"], "Hardy", null)], 19)
	_check(absf(ab9._defense_mult(0, ab9.active_battler(0), DataStore.move("Ember"), false) - 0.5) < 0.001,
		"Thick Fat halves incoming Fire damage")

	print("=== sim_check: weather ===")
	# Rain Dance: sets rain for 5 turns, then it expires
	var w1 := BattleEngine.new([_mkx(60, 50, ["Rain Dance", "Splash"], "Hardy", null)],
		[_mkx(66, 50, ["Splash"], "Hardy", null)], 21)
	w1.step_turn({"type": "move", "index": 0}, {"type": "move", "index": 0})
	_check(w1.weather() == "rain"
		and w1.events.any(func(ev): return ev["t"] == "weather_start" and ev["kind"] == "rain" and ev["source"] == "move"),
		"Rain Dance starts the rain (turns left %d)" % w1.weather_turns_left())
	_check(absf(w1._weather_move_mult("water") - 1.5) < 0.001
		and absf(w1._weather_move_mult("fire") - 0.5) < 0.001,
		"rain: water x1.5, fire x0.5")
	for i in 4:
		w1.step_turn({"type": "move", "index": 1}, {"type": "move", "index": 0})
	_check(w1.weather() == ""
		and w1.events.any(func(ev): return ev["t"] == "weather_end" and ev["kind"] == "rain"),
		"rain expires after 5 turns")
	# Chlorophyll / Swift Swim style weather speed
	var w2 := BattleEngine.new([_mkx(45, 50, ["Splash"], "Hardy", null)],
		[_mkx(66, 50, ["Splash"], "Hardy", null)], 22)
	var leaf: Dictionary = w2.active_battler(0)
	var spe_clear: float = w2._eff_stat(leaf, "spe")
	w2._set_weather("sun", 5, "move", 0, "test")
	_check(absf(w2._eff_stat(leaf, "spe") - spe_clear * 2.0) < 0.01,
		"Chlorophyll doubles Speed in the sun")
	# Sand Stream: auto-weather on entry + residual chip on the non-immune side
	var w3 := BattleEngine.new([_mkx(248, 50, ["Tackle"], "Hardy", null)],
		[_mkx(66, 50, ["Splash"], "Hardy", null)], 23)
	_check(w3.weather() == "sand"
		and w3.events.any(func(ev): return ev["t"] == "ability_triggered" and ev["ability"] == "sand_stream")
		and w3.events.any(func(ev): return ev["t"] == "weather_start" and ev["source"] == "ability"),
		"Sand Stream whips up a sandstorm on entry")
	w3.step_turn({"type": "move", "index": 0}, {"type": "move", "index": 0})
	_check(w3.events.any(func(ev): return ev["t"] == "weather_chip" and int(ev["side"]) == 1),
		"sandstorm chips the non-immune side")
	_check(not w3.events.any(func(ev): return ev["t"] == "weather_chip" and int(ev["side"]) == 0),
		"Rock types shrug the sandstorm off")
	# AI weather awareness: boosted moves score higher
	var w4 := BattleEngine.new([_mkx(60, 50, ["Surf", "Tackle"], "Hardy", null)],
		[_mkx(66, 50, ["Splash"], "Hardy", null)], 24)
	var surf_clear: float = w4._move_score(w4.active_battler(0), w4.active_battler(1), "Surf")
	w4._set_weather("rain", 5, "move", 0, "test")
	_check(w4._move_score(w4.active_battler(0), w4.active_battler(1), "Surf") > surf_clear,
		"AI scores rain-boosted Water moves higher")

	print("=== sim_check: determinism with natures + abilities + weather ===")
	var da_events := []
	var da_winner := []
	for rep in 2:
		var dta: Array = [_mkx(248, 50, ["Tackle", "Sandstorm"], "Adamant", null),
			_mkx(130, 50, ["Surf", "Rain Dance"], "Jolly", null),
			_mkx(38, 50, ["Ember", "Sunny Day"], "Timid", null)]
		var dtb: Array = [_mkx(186, 50, ["Surf", "Splash"], "Modest", null),
			_mkx(45, 50, ["Vine Whip", "Sunny Day"], "Bold", null),
			_mkx(66, 50, ["Karate Chop"], "Adamant", null)]
		var dd := BattleEngine.new(dta, dtb, 20260830)
		dd.run_to_end()
		da_events.append(dd.events.size())
		da_winner.append(dd.winner())
		if rep == 0:
			var dk := {}
			for ev in dd.events:
				dk[ev["t"]] = dk.get(ev["t"], 0) + 1
			_check(dk.has("ability_triggered") and dk.has("weather_start"),
				"depth events present in an AI battle: %s" % str(dk))
	_check(da_events[0] == da_events[1] and da_winner[0] == da_winner[1],
		"same seed => identical battle with natures/abilities/weather (%d events)" % da_events[0])

	print("=== sim_check: 50-day season fast-forward ===")
	var start_date: String = GameState.current_date
	for i in 50:
		GameState.advance_day()
	_check(GameState.current_date == Season.date_add(start_date, 50),
		"calendar advanced 50 days -> %s" % GameState.current_date)

	var played := GameState.fixtures.filter(func(f): return f["played"])
	var league_played := played.filter(func(f): return f["comp"] == "league")
	var cup_played := played.filter(func(f): return f["comp"] == "cup")
	_check(league_played.size() >= 80, "league fixtures simulated across both leagues (%d played)" % league_played.size())
	_check(cup_played.size() >= 16, "cup round 1 simulated (%d cup ties played)" % cup_played.size())
	_check(GameState.cup_round >= 2, "next cup round drawn (cup_round=%d)" % GameState.cup_round)
	for f in played:
		if f["score_home"] == f["score_away"]:
			_check(false, "no draws allowed, got %s" % str(f))
			break

	print("=== sim_check: two-league structure ===")
	_check(GameState.leagues().size() == 2, "two leagues (%s)" % str(GameState.leagues()))
	_check(GameState.league_club_ids("kanto").size() == 16 and GameState.league_club_ids("johto").size() == 16,
		"16 clubs per league")
	_check(GameState.all_club_ids().size() == 32, "32 clubs world-wide")
	_check(GameState.league_of("club00") == "kanto" and GameState.league_of("club16") == "johto",
		"league_of maps both regions")
	var cross_league := 0
	for f in GameState.fixtures:
		if f["comp"] == "league" and GameState.league_of(f["home"]) != GameState.league_of(f["away"]):
			cross_league += 1
	_check(cross_league == 0, "league fixtures never cross leagues")
	var kanto_played := league_played.filter(func(f): return str(f.get("league", "")) == "kanto")
	var johto_played := league_played.filter(func(f): return str(f.get("league", "")) == "johto")
	_check(kanto_played.size() >= 40 and johto_played.size() >= 40,
		"both championships sim in parallel (%d kanto / %d johto)" % [kanto_played.size(), johto_played.size()])
	var cup1 := GameState.fixtures.filter(func(f): return f["comp"] == "cup" and int(f["round"]) == 1)
	_check(cup1.size() == 16, "Indigo Cup round 1 has 16 ties (32 clubs)")
	var cup_cross := cup1.filter(func(f): return GameState.league_of(f["home"]) != GameState.league_of(f["away"]))
	_check(cup_cross.size() > 0, "Indigo Cup draws across leagues (%d cross-league ties in R1)" % cup_cross.size())
	_check(Season.cup_round_name(5) == "Final" and Season.cup_round_name(3) == "Quarter-Final",
		"32-club cup round names")

	var table: Array = GameState.league_table()
	_check(table.size() == 16, "player-league table has 16 rows")
	var total_played := 0
	for row in table:
		total_played += int(row["played"])
		_check_quiet(int(row["points"]) == int(row["won"]) * 3, "points = 3*wins for %s" % row["club_id"])
	_check(total_played == kanto_played.size() * 2, "kanto table played counts match kanto fixtures")
	var jtable: Array = GameState.league_table("johto")
	_check(jtable.size() == 16, "johto table has 16 rows")
	var jtotal := 0
	for row in jtable:
		jtotal += int(row["played"])
	_check(jtotal == johto_played.size() * 2, "johto table played counts match johto fixtures")
	var top: Dictionary = table[0]
	print("  info: kanto leader after 50 days: %s with %d pts (%d played)" %
		[GameState.club(top["club_id"])["name"], top["points"], top["played"]])
	print("  info: johto leader after 50 days: %s with %d pts (%d played)" %
		[GameState.club(jtable[0]["club_id"])["name"], jtable[0]["points"], jtable[0]["played"]])
	_check(GameState.player_table_position() > 0, "player club in table (pos %d)" % GameState.player_table_position())
	_check(GameState.inbox.size() > 1, "inbox has match reports (%d messages)" % GameState.inbox.size())

	_season_boundary_checks()

	print("=== sim_check: gen-2 type chart sanity ===")
	_check(DataStore.effectiveness("dark", ["psychic"]) == 2.0, "Dark hits Psychic super-effectively")
	_check(DataStore.effectiveness("ghost", ["psychic"]) == 2.0, "Ghost hits Psychic super-effectively (gen-2 fix)")
	_check(DataStore.effectiveness("psychic", ["dark"]) == 0.0, "Psychic can't touch Dark")
	_check(DataStore.effectiveness("poison", ["steel"]) == 0.0, "Poison can't touch Steel")
	_check(DataStore.effectiveness("fighting", ["dark"]) == 2.0, "Fighting hits Dark super-effectively")
	_check(DataStore.effectiveness("steel", ["ice"]) == 2.0, "Steel hits Ice super-effectively")

	print("=== sim_check: services convention (auto-load, tick, persistence) ===")
	var probe: Variant = null
	for svc in GameState._services:
		if _svc_id(svc) == "_tmp_simcheck_service":
			probe = svc
	_check(probe != null, "res://shared/sim/services/*.gd auto-loaded at career start")
	if probe != null:
		_check(int(probe.days) >= 50, "service ticked daily (%d days)" % int(probe.days))
		_check(str(probe.last_date) == GameState.current_date, "service sees the current date")

	print("=== sim_check: Continue behaviour ===")
	var before_next := GameState.next_player_fixture()
	GameState.advance_to_next_event()
	_check(before_next.get("id") != GameState.next_player_fixture().get("id"),
		"advance_to_next_event processed the next player fixture")

	print("=== sim_check: items — club economy ===")
	var pc: Dictionary = GameState.player_club()
	var bal0 := int(pc["finances"]["balance"])
	_check(GameState.buy_item("leftovers", 1) == "", "buy_item succeeds")
	_check(int(pc["finances"]["balance"]) == bal0 - int(DataStore.item("leftovers")["price"]),
		"purchase deducted from club balance")
	_check(int(GameState.player_inventory().get("leftovers", 0)) >= 1, "storeroom stocked")
	_check(GameState.buy_item("max_revive", 999999) != "", "over-budget purchase rejected")
	var uid0: String = str(pc["squad"][0]["uid"])
	_check(GameState.assign_held_item(uid0, "leftovers") == "", "assign_held_item equips")
	_check(str(pc["squad"][0]["held_item"]) == "leftovers", "held slot set on instance")
	_check(GameState.unassign_held_item(uid0) == "", "unassign_held_item")
	_check(int(GameState.player_inventory().get("leftovers", 0)) >= 1, "item returned to storeroom")
	var equipped := 0
	for c in GameState.world["clubs"]:
		for m in c["squad"]:
			if m.get("held_item") != null and str(m.get("held_item", "")) != "":
				equipped += 1
	_check(equipped >= 10, "AI squads carry starting held items (%d equipped league-wide)" % equipped)
	var inv_before_save: String = _inv_norm(GameState.player_inventory())

	print("=== sim_check: save/load roundtrip ===")
	var date_before_save: String = GameState.current_date
	var fixtures_count := GameState.fixtures.size()
	var svc_days_before := 0
	for svc in GameState._services:
		if _svc_id(svc) == "_tmp_simcheck_service":
			svc_days_before = int(svc.days)
	_check(GameState.save_game(), "save_game succeeds")
	GameState.new_career(1)  # wipe in-memory state
	_check(GameState.load_game(), "load_game succeeds")
	_check(GameState.current_date == date_before_save, "loaded date matches (%s)" % GameState.current_date)
	_check(GameState.fixtures.size() == fixtures_count, "loaded fixture count matches (%d)" % fixtures_count)
	_check(_inv_norm(GameState.player_inventory()) == inv_before_save,
		"loaded item inventory matches")
	var svc_days_after := -1
	for svc in GameState._services:
		if _svc_id(svc) == "_tmp_simcheck_service":
			svc_days_after = int(svc.days)
	_check(svc_days_before > 0 and svc_days_after == svc_days_before,
		"service state survives save/load (%d days)" % svc_days_after)

	print("=== sim_check: new career at a Johto club ===")
	GameState.delete_save()
	GameState.new_career(777, "club20")
	_check(GameState.player_club().get("league", "") == "johto",
		"player club is in Johto (%s)" % GameState.player_club().get("name", "?"))
	_check(str(GameState.world["meta"]["league_name"]) == "Johto League",
		"meta.league_name follows the chosen club (screens' title source)")
	_check(GameState.league_table().size() == 16 and GameState.player_table_position() > 0,
		"johto standings host the player club")
	_check(not GameState.next_player_fixture().is_empty(), "johto career has a first fixture")

	print("=== sim_check: pre-leagues saves recover gracefully ===")
	var old_save := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	old_save.store_string(JSON.stringify({"version": 1, "career_seed": 5, "world": {}}))
	old_save.close()
	_check(not GameState.load_game(), "v1 save rejected without crashing")
	GameState.boot()
	_check(GameState.current_date == GameState.season_start, "boot routed to a fresh career")
	_check(GameState.inbox.any(func(m): return str(m["title"]).contains("earlier era")),
		"inbox explains the incompatible save")
	var resaved: Variant = JSON.parse_string(FileAccess.open(GameState.SAVE_PATH, FileAccess.READ).get_as_text())
	_check(typeof(resaved) == TYPE_DICTIONARY and int(resaved.get("version", 0)) == 2,
		"old save replaced by a v2 save")

	GameState.delete_save()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SERVICE_PATH))
	SaveGuard.restore()   # hand the player's real save back

	if _fail:
		printerr("SIM CHECK FAILED")
		get_tree().quit(1)
	else:
		print("SIM CHECK OK")
		get_tree().quit(0)


## SEASON BOUNDARY: fast-forward the current career through matchday 30 and
## across the rollover — Championship Series resolves, danger-zone consequences
## land, awards + history are recorded, and a fresh season begins. League/cup
## remainders are completed synthetically (deterministic scores + valid detail
## stubs, so no costly replays); the playoff itself is simulated for real.
func _season_boundary_checks() -> void:
	print("=== sim_check: season boundary — playoff, awards, history, rollover ===")
	var season1_start: String = GameState.season_start
	_synth_complete_season()
	_check(Season.league_complete(GameState.fixtures), "both championships completed (synthetically)")
	var cup_final: Array = GameState.fixtures.filter(func(f):
		return f["comp"] == "cup" and int(f["round"]) == 5 and f["played"])
	_check(cup_final.size() == 1, "cup ran to its Final (round 5 played)")

	# final tables (the playoff seeding source) + pre-ceremony club standing
	var kanto_top: Array = GameState.league_table("kanto").slice(0, 4).map(func(r): return str(r["club_id"]))
	var johto_top: Array = GameState.league_table("johto").slice(0, 4).map(func(r): return str(r["club_id"]))
	var rep_before := {}
	var danger_ids: Array = []
	for lid in ["kanto", "johto"]:
		var t: Array = GameState.league_table(lid)
		for i in range(13, t.size()):
			danger_ids.append(str(t[i]["club_id"]))
	for cid in danger_ids + kanto_top.slice(0, 1) + johto_top.slice(0, 1):
		rep_before[cid] = int(GameState.club(cid)["reputation"])

	# one day forward: the season_flow service must draw the quarter-finals
	GameState.advance_day()
	var po: Array = Season.playoff_fixtures(GameState.fixtures)
	_check(po.size() == 4, "Championship Series QF drawn after matchday 30 (%d ties)" % po.size())
	var qualified: Array = []
	for f in po:
		qualified += [str(f["home"]), str(f["away"])]
		var leagues := [GameState.league_of(str(f["home"])), GameState.league_of(str(f["away"]))]
		_check_quiet("kanto" in leagues and "johto" in leagues, "QF %s is cross-league" % f["id"])
	qualified.sort()
	var expected: Array = kanto_top + johto_top
	expected.sort()
	_check(qualified == expected, "QF field == top four of EACH league (zone legend feeds the mechanism)")
	_check(GameState.inbox.any(func(m): return str(m["title"]).contains("top four of each league")),
		"playoff qualification announced in the inbox")

	# play the Series + ceremony + rollover via plain advance_day (Continue path)
	var flow: Variant = null
	for svc in GameState._services:
		if _svc_id(svc) == "season_flow":
			flow = svc
	_check(flow != null, "season_flow service auto-loaded")
	var guard := 0
	while GameState.season_history().is_empty() and guard < 40:
		GameState.advance_day()
		guard += 1
	_check(not GameState.season_history().is_empty(), "season completed within %d days (ceremony fired)" % guard)
	var po_all: Array = Season.playoff_fixtures(GameState.fixtures)
	_check(po_all.size() == 7 and po_all.all(func(f): return f["played"]),
		"playoff ran QF->SF->Final (%d ties, all played)" % po_all.size())
	var finals: Array = po_all.filter(func(f): return int(f["round"]) == 3)
	var indigo := Season.fixture_winner(finals[0])
	_check(indigo != "", "Indigo Champion crowned: %s" % GameState.club(indigo).get("name", "?"))

	# history entry + awards
	var e: Dictionary = GameState.season_history()[0]
	_check(str(e["indigo"]["champion"]) == indigo, "history records the Indigo Champion")
	_check(str(e["league_champions"]["kanto"]["club_id"]) == kanto_top[0]
		and str(e["league_champions"]["johto"]["club_id"]) == johto_top[0],
		"history records both league champions")
	_check(str(e["cup"]["winner"]) != "", "history records the cup winners (%s)" % e["cup"]["name"])
	_check((e["playoff_results"] as Array).size() == 7, "history keeps the full playoff bracket")
	var pos_award: Dictionary = e["awards"].get("pokemon_of_season", {})
	_check(not pos_award.is_empty() and float(pos_award["rating"]) > 0.0 and int(pos_award["battles"]) >= 1,
		"Pokémon of the Season from real ratings: %s (%s) %.2f" % [
		pos_award.get("name", "?"), pos_award.get("species", "?"), float(pos_award.get("rating", 0))])
	var dev_award: Dictionary = e["awards"].get("best_developer", {})
	_check(not dev_award.is_empty() and int(dev_award["age_months"]) <= 60,
		"Best Developer is a young Pokémon (%s, %d months)" % [
		dev_award.get("name", "?"), int(dev_award.get("age_months", 0))])
	var aw1 := str(flow.compute_awards(GameState))
	var aw2 := str(flow.compute_awards(GameState))
	_check(aw1 == aw2, "awards computation is deterministic (identical on recompute)")
	_check(GameState.inbox.any(func(m): return str(m["title"]).begins_with("End-of-Season Awards")),
		"awards ceremony mail sent")
	_check(GameState.inbox.any(func(m): return str(m["title"]).begins_with("Season 1 review")),
		"season review mail sent")

	# danger zone (14-16) consequences are real
	var danger_hit := 0
	for cid in danger_ids:
		var before := int(rep_before[cid])
		var after := int(GameState.club(cid)["reputation"])
		if after == maxi(1, before - 1) and after <= before:
			danger_hit += 1
	_check(danger_hit == danger_ids.size(), "all %d danger-zone clubs lost reputation" % danger_ids.size())
	_check(int(GameState.club(kanto_top[0])["reputation"]) >= int(rep_before[kanto_top[0]]),
		"league champions gained standing")

	# rollover into season 2
	var age0 := int(GameState.player_club()["squad"][0].get("age_months", 0))
	guard = 0
	while GameState.season_no() < 2 and guard < 12:
		GameState.advance_day()
		guard += 1
	_check(GameState.season_no() == 2, "season counter rolled to 2")
	_check(GameState.season_start == Season.date_add(season1_start, 364)
		and GameState.current_date == GameState.season_start,
		"calendar rolled to the new preseason (%s)" % GameState.season_start)
	var s2_league: Array = GameState.fixtures.filter(func(f): return f["comp"] == "league")
	var s2_cup: Array = GameState.fixtures.filter(func(f): return f["comp"] == "cup")
	_check(s2_league.size() == 2 * 240 and s2_league.all(func(f): return not f["played"]),
		"fresh league fixtures for BOTH leagues (%d, none played)" % s2_league.size())
	_check(s2_cup.size() == 16 and str(s2_cup[0]["id"]).begins_with("S2"),
		"fresh cup draw with season-unique fixture ids (%s...)" % s2_cup[0]["id"])
	_check(int(GameState.player_club()["squad"][0].get("age_months", 0)) == age0 + 12,
		"ages ticked +12 months across the rollover")
	_check(not GameState.next_player_fixture().is_empty(),
		"Continue flows on: next player fixture %s" % GameState.next_player_fixture().get("date", "?"))
	_check(str(flow.phase) == "regular", "season_flow back in the regular phase")

	# history + season state survive save/load (JSON round-trip normalizes
	# ints to floats, so fingerprint the pre-save history the same way)
	var hist_json: String = JSON.stringify(JSON.parse_string(JSON.stringify(GameState.season_history())))
	_check(GameState.save_game(), "save across the boundary succeeds")
	GameState.new_career(99)   # wipe in-memory state
	_check(GameState.load_game(), "load across the boundary succeeds")
	_check(GameState.season_no() == 2, "loaded save is still season 2")
	_check(JSON.stringify(GameState.season_history()) == hist_json,
		"champions/awards history persists through save/load")
	var flow2: Variant = null
	for svc in GameState._services:
		if _svc_id(svc) == "season_flow":
			flow2 = svc
	_check(flow2 != null and str(flow2.phase) == "regular",
		"season_flow state restored from the save")
	# rollover moves current_date AFTER earlier-alphabet services already ticked
	# that day — advance once so every service has seen the season-2 calendar.
	GameState.advance_day()


## Complete every remaining league fixture + cup round with deterministic
## synthetic results and valid score-consistent detail stubs (no replays),
## then move the calendar to the final league matchday.
func _synth_complete_season() -> void:
	var last_league_date := ""
	var guard := 0
	while guard < 8:
		guard += 1
		var pending: Array = GameState.fixtures.filter(func(f): return not f["played"])
		for f in pending:
			var h := absi(str(f["id"]).hash())
			var home_wins := h % 2 == 0
			var loser_score := (h / 3) % 2
			f["played"] = true
			f["score_home"] = 2 if home_wins else loser_score
			f["score_away"] = loser_score if home_wins else 2
			f["detail"] = {"score_home": int(f["score_home"]), "score_away": int(f["score_away"]),
				"battles": [], "players": {}, "no_report": true}
			if f["comp"] == "league" and str(f["date"]) > last_league_date:
				last_league_date = str(f["date"])
		GameState._table_dirty = true
		GameState._maybe_generate_next_cup_round()
		if not GameState.fixtures.any(func(f): return not f["played"]):
			break
	if last_league_date != "" and last_league_date > GameState.current_date:
		GameState.current_date = last_league_date


## Service id, mirroring GameState._service_id (file basename fallback).
func _svc_id(svc: Object) -> String:
	if svc.has_method("service_id"):
		return str(svc.service_id())
	var script: Script = svc.get_script()
	if script != null:
		return str(script.resource_path.get_file().get_basename())
	return "service"


func _check_quiet(cond: bool, what: String) -> void:
	if not cond:
		printerr("  FAIL: %s" % what)
		_fail = true


## Sorted, int-normalized inventory fingerprint (JSON floats vs ints).
func _inv_norm(inv: Dictionary) -> String:
	var keys := inv.keys()
	keys.sort()
	var parts: Array = []
	for k in keys:
		parts.append("%s=%d" % [str(k), int(inv[k])])
	return ",".join(parts)


## DOUBLES (2v2) engine assertions: mode boot, targeting, spread scaling,
## ally-hitting field moves, per-slot event info and determinism.
func _doubles_checks() -> void:
	print("=== sim_check: doubles (2v2) engine ===")
	var mk_sides := func() -> Array:
		return [[_mkx(112, 50, ["Swift", "Earthquake", "Slash"], "Hardy", null),
			_mkx(143, 50, ["Body Slam", "Rest"], "Hardy", null),
			_mkx(25, 50, ["Thunderbolt", "Quick Attack"], "Hardy", null)],
			[_mkx(9, 55, ["Tackle"], "Hardy", null),
			_mkx(55, 55, ["Tackle"], "Hardy", null),
			_mkx(143, 55, ["Tackle"], "Hardy", null)]]
	var s: Array = mk_sides.call()
	var ed := BattleEngine.new(s[0], s[1], 2424, "doubles")
	_check(ed.is_doubles() and ed.slot_count() == 2, "doubles mode boots with 2 slots/side")
	var opens := ed.events.filter(func(ev): return ev["t"] == "switch" and ev.get("first", false))
	_check(opens.size() == 4 and opens.all(func(ev): return ev.has("slot")),
		"four opening send-outs, all with slot info")
	# single-target moves list both foes as choosable targets
	var slash: Dictionary = {}
	for a in ed.legal_actions_slot(0, 0):
		if a.get("type", "") == "move" and str(a.get("move", "")) == "Slash":
			slash = a
	_check(str(slash.get("targeting", "")) == "single" and slash.get("targets", []).size() == 2,
		"single-target move offers both foe slots as targets")
	var heal_all := func(eng: BattleEngine) -> void:
		for side in 2:
			for b in eng.team_state(side):
				b["hp"] = b["max_hp"]
	# targeted Slash hits exactly the chosen slot
	var evs1: Array = ed.step_turn([{"type": "move", "index": 2,
		"target": {"side": 1, "slot": 1}}, null], null)
	var hits1 := evs1.filter(func(ev): return ev["t"] == "damage" and ev.get("move", "") == "Slash")
	_check(hits1.size() == 1 and int(hits1[0].get("slot", -9)) == 1
		and int(hits1[0].get("by_slot", -9)) == 0,
		"targeted single move hit the chosen foe slot (with slot/by_slot info)")
	heal_all.call(ed)
	# spread move (Swift, never-miss) hits BOTH foes at 0.75x
	var evs2: Array = ed.step_turn([{"type": "move", "index": 0}, null], null)
	var hits2 := evs2.filter(func(ev): return ev["t"] == "damage" and ev.get("move", "") == "Swift")
	_check(hits2.size() == 2 and hits2.all(func(ev): return ev.get("spread", false)),
		"spread move hit both foes, damage flagged spread (0.75x)")
	heal_all.call(ed)
	# Earthquake hits both foes AND the user's ally
	var evs3: Array = ed.step_turn([{"type": "move", "index": 1}, null], null)
	var hits3 := evs3.filter(func(ev): return ev["t"] == "damage" and ev.get("move", "") == "Earthquake")
	var ally := hits3.filter(func(ev): return ev.get("ally_hit", false))
	_check(hits3.size() == 3 and ally.size() == 1,
		"Earthquake hit both foes + the ally (%d hits, %d ally)" % [hits3.size(), ally.size()])
	# doubles determinism: same teams + seed + mode => identical log
	var sa: Array = mk_sides.call()
	var sb: Array = mk_sides.call()
	var d1 := BattleEngine.new(sa[0], sa[1], 4321, "doubles")
	var d2 := BattleEngine.new(sb[0], sb[1], 4321, "doubles")
	var dl1 := d1.run_to_end()
	var dl2 := d2.run_to_end()
	_check(d1.is_over() and d1.winner() in [0, 1], "doubles battle finishes (winner=%d, turns=%d)" % [d1.winner(), d1.turn])
	_check(dl1.size() == dl2.size() and d1.winner() == d2.winner(),
		"doubles same seed => identical battle (%d events)" % dl1.size())


## Battler factory with explicit moves + nature (ability = species ability).
func _mkx(species_id: int, level: int, mvs: Array, nat: String, held: Variant) -> Dictionary:
	return DataStore.make_battler({"uid": "x%d_%d" % [species_id, level],
		"species_id": species_id, "nickname": null, "level": level,
		"ivs": {}, "moves": mvs, "held_item": held, "nature": nat})


## Quick battler factory for item tests (moves default to the learnset).
func _mk(species_id: int, level: int, held: Variant) -> Dictionary:
	return DataStore.make_battler({"uid": "t%d_%s" % [species_id, str(held)],
		"species_id": species_id, "nickname": null, "level": level,
		"ivs": {}, "moves": [], "held_item": held})
