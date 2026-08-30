extends Node
## Headless QA for the match piece (not part of the game UI).
## Run: godot --headless --path . res://screens/match/_qa.tscn
## Runs a destructive throwaway career, but the player's real user://save.json
## is backed up and restored via tools/save_guard.gd (like the other dev tools).

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


func _run() -> void:
	print("=== match QA: full interactive flow (headless) ===")
	SaveGuard.backup()
	GameState.new_career(112233)
	var f: Dictionary = GameState.next_player_fixture()
	_check(not f.is_empty(), "found player fixture %s" % str(f.get("id")))
	GameState.current_date = str(f["date"])
	_check(not MatchRunner.pending_fixture().is_empty(), "pending_fixture sees due fixture")

	# guarantee an always-legal usable item (xstat targets the active slot)
	var buy_err: String = GameState.buy_item("x_attack", 1)
	_check(buy_err == "", "bought X Attack for the match bag (%s)" % ("ok" if buy_err == "" else buy_err))

	var r = MatchRunner.begin(f)
	_check(r.phase == MatchRunner.Phase.PRE, "runner starts in PRE")
	_check(bool(r.policy["full_control"]), "manual combat is the default policy")
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

	# bags wired into the engine
	_check(not r.series_bag[r.player_side].is_empty(), "player match bag loaded (%s)" % str(r.series_bag[r.player_side]))
	_check(int(r.engine.inventory(r.player_side).get("x_attack", 0)) >= 1, "engine sees the bag")

	# touchline policies while consuming (watch mode)
	r.set_policy("full_control", false)
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
		var item_act := {}
		for a in acts:
			if a["type"] == "move" and not a.get("preview", {}).is_empty():
				has_preview = true
			if a["type"] == "use_item" and item_act.is_empty():
				item_act = a
		_check(has_preview, "move previews present")
		_check(not item_act.is_empty(), "use_item action offered (%s)" % str(item_act.get("item", "")))
		if not item_act.is_empty():
			var bag_before: int = int(r.series_bag[r.player_side].get(str(item_act["item"]), 0))
			r.submit_action({"type": "use_item", "item": str(item_act["item"]),
				"target": int(item_act["target"])})
			var saw_item_used := false
			for i in 60:
				var e3: Dictionary = r.consume_next()
				if e3.is_empty():
					break
				if str(e3.get("t")) == "item_used" and int(e3.get("side", -1)) == r.player_side:
					saw_item_used = true
					break
			_check(saw_item_used, "item_used event replayed for our side")
			_check(int(r.series_bag[r.player_side].get(str(item_act["item"]), 0)) == bag_before - 1,
				"series bag decremented")
			_check(int(r.used_items[r.player_side].get(str(item_act["item"]), 0)) >= 1,
				"used_items records the spend")
		else:
			r.submit_action(acts[0])
		_check(r.live_state == MatchRunner.LiveState.REPLAYING, "submit resumes replay")
	r.set_policy("full_control", false)

	# run out the series
	var inbox_before: int = GameState.inbox.size()
	var store_before: Dictionary = GameState.player_inventory().duplicate(true)
	r.skip_series()
	_check(r.phase == MatchRunner.Phase.POST, "series ends in POST")
	_check(r.series_decided(), "series decided %d-%d" % [r.wins[0], r.wins[1]])
	_check(bool(f["played"]), "fixture marked played")
	_check(int(f["score_home"]) == r.wins[0] and int(f["score_away"]) == r.wins[1],
		"fixture score matches watched result")
	_check(GameState.inbox.size() == inbox_before + 1, "match report added to inbox")
	var consumed_ok := true
	for iid in r.used_items[r.player_side]:
		var expect: int = int(store_before.get(str(iid), 0)) - int(r.used_items[r.player_side][iid])
		if int(GameState.player_inventory().get(str(iid), 0)) != maxi(0, expect):
			consumed_ok = false
	_check(consumed_ok, "club store debited for items used (%s)" % str(r.used_items[r.player_side]))
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
	SaveGuard.restore()
	if _fail:
		printerr("MATCH QA FAILED")
		get_tree().quit(1)
	else:
		print("MATCH QA OK")
		get_tree().quit(0)
