extends VBoxContainer
## FIXTURES & RESULTS tab — chronological schedule grouped by round, filters,
## clickable results opening a full mini match report (real replayed stats).

const UI := preload("res://screens/competition/ui.gd")
const TB := preload("res://shared/theme/theme_builder.gd")

var _comp_filter := "all"       # all | league | cup
var _mine_only := false
var _selected_fid := ""
var league_id := ""             # which league's fixtures ("" = player's)
var _cup_focus := false         # competition switcher parked on the cup

var _list_box: VBoxContainer
var _scroll: ScrollContainer
var _detail_card: PanelContainer
var _detail_body: VBoxContainer
var _filter_buttons: Dictionary = {}
var _mine_btn: Button
var _row_buttons: Dictionary = {}       # fid -> Button
var _current_round_anchor: Control


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_build_controls()
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 10)
	add_child(split)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(_scroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 2)
	_scroll.add_child(_list_box)

	_detail_card = UI.card("Match Detail")
	_detail_card.custom_minimum_size.x = 460
	_detail_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(_detail_card)
	_detail_body = UI.card_body(_detail_card)


func _build_controls() -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	for entry in [["all", "All Competitions"], ["league", GameState.league_name()], ["cup", GameState.cup_name()]]:
		var b := Button.new()
		b.text = entry[1]
		b.toggle_mode = true
		b.button_pressed = entry[0] == _comp_filter
		b.pressed.connect(_on_filter.bind(entry[0]))
		bar.add_child(b)
		_filter_buttons[entry[0]] = b
	var vs := VSeparator.new()
	bar.add_child(vs)
	_mine_btn = Button.new()
	_mine_btn.text = "My Fixtures"
	_mine_btn.toggle_mode = true
	_mine_btn.toggled.connect(func(on: bool):
		_mine_only = on
		refresh())
	bar.add_child(_mine_btn)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	var jump := Button.new()
	jump.text = "Go To Current Date"
	jump.pressed.connect(_scroll_to_current)
	bar.add_child(jump)
	add_child(bar)


## Competition-switcher hook (screen.gd). Cup context focuses the cup filter;
## returning to a league restores the full schedule for that league.
func set_league_context(lg: String, cup: bool) -> void:
	league_id = lg
	if cup:
		_comp_filter = "cup"
	elif _cup_focus:
		_comp_filter = "all"
	_cup_focus = cup
	if not _filter_buttons.is_empty():
		for k in _filter_buttons:
			_filter_buttons[k].set_pressed_no_signal(k == _comp_filter)


func _lg() -> String:
	return league_id if league_id != "" else GameState.player_league_id()


func _in_league(f: Dictionary) -> bool:
	if f["comp"] != "league":
		return true   # cup ties are cross-league, always shown
	var tag := str(f.get("league", ""))
	return tag == "" or tag == _lg()


func _on_filter(which: String) -> void:
	_comp_filter = which
	for k in _filter_buttons:
		_filter_buttons[k].set_pressed_no_signal(k == _comp_filter)
	refresh()


