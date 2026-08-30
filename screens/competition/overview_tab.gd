extends VBoxContainer
## SEASON OVERVIEW tab — round status, next matchday, title race, cup, form.

const UI := preload("res://screens/competition/ui.gd")
const TB := preload("res://shared/theme/theme_builder.gd")

var _grid: GridContainer


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_grid)


func refresh() -> void:
	for c in _grid.get_children():
		c.queue_free()
	# cross-league season desk: both championships' title races + the cup
	_grid.add_child(_season_card())
	_grid.add_child(_next_matchday_card())
	_grid.add_child(_cup_card())
	for lg in GameState.leagues():
		_grid.add_child(_title_race_card(str(lg["id"]), str(lg["name"])))
	_grid.add_child(_recent_card())


func _sized(card: PanelContainer) -> PanelContainer:
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 250)
	return card


func _season_card() -> PanelContainer:
	var card := _sized(UI.card("Season"))
	var body := UI.card_body(card)
	var fixtures: Array = GameState.fixtures
	var battles := 0
	for f in fixtures:
		if f["played"]:
			battles += int(f["score_home"]) + int(f["score_away"])
	# matchday progress is YOUR championship's; battles count the whole world
	var league_fx := Season.league_fixtures(fixtures, GameState.player_league_id())
	var total := Season.total_league_rounds(league_fx)
	var completed := 0
	for f in league_fx:
		if f["played"]:
			completed = maxi(completed, int(f["round"]))
	var played_fx: int = league_fx.filter(func(f): return f["played"]).size()

	body.add_child(UI.label(str(GameState.league_name()), 15, Color.WHITE))
	body.add_child(UI.dim("Season %s · %d leagues of 16 · double round-robin · %s" % [
		GameState.season_start.split("-")[0], GameState.leagues().size(), GameState.cup_name()], 12))
	body.add_child(UI.vspace(2))
	var pb := ProgressBar.new()
	pb.min_value = 0
	pb.max_value = total
	pb.value = completed
	pb.show_percentage = false
	pb.custom_minimum_size.y = 10
	body.add_child(pb)
	body.add_child(UI.kv_row("Current matchday", "%d of %d" % [maxi(completed, 0), total]))
	body.add_child(UI.kv_row("League matches played", "%d / %d" % [played_fx, league_fx.size()]))
	body.add_child(UI.kv_row("Battles fought (all regions)", str(battles)))
	body.add_child(UI.kv_row("Today", "%s %s" % [UI.weekday(GameState.current_date),
		Season.pretty_date(GameState.current_date)]))
	body.add_child(UI.kv_row("First matchday", Season.pretty_date(
		Season.date_add(GameState.season_start, Season.LEAGUE_ROUND_OFFSET))))
	body.add_child(UI.kv_row("Final matchday", Season.pretty_date(
		Season.date_add(GameState.season_start, Season.LEAGUE_ROUND_OFFSET + (total - 1) * Season.LEAGUE_ROUND_STEP))))
	return card


func _next_matchday_card() -> PanelContainer:
	var card := _sized(UI.card("Next Matchday"))
	var body := UI.card_body(card)
	var today: String = GameState.current_date
	var upcoming: Array = GameState.fixtures.filter(func(f): return not f["played"] and f["date"] > today)
	if upcoming.is_empty():
		body.add_child(UI.dim("Season complete — awards done, the next season\nstarts after the off-season break (see your Inbox).", 13))
		return card
	upcoming.sort_custom(func(a, b): return a["date"] < b["date"])
	var next_date: String = upcoming[0]["date"]
	var day_fx := upcoming.filter(func(f): return f["date"] == next_date)
	var days := Season.days_between(today, next_date)
	var comp_lbl: String = "Matchday %d" % int(day_fx[0]["round"])
	if day_fx[0]["comp"] == "cup":
		comp_lbl = "Cup %s" % Season.cup_round_name(int(day_fx[0]["round"]))
	elif day_fx[0]["comp"] == "playoff":
		comp_lbl = "%s %s" % [Season.PLAYOFF_NAME, Season.playoff_round_name(int(day_fx[0]["round"]))]

	body.add_child(UI.label("%s %s" % [UI.weekday(next_date), Season.pretty_date(next_date)], 15, Color.WHITE))
	body.add_child(UI.kv_row("In", "%d day%s" % [days, "" if days == 1 else "s"],
		UI.COL_WIN if days <= 2 else TB.COL_TEXT))
	body.add_child(UI.kv_row("Competition", comp_lbl))
	body.add_child(UI.kv_row("Fixtures that day", str(day_fx.size())))
	body.add_child(UI.vspace(2))

	var nf := GameState.next_player_fixture()
	if nf.is_empty():
		body.add_child(UI.dim("You have no remaining fixtures.", 12))
	else:
		var we_home: bool = GameState.is_player_club(nf["home"])
		var opp := GameState.club(nf["away"] if we_home else nf["home"])
		body.add_child(UI.dim("YOUR NEXT MATCH", 11))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(UI.monogram(opp, 24, 10))
		var l := UI.link("%s (%s)" % [opp["name"], "H" if we_home else "A"], 13,
			TB.COL_TEXT, {"kind": "club", "id": str(opp["id"])},
			"%s — view club profile" % opp["name"])
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(UI.link(UI.short_date(nf["date"]), 12, TB.COL_TEXT_DIM,
			{"kind": "fixture", "id": str(nf["id"])}, "Go to fixture preview"))
		body.add_child(row)
		var form := Season.club_form(opp["id"], GameState.fixtures, 5)
		if not form.is_empty():
			var fr := HBoxContainer.new()
			fr.add_theme_constant_override("separation", 8)
			fr.add_child(UI.dim("Their form", 12))
			fr.add_child(UI.form_pips(form, 14))
			body.add_child(fr)
	return card


