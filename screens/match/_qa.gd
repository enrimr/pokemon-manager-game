extends Node
## Headless QA for the match piece (not part of the game UI).
## Run: godot --headless --path . res://screens/match/_qa.tscn
## Back up user://save.json first if you care about it — this mutates state,
## then deletes the save it wrote.

const MatchRunner := preload("res://screens/match/match_runner.gd")

var _fail := false


func _ready() -> void:
	_run.call_deferred()


func _check(cond: bool, what: String) -> void:
	if cond:
		print("  ok: %s" % what)
	else:
		printerr("  QA FAIL: %s" % what)
		_fail = true


func _run() -> void:
	print("=== match QA: full interactive flow (headless) ===")
	GameState.new_career(112233)
	var f: Dictionary = GameState.next_player_fixture()
	_check(not f.is_empty(), "found player fixture %s" % str(f.get("id")))
	GameState.current_date = str(f["date"])
	_check(not MatchRunner.pending_fixture().is_empty(), "pending_fixture sees due fixture")

	var r = MatchRunner.begin(f)
	_check(r.phase == MatchRunner.Phase.PRE, "runner starts in PRE")
	_check(r.starting_six.size() == 6, "default starting six picked")
	_check(r.opp_six.size() == 6, "opponent six scouted")

	# lineup adjust: swap order
	var tmp = r.starting_six[0]
	r.starting_six[0] = r.starting_six[1]
	r.starting_six[1] = tmp
	r.confirm_lineup()
	_check(r.phase == MatchRunner.Phase.LIVE, "confirm -> LIVE")
	_check(r.vm["teams"][r.player_side][0]["name"] == DataStore.make_battler(r.starting_six[0])["name"],
		"lead honours adjusted order")

	# touchline policies while consuming
	r.set_policy("aggression", "attacking")
	var consumed := 0
	while consumed < 25:
		var e: Dictionary = r.consume_next()
		if e.is_empty():
			break
		consumed += 1
	_check(consumed > 10, "policy-driven replay produced events (%d)" % consumed)
	r.set_policy("aggression", "balanced")

	# force switch
	var bench_idx := -1
	for i in r.vm["teams"][r.player_side].size():
		var b: Dictionary = r.vm["teams"][r.player_side][i]
		if not b["fainted"] and i != r.vm["active"][r.player_side]:
			bench_idx = i
			break
	if bench_idx >= 0 and r.live_state == MatchRunner.LiveState.REPLAYING:
		r.force_switch(bench_idx)
		var found_switch := false
		for i in 40:
			var e2: Dictionary = r.consume_next()
			if e2.is_empty():
				break
			if str(e2.get("t")) == "switch" and int(e2.get("side", -1)) == r.player_side:
				found_switch = true
				break
		_check(found_switch, "forced switch executed")

	# full control: await + submit
	r.set_policy("full_control", true)
	for i in 400:
		if r.consume_next().is_empty():
			break
	if r.live_state == MatchRunner.LiveState.AWAIT_INPUT:
		_check(r.awaiting_input(), "full control halts for input")
		var acts: Array = r.available_actions()
		_check(acts.size() > 0, "available_actions non-empty (%d)" % acts.size())
		var has_preview := false
		for a in acts:
			if a["type"] == "move" and not a.get("preview", {}).is_empty():
				has_preview = true
		_check(has_preview, "move previews present")
		r.submit_action(acts[0])
		_check(r.live_state == MatchRunner.LiveState.REPLAYING, "submit resumes replay")
	r.set_policy("full_control", false)

	# run out the series
	var inbox_before: int = GameState.inbox.size()
	r.skip_series()
	_check(r.phase == MatchRunner.Phase.POST, "series ends in POST")
	_check(r.series_decided(), "series decided %d-%d" % [r.wins[0], r.wins[1]])
	_check(bool(f["played"]), "fixture marked played")
	_check(int(f["score_home"]) == r.wins[0] and int(f["score_away"]) == r.wins[1],
		"fixture score matches watched result")
	_check(GameState.inbox.size() == inbox_before + 1, "match report added to inbox")
	_check(str(GameState.inbox[0]["title"]).begins_with("Match report"), "report title correct")
	var in_table := false
	for row in GameState.league_table():
		if GameState.is_player_club(str(row["club_id"])) and int(row["played"]) >= 1:
			in_table = true
	_check(in_table, "league table reflects the result")
	_check(not r.momentum.is_empty(), "momentum samples recorded (%d)" % r.momentum.size())
	_check(not r.ticker.is_empty(), "ticker lines generated (%d)" % r.ticker.size())
	_check(not r.key_events.is_empty(), "key events captured (%d)" % r.key_events.size())
	var rows: Array = r.rating_rows(r.player_side)
	_check(rows.size() > 0, "player ratings computed (%d rows)" % rows.size())
	var sane := true
	for row in rows:
		if float(row["rating"]) < 4.0 or float(row["rating"]) > 10.0:
			sane = false
	_check(sane, "ratings within bounds")
	var motm: Dictionary = r.man_of_the_match()
	_check(not motm.is_empty(), "man of the match: %s (%.1f)" % [motm.get("name"), motm.get("rating", 0.0)])
	print("  info: final %s %d-%d %s, battles=%s" % [r.shorts()[0], r.wins[0], r.wins[1],
		r.shorts()[1], str(r.battles)])

	# determinism guard: engine still deterministic through policy wrapper
	var t_a: Array = Season.pick_team(GameState.world["clubs"][2])
	var t_b: Array = Season.pick_team(GameState.world["clubs"][3])
	var e_1 := BattleEngine.new(t_a, t_b, 55)
	var e_2 := BattleEngine.new(t_a, t_b, 55)
	while not e_1.is_over():
		e_1.step_turn(e_1.choose_action_policy(0, {"aggression": "cautious", "switching": "eager"}), null)
	while not e_2.is_over():
		e_2.step_turn(e_2.choose_action_policy(0, {"aggression": "cautious", "switching": "eager"}), null)
	_check(e_1.winner() == e_2.winner() and e_1.events.size() == e_2.events.size(),
		"choose_action_policy is deterministic")

	GameState.delete_save()
	if _fail:
		printerr("MATCH QA FAILED")
		get_tree().quit(1)
	else:
		print("MATCH QA OK")
		get_tree().quit(0)
