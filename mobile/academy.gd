extends VBoxContainer
## Mobile Academy-lite (mobile piece): the youth roster, phone-shaped.
## See the intake class (current ability + judged potential band), promote a
## recruit to the first team, set their training focus, or release them —
## the SAME AcademyService the desktop Academy screen drives. Facility
## investment and the intake-day report cards stay in landscape / the inbox.

var _sel_uid := ""       # drill-down: one recruit's action sheet


func _init() -> void:
	add_theme_constant_override("separation", 6)


func go_root() -> void:
	_sel_uid = ""
	refresh()


func _svc() -> RefCounted:
	return AcademyService.active


func refresh() -> void:
	for c in get_children():
		c.queue_free()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	add_child(head)
	var back := MUI.button("‹ " + (tr("Academy") if _sel_uid != "" else tr("More")),
		Color(ThemeBuilder.COL_PANEL_ALT, 1.0), ThemeBuilder.COL_BORDER)
	back.custom_minimum_size = Vector2(0, 38)
	back.pressed.connect(func():
		if _sel_uid != "":
			go_root()
		else:
			_shell().call("open_tab", "more"))
	head.add_child(back)
	head.add_child(MUI.hspacer())

	var svc: RefCounted = _svc()
	if svc == null:
		add_child(MUI.dim(tr("Academy service unavailable."), 12))
		return
	if _sel_uid != "":
		_build_detail(svc)
	else:
		_build_roster(svc)


# ---------------------------------------------------------------- roster

func _build_roster(svc: RefCounted) -> void:
	var pg := MUI.page()
	pg[0].size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(pg[0])
	var v: VBoxContainer = pg[1]

	var idc := MUI.card()
	v.add_child(idc[0])
	var iv: VBoxContainer = idc[1]
	iv.add_child(MUI.dim(tr("YOUTH ACADEMY").to_upper(), 10))
	iv.add_child(MUI.label("%s · %s" % [str(svc.head_youth_coach()),
		tr("Facilities Lv%d") % int(svc.facility_level)], 12, Color.WHITE))
	iv.add_child(MUI.dim(tr("%d/%d recruits · next intake %s") % [svc.roster.size(),
		int(svc.roster_cap()), I18n.pretty_date(str(svc.next_intake_date()))], 10))

	if svc.roster.is_empty():
		v.add_child(MUI.dim(tr("The dormitories are empty — intake day will fill them."), 11))
		return
	var rc := MUI.card()
	v.add_child(rc[0])
	var rv: VBoxContainer = rc[1]
	rv.add_child(MUI.dim(tr("RECRUITS — tap for actions").to_upper(), 10))
	var roster: Array = svc.roster.duplicate()
	roster.sort_custom(func(a, b): return float(a.get("stars", 0)) > float(b.get("stars", 0)))
	for m in roster:
		var uid := str(m["uid"])
		var row := MUI.row(func():
			_sel_uid = uid
			refresh())
		var h: HBoxContainer = row[1]
		h.add_child(PokeArt.icon(int(m.get("species_id", 0)), 32))
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", 0)
		col.add_child(MUI.label("%s · %s" % [str(m.get("species", "?")),
			tr("Lv%d") % int(m.get("level", 1))], 13, Color.WHITE))
		var band: Array = svc.potential_stars(m)
		col.add_child(MUI.dim("%s · %s" % [_stars_text(float(m.get("stars", 0.0))),
			tr("potential %s–%s") % [_stars_text(float(band[0])), _stars_text(float(band[1]))]], 9))
		h.add_child(col)
		var age := MUI.dim(I18n.np(int(m.get("age_months", 12)), "%d month", "%d months")
			% int(m.get("age_months", 12)), 9)
		age.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(age)
		rv.add_child(row[0])
	v.add_child(MUI.dim(tr("Intake-day report cards land in the inbox. Facility investment lives in landscape."), 10))


static func _stars_text(stars: float) -> String:
	var full := int(stars)
	var half := stars - float(full) >= 0.5
	var out := ""
	for i in full:
		out += "★"
	if half:
		out += "½"
	return out if out != "" else "☆"