func _title_race_card(league_id: String, league_name: String) -> PanelContainer:
	var is_ours := league_id == GameState.player_league_id()
	var card := _sized(UI.card("%s · Title Race" % league_name))
	var body := UI.card_body(card)
	var table: Array = GameState.league_table(league_id)
	if table.is_empty():
		return card
	var leader_pts := int(table[0]["points"])
	for i in mini(4, table.size()):
		var row: Dictionary = table[i]
		var club := GameState.club(row["club_id"])
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		var pos := UI.dim(str(i + 1), 12)
		pos.custom_minimum_size.x = 16
		h.add_child(pos)
		h.add_child(UI.monogram(club, 20, 9))
		var is_player := GameState.is_player_club(row["club_id"])
		var name := UI.club_link(club, 13,
			TB.COL_ACCENT.lightened(0.35) if is_player else (Color.WHITE if i == 0 else TB.COL_TEXT))
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(name)
		var gap := leader_pts - int(row["points"])
		h.add_child(UI.dim("-%d" % gap if gap > 0 else "", 12))
		h.add_child(UI.label("%d pts" % int(row["points"]), 13, Color.WHITE))
		body.add_child(h)
	body.add_child(UI.vspace(2))
	if is_ours:
		var ppos := GameState.player_table_position()
		var prow: Dictionary = {}
		for r in table:
			if GameState.is_player_club(r["club_id"]):
				prow = r
				break
		if not prow.is_empty():
			var gap_p := leader_pts - int(prow["points"])
			body.add_child(HSeparator.new())
			body.add_child(UI.kv_row("Your position",
				"—" if int(prow.get("played", 0)) == 0 else _ord(ppos), TB.COL_ACCENT.lightened(0.35)))
			body.add_child(UI.kv_row("Gap to top", "%d pt%s" % [gap_p, "" if gap_p == 1 else "s"],
				UI.COL_WIN if gap_p == 0 else TB.COL_TEXT))
	else:
		# the other region's race: how tight is it at the top?
		body.add_child(HSeparator.new())
		if table.size() >= 2 and int(table[0]["played"]) > 0:
			var margin := int(table[0]["points"]) - int(table[1]["points"])
			body.add_child(UI.kv_row("Lead at the top", "%d pt%s" % [margin, "" if margin == 1 else "s"],
				UI.COL_WIN if margin >= 6 else TB.COL_TEXT))
		var lb := UI.link("Open the %s table ›" % league_name, 12, TB.COL_TEXT_DIM,
			{"kind": "league", "id": league_id}, "Browse the %s" % league_name)
		body.add_child(lb)
	return card


