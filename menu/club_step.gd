extends Control
## Onboarding step 2: club selection (menu piece). Extends the shell's
## new-career picker concept — league tabs + one row per club (crest,
## reputation meter, world-percentile squad stars) — and adds an FM-style
## club DETAIL PANE: board season expectation preview, squad strength,
## budgets and the manager you'd replace.
##
## Reads a FRESH res://shared/data/world.json (like shell/club_picker.gd)
## so the numbers are exactly what the new career starts with.

signal club_selected(summary: Dictionary)
signal club_confirmed

var _font_bold: Font
var _font_semibold: Font
var _font_header: Font

var season_start := ""             # fresh world's meta.season_start (summary card)
var _leagues: Array = []
var _clubs: Dictionary = {}        # league_id -> [summary]
var _all: Array = []               # every summary (expectation ranks)
var _active_league := ""
var _selected_id := ""

var _rows_box: VBoxContainer
var _detail_box: VBoxContainer
var _tab_btns: Dictionary = {}
var _narrow := false   # portrait phone layout (mobile piece)
var _row_panels: Dictionary = {}


func setup(bold: Font, semibold: Font, header: Font) -> void:
	_font_bold = bold
	_font_semibold = semibold
	_font_header = header


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_load_world()
	_build_ui()
	if not _leagues.is_empty():
		set_league(str(_leagues[0]["id"]))


func selected_summary() -> Dictionary:
	return _find_summary(_selected_id)


# ------------------------------------------------------------------ data

func _load_world() -> void:
	var f := FileAccess.open("res://shared/data/world.json", FileAccess.READ)
	if f == null:
		return
	var world: Variant = JSON.parse_string(f.get_as_text())
	if typeof(world) != TYPE_DICTIONARY:
		return
	season_start = str(world["meta"].get("season_start", ""))
	_leagues = world["meta"].get("leagues",
		[{"id": "kanto", "name": str(world["meta"].get("league_name", "League"))}])
	for c in world.get("clubs", []):
		_all.append(_summarize(c))
	# world-percentile squad stars (comparable between leagues)
	var by_strength := _all.duplicate()
	by_strength.sort_custom(func(a, b): return float(a["avg6"]) < float(b["avg6"]))
	for i in by_strength.size():
		by_strength[i]["stars"] = 1 + int(floor(float(i) / maxf(1.0, float(by_strength.size())) * 5.0))
	# expected league position across the whole world = rank by reputation
	# (mirrors the Board & Finances screen's expected_position maths)
	for s in _all:
		var better := 0
		for o in _all:
			if o["id"] == s["id"]:
				continue
			if int(o["rep"]) > int(s["rep"]) or \
					(int(o["rep"]) == int(s["rep"]) and str(o["id"]) < str(s["id"])):
				better += 1
		s["expected"] = better + 1
	for s in _all:
		var lid: String = str(s["league"])
		if not _clubs.has(lid):
			_clubs[lid] = []
		_clubs[lid].append(s)
	for lid in _clubs:
		_clubs[lid].sort_custom(func(a, b):
			if int(a["rep"]) != int(b["rep"]):
				return int(a["rep"]) > int(b["rep"])
			return str(a["name"]) < str(b["name"]))


func _summarize(c: Dictionary) -> Dictionary:
	var levels: Array = c.get("squad", []).map(func(m): return int(m["level"]))
	levels.sort()
	levels.reverse()
	var top: Array = levels.slice(0, 6)
	var avg := 0.0
	for l in top:
		avg += float(l)
	avg /= maxf(1.0, float(top.size()))
	return {
		"id": str(c["id"]), "name": str(c["name"]), "short": str(c.get("short", "")),
		"league": str(c.get("league", "kanto")), "manager": str(c.get("manager", "")),
		"rep": int(c.get("reputation", 10)),
		"balance": int(c.get("finances", {}).get("balance", 0)),
		"wage_budget": int(c.get("finances", {}).get("wage_budget", 0)),
		"squad_n": c.get("squad", []).size(),
		"avg6": avg, "stars": 3, "expected": 8,
		"type": _primary_type(c),
		"club": c,   # full dict so the crest reads the real squad (crests piece)
	}


func _primary_type(c: Dictionary) -> String:
	var counts := {}
	for inst in c.get("squad", []):
		var sp: Dictionary = DataStore.species(int(inst["species_id"]))
		if sp.is_empty():
			continue
		var types: Array = sp.get("types", [])
		if types.size() > 0:
			counts[types[0]] = counts.get(types[0], 0) + 2
		if types.size() > 1:
			counts[types[1]] = counts.get(types[1], 0) + 1
	var best := "normal"
	var best_n := -1
	for t in counts:
		if counts[t] > best_n:
			best_n = counts[t]
			best = t
	return best


