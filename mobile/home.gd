extends VBoxContainer
## Mobile Home (mobile piece): the manager's day at a glance — next match,
## last result, league position + form, urgent mail. Portrait, one column.


func _init() -> void:
	add_theme_constant_override("separation", 8)


func refresh() -> void:
	for c in get_children():
		c.queue_free()
	var pg := MUI.page()
	add_child(pg[0])
	var v: VBoxContainer = pg[1]

	# ---- urgent mail banner
	var urgent := 0
	for m in GameState.inbox:
		if m.get("urgent", false) and not m.get("read", false):
			urgent += 1
	if urgent > 0:
		var ub := MUI.button(tr("%d decisions waiting in the Inbox") % urgent,
			Color(ThemeBuilder.COL_WARN, 0.25), ThemeBuilder.COL_WARN)
		ub.pressed.connect(func(): _shell().open_tab("inbox"))
		v.add_child(ub)

	# ---- next match card
	var nf := GameState.next_player_fixture()
	var card := MUI.card()
	v.add_child(card[0])
	var cv: VBoxContainer = card[1]
	cv.add_child(MUI.dim(tr("NEXT MATCH").to_upper(), 10))
	if nf.is_empty():
		cv.add_child(MUI.title(tr("No matches ahead: the season is over."), 14))
	else:
		var we_home: bool = GameState.is_player_club(str(nf["home"]))
		var home: Dictionary = GameState.club(str(nf["home"]))
		var away: Dictionary = GameState.club(str(nf["away"]))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		cv.add_child(row)
		row.add_child(Crest.icon(home, 40, {"no_tooltip": true}))
		var mid := VBoxContainer.new()
		mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mid.alignment = BoxContainer.ALIGNMENT_CENTER
		mid.add_theme_constant_override("separation", 1)
		var names := MUI.title("%s — %s" % [str(home.get("short", "?")), str(away.get("short", "?"))], 16)
		names.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mid.add_child(names)
		var sub := MUI.dim("%s · %s" % [I18n.comp_label(nf), I18n.pretty_date(str(nf["date"]))], 11)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mid.add_child(sub)
		var venue := MUI.dim(tr("we host") if we_home else tr("we travel"), 11)
		venue.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mid.add_child(venue)
		row.add_child(mid)
		row.add_child(Crest.icon(away, 40, {"no_tooltip": true}))
		var days := Season.days_between(GameState.current_date, str(nf["date"]))
		var hint := MUI.dim(tr("today — Continue plays it (instant result; rotate to landscape to manage it live)") if days <= 0
			else I18n.np(days, "in %d day", "in %d days"), 11)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cv.add_child(hint)

	# ---- last result card
	var last := _last_played()
	if not last.is_empty():
		var lc := MUI.card()
		v.add_child(lc[0])
		var lv: VBoxContainer = lc[1]
		lv.add_child(MUI.dim(tr("LAST RESULT").to_upper(), 10))
		var we_home2: bool = GameState.is_player_club(str(last["home"]))
		var us := int(last["score_home"] if we_home2 else last["score_away"])
		var them := int(last["score_away"] if we_home2 else last["score_home"])
		var opp: Dictionary = GameState.club(str(last["away"] if we_home2 else last["home"]))
		var lrow := HBoxContainer.new()
		lrow.add_theme_constant_override("separation", 10)
		lv.add_child(lrow)
		lrow.add_child(Crest.icon(opp, 30, {"no_tooltip": true}))
		var res := MUI.title("%d–%d  %s %s" % [us, them,
			tr("vs") if we_home2 else tr("at"), str(opp.get("short", "?"))], 15)
		res.add_theme_color_override("font_color",
			ThemeBuilder.COL_GOOD if us > them else ThemeBuilder.COL_BAD)
		res.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		lrow.add_child(res)
		lrow.add_child(MUI.hspacer())
		var when := MUI.dim(I18n.short_date(str(last["date"])), 11)
		when.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		lrow.add_child(when)

	# ---- season status card
	var sc := MUI.card()
	v.add_child(sc[0])
	var sv: VBoxContainer = sc[1]
	sv.add_child(MUI.dim(tr("SEASON").to_upper(), 10))
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 12)
	sv.add_child(srow)
	var pos := GameState.player_table_position()
	var poscol := VBoxContainer.new()
	poscol.add_theme_constant_override("separation", 0)
	poscol.add_child(MUI.title(I18n.ordinal(pos) if pos > 0 else "—", 20))
	poscol.add_child(MUI.dim(tr(GameState.world["meta"].get("league_name", "League")), 10))
	srow.add_child(poscol)
	srow.add_child(MUI.hspacer())
	var frow := HBoxContainer.new()
	frow.add_theme_constant_override("separation", 4)
	frow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var form := Season.club_form(str(GameState.player_club()["id"]), GameState.fixtures, 5)
	if form.is_empty():
		frow.add_child(MUI.dim(tr("no matches yet"), 11))
	for r in form:
		var pip := MUI.label(tr(str(r)), 12, Color.WHITE)
		pip.add_theme_font_override("font", MUI.bold())
		var pp := PanelContainer.new()
		var col: Color = ThemeBuilder.COL_GOOD if str(r) == "W" else ThemeBuilder.COL_BAD
		pp.add_theme_stylebox_override("panel", ThemeBuilder._flat(col.darkened(0.3), col, 4, 7, 3))
		pp.add_child(pip)
		frow.add_child(pp)
	srow.add_child(frow)
	var see := MUI.button(tr("League table"))
	see.pressed.connect(func(): _shell().open_tab("league"))
	sv.add_child(see)

	# ---- landscape features note
	var note := MUI.dim(tr("Tactics, Training, Transfers, Routes, Items and live matches: rotate to landscape."), 11)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)


func _last_played() -> Dictionary:
	var best := {}
	for f in GameState.player_fixtures():
		if f.get("played", false) and (best.is_empty() or str(f["date"]) > str(best["date"])):
			best = f
	return best


func _shell() -> Node:
	var n: Node = get_parent()
	while n != null and not n.has_method("open_tab"):
		n = n.get_parent()
	return n
