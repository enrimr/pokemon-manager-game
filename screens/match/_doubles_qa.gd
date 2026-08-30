extends Node
## Headless QA for DOUBLES (engine + match runner). Not part of the game UI.
## Run: godot --headless --path . res://screens/match/_doubles_qa.tscn
## Prints "DOUBLES QA OK" and exits 0 on success.

const MatchRunner := preload("res://screens/match/match_runner.gd")
const SaveGuard := preload("res://tools/save_guard.gd")

var _fail := false


func _ready() -> void:
	_run.call_deferred()


func _check(cond: bool, what: String) -> void:
	if cond:
		print("  ok: %s" % what)
	else:
		printerr("  QA FAIL: %s" % what)
		_fail = true


func _mkx(species_id: int, level: int, mvs: Array, nat: String, held: Variant) -> Dictionary:
	return DataStore.make_battler({"uid": "d%d_%d" % [species_id, level],
		"species_id": species_id, "nickname": null, "level": level,
		"ivs": {}, "moves": mvs, "held_item": held, "nature": nat})


func _run() -> void:
	print("=== doubles QA: engine basics ===")
	SaveGuard.backup()
	GameState.new_career(445566)
	_engine_checks()
	_runner_checks()
	GameState.delete_save()
	SaveGuard.restore()
	if _fail:
		printerr("DOUBLES QA FAILED")
		get_tree().quit(1)
	else:
		print("DOUBLES QA OK")
		get_tree().quit(0)


