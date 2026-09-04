extends VBoxContainer
## Mobile More (mobile piece): the manager card, quick settings (language,
## UI scale, audio), save controls, and an honest map of what lives in
## landscape. No new systems — thin dials over Settings + GameState.


func _init() -> void:
	add_theme_constant_override("separation", 6)


func refresh() -> void:
	for c in get_children():
		c.queue_free()
	var pg := MUI.page()
	add_child(pg[0])
	var v: VBoxContainer = pg[1]

	# ---- manager card
	var mc := MUI.card()
	v.add_child(mc[0])
	var mv: VBoxContainer = mc[1]
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 10)
	mv.add_child(mrow)
	mrow.add_child(Portrait.avatar(Portrait.manager_seed(), 46,
		Portrait.manager_opts({"collar": Portrait.club_collar(GameState.player_club())})))
	var mcol := VBoxContainer.new()
	mcol.alignment = BoxContainer.ALIGNMENT_CENTER
	mcol.add_theme_constant_override("separation", 1)
	mcol.add_child(MUI.title(MenuFlow.manager_name(), 15))
	mcol.add_child(MUI.dim("%s · %s" % [str(GameState.player_club().get("name", "?")),
		tr(GameState.world["meta"].get("league_name", "League"))], 11))
	mrow.add_child(mcol)

	# ---- club desk shortcuts: the bag & store, and the wild routes
	var hub := HBoxContainer.new()
	hub.add_theme_constant_override("separation", 8)
	v.add_child(hub)
	var items_btn := MUI.button(tr("Items & Store"))
	items_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	items_btn.pressed.connect(func(): _shell().call("open_tab", "items"))
	hub.add_child(items_btn)
	var routes_btn := MUI.button(tr("Routes & Expeditions"))
	routes_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	routes_btn.pressed.connect(func(): _shell().call("open_tab", "routes"))
	hub.add_child(routes_btn)
	var tac_btn := MUI.button(tr("Tactics & Battle Plan"))
	tac_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tac_btn.pressed.connect(func(): _shell().call("open_tab", "tactics"))
	hub.add_child(tac_btn)
	var aca_btn := MUI.button(tr("Youth Academy"))
	aca_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	aca_btn.pressed.connect(func(): _shell().call("open_tab", "academy"))
	hub.add_child(aca_btn)

	# ---- weekly training (express): one tap stamps a preset on THIS week
	var tc := MUI.card()
	v.add_child(tc[0])
	var tv: VBoxContainer = tc[1]
	tv.add_child(MUI.dim(tr("THIS WEEK'S TRAINING").to_upper(), 10))
	var tsvc: Node = load("res://screens/training/training_service.gd").ensure()
	var tgrid := GridContainer.new()
	tgrid.columns = 2
	tgrid.add_theme_constant_override("h_separation", 6)
	tgrid.add_theme_constant_override("v_separation", 6)
	tv.add_child(tgrid)
	for preset_v in tsvc.PRESETS:
		var preset := str(preset_v)
		var pb := MUI.button(tr(str(tsvc.PRESET_LABELS[preset])), Color(ThemeBuilder.COL_PANEL_ALT, 1.0), ThemeBuilder.COL_BORDER)
		pb.custom_minimum_size.y = 40
		pb.add_theme_font_size_override("font_size", 12)
		pb.pressed.connect(func():
			tsvc.apply_preset_to_week(preset, GameState.current_date)
			var sh: Node = _shell()
			if sh != null:
				sh.call("toast", tr("%s week set — training runs it from today.") % tr(str(tsvc.PRESET_LABELS[preset]))))
		tgrid.add_child(pb)
	tv.add_child(MUI.dim(tr("The full calendar, coaches and mentoring live in landscape."), 10))

	# ---- the boardroom: confidence + real requests (shares the inbox's board)
	_build_board_card(v)

	# ---- quick settings
	var sc := MUI.card()
	v.add_child(sc[0])
	var sv: VBoxContainer = sc[1]
	sv.add_child(MUI.dim(tr("SETTINGS").to_upper(), 10))

	var lrow := HBoxContainer.new()
	lrow.add_theme_constant_override("separation", 8)
	sv.add_child(lrow)
	var ll := MUI.label(tr("Language"), 13)
	ll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lrow.add_child(ll)
	var lsel := OptionButton.new()
	lsel.custom_minimum_size = Vector2(130, 40)
	lsel.add_item("English", 0)
	lsel.add_item("Español", 1)
	lsel.selected = 1 if str(Settings.get_setting("locale")) == "es" else 0
	lsel.item_selected.connect(func(i):
		Settings.set_setting("locale", "es" if i == 1 else "en")
		refresh())
	lrow.add_child(lsel)

	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 8)
	sv.add_child(srow)
	var sl := MUI.label(tr("UI scale"), 13)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	srow.add_child(sl)
	var ssel := OptionButton.new()
	ssel.custom_minimum_size = Vector2(130, 40)
	for i in Settings.UI_SCALES.size():
		ssel.add_item("%d%%" % int(float(Settings.UI_SCALES[i]) * 100.0), i)
		if is_equal_approx(float(Settings.UI_SCALES[i]), float(Settings.get_setting("ui_scale"))):
			ssel.selected = i
	ssel.item_selected.connect(func(i):
		Settings.set_setting("ui_scale", Settings.UI_SCALES[i]))
	srow.add_child(ssel)

	var arow := HBoxContainer.new()
	arow.add_theme_constant_override("separation", 8)
	sv.add_child(arow)
	var al := MUI.label(tr("Sound"), 13)
	al.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arow.add_child(al)
	var achk := CheckButton.new()
	achk.button_pressed = bool(Settings.get_setting("audio_enabled", true))
	achk.toggled.connect(func(on): Settings.set_setting("audio_enabled", on))
	arow.add_child(achk)

	# ---- save
	var svc := MUI.card()
	v.add_child(svc[0])
	var vv: VBoxContainer = svc[1]
	vv.add_child(MUI.dim(tr("CAREER").to_upper(), 10))
	var save := MUI.button(tr("Save Game"))
	save.pressed.connect(func():
		GameState.save_game()
		var sh: Node = _shell()
		if sh != null:
			sh.call("toast", tr("Saved.")))
	vv.add_child(save)
	vv.add_child(MUI.dim(tr("The game autosaves whenever you Continue."), 10))

	# ---- landscape map
	var lc := MUI.card()
	v.add_child(lc[0])
	var lv: VBoxContainer = lc[1]
	lv.add_child(MUI.dim(tr("IN LANDSCAPE").to_upper(), 10))
	var txt := MUI.label(tr("Rotate the phone for the full manager desk: Tactics, Training, Transfers, Routes, Items, Academy, Board & Finances and live manual matches."), 12)
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lv.add_child(txt)


