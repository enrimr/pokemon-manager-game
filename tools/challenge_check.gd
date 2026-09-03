extends Node
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	await get_tree().process_frame
	preload("res://tools/save_guard.gd").backup()
	GameState.new_career()
	var svc = ChallengeService.instance
	var fails := 0
	if svc == null:
		printerr("FAIL: service not loaded"); fails += 1
	else:
		# force-spawn each tier deterministically
		var rng := RandomNumberGenerator.new()
		rng.seed = 42
		svc._spawn(rng, GameState.current_date)
		var ch: Dictionary = svc.pending()
		if ch.is_empty():
			printerr("FAIL: no challenge spawned"); fails += 1
		else:
			print("  ok: spawned %s (tier %s, team %d, Lv~%d, prize %d)" % [
				svc._title(ch), ch["tier"], (ch["team"] as Array).size(), ch["level"], ch["money"]])
			var err := str(svc.accept())
			if err != "":
				printerr("FAIL accept: " + err); fails += 1
			else:
				var MR = load("res://screens/match/match_runner.gd")
				var r = MR.active
				r.confirm_lineup()
				r.instant_result()
				var bal_before := int(GameState.player_club()["finances"]["balance"])
				var inv_before := GameState.player_inventory().duplicate()
				svc.settle(r)
				var won: bool = r.player_won()
				var bal_after := int(GameState.player_club()["finances"]["balance"])
				print("  ok: exhibition resolved (%s), balance %+d" % ["WON" if won else "LOST", bal_after - bal_before])
				if won and bal_after <= bal_before:
					printerr("FAIL: won but no prize"); fails += 1
				if not won and bal_after != bal_before:
					printerr("FAIL: lost but money moved"); fails += 1
				var inv_now: Dictionary = GameState.player_inventory()
				var gained := 0
				for iid in inv_now:
					gained += int(inv_now[iid]) - int(inv_before.get(iid, 0))
				print("  ok: items gained: %d" % gained)
				if not svc.pending().is_empty():
					printerr("FAIL: pending not cleared"); fails += 1
				MR.clear()
		# league table untouched by the exhibition
		var played_league := 0
		for f in GameState.fixtures:
			if f.get("played", false):
				played_league += 1
		if played_league > 0:
			printerr("FAIL: exhibition leaked into fixtures"); fails += 1
		else:
			print("  ok: league fixtures untouched")
	preload("res://tools/save_guard.gd").restore()
	print("CHALLENGE CHECK %s" % ("OK" if fails == 0 else "FAILED"))
	get_tree().quit(0 if fails == 0 else 1)
