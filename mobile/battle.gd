extends VBoxContainer
## Mobile Battle (mobile piece) — the core of the game, phone-native: the
## classic portrait battle framing (foe up top, your battler under your
## thumb, moves in a 2x2 grid). Drives the SAME MatchRunner state machine as
## the desktop match screen — engine, previews, doubles targeting, items,
## delegation, ratings — only the presentation is phone-shaped. The runner
## lives in a static, so rotating to landscape mid-match hands the series to
## the desktop Match screen intact (and back).

const MatchRunner := preload("res://screens/match/match_runner.gd")
const Commentary := preload("res://screens/match/commentary.gd")

var runner = null
var _clock := 0.0
var _speed := 1.0
var _live_battle_built := -1
var _actions_built := false
var _picking := ""           # "" | "switch" | "item" | "target"
var _pending_move: Dictionary = {}
var _order_slot := -1        # doubles: slot being ordered

# live refs
var _hdr_lbl: Label
var _wins_lbl: Label
var _foe_zone: VBoxContainer
var _our_zone: VBoxContainer
var _ticker: RichTextLabel
var _action_area: VBoxContainer


func _init() -> void:
	add_theme_constant_override("separation", 6)


## Entry: called by the shell with the due fixture (or resumes a live one).
func open_for(fixture: Dictionary) -> void:
	if MatchRunner.active != null:
		runner = MatchRunner.active
	elif not fixture.is_empty():
		runner = MatchRunner.begin(fixture)
	refresh()


func refresh() -> void:
	_live_battle_built = -1
	_actions_built = false
	_picking = ""
	_order_slot = -1
	for c in get_children():
		c.queue_free()
	if runner == null or (runner.fixture.get("played", false) and runner.phase != runner.Phase.POST):
		_build_empty()
		return
	match runner.phase:
		runner.Phase.PRE:
			_build_pre()
		runner.Phase.LIVE:
			_build_live()
		runner.Phase.POST:
			_build_post()


func _shell() -> Node:
	var n: Node = get_parent()
	while n != null and not n.has_method("open_tab"):
		n = n.get_parent()
	return n


func _leave() -> void:
	MatchRunner.clear()
	runner = null
	var sh: Node = _shell()
	if sh != null:
		sh.call("close_battle")


# ================================================================== PRE

