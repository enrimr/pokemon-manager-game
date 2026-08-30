extends VBoxContainer
## CHAMPIONSHIP SERIES tab — the mechanism behind the table's top-four zone.
## Before matchday 30 completes: the qualification race (both leagues' top
## four as it stands) + format explainer. Once the playoff is live: the seeded
## cross-league bracket round by round, and the Indigo Champion when crowned.

const UI := preload("res://screens/competition/ui.gd")
const TB := preload("res://shared/theme/theme_builder.gd")

const GOLD := Color(0.83, 0.68, 0.21)

var _status: Label
var _scroll: ScrollContainer
var _body: VBoxContainer


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.add_child(UI.label(Season.PLAYOFF_NAME.to_upper(), 16, Color.WHITE))
	var lgs := HBoxContainer.new()
	lgs.add_theme_constant_override("separation", 4)
	lgs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for lg in GameState.leagues():
		lgs.add_child(UI.league_chip(str(lg["id"])))
	head.add_child(lgs)
	head.add_child(UI.dim("top four of each league · seeded knockout · winner is %s" %
		Season.INDIGO_TITLE, 12))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	_status = UI.dim("", 12)
	head.add_child(_status)
	add_child(head)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 10)
	_scroll.add_child(_body)


## Competition-switcher hook (cross-league competition — context is inert).
func set_league_context(_lg: String, _cup: bool) -> void:
	pass


func refresh() -> void:
	for c in _body.get_children():
		c.queue_free()
	var po: Array = Season.playoff_fixtures(GameState.fixtures)
	if po.is_empty():
		_render_race()
	else:
		_render_bracket(po)


# ------------------------------------------------- before the playoff exists

func _render_race() -> void:
	var last := Season.latest_completed_league_round(
		GameState.fixtures.filter(func(f): return f["comp"] == "league"))
	var total := Season.total_league_rounds(GameState.fixtures)
	_status.text = "qualification race · after matchday %d of %d" % [maxi(last, 0), total]

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	for lg in GameState.leagues():
		row.add_child(_race_card(str(lg["id"])))
	row.add_child(_format_card())
	_body.add_child(row)
	_body.add_child(_honours_note())


func _race_card(lid: String) -> Control:
	var card := UI.card("%s · TOP FOUR AS IT STANDS" % GameState.league_name(lid).to_upper())
	card.custom_minimum_size.x = 380
	var body := UI.card_body(card)
	var table: Array = GameState.league_table(lid)
	for i in mini(6, table.size()):
		var r: Dictionary = table[i]
		var cid := str(r["club_id"])
		var club: Dictionary = GameState.club(cid)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		var in_zone := i < 4
		var pos := UI.label(str(i + 1), 12, (GOLD if i == 0 else UI.COL_WIN) if in_zone else TB.COL_TEXT_DIM)
		pos.custom_minimum_size.x = 20
		pos.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(pos)
		var m := UI.monogram(club, 16, 8)
		h.add_child(m)
		var col := TB.COL_ACCENT.lightened(0.35) if GameState.is_player_club(cid) \
			else (Color.WHITE if in_zone else TB.COL_TEXT_DIM)
		var nm := UI.link(str(club.get("name", cid)), 12, col,
			{"kind": "club", "id": cid}, "%s — view club profile" % club.get("name", cid))
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(nm)
		h.add_child(UI.dim("%d pts" % int(r["points"]), 12))
		body.add_child(h)
		if i == 3:
			var sep := HSeparator.new()
			sep.tooltip_text = "Qualification line — top four go through"
			body.add_child(sep)
	return card


func _format_card() -> Control:
	var card := UI.card("HOW IT WORKS")
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_FILL
	var body := UI.card_body(card)
	var last_md := Season.date_add(GameState.season_start,
		Season.LEAGUE_ROUND_OFFSET + (Season.total_league_rounds(GameState.fixtures) - 1) * Season.LEAGUE_ROUND_STEP)
	for line in [
		"After matchday 30, positions 1-4 of the Kanto and Johto",
		"championships enter a seeded cross-league knockout:",
		"",
		"  Quarter-finals   %s" % UI.short_date(Season.date_add(last_md, 7)),
		"  Semi-finals      %s" % UI.short_date(Season.date_add(last_md, 14)),
		"  Final            %s" % UI.short_date(Season.date_add(last_md, 21)),
		"",
		"Seeding keeps the two league champions apart: each plays",
		"the other league's 4th, so they can only meet in the Final.",
		"Every tie is decided like a matchday: best of three battles.",
		"",
		"The Final's winner is crowned %s — the" % Season.INDIGO_TITLE,
		"season's true champion, recorded forever in History.",
	]:
		body.add_child(UI.dim(str(line), 12))
	return card


