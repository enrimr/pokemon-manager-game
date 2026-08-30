extends Node
## Screenshot-prep harness (competition piece, headless): builds a career
## sitting right AFTER the Championship Series Final + awards ceremony (the
## off-season week), so the playoff bracket, History tab and season-end header
## can be captured. Writes user://save.json — the runner script backs up and
## restores the player's real save around this.
## Run: godot --headless --path . res://screens/competition/season_shot_prep.tscn


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	GameState.delete_save()
	GameState.new_career(20260830)
	# real sims first so awards come from genuine match ratings
	for i in 50:
		GameState.advance_day()
	# synthetically complete the remaining league/cup slate (valid stubs)
	var last_league_date := ""
	var guard := 0
	while guard < 8:
		guard += 1
		for f in GameState.fixtures:
			if f["played"]:
				continue
			var h := absi(str(f["id"]).hash())
			var home_wins := h % 2 == 0
			var loser := (h / 3) % 2
			f["played"] = true
			f["score_home"] = 2 if home_wins else loser
			f["score_away"] = loser if home_wins else 2
			f["detail"] = {"score_home": int(f["score_home"]), "score_away": int(f["score_away"]),
				"battles": [], "players": {}, "no_report": true}
			if f["comp"] == "league" and str(f["date"]) > last_league_date:
				last_league_date = str(f["date"])
		GameState._table_dirty = true
		GameState._maybe_generate_next_cup_round()
		if not GameState.fixtures.any(func(f): return not f["played"]):
			break
	if last_league_date > GameState.current_date:
		GameState.current_date = last_league_date
	# advance through the Series for real, stop once the ceremony has fired
	guard = 0
	while GameState.season_history().is_empty() and guard < 40:
		GameState.advance_day()
		guard += 1
	if GameState.season_history().is_empty():
		printerr("SEASON SHOT PREP FAILED: no ceremony")
		get_tree().quit(1)
		return
	GameState.save_game()
	print("SEASON SHOT PREP OK (date %s, season %d, history %d)" % [
		GameState.current_date, GameState.season_no(), GameState.season_history().size()])
	get_tree().quit(0)