func _build_pre() -> void:
	var pg := MUI.page()
	pg[0].size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(pg[0])
	var v: VBoxContainer = pg[1]

	# leaving prematch keeps the held fixture (Home's match-due card remains)
	var exit_row := HBoxContainer.new()
	v.add_child(exit_row)
	var back := MUI.button("‹ " + tr("Back to the club"), Color(ThemeBuilder.COL_PANEL_ALT, 1.0), ThemeBuilder.COL_BORDER)
	back.custom_minimum_size = Vector2(0, 36)
	back.pressed.connect(func():
		var sh: Node = _shell()
		if sh != null:
			sh.call("close_battle"))
	exit_row.add_child(back)
	exit_row.add_child(MUI.hspacer())

	var opp: Dictionary = runner.opponent_club()
	var head := MUI.card()
	v.add_child(head[0])
	var hv: VBoxContainer = head[1]
	hv.add_child(MUI.dim(tr("MATCHDAY").to_upper(), 10))
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 10)
	hv.add_child(hrow)
	hrow.add_child(Crest.icon(opp, 40, {"no_tooltip": true}))
	var hcol := VBoxContainer.new()
	hcol.alignment = BoxContainer.ALIGNMENT_CENTER
	hcol.add_theme_constant_override("separation", 1)
	hcol.add_child(MUI.title("%s %s" % [tr("vs") if runner.player_side == 0 else tr("at"),
		str(opp.get("name", "?"))], 16))
	hcol.add_child(MUI.dim(I18n.comp_label(runner.fixture), 11))
	hrow.add_child(hcol)
	var fmt := MUI.dim(tr("Best of 3 · game 2 is 2v2 DOUBLES") if str(runner.fixture["comp"]) == "cup"
		else tr("Three games of 6v6 singles"), 11)
	hv.add_child(fmt)

	# lineup order (lead first) — ▲ nudges a battler up one slot
	var lc := MUI.card()
	v.add_child(lc[0])
	var lv: VBoxContainer = lc[1]
	lv.add_child(MUI.dim(tr("STARTING SIX — lead first").to_upper(), 10))
	for i in runner.starting_six.size():
		var inst: Dictionary = runner.starting_six[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		lv.add_child(row)
		row.add_child(MUI.dim(str(i + 1), 11))
		row.add_child(PokeArt.icon(int(inst.get("species_id", 0)), 30))
		var nm := MUI.label("%s  ·  %s" % [_inst_name(inst), tr("Lv%d") % int(inst["level"])], 13,
			Color.WHITE if i == 0 else ThemeBuilder.COL_TEXT)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nm)
		if i > 0:
			var up := Button.new()
			up.icon = GlyphIcons.tex("arrow_up", 12, ThemeBuilder.COL_TEXT)
			up.custom_minimum_size = Vector2(40, 34)
			up.focus_mode = Control.FOCUS_NONE
			up.pressed.connect(func():
				var tmp = runner.starting_six[i - 1]
				runner.starting_six[i - 1] = runner.starting_six[i]
				runner.starting_six[i] = tmp
				refresh())
			row.add_child(up)

	var go := MUI.button(tr("Start the match"), Color(ThemeBuilder.COL_GOOD, 0.22), ThemeBuilder.COL_GOOD)
	go.pressed.connect(func():
		runner.set_policy("full_control", true)
		runner.confirm_lineup()
		refresh())
	v.add_child(go)
	var dele := MUI.button(tr("Delegate to the coach and watch"))
	dele.pressed.connect(func():
		runner.set_policy("full_control", false)
		runner.confirm_lineup()
		refresh())
	v.add_child(dele)
	var inst_btn := MUI.button(tr("Instant result"), Color(ThemeBuilder.COL_PANEL_ALT, 1.0), ThemeBuilder.COL_BORDER)
	inst_btn.pressed.connect(func():
		runner.instant_result()
		refresh())
	v.add_child(inst_btn)


# ================================================================== LIVE

func _build_live() -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	add_child(head)
	_hdr_lbl = MUI.dim("", 11)
	head.add_child(_hdr_lbl)
	head.add_child(MUI.hspacer())
	_wins_lbl = MUI.title("", 14)
	head.add_child(_wins_lbl)

	_foe_zone = VBoxContainer.new()
	_foe_zone.add_theme_constant_override("separation", 4)
	add_child(_foe_zone)

	_ticker = RichTextLabel.new()
	_ticker.bbcode_enabled = true
	_ticker.scroll_following = true
	_ticker.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ticker.custom_minimum_size.y = 90
	_ticker.add_theme_font_size_override("normal_font_size", 11)
	_ticker.add_theme_constant_override("line_separation", 3)
	add_child(_ticker)

	_our_zone = VBoxContainer.new()
	_our_zone.add_theme_constant_override("separation", 4)
	add_child(_our_zone)

	_action_area = VBoxContainer.new()
	_action_area.add_theme_constant_override("separation", 5)
	add_child(_action_area)

	# footer controls: speed / skip / delegate
	var ctl := HBoxContainer.new()
	ctl.add_theme_constant_override("separation", 6)
	add_child(ctl)
	var spd := MUI.button("x1", Color(ThemeBuilder.COL_PANEL_ALT, 1.0), ThemeBuilder.COL_BORDER)
	spd.custom_minimum_size = Vector2(56, 36)
	spd.pressed.connect(func():
		_speed = 3.0 if _speed < 2.0 else 1.0
		spd.text = "x3" if _speed > 2.0 else "x1")
	ctl.add_child(spd)
	var skip := MUI.button(tr("Skip game"), Color(ThemeBuilder.COL_PANEL_ALT, 1.0), ThemeBuilder.COL_BORDER)
	skip.custom_minimum_size.y = 36
	skip.pressed.connect(func():
		runner.skip_battle()
		_sync())
	ctl.add_child(skip)
	ctl.add_child(MUI.hspacer())
	var dele := MUI.button(tr("Coach"), Color(ThemeBuilder.COL_PANEL_ALT, 1.0), ThemeBuilder.COL_BORDER)
	dele.custom_minimum_size.y = 36
	dele.tooltip_text = tr("Delegate the calls to the coach")
	dele.pressed.connect(func():
		runner.set_policy("full_control", not bool(runner.policy["full_control"]))
		dele.text = tr("Coach ON") if not bool(runner.policy["full_control"]) else tr("Coach")
		_actions_built = false
		_refresh_actions())
	ctl.add_child(dele)

	_zone_state = {}
	_live_battle_built = int(runner.battle_no)
	_sync()


