extends VBoxContainer
## LEAGUE TABLE tab — FM-style standings with zones, form pips, movement
## arrows, clickable column sorting, Overall / Home / Away / Form splits and
## a position-over-time graph of the whole league.

const UI := preload("res://screens/competition/ui.gd")
const TB := preload("res://shared/theme/theme_builder.gd")
const Charts := preload("res://screens/competition/charts.gd")

const ZONE_TITLE_END := 1     # pos 1: league champions (CS top seed)
const ZONE_PROMO_END := 4     # pos 1..4 qualify for the Championship Series
const ZONE_RELEG_FROM := 14   # pos 14..16: Danger Zone (board consequences)

const TITLES := ["Pos", "", "Club", "Pld", "Won", "Lost", "BF", "BA", "+/-", "Pts", "Form"]
const WIDTHS := [44, 34, 0, 52, 52, 52, 56, 56, 56, 60, 128]
const SPLITS := [
	["overall", "Overall"],
	["home", "Home"],
	["away", "Away"],
	["form", "Form (last 5)"],
	["graph", "Position Graph"],
]

## Which league's standings to show ("" = the player's league).
var league_id := ""

var _tree: Tree
var _graph   # Charts.PositionChart (untyped: inner-class Control)
var _footer: Label
var _hint: Label
var _split_buttons: Dictionary = {}
var _mode := "overall"
var _sort_col := 0        # 0 = league position (default order)
var _sort_asc := true


func _ready() -> void:
	add_theme_constant_override("separation", 8)

	# split selector toolbar (FM's Overall/Home/Away/Form table views)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	var cap := UI.dim("TABLE", 11)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(cap)
	for entry in SPLITS:
		var b := Button.new()
		b.text = tr(entry[1])
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(96, 26)
		b.add_theme_font_size_override("font_size", 12)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		match entry[0]:
			"overall": b.tooltip_text = "Full league standings"
			"home": b.tooltip_text = "Standings counting each club's home matches only"
			"away": b.tooltip_text = "Standings counting each club's away matches only"
			"form": b.tooltip_text = "Standings over each club's last 5 played matches"
			"graph": b.tooltip_text = "Every club's league position after each matchday"
		b.pressed.connect(_set_mode.bind(entry[0]))
		bar.add_child(b)
		_split_buttons[entry[0]] = b
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(sp)
	_hint = UI.dim("click a column header to sort · click again to reverse", 11)
	_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(_hint)
	add_child(bar)

	_tree = Tree.new()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.hide_root = true
	_tree.select_mode = Tree.SELECT_ROW
	_tree.scroll_horizontal_enabled = false
	_tree.columns = 11
	_tree.column_titles_visible = true
	for i in _tree.columns:
		_tree.set_column_title(i, tr(TITLES[i]) if TITLES[i] != "" else "")
		_tree.set_column_title_alignment(i, HORIZONTAL_ALIGNMENT_LEFT if i == 2 else HORIZONTAL_ALIGNMENT_CENTER)
		if WIDTHS[i] > 0:
			_tree.set_column_expand(i, false)
			_tree.set_column_custom_minimum_width(i, WIDTHS[i])
		else:
			_tree.set_column_expand(i, true)
	_tree.column_title_clicked.connect(_on_title_clicked)
	UI.wire_tree_links(_tree)
	_tree.item_activated.connect(func():
		var item := _tree.get_selected()
		if item != null and item.get_metadata(2) is Dictionary:
			UI.navigate(_tree, item.get_metadata(2)))
	add_child(_tree)

	_graph = Charts.PositionChart.new()
	_graph.zone_title_end = ZONE_TITLE_END
	_graph.zone_promo_end = ZONE_PROMO_END
	_graph.zone_releg_from = ZONE_RELEG_FROM
	_graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_graph.visible = false
	add_child(_graph)

	# Every zone here feeds a real mechanism: 1-4 enter the cross-league
	# Championship Series playoff after matchday 30 (see the tab of that name);
	# 14-16 trigger board consequences at the end-of-season ceremony.
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 18)
	legend.add_child(_legend_entry(Color(0.83, 0.68, 0.21), tr("League Champions (1st)"),
		tr("1st place wins the league title and tops the Championship Series seeding")))
	legend.add_child(_legend_entry(Color(0.34, 0.79, 0.47), tr("Championship Series (1-4)"),
		tr("Positions 1-4 of BOTH leagues enter the cross-league Championship Series\nplayoff after matchday 30 — its Final crowns the Indigo Champion")))
	legend.add_child(_legend_entry(Color(0.88, 0.38, 0.38), tr("Danger Zone (14-16)"),
		tr("Finish 14th-16th and the board reacts at season's end:\nreputation -1, transfer budget cut 25%, sponsors pull back —\nand your star Pokémon may demand a move")))
	legend.add_child(_legend_entry(TB.COL_ACCENT, tr("Your club"), ""))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	legend.add_child(spacer)
	_footer = UI.dim("", 12)
	legend.add_child(_footer)
	add_child(legend)

	# Screenshot-harness hook only: pre-select a table split (inert in play).
	var dev_mode := OS.get_environment("COMP_DEV_TABLE_MODE")
	for entry in SPLITS:
		if entry[0] == dev_mode:
			_mode = dev_mode


