extends Node
## Headless verification of the multi-league competition UI logic against live
## simmed data: independent per-league tables, cross-league cup draw, no stat
## bleed between the leagues, and the screen-level competition switcher. Run:
##   Godot --headless --path . res://screens/competition/league_check.tscn
## Prints "LEAGUE CHECK OK" and exits 0 on success.
## WARNING: starts a fresh career in user://save.json.

var _fails := 0


func _check(cond: bool, what: String) -> void:
	if cond:
		print("  ok: %s" % what)
	else:
		_fails += 1
		printerr("  FAIL: %s" % what)


func _ready() -> void:
	await _run()
	if _fails == 0:
		print("LEAGUE CHECK OK")
	get_tree().quit(0 if _fails == 0 else 1)


func _run() -> void:
	var shell: Node = load("res://shell/main.tscn").instantiate()
	add_child(shell)
	await get_tree().process_frame
	await get_tree().process_frame
	GameState.new_career(4242)
	var guard := 0
	while guard < 60 and GameState.fixtures.filter(func(f): return f["played"]).size() < 80:
		guard += 1
		GameState.advance_day()
	print("  simmed %d days, %d fixtures played" % [guard,
		GameState.fixtures.filter(func(f): return f["played"]).size()])

	# --- both leagues' tables fill independently
	var ids_k: Array = GameState.league_club_ids("kanto")
	var ids_j: Array = GameState.league_club_ids("johto")
	_check(ids_k.size() == 16 and ids_j.size() == 16, "16 clubs per league")
	var overlap := ids_k.filter(func(id): return ids_j.has(id))
	_check(overlap.is_empty(), "league club sets are disjoint")
	for lg in [["kanto", ids_k], ["johto", ids_j]]:
		var table: Array = GameState.league_table(lg[0])
		_check(table.size() == 16, "%s table has 16 rows" % lg[0])
		var played_rows := 0
		var foreign := 0
		for r in table:
			played_rows += int(r["played"])
			if not (lg[1] as Array).has(r["club_id"]):
				foreign += 1
		var lg_played: int = Season.league_fixtures(GameState.fixtures, lg[0]) \
			.filter(func(f): return f["played"]).size()
		_check(foreign == 0, "%s table contains only its own clubs" % lg[0])
		_check(played_rows == 2 * lg_played,
			"%s table played counts match its fixtures exactly (%d rows vs %d fx)" % [lg[0], played_rows, lg_played])
		_check(played_rows > 0, "%s championship has been played" % lg[0])

	# --- cup draw mixes leagues
	var cup1: Array = GameState.fixtures.filter(func(f):
		return f["comp"] == "cup" and int(f["round"]) == 1)
	_check(cup1.size() == 16, "cup first round has 16 ties (32 clubs)")
	var cross := 0
	for f in cup1:
		if GameState.league_of(str(f["home"])) != GameState.league_of(str(f["away"])):
			cross += 1
	_check(cross > 0, "cup draw mixes the leagues (%d cross-league ties)" % cross)

	# --- no stat bleed: per-league club stats only credit that league's clubs
	var stats_k: Dictionary = Season.season_club_stats(ids_k, GameState.fixtures, "league")
	var bleed := false
	var total_matches := 0
	for cid in stats_k:
		if not ids_k.has(cid):
			bleed = true
		total_matches += int(stats_k[cid]["matches"])
	var lg_played_k: int = Season.league_fixtures(GameState.fixtures, "kanto") \
		.filter(func(f): return f["played"]).size()
	_check(not bleed, "kanto club stats contain no johto club")
	_check(total_matches == 2 * lg_played_k,
		"kanto league-only stats sum to kanto fixtures (%d vs %d)" % [total_matches, lg_played_k])

	# --- position history is per-league (cache must not cross-contaminate)
	var hist_k: Dictionary = Season.position_history(ids_k, Season.league_fixtures(GameState.fixtures, "kanto"))
	var hist_j: Dictionary = Season.position_history(ids_j, Season.league_fixtures(GameState.fixtures, "johto"))
	_check(not hist_k.is_empty() and not hist_j.is_empty(), "position history computed for both leagues")
	_check(not hist_k.has(ids_j[0]) and not hist_j.has(ids_k[0]),
		"position histories keyed by their own league's clubs only")

	# --- competition switcher drives the whole screen
	shell.navigate_to("competition")
	await get_tree().process_frame
	var screen: Node = shell._current_screen_instance()
	_check(screen != null and screen.has_method("comp_set_league"), "screen exposes comp_set_league")
	if screen == null:
		return
	screen.comp_set_league("johto")
	await get_tree().process_frame
	_check(str(screen._comp_ctx) == "johto", "context switched to johto")
	_check(str(screen._hdr_title.text) == GameState.league_name("johto").to_upper(),
		"header title follows the browsed league")
	_check(str(screen._views["table"].league_id) == "johto", "table tab received the league context")
	screen._select_tab("table")
	await get_tree().process_frame
	var tree: Tree = screen._views["table"]._tree
	var seen_clubs := 0
	var wrong := 0
	var item := tree.get_root().get_first_child()
	while item != null:
		seen_clubs += 1
		var md: Variant = item.get_metadata(2)
		if md is Dictionary and not ids_j.has(str(md.get("id", ""))):
			wrong += 1
		item = item.get_next()
	_check(seen_clubs == 16 and wrong == 0, "johto table renders exactly the 16 johto clubs")

	screen.comp_set_league("cup")
	await get_tree().process_frame
	_check(screen._current != "table", "cup context leaves the league table tab")
	_check(screen._tab_buttons["table"].disabled, "league table tab disabled for the cup")
	screen.comp_set_league("kanto")
	await get_tree().process_frame
	_check(not screen._tab_buttons["table"].disabled, "table tab restored for a league")
	_check(str(screen._views["fixtures"].league_id) == "kanto", "fixtures tab follows the switcher")

	# stats tab region scope: johto scope must contain no kanto club rows
	var stats_tab: Node = screen._views["stats"]
	stats_tab.set_league_context("johto", false)
	var trows: Array = stats_tab._build_team_rows("all")
	var bad := trows.filter(func(r): return not ids_j.has(str(r["cid"])))
	_check(trows.size() == 16 and bad.is_empty(), "stats teams rows scoped to johto only")
	var prows: Array = stats_tab._build_rows("all")
	var badp := prows.filter(func(r): return str(r.get("lg", "")) != "johto")
	_check(not prows.is_empty() and badp.is_empty(), "stats player rows scoped to johto only")
	stats_tab.set_league_context("", false)   # merge view via "" scope? (All Regions)
	stats_tab._set_option(stats_tab._lg_sel, "")
	var arows: Array = stats_tab._build_team_rows("all")
	_check(arows.size() == 32, "all-regions merge shows all 32 clubs")
	GameState.delete_save()