## Persistent battler cards: built once per switch-in, then UPDATED — the
## HP bar drains with a tween and the number counts down (user request),
## instead of snapping to the new total.
var _zone_state := {}   # side -> {names, cards: [refs], bench: Label}


func _battler_card(b: Dictionary, foe: bool) -> Dictionary:
	var card := PanelContainer.new()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	card.add_child(v)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	v.add_child(row)
	var art := PokeArt.icon(PokeArt.id_of(str(b.get("species", b.get("name", "")))), 44,
		{"flip": not foe})
	row.add_child(art)
	var nm := MUI.label(str(b.get("name", "?")), 13, Color.WHITE)
	nm.add_theme_font_override("font", MUI.bold())
	row.add_child(nm)
	row.add_child(MUI.dim(tr("Lv%d") % int(b.get("level", 1)), 10))
	for t in b.get("types", []):
		row.add_child(MUI.type_chip(str(t)))
	row.add_child(MUI.hspacer())
	var status := MUI.label("", 9, ThemeBuilder.COL_WARN)
	row.add_child(status)
	var bar_bg := PanelContainer.new()
	bar_bg.custom_minimum_size.y = 9
	bar_bg.add_theme_stylebox_override("panel", ThemeBuilder._flat(Color("14161f"), ThemeBuilder.COL_BORDER, 4, 0, 0))
	var fill := ColorRect.new()
	fill.custom_minimum_size = Vector2(0, 9)
	fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	bar_bg.add_child(fill)
	v.add_child(bar_bg)
	var hp := MUI.dim("", 10)
	hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(hp)
	var refs := {"root": card, "art": art, "nm": nm, "status": status,
		"fill": fill, "hp": hp, "foe": foe,
		"frac": -1.0, "hp_shown": int(b.get("hp", 0)), "tw": null}
	_update_card(refs, b, false)
	return refs


static func _hp_color(frac: float) -> Color:
	return ThemeBuilder.COL_GOOD if frac > 0.5 \
		else (ThemeBuilder.COL_WARN if frac > 0.22 else ThemeBuilder.COL_BAD)