func _shell() -> Node:
	var n: Node = get_parent()
	while n != null and not n.has_method("toast"):
		n = n.get_parent()
	return n


## Boardroom card: live confidence (with the three faces) + the request
## system — the same BoardRoom the inbox drives, so state/pending are shared.
func _build_board_card(v: VBoxContainer) -> void:
	var sh: Node = _shell()
	if sh == null or not ("_pages" in sh):
		return
	var inbox_page: Node = sh.get("_pages").get("inbox")
	if inbox_page == null:
		return
	var board: RefCounted = inbox_page.get("board")
	var news: RefCounted = inbox_page.get("news")
	if board == null or news == null:
		return
	var bc := MUI.card()
	v.add_child(bc[0])
	var bv: VBoxContainer = bc[1]
	bv.add_child(MUI.dim(tr("BOARD & FINANCES").to_upper(), 10))
	var pc: Dictionary = GameState.player_club()
	var frow := HBoxContainer.new()
	frow.add_theme_constant_override("separation", 10)
	bv.add_child(frow)
	for member in Portrait.board_members(pc):
		frow.add_child(Portrait.avatar(str(member["name"]), 28,
			{"collar": Portrait.club_collar(pc), "age": int(member["age"]),
			"tooltip": "%s — %s" % [str(member["name"]), tr(str(member["role"]))]}))
	var conf: Dictionary = news.call("board_confidence")
	var score := int(conf.get("score", 60))
	var word := MUI.label("%s · %d%%" % [tr(str(conf.get("word", "steady"))).to_upper(), score], 13,
		ThemeBuilder.COL_GOOD if score >= 65 else (ThemeBuilder.COL_WARN if score >= 45 else ThemeBuilder.COL_BAD))
	word.add_theme_font_override("font", MUI.bold())
	word.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frow.add_child(MUI.hspacer())
	frow.add_child(word)

	var pending: Dictionary = board.call("pending_request")
	if not pending.is_empty():
		var pl := MUI.label(tr("Request pending: %s — the board is deliberating.") %
			tr(str(pending.get("title", "?"))), 12, ThemeBuilder.COL_WARN)
		pl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bv.add_child(pl)
		return
	for def_v in board.call("request_defs"):
		var d: Dictionary = def_v
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		bv.add_child(row)
		var t := MUI.label(tr(str(d.get("title", "?"))), 12)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(t)
		for opt_v in d.get("options", []):
			var opt: Dictionary = opt_v
			var ob := MUI.button(str(opt.get("label", "?")), Color(ThemeBuilder.COL_PANEL_ALT, 1.0), ThemeBuilder.COL_BORDER)
			ob.custom_minimum_size.y = 38
			ob.add_theme_font_size_override("font_size", 11)
			ob.pressed.connect(func():
				var err := str(board.call("submit", str(d["kind"]), int(opt["amount"])))
				var sh2: Node = _shell()
				if sh2 != null:
					sh2.call("toast", err if err != "" else tr("Request sent — the board will answer by mail."))
				refresh())
			row.add_child(ob)
