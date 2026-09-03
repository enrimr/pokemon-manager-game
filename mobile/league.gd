extends VBoxContainer
## Mobile League (mobile piece): the standings + the player club's fixture
## list, portrait-shaped. Full competition suite (cup bracket, stats,
## history, playoffs) lives in landscape.

var _mode := "table"   # "table" | "fixtures"
var _club: Dictionary = {}   # drill-down: a club's profile (scout & sign here)


func _init() -> void:
	add_theme_constant_override("separation", 6)


func go_root() -> void:
	_club = {}
	refresh()


func refresh() -> void:
	for c in get_children():
		c.queue_free()
	if not _club.is_empty():
		_build_club()
		return

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	add_child(head)
	head.add_child(MUI.title(tr(GameState.world["meta"].get("league_name", "League")), 16))
	head.add_child(MUI.hspacer())
	for m in [["table", tr("Table")], ["fixtures", tr("Matches")]]:
		var key: String = m[0]
		var b := MUI.button(str(m[1]),
			ThemeBuilder.COL_ACCENT_DIM if _mode == key else Color(ThemeBuilder.COL_PANEL_ALT, 1.0),
			ThemeBuilder.COL_ACCENT if _mode == key else ThemeBuilder.COL_BORDER)
		b.custom_minimum_size = Vector2(0, 36)
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(func():
			_mode = key
			refresh())
		head.add_child(b)

	var pg := MUI.page()
	pg[0].size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(pg[0])
	var v: VBoxContainer = pg[1]
	v.add_theme_constant_override("separation", 3)
	if _mode == "table":
		_build_table(v)
	else:
		_build_fixtures(v)


# ---------------------------------------------------------------- table

func _build_table(v: VBoxContainer) -> void:
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 8)
	v.add_child(hdr)
	hdr.add_child(_cell("#", 22, ThemeBuilder.COL_TEXT_DIM))
	var club_h := _cell(tr("Club"), 0, ThemeBuilder.COL_TEXT_DIM)
	club_h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(club_h)
	for h in [tr("P"), tr("W"), tr("L"), "+/-", tr("Pts")]:
		hdr.add_child(_cell(str(h), 30, ThemeBuilder.COL_TEXT_DIM))
	v.add_child(MUI.hline())

	var table: Array = GameState.league_table()
	for i in table.size():
		var row: Dictionary = table[i]
		var club: Dictionary = GameState.club(str(row["club_id"]))
		var mine := GameState.is_player_club(str(row["club_id"]))
		var p := Button.new()
		p.focus_mode = Control.FOCUS_NONE
		p.add_theme_stylebox_override("normal", ThemeBuilder._flat(
			ThemeBuilder.COL_ACCENT_DIM.darkened(0.35) if mine else ThemeBuilder.COL_PANEL,
			ThemeBuilder.COL_ACCENT if mine else ThemeBuilder.COL_BORDER, 4, 8, 4))
		p.add_theme_stylebox_override("hover", ThemeBuilder._flat(Color("232941"),
			ThemeBuilder.COL_BORDER, 4, 8, 4))
		p.add_theme_stylebox_override("pressed", ThemeBuilder._flat(ThemeBuilder.COL_ACCENT_DIM,
			ThemeBuilder.COL_ACCENT, 4, 8, 4))
		p.pressed.connect(func():
			_club = club
			refresh())
		var h := HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_theme_constant_override("separation", 8)
		p.add_child(h)
		h.add_child(_cell(str(i + 1), 22, ThemeBuilder.COL_TEXT))
		var crow := HBoxContainer.new()
		crow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		crow.add_theme_constant_override("separation", 6)
		crow.add_child(Crest.icon(club, 22, {"no_tooltip": true}))
		var nm := MUI.label(str(club.get("short", "?")), 12,
			Color.WHITE if mine else ThemeBuilder.COL_TEXT)
		if mine:
			nm.add_theme_font_override("font", MUI.bold())
		nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		crow.add_child(nm)
		h.add_child(crow)
		var diff := int(row.get("bf", 0)) - int(row.get("ba", 0))
		for pair in [[int(row.get("played", 0)), ThemeBuilder.COL_TEXT],
				[int(row.get("won", 0)), ThemeBuilder.COL_GOOD],
				[int(row.get("lost", 0)), ThemeBuilder.COL_BAD],
				[diff, ThemeBuilder.COL_GOOD if diff >= 0 else ThemeBuilder.COL_BAD],
				[int(row.get("points", 0)), Color.WHITE]]:
			h.add_child(_cell(str(pair[0]), 30, pair[1]))
		v.add_child(p)


func _cell(text: String, w: int, col: Color) -> Label:
	var l := MUI.label(text, 11, col)
	if w > 0:
		l.custom_minimum_size.x = w
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if w > 0 else HORIZONTAL_ALIGNMENT_LEFT
	return l


# ---------------------------------------------------------------- fixtures