func _update_card(refs: Dictionary, b: Dictionary, animate: bool = true) -> void:
	var fainted: bool = bool(b.get("fainted", false))
	var foe: bool = bool(refs["foe"])
	(refs["root"] as PanelContainer).add_theme_stylebox_override("panel", ThemeBuilder._flat(
		ThemeBuilder.COL_PANEL.darkened(0.25) if fainted else ThemeBuilder.COL_PANEL,
		ThemeBuilder.COL_BORDER if fainted
		else (ThemeBuilder.COL_BAD if foe else ThemeBuilder.COL_ACCENT), 6, 10, 6))
	(refs["art"] as Control).modulate = Color(0.42, 0.42, 0.5, 0.85) if fainted else Color.WHITE
	(refs["nm"] as Label).add_theme_color_override("font_color",
		ThemeBuilder.COL_TEXT_DIM if fainted else Color.WHITE)
	var st := str(b.get("status", ""))
	if fainted:
		st = "fainted"
	var status: Label = refs["status"]
	status.visible = st != ""
	status.text = I18n.t(st).to_upper() if st != "" else ""
	var max_hp := maxf(float(b.get("max_hp", 1)), 1.0)
	var frac := clampf(float(b.get("hp", 0)) / max_hp, 0.0, 1.0)
	var fill: ColorRect = refs["fill"]
	var hp_lbl: Label = refs["hp"]
	if not animate or refs["frac"] < 0.0:
		if refs["tw"] != null and (refs["tw"] as Tween).is_valid():
			(refs["tw"] as Tween).kill()
		fill.anchor_right = frac
		fill.color = _hp_color(frac)
		hp_lbl.text = "%d / %d" % [int(b.get("hp", 0)), int(max_hp)]
	elif not is_equal_approx(frac, float(refs["frac"])):
		if refs["tw"] != null and (refs["tw"] as Tween).is_valid():
			(refs["tw"] as Tween).kill()
		fill.color = _hp_color(frac)
		var from_hp := float(refs.get("hp_shown", int(max_hp)))
		var to_hp := float(b.get("hp", 0))
		var tw := fill.create_tween()
		tw.tween_property(fill, "anchor_right", frac, 0.38) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_method(func(v: float):
			hp_lbl.text = "%d / %d" % [int(round(v)), int(max_hp)],
			from_hp, to_hp, 0.38)
		refs["tw"] = tw
	refs["frac"] = frac
	refs["hp_shown"] = int(b.get("hp", 0))


func _sync() -> void:
	if runner == null or runner.phase != runner.Phase.LIVE or _hdr_lbl == null:
		return
	var mode := tr("DOUBLES 2v2") if runner.doubles_now() else tr("SINGLES")
	_hdr_lbl.text = "%s %d/3 · %s · %s %d" % [tr("Game"), int(runner.battle_no), mode, tr("Turn"), int(runner.turn_now)]
	var shorts: Array = runner.shorts()
	_wins_lbl.text = "%s %d – %d %s" % [str(shorts[runner.player_side]), int(runner.wins[runner.player_side]),
		int(runner.wins[1 - runner.player_side]), str(shorts[1 - runner.player_side])]
	_sync_zone(_foe_zone, 1 - runner.player_side)
	_sync_zone(_our_zone, runner.player_side)
	var tail := ""
	var from := maxi(0, runner.ticker.size() - 7)
	for i in range(from, runner.ticker.size()):
		tail += str(runner.ticker[i]["text"]) + "\n"
	_ticker.text = tail


func _sync_zone(zone: VBoxContainer, side: int) -> void:
	var team: Array = runner.vm["teams"][side]
	var actives: Array = runner.vm["actives"][side]
	var names: Array = []
	for slot in actives:
		var idx := int(slot)
		names.append(str(team[idx]["name"]) if idx >= 0 and idx < team.size() else "")
	var st: Dictionary = _zone_state.get(side, {})
	if st.is_empty() or (st.get("names", []) as Array) != names:
		for c in zone.get_children():
			zone.remove_child(c)
			c.free()
		var cards: Array = []
		for slot in actives:
			var idx := int(slot)
			if idx >= 0 and idx < team.size():
				var refs := _battler_card(team[idx], side != runner.player_side)
				zone.add_child(refs["root"])
				cards.append(refs)
		var bench := MUI.dim("", 9)
		zone.add_child(bench)
		st = {"names": names, "cards": cards, "bench": bench}
		_zone_state[side] = st
	else:
		var cards2: Array = st["cards"]
		for i in cards2.size():
			var idx2 := int(actives[i]) if i < actives.size() else -1
			if idx2 >= 0 and idx2 < team.size():
				_update_card(cards2[i], team[idx2])
	if team.is_empty():
		(st["bench"] as Label).text = ""
		return
	var alive := 0
	for b in team:
		if not b.get("fainted", false):
			alive += 1
	(st["bench"] as Label).text = tr("%d of %d standing") % [alive, team.size()]