func league_name_of(lid: String) -> String:
	for lg in _leagues:
		if str(lg["id"]) == lid:
			return str(lg["name"])
	return lid


## Same tier thresholds the in-game board expectation uses (news_gen).
func expectation_key(expected: int) -> String:
	if expected <= 2:
		return "challenge for the league title"
	if expected <= 5:
		return "push for a top-four finish"
	if expected <= 8:
		return "finish in the top half of the table"
	if expected <= 12:
		return "secure a comfortable mid-table finish"
	return "stay well clear of the bottom places"


func cup_expectation_key(expected: int) -> String:
	if expected <= 4:
		return "reach the Indigo Cup Final"
	if expected <= 8:
		return "reach the Indigo Cup Semi-Final"
	return "reach the Indigo Cup Quarter-Final"


# ------------------------------------------------------------------ ui

func _build_ui() -> void:
	# portrait phones stack the list over the detail pane (mobile piece)
	_narrow = get_viewport_rect().size.x < 700.0
	var root: BoxContainer = VBoxContainer.new() if _narrow else HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 10 if _narrow else 14)
	add_child(root)

	var left := VBoxContainer.new()
	if _narrow:
		left.size_flags_vertical = Control.SIZE_EXPAND_FILL
		left.size_flags_stretch_ratio = 1.4
	else:
		left.custom_minimum_size.x = 620
	left.add_theme_constant_override("separation", 8)
	root.add_child(left)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	for lg in _leagues:
		var lid: String = str(lg["id"])
		var b := Button.new()
		b.text = tr(str(lg["name"])).to_upper()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(150 if _narrow else 180, 34)
		b.add_theme_font_override("font", _font_header)
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(func(): set_league(lid))
		tabs.add_child(b)
		_tab_btns[lid] = b
	left.add_child(tabs)

	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel",
		ThemeBuilder._flat(ThemeBuilder.COL_PANEL_ALT, ThemeBuilder.COL_BORDER, 4, 10, 4))
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 10)
	for spec in [[tr("CLUB"), 180.0 if _narrow else 280.0],
			[tr("REP") if _narrow else tr("REPUTATION"), 76.0 if _narrow else 140.0],
			[tr("STARS") if _narrow else tr("SQUAD STRENGTH"), 0.0]]:
		var l := Label.new()
		l.text = str(spec[0])
		l.add_theme_font_override("font", _font_header)
		l.add_theme_font_size_override("font_size", 10)
		l.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
		if float(spec[1]) > 0.0:
			l.custom_minimum_size.x = float(spec[1])
		else:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hrow.add_child(l)
	head.add_child(hrow)
	left.add_child(head)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("separation", 3)
	scroll.add_child(_rows_box)
	left.add_child(scroll)

	# right (below, on portrait phones): detail pane
	var pane := PanelContainer.new()
	pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pane.add_theme_stylebox_override("panel",
		ThemeBuilder._flat(ThemeBuilder.COL_PANEL_ALT, ThemeBuilder.COL_BORDER, 6, 16, 14))
	_detail_box = VBoxContainer.new()
	_detail_box.add_theme_constant_override("separation", 8)
	if _narrow:
		var dscroll := ScrollContainer.new()
		dscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dscroll.add_child(_detail_box)
		pane.add_child(dscroll)
	else:
		pane.add_child(_detail_box)
	root.add_child(pane)
	_render_detail({})


func set_league(lid: String) -> void:
	_active_league = lid
	for t in _tab_btns:
		var b: Button = _tab_btns[t]
		b.set_pressed_no_signal(t == lid)
		b.add_theme_color_override("font_color",
			Color.WHITE if t == lid else ThemeBuilder.COL_TEXT_DIM)
	for child in _rows_box.get_children():
		child.queue_free()
	_row_panels.clear()
	for s in _clubs.get(lid, []):
		_rows_box.add_child(_club_row(s))
	_apply_selection_styles()