func _build_fixtures(v: VBoxContainer) -> void:
	var fixtures: Array = GameState.player_fixtures()
	fixtures.sort_custom(func(a, b): return str(a["date"]) < str(b["date"]))
	var next_seen := false
	for f in fixtures:
		var played: bool = f.get("played", false)
		var we_home: bool = GameState.is_player_club(str(f["home"]))
		var opp: Dictionary = GameState.club(str(f["away"] if we_home else f["home"]))
		var p := PanelContainer.new()
		var is_next: bool = not played and not next_seen
		if is_next:
			next_seen = true
		p.add_theme_stylebox_override("panel", ThemeBuilder._flat(
			ThemeBuilder.COL_ACCENT_DIM.darkened(0.35) if is_next else ThemeBuilder.COL_PANEL,
			ThemeBuilder.COL_ACCENT if is_next else ThemeBuilder.COL_BORDER, 4, 8, 5))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		p.add_child(h)
		var d := MUI.dim(I18n.short_date(str(f["date"])), 10)
		d.custom_minimum_size.x = 48
		d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(d)
		h.add_child(Crest.icon(opp, 24, {"no_tooltip": true}))
		var mid := VBoxContainer.new()
		mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mid.alignment = BoxContainer.ALIGNMENT_CENTER
		mid.add_theme_constant_override("separation", 0)
		mid.add_child(MUI.label("%s %s" % [tr("vs") if we_home else tr("at"),
			str(opp.get("short", "?"))], 12, Color.WHITE))
		mid.add_child(MUI.dim(I18n.comp_label(f), 9))
		h.add_child(mid)
		if played:
			var us := int(f["score_home"] if we_home else f["score_away"])
			var them := int(f["score_away"] if we_home else f["score_home"])
			var res := MUI.label("%d–%d" % [us, them], 13,
				ThemeBuilder.COL_GOOD if us > them else ThemeBuilder.COL_BAD)
			res.add_theme_font_override("font", MUI.bold())
			res.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(res)
		else:
			var pv := MUI.dim(tr("preview"), 10)
			pv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(pv)
		v.add_child(p)


# ---------------------------------------------------------------- club profile
## Tap a table row -> the club's profile: identity, manager, and the squad
## with the global Pokémon action menu (scout / offer / shortlist from here).
func _build_club() -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	add_child(head)
	var back := MUI.button("‹ " + tr("Table"), Color(ThemeBuilder.COL_PANEL_ALT, 1.0), ThemeBuilder.COL_BORDER)
	back.custom_minimum_size = Vector2(0, 38)
	back.pressed.connect(go_root)
	head.add_child(back)
	head.add_child(MUI.hspacer())

	var pg := MUI.page()
	pg[0].size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(pg[0])
	var v: VBoxContainer = pg[1]

	var idc := MUI.card()
	v.add_child(idc[0])
	var iv: VBoxContainer = idc[1]
	var irow := HBoxContainer.new()
	irow.add_theme_constant_override("separation", 10)
	iv.add_child(irow)
	irow.add_child(Crest.icon(_club, 44, {"no_tooltip": true}))
	var icol := VBoxContainer.new()
	icol.alignment = BoxContainer.ALIGNMENT_CENTER
	icol.add_theme_constant_override("separation", 1)
	icol.add_child(MUI.title(str(_club.get("name", "?")), 16))
	icol.add_child(MUI.dim("%s · %s %d/20" % [
		tr(GameState.league_name(str(_club.get("league", "kanto")))),
		tr("Reputation"), int(_club.get("reputation", 10))], 11))
	irow.add_child(icol)
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 8)
	iv.add_child(mrow)
	mrow.add_child(Portrait.avatar(str(_club.get("manager", "?")), 26,
		{"collar": Portrait.club_collar(_club)}))
	var ml := MUI.dim("%s · %s%s" % [str(_club.get("manager", "?")),
		str(GameState.world["meta"].get("currency", "P$")),
		I18n.number(int((_club.get("finances", {}) as Dictionary).get("balance", 0)))], 11)
	ml.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mrow.add_child(ml)

	var sc := MUI.card()
	v.add_child(sc[0])
	var sv: VBoxContainer = sc[1]
	sv.add_child(MUI.dim(tr("SQUAD").to_upper() + " · " + tr("tap Actions to scout or bid"), 10))
	var squad: Array = _club.get("squad", []).duplicate()
	squad.sort_custom(func(a, b): return int(a["level"]) > int(b["level"]))
	for inst in squad:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		sv.add_child(row)
		row.add_child(PokeArt.icon(int(inst.get("species_id", 0)), 32))
		var mid := VBoxContainer.new()
		mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mid.alignment = BoxContainer.ALIGNMENT_CENTER
		mid.add_theme_constant_override("separation", 0)
		var nrow := HBoxContainer.new()
		nrow.add_theme_constant_override("separation", 6)
		nrow.add_child(MUI.label(str(inst.get("species", "?")), 12, Color.WHITE))
		nrow.add_child(MonRoles.chip(int(inst.get("species_id", 0)), 8))
		mid.add_child(nrow)
		mid.add_child(MUI.dim(tr("Lv%d") % int(inst["level"]), 9))
		row.add_child(mid)
		if MonActions.can_act(str(inst.get("uid", ""))):
			row.add_child(MonActions.action_pill(str(inst["uid"]), tr("Actions")))