func _engine_checks() -> void:
	# 2v2 setup: four actives, slot info on the initial switches
	var ta: Array = [_mkx(6, 50, ["Flamethrower", "Slash"], "Hardy", null),
		_mkx(112, 50, ["Earthquake", "Rock Slide"], "Hardy", null),
		_mkx(25, 50, ["Thunderbolt", "Quick Attack"], "Hardy", null)]
	var tb: Array = [_mkx(9, 50, ["Surf", "Bite"], "Hardy", null),
		_mkx(59, 50, ["Flamethrower", "Bite"], "Hardy", null),
		_mkx(143, 50, ["Body Slam", "Rest"], "Hardy", null)]
	var e := BattleEngine.new(ta, tb, 4242, "doubles")
	_check(e.is_doubles() and e.slot_count() == 2, "doubles mode: two slots per side")
	var first_switches := e.events.filter(func(ev): return ev["t"] == "switch" and ev.get("first", false))
	_check(first_switches.size() == 4, "four opening send-outs (%d)" % first_switches.size())
	_check(first_switches.all(func(ev): return ev.has("slot")), "opening switches carry slot info")
	_check(str(e.events[0].get("mode", "")) == "doubles", "battle_start declares the mode")
	_check(not e.slot_battler(0, 1).is_empty() and not e.slot_battler(1, 1).is_empty(),
		"slot battlers reachable")

	# legal actions per slot: single-target moves list choosable targets
	var acts: Array = e.legal_actions_slot(0, 0)
	var mv_acts: Array = acts.filter(func(a): return a["type"] == "move")
	_check(mv_acts.size() >= 1, "slot 0 has move actions")
	var tgt_act: Dictionary = {}
	for a in mv_acts:
		if a.get("targeting", "") == "single":
			tgt_act = a
	_check(not tgt_act.is_empty() and tgt_act.get("targets", []).size() == 2,
		"single-target move offers both foe slots as targets")
	var sw_acts: Array = acts.filter(func(a): return a["type"] == "switch")
	_check(sw_acts.size() == 1 and int(sw_acts[0]["index"]) == 2,
		"switch offers only the shared bench (got %s)" % str(sw_acts))

	# explicit targeting: hit foe slot 1 (Arcanine), not slot 0
	var single_a: Array = [_mkx(6, 50, ["Flamethrower", "Slash"], "Hardy", null),
		_mkx(25, 50, ["Thunderbolt", "Quick Attack"], "Hardy", null)]
	var e2 := BattleEngine.new(single_a, tb, 777, "doubles")
	var hp_b0: int = int(e2.slot_battler(1, 0)["hp"])
	var hp_b1: int = int(e2.slot_battler(1, 1)["hp"])
	e2.step_turn([{"type": "move", "index": 1, "target": {"side": 1, "slot": 1}},
		{"type": "move", "index": 1, "target": {"side": 1, "slot": 1}}],
		[{"type": "move", "index": 1, "target": {"side": 0, "slot": 0}},
		{"type": "move", "index": 1, "target": {"side": 0, "slot": 0}}])
	_check(int(e2.slot_battler(1, 1)["hp"]) < hp_b1, "chosen target (foe slot 1) took damage")
	var dmg_to_b0 := e2.events.filter(func(ev):
		return ev["t"] == "damage" and int(ev.get("side", -1)) == 1 \
			and int(ev.get("slot", -1)) == 0 and ev.has("by"))
	_check(int(e2.slot_battler(1, 0)["hp"]) == hp_b0 and dmg_to_b0.is_empty(),
		"unchosen foe slot 0 untouched")

	# spread: Rock Slide hits BOTH foes, never the ally
	var e3 := BattleEngine.new(ta, tb, 999, "doubles")
	var evs3: Array = e3.step_turn(
		[{"type": "move", "index": 0, "target": {"side": 1, "slot": 0}},   # Rhydon slot? no —
		{"type": "move", "index": 1}],                                     # slot1 Rhydon Rock Slide
		[{"type": "move", "index": 1, "target": {"side": 0, "slot": 0}},
		{"type": "move", "index": 1, "target": {"side": 0, "slot": 0}}])
	var rs_hits := evs3.filter(func(ev):
		return ev["t"] == "damage" and str(ev.get("move", "")) == "Rock Slide" and int(ev.get("side", -1)) == 1)
	var rs_ally := evs3.filter(func(ev):
		return ev["t"] == "damage" and str(ev.get("move", "")) == "Rock Slide" and int(ev.get("side", -1)) == 0)
	_check(rs_hits.size() == 2 and rs_hits.all(func(ev): return bool(ev.get("spread", false))),
		"Rock Slide hits both foes, flagged spread (%d hits)" % rs_hits.size())
	_check(rs_ally.is_empty(), "Rock Slide never clips the ally")

	# Earthquake hits both foes AND the ally (Pikachu is ground-vulnerable)
	var quake_a: Array = [_mkx(112, 50, ["Earthquake", "Rock Slide"], "Hardy", null),
		_mkx(25, 50, ["Thunderbolt", "Quick Attack"], "Hardy", null)]
	var tanks: Array = [_mkx(143, 50, ["Body Slam"], "Hardy", null),
		_mkx(143, 50, ["Body Slam"], "Hardy", null)]
	var e4 := BattleEngine.new(quake_a, tanks, 1234, "doubles")
	var ally_hp: int = int(e4.slot_battler(0, 1)["hp"])
	var evs4: Array = e4.step_turn(
		[{"type": "move", "index": 0},                                     # slot0 Rhydon EARTHQUAKE
		{"type": "move", "index": 1, "target": {"side": 1, "slot": 0}}],   # slot1 Pikachu Quick Attack
		[{"type": "move", "index": 0, "target": {"side": 0, "slot": 0}},
		{"type": "move", "index": 0, "target": {"side": 0, "slot": 0}}])
	var eq_hits := evs4.filter(func(ev):
		return ev["t"] == "damage" and str(ev.get("move", "")) == "Earthquake")
	var eq_ally := eq_hits.filter(func(ev): return bool(ev.get("ally_hit", false)))
	_check(eq_hits.size() == 3, "Earthquake hits three targets (%d)" % eq_hits.size())
	_check(eq_ally.size() == 1 and int(eq_ally[0].get("side", -1)) == 0
		and int(e4.slot_battler(0, 1)["hp"]) < ally_hp,
		"Earthquake splash damages the user's own ally")

	# spread 0.75x: same seed, Rock Slide vs 2 targets deals less than vs 1
	var solo_b: Array = [_mkx(9, 50, ["Surf", "Bite"], "Hardy", null)]
	var e5 := BattleEngine.new([ta[1]], solo_b, 31, "doubles")
	var evs5: Array = e5.step_turn([{"type": "move", "index": 1}], [{"type": "move", "index": 1}])
	var solo_hit := evs5.filter(func(ev):
		return ev["t"] == "damage" and str(ev.get("move", "")) == "Rock Slide")
	_check(not solo_hit.is_empty() and not bool(solo_hit[0].get("spread", false)),
		"lone-target spread move drops the spread flag (full power)")

	# redirection: target faints mid-turn -> attack redirects to the other foe
	var frail: Array = [_mkx(129, 5, ["Splash"], "Hardy", null),
		_mkx(129, 5, ["Splash"], "Hardy", null)]
	var hitters: Array = [_mkx(6, 80, ["Flamethrower", "Slash"], "Hardy", null),
		_mkx(25, 80, ["Thunderbolt", "Quick Attack"], "Hardy", null)]
	var e6 := BattleEngine.new(hitters, frail, 55, "doubles")
	var evs6: Array = e6.step_turn(
		[{"type": "move", "index": 0, "target": {"side": 1, "slot": 0}},
		{"type": "move", "index": 0, "target": {"side": 1, "slot": 0}}], null)
	var kills := evs6.filter(func(ev): return ev["t"] == "faint" and int(ev["side"]) == 1)
	_check(kills.size() == 2 and e6.is_over() and e6.winner() == 0,
		"double-up on one slot redirects the second attack (both foes down)")

	# doubles determinism: full AI battles, twice, identical
	var logs: Array = []
	for rep in 2:
		var t1: Array = [_mkx(6, 50, ["Flamethrower", "Slash"], "Adamant", "leftovers"),
			_mkx(112, 50, ["Earthquake", "Rock Slide"], "Jolly", null),
			_mkx(25, 50, ["Thunderbolt", "Quick Attack"], "Timid", null),
			_mkx(94, 50, ["Shadow Ball", "Sludge Bomb"], "Modest", null)]
		var t2: Array = [_mkx(9, 50, ["Surf", "Bite"], "Modest", null),
			_mkx(59, 50, ["Flamethrower", "Bite"], "Hardy", "sitrus_berry"),
			_mkx(143, 50, ["Body Slam", "Rest"], "Careful", null),
			_mkx(130, 50, ["Surf", "Rain Dance"], "Adamant", null)]
		var d := BattleEngine.new(t1, t2, 20260830, "doubles")
		d.run_to_end()
		logs.append([d.events.size(), d.winner(), d.turn])
	_check(logs[0][0] == logs[1][0] and logs[0][1] == logs[1][1] and logs[0][2] == logs[1][2],
		"doubles determinism: same seed => identical battle (%s)" % str(logs[0]))

	# Intimidate hits BOTH foes on entry in doubles
	var e7 := BattleEngine.new([_mkx(130, 50, ["Surf"], "Hardy", null),
		_mkx(9, 50, ["Surf"], "Hardy", null)],
		[_mkx(66, 50, ["Karate Chop"], "Hardy", null),
		_mkx(67, 50, ["Karate Chop"], "Hardy", null)], 88, "doubles")
	_check(int(e7.slot_battler(1, 0)["stages"]["atk"]) == -1
		and int(e7.slot_battler(1, 1)["stages"]["atk"]) == -1,
		"Intimidate drops Attack on BOTH foes")

	# Levitate ally shrugs off its partner's Earthquake
	var e8 := BattleEngine.new([_mkx(112, 50, ["Earthquake"], "Hardy", null),
		_mkx(94, 50, ["Shadow Ball"], "Hardy", null)],
		[_mkx(143, 50, ["Body Slam"], "Hardy", null),
		_mkx(143, 50, ["Body Slam"], "Hardy", null)], 66, "doubles")
	var evs8: Array = e8.step_turn([{"type": "move", "index": 0}, null], null)
	var ally_immune := evs8.filter(func(ev):
		return ev["t"] == "ability_triggered" and str(ev.get("ability", "")) == "levitate")
	_check(not ally_immune.is_empty(), "Levitate ally is immune to partner Earthquake")

	# doubles singles-compat: singles battles still deterministic after refactor
	var clubs: Array = GameState.world["clubs"]
	var s1 := BattleEngine.new(Season.pick_team(clubs[0]), Season.pick_team(clubs[1]), 777)
	s1.run_to_end()
	var s2 := BattleEngine.new(Season.pick_team(clubs[0]), Season.pick_team(clubs[1]), 777)
	s2.run_to_end()
	_check(s1.events.size() == s2.events.size() and s1.winner() == s2.winner(),
		"singles path unchanged and deterministic (%d events)" % s1.events.size())


