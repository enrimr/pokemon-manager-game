extends Node
## Headless verification that competition match data has a SINGLE SOURCE OF
## TRUTH: the detail dict persisted on each fixture at play time. Run:
##   Godot --headless --path . res://screens/competition/integrity_check.tscn -- --mode=sim
##   Godot --headless --path . res://screens/competition/integrity_check.tscn -- --mode=verify
## Modes:
##   sim     — fresh career, fast-forward until 30+ fixtures are played, verify
##             every match report agrees with its recorded score, save.
##   verify  — boot from the existing save (a SECOND process = second boot, or
##             a legacy save stripped of details) and re-verify 100% agreement,
##             that details are the persisted dicts (stats/POTM source), and
##             that legacy fixtures were migrated (adopted or score-only stub).
## Prints "INTEGRITY OK" and exits 0 on success.
##
## WARNING: uses the real user://save.json — back it up before running.

var _fails := 0


func _check(cond: bool, what: String) -> void:
	if cond:
		print("  ok: %s" % what)
	else:
		_fails += 1
		printerr("  FAIL: %s" % what)


func _ready() -> void:
	var mode := "verify"
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--mode="):
			mode = str(a).split("=")[1]
	await get_tree().process_frame   # let autoloads finish booting
	if mode == "sim":
		_run_sim()
	else:
		_run_verify()
	if _fails == 0:
		print("INTEGRITY OK")
	get_tree().quit(0 if _fails == 0 else 1)


## Fresh career; sim until 30+ fixtures are played; verify; save.
func _run_sim() -> void:
	GameState.new_career()
	var guard := 0
	while _played().size() < 34 and guard < 80:
		guard += 1
		GameState.advance_day()
	var played := _played()
	print("  simmed %d played fixtures over %d days" % [played.size(), guard])
	_check(played.size() >= 30, "30+ fixtures played (%d)" % played.size())
	_verify_all(played, false)
	_check(GameState.save_game(), "career saved")


## Booted from save (autoload already loaded it). Verify integrity again.
func _run_verify() -> void:
	var played := _played()
	print("  loaded save: %d played fixtures" % played.size())
	_check(played.size() >= 30, "save has 30+ played fixtures (%d)" % played.size())
	_verify_all(played, true)


func _played() -> Array:
	return GameState.fixtures.filter(func(f): return f.get("played", false))


func _verify_all(played: Array, from_save: bool) -> void:
	var agree := 0
	var stubs := 0
	var persisted := 0
	for f in played:
		# 1) every played fixture carries a persisted detail dict
		var stored: Variant = f.get("detail")
		var has_stored: bool = stored is Dictionary and stored.has("players") and stored.has("battles")
		if has_stored:
			persisted += 1
		# 2) the report NEVER contradicts the recorded score
		var d: Dictionary = Season.fixture_detail(f)
		var ok_score: bool = not d.is_empty() \
			and int(d["score_home"]) == int(f["score_home"]) \
			and int(d["score_away"]) == int(f["score_away"])
		# 3) battle list is internally consistent with the score
		var ok_battles := true
		if not d.get("no_report", false):
			var hw := 0
			var aw := 0
			for b in d["battles"]:
				if int(b["winner"]) == 0:
					hw += 1
				else:
					aw += 1
			ok_battles = hw == int(f["score_home"]) and aw == int(f["score_away"])
		else:
			stubs += 1
		if ok_score and ok_battles:
			agree += 1
		else:
			_fails += 1
			printerr("  FAIL: %s recorded %d-%d but report says %s" % [
				f["id"], int(f["score_home"]), int(f["score_away"]), str(d)])
		# 4) the report IS the persisted dict (fixture_detail returned/installed it)
		if not (f.get("detail") is Dictionary and Season.fixture_detail(f) == f["detail"]):
			_fails += 1
			printerr("  FAIL: %s fixture_detail is not the persisted detail" % f["id"])
	print("  reports agreeing with recorded score: %d/%d (stubs: %d, persisted pre-boot: %d)" % [
		agree, played.size(), stubs, persisted])
	_check(agree == played.size(), "100%% of match reports agree with recorded scores")
	if from_save:
		_check(persisted == played.size() or stubs > 0,
			"details persisted in the save (or migrated legacy fixtures present)")

	# 5) season stats / POTM derive ONLY from persisted details: aggregating the
	# persisted dicts by hand must reproduce Season.season_player_stats exactly.
	var manual := {}
	for f in played:
		var d: Dictionary = f["detail"]
		for uid in d["players"]:
			Season._merge_player_stats(manual, str(uid), d["players"][uid])
	var stats: Dictionary = Season.season_player_stats(GameState.fixtures)
	var same := stats.size() == manual.size()
	for uid in stats:
		if not manual.has(uid):
			same = false
			break
		for k in ["battles", "wins", "kos", "dmg", "taken", "faints"]:
			if int(stats[uid][k]) != int(manual[uid][k]):
				same = false
		if absf(float(stats[uid]["rating_sum"]) - float(manual[uid]["rating_sum"])) > 0.001:
			same = false
	_check(same, "season stats identical to manual aggregate of persisted details (%d battlers)" % stats.size())

	# 6) POTM per fixture comes from the persisted players dict
	var potm_checked := 0
	for f in played:
		var d: Dictionary = f["detail"]
		if (d["players"] as Dictionary).is_empty():
			continue
		var via_detail := _potm(Season.fixture_detail(f)["players"])
		var via_stored := _potm(d["players"])
		if via_detail != via_stored:
			_fails += 1
			printerr("  FAIL: %s POTM differs between report and persisted detail" % f["id"])
		potm_checked += 1
	_check(potm_checked > 0, "POTM verified against persisted details on %d fixtures" % potm_checked)


func _potm(players: Dictionary) -> String:
	var best := ""
	var best_r := -1.0
	for uid in players:
		var p: Dictionary = players[uid]
		var r := float(p["rating_sum"]) / maxi(int(p["battles"]), 1)
		if r > best_r:
			best_r = r
			best = str(uid)
	return best
