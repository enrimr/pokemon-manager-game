extends VBoxContainer
## Mobile Tactics-lite (mobile piece): the battle plan, phone-shaped. Switch
## presets, reorder the starting six (same ▲ pattern as the prematch screen),
## swap bench battlers in, and set the team instructions — all writing the
## SAME world.meta.tactics_state the desktop Tactics screen owns, published
## to the engine through its own Logic.save_state. Deep work (role guide,
## coverage analysis, preset authoring) stays in landscape.

const Logic := preload("res://screens/tactics/tactics_logic.gd")

var _swap_uid := ""      # bench battler waiting for a starting slot to take


func _init() -> void:
	add_theme_constant_override("separation", 6)


func go_root() -> void:
	_swap_uid = ""
	refresh()


func _state() -> Dictionary:
	return Logic.load_state()


func _preset(state: Dictionary) -> Dictionary:
	return Logic.active_preset(state)


func _inst(uid: String) -> Dictionary:
	for m in GameState.player_club().get("squad", []):
		if str(m.get("uid", "")) == uid:
			return m
	return {}


func refresh() -> void:
	for c in get_children():
		c.queue_free()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	add_child(head)
	var back := MUI.button("‹ " + tr("More"), Color(ThemeBuilder.COL_PANEL_ALT, 1.0), ThemeBuilder.COL_BORDER)
	back.custom_minimum_size = Vector2(0, 38)
	back.pressed.connect(func():
		if _swap_uid != "":
			_swap_uid = ""
			refresh()
		else:
			_shell().call("open_tab", "more"))
	head.add_child(back)
	head.add_child(MUI.hspacer())

	var state := _state()
	var p := _preset(state)
	var pg := MUI.page()
	pg[0].size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(pg[0])
	var v: VBoxContainer = pg[1]

	# ---- plans (presets)
	var plc := MUI.card()
	v.add_child(plc[0])
	var pv: VBoxContainer = plc[1]
	pv.add_child(MUI.dim(tr("BATTLE PLAN").to_upper(), 10))
	var prow := HFlowContainer.new()
	prow.add_theme_constant_override("h_separation", 6)
	prow.add_theme_constant_override("v_separation", 6)
	pv.add_child(prow)
	for pr in state["presets"]:
		var pname := str(pr["name"])
		var active := pname == str(state["active"])
		var b := MUI.button(tr(pname),
			ThemeBuilder.COL_ACCENT_DIM if active else Color(ThemeBuilder.COL_PANEL_ALT, 1.0),
			ThemeBuilder.COL_ACCENT if active else ThemeBuilder.COL_BORDER)
		b.custom_minimum_size = Vector2(0, 36)
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(func():
			state["active"] = pname
			Logic.save_state(state)
			_shell().call("toast", tr("%s is now the active plan.") % tr(pname))
			refresh())
		prow.add_child(b)

	# ---- starting six (lead first); in swap mode, tap a slot to fill it
	var sc := MUI.card()
	v.add_child(sc[0])
	var sv: VBoxContainer = sc[1]
	sv.add_child(MUI.dim((tr("TAP THE SLOT FOR %s") % _inst(_swap_uid).get("species", "?")
		if _swap_uid != "" else tr("STARTING SIX — lead first")).to_upper(), 10))
	var lineup: Array = p["lineup"]
	for i in mini(6, lineup.size()):
		var uid := str(lineup[i])
		var inst := _inst(uid)
		if inst.is_empty():
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		sv.add_child(row)
		if _swap_uid != "":
			var slot_btn := MUI.button("%d  %s · %s" % [i + 1, str(inst.get("species", "?")),
				tr("Lv%d") % int(inst["level"])],
				Color(ThemeBuilder.COL_GOOD, 0.16), ThemeBuilder.COL_GOOD)
			slot_btn.custom_minimum_size = Vector2(0, 40)
			slot_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var slot_i := i
			slot_btn.pressed.connect(func(): _do_swap(state, p, slot_i))
			row.add_child(slot_btn)
			continue
		row.add_child(MUI.dim(str(i + 1), 11))
		row.add_child(PokeArt.icon(int(inst.get("species_id", 0)), 30))
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", 0)
		col.add_child(MUI.label("%s · %s" % [str(inst.get("species", "?")),
			tr("Lv%d") % int(inst["level"])], 13, Color.WHITE if i == 0 else ThemeBuilder.COL_TEXT))
		col.add_child(MUI.dim(I18n.t(str(p["roles"].get(uid, ""))), 9))
		row.add_child(col)
		if i > 0:
			var up := Button.new()
			up.text = "▲"
			up.custom_minimum_size = Vector2(40, 34)
			up.focus_mode = Control.FOCUS_NONE
			var idx := i
			up.pressed.connect(func():
				var tmp = lineup[idx - 1]
				lineup[idx - 1] = lineup[idx]
				lineup[idx] = tmp
				Logic.save_state(state)
				refresh())
			row.add_child(up)

	# ---- bench: tap to bring a battler into the six
	var bench: Array = p.get("bench", [])
	if not bench.is_empty() and _swap_uid == "":
		var bc := MUI.card()
		v.add_child(bc[0])
		var bv: VBoxContainer = bc[1]
		bv.add_child(MUI.dim(tr("BENCH — tap to bring into the six").to_upper(), 10))
		for j in bench.size():
			var buid := str(bench[j])
			var binst := _inst(buid)
			if binst.is_empty():
				continue
			var brow := MUI.row(func():
				_swap_uid = buid
				refresh())
			var h: HBoxContainer = brow[1]
			h.add_child(PokeArt.icon(int(binst.get("species_id", 0)), 28))
			var bl := MUI.label("%s · %s" % [str(binst.get("species", "?")),
				tr("Lv%d") % int(binst["level"])], 12, ThemeBuilder.COL_TEXT)
			bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(bl)
			var rl := MUI.dim(I18n.t(str(p["roles"].get(buid, ""))), 9)
			rl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(rl)
			bv.add_child(brow[0])

	if _swap_uid != "":
		return   # swap mode: instructions hidden until the slot is chosen

	# ---- team instructions (the engine reads these every AI turn)
	var ic := MUI.card()
	v.add_child(ic[0])
	var iv: VBoxContainer = ic[1]
	iv.add_child(MUI.dim(tr("TEAM INSTRUCTIONS").to_upper(), 10))
	var instr: Dictionary = p["instructions"]

	iv.add_child(MUI.dim(tr("Aggression"), 10))
	iv.add_child(_cycle_row(Logic.AGGRESSION_LABELS, int(instr.get("aggression", 2)), func(val):
		instr["aggression"] = val
		Logic.save_state(state)
		refresh()))
	iv.add_child(MUI.dim(tr("Retreat below HP"), 10))
	iv.add_child(_choice_row([["15%", 15], ["25%", 25], ["40%", 40]],
		func(val): return int(val) == int(instr.get("switch_threshold", 25)),
		func(val):
			instr["switch_threshold"] = int(val)
			Logic.save_state(state)
			refresh()))
	iv.add_child(MUI.dim(tr("Status moves"), 10))
	iv.add_child(_choice_row([[tr("Low"), 0], [tr("Balanced"), 1], [tr("High"), 2]],
		func(val): return int(val) == int(instr.get("status_priority", 1)),
		func(val):
			instr["status_priority"] = int(val)
			Logic.save_state(state)
			refresh()))
	for tog in [["protect_lead", tr("Protect the Lead from bad matchups")],
			["preserve_last", tr("Never sacrifice the last battler")],
			["revenge_switch", tr("Revenge-switch after a faint")]]:
		var key := str(tog[0])
		var cb := CheckButton.new()
		cb.text = str(tog[1])
		cb.button_pressed = bool(instr.get(key, false))
		cb.add_theme_font_size_override("font_size", 12)
		cb.toggled.connect(func(on: bool):
			instr[key] = on
			Logic.save_state(state))
		iv.add_child(cb)
	v.add_child(MUI.dim(tr("Role guide, coverage analysis and preset authoring live in landscape."), 10))