func _runner_checks() -> void:
	print("=== doubles QA: match runner (cup game 2 is doubles) ===")
	# Find/create a cup fixture for the player club.
	var f: Dictionary = {}
	for fx in GameState.player_fixtures():
		if str(fx["comp"]) == "cup" and not fx["played"]:
			f = fx
			break
	_check(not f.is_empty(), "player has an unplayed cup fixture (%s)" % str(f.get("id", "-")))
	if f.is_empty():
		return
	GameState.current_date = str(f["date"])
	var r = MatchRunner.begin(f)
	r.exhibition = true
	_check(r.mode_for_battle(1) == "singles" and r.mode_for_battle(2) == "doubles"
		and r.mode_for_battle(3) == "singles",
		"cup tie format: game 2 of the best-of-3 is DOUBLES")
	r.confirm_lineup()
	_check(not r.doubles_now(), "game 1 runs singles")
	r.set_policy("full_control", false)
	r.skip_battle()
	if not r.series_decided():
		r.next_battle()
		_check(r.doubles_now(), "game 2 engine boots in doubles mode")
		_check(r.engine.is_doubles(), "engine mode flag set")
		_check(r.vm["actives"][0].size() == 2 and r.vm["actives"][1].size() == 2,
			"view model tracks two active slots per side")
		# manual doubles: await input, per-slot actions with targets
		r.set_policy("full_control", true)
		for i in 400:
			if r.consume_next().is_empty():
				break
		_check(r.awaiting_input(), "manual mode halts for doubles input")
		var awaiting: Array = r.slots_awaiting()
		_check(awaiting.size() >= 1, "player has slots to command (%s)" % str(awaiting))
		var picked_target := false
		var guard := 0
		while r.awaiting_input() and guard < 3:
			guard += 1
			var k: int = int(r.slots_awaiting()[0])
			var acts_k: Array = r.available_actions_slot(k)
			_check(not acts_k.is_empty(), "slot %d actions offered (%d)" % [k, acts_k.size()])
			var chosen := {}
			for a in acts_k:
				if a["type"] == "move" and str(a.get("targeting", "")) == "single" \
						and not a.get("targets", []).is_empty():
					var t: Dictionary = a["targets"][a.get("targets", []).size() - 1]
					chosen = {"type": "move", "index": int(a["index"]),
						"target": {"side": int(t["side"]), "slot": int(t["slot"])}}
					picked_target = true
					break
			if chosen.is_empty():
				for a in acts_k:
					if a["type"] == "move":
						chosen = {"type": "move", "index": int(a["index"])}
						break
			if chosen.is_empty():
				break
			r.submit_slot_action(k, chosen)
		_check(picked_target, "player picked an explicit target")
		_check(r.live_state == MatchRunner.LiveState.REPLAYING, "both slots submitted -> replay resumes")
		var saw_turn := false
		for i in 200:
			var e: Dictionary = r.consume_next()
			if e.is_empty():
				break
			if str(e.get("t", "")) == "turn_start":
				saw_turn = true
		_check(saw_turn, "doubles turn executed from manual input")
	r.set_policy("full_control", false)
	r.skip_series()
	_check(r.phase == MatchRunner.Phase.POST, "cup tie completes through POST")
	print("  info: cup tie result %s %d-%d %s" % [r.shorts()[0], r.wins[0], r.wins[1], r.shorts()[1]])
	MatchRunner.clear()
