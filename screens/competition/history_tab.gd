extends VBoxContainer
## HISTORY tab — the permanent record: one card per completed season with the
## Indigo Champion, both league champions, the cup winner, individual awards
## and your own finish. Written by the season_flow service at every ceremony.

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
	head.add_child(UI.label("HONOURS & HISTORY", 16, Color.WHITE))
	head.add_child(UI.dim("champions, awards and records — one entry per completed season", 12))
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


func set_league_context(_lg: String, _cup: bool) -> void:
	pass


func refresh() -> void:
	for c in _body.get_children():
		c.queue_free()
	var hist: Array = GameState.season_history()
	_status.text = "Season %d in progress · %d completed season%s on record" % [
		GameState.season_no(), hist.size(), "" if hist.size() == 1 else "s"]
	if hist.is_empty():
		_body.add_child(UI.dim("No season has finished yet. History is written at the "
			+ "end-of-season ceremony:\nleague champions, the %s bracket, the %s winners, "
			% [Season.PLAYOFF_NAME, GameState.cup_name()]
			+ "Pokémon of the Season and Best Developer\nall land here permanently — and carry across seasons and saves.", 13))
		_body.add_child(_roll_of_honour([]))
		return
	_body.add_child(_roll_of_honour(hist))
	for i in range(hist.size() - 1, -1, -1):   # latest season first
		_body.add_child(_season_card(hist[i]))


## Compact all-time list: Indigo Champions by season.
func _roll_of_honour(hist: Array) -> Control:
	var card := UI.card("%s ROLL OF HONOUR" % Season.INDIGO_TITLE.to_upper())
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body := UI.card_body(card)
	if hist.is_empty():
		body.add_child(UI.dim("Nobody has been crowned yet.", 12))
		return card
	for i in range(hist.size() - 1, -1, -1):
		var e: Dictionary = hist[i]
		var ind: Dictionary = e.get("indigo", {})
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		var season_l := UI.dim("Season %d" % int(e.get("season", i + 1)), 12)
		season_l.custom_minimum_size.x = 76
		h.add_child(season_l)
		var cid := str(ind.get("champion", ""))
		h.add_child(UI.monogram(GameState.club(cid), 16, 8))
		h.add_child(UI.link(str(ind.get("name", "?")), 13, GOLD.lightened(0.25),
			{"kind": "club", "id": cid}, "View club profile"))
		var chip := UI.league_chip(GameState.league_of(cid), 8)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(chip)
		h.add_child(UI.dim("def. %s in the Final" % str(ind.get("runner_up_name", "?")), 11))
		body.add_child(h)
	return card


func _season_card(e: Dictionary) -> Control:
	var card := UI.card("SEASON %d · %s to %s" % [int(e.get("season", 1)),
		Season.pretty_date(str(e.get("start", "?"))), Season.pretty_date(str(e.get("end", "?")))])
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body := UI.card_body(card)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 4)
	body.add_child(grid)

	var ind: Dictionary = e.get("indigo", {})
	grid.add_child(UI.dim(Season.INDIGO_TITLE, 12))
	grid.add_child(_club_line(str(ind.get("champion", "")), str(ind.get("name", "?")), GOLD.lightened(0.25)))
	for lg in GameState.leagues():
		var lid := str(lg["id"])
		var lc: Dictionary = e.get("league_champions", {}).get(lid, {})
		if lc.is_empty():
			continue
		grid.add_child(UI.dim("%s champions" % str(lg["name"]), 12))
		grid.add_child(_club_line(str(lc.get("club_id", "")),
			"%s (%d pts)" % [str(lc.get("name", "?")), int(lc.get("points", 0))], Color.WHITE))
	var cup: Dictionary = e.get("cup", {})
	if str(cup.get("winner", "")) != "":
		grid.add_child(UI.dim("%s winners" % GameState.cup_name(), 12))
		grid.add_child(_club_line(str(cup.get("winner", "")), str(cup.get("name", "?")), Color.WHITE))

	var aw: Dictionary = e.get("awards", {})
	var pos: Dictionary = aw.get("pokemon_of_season", {})
	if not pos.is_empty():
		grid.add_child(UI.dim("Pokémon of the Season", 12))
		grid.add_child(_award_line(pos))
	var dev: Dictionary = aw.get("best_developer", {})
	if not dev.is_empty():
		grid.add_child(UI.dim("Best Developer (young star)", 12))
		grid.add_child(_award_line(dev))

	var p: Dictionary = e.get("player", {})
	if not p.is_empty():
		grid.add_child(UI.dim("Your season (%s)" % str(p.get("name", "?")), 12))
		grid.add_child(UI.label("%s in the %s · %d pts · %s: %s" % [
			_ord(int(p.get("pos", 0))), GameState.league_name(str(p.get("league", ""))),
			int(p.get("points", 0)), GameState.cup_name(), str(p.get("cup", "?"))], 12,
			TB.COL_ACCENT.lightened(0.35)))

	var po: Array = e.get("playoff_results", [])
	if not po.is_empty():
		body.add_child(UI.vspace(2))
		var line: Array = []
		for r in po:
			if int(r.get("round", 0)) >= 2:
				line.append("%s %s %d-%d %s" % [
					Season.playoff_round_name(int(r["round"])).replace("Semi-Final", "SF").replace("Final", "F"),
					str(GameState.club(str(r["home"])).get("short", "?")), int(r["sh"]), int(r["sa"]),
					str(GameState.club(str(r["away"])).get("short", "?"))])
		body.add_child(UI.dim("%s run-in:  %s" % [Season.PLAYOFF_NAME, "   ·   ".join(line)], 11))
	return card


func _club_line(cid: String, text: String, col: Color) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.add_child(UI.monogram(GameState.club(cid), 16, 8))
	h.add_child(UI.link(text, 12, col, {"kind": "club", "id": cid}, "View club profile"))
	var chip := UI.league_chip(GameState.league_of(cid), 8)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(chip)
	return h


func _award_line(a: Dictionary) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var cid := str(a.get("club_id", ""))
	h.add_child(UI.label("%s (%s)" % [str(a.get("name", "?")), str(a.get("species", "?"))], 12, Color.WHITE))
	h.add_child(UI.link(str(GameState.club(cid).get("short", "?")), 12, TB.COL_TEXT_DIM,
		{"kind": "club", "id": cid}, "View club profile"))
	h.add_child(UI.dim("%.2f avg rating · %d battles" % [float(a.get("rating", 0.0)), int(a.get("battles", 0))], 11))
	return h


func _ord(n: int) -> String:
	if n <= 0:
		return "—"
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1: suffix = "st"
			2: suffix = "nd"
			3: suffix = "rd"
	return "%d%s" % [n, suffix]
