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

	print("=== sim_check: save/load roundtrip ===")
	var date_before_save: String = GameState.current_date
	var fixtures_count := GameState.fixtures.size()
	_check(GameState.save_game(), "save_game succeeds")
	GameState.new_career(1)  # wipe in-memory state
	_check(GameState.load_game(), "load_game succeeds")
	_check(GameState.current_date == date_before_save, "loaded date matches (%s)" % GameState.current_date)
	_check(GameState.fixtures.size() == fixtures_count, "loaded fixture count matches (%d)" % fixtures_count)
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
