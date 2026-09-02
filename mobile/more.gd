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
		{"collar": Portrait.club_collar(GameState.player_club())}))
	var mcol := VBoxContainer.new()
	mcol.alignment = BoxContainer.ALIGNMENT_CENTER
	mcol.add_theme_constant_override("separation", 1)
	mcol.add_child(MUI.title(MenuFlow.manager_name(), 15))
	mcol.add_child(MUI.dim("%s · %s" % [str(GameState.player_club().get("name", "?")),
		tr(GameState.world["meta"].get("league_name", "League"))], 11))
	mrow.add_child(mcol)

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