func _honours_note() -> Control:
	var hist: Array = GameState.season_history()
	if hist.is_empty():
		return UI.dim("No %s has been crowned yet — this season's Final will be the first."
			% Season.INDIGO_TITLE, 12)
	var last: Dictionary = hist[hist.size() - 1]
	var ind: Dictionary = last.get("indigo", {})
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.add_child(UI.dim("Reigning %s:" % Season.INDIGO_TITLE, 12))
	h.add_child(UI.link(str(ind.get("name", "?")), 13, GOLD.lightened(0.25),
		{"kind": "club", "id": str(ind.get("champion", ""))}, "View club profile"))
	h.add_child(UI.dim("(Season %d — full honours in the History tab)" % int(last.get("season", 1)), 12))
	return h


# ------------------------------------------------------- the live bracket

func _render_bracket(po: Array) -> void:
	var max_round := 0
	for f in po:
		max_round = maxi(max_round, int(f["round"]))
	var final_f := {}
	for f in po:
		if int(f["round"]) == 3 and f["played"]:
			final_f = f

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	for r in range(1, 4):
		row.add_child(_round_card(po, r))
	row.add_child(_champion_card(final_f))
	_body.add_child(row)
	_body.add_child(UI.dim("Seeding: each league champion opens against the other league's 4th "
		+ "place; ties are best-of-3 battles, no replays. The Final crowns the %s." % Season.INDIGO_TITLE, 12))

	if not final_f.is_empty():
		var champ := GameState.club(Season.fixture_winner(final_f))
		_status.text = "%s are the %s" % [champ.get("name", "?"), Season.INDIGO_TITLE]
	else:
		var current: Array = po.filter(func(f): return int(f["round"]) == max_round)
		var pending: Array = current.filter(func(f): return not f["played"])
		_status.text = "%s · %s" % [Season.playoff_round_name(max_round),
			"complete — next round pending" if pending.is_empty()
			else "ties on %s" % Season.pretty_date(str(pending[0]["date"]))]


func _round_card(po: Array, round_no: int) -> Control:
	var ties: Array = po.filter(func(f): return int(f["round"]) == round_no)
	ties.sort_custom(func(x, y): return str(x["id"]) < str(y["id"]))
	var title := Season.playoff_round_name(round_no).to_upper()
	if not ties.is_empty():
		title += " · %s" % UI.short_date(str(ties[0]["date"]))
	var card := UI.card(title)
	card.custom_minimum_size.x = 330
	var body := UI.card_body(card)
	if ties.is_empty():
		var n := 4 / int(pow(2, round_no - 1))
		for i in n:
			body.add_child(UI.dim("Winners of %s ties" % Season.playoff_round_name(round_no - 1), 12))
		return card
	for f in ties:
		body.add_child(_tie_line(f))
		if f != ties.back():
			body.add_child(HSeparator.new())
	return card


func _tie_line(f: Dictionary) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	var winner := Season.fixture_winner(f)
	for side in 2:
		var cid: String = str(f["home"] if side == 0 else f["away"])
		var club: Dictionary = GameState.club(cid)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		h.add_child(UI.monogram(club, 16, 8))
		var chip := UI.league_chip(GameState.league_of(cid), 8)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(chip)
		var col := TB.COL_TEXT
		if GameState.is_player_club(cid):
			col = TB.COL_ACCENT.lightened(0.35)
		elif winner == cid:
			col = Color.WHITE
		elif winner != "":
			col = TB.COL_TEXT_DIM
		var nm := UI.link(str(club.get("name", cid)), 12, col,
			{"kind": "club", "id": cid}, "%s — view club profile" % club.get("name", cid))
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(nm)
		var score_txt: String = str(int(f["score_home"] if side == 0 else f["score_away"])) \
			if f["played"] else "-"
		h.add_child(UI.link(score_txt, 12, Color.WHITE if winner == cid else TB.COL_TEXT_DIM,
			{"kind": "fixture", "id": str(f["id"])},
			"Go to match report" if f["played"] else "Go to fixture preview"))
		v.add_child(h)
	return v


func _champion_card(final_f: Dictionary) -> Control:
	var card := UI.card("%s" % Season.INDIGO_TITLE.to_upper())
	card.custom_minimum_size.x = 250
	var body := UI.card_body(card)
	if final_f.is_empty():
		body.add_child(UI.dim("To be decided in the Final.", 12))
		return card
	var cid := Season.fixture_winner(final_f)
	var club := GameState.club(cid)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var m := UI.monogram(club, 30, 12)
	m.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(m)
	h.add_child(UI.club_link(club, 14, GOLD.lightened(0.3)))
	var chip := UI.league_chip(GameState.league_of(cid))
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(chip)
	body.add_child(h)
	body.add_child(UI.dim("Season %d %s" % [GameState.season_no(), Season.INDIGO_TITLE], 11))
	return card
