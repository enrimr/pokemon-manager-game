extends Node
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	await get_tree().process_frame
	preload("res://tools/save_guard.gd").backup()
	GameState.new_career()
	GameState.auto_sim_player_matches = true
	var before := {}
	var lv_before := 0
	for m in GameState.player_club()["squad"]:
		before[m["uid"]] = int(m["level"])
		lv_before += int(m["level"])
	for i in 90:
		GameState.advance_day()
	var lv_after := 0
	var ups := 0
	for m in GameState.player_club()["squad"]:
		lv_after += int(m["level"])
		if int(m["level"]) > int(before.get(m["uid"], 99)):
			ups += 1
	var fixture_ups := 0
	for f in GameState.fixtures:
		if f.get("played", false) and (f.get("level_ups", []) as Array).size() > 0:
			fixture_ups += 1
	# AI clubs level too
	var ai_lv := 0
	var ai_cnt := 0
	for c in GameState.world["clubs"]:
		if GameState.is_player_club(str(c["id"])):
			continue
		for m in c["squad"]:
			ai_lv += int(m.get("xp", 0) > 0)
			ai_cnt += 1
	print("player squad level sum: %d -> %d (+%d), %d mons levelled" % [lv_before, lv_after, lv_after - lv_before, ups])
	print("player fixtures with recorded level_ups: %d" % fixture_ups)
	print("AI mons with xp earned: %d / %d" % [ai_lv, ai_cnt])
	preload("res://tools/save_guard.gd").restore()
	get_tree().quit(0)