## Competition-switcher hook (screen.gd): render this league's standings.
func set_league_context(lg: String, _cup: bool) -> void:
	league_id = lg


func _lg() -> String:
	return league_id if league_id != "" else GameState.player_league_id()


func _set_mode(mode: String) -> void:
	_mode = mode
	_sort_col = 0
	_sort_asc = true
	refresh()


func _on_title_clicked(col: int, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_LEFT or col == 1:
		return   # col 1 is the movement-arrow column
	if _sort_col == col:
		_sort_asc = not _sort_asc
	else:
		_sort_col = col
		# sensible first direction: position/club ascending, stats descending
		_sort_asc = col in [0, 2]
	refresh()


func refresh() -> void:
	for k in _split_buttons:
		_split_buttons[k].set_pressed_no_signal(k == _mode)
		_split_buttons[k].add_theme_color_override("font_color",
			Color.WHITE if k == _mode else TB.COL_TEXT_DIM)
	var graph_mode := _mode == "graph"
	_tree.visible = not graph_mode
	_graph.visible = graph_mode
	_hint.text = (tr("hover a line to pick out a club · zones shaded behind") if graph_mode
		else tr("click a column header to sort · click again to reverse"))
	if graph_mode:
		_refresh_graph()
		return
	_refresh_titles()

	_tree.clear()
	var root := _tree.create_item()
	var club_ids: Array = GameState.league_club_ids(_lg())
	var fixtures: Array = Season.league_fixtures(GameState.fixtures, _lg())
	var table: Array = Season.compute_table_variant(club_ids, fixtures, _mode)
	var n := table.size()
	var played_league: Array = fixtures.filter(func(f): return f["played"])
	var completed := 0
	var last_date := ""
	for f in played_league:
		completed = maxi(completed, int(f["round"]))
		if str(f["date"]) > last_date:
			last_date = str(f["date"])
	var prev_pos := {}
	if _mode == "overall" and completed >= 2:
		var before: Array = played_league.filter(func(f): return str(f["date"]) < last_date)
		prev_pos = Season.table_positions(Season.compute_table(club_ids, before))

	# rows keep their split-table position, then reorder by the active sort
	var rows: Array = []
	for i in n:
		var r: Dictionary = table[i].duplicate()
		r["pos"] = i + 1
		r["diff"] = int(r["bf"]) - int(r["ba"])
		r["club"] = GameState.club(str(r["club_id"]))
		r["form"] = Season.club_form(str(r["club_id"]), fixtures, 5)
		rows.append(r)
	_sort_rows(rows)

	for r in rows:
		var cid: String = r["club_id"]
		var club: Dictionary = r["club"]
		var pos: int = r["pos"]
		var item := root.create_child()

		item.set_text(0, str(pos))
		item.set_text_alignment(0, HORIZONTAL_ALIGNMENT_CENTER)

		# movement arrow vs previous matchday (overall split only)
		var delta := 0
		if prev_pos.has(cid):
			delta = int(prev_pos[cid]) - pos
		item.set_cell_mode(1, TreeItem.CELL_MODE_CUSTOM)
		item.set_custom_draw_callback(1, _draw_movement.bind(delta if _mode == "overall" else 0))

		item.set_icon(2, UI.badge_texture(UI.club_color(club), 12))
		item.set_text(2, " " + str(club.get("name", cid)))
		UI.cell_link(item, 2, {"kind": "club", "id": cid},
			"%s — view club profile (squad, results, season record)" % club.get("name", cid))
		item.set_text(3, str(r["played"]))
		item.set_text(4, str(r["won"]))
		item.set_text(5, str(r["lost"]))
		item.set_text(6, str(r["bf"]))
		item.set_text(7, str(r["ba"]))
		var diff: int = r["diff"]
		item.set_text(8, ("+%d" % diff) if diff > 0 else str(diff))
		item.set_custom_color(8, UI.COL_WIN if diff > 0 else (UI.COL_LOSS if diff < 0 else TB.COL_TEXT_DIM))
		item.set_text(9, str(r["points"]))
		item.set_custom_color(9, Color.WHITE)
		for c in [3, 4, 5, 6, 7, 8, 9]:
			item.set_text_alignment(c, HORIZONTAL_ALIGNMENT_CENTER)
		item.set_custom_color(4, UI.COL_WIN)
		item.set_custom_color(5, UI.COL_LOSS)

		# form pips (custom drawn, oldest -> newest)
		item.set_cell_mode(10, TreeItem.CELL_MODE_CUSTOM)
		item.set_custom_draw_callback(10, _draw_form.bind(r["form"]))

		# zone tinting + player highlight (zones follow the split's positions)
		var zone := Color(0, 0, 0, 0)
		if pos <= ZONE_TITLE_END:
			zone = UI.COL_TITLE_ZONE
		elif pos <= ZONE_PROMO_END:
			zone = UI.COL_PROMO_ZONE
		elif pos >= ZONE_RELEG_FROM:
			zone = UI.COL_RELEG_ZONE
		var is_player := GameState.is_player_club(cid)
		for c in _tree.columns:
			if is_player:
				item.set_custom_bg_color(c, UI.COL_PLAYER_ROW)
			elif zone.a > 0.0:
				item.set_custom_bg_color(c, zone)
		if is_player:
			item.set_custom_color(2, TB.COL_ACCENT.lightened(0.35))
		else:
			item.set_custom_color(2, TB.COL_TEXT)

	var total := Season.total_league_rounds(fixtures)
	var split_note := ""
	match _mode:
		"home": split_note = tr(" · home matches only")
		"away": split_note = tr(" · away matches only")
		"form": split_note = tr(" · last 5 matches per club")
	if completed <= 0:
		_footer.text = tr("%s · season starts %s · %d clubs") % [
			tr(GameState.league_name(_lg())), I18n.pretty_date(
				Season.date_add(GameState.season_start, Season.LEAGUE_ROUND_OFFSET)), n]
	else:
		_footer.text = tr("%s · after Matchday %d of %d%s · click a club for its profile") % [
			tr(GameState.league_name(_lg())), completed, total, split_note]


## Feed the multi-club position tracker (Season.position_history) and set the
## footer. Clubs ordered by current position so hover z-order feels natural.
func _refresh_graph() -> void:
	var club_ids: Array = GameState.league_club_ids(_lg())
	var hist: Dictionary = Season.position_history(club_ids,
		Season.league_fixtures(GameState.fixtures, _lg()))
	var series: Array = []
	var table: Array = GameState.league_table(_lg())
	for row in table:
		var cid: String = str(row["club_id"])
		var club: Dictionary = GameState.club(cid)
		series.append({
			"id": cid,
			"label": str(club.get("short", cid)),
			"full": str(club.get("name", cid)),
			"color": UI.club_color(club).lightened(0.15),
			"values": hist.get(cid, []),
			"highlight": GameState.is_player_club(cid),
		})
	_graph.set_data(series, club_ids.size())
	var rounds := 0
	for s in series:
		rounds = maxi(rounds, (s["values"] as Array).size())
	if rounds == 0:
		_footer.text = tr("%s · the position graph appears after Matchday 1 completes") % \
			tr(GameState.world["meta"]["league_name"])
	else:
		_footer.text = tr("%s · league position after each of %d completed matchday%s · your club in accent") % [
			tr(GameState.world["meta"]["league_name"]), rounds, "" if rounds == 1 else "s"]


func _refresh_titles() -> void:
	for i in _tree.columns:
		var t: String = tr(TITLES[i]) if TITLES[i] != "" else ""
		if i == _sort_col and t != "":
			t += " ▲" if _sort_asc else " ▼"
		_tree.set_column_title(i, t)


func _sort_rows(rows: Array) -> void:
	var col := _sort_col
	var asc := _sort_asc
	rows.sort_custom(func(a, b):
		var va: Variant
		var vb: Variant
		match col:
			0: va = a["pos"]; vb = b["pos"]
			2: va = str(a["club"].get("name", "")); vb = str(b["club"].get("name", ""))
			3: va = a["played"]; vb = b["played"]
			4: va = a["won"]; vb = b["won"]
			5: va = a["lost"]; vb = b["lost"]
			6: va = a["bf"]; vb = b["bf"]
			7: va = a["ba"]; vb = b["ba"]
			8: va = a["diff"]; vb = b["diff"]
			9: va = a["points"]; vb = b["points"]
			10:
				va = a["form"].count("W"); vb = b["form"].count("W")
			_: va = a["pos"]; vb = b["pos"]
		if va == vb:
			return a["pos"] < b["pos"]   # stable tiebreak: league position
		return va < vb if asc else va > vb)


func _draw_movement(item: TreeItem, rect: Rect2, delta: int) -> void:
	var cx := rect.position.x + rect.size.x / 2.0
	var cy := rect.position.y + rect.size.y / 2.0
	if delta == 0:
		_tree.draw_rect(Rect2(cx - 4, cy - 1, 8, 2), Color(TB.COL_TEXT_DIM, 0.5))
		return
	var up := delta > 0
	var col := UI.COL_WIN if up else UI.COL_LOSS
	var s := 4.5
	var tri: PackedVector2Array
	if up:
		tri = PackedVector2Array([Vector2(cx, cy - s), Vector2(cx - s, cy + s * 0.8), Vector2(cx + s, cy + s * 0.8)])
	else:
		tri = PackedVector2Array([Vector2(cx, cy + s), Vector2(cx - s, cy - s * 0.8), Vector2(cx + s, cy - s * 0.8)])
	_tree.draw_colored_polygon(tri, col)
	if absi(delta) > 1:
		var f := _tree.get_theme_font("font")
		_tree.draw_string(f, Vector2(cx + s + 2, cy + 4), str(absi(delta)),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)


func _draw_form(item: TreeItem, rect: Rect2, form: Array) -> void:
	if form.is_empty():
		var f := _tree.get_theme_font("font")
		_tree.draw_string(f, rect.position + Vector2(8, rect.size.y / 2.0 + 4), "-",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(TB.COL_TEXT_DIM, 0.5))
		return
	var pip := 15.0
	var gap := 4.0
	var x := rect.position.x + 8.0
	var y := rect.position.y + (rect.size.y - pip) / 2.0
	var font := _tree.get_theme_font("font")
	for r in form:
		var col: Color = UI.COL_WIN if r == "W" else UI.COL_LOSS
		var rr := Rect2(x, y, pip, pip)
		_tree.draw_rect(rr, Color(col.r, col.g, col.b, 0.22))
		_tree.draw_rect(rr, col, false, 1.0)
		_tree.draw_string(font, Vector2(x + (pip - 8) / 2.0, y + pip - 4), tr(str(r)),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col.lightened(0.3))
		x += pip + gap


func _legend_entry(col: Color, text: String, tip: String = "") -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	if tip != "":
		h.tooltip_text = tip
		h.mouse_filter = Control.MOUSE_FILTER_STOP
	var sq := Panel.new()
	sq.custom_minimum_size = Vector2(11, 11)
	sq.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r, col.g, col.b, 0.35)
	sb.border_color = col
	sb.set_border_width_all(1)
	sq.add_theme_stylebox_override("panel", sb)
	h.add_child(sq)
	h.add_child(UI.dim(text, 12))
	return h
