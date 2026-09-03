extends VBoxContainer
## Mobile Routes (mobile piece): the capture loop, phone-shaped. Pick a
## route, pick a leader and an approach, send the party — field reports and
## captures land in the inbox, powered by the SAME ExpeditionService the
## desktop Routes screen drives. Deep planning (knowledge maps, history)
## stays in landscape.

var _route_id := ""      # drill-down: planning a specific route
var _days := 5
var _approach := "balanced"
var _attempts := 6
var _leader_id := ""


func _init() -> void:
	add_theme_constant_override("separation", 6)


func go_root() -> void:
	_route_id = ""
	refresh()


func _svc() -> RefCounted:
	return ExpeditionService.active


func refresh() -> void:
	for c in get_children():
		c.queue_free()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	add_child(head)
	var back := MUI.button("‹ " + (tr("Routes") if _route_id != "" else tr("More")),
		Color(ThemeBuilder.COL_PANEL_ALT, 1.0), ThemeBuilder.COL_BORDER)
	back.custom_minimum_size = Vector2(0, 38)
	back.pressed.connect(func():
		if _route_id != "":
			go_root()
		else:
			_shell().call("open_tab", "more"))
	head.add_child(back)
	head.add_child(MUI.hspacer())

	if _svc() == null:
		add_child(MUI.dim(tr("Expedition service unavailable."), 12))
		return
	if _route_id != "":
		_build_planner()
	else:
		_build_list()


# ---------------------------------------------------------------- route list

func _build_list() -> void:
	var svc: RefCounted = _svc()
	var pg := MUI.page()
	pg[0].size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(pg[0])
	var v: VBoxContainer = pg[1]

	# active parties first
	var act: Array = svc.expeditions
	if not act.is_empty():
		var ac := MUI.card()
		v.add_child(ac[0])
		var av: VBoxContainer = ac[1]
		av.add_child(MUI.dim(tr("PARTIES IN THE FIELD").to_upper(), 10))
		for exp in act:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			av.add_child(row)
			var col := VBoxContainer.new()
			col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			col.add_theme_constant_override("separation", 0)
			col.add_child(MUI.label("%s — %s" % [tr(str(exp["route_name"])), str(exp["leader"])], 12, Color.WHITE))
			col.add_child(MUI.dim(tr("%s · day %d · %d captures · %d attempts left") % [
				tr(str(exp["phase"])), int(exp["day_no"]), (exp["captures"] as Array).size(),
				int(exp["attempts_left"])], 10))
			row.add_child(col)
			var rec := MUI.button(tr("Recall"), Color(ThemeBuilder.COL_WARN, 0.2), ThemeBuilder.COL_WARN)
			rec.custom_minimum_size = Vector2(0, 34)
			rec.add_theme_font_size_override("font_size", 11)
			rec.pressed.connect(func():
				var err := str(svc.recall(str(exp["id"])))
				_shell().call("toast", err if err != "" else tr("Party recalled — reports on the way home."))
				refresh())
			row.add_child(rec)

	# routes by region
	for region_v in [svc.player_region(), _other_region(svc)]:
		var region := str(region_v)
		var rc := MUI.card()
		v.add_child(rc[0])
		var rv: VBoxContainer = rc[1]
		rv.add_child(MUI.dim(str(region).to_upper(), 10))
		for r in ExpeditionService.region_routes(region):
			var rid := str(r["id"])
			var row := MUI.row(func():
				_route_id = rid
				_leader_id = ""
				refresh())
			var h: HBoxContainer = row[1]
			var col := VBoxContainer.new()
			col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			col.alignment = BoxContainer.ALIGNMENT_CENTER
			col.add_theme_constant_override("separation", 0)
			col.add_child(MUI.label(tr(str(r["name"])), 12, Color.WHITE))
			var band: Array = r.get("levels", [5, 20])
			col.add_child(MUI.dim("%s · Lv %d–%d · %s" % [_terrain_text(r),
				int(band[0]), int(band[1]),
				tr("knowledge %d/3") % svc.knowledge_tier(rid)], 9))
			h.add_child(col)
			var side := VBoxContainer.new()
			side.alignment = BoxContainer.ALIGNMENT_CENTER
			var cool := str(svc.cooldown_until(rid))
			if not svc.expedition_on(rid).is_empty():
				side.add_child(MUI.label(tr("IN THE FIELD"), 9, ThemeBuilder.COL_ACCENT.lightened(0.2)))
			elif cool != "":
				side.add_child(MUI.label(tr("settles %s") % I18n.short_date(cool), 9, ThemeBuilder.COL_WARN))
			h.add_child(side)
			rv.add_child(row[0])


