extends Node
## Headless end-to-end check of the season + battle engines.
## Run: godot --headless --path . res://tools/sim_check.tscn
## Prints "SIM CHECK OK" and exits 0 on success; exits 1 on any failure.

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


func _run() -> void:
	print("=== sim_check: battle engine determinism ===")
	GameState.delete_save()
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

	print("=== sim_check: 50-day season fast-forward ===")
	var start_date: String = GameState.current_date
	for i in 50:
		GameState.advance_day()
	_check(GameState.current_date == Season.date_add(start_date, 50),
		"calendar advanced 50 days -> %s" % GameState.current_date)

	var played := GameState.fixtures.filter(func(f): return f["played"])
	var league_played := played.filter(func(f): return f["comp"] == "league")
	var cup_played := played.filter(func(f): return f["comp"] == "cup")
	_check(league_played.size() >= 40, "league fixtures simulated (%d played)" % league_played.size())
	_check(cup_played.size() >= 8, "cup round 1 simulated (%d cup ties played)" % cup_played.size())
	_check(GameState.cup_round >= 2, "next cup round drawn (cup_round=%d)" % GameState.cup_round)
	for f in played:
		if f["score_home"] == f["score_away"]:
			_check(false, "no draws allowed, got %s" % str(f))
			break

	var table: Array = GameState.league_table()
	_check(table.size() == 16, "table has 16 rows")
	var total_played := 0
	for row in table:
		total_played += int(row["played"])
		_check_quiet(int(row["points"]) == int(row["won"]) * 3, "points = 3*wins for %s" % row["club_id"])
	_check(total_played == league_played.size() * 2, "table played counts match fixtures")
	var top: Dictionary = table[0]
	print("  info: leader after 50 days: %s with %d pts (%d played)" %
		[GameState.club(top["club_id"])["name"], top["points"], top["played"]])
	_check(GameState.player_table_position() > 0, "player club in table (pos %d)" % GameState.player_table_position())
	_check(GameState.inbox.size() > 1, "inbox has match reports (%d messages)" % GameState.inbox.size())

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
	_check(GameState.save_game(), "save_game succeeds")
	GameState.new_career(1)  # wipe in-memory state
	_check(GameState.load_game(), "load_game succeeds")
	_check(GameState.current_date == date_before_save, "loaded date matches (%s)" % GameState.current_date)
	_check(GameState.fixtures.size() == fixtures_count, "loaded fixture count matches (%d)" % fixtures_count)
	_check(_inv_norm(GameState.player_inventory()) == inv_before_save,
		"loaded item inventory matches")
	GameState.delete_save()

	if _fail:
		printerr("SIM CHECK FAILED")
		get_tree().quit(1)
	else:
		print("SIM CHECK OK")
		get_tree().quit(0)


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


## Quick battler factory for item tests (moves default to the learnset).
func _mk(species_id: int, level: int, held: Variant) -> Dictionary:
	return DataStore.make_battler({"uid": "t%d_%s" % [species_id, str(held)],
		"species_id": species_id, "nickname": null, "level": level,
		"ivs": {}, "moves": [], "held_item": held})