func refresh() -> void:
	for c in _list_box.get_children():
		c.queue_free()
	_row_buttons.clear()
	_current_round_anchor = null

	_filter_buttons["league"].text = GameState.league_name(_lg())
	_filter_buttons["cup"].text = GameState.cup_name()
	var pid: String = GameState.world["meta"]["player_club_id"]
	var fixtures: Array = GameState.fixtures.filter(func(f):
		if _comp_filter != "all" and f["comp"] != _comp_filter:
			return false
		if not _in_league(f):
			return false
		if _mine_only and f["home"] != pid and f["away"] != pid:
			return false
		return true)

	# group into (comp, round) blocks ordered by date
	var groups := {}
	var order: Array = []
	for f in fixtures:
		var key := "%s|%d" % [f["comp"], int(f["round"])]
		if not groups.has(key):
			groups[key] = {"comp": f["comp"], "round": int(f["round"]), "date": f["date"], "fx": []}
			order.append(key)
		groups[key]["fx"].append(f)
	order.sort_custom(func(a, b): return groups[a]["date"] < groups[b]["date"])

	var today: String = GameState.current_date
	var anchor_set := false
	for key in order:
		var g: Dictionary = groups[key]
		var head := _group_header(g)
		_list_box.add_child(head)
		if not anchor_set and g["date"] >= today:
			_current_round_anchor = head
			anchor_set = true
		for f in g["fx"]:
			_list_box.add_child(_fixture_row(f))

	if _list_box.get_child_count() == 0:
		_list_box.add_child(UI.dim("No fixtures match the current filter.", 13))

	# keep / initialise selection
	if _selected_fid == "" or _row_buttons.get(_selected_fid) == null:
		var last_played := {}
		for f in GameState.player_fixtures():
			if f["played"]:
				last_played = f
		if last_played.is_empty():
			for f in GameState.fixtures:
				if f["played"]:
					last_played = f
		if last_played.is_empty():
			var nf := GameState.next_player_fixture()
			if not nf.is_empty():
				last_played = nf
		if not last_played.is_empty():
			_selected_fid = str(last_played["id"])
	_apply_selection_styles()
	_render_detail()
	call_deferred("_scroll_to_current")


func _scroll_to_current() -> void:
	if _current_round_anchor != null and is_instance_valid(_current_round_anchor):
		await get_tree().process_frame
		if is_instance_valid(_current_round_anchor):
			_scroll.ensure_control_visible(_current_round_anchor)


func _group_header(g: Dictionary) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = TB.COL_PANEL_ALT
	sb.border_color = TB.COL_BORDER
	sb.set_border_width_all(1)
	sb.content_margin_left = 10
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	p.add_child(h)
	var title := ""
	if g["comp"] == "league":
		title = "%s · MATCHDAY %d" % [GameState.league_name(_lg()).to_upper(), g["round"]]
	elif g["comp"] == "playoff":
		title = "%s · %s" % [Season.PLAYOFF_NAME.to_upper(), Season.playoff_round_name(g["round"]).to_upper()]
	else:
		title = "%s · %s" % [GameState.cup_name().to_upper(), Season.cup_round_name(g["round"]).to_upper()]
	var l := UI.label(title, 12, TB.COL_TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	h.add_child(UI.dim("%s %s" % [UI.weekday(g["date"]), Season.pretty_date(g["date"])], 12))
	return p


func _fixture_row(f: Dictionary) -> Button:
	var pid: String = GameState.world["meta"]["player_club_id"]
	var home: Dictionary = GameState.club(f["home"])
	var away: Dictionary = GameState.club(f["away"])
	var btn := Button.new()
	btn.custom_minimum_size.y = 30
	btn.add_theme_stylebox_override("normal", _row_style(TB.COL_PANEL, TB.COL_PANEL))
	btn.add_theme_stylebox_override("hover", _row_style(Color("232a44"), TB.COL_BORDER))
	btn.add_theme_stylebox_override("pressed", _row_style(Color("2a3150"), TB.COL_ACCENT_DIM))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.pressed.connect(_on_row_clicked.bind(str(f["id"])))
	_row_buttons[str(f["id"])] = btn

	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 8)
	btn.add_child(h)

	var played: bool = f["played"]
	var hw: bool = played and int(f["score_home"]) > int(f["score_away"])
	var aw: bool = played and not hw

	var home_l := UI.link(str(home.get("name", f["home"])), 13,
		_club_text_color(f["home"], pid, hw, played),
		{"kind": "club", "id": str(f["home"])},
		"%s — view club profile" % home.get("name", "?"))
	home_l.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	home_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(home_l)
	if f["comp"] in ["cup", "playoff"]:   # cross-league tie: badge each club's championship
		var hc := UI.league_chip(GameState.league_of(str(f["home"])))
		hc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(hc)
	var hm := UI.monogram(home, 20, 9)
	hm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(hm)

	var mid := UI.label("v", 13, TB.COL_TEXT_DIM)
	if played:
		mid.text = "%d - %d" % [f["score_home"], f["score_away"]]
		mid.add_theme_color_override("font_color", Color.WHITE)
	mid.custom_minimum_size.x = 52
	mid.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_child(mid)

	var am := UI.monogram(away, 20, 9)
	am.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(am)
	if f["comp"] in ["cup", "playoff"]:
		var ac := UI.league_chip(GameState.league_of(str(f["away"])))
		ac.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ac)
	var away_l := UI.link(str(away.get("name", f["away"])), 13,
		_club_text_color(f["away"], pid, aw, played),
		{"kind": "club", "id": str(f["away"])},
		"%s — view club profile" % away.get("name", "?"))
	away_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(away_l)

	var tag := UI.dim("FT" if played else UI.short_date(f["date"]), 11)
	tag.custom_minimum_size.x = 46
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(tag)
	return btn