func _do_swap(state: Dictionary, p: Dictionary, slot_i: int) -> void:
	var lineup: Array = p["lineup"]
	var bench: Array = p["bench"]
	var bench_i := bench.find(_swap_uid)
	if bench_i >= 0:
		bench[bench_i] = lineup[slot_i]   # the displaced starter takes the bench spot
		lineup[slot_i] = _swap_uid
		Logic.save_state(state)
		_shell().call("toast", tr("%s starts — slot %d.") % [
			str(_inst(str(lineup[slot_i])).get("species", "?")), slot_i + 1])
	_swap_uid = ""
	refresh()


## "‹ Label ›" cycler for ordered labels (aggression).
func _cycle_row(labels: Array, cur: int, on_set: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var prev := MUI.button("‹", Color(ThemeBuilder.COL_PANEL_ALT, 1.0), ThemeBuilder.COL_BORDER)
	prev.custom_minimum_size = Vector2(44, 36)
	prev.pressed.connect(func(): on_set.call(maxi(0, cur - 1)))
	row.add_child(prev)
	var val := MUI.label(tr(str(labels[clampi(cur, 0, labels.size() - 1)])), 12,
		ThemeBuilder.COL_ACCENT.lightened(0.2))
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(val)
	var next := MUI.button("›", Color(ThemeBuilder.COL_PANEL_ALT, 1.0), ThemeBuilder.COL_BORDER)
	next.custom_minimum_size = Vector2(44, 36)
	next.pressed.connect(func(): on_set.call(mini(labels.size() - 1, cur + 1)))
	row.add_child(next)
	return row


func _choice_row(options: Array, is_sel: Callable, on_pick: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for opt in options:
		var sel: bool = is_sel.call(opt[1])
		var b := MUI.button(str(opt[0]),
			ThemeBuilder.COL_ACCENT_DIM if sel else Color(ThemeBuilder.COL_PANEL_ALT, 1.0),
			ThemeBuilder.COL_ACCENT if sel else ThemeBuilder.COL_BORDER)
		b.custom_minimum_size = Vector2(0, 36)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 12)
		var val = opt[1]
		b.pressed.connect(func(): on_pick.call(val))
		row.add_child(b)
	return row


func _shell() -> Node:
	var n: Node = get_parent()
	while n != null and not n.has_method("open_tab"):
		n = n.get_parent()
	return n
