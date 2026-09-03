extends Node
## Headless functional check for promotion/relegation (promotion piece).
## Fabricates a completed regular season (deterministic synthetic scores, no
## battle sims), then drives SeasonFlowService's stage/apply directly. Run:
##   godot --headless --path . res://tools/promo_check.tscn

const SaveGuard := preload("res://tools/save_guard.gd")

var _fails := 0


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ok: %s" % what)
	else:
		_fails += 1
		printerr("  FAIL: %s" % what)


func _ready() -> void:
	SaveGuard.backup()
	GameState.new_career(4242)

	# ---- structure
	_check(GameState.leagues().size() == 4, "four divisions in the world")
	_check(GameState.league_club_ids("kanto2").size() == 12, "kanto2 has 12 clubs")

	# ---- fabricate a finished regular season (bounded scores, deterministic)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for f in GameState.fixtures:
		if str(f["comp"]) != "league":
			continue
		f["played"] = true
		f["score_home"] = int(rng.randi() % 3)
		f["score_away"] = int(rng.randi() % 3)
		if f["score_home"] == f["score_away"]:
			f["score_home"] += 1   # league battles have no draws
	GameState._table_dirty = true
	_check(Season.league_complete(GameState.fixtures), "regular season complete")

	var svc: SeasonFlowService = SeasonFlowService.instance
	_check(svc != null, "season flow service running")

	# ---- stage: 2 down + 2 up per region, mails announced
	svc._stage_promotion_relegation(GameState)
	_check(svc.pending_moves.size() == 8, "8 staged moves (2 up + 2 down per region)")
	var t_k: Array = GameState.league_table("kanto")
	var bottom2 := [str(t_k[14]["club_id"]), str(t_k[15]["club_id"])]
	var down_ids := svc.pending_moves.filter(func(m): return m["from"] == "kanto") \
		.map(func(m): return str(m["club_id"]))
	_check(bottom2.all(func(c): return down_ids.has(c)), "kanto bottom two are the relegated pair")
	var t_k2: Array = GameState.league_table("kanto2")
	var up_ids := svc.pending_moves.filter(func(m): return m["from"] == "kanto2") \
		.map(func(m): return str(m["club_id"]))
	_check(up_ids.has(str(t_k2[0]["club_id"])) and up_ids.has(str(t_k2[1]["club_id"])),
		"kanto2 top two are the promoted pair")
	_check(GameState.inbox.any(func(m): return str(m["title"]).contains("promotion and relegation")),
		"announcement mail lands in the inbox")

	# ---- apply: memberships swap, division sizes hold
	svc._apply_pending_moves(GameState)
	_check(svc.pending_moves.is_empty(), "moves consumed on apply")
	_check(GameState.league_of(bottom2[0]) == "kanto2" and GameState.league_of(bottom2[1]) == "kanto2",
		"relegated clubs now play in kanto2")
	for cid in up_ids:
		_check(GameState.league_of(str(cid)) == "kanto", "promoted club %s now plays in kanto" % cid)
	_check(GameState.league_club_ids("kanto").size() == 16 and GameState.league_club_ids("kanto2").size() == 12,
		"division sizes stable after the swap")
	_check(GameState.league_club_ids("johto").size() == 16 and GameState.league_club_ids("johto2").size() == 12,
		"johto pyramid stable too")

	# ---- playoff pool stays top-flight after the swap
	var lgs_t1: Array = GameState.leagues().filter(func(lg): return int(lg.get("tier", 1)) == 1)
	_check(lgs_t1.size() == 2, "exactly two top flights feed the Championship Series")

	# ---- old-save migration: strip the D2s, sanitizer injects them back
	GameState.world["meta"]["leagues"] = [
		{"id": "kanto", "name": "Kanto League"}, {"id": "johto", "name": "Johto League"}]
	GameState.world["clubs"] = GameState.world["clubs"].filter(func(c):
		return str(c.get("league", "")) in ["kanto", "johto"])
	GameState._index_clubs()
	GameState._ensure_league_state()
	_check(GameState.leagues().size() == 4, "migration restores four divisions")
	_check(GameState.all_club_ids().size() == 56, "migration injects the D2 clubs")
	_check(GameState.league_tier("kanto") == 1 and GameState.region_of_league("kanto2") == "kanto",
		"migrated leagues carry tier + region")
	_check(GameState.inbox.any(func(m): return str(m["title"]).contains("pyramid")),
		"migration announces itself in the inbox")

	SaveGuard.restore()
	print("PROMO CHECK OK" if _fails == 0 else "PROMO CHECK FAILED (%d)" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
