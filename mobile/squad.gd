extends VBoxContainer
## Mobile Squad (mobile piece): touch list of the squad -> profile-lite with
## the battle-real numbers, moves, contract and the global Pokémon action
## menu (MonActions) — deep management stays in landscape.

const SquadUI := preload("res://screens/squad/ui_helpers.gd")
const TrainingSvc := preload("res://screens/training/training_service.gd")

var _selected: Dictionary = {}
var _learn_mode := ""            # "" | "pick" (choose new move) | "slot" (choose forgotten)
var _learn_move := ""            # the chosen move while picking a slot


func _init() -> void:
	add_theme_constant_override("separation", 6)


func go_root() -> void:
	_selected = {}
	_learn_mode = ""
	_learn_move = ""
	refresh()


func refresh() -> void:
	for c in get_children():
		c.queue_free()
	if _selected.is_empty() or GameState.squad_member(str(_selected.get("uid", ""))).is_empty():
		_selected = {}
		_build_list()
	else:
		_build_detail()


# ---------------------------------------------------------------- list

func _build_list() -> void:
	var pc: Dictionary = GameState.player_club()
	var head := HBoxContainer.new()
	add_child(head)
	head.add_child(MUI.title(tr("Squad"), 17))
	head.add_child(MUI.hspacer())
	var n := MUI.dim(I18n.np(pc["squad"].size(), "%d battler", "%d battlers"), 11)
	n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(n)

	var pg := MUI.page()
	pg[0].size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(pg[0])
	var v: VBoxContainer = pg[1]
	v.add_theme_constant_override("separation", 4)
	var squad: Array = pc["squad"].duplicate()
	squad.sort_custom(func(a, b): return int(a["level"]) > int(b["level"]))
	for inst in squad:
		v.add_child(_row(inst))


func _row(inst: Dictionary) -> Control:
	var sp: Dictionary = DataStore.species(int(inst.get("species_id", 0)))
	var types: Array = sp.get("types", [])
	var r := MUI.row(func():
		_selected = inst
		refresh())
	var h: HBoxContainer = r[1]
	h.add_child(PokeArt.icon(int(inst.get("species_id", 0)), 38))
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 1)
	var nm := MUI.label(_name(inst), 13, Color.WHITE)
	nm.add_theme_font_override("font", MUI.bold())
	mid.add_child(nm)
	var sub := HBoxContainer.new()
	sub.add_theme_constant_override("separation", 4)
	sub.add_child(MUI.dim(tr("Lv%d") % int(inst["level"]), 10))
	for t in types:
		sub.add_child(MUI.type_chip(str(t)))
	mid.add_child(sub)
	h.add_child(mid)
	var side := VBoxContainer.new()
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.add_theme_constant_override("separation", 1)
	var mor := int(inst.get("morale", 70))
	var cond := int(inst.get("condition", 100))
	var ml := MUI.label(tr("Morale %d") % mor, 10, SquadUI.pct_color(mor))
	ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	side.add_child(ml)
	var cl := MUI.label(tr("Cond %d") % cond, 10, SquadUI.pct_color(cond))
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	side.add_child(cl)
	h.add_child(side)
	return r[0]


# ---------------------------------------------------------------- detail