func _club_text_color(cid: String, pid: String, is_winner: bool, played: bool) -> Color:
	if cid == pid:
		return TB.COL_ACCENT.lightened(0.35)
	if not played:
		return TB.COL_TEXT
	return Color.WHITE if is_winner else TB.COL_TEXT_DIM


func _row_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	return sb


func _on_row_clicked(fid: String) -> void:
	_selected_fid = fid
	_apply_selection_styles()
	_render_detail()


## Cross-navigation entry point: profiles, brackets and the overview jump to a
## specific match report/preview here (screen.gd comp_navigate "fixture").
func select_fixture(fid: String) -> void:
	_selected_fid = fid
	var f := _find_fixture(fid)
	# make sure the row is visible under the current filters
	if not f.is_empty():
		# a fixture from the other league pulls the whole competition context over
		var tag := str(f.get("league", ""))
		if f["comp"] == "league" and tag != "" and tag != _lg():
			var n: Node = get_parent()
			while n != null and not n.has_method("comp_set_league"):
				n = n.get_parent()
			if n != null:
				n.call("comp_set_league", tag)
		if _comp_filter != "all" and str(f["comp"]) != _comp_filter:
			_comp_filter = "all"
			for k in _filter_buttons:
				_filter_buttons[k].set_pressed_no_signal(k == _comp_filter)
		var pid: String = GameState.world["meta"]["player_club_id"]
		if _mine_only and f["home"] != pid and f["away"] != pid:
			_mine_only = false
			_mine_btn.set_pressed_no_signal(false)
	refresh()
	call_deferred("_scroll_to_selected")


func _scroll_to_selected() -> void:
	var b: Button = _row_buttons.get(_selected_fid)
	if b != null and is_instance_valid(b):
		await get_tree().process_frame
		if is_instance_valid(b):
			_scroll.ensure_control_visible(b)


func _apply_selection_styles() -> void:
	for fid in _row_buttons:
		var b: Button = _row_buttons[fid]
		if not is_instance_valid(b):
			continue
		if fid == _selected_fid:
			b.add_theme_stylebox_override("normal", _row_style(Color("2a3150"), TB.COL_ACCENT_DIM))
		else:
			b.add_theme_stylebox_override("normal", _row_style(TB.COL_PANEL, TB.COL_PANEL))


func _find_fixture(fid: String) -> Dictionary:
	for f in GameState.fixtures:
		if str(f["id"]) == fid:
			return f
	return {}


# ---------------------------------------------------------------- match detail

func _render_detail() -> void:
	for c in _detail_body.get_children():
		c.queue_free()
	var f := _find_fixture(_selected_fid)
	if f.is_empty():
		_detail_body.add_child(UI.dim("Select a fixture to see the match report,\nor an upcoming tie for a preview.", 13))
		return
	var home: Dictionary = GameState.club(f["home"])
	var away: Dictionary = GameState.club(f["away"])

	var comp_name: String = Season.comp_label(f)
	_detail_body.add_child(UI.dim("%s · %s %s" % [comp_name, UI.weekday(f["date"]), Season.pretty_date(f["date"])], 12))
	_detail_body.add_child(UI.vspace(2))

	# scoreline header
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.add_child(UI.monogram(home, 34, 12))
	var hn := UI.club_link(home, 15, Color.WHITE)
	hn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hn)
	var score := UI.label("v", 22, TB.COL_TEXT_DIM)
	if f["played"]:
		score.text = "%d - %d" % [f["score_home"], f["score_away"]]
		score.add_theme_color_override("font_color", Color.WHITE)
	head.add_child(score)
	var an := UI.club_link(away, 15, Color.WHITE)
	an.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	an.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(an)
	head.add_child(UI.monogram(away, 34, 12))
	_detail_body.add_child(head)
	_detail_body.add_child(HSeparator.new())

	if f["played"]:
		_render_report(f, home, away)
	else:
		_render_preview(f, home, away)