# ---------------------------------------------------------------- detail

func _build_detail(svc: RefCounted) -> void:
	var m: Dictionary = svc.find(_sel_uid)
	if m.is_empty():
		go_root()
		return
	var pg := MUI.page()
	pg[0].size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(pg[0])
	var v: VBoxContainer = pg[1]

	var idc := MUI.card()
	v.add_child(idc[0])
	var iv: VBoxContainer = idc[1]
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 10)
	iv.add_child(hrow)
	hrow.add_child(PokeArt.icon(int(m.get("species_id", 0)), 56))
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 1)
	col.add_child(MUI.title("%s · %s" % [str(m.get("species", "?")),
		tr("Lv%d") % int(m.get("level", 1))], 16))
	var band: Array = svc.potential_stars(m)
	col.add_child(MUI.dim("%s · %s" % [_stars_text(float(m.get("stars", 0.0))),
		tr("potential %s–%s") % [_stars_text(float(band[0])), _stars_text(float(band[1]))]], 10))
	col.add_child(MUI.dim("%s · %s" % [
		I18n.np(int(m.get("age_months", 12)), "%d month", "%d months") % int(m.get("age_months", 12)),
		tr("joined %s") % I18n.pretty_date(str(m.get("joined", "")))], 10))
	hrow.add_child(col)

	# training focus
	var fc := MUI.card()
	v.add_child(fc[0])
	var fv: VBoxContainer = fc[1]
	fv.add_child(MUI.dim(tr("TRAINING FOCUS").to_upper(), 10))
	var frow := HFlowContainer.new()
	frow.add_theme_constant_override("h_separation", 6)
	frow.add_theme_constant_override("v_separation", 6)
	fv.add_child(frow)
	for f in AcademyService.FOCUSES:
		var fname := str(f)
		var active := fname == str(m.get("focus", "balanced"))
		var b := MUI.button(tr(str(AcademyService.FOCUS_LABELS[fname])),
			ThemeBuilder.COL_ACCENT_DIM if active else Color(ThemeBuilder.COL_PANEL_ALT, 1.0),
			ThemeBuilder.COL_ACCENT if active else ThemeBuilder.COL_BORDER)
		b.custom_minimum_size = Vector2(0, 36)
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(func():
			svc.set_focus(_sel_uid, fname)
			GameState.save_game()
			refresh())
		frow.add_child(b)

	# actions
	var promote := MUI.button(tr("Promote to the first team"),
		Color(ThemeBuilder.COL_GOOD, 0.22), ThemeBuilder.COL_GOOD)
	promote.pressed.connect(func():
		var err := str(_svc().promote(_sel_uid))
		_shell().call("toast", err if err != "" else tr("%s joins the first team!") % str(m.get("species", "?")))
		if err == "":
			GameState.save_game()
			go_root()
		)
	v.add_child(promote)
	var rel := MUI.button(tr("Release from the academy"),
		Color(ThemeBuilder.COL_WARN, 0.18), ThemeBuilder.COL_WARN)
	rel.pressed.connect(func(): _confirm_release(m))
	v.add_child(rel)


func _confirm_release(m: Dictionary) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.dialog_autowrap = true
	dlg.title = tr("Release this recruit?")
	dlg.ok_button_text = tr("Release")
	dlg.dialog_text = tr("%s (Lv%d) leaves the academy for good. Scouts of rival clubs are already at the gate.") % [
		str(m.get("species", "?")), int(m.get("level", 1))]
	dlg.confirmed.connect(func():
		var err := str(_svc().release(_sel_uid))
		_shell().call("toast", err if err != "" else tr("%s released.") % str(m.get("species", "?")))
		GameState.save_game()
		go_root())
	add_child(dlg)
	dlg.popup_centered(Vector2i(mini(420, int(get_viewport_rect().size.x) - 20), 0))


func _shell() -> Node:
	var n: Node = get_parent()
	while n != null and not n.has_method("open_tab"):
		n = n.get_parent()
	return n