func _build_detail() -> void:
	var inst := _selected
	var sp: Dictionary = DataStore.species(int(inst.get("species_id", 0)))
	var types: Array = sp.get("types", [])

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	add_child(head)
	var back := MUI.button("‹ " + tr("Squad"), Color(ThemeBuilder.COL_PANEL_ALT, 1.0), ThemeBuilder.COL_BORDER)
	back.custom_minimum_size = Vector2(0, 38)
	back.pressed.connect(go_root)
	head.add_child(back)
	head.add_child(MUI.hspacer())
	if MonActions.can_act(str(inst.get("uid", ""))):
		head.add_child(MonActions.action_pill(str(inst["uid"]), tr("Actions")))

	var pg := MUI.page()
	pg[0].size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(pg[0])
	var v: VBoxContainer = pg[1]

	# identity card
	var idc := MUI.card()
	v.add_child(idc[0])
	var iv: VBoxContainer = idc[1]
	var irow := HBoxContainer.new()
	irow.add_theme_constant_override("separation", 10)
	iv.add_child(irow)
	irow.add_child(PokeArt.icon(int(inst.get("species_id", 0)), 64))
	var icol := VBoxContainer.new()
	icol.alignment = BoxContainer.ALIGNMENT_CENTER
	icol.add_theme_constant_override("separation", 2)
	icol.add_child(MUI.title(_name(inst), 17))
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 4)
	trow.add_child(MUI.dim("%s · %s · %s" % [str(inst.get("species", "?")),
		tr("Lv%d") % int(inst["level"]), SquadUI.age_str(int(inst.get("age_months", 24)))], 11))
	icol.add_child(trow)
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 4)
	for t in types:
		chips.add_child(MUI.type_chip(str(t)))
	chips.add_child(MonRoles.chip(int(inst.get("species_id", 0))))
	icol.add_child(chips)
	irow.add_child(icol)

	# state card
	var stc := MUI.card()
	v.add_child(stc[0])
	var sv: VBoxContainer = stc[1]
	sv.add_child(MUI.dim(tr("STATE").to_upper(), 10))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 2)
	sv.add_child(grid)
	for pair in [[tr("Morale"), int(inst.get("morale", 70))],
			[tr("Condition"), int(inst.get("condition", 100))],
			[tr("Fitness"), int(inst.get("fitness", 100))],
			[tr("XP"), "%d/%d" % [int(inst.get("xp", 0)), GameState.xp_needed(int(inst["level"]))]]]:
		var cellv := VBoxContainer.new()
		cellv.add_theme_constant_override("separation", 0)
		cellv.add_child(MUI.dim(str(pair[0]), 10))
		var val_col: Color = SquadUI.pct_color(int(pair[1])) if pair[1] is int else ThemeBuilder.COL_TEXT
		cellv.add_child(MUI.label(str(pair[1]), 15, val_col))
		grid.add_child(cellv)

	# base stats card
	var base: Dictionary = sp.get("base", {})
	if not base.is_empty():
		var bc := MUI.card()
		v.add_child(bc[0])
		var bv: VBoxContainer = bc[1]
		bv.add_child(MUI.dim(tr("BASE STATS").to_upper(), 10))
		var bgrid := GridContainer.new()
		bgrid.columns = 6
		bgrid.add_theme_constant_override("h_separation", 12)
		bv.add_child(bgrid)
		for key in ["hp", "atk", "def", "spa", "spd", "spe"]:
			var cell := VBoxContainer.new()
			cell.add_theme_constant_override("separation", 0)
			cell.add_child(MUI.dim(key.to_upper(), 9))
			var val := int(base.get(key, 0))
			cell.add_child(MUI.label(str(val), 13, SquadUI.attr_color(SquadUI.base_to_20(val))))
			bgrid.add_child(cell)

	# moves card (+ the training ground's move-learning pipeline, mobile UI)
	var tsvc: Node = TrainingSvc.ensure()
	var lstate: Variant = tsvc.mon_state(str(inst["uid"])).get("move")
	var mc := MUI.card()
	v.add_child(mc[0])
	var mv: VBoxContainer = mc[1]
	mv.add_child(MUI.dim(tr("MOVES").to_upper(), 10))
	var known: Array = inst.get("moves", [])
	for mi in known.size():
		var mvname := str(known[mi])
		var md: Dictionary = DataStore.moves.get(mvname, {})
		var mrow := HBoxContainer.new()
		mrow.add_theme_constant_override("separation", 8)
		mv.add_child(mrow)
		if _learn_mode == "slot":
			var forget := MUI.button(tr("Forget"), Color(ThemeBuilder.COL_WARN, 0.2), ThemeBuilder.COL_WARN)
			forget.custom_minimum_size = Vector2(0, 32)
			forget.add_theme_font_size_override("font_size", 10)
			var slot_i := mi
			forget.pressed.connect(func():
				tsvc.start_move_learning(str(inst["uid"]), _learn_move, slot_i)
				_learn_mode = ""
				_learn_move = ""
				refresh())
			mrow.add_child(forget)
		mrow.add_child(MUI.label(I18n.move_name(mvname), 13, Color.WHITE))
		mrow.add_child(MUI.hspacer())
		if not md.is_empty():
			mrow.add_child(MUI.type_chip(str(md.get("type", "normal"))))
			var pw := int(md.get("power", 0))
			mrow.add_child(MUI.dim(tr("PWR %d") % pw if pw > 0 else tr("Status"), 11))
	if lstate != null and _learn_mode == "":
		var lrow := HBoxContainer.new()
		lrow.add_theme_constant_override("separation", 8)
		mv.add_child(lrow)
		var ld: Dictionary = lstate
		var pl := MUI.label(tr("Learning %s — %d%%") % [I18n.move_name(str(ld.get("name", "?"))),
			int(ld.get("progress", 0.0))], 12, ThemeBuilder.COL_ACCENT.lightened(0.25))
		pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		lrow.add_child(pl)
		var cancel := MUI.button(tr("Cancel"), Color(ThemeBuilder.COL_PANEL_ALT, 1.0), ThemeBuilder.COL_BORDER)
		cancel.custom_minimum_size = Vector2(0, 32)
		cancel.add_theme_font_size_override("font_size", 10)
		cancel.pressed.connect(func():
			tsvc.cancel_move_learning(str(inst["uid"]))
			refresh())
		lrow.add_child(cancel)
	elif _learn_mode == "pick":
		mv.add_child(MUI.dim(tr("Pick the move to drill (Move Practice sessions speed it up):"), 10))
		var sp2: Dictionary = DataStore.species(int(inst.get("species_id", 0)))
		for cand_v in sp2.get("learnset", []):
			var cand := str(cand_v)
			if known.has(cand):
				continue
			var cd: Dictionary = DataStore.moves.get(cand, {})
			var crow := HBoxContainer.new()
			crow.add_theme_constant_override("separation", 8)
			mv.add_child(crow)
			var pick := MUI.button(I18n.move_name(cand))
			pick.custom_minimum_size = Vector2(0, 36)
			pick.add_theme_font_size_override("font_size", 12)
			pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			pick.pressed.connect(func():
				if known.size() >= 4:
					_learn_move = cand
					_learn_mode = "slot"
				else:
					tsvc.start_move_learning(str(inst["uid"]), cand, 0)
					_learn_mode = ""
				refresh())
			crow.add_child(pick)
			if not cd.is_empty():
				crow.add_child(MUI.type_chip(str(cd.get("type", "normal"))))
				var cpw := int(cd.get("power", 0))
				crow.add_child(MUI.dim(tr("PWR %d") % cpw if cpw > 0 else tr("Status"), 11))
		var back2 := MUI.button("‹ " + tr("Back"), Color(ThemeBuilder.COL_PANEL_ALT, 1.0), ThemeBuilder.COL_BORDER)
		back2.custom_minimum_size = Vector2(0, 34)
		back2.pressed.connect(func():
			_learn_mode = ""
			refresh())
		mv.add_child(back2)
	elif _learn_mode == "slot":
		mv.add_child(MUI.dim(tr("Four moves known — tap Forget on the one to replace with %s.") % I18n.move_name(_learn_move), 10))
	else:
		var learn := MUI.button(tr("Teach a move…"), Color(ThemeBuilder.COL_PANEL_ALT, 1.0), ThemeBuilder.COL_BORDER)
		learn.custom_minimum_size = Vector2(0, 36)
		learn.add_theme_font_size_override("font_size", 12)
		learn.pressed.connect(func():
			_learn_mode = "pick"
			refresh())
		mv.add_child(learn)

	# contract + item card
	var cc := MUI.card()
	v.add_child(cc[0])
	var cv: VBoxContainer = cc[1]
	cv.add_child(MUI.dim(tr("CONTRACT & ITEM").to_upper(), 10))
	var contract: Dictionary = inst.get("contract", {})
	cv.add_child(MUI.label(tr("Salary %s / mo · until %s") % [
		SquadUI.money(int(contract.get("salary", 0))),
		I18n.pretty_date(str(contract.get("expiry", "?")))], 12))
	var held := str(inst.get("held_item", "") if inst.get("held_item") != null else "")
	cv.add_child(MUI.label(tr("Held item: %s") % (I18n.item_name(held) if held != "" else tr("none")), 12))

	var note := MUI.dim(tr("Full profile, training and contracts: rotate to landscape."), 11)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)


func _name(inst: Dictionary) -> String:
	var nick_v: Variant = inst.get("nickname")   # JSON saves store null, not ""
	var nick := str(nick_v) if nick_v != null else ""
	return nick if nick != "" else str(inst.get("species", "?"))