func _render_report(f: Dictionary, home: Dictionary, away: Dictionary) -> void:
	var detail := Season.fixture_detail(f)
	if detail.is_empty():
		_detail_body.add_child(UI.dim("Match data unavailable.", 13))
		return
	if detail.get("no_report", false) or (detail["battles"] as Array).is_empty():
		# Legacy fixture: the result stands but no battle-level report was
		# recorded at play time — never reconstruct one that could lie.
		_detail_body.add_child(UI.dim(
			"Full match report unavailable — this result was recorded before\ndetailed match reports were kept. The score above is official.", 13))
		return

	_detail_body.add_child(UI.dim("BEST-OF-3 BATTLES", 11))
	var battles: Array = detail["battles"]
	for i in battles.size():
		var b: Dictionary = battles[i]
		var wclub: Dictionary = home if int(b["winner"]) == 0 else away
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var lab := UI.label("Battle %d" % (i + 1), 13, TB.COL_TEXT_DIM)
		lab.custom_minimum_size.x = 64
		row.add_child(lab)
		var win := UI.label("%s win" % wclub["short"], 13,
			TB.COL_ACCENT.lightened(0.35) if GameState.is_player_club(wclub["id"]) else Color.WHITE)
		win.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(win)
		row.add_child(UI.dim("%d turns" % int(b["turns"]), 12))
		_detail_body.add_child(row)

	_detail_body.add_child(UI.vspace(4))
	_detail_body.add_child(UI.dim("PERFORMERS  ·  KOs / damage / match rating", 11))

	# performers table
	var players: Dictionary = detail["players"]
	var rows: Array = []
	for uid in players:
		var p: Dictionary = players[uid]
		var battles_n := maxi(int(p["battles"]), 1)
		rows.append({"uid": str(uid), "name": p["name"], "side": int(p["side"]),
			"kos": int(p["kos"]), "dmg": int(p["dmg"]),
			"rating": float(p["rating_sum"]) / battles_n})
	rows.sort_custom(func(a, b): return a["rating"] > b["rating"])

	var tree := Tree.new()
	tree.hide_root = true
	tree.columns = 5
	tree.column_titles_visible = true
	tree.custom_minimum_size.y = 300
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var titles := ["Pokémon", "Club", "KOs", "Dmg", "Rat"]
	var widths := [0, 64, 48, 64, 52]
	for i in tree.columns:
		tree.set_column_title(i, titles[i])
		tree.set_column_title_alignment(i, HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_CENTER)
		if widths[i] > 0:
			tree.set_column_expand(i, false)
			tree.set_column_custom_minimum_width(i, widths[i])
	UI.wire_tree_links(tree)
	var root := tree.create_item()
	var mvp := true
	for r in rows.slice(0, 12):
		var item := root.create_child()
		var club: Dictionary = home if r["side"] == 0 else away
		item.set_text(0, str(r["name"]))
		item.set_icon(0, UI.badge_texture(UI.club_color(club), 10))
		UI.cell_link(item, 0, {"kind": "pokemon", "id": r["uid"]},
			"%s — view Pokémon profile" % r["name"])
		item.set_text(1, str(club["short"]))
		item.set_custom_color(1, TB.COL_TEXT_DIM)
		UI.cell_link(item, 1, {"kind": "club", "id": str(club["id"])},
			"%s — view club profile" % club["name"])
		item.set_text(2, str(r["kos"]))
		item.set_text(3, str(r["dmg"]))
		item.set_text(4, "%.1f" % r["rating"])
		item.set_custom_color(4, _rating_color(r["rating"]))
		for c in [2, 3, 4]:
			item.set_text_alignment(c, HORIZONTAL_ALIGNMENT_CENTER)
		if GameState.is_player_club(club["id"]):
			for c in tree.columns:
				item.set_custom_bg_color(c, UI.COL_PLAYER_ROW)
		if mvp:
			item.set_custom_color(0, Color(0.95, 0.83, 0.4))
			mvp = false
		else:
			item.set_custom_color(0, TB.COL_TEXT)
	_detail_body.add_child(tree)
	if not rows.is_empty():
		var potm := HBoxContainer.new()
		potm.add_theme_constant_override("separation", 6)
		potm.add_child(UI.dim("Player of the Match:", 12))
		var pl := UI.link("%s (%.1f)" % [rows[0]["name"], rows[0]["rating"]], 12,
			Color(0.95, 0.83, 0.4), {"kind": "pokemon", "id": rows[0]["uid"]})
		potm.add_child(pl)
		_detail_body.add_child(potm)