func _club_row(s: Dictionary) -> Control:
	var cid: String = str(s["id"])
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			if _selected_id == cid and ev.double_click:
				club_confirmed.emit()
			else:
				select_club(cid))
	_row_panels[cid] = panel

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)

	var club_cell := HBoxContainer.new()
	club_cell.custom_minimum_size.x = 180 if _narrow else 280
	club_cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	club_cell.add_theme_constant_override("separation", 10)
	club_cell.add_child(_crest(s, 30))
	var name_col := VBoxContainer.new()
	name_col.alignment = BoxContainer.ALIGNMENT_CENTER
	name_col.add_theme_constant_override("separation", 0)
	name_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nm := Label.new()
	nm.text = str(s["name"])
	nm.add_theme_font_override("font", _font_bold)
	nm.add_theme_font_size_override("font_size", 13)
	nm.add_theme_color_override("font_color", Color.WHITE)
	name_col.add_child(nm)
	var sub := Label.new()
	sub.text = tr("%s · %d in squad") % [str(s["short"]), int(s["squad_n"])]
	sub.add_theme_font_size_override("font_size", 10)
	sub.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	name_col.add_child(sub)
	club_cell.add_child(name_col)
	row.add_child(club_cell)

	var rep_cell := HBoxContainer.new()
	rep_cell.custom_minimum_size.x = 76 if _narrow else 140
	rep_cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rep_cell.add_theme_constant_override("separation", 8)
	var rep_n := Label.new()
	rep_n.text = "%d" % int(s["rep"])
	rep_n.custom_minimum_size.x = 20
	rep_n.add_theme_font_override("font", _font_semibold)
	rep_n.add_theme_font_size_override("font_size", 12)
	rep_n.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT)
	rep_cell.add_child(rep_n)
	rep_cell.add_child(_meter(float(s["rep"]) / 20.0, ThemeBuilder.COL_ACCENT, 46 if _narrow else 90))
	row.add_child(rep_cell)

	var str_cell := HBoxContainer.new()
	str_cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	str_cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	str_cell.add_theme_constant_override("separation", 8)
	var stars := TextureRect.new()
	var n := clampi(int(s["stars"]), 1, 5)
	stars.texture = GlyphIcons.rating_tex(float(n), 5, 12, ThemeBuilder.COL_WARN)
	stars.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	str_cell.add_child(stars)
	if not _narrow:   # phones keep stars only — the label overflowed the row
		var avg := Label.new()
		avg.text = tr("avg Lv %.0f") % float(s["avg6"])
		avg.add_theme_font_size_override("font_size", 11)
		avg.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
		str_cell.add_child(avg)
	row.add_child(str_cell)

	panel.add_child(row)
	return panel


func select_club(cid: String) -> void:
	_selected_id = cid
	_apply_selection_styles()
	var s := _find_summary(cid)
	_render_detail(s)
	if not s.is_empty():
		club_selected.emit(s)


func _find_summary(cid: String) -> Dictionary:
	for s in _all:
		if str(s["id"]) == cid:
			return s
	return {}


func _apply_selection_styles() -> void:
	for cid in _row_panels:
		var selected: bool = str(cid) == _selected_id
		var bg: Color = ThemeBuilder.COL_ACCENT_DIM if selected else ThemeBuilder.COL_PANEL
		var border: Color = ThemeBuilder.COL_ACCENT if selected else ThemeBuilder.COL_BORDER
		(_row_panels[cid] as PanelContainer).add_theme_stylebox_override("panel",
			ThemeBuilder._flat(bg, border, 5, 10, 5))


# ------------------------------------------------------------------ detail pane