func _process(delta: float) -> void:
	if runner == null or runner.phase != runner.Phase.LIVE or not is_inside_tree():
		return
	if _live_battle_built != int(runner.battle_no):
		refresh()
		return
	if runner.awaiting_input():
		_refresh_actions()
		return
	_clock -= delta * _speed
	while _clock <= 0.0:
		var e: Dictionary = runner.consume_next()
		if e.is_empty():
			_on_stalled()
			return
		AudioManager.on_battle_event(e)
		_sync()
		_clock += maxf(0.8 if Commentary.is_key_event(e) else 0.28, 0.001)


func _on_stalled() -> void:
	if runner.live_state == runner.LiveState.BATTLE_OVER and runner.buffered() == 0:
		_show_interlude()
	elif runner.awaiting_input():
		_refresh_actions()


func _show_interlude() -> void:
	if _actions_built:
		return
	_actions_built = true
	_clear_actions()
	if runner.series_decided():
		var fin := MUI.button(tr("Full time — see the report"),
			Color(ThemeBuilder.COL_GOOD, 0.22), ThemeBuilder.COL_GOOD)
		fin.pressed.connect(func():
			runner.to_post()
			refresh())
		_action_area.add_child(fin)
	else:
		var nxt := MUI.button(tr("Next game"))
		nxt.pressed.connect(func():
			runner.next_battle()
			refresh())
		_action_area.add_child(nxt)


func _clear_actions() -> void:
	for c in _action_area.get_children():
		_action_area.remove_child(c)
		c.free()


# ------------------------------------------------------------- action input

func _refresh_actions() -> void:
	if runner.live_state == runner.LiveState.BATTLE_OVER:
		_show_interlude()
		return
	if not bool(runner.policy["full_control"]):
		return   # the coach plays on; stream continues by itself
	if _actions_built:
		return
	_actions_built = true
	_clear_actions()
	_sync()
	if runner.doubles_now():
		var waiting: Array = runner.slots_awaiting()
		if waiting.is_empty():
			_actions_built = false
			return
		_order_slot = int(waiting[0])
		var me: Dictionary = runner.engine.slot_battler(runner.player_side, _order_slot)
		_action_area.add_child(MUI.dim(tr("Orders for %s") % str(me.get("name", "?")), 10))
		_build_action_buttons(runner.available_actions_slot(_order_slot))
	else:
		_build_action_buttons(runner.available_actions())


func _build_action_buttons(actions: Array) -> void:
	match _picking:
		"switch":
			_build_pick_list(actions, "switch")
			return
		"item":
			_build_pick_list(actions, "use_item")
			return
		"target":
			_build_target_list()
			return
	var moves: Array = actions.filter(func(a): return str(a["type"]) == "move")
	var switches: Array = actions.filter(func(a): return str(a["type"]) == "switch")
	var items: Array = actions.filter(func(a): return str(a["type"]) == "use_item")
	if moves.is_empty() and not switches.is_empty():
		# forced switch (faint): straight to the bench list
		_action_area.add_child(MUI.dim(tr("Choose the next battler"), 10))
		_build_pick_list(actions, "switch")
		return
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	_action_area.add_child(grid)
	for a in moves:
		grid.add_child(_move_button(a))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_action_area.add_child(row)
	if not switches.is_empty():
		var sw := MUI.button(tr("Switch"), Color(ThemeBuilder.COL_PANEL_ALT, 1.0), ThemeBuilder.COL_BORDER)
		sw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sw.pressed.connect(func():
			_picking = "switch"
			_actions_built = false
			_refresh_actions())
		row.add_child(sw)
	if not items.is_empty():
		var it := MUI.button(tr("Item"), Color(ThemeBuilder.COL_PANEL_ALT, 1.0), ThemeBuilder.COL_BORDER)
		it.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		it.pressed.connect(func():
			_picking = "item"
			_actions_built = false
			_refresh_actions())
		row.add_child(it)