func _cup_card() -> PanelContainer:
	var card := _sized(UI.card("%s · Cross-League Knockout" % GameState.cup_name()))
	var body := UI.card_body(card)
	var cup: Array = GameState.fixtures.filter(func(f): return f["comp"] == "cup")
	if cup.is_empty():
		body.add_child(UI.dim("Draw not yet made.", 13))
		return card
	var max_round := 0
	for f in cup:
		max_round = maxi(max_round, int(f["round"]))
	var first_count: int = cup.filter(func(f): return int(f["round"]) == 1).size()
	var total_rounds := 1
	var nties := first_count
	while nties > 1:
		nties = nties / 2
		total_rounds += 1
	var current := cup.filter(func(f): return int(f["round"]) == max_round)
	body.add_child(UI.kv_row("Clubs in the draw", "%d · both leagues" % (first_count * 2)))
	body.add_child(UI.kv_row("Current round", "%s (%d of %d)" % [
		Season.cup_round_name(max_round), max_round, total_rounds]))
	body.add_child(UI.kv_row("Round date", Season.pretty_date(current[0]["date"])))

	var pid: String = GameState.world["meta"]["player_club_id"]
	var status := ""
	var status_col := TB.COL_TEXT
	var final_played: bool = max_round >= total_rounds and not current.any(func(f): return not f["played"])
	var our_ties := cup.filter(func(f): return f["home"] == pid or f["away"] == pid)
	var eliminated := false
	var elim_round := 0
	var elim_by := ""
	for f in our_ties:
		if f["played"] and Season.fixture_winner(f) != pid:
			eliminated = true
			elim_round = int(f["round"])
			elim_by = f["away"] if f["home"] == pid else f["home"]
	if final_played and Season.fixture_winner(current[0]) == pid:
		status = "CHAMPIONS!"
		status_col = Color(0.95, 0.83, 0.4)
	elif eliminated:
		status = "Eliminated in %s by %s" % [Season.cup_round_name(elim_round),
			GameState.club(elim_by).get("short", elim_by)]
		status_col = UI.COL_LOSS
	else:
		status = "Still in the cup"
		status_col = UI.COL_WIN
	body.add_child(UI.kv_row("Your status", status, status_col))
	var our_next := our_ties.filter(func(f): return not f["played"])
	if not our_next.is_empty():
		var nf: Dictionary = our_next[0]
		var we_home: bool = nf["home"] == pid
		var opp_id: String = str(nf["away"] if we_home else nf["home"])
		var opp := GameState.club(opp_id)
		body.add_child(UI.kv_link_row("Your tie", "%s [%s] (%s) · %s" % [opp.get("short", "?"),
			UI.league_tag(GameState.league_of(opp_id)),
			"H" if we_home else "A", UI.short_date(nf["date"])],
			{"kind": "fixture", "id": str(nf["id"])}))
	var alive: int = 0
	if not current.is_empty():
		var winners := {}
		for f in current:
			if f["played"]:
				winners[Season.fixture_winner(f)] = true
		alive = winners.size() if not current.any(func(f): return not f["played"]) else current.size() * 2
	body.add_child(UI.kv_row("Clubs remaining", str(alive)))
	body.add_child(UI.link("Open the bracket ›", 12, TB.COL_TEXT_DIM,
		{"kind": "tab", "id": "cup"}, "Go to the cup bracket"))
	return card


func _recent_card() -> PanelContainer:
	var card := _sized(UI.card("Your Recent Results"))
	var body := UI.card_body(card)
	var pid: String = GameState.world["meta"]["player_club_id"]
	var played := GameState.player_fixtures().filter(func(f): return f["played"])
	if played.is_empty():
		body.add_child(UI.dim("No matches played yet.", 13))
		var nf := GameState.next_player_fixture()
		if not nf.is_empty():
			var we_home: bool = nf["home"] == pid
			var opp := GameState.club(nf["away"] if we_home else nf["home"])
			var first := HBoxContainer.new()
			first.add_theme_constant_override("separation", 4)
			first.add_child(UI.dim("First up:", 12))
			first.add_child(UI.link("%s (%s)" % [opp["name"], "H" if we_home else "A"],
				12, TB.COL_TEXT, {"kind": "club", "id": str(opp["id"])}))
			first.add_child(UI.dim("on %s." % Season.pretty_date(nf["date"]), 12))
			body.add_child(first)
		return card
	played.sort_custom(func(a, b): return a["date"] > b["date"])
	for f in played.slice(0, 5):
		var we_home: bool = f["home"] == pid
		var us: int = int(f["score_home"]) if we_home else int(f["score_away"])
		var them: int = int(f["score_away"]) if we_home else int(f["score_home"])
		var opp := GameState.club(f["away"] if we_home else f["home"])
		var won := us > them
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		h.add_child(UI.form_pips(["W" if won else "L"], 15))
		var lab := UI.link("%d-%d vs %s (%s)" % [us, them, opp["short"], "H" if we_home else "A"],
			13, Color.WHITE if won else TB.COL_TEXT_DIM,
			{"kind": "fixture", "id": str(f["id"])}, "Go to match report")
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(lab)
		var tag := "LGE"
		if f["comp"] == "cup":
			tag = "CUP"
		elif f["comp"] == "playoff":
			tag = "CS"
		h.add_child(UI.dim("%s · %s" % [tag, UI.short_date(f["date"])], 11))
		body.add_child(h)
	return card


func _ord(n: int) -> String:
	if n <= 0:
		return "-"
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1: suffix = "st"
			2: suffix = "nd"
			3: suffix = "rd"
	return "%d%s" % [n, suffix]