func _render_detail(s: Dictionary) -> void:
	for child in _detail_box.get_children():
		child.queue_free()
	if s.is_empty():
		var empty := Label.new()
		empty.text = tr("Select a club to see the board's expectations, squad strength and budget.")
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_font_size_override("font_size", 13)
		empty.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
		_detail_box.add_child(empty)
		return

	var ident := HBoxContainer.new()
	ident.add_theme_constant_override("separation", 12)
	ident.add_child(_crest(s, 54))
	var idcol := VBoxContainer.new()
	idcol.alignment = BoxContainer.ALIGNMENT_CENTER
	idcol.add_theme_constant_override("separation", 0)
	var nm := Label.new()
	nm.text = str(s["name"])
	nm.add_theme_font_override("font", _font_bold)
	nm.add_theme_font_size_override("font_size", 18)
	nm.add_theme_color_override("font_color", Color.WHITE)
	idcol.add_child(nm)
	var lg := Label.new()
	lg.text = "%s · %s" % [tr(league_name_of(str(s["league"]))),
		tr("You will replace %s") % str(s["manager"])]
	lg.add_theme_font_size_override("font_size", 11)
	lg.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	idcol.add_child(lg)
	ident.add_child(idcol)
	_detail_box.add_child(ident)
	_detail_box.add_child(_sep())

	# board expectation preview — same sentence the Board & Finances screen uses
	var exp_head := Label.new()
	exp_head.text = tr("SEASON EXPECTATIONS")
	exp_head.add_theme_font_override("font", _font_header)
	exp_head.add_theme_font_size_override("font_size", 11)
	exp_head.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	_detail_box.add_child(exp_head)
	var exp := Label.new()
	exp.text = tr("\"%s expect the club to %s and to %s.\"") % [str(s["name"]),
		tr(expectation_key(int(s["expected"]))), tr(cup_expectation_key(int(s["expected"])))]
	exp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	exp.add_theme_font_override("font", _font_bold)
	exp.add_theme_font_size_override("font_size", 13)
	exp.add_theme_color_override("font_color", Color("f2f4fb"))
	_detail_box.add_child(exp)
	var exp_sub := Label.new()
	exp_sub.text = tr("Expected league position: around %s of the world's %d clubs by reputation") \
		% [I18n.ordinal(int(s["expected"])), _all.size()]
	exp_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	exp_sub.add_theme_font_size_override("font_size", 11)
	exp_sub.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	_detail_box.add_child(exp_sub)
	_detail_box.add_child(_sep())

	# stat rows
	var stars_n := clampi(int(s["stars"]), 1, 5)
	var stars_row := _stat_row(tr("Squad stars"), "", ThemeBuilder.COL_WARN)
	var stars_tex := TextureRect.new()
	stars_tex.texture = GlyphIcons.rating_tex(float(stars_n), 5, 12, ThemeBuilder.COL_WARN)
	stars_tex.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	stars_row.add_child(stars_tex)
	_detail_box.add_child(stars_row)
	_detail_box.add_child(_stat_row(tr("Top-six average level"), "Lv %.0f" % float(s["avg6"]), ThemeBuilder.COL_TEXT))
	_detail_box.add_child(_stat_row(tr("Squad size"), str(int(s["squad_n"])), ThemeBuilder.COL_TEXT))
	var rep_row := HBoxContainer.new()
	rep_row.add_theme_constant_override("separation", 8)
	var rep_l := Label.new()
	rep_l.text = tr("Reputation")
	rep_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rep_l.add_theme_font_size_override("font_size", 12)
	rep_l.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	rep_row.add_child(rep_l)
	var rep_v := Label.new()
	rep_v.text = "%d/20" % int(s["rep"])
	rep_v.add_theme_font_override("font", _font_semibold)
	rep_v.add_theme_font_size_override("font_size", 12)
	rep_v.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT)
	rep_row.add_child(rep_v)
	rep_row.add_child(_meter(float(s["rep"]) / 20.0, ThemeBuilder.COL_ACCENT, 110))
	_detail_box.add_child(rep_row)
	_detail_box.add_child(_sep())
	_detail_box.add_child(_stat_row(tr("Bank balance"), "P$ %s" % _thousands(int(s["balance"])), ThemeBuilder.COL_GOOD))
	_detail_box.add_child(_stat_row(tr("Weekly wage budget"), "P$ %s" % _thousands(int(s["wage_budget"])), ThemeBuilder.COL_TEXT))

	var hint := Label.new()
	hint.text = tr("Double-click a club row to jump straight to the summary.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color("5c6480"))
	hint.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_detail_box.add_child(hint)


func _stat_row(label: String, value: String, col: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := Label.new()
	l.text = label
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	row.add_child(l)
	var v := Label.new()
	v.text = value
	v.add_theme_font_override("font", _font_semibold)
	v.add_theme_font_size_override("font_size", 12)
	v.add_theme_color_override("font_color", col)
	row.add_child(v)
	return row


func _sep() -> Control:
	var line := ColorRect.new()
	line.color = ThemeBuilder.COL_BORDER
	line.custom_minimum_size.y = 1
	return line


func _crest(s: Dictionary, px: int) -> Control:
	# procedural gym-badge crest (crests piece); rows carry the full club dict
	return Crest.icon(s.get("club", s), px, {"no_tooltip": true})


func _meter(frac: float, col: Color, w: int = 110) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(w, 8)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := ColorRect.new()
	bg.color = ThemeBuilder.COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(bg)
	var fill := ColorRect.new()
	fill.color = col
	fill.anchor_right = clampf(frac, 0.02, 1.0)
	fill.anchor_bottom = 1.0
	holder.add_child(fill)
	return holder


func _thousands(n: int) -> String:
	return ("-" if n < 0 else "") + I18n.number(absi(n))