func _move_button(a: Dictionary) -> Button:
	var md: Dictionary = DataStore.move(str(a["move"]))
	var tcol: Color = DataStore.type_color(str(md.get("type", "normal")))
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 52)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", ThemeBuilder._flat(tcol.darkened(0.55), tcol, 6, 10, 5))
	b.add_theme_stylebox_override("hover", ThemeBuilder._flat(tcol.darkened(0.35), tcol, 6, 10, 5))
	b.add_theme_stylebox_override("pressed", ThemeBuilder._flat(tcol.darkened(0.2), tcol.lightened(0.2), 6, 10, 5))
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var nm := MUI.label(I18n.move_name(str(a["move"])), 13, Color.WHITE)
	nm.add_theme_font_override("font", MUI.bold())
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(nm)
	var pv: Dictionary = a.get("preview", {})
	var sub := tr("PP %d") % int(a.get("pp", 0))
	if not pv.is_empty():
		var eff := float(pv.get("eff", 1.0))
		if float(pv.get("est_frac", 0.0)) > 0.0:
			sub += " · ~%d%%" % int(round(float(pv["est_frac"]) * 100.0))
		if eff > 1.5:
			sub += " · " + tr("super")
		elif eff == 0.0:
			sub += " · " + tr("no effect")
		elif eff < 0.9:
			sub += " · " + tr("weak")
	v.add_child(MUI.dim(sub, 9))
	b.pressed.connect(func(): _choose_move(a))
	return b


func _choose_move(a: Dictionary) -> void:
	if runner.doubles_now() and str(a.get("targeting", "")) == "single" \
			and (a.get("targets", []) as Array).size() > 1:
		_pending_move = a
		_picking = "target"
		_actions_built = false
		_refresh_actions()
		return
	var action := {"type": "move", "index": int(a["index"])}
	if runner.doubles_now() and (a.get("targets", []) as Array).size() == 1:
		var t: Dictionary = a["targets"][0]
		action["target"] = {"side": int(t["side"]), "slot": int(t["slot"])}
	_submit(action)


func _build_target_list() -> void:
	_action_area.add_child(MUI.dim(tr("Target for %s") % I18n.move_name(str(_pending_move["move"])), 10))
	for t in _pending_move.get("targets", []):
		var pv: Dictionary = t.get("preview", {})
		var label := str(t.get("name", "?"))
		if not pv.is_empty() and float(pv.get("est_frac", 0.0)) > 0.0:
			label += "   ~%d%%" % int(round(float(pv["est_frac"]) * 100.0))
		var b := MUI.button(label)
		b.pressed.connect(func():
			_submit({"type": "move", "index": int(_pending_move["index"]),
				"target": {"side": int(t["side"]), "slot": int(t["slot"])}}))
		_action_area.add_child(b)
	_action_area.add_child(_back_button())


func _build_pick_list(actions: Array, kind: String) -> void:
	for a in actions:
		if str(a["type"]) != kind:
			continue
		var b: Button
		if kind == "switch":
			b = MUI.button("%s   %d/%d" % [str(a.get("pokemon", "?")),
				int(a.get("hp", 0)), int(a.get("max_hp", 1))])
			b.pressed.connect(func(): _submit({"type": "switch", "index": int(a["index"])}))
		else:
			b = MUI.button("%s → %s (%d/%d)" % [I18n.item_name(str(a["item"])),
				str(a.get("target_name", "?")), int(a.get("target_hp", 0)), int(a.get("target_max", 1))])
			b.pressed.connect(func(): _submit({"type": "use_item", "item": str(a["item"]),
				"target": int(a["target"])}))
		_action_area.add_child(b)
	_action_area.add_child(_back_button())


func _back_button() -> Button:
	var b := MUI.button("‹ " + tr("Back"), Color(ThemeBuilder.COL_PANEL_ALT, 1.0), ThemeBuilder.COL_BORDER)
	b.custom_minimum_size.y = 38
	b.pressed.connect(func():
		_picking = ""
		_pending_move = {}
		_actions_built = false
		_refresh_actions())
	return b