func _other_region(svc: RefCounted) -> String:
	for r in ExpeditionService.routes():
		if str(r["region"]) != str(svc.player_region()):
			return str(r["region"])
	return str(svc.player_region())


# ---------------------------------------------------------------- planner

func _build_planner() -> void:
	var svc: RefCounted = _svc()
	var r: Dictionary = ExpeditionService.route(_route_id)
	var pg := MUI.page()
	pg[0].size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(pg[0])
	var v: VBoxContainer = pg[1]

	var idc := MUI.card()
	v.add_child(idc[0])
	var iv: VBoxContainer = idc[1]
	iv.add_child(MUI.title(tr(str(r["name"])), 16))
	var band: Array = r.get("levels", [5, 20])
	iv.add_child(MUI.dim("%s · %s · Lv %d–%d · %s" % [tr(str(r["region"])),
		_terrain_text(r), int(band[0]), int(band[1]),
		I18n.np(int(r.get("travel", 1)), "%d travel day", "%d travel days") % int(r.get("travel", 1))], 11))
	var blurb := MUI.dim(tr(str(r.get("blurb", ""))), 11)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	iv.add_child(blurb)

	var plc := MUI.card()
	v.add_child(plc[0])
	var pv: VBoxContainer = plc[1]
	pv.add_child(MUI.dim(tr("PLAN THE EXPEDITION").to_upper(), 10))

	pv.add_child(MUI.dim(tr("Field days"), 10))
	pv.add_child(_choice_row([["3", 3], ["5", 5], ["8", 8], ["12", 12]],
		func(val): return int(val) == _days,
		func(val):
			_days = int(val)
			refresh()))
	pv.add_child(MUI.dim(tr("Approach"), 10))
	pv.add_child(_choice_row([[tr("Cautious"), "cautious"], [tr("Balanced"), "balanced"], [tr("Aggressive"), "aggressive"]],
		func(val): return str(val) == _approach,
		func(val):
			_approach = str(val)
			refresh()))
	pv.add_child(MUI.dim(tr("Capture attempts"), 10))
	pv.add_child(_choice_row([["2", 2], ["6", 6], ["10", 10]],
		func(val): return int(val) == _attempts,
		func(val):
			_attempts = int(val)
			refresh()))

	pv.add_child(MUI.dim(tr("Leader"), 10))
	var lsel := OptionButton.new()
	lsel.custom_minimum_size.y = 42
	var lds: Array = svc.leaders()
	var sel_idx := 0
	for i in lds.size():
		var l: Dictionary = lds[i]
		lsel.add_item("%s (%s · %d/20)%s" % [str(l["name"]), tr(str(l["role"])),
			int(l["skill"]), tr(" — BUSY") if bool(l["busy"]) else ""], i)
		if _leader_id == "" and not bool(l["busy"]):
			_leader_id = str(l["id"])
		if str(l["id"]) == _leader_id:
			sel_idx = i
	lsel.selected = sel_idx
	lsel.item_selected.connect(func(i):
		_leader_id = str(lds[i]["id"]))
	pv.add_child(lsel)

	var cost := int(svc.cost_quote(_route_id, _days, _attempts))
	var go := MUI.button(tr("Send the party · %s%s") % [
		str(GameState.world["meta"].get("currency", "P$")), I18n.number(cost)],
		Color(ThemeBuilder.COL_GOOD, 0.22), ThemeBuilder.COL_GOOD)
	go.pressed.connect(func():
		var err := str(svc.plan(_route_id, _days, _leader_id, _approach, _attempts, "academy"))
		_shell().call("toast", err if err != "" else tr("Party dispatched — field reports by mail."))
		if err == "":
			GameState.save_game()
			go_root())
	v.add_child(go)
	v.add_child(MUI.dim(tr("Captures land in the ACADEMY. Costs come off the transfer budget, up front."), 10))


func _choice_row(options: Array, is_sel: Callable, on_pick: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for opt in options:
		var sel: bool = is_sel.call(opt[1])
		var b := MUI.button(str(opt[0]),
			ThemeBuilder.COL_ACCENT_DIM if sel else Color(ThemeBuilder.COL_PANEL_ALT, 1.0),
			ThemeBuilder.COL_ACCENT if sel else ThemeBuilder.COL_BORDER)
		b.custom_minimum_size = Vector2(0, 38)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 12)
		var val = opt[1]
		b.pressed.connect(func(): on_pick.call(val))
		row.add_child(b)
	return row


static func _terrain_text(r: Dictionary) -> String:
	var parts: Array = []
	for t in r.get("terrain", []):
		parts.append(I18n.t(str(t).capitalize()))
	return " / ".join(parts)


func _shell() -> Node:
	var n: Node = get_parent()
	while n != null and not n.has_method("open_tab"):
		n = n.get_parent()
	return n