func _render_preview(f: Dictionary, home: Dictionary, away: Dictionary) -> void:
	var days := Season.days_between(GameState.current_date, f["date"])
	_detail_body.add_child(UI.kv_row("Kick-off", "%s · in %d day%s" % [
		Season.pretty_date(f["date"]), days, "" if days == 1 else "s"]))
	# each club's standing in ITS OWN championship (cup ties cross leagues)
	var lg_h := GameState.league_of(str(f["home"]))
	var lg_a := GameState.league_of(str(f["away"]))
	var pos_h: int = Season.table_positions(GameState.league_table(lg_h)).get(f["home"], 0)
	var pos_a: int = Season.table_positions(GameState.league_table(lg_a)).get(f["away"], 0)
	if lg_h == lg_a:
		_detail_body.add_child(UI.kv_row("League position",
			"%s  %s   ·   %s  %s" % [home["short"], _ord(pos_h), away["short"], _ord(pos_a)]))
	else:
		_detail_body.add_child(UI.kv_row("League position",
			"%s  %s (%s)   ·   %s  %s (%s)" % [
				home["short"], _ord(pos_h), UI.league_tag(lg_h),
				away["short"], _ord(pos_a), UI.league_tag(lg_a)]))
	_detail_body.add_child(UI.vspace(2))
	for entry in [[home, f["home"]], [away, f["away"]]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var l := UI.link("%s form" % entry[0]["short"], 12, TB.COL_TEXT_DIM,
			{"kind": "club", "id": str(entry[1])},
			"%s — view club profile" % entry[0]["name"])
		l.custom_minimum_size.x = 90
		row.add_child(l)
		var form := Season.club_form(entry[1], GameState.fixtures, 5)
		if form.is_empty():
			row.add_child(UI.dim("no matches yet", 12))
		else:
			row.add_child(UI.form_pips(form, 15))
		_detail_body.add_child(row)
	# head-to-head this season
	var h2h: Array = GameState.fixtures.filter(func(x):
		return x["played"] and ((x["home"] == f["home"] and x["away"] == f["away"])
			or (x["home"] == f["away"] and x["away"] == f["home"])))
	if not h2h.is_empty():
		_detail_body.add_child(UI.vspace(2))
		_detail_body.add_child(UI.dim("MEETINGS THIS SEASON", 11))
		for m in h2h:
			var hm: Dictionary = GameState.club(m["home"])
			var am: Dictionary = GameState.club(m["away"])
			var mlink := UI.link("%s  %s %d - %d %s" % [UI.short_date(m["date"]),
				hm["short"], m["score_home"], m["score_away"], am["short"]], 13,
				TB.COL_TEXT, {"kind": "fixture", "id": str(m["id"])}, "Go to this match report")
			_detail_body.add_child(mlink)


func _rating_color(r: float) -> Color:
	if r >= 8.0:
		return Color(0.95, 0.83, 0.4)
	if r >= 7.0:
		return UI.COL_WIN
	if r < 6.2:
		return UI.COL_LOSS
	return TB.COL_TEXT


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