func _submit(action: Dictionary) -> void:
	_picking = ""
	_pending_move = {}
	_actions_built = false
	_clear_actions()
	if runner.doubles_now():
		runner.submit_slot_action(_order_slot, action)
		_order_slot = -1
		if runner.awaiting_input() and not runner.slots_awaiting().is_empty():
			_refresh_actions()   # second slot's orders
	else:
		runner.submit_action(action)


# ================================================================== POST

func _build_post() -> void:
	var pg := MUI.page()
	pg[0].size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(pg[0])
	var v: VBoxContainer = pg[1]

	var won: bool = runner.player_won()
	var rc := MUI.card()
	v.add_child(rc[0])
	var rv: VBoxContainer = rc[1]
	rv.add_child(MUI.dim(tr("FULL TIME").to_upper(), 10))
	var res := MUI.title("%s  %d – %d" % [tr("Victory!") if won else tr("Defeat"),
		int(runner.wins[runner.player_side]), int(runner.wins[1 - runner.player_side])], 20)
	res.add_theme_color_override("font_color", ThemeBuilder.COL_GOOD if won else ThemeBuilder.COL_BAD)
	rv.add_child(res)
	rv.add_child(MUI.dim("%s %s" % [tr("vs") if runner.player_side == 0 else tr("at"),
		str(runner.opponent_club().get("name", "?"))], 11))

	var motm: Dictionary = runner.man_of_the_match()
	if not motm.is_empty():
		var mc := MUI.card()
		v.add_child(mc[0])
		var mv: VBoxContainer = mc[1]
		mv.add_child(MUI.dim(tr("STAR OF THE MATCH").to_upper(), 10))
		mv.add_child(MUI.title(str(motm.get("name", "?")), 15))
		mv.add_child(MUI.dim(tr("Rating %s") % I18n.decimal(float(motm.get("rating", 6.0)), 1), 11))

	var ups: Array = runner.fixture.get("level_ups", [])
	if not ups.is_empty():
		var uc := MUI.card()
		v.add_child(uc[0])
		var uv: VBoxContainer = uc[1]
		uv.add_child(MUI.dim(tr("LEVEL UPS").to_upper(), 10))
		for u in ups:
			uv.add_child(MUI.label("▲ " + tr("%s climbs to Lv %d") % [str(u.get("name", "?")),
				int(u.get("to", 0))], 13, ThemeBuilder.COL_GOOD))

	var rows: Array = runner.rating_rows(runner.player_side)
	if not rows.is_empty():
		var tc := MUI.card()
		v.add_child(tc[0])
		var tv: VBoxContainer = tc[1]
		tv.add_child(MUI.dim(tr("YOUR RATINGS").to_upper(), 10))
		for r in rows:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			tv.add_child(row)
			var nm := MUI.label(str(r.get("name", "?")), 12)
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(nm)
			row.add_child(MUI.dim(tr("%d KOs") % int(r.get("kos", 0)), 11))
			var rt := MUI.label(I18n.decimal(float(r.get("rating", 6.0)), 1), 12,
				ThemeBuilder.COL_GOOD if float(r.get("rating", 6.0)) >= 7.0 else ThemeBuilder.COL_TEXT)
			rt.add_theme_font_override("font", MUI.bold())
			row.add_child(rt)

	var done := MUI.button(tr("Back to the club"), Color(ThemeBuilder.COL_GOOD, 0.22), ThemeBuilder.COL_GOOD)
	done.pressed.connect(_leave)
	v.add_child(done)


func _build_empty() -> void:
	add_child(MUI.title(tr("No match in progress."), 14))
	var back := MUI.button(tr("Back to the club"))
	back.pressed.connect(_leave)
	add_child(back)


func _inst_name(inst: Dictionary) -> String:
	var nick_v: Variant = inst.get("nickname")
	var nick := str(nick_v) if nick_v != null else ""
	return nick if nick != "" else str(inst.get("species", "?"))
