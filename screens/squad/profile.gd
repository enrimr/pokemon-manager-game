extends Control
const EvoSvc := preload("res://shared/sim/services/evolution.gd")
## Squad piece: full Pokémon profile (FM player-profile style).
## Overview tab: header (monogram, types, key facts), attribute panels with
## 1-20 colored bars and 30-day change indicators, known + learnable moves,
## season stats, condition, contract, development, teammate comparison.
## History tab: season-by-season career stats, transfer/contract event record,
## attribute progression with sparklines and a development log — all from the
## persistent SquadHistory model. All live GameState / DataStore data.

signal back_requested

const UI := preload("res://screens/squad/ui_helpers.gd")
const SeasonStats := preload("res://screens/squad/season_stats.gd")
const Actions := preload("res://screens/squad/actions_ui.gd")
const Service := preload("res://screens/squad/squad_service.gd")
const History := preload("res://screens/squad/career_history.gd")
const Ability := preload("res://screens/squad/ability.gd")
const Selection := preload("res://screens/squad/selection.gd")
const Personality := preload("res://screens/squad/personality.gd")

const STAT_KEYS := ["hp", "atk", "def", "spa", "spd", "spe"]
const STAT_NAMES := {"hp": "HP", "atk": "Attack", "def": "Defence",
	"spa": "Sp. Attack", "spd": "Sp. Defence", "spe": "Speed"}
const DEV_WINDOW_DAYS := 30

var _uid := ""
var _compare_uid := ""
var _tab := "overview"


func open(uid: String) -> void:
	if uid != _uid:
		_compare_uid = ""
		_tab = "overview"
	_uid = uid
	refresh()


func refresh() -> void:
	for c in get_children():
		c.queue_free()
	var squad: Array = GameState.player_club().get("squad", [])
	var idx := -1
	for i in squad.size():
		if squad[i]["uid"] == _uid:
			idx = i
			break
	if idx < 0:
		back_requested.emit()
		return
	_build(squad, idx)


# ------------------------------------------------------------------ build

func _build(squad: Array, idx: int) -> void:
	var inst: Dictionary = squad[idx]
	var sp: Dictionary = DataStore.species(int(inst["species_id"]))
	var stats := UI.effective_stats(inst)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	# --- nav bar
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 8)
	root.add_child(nav)
	var back := Button.new()
	back.text = tr("<  Squad")
	back.pressed.connect(func(): back_requested.emit())
	nav.add_child(back)
	var crumbs := Label.new()
	crumbs.text = tr("Squad  /  %s  /  Profile") % UI.display_name(inst)
	crumbs.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	crumbs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nav.add_child(crumbs)
	var nsp := Control.new()
	nsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(nsp)
	var pos_lbl := Label.new()
	pos_lbl.text = tr("%d of %d in squad") % [idx + 1, squad.size()]
	pos_lbl.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	pos_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nav.add_child(pos_lbl)
	var prev := Button.new()
	prev.text = tr("< Prev")
	prev.pressed.connect(func(): open(squad[(idx - 1 + squad.size()) % squad.size()]["uid"]))
	nav.add_child(prev)
	var next := Button.new()
	next.text = tr("Next >")
	next.pressed.connect(func(): open(squad[(idx + 1) % squad.size()]["uid"]))
	nav.add_child(next)

	root.add_child(_header(inst, sp))
	root.add_child(_action_bar(inst))
	root.add_child(_tab_bar(inst))

	if _tab == "history":
		_build_history_body(root, inst)
		return

	# --- overview body columns (scrolls if the panels outgrow the window)
	var body_scroll := ScrollContainer.new()
	body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(body_scroll)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_scroll.add_child(body)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.custom_minimum_size = Vector2(470, 0)
	body.add_child(left)
	var evo_panel := _evolution_panel(inst)
	var evo_pending: bool = EvoSvc.instance != null \
		and not EvoSvc.instance.pending_for(str(inst["uid"])).is_empty()
	if evo_panel != null and evo_pending:
		left.add_child(evo_panel)   # a decision is due — lead with it, FM-style
	left.add_child(_attributes_panel(inst, sp, stats, squad))
	left.add_child(_matchups_panel(inst, sp))
	left.add_child(_development_panel(inst, sp))
	if evo_panel != null and not evo_pending:
		left.add_child(evo_panel)

	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 8)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(mid)
	mid.add_child(_mind_panel(inst))
	mid.add_child(_moves_panel(inst, sp))
	mid.add_child(_form_panel(inst))

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.custom_minimum_size = Vector2(330, 0)
	body.add_child(right)
	right.add_child(_coach_report_panel(inst))
	right.add_child(_item_panel(inst))
	right.add_child(_season_panel(inst))
	right.add_child(_condition_panel(inst))
	right.add_child(_contract_panel(inst))


func _tab_bar(inst: Dictionary) -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	for pair in [["overview", "Overview"], ["history", "History"]]:
		var b := Button.new()
		b.text = pair[1]
		b.toggle_mode = true
		b.button_pressed = _tab == pair[0]
		var key: String = pair[0]
		b.pressed.connect(func() -> void:
			_tab = key
			refresh())
		bar.add_child(b)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(sp)
	var hist: Node = History.ensure()
	var joined: String = hist.joined_on(inst["uid"])
	var note := Label.new()
	note.text = ("Career records kept since %s" % I18n.pretty_date(joined)) if joined != "" \
		else tr("Career records begin today")
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(note)
	return bar


# ------------------------------------------------------------------ header

func _header(inst: Dictionary, sp: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 9)
	panel.add_child(hb)

	hb.add_child(UI.monogram(UI.display_name(inst), sp["types"], 72, 30, int(inst.get("species_id", 0))))

	var id_box := VBoxContainer.new()
	id_box.add_theme_constant_override("separation", 3)
	id_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(id_box)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	id_box.add_child(name_row)
	var nm := Label.new()
	nm.text = UI.display_name(inst)
	nm.add_theme_font_size_override("font_size", 26)
	nm.add_theme_color_override("font_color", Color.WHITE)
	name_row.add_child(nm)
	for t in sp["types"]:
		var b := UI.type_badge(t, 12)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_row.add_child(b)
	var ab_tag := Label.new()
	ab_tag.text = UI.ability_label(inst).to_upper()
	ab_tag.add_theme_font_size_override("font_size", 11)
	ab_tag.add_theme_color_override("font_color", UI.COL_ACCENT.lightened(0.3))
	ab_tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ab_tag.mouse_filter = Control.MOUSE_FILTER_STOP
	ab_tag.tooltip_text = tr("Battle ability (passive, always active in battle):\n%s") % UI.ability_tip(inst)
	name_row.add_child(ab_tag)
	var nat_tag := Label.new()
	nat_tag.text = UI.nature_text(inst).to_upper()
	nat_tag.add_theme_font_size_override("font_size", 11)
	nat_tag.add_theme_color_override("font_color",
		UI.COL_TEXT_DIM if UI.nature_text(inst).ends_with("(neutral)") else UI.COL_WARN.lightened(0.15))
	nat_tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nat_tag.mouse_filter = Control.MOUSE_FILTER_STOP
	nat_tag.tooltip_text = UI.nature_tip(inst)
	name_row.add_child(nat_tag)
	var svc: Node = Service.ensure()
	var happy: Dictionary = Personality.happiness(inst, svc, Personality.context(svc))
	var sel: Dictionary = Selection.selection()
	var pick: Dictionary = Selection.pick_info(str(inst["uid"]), sel)
	var pick_tag := Label.new()
	pick_tag.text = ("PICKED  %s" % pick["text"]) if pick["kind"] == "starter" \
		else tr("BENCH  %s") % pick["text"]
	pick_tag.add_theme_font_size_override("font_size", 11)
	pick_tag.add_theme_color_override("font_color",
		UI.COL_ACCENT.lightened(0.3) if pick["kind"] == "starter" else UI.COL_TEXT_DIM)
	pick_tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pick_tag.mouse_filter = Control.MOUSE_FILTER_STOP
	pick_tag.tooltip_text = str(pick["tip"])
	name_row.add_child(pick_tag)
	var flags: Array = Selection.flags(inst)
	if not flags.is_empty():
		var av_tag := Label.new()
		av_tag.text = Selection.flags_text(flags)
		av_tag.add_theme_font_size_override("font_size", 11)
		av_tag.add_theme_color_override("font_color", Selection.worst_color(flags))
		av_tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		av_tag.mouse_filter = Control.MOUSE_FILTER_STOP
		av_tag.tooltip_text = Selection.flags_tip(flags)
		name_row.add_child(av_tag)
	if Service.ensure().is_listed(inst):
		var tag := Label.new()
		tag.text = tr("TRANSFER LISTED · %s") % UI.money(int(inst.get("asking_price", 0)))
		tag.add_theme_font_size_override("font_size", 11)
		tag.add_theme_color_override("font_color", UI.COL_BAD)
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_row.add_child(tag)
	var sub_row := HBoxContainer.new()
	sub_row.add_theme_constant_override("separation", 0)
	id_box.add_child(sub_row)
	var arch_tag := Label.new()
	arch_tag.text = str((happy["arch"] as Dictionary)["name"])
	arch_tag.add_theme_color_override("font_color", UI.COL_ACCENT.lightened(0.3))
	arch_tag.mouse_filter = Control.MOUSE_FILTER_STOP
	arch_tag.tooltip_text = I18n.t("%s\nCoach's read: %s.") % [str((happy["arch"] as Dictionary)["desc"]),
		Personality.attrs_line(happy["attrs"])]
	sub_row.add_child(arch_tag)
	var sub := Label.new()
	var nick_note := ""
	if inst.get("nickname"):
		nick_note = "%s  ·  " % inst["species"]
	sub.text = tr("  ·  %sLevel %d  ·  Age %s  ·  %s  ·  #%03d") % [
		nick_note, int(inst["level"]), UI.age_str(int(inst["age_months"])),
		UI.age_stage(int(inst["age_months"])), int(sp["id"])]
	sub.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	sub_row.add_child(sub)
	var sub2 := Label.new()
	var club: Dictionary = GameState.player_club()
	sub2.text = tr("%s  ·  Contract to %s  ·  %s/wk") % [club["name"],
		I18n.pretty_date(inst["contract"]["expiry"]),
		UI.money(int(inst["contract"]["salary"]))]
	sub2.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	id_box.add_child(sub2)

	var hsp := Control.new()
	hsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(hsp)

	var rep: Dictionary = Ability.report(inst)
	var cur_stars := _big_stars("ABILITY", Ability.stars_icon(float(rep["now"]), -1.0, Ability.COL_STARS_NOW, 14),
		Ability.ability_word(float(rep["now"])))
	cur_stars.tooltip_text = tr("Coach report by %s (judging ability %d/20): top %d%% of the league's %d battlers.") % [
		rep["ja_name"], int(rep["ja"]),
		maxi(int(round((1.0 - float(rep["pct_now"])) * 100.0)), 1), int(rep["league_n"])]
	hb.add_child(cur_stars)
	var pot_stars := _big_stars("POTENTIAL",
		Ability.stars_icon(float(rep["pot_lo"]), float(rep["pot_hi"]), Ability.COL_STARS_POT, 14),
		tr("%s stars, %s conf.") % [Ability.stars_range_text(float(rep["pot_lo"]), float(rep["pot_hi"])), rep["confidence"]])
	pot_stars.tooltip_text = tr("Judged by %s (judging potential %d/20). Ceiling from trainable IVs and the full learnset — see the Coach Report panel.") % [
		rep["jp_name"], int(rep["jp"])]
	hb.add_child(pot_stars)
	var apps := SeasonStats.stat_of(inst["uid"], "battles")
	var rat := SeasonStats.avg_rating(inst["uid"])
	hb.add_child(_big_stat(tr("AV RATING"), I18n.decimal(rat, 2) if apps > 0 else "-",
		UI.rating_color(rat) if apps > 0 else UI.COL_TEXT_DIM))
	hb.add_child(_big_stat("BATTLES", str(apps), UI.COL_TEXT))
	var dev_gain: int = History.ensure().dev_gain(inst["uid"], inst, DEV_WINDOW_DAYS)
	var dev_stat := _big_stat(tr("DEV %dD") % DEV_WINDOW_DAYS,
		(tr("+%d IV") % dev_gain) if dev_gain > 0 else "=",
		UI.COL_GOOD if dev_gain > 0 else UI.COL_TEXT_DIM)
	dev_stat.tooltip_text = tr("IV points gained from training in the last %d days — see the History tab") % DEV_WINDOW_DAYS
	hb.add_child(dev_stat)
	hb.add_child(_big_stat("CONDITION", "%d%%" % int(inst["condition"]),
		UI.pct_color(int(inst["condition"]))))
	var morale_stat := _big_stat("MORALE", UI.morale_word(int(inst["morale"])),
		UI.pct_color(int(inst["morale"])))
	morale_stat.tooltip_text = _mood_ledger_tip(str(inst["uid"]), int(inst["morale"]), happy)
	hb.add_child(morale_stat)
	var happy_stat := _big_stat("HAPPINESS", str(happy["word"]), happy["color"])
	happy_stat.tooltip_text = Personality.factors_tip(happy)
	hb.add_child(happy_stat)
	return panel


func _mood_ledger_tip(uid: String, morale: int, happy: Dictionary) -> String:
	var lines: Array = [tr("Morale %s (%d) — day-to-day mood. Recent events:") % [UI.morale_word(morale), morale]]
	var log: Array = Service.ensure().mood_log(uid)
	if log.is_empty():
		lines.append(tr("  none recorded yet"))
	for e in log.slice(0, 7):
		lines.append("  %s  %+d  %s" % [I18n.pretty_date(str(e["d"])), int(e["delta"]), str(e["why"])])
	var gap: int = int(happy["score"]) - morale
	if absi(gap) > 6:
		lines.append(tr("Drifting %s toward underlying happiness (%s, %d/100).") %
			["up" if gap > 0 else "down", str(happy["word"]), int(happy["score"])])
	return "\n".join(PackedStringArray(lines))


## Dialog host: the squad screen root, so popups survive profile rebuilds.
func _host() -> Control:
	var p := get_parent()
	return p if p is Control else self


func _action_bar(inst: Dictionary) -> Control:
	var svc: Node = Service.ensure()
	var uid: String = inst["uid"]
	var panel := PanelContainer.new()
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	panel.add_child(hb)

	var lbl := Label.new()
	lbl.text = "MANAGE"
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", UI.COL_ACCENT.lightened(0.25))
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(lbl)

	var contract_b := Button.new()
	contract_b.text = tr("Offer New Contract")
	if svc.talks_locked(uid):
		contract_b.disabled = true
		contract_b.text = tr("Talks Off Until %s") % I18n.pretty_date(svc.talks_locked_until(uid))
	contract_b.pressed.connect(func() -> void: Actions.open_contract_dialog(_host(), uid))
	hb.add_child(contract_b)

	var listed: bool = svc.is_listed(inst)
	var list_b := Button.new()
	list_b.text = tr("Remove From Transfer List") if listed else tr("Add To Transfer List")
	list_b.pressed.connect(func() -> void:
		if svc.is_listed(svc.find_instance(uid)):
			var err: String = svc.unlist(uid)
			if err != "":
				Actions.notice(_host(), tr("Transfer list"), err)
		else:
			Actions.open_list_dialog(_host(), uid))
	hb.add_child(list_b)

	var bids: Array = svc.offers_for(uid)
	if not bids.is_empty():
		var bids_b := Button.new()
		bids_b.text = tr("Respond To %d Bid%s") % [bids.size(), "s" if bids.size() > 1 else ""]
		bids_b.add_theme_color_override("font_color", UI.COL_WARN)
		bids_b.pressed.connect(func() -> void: Actions.open_offers_dialog(_host(), uid))
		hb.add_child(bids_b)

	var can_chat: bool = svc.can_interact(uid)
	var praise_b := Button.new()
	praise_b.text = tr("Praise Form")
	praise_b.disabled = not can_chat
	praise_b.tooltip_text = tr("Morale boost if recent form deserves it — hollow praise backfires") \
		if can_chat else tr("Next chat available %s") % I18n.pretty_date(svc.interaction_available_on(uid))
	praise_b.pressed.connect(func() -> void: Actions.interact(_host(), uid, true))
	hb.add_child(praise_b)
	var disc_b := Button.new()
	disc_b.text = tr("Criticise Form")
	disc_b.disabled = not can_chat
	disc_b.tooltip_text = tr("A justified dressing-down keeps standards; an unfair one enrages") \
		if can_chat else tr("Next chat available %s") % I18n.pretty_date(svc.interaction_available_on(uid))
	disc_b.pressed.connect(func() -> void: Actions.interact(_host(), uid, false))
	hb.add_child(disc_b)

	var nick_b := Button.new()
	nick_b.text = "Rename"
	nick_b.pressed.connect(func() -> void: Actions.open_nickname_dialog(_host(), uid))
	hb.add_child(nick_b)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(spacer)

	var release_b := Button.new()
	release_b.text = tr("Terminate Contract")
	release_b.add_theme_color_override("font_color", UI.COL_BAD)
	release_b.tooltip_text = tr("Release into free agency, paying off half the remaining deal")
	release_b.pressed.connect(func() -> void: Actions.open_release_dialog(_host(), uid))
	hb.add_child(release_b)
	return panel


func _big_stat(label: String, value: String, col: Color) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.custom_minimum_size = Vector2(70, 0)
	var l1 := Label.new()
	l1.text = label
	l1.add_theme_font_size_override("font_size", 10)
	l1.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	l1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l1)
	var l2 := Label.new()
	l2.text = value
	l2.add_theme_font_size_override("font_size", 19)
	l2.add_theme_color_override("font_color", col)
	l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l2)
	return v


func _big_stars(label: String, tex: ImageTexture, sub: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.custom_minimum_size = Vector2(90, 0)
	var l1 := Label.new()
	l1.text = label
	l1.add_theme_font_size_override("font_size", 10)
	l1.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	l1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l1)
	var tr := TextureRect.new()
	tr.texture = tex
	tr.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	v.add_child(tr)
	var l2 := Label.new()
	l2.text = sub
	l2.add_theme_font_size_override("font_size", 10)
	l2.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l2)
	return v


# ------------------------------------------------------------------ panels

func _panel(title: String) -> Array:
	# returns [PanelContainer, VBoxContainer content]
	var p := PanelContainer.new()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	p.add_child(v)
	var t := Label.new()
	t.text = title.to_upper()
	t.add_theme_font_size_override("font_size", 11)
	t.add_theme_color_override("font_color", UI.COL_ACCENT.lightened(0.25))
	v.add_child(t)
	var sep := HSeparator.new()
	v.add_child(sep)
	return [p, v]


func _bar(ratio: float, col: Color, w: int = 110, h: int = 9) -> Control:
	var bg := PanelContainer.new()
	bg.custom_minimum_size = Vector2(w, h)
	bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb_bg := StyleBoxFlat.new()
	sb_bg.bg_color = Color("11141d")
	sb_bg.border_color = UI.COL_BORDER
	sb_bg.set_border_width_all(1)
	sb_bg.set_corner_radius_all(2)
	bg.add_theme_stylebox_override("panel", sb_bg)
	var fill := ColorRect.new()
	fill.color = col
	var rw := clampf(ratio, 0.0, 1.0) * (w - 2)
	fill.custom_minimum_size = Vector2(rw, h - 2)
	fill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	fill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bg.add_child(fill)
	return bg


func _attributes_panel(inst: Dictionary, sp: Dictionary, stats: Dictionary, squad: Array) -> Control:
	var pk := _panel("Attributes")
	var panel: PanelContainer = pk[0]
	var v: VBoxContainer = pk[1]

	var cmp_inst := {}
	var cmp_stats := {}
	for m in squad:
		if m["uid"] == _compare_uid:
			cmp_inst = m
			cmp_stats = UI.effective_stats(m)

	# column headers
	var head := GridContainer.new()
	head.columns = 6
	head.add_theme_constant_override("h_separation", 10)
	v.add_child(head)
	for h in ["", "BASE", "", tr("CURRENT (LV %d)") % int(inst["level"]), "IV", "SQUAD"]:
		var l := Label.new()
		l.text = h
		l.add_theme_font_size_override("font_size", 10)
		l.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
		head.add_child(l)

	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 7)
	v.add_child(grid)

	# squad maxima for bar scaling + ranks
	var squad_max := {}
	for k in STAT_KEYS:
		squad_max[k] = 1
	var all_stats: Array = []
	for m in squad:
		var s := UI.effective_stats(m)
		all_stats.append(s)
		for k in STAT_KEYS:
			squad_max[k] = maxi(squad_max[k], int(s[k]))

	var base: Dictionary = sp["base"]
	var ivs: Dictionary = inst.get("ivs", {})
	var dev: Dictionary = History.ensure().delta_since(inst["uid"], inst, DEV_WINDOW_DAYS)
	for k in STAT_KEYS:
		var name_l := Label.new()
		var ndir := UI.nature_dir(inst, k)
		name_l.text = STAT_NAMES[k] + ("  +" if ndir > 0 else ("  −" if ndir < 0 else ""))
		name_l.custom_minimum_size = Vector2(84, 0)
		if ndir != 0:
			name_l.add_theme_color_override("font_color", UI.COL_GOOD if ndir > 0 else UI.COL_WARN)
			name_l.mouse_filter = Control.MOUSE_FILTER_STOP
			name_l.tooltip_text = UI.nature_tip(inst)
		grid.add_child(name_l)

		var b20 := UI.base_to_20(int(base[k]))
		var b_num := Label.new()
		b_num.text = str(b20)
		b_num.custom_minimum_size = Vector2(24, 0)
		b_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		b_num.add_theme_color_override("font_color", UI.attr_color(b20))
		b_num.tooltip_text = tr("Species base %s: %d (scaled to 1-20)") % [STAT_NAMES[k], int(base[k])]
		grid.add_child(b_num)
		grid.add_child(_bar(b20 / 20.0, UI.attr_color(b20)))

		var cur := int(stats[k])
		var cur_row := HBoxContainer.new()
		cur_row.add_theme_constant_override("separation", 6)
		var c_num := Label.new()
		c_num.text = str(cur)
		c_num.custom_minimum_size = Vector2(34, 0)
		c_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		c_num.add_theme_color_override("font_color", Color.WHITE)
		cur_row.add_child(c_num)
		cur_row.add_child(_bar(float(cur) / float(squad_max[k]), UI.COL_ACCENT, 96))
		if not cmp_stats.is_empty():
			var d := cur - int(cmp_stats[k])
			var d_l := Label.new()
			d_l.text = "%+d" % d
			d_l.add_theme_font_size_override("font_size", 12)
			d_l.add_theme_color_override("font_color",
				UI.COL_GOOD if d > 0 else (UI.COL_BAD if d < 0 else UI.COL_TEXT_DIM))
			cur_row.add_child(d_l)
		grid.add_child(cur_row)

		var iv_l := Label.new()
		var iv_gain := 0
		if bool(dev.get("has", false)):
			iv_gain = int((dev["ivs"] as Dictionary).get(k, 0))
		iv_l.text = "%d/15" % int(ivs.get(k, 8)) + (("  +%d^" % iv_gain) if iv_gain > 0 else "")
		iv_l.add_theme_font_size_override("font_size", 12)
		iv_l.add_theme_color_override("font_color",
			UI.COL_GOOD if iv_gain > 0 else
			(Color("b9c96a") if int(ivs.get(k, 8)) >= 12 else UI.COL_TEXT_DIM))
		if iv_gain > 0:
			iv_l.tooltip_text = tr("%s IV up %d in the last %d days (training) — full record on the History tab") % \
				[STAT_NAMES[k], iv_gain, DEV_WINDOW_DAYS]
		grid.add_child(iv_l)

		var rank := 1
		for s in all_stats:
			if int(s[k]) > cur:
				rank += 1
		var rank_l := Label.new()
		rank_l.text = _ordinal(rank)
		rank_l.add_theme_font_size_override("font_size", 12)
		rank_l.add_theme_color_override("font_color",
			UI.COL_GOOD if rank <= 2 else UI.COL_TEXT_DIM)
		rank_l.tooltip_text = tr("Rank in squad for %s") % STAT_NAMES[k]
		grid.add_child(rank_l)

	# totals + compare picker
	var bst := 0
	for k in base:
		bst += int(base[k])
	var tot := 0
	for k in STAT_KEYS:
		tot += int(stats[k])
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	v.add_child(foot)
	var tot_l := Label.new()
	tot_l.text = tr("Base total %d  ·  Current total %d  ·  %s nature applied") % [bst, tot, UI.nature_name(inst)]
	tot_l.mouse_filter = Control.MOUSE_FILTER_STOP
	tot_l.tooltip_text = UI.nature_tip(inst) + "\nCURRENT figures are battle-real — identical to what the match engine uses."
	tot_l.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	tot_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(tot_l)
	var fsp := Control.new()
	fsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(fsp)
	var cmp := OptionButton.new()
	cmp.add_item(tr("Compare with..."), 0)
	var sel_idx := 0
	var oid := 1
	var uid_by_id := {}
	for m in squad:
		if m["uid"] == inst["uid"]:
			continue
		cmp.add_item(tr("%s (Lv %d)") % [UI.display_name(m), int(m["level"])], oid)
		uid_by_id[oid] = m["uid"]
		if m["uid"] == _compare_uid:
			sel_idx = cmp.item_count - 1
		oid += 1
	cmp.selected = sel_idx
	cmp.item_selected.connect(func(i: int) -> void:
		var id := cmp.get_item_id(i)
		_compare_uid = uid_by_id.get(id, "")
		refresh())
	foot.add_child(cmp)
	if not cmp_inst.is_empty():
		var note := Label.new()
		note.text = tr("vs %s") % UI.display_name(cmp_inst)
		note.add_theme_color_override("font_color", UI.COL_WARN)
		note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		foot.add_child(note)
	return panel


func _ordinal(n: int) -> String:
	return I18n.ordinal(n)


# ------------------------------------------------------------------ moves

func _moves_panel(inst: Dictionary, sp: Dictionary) -> Control:
	var pk := _panel("Moves")
	var panel: PanelContainer = pk[0]
	var v: VBoxContainer = pk[1]

	var known: Array = inst.get("moves", [])
	v.add_child(_moves_grid(known, false))

	var learnable: Array = []
	for m in sp.get("learnset", []):
		if not known.has(m):
			learnable.append(m)
	var sub := Label.new()
	sub.text = tr("LEARNABLE THROUGH TRAINING  (%d in learnset)") % learnable.size()
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	v.add_child(sub)
	v.add_child(HSeparator.new())
	if learnable.is_empty():
		var none := Label.new()
		none.text = tr("Full learnset already mastered.")
		none.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
		v.add_child(none)
	else:
		v.add_child(_moves_grid(learnable.slice(0, 8), true))
	return panel


func _moves_grid(move_names: Array, dim: bool) -> Control:
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 5)
	for h in ["MOVE", "TYPE", "CAT", "POW", "ACC", "PP", "EFFECT"]:
		var l := Label.new()
		l.text = h
		l.add_theme_font_size_override("font_size", 10)
		l.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
		if h in ["POW", "ACC", "PP"]:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(l)
	for mn in move_names:
		var mv: Dictionary = DataStore.move(mn)
		if mv.is_empty():
			continue
		var name_l := Label.new()
		name_l.text = mn
		name_l.custom_minimum_size = Vector2(120, 0)
		name_l.add_theme_color_override("font_color", UI.COL_TEXT_DIM if dim else Color.WHITE)
		grid.add_child(name_l)
		var badge := UI.type_badge(mv["type"], 10)
		badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		if dim:
			badge.modulate = Color(1, 1, 1, 0.55)
		grid.add_child(badge)
		var cat := Label.new()
		match mv["category"]:
			"phys": cat.text = "PHY"
			"spec": cat.text = "SPE"
			_: cat.text = "STA"
		cat.add_theme_font_size_override("font_size", 12)
		cat.add_theme_color_override("font_color",
			{"phys": Color("e0905a"), "spec": Color("7aa7e0"), "status": Color("a8a8c0")}.get(mv["category"], UI.COL_TEXT_DIM))
		grid.add_child(cat)
		grid.add_child(_num_cell(str(int(mv["power"])) if int(mv["power"]) > 0 else "-", dim))
		grid.add_child(_num_cell(("%d%%" % int(mv["accuracy"])) if int(mv["accuracy"]) > 0 else "-", dim))
		grid.add_child(_num_cell(str(int(mv["pp"])), dim))
		var fx := Label.new()
		var tags: Array = mv.get("effects", [])
		fx.text = ", ".join(tags.map(func(t): return str(t).split(":")[0])) if not tags.is_empty() else "-"
		fx.add_theme_font_size_override("font_size", 12)
		fx.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
		grid.add_child(fx)
	return grid


func _num_cell(text: String, dim: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", UI.COL_TEXT_DIM if dim else UI.COL_TEXT)
	return l


func _matchups_panel(inst: Dictionary, sp: Dictionary) -> Control:
	var pk := _panel(tr("Defensive Matchups"))
	var panel: PanelContainer = pk[0]
	var v: VBoxContainer = pk[1]
	var ability := UI.ability_id(inst)
	var weak: Array = []
	var resist: Array = []
	var immune: Array = []
	for t in DataStore.types:
		# Ability-aware: Levitate/Water Absorb etc. zero out or dampen types
		# the raw chart would call weaknesses — same math the engine applies.
		var mult := UI.defense_multiplier(sp["types"], ability, t)
		if mult == 0.0:
			immune.append([t, mult])
		elif mult > 1.0:
			weak.append([t, mult])
		elif mult < 1.0:
			resist.append([t, mult])
	weak.sort_custom(func(a, b): return a[1] > b[1])
	resist.sort_custom(func(a, b): return a[1] < b[1])
	for group in [[tr("WEAK TO"), weak, UI.COL_BAD], ["RESISTS", resist, UI.COL_GOOD],
			[tr("IMMUNE TO"), immune, UI.COL_ACCENT]]:
		if (group[1] as Array).is_empty():
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var l := Label.new()
		l.text = group[0]
		l.custom_minimum_size = Vector2(66, 0)
		l.add_theme_font_size_override("font_size", 10)
		l.add_theme_color_override("font_color", group[2])
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(l)
		var wrap := HFlowContainer.new()
		wrap.add_theme_constant_override("h_separation", 4)
		wrap.add_theme_constant_override("v_separation", 3)
		wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for pair in group[1]:
			var b := UI.type_badge(pair[0], 9)
			b.tooltip_text = tr("x%s damage taken from %s moves") % [
				String.num(pair[1], 2).rstrip("0").rstrip("."), pair[0]]
			if float(pair[1]) >= 4.0 or (float(pair[1]) > 0.0 and float(pair[1]) <= 0.25):
				var mark := Label.new()
				mark.text = "x4" if float(pair[1]) >= 4.0 else "x%s" % String.num(pair[1], 2)
				mark.add_theme_font_size_override("font_size", 9)
				mark.add_theme_color_override("font_color", group[2])
				var hb := HBoxContainer.new()
				hb.add_theme_constant_override("separation", 2)
				hb.add_child(b)
				hb.add_child(mark)
				wrap.add_child(hb)
			else:
				wrap.add_child(b)
		row.add_child(wrap)
		v.add_child(row)
	var imm_types := UI.ability_immunities(ability)
	if not imm_types.is_empty():
		var note := Label.new()
		note.text = tr("%s: immune to %s — folded into the chart above.") % [UI.ability_label(inst),
			" & ".join(imm_types.map(func(t): return I18n.t(str(t).capitalize())))]
		note.add_theme_font_size_override("font_size", 11)
		note.add_theme_color_override("font_color", UI.COL_ACCENT.lightened(0.2))
		note.mouse_filter = Control.MOUSE_FILTER_STOP
		note.tooltip_text = UI.ability_tip(inst)
		v.add_child(note)
	return panel


func _form_panel(inst: Dictionary) -> Control:
	var pk := _panel(tr("Recent Form"))
	var panel: PanelContainer = pk[0]
	var v: VBoxContainer = pk[1]
	var entries: Array = SeasonStats.form_of(inst["uid"])
	if entries.is_empty():
		var none := Label.new()
		none.text = tr("No appearances yet this season.")
		none.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
		v.add_child(none)
		return panel
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	for h in ["DATE", "COMP", "OPPONENT", "RESULT", "KOS", "DMG", "RATING"]:
		var l := Label.new()
		l.text = h
		l.add_theme_font_size_override("font_size", 10)
		l.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
		if h in ["KOS", "DMG", "RATING"]:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(l)
	for e in entries.slice(0, 8):
		var won: bool = int(e["us"]) > int(e["them"])
		var d := Label.new()
		d.text = I18n.pretty_date(e["date"])
		d.add_theme_font_size_override("font_size", 12)
		d.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
		grid.add_child(d)
		var comp := Label.new()
		comp.text = "LGE" if e["comp"] == "league" else "CUP"
		comp.add_theme_font_size_override("font_size", 12)
		comp.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
		grid.add_child(comp)
		var opp := Label.new()
		opp.text = str(e["opp_short"])
		opp.add_theme_font_size_override("font_size", 12)
		grid.add_child(opp)
		var res := Label.new()
		res.text = "%s %d-%d" % ["W" if won else "L", int(e["us"]), int(e["them"])]
		res.add_theme_font_size_override("font_size", 12)
		res.add_theme_color_override("font_color", UI.COL_GOOD if won else UI.COL_BAD)
		grid.add_child(res)
		grid.add_child(_num_cell(str(int(e["kos"])), false))
		grid.add_child(_num_cell(str(int(e["dmg"])), false))
		var r := Label.new()
		r.text = I18n.decimal(float(e["rating"]), 2)
		r.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		r.add_theme_font_size_override("font_size", 12)
		r.add_theme_color_override("font_color", UI.rating_color(float(e["rating"])))
		grid.add_child(r)
	return panel


# ------------------------------------------------------------------ right column

func _kv_row(grid: GridContainer, key: String, value: String, col: Color = UI.COL_TEXT) -> void:
	var k := Label.new()
	k.text = key
	k.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	grid.add_child(k)
	var val := Label.new()
	val.text = value
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val.add_theme_color_override("font_color", col)
	grid.add_child(val)


## FM's qualitative layer: personality archetype + hidden-attribute read,
## squad-status expectation, the explained happiness ledger (every factor a
## row, actionable concerns get a resolve button), tracked promises and the
## recent-morale-events log.
func _mind_panel(inst: Dictionary) -> Control:
	var pk := _panel(tr("Personality & Happiness"))
	var panel: PanelContainer = pk[0]
	var v: VBoxContainer = pk[1]
	var svc: Node = Service.ensure()
	var uid: String = inst["uid"]
	var h: Dictionary = Personality.happiness(inst, svc, Personality.context(svc))
	var arch: Dictionary = h["arch"]
	var st: Dictionary = h["status"]

	# --- archetype
	var arch_l := Label.new()
	arch_l.text = str(arch["name"])
	arch_l.add_theme_font_size_override("font_size", 15)
	arch_l.add_theme_color_override("font_color", Color.WHITE)
	v.add_child(arch_l)
	var desc := Label.new()
	desc.text = str(arch["desc"])
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 11)
	desc.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	v.add_child(desc)
	var attrs_l := Label.new()
	attrs_l.text = Personality.attrs_line(h["attrs"])
	attrs_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	attrs_l.add_theme_font_size_override("font_size", 11)
	attrs_l.add_theme_color_override("font_color", UI.COL_TEXT)
	attrs_l.mouse_filter = Control.MOUSE_FILTER_STOP
	attrs_l.tooltip_text = tr("The coaches' read of the hidden character attributes. They scale contract demands, praise/criticism reactions, result swings and promise fallout.")
	v.add_child(attrs_l)

	# --- squad status expectation
	var st_row := HBoxContainer.new()
	st_row.add_theme_constant_override("separation", 8)
	v.add_child(st_row)
	var st_k := Label.new()
	st_k.text = tr("SQUAD STATUS")
	st_k.add_theme_font_size_override("font_size", 10)
	st_k.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	st_k.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	st_row.add_child(st_k)
	var st_v := Label.new()
	st_v.text = str(st["label"])
	st_v.add_theme_font_size_override("font_size", 13)
	st_v.add_theme_color_override("font_color", st["color"])
	st_v.mouse_filter = Control.MOUSE_FILTER_STOP
	st_v.tooltip_text = tr("Rated %d of %d in the squad.") % [int(st["rank"]), int(st["n"])]
	st_row.add_child(st_v)
	var expect := Label.new()
	expect.text = str(st["expect"])
	expect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	expect.add_theme_font_size_override("font_size", 11)
	expect.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	v.add_child(expect)

	# --- happiness banner
	var band := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	var hc: Color = h["color"]
	sb.bg_color = Color(hc.r, hc.g, hc.b, 0.13)
	sb.border_color = hc
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	band.add_theme_stylebox_override("panel", sb)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 10)
	band.add_child(brow)
	var word := Label.new()
	word.text = str(h["word"]).to_upper()
	word.add_theme_font_size_override("font_size", 14)
	word.add_theme_color_override("font_color", hc.lightened(0.15))
	word.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brow.add_child(word)
	var hb2 := _bar(float(h["score"]) / 100.0, hc, 120)
	brow.add_child(hb2)
	var scr := Label.new()
	scr.text = "%d/100" % int(h["score"])
	scr.add_theme_font_size_override("font_size", 11)
	scr.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	scr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brow.add_child(scr)
	v.add_child(band)

	# --- factor ledger with resolve actions
	var facs: Array = (h["factors"] as Array).duplicate()
	facs.sort_custom(func(x, y): return float(x["w"]) < float(y["w"]))
	if facs.is_empty():
		var none := Label.new()
		none.text = tr("Nothing on their mind — no active happiness factors.")
		none.add_theme_font_size_override("font_size", 11)
		none.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
		v.add_child(none)
	for fac in facs:
		var w := float(fac["w"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 7)
		v.add_child(row)
		var dot := TextureRect.new()
		dot.texture = UI.dot_icon(UI.COL_GOOD if w >= 0.0 else (UI.COL_BAD if w <= -8.0 else UI.COL_WARN), 9)
		dot.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		row.add_child(dot)
		var fl := Label.new()
		fl.text = str(fac["short"])
		fl.add_theme_font_size_override("font_size", 12)
		fl.add_theme_color_override("font_color", UI.COL_TEXT if w >= 0.0 else
			(UI.COL_BAD if w <= -8.0 else UI.COL_WARN))
		fl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fl.mouse_filter = Control.MOUSE_FILTER_STOP
		fl.tooltip_text = str(fac["detail"])
		row.add_child(fl)
		var act := str(fac["act"])
		if act != "":
			var ab := Button.new()
			ab.add_theme_font_size_override("font_size", 11)
			match act:
				"contract":
					ab.text = tr("Offer Deal")
					ab.disabled = svc.talks_locked(uid)
					ab.pressed.connect(func() -> void: Actions.open_contract_dialog(_host(), uid))
				"unlist":
					ab.text = "Unlist"
					ab.pressed.connect(func() -> void:
						var err: String = svc.unlist(uid)
						if err != "":
							Actions.notice(_host(), tr("Transfer list"), err))
				"promise_battles":
					ab.text = "Promise"
					ab.disabled = not svc.open_promise(uid).is_empty()
					ab.tooltip_text = tr("Promise a run of battles — tracked with a deadline and real consequences")
					ab.pressed.connect(func() -> void: Actions.open_promise_dialog(_host(), uid, "battles"))
			row.add_child(ab)

	# --- promises
	v.add_child(HSeparator.new())
	var p_head := HBoxContainer.new()
	v.add_child(p_head)
	var p_t := Label.new()
	p_t.text = "PROMISES"
	p_t.add_theme_font_size_override("font_size", 10)
	p_t.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	p_t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p_t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p_head.add_child(p_t)
	var pm := MenuButton.new()
	pm.text = tr("Make A Promise...")
	pm.flat = false
	pm.disabled = not svc.open_promise(uid).is_empty()
	if pm.disabled:
		pm.tooltip_text = tr("A promise is already outstanding — one at a time.")
	var pop := pm.get_popup()
	for i in Actions.PROMISE_KINDS.size():
		var kind: String = Actions.PROMISE_KINDS[i]
		if kind == "unlist" and not svc.is_listed(inst):
			continue
		pop.add_item(Actions.PROMISE_MENU[kind], i)
	pop.id_pressed.connect(func(id: int) -> void:
		Actions.open_promise_dialog(_host(), uid, Actions.PROMISE_KINDS[id]))
	p_head.add_child(pm)
	var plist: Array = svc.promises_for(uid)
	plist.reverse()
	var pledges: Array = svc.inbox_pledges(uid).filter(func(pl): return str(pl.get("status", "")) == "open")
	if plist.is_empty() and pledges.is_empty():
		var pn := Label.new()
		pn.text = tr("None made. A tracked promise (battles, a new deal, unlisting) is the strongest lever on an unhappy battler — and the costliest to break.")
		pn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pn.add_theme_font_size_override("font_size", 11)
		pn.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
		v.add_child(pn)
	for p in plist.slice(0, 3):
		var status := str(p["status"])
		var col: Color = UI.COL_ACCENT.lightened(0.25) if status == "open" else \
			(UI.COL_GOOD if status == "kept" else (UI.COL_BAD if status == "broken" else UI.COL_TEXT_DIM))
		var pr := Label.new()
		pr.text = "%s %s — %s" % [
			{"open": "OPEN", "kept": "KEPT", "broken": "BROKEN", "void": "VOID"}.get(status, "?"),
			str(p["text"]).trim_suffix("."),
			("deadline %s" % I18n.pretty_date(str(p["deadline"]))) if status == "open"
			else (I18n.t("resolved %s") % I18n.pretty_date(str(p["resolved_on"])))]
		pr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pr.add_theme_font_size_override("font_size", 11)
		pr.add_theme_color_override("font_color", col)
		v.add_child(pr)
	for pl in pledges:
		var il := Label.new()
		il.text = tr("OPEN (via coach, Inbox) — %d battles by %s") % [int(pl.get("target", 4)),
			I18n.pretty_date(str(pl.get("deadline", GameState.current_date)))]
		il.add_theme_font_size_override("font_size", 11)
		il.add_theme_color_override("font_color", UI.COL_ACCENT.lightened(0.25))
		v.add_child(il)

	# --- recent morale events
	var log: Array = svc.mood_log(uid)
	if not log.is_empty():
		v.add_child(HSeparator.new())
		var m_t := Label.new()
		m_t.text = tr("RECENT MORALE EVENTS")
		m_t.add_theme_font_size_override("font_size", 10)
		m_t.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
		v.add_child(m_t)
		for e in log.slice(0, 5):
			var er := HBoxContainer.new()
			er.add_theme_constant_override("separation", 8)
			v.add_child(er)
			var ed := Label.new()
			ed.text = I18n.pretty_date(str(e["d"]))
			ed.custom_minimum_size = Vector2(78, 0)
			ed.add_theme_font_size_override("font_size", 11)
			ed.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
			er.add_child(ed)
			var edelta := Label.new()
			edelta.text = "%+d" % int(e["delta"])
			edelta.custom_minimum_size = Vector2(26, 0)
			edelta.add_theme_font_size_override("font_size", 11)
			edelta.add_theme_color_override("font_color",
				UI.COL_GOOD if int(e["delta"]) > 0 else UI.COL_BAD)
			er.add_child(edelta)
			var ew := Label.new()
			ew.text = str(e["why"])
			ew.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			ew.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ew.add_theme_font_size_override("font_size", 11)
			ew.add_theme_color_override("font_color", UI.COL_TEXT)
			er.add_child(ew)
	return panel


func _coach_report_panel(inst: Dictionary) -> Control:
	var pk := _panel(tr("Coach Report"))
	var panel: PanelContainer = pk[0]
	var v: VBoxContainer = pk[1]
	var rep: Dictionary = Ability.report(inst)

	# star rows
	for row_def in [
			[tr("Current ability"), Ability.stars_icon(float(rep["now"]), -1.0, Ability.COL_STARS_NOW, 13),
				Ability.ability_word(float(rep["now"]))],
			["Potential", Ability.stars_icon(float(rep["pot_lo"]), float(rep["pot_hi"]), Ability.COL_STARS_POT, 13),
				Ability.stars_range_text(float(rep["pot_lo"]), float(rep["pot_hi"])) + tr(" stars")]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var l := Label.new()
		l.text = row_def[0]
		l.custom_minimum_size = Vector2(102, 0)
		l.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(l)
		var tr := TextureRect.new()
		tr.texture = row_def[1]
		tr.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		row.add_child(tr)
		var wl := Label.new()
		wl.text = row_def[2]
		wl.add_theme_font_size_override("font_size", 12)
		wl.add_theme_color_override("font_color", UI.COL_TEXT)
		wl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(wl)
		v.add_child(row)

	# verdict banner
	var band := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	var vc: Color = rep["verdict_color"]
	sb.bg_color = Color(vc.r, vc.g, vc.b, 0.14)
	sb.border_color = vc
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	band.add_theme_stylebox_override("panel", sb)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 1)
	band.add_child(bv)
	var word := Label.new()
	word.text = str(rep["verdict"]).to_upper()
	word.add_theme_font_size_override("font_size", 13)
	word.add_theme_color_override("font_color", vc.lightened(0.15))
	bv.add_child(word)
	var reason := Label.new()
	reason.text = str(rep["reason"])
	reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reason.add_theme_font_size_override("font_size", 11)
	reason.add_theme_color_override("font_color", UI.COL_TEXT)
	bv.add_child(reason)
	v.add_child(band)

	# report body
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	var top_now := maxi(int(round((1.0 - float(rep["pct_now"])) * 100.0)), 1)
	var top_pot := maxi(int(round((1.0 - float(rep["pct_pot"])) * 100.0)), 1)
	_kv_row(grid, tr("League standing now"), tr("top %d%% of %d") % [top_now, int(rep["league_n"])],
		UI.COL_GOOD if top_now <= 20 else UI.COL_TEXT)
	_kv_row(grid, tr("Standing at peak"), tr("top %d%% of %d") % [top_pot, int(rep["league_n"])],
		UI.COL_GOOD if top_pot <= 20 else UI.COL_TEXT)
	_kv_row(grid, tr("IV ceiling"), "%d%% -> ~%d%%" % [int(rep["iv_pct"]), int(rep["iv_pct_peak"])],
		UI.COL_GOOD if int(rep["iv_pct_peak"]) - int(rep["iv_pct"]) >= 10 else UI.COL_TEXT)
	_kv_row(grid, tr("Headroom realisable"), tr("%d%% (age/growth)") % int(round(float(rep["realise"]) * 100.0)))
	_kv_row(grid, "Best move now", str(rep["move_now"]))
	if str(rep["move_ceiling"]) != str(rep["move_now"]):
		_kv_row(grid, "Learnset ceiling", str(rep["move_ceiling"]), UI.COL_ACCENT.lightened(0.25))
	var foot := Label.new()
	foot.text = tr("%s confidence — ability judged by %s (%d/20), potential by %s (%d/20). Stars are relative to every battler in the league today.") % [
		rep["confidence"], rep["ja_name"], int(rep["ja"]), rep["jp_name"], int(rep["jp"])]
	foot.add_theme_font_size_override("font_size", 11)
	foot.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(foot)
	return panel


func _season_panel(inst: Dictionary) -> Control:
	var pk := _panel(I18n.t("Season %s") % GameState.season_start.substr(0, 4))
	var panel: PanelContainer = pk[0]
	var v: VBoxContainer = pk[1]
	var uid: String = inst["uid"]
	var apps := SeasonStats.stat_of(uid, "battles")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	_kv_row(grid, "Battles", str(apps))
	_kv_row(grid, tr("Team wins when used"), "%d" % SeasonStats.stat_of(uid, "wins"))
	_kv_row(grid, "Knockouts", str(SeasonStats.stat_of(uid, "kos")), UI.COL_GOOD if SeasonStats.stat_of(uid, "kos") > 0 else UI.COL_TEXT)
	_kv_row(grid, "Damage dealt", str(SeasonStats.stat_of(uid, "dmg")))
	_kv_row(grid, "Damage taken", str(SeasonStats.stat_of(uid, "taken")))
	_kv_row(grid, "Times fainted", str(SeasonStats.stat_of(uid, "faints")),
		UI.COL_BAD if SeasonStats.stat_of(uid, "faints") > 0 else UI.COL_TEXT)
	var rat := SeasonStats.avg_rating(uid)
	_kv_row(grid, tr("Average rating"), I18n.decimal(rat, 2) if apps > 0 else "-",
		UI.rating_color(rat) if apps > 0 else UI.COL_TEXT_DIM)
	if apps == 0:
		var note := Label.new()
		note.text = tr("No competitive battles yet this season.")
		note.add_theme_font_size_override("font_size", 12)
		note.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
		v.add_child(note)
	return panel


func _condition_panel(inst: Dictionary) -> Control:
	var pk := _panel(tr("Condition & Morale"))
	var panel: PanelContainer = pk[0]
	var v: VBoxContainer = pk[1]
	for pair in [["Condition", int(inst["condition"])], ["Fitness", int(inst["fitness"])],
			["Morale", int(inst["morale"])]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var l := Label.new()
		l.text = pair[0]
		l.custom_minimum_size = Vector2(72, 0)
		l.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
		row.add_child(l)
		row.add_child(_bar(pair[1] / 100.0, UI.pct_color(pair[1]), 140))
		var n := Label.new()
		n.text = ("%d%%" % pair[1]) if pair[0] != "Morale" else "%s (%d)" % [UI.morale_word(pair[1]), pair[1]]
		n.add_theme_color_override("font_color", UI.pct_color(pair[1]))
		row.add_child(n)
		v.add_child(row)
	return panel


func _item_panel(inst: Dictionary) -> Control:
	var pk := _panel(tr("Held Item"))
	var panel: PanelContainer = pk[0]
	var v: VBoxContainer = pk[1]
	var item_id := str(inst.get("held_item")) if inst.get("held_item") else ""
	var item: Dictionary = DataStore.item(item_id) if item_id != "" else {}
	if item.is_empty():
		var none := Label.new()
		none.text = tr("Not holding anything. A held item works passively in every battle — Leftovers, a Choice item, a pinch berry...")
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.add_theme_font_size_override("font_size", 12)
		none.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
		v.add_child(none)
	else:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		v.add_child(row)
		var badge := UI.item_badge(item, 26, 14)
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(badge)
		var name_l := Label.new()
		name_l.text = str(item["name"])
		name_l.add_theme_font_size_override("font_size", 15)
		name_l.add_theme_color_override("font_color", Color.WHITE)
		name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(name_l)
		var rar := Label.new()
		rar.text = str(item.get("rarity", "")).to_upper()
		rar.add_theme_font_size_override("font_size", 10)
		rar.add_theme_color_override("font_color", UI.rarity_color(str(item.get("rarity", ""))))
		rar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(rar)
		var rsp := Control.new()
		rsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(rsp)
		var val := Label.new()
		val.text = UI.money(int(item.get("price", 0)))
		val.add_theme_font_size_override("font_size", 12)
		val.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
		val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(val)
		var desc := Label.new()
		desc.text = str(item.get("desc", ""))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_font_size_override("font_size", 12)
		desc.add_theme_color_override("font_color", UI.COL_TEXT)
		v.add_child(desc)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	v.add_child(foot)
	var hint := Label.new()
	hint.text = tr("Buy, equip and swap held items in the club storeroom.")
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	foot.add_child(hint)
	var go := Button.new()
	go.text = tr("Items Screen >")
	go.tooltip_text = tr("Open the Items screen: shop catalog + squad equipment board")
	go.pressed.connect(_goto_items)
	foot.add_child(go)
	return panel


func _goto_items() -> void:
	var n: Node = get_parent()
	while n != null and not n.has_method("navigate_to"):
		n = n.get_parent()
	if n != null:
		n.call("navigate_to", "items")


func _development_panel(inst: Dictionary, sp: Dictionary) -> Control:
	var pk := _panel("Development")
	var panel: PanelContainer = pk[0]
	var v: VBoxContainer = pk[1]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	var ivs: Dictionary = inst.get("ivs", {})
	var iv_sum := 0
	for k in ivs:
		iv_sum += int(ivs[k])
	var iv_pct := int(round(float(iv_sum) / 90.0 * 100.0))
	_kv_row(grid, tr("Growth curve"), UI.growth_label(sp.get("growth", "")))
	_kv_row(grid, tr("Career stage"), UI.age_stage(int(inst["age_months"])))
	_kv_row(grid, tr("Genetic potential (IVs)"), "%d%%" % iv_pct,
		UI.COL_GOOD if iv_pct >= 65 else (UI.COL_WARN if iv_pct < 40 else UI.COL_TEXT))
	_kv_row(grid, tr("Learnset size"), tr("%d moves") % (sp.get("learnset", []) as Array).size())
	var next_fx: Dictionary = GameState.next_player_fixture()
	if not next_fx.is_empty():
		var opp_id: String = next_fx["away"] if GameState.is_player_club(next_fx["home"]) else next_fx["home"]
		_kv_row(grid, tr("Next fixture"), "%s, %s" % [GameState.club(opp_id).get("short", "?"),
			I18n.pretty_date(next_fx["date"])])

	# Individual training focus, wired to the training model.
	var svc: Node = Service.ensure()
	var uid: String = inst["uid"]
	var focus_row := HBoxContainer.new()
	focus_row.add_theme_constant_override("separation", 8)
	v.add_child(focus_row)
	var fl := Label.new()
	fl.text = tr("Training focus")
	fl.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	fl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	focus_row.add_child(fl)
	var fsp := Control.new()
	fsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	focus_row.add_child(fsp)
	var picker := OptionButton.new()
	var current: String = svc.training_focus(uid)
	for i in Actions.FOCUS_KEYS.size():
		var key: String = Actions.FOCUS_KEYS[i]
		picker.add_item(Actions.FOCUS_LABELS[key], i)
		if key == current:
			picker.selected = i
	picker.item_selected.connect(func(i: int) -> void:
		svc.set_training_focus(uid, Actions.FOCUS_KEYS[i]))
	focus_row.add_child(picker)
	return panel


## FM-style development-milestone panel: the mon's evolution pathways with
## live eligibility, the pending manager-approval decision (Approve/Postpone
## act on the real EvolutionService) and stone routes (Use consumes stock).
func _evolution_panel(inst: Dictionary) -> Control:
	var svc: RefCounted = EvoSvc.instance
	if svc == null:
		return null
	var uid: String = str(inst["uid"])
	var options: Array = svc.eligibility(inst)
	if options.is_empty():
		return null
	var pk := _panel("Evolution")
	var panel: PanelContainer = pk[0]
	var v: VBoxContainer = pk[1]

	var pend: Dictionary = svc.pending_for(uid)
	if not pend.is_empty():
		v.add_child(_evo_pending_box(inst, pend, svc))

	for o in options:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		v.add_child(row)
		var arrow := Label.new()
		arrow.text = "->  %s" % str(o["to_name"])
		arrow.custom_minimum_size = Vector2(130, 0)
		arrow.add_theme_color_override("font_color",
			Color.WHITE if o["ok"] else UI.COL_TEXT)
		row.add_child(arrow)
		var mth := Label.new()
		mth.text = _evo_method_word(str(o["method"]))
		mth.custom_minimum_size = Vector2(88, 0)
		mth.add_theme_font_size_override("font_size", 11)
		mth.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
		row.add_child(mth)
		var status := Label.new()
		status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		status.add_theme_font_size_override("font_size", 12)
		if o["ok"]:
			status.text = "READY" if str(o["method"]) != "stone" else "READY — stone in stock"
			status.add_theme_color_override("font_color", UI.COL_GOOD)
		else:
			status.text = str(o["why"])
			status.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
		status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(status)

	# stone routes get a live Use button (consumes the stone from the storeroom)
	var stones: Array = svc.stone_options(uid)
	if not stones.is_empty():
		var srow := HFlowContainer.new()
		srow.add_theme_constant_override("h_separation", 8)
		srow.add_theme_constant_override("v_separation", 6)
		v.add_child(srow)
		for s in stones:
			var b := Button.new()
			var owned := int(s["owned"])
			b.text = I18n.t("Use %s (%d in stock)") % [str(s["item_name"]), owned] if owned > 0 \
				else I18n.t("%s: none in stock") % str(s["item_name"])
			b.disabled = owned <= 0
			b.tooltip_text = (tr("Evolves %s into %s immediately — using the stone is the approval.") %
				[UI.display_name(inst), str(s["to_name"])]) if owned > 0 \
				else tr("Buy one in the League Store (Items screen).")
			var iid := str(s["item_id"])
			b.pressed.connect(func() -> void: _evo_act(svc.use_stone(uid, iid)))
			srow.add_child(b)
		if stones.all(func(s2): return int(s2["owned"]) <= 0):
			var shop := Button.new()
			shop.text = tr("League Store >")
			shop.pressed.connect(_goto_items)
			srow.add_child(shop)

	var foot := Label.new()
	foot.text = tr("Effective Lv %d  (Lv %d + %d from %d training development pts)") % \
		[svc.effective_level(inst), int(inst["level"]), svc.dev_levels(uid), svc.dev_points(uid)]
	foot.add_theme_font_size_override("font_size", 11)
	foot.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	foot.tooltip_text = tr("Levels are static in this league — training development is what pushes a Pokémon past evolution thresholds (6 dev pts = 1 effective level).")
	v.add_child(foot)
	return panel


## The highlighted "awaiting your approval" decision box inside the panel.
func _evo_pending_box(inst: Dictionary, pend: Dictionary, svc: RefCounted) -> Control:
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UI.COL_GOOD, 0.12)
	sb.border_color = UI.COL_GOOD
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	box.add_theme_stylebox_override("panel", sb)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 6)
	box.add_child(bv)
	var head := Label.new()
	head.text = I18n.t("READY TO EVOLVE INTO %s — AWAITING YOUR APPROVAL") % str(pend["to_name"]).to_upper()
	head.add_theme_font_size_override("font_size", 12)
	head.add_theme_color_override("font_color", UI.COL_GOOD)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bv.add_child(head)
	var uid: String = str(inst["uid"])
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	bv.add_child(btns)
	var ok_b := Button.new()
	ok_b.text = tr("Approve Evolution")
	ok_b.tooltip_text = tr("Transform %s into %s now: +%d morale, old learnset stays trainable.") % \
		[UI.display_name(inst), str(pend["to_name"]), EvoSvc.EVOLVE_MORALE_BOOST]
	ok_b.pressed.connect(func() -> void: _evo_act(svc.approve(uid)))
	btns.add_child(ok_b)
	var no_b := Button.new()
	no_b.text = tr("Postpone (-%d morale)") % EvoSvc.POSTPONE_MORALE_COST
	no_b.tooltip_text = tr("Hold it back: costs %d morale, the offer returns in %d days if still eligible.") % \
		[EvoSvc.POSTPONE_MORALE_COST, EvoSvc.REOFFER_DAYS]
	no_b.pressed.connect(func() -> void: _evo_act(svc.postpone(uid)))
	btns.add_child(no_b)
	return box


func _evo_act(err: String) -> void:
	if err != "":
		var dlg := AcceptDialog.new()
		dlg.title = "Evolution"
		dlg.dialog_text = err
		dlg.confirmed.connect(dlg.queue_free)
		dlg.canceled.connect(dlg.queue_free)
		_host().add_child(dlg)
		dlg.popup_centered()
	refresh()


func _evo_method_word(method: String) -> String:
	match method:
		"level": return "Level"
		"development": return "Development"
		"stone": return "Stone"
	return method.capitalize()


func _contract_panel(inst: Dictionary) -> Control:
	var pk := _panel("Contract")
	var panel: PanelContainer = pk[0]
	var v: VBoxContainer = pk[1]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	var club: Dictionary = GameState.player_club()
	var wage_bill := 0
	for m in club["squad"]:
		wage_bill += int(m["contract"]["salary"])
	var salary := int(inst["contract"]["salary"])
	var expiry: String = inst["contract"]["expiry"]
	var days := UI.days_between(GameState.current_date, expiry)
	_kv_row(grid, "Wage", UI.money(salary) + "/wk")
	_kv_row(grid, "Expires", I18n.pretty_date(expiry),
		UI.COL_BAD if days < 90 else (UI.COL_WARN if days < 240 else UI.COL_TEXT))
	_kv_row(grid, tr("Time remaining"), tr("%d days") % maxi(days, 0))
	_kv_row(grid, tr("Share of wage bill"), I18n.decimal(float(salary) / maxf(wage_bill, 1.0) * 100.0, 1) + "%")
	_kv_row(grid, tr("Estimated value"), UI.money(UI.est_value(inst)), UI.COL_GOOD)

	var svc: Node = Service.ensure()
	var uid: String = inst["uid"]
	var demand: Dictionary = svc.contract_demand(inst)
	_kv_row(grid, tr("Renewal demand"), tr("~%s/wk, %d-year deal") %
		[UI.money(int(demand["wage"])), int(demand["years"])],
		UI.COL_WARN if int(demand["wage"]) > salary * 2 else UI.COL_TEXT)
	if svc.is_listed(inst):
		_kv_row(grid, tr("Transfer status"), tr("Listed at %s") % UI.money(int(inst.get("asking_price", 0))), UI.COL_BAD)
		var bids: Array = svc.offers_for(uid)
		if not bids.is_empty():
			_kv_row(grid, tr("Live bids"), tr("%d (best %s)") % [bids.size(),
				UI.money(bids.map(func(o): return int(o["bid"])).max())], UI.COL_WARN)
	if svc.talks_locked(uid):
		var note := Label.new()
		note.text = tr("Talks broke down — no renegotiation before %s.") % \
			I18n.pretty_date(svc.talks_locked_until(uid))
		note.add_theme_font_size_override("font_size", 12)
		note.add_theme_color_override("font_color", UI.COL_BAD)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(note)
	else:
		var offer_b := Button.new()
		offer_b.text = tr("Offer New Contract")
		offer_b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		offer_b.pressed.connect(func() -> void: Actions.open_contract_dialog(_host(), uid))
		v.add_child(offer_b)
	return panel


# ------------------------------------------------------------------ history tab

func _build_history_body(root: VBoxContainer, inst: Dictionary) -> void:
	var hist: Node = History.ensure()
	hist.sync()
	var uid: String = inst["uid"]

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.custom_minimum_size = Vector2(640, 0)
	body.add_child(left)
	left.add_child(_career_stats_panel(hist, uid))
	left.add_child(_progression_panel(hist, inst))

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	var contracts := _events_panel(hist, uid, tr("Transfers & Contracts"),
		History.CONTRACT_TYPES, tr("No contract or transfer events recorded yet."))
	contracts.size_flags_stretch_ratio = 0.4
	right.add_child(contracts)
	var devlog := _events_panel(hist, uid, tr("Development Log"),
		History.DEV_TYPES,
		tr("No development recorded yet — attribute gains, learned moves and level changes will appear here."))
	devlog.size_flags_stretch_ratio = 0.6
	right.add_child(devlog)


func _career_stats_panel(hist: Node, uid: String) -> Control:
	var pk := _panel(tr("Career Stats — Season By Season"))
	var panel: PanelContainer = pk[0]
	var v: VBoxContainer = pk[1]
	var rows: Array = hist.season_rows(uid)
	var grid := GridContainer.new()
	grid.columns = 9
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 5)
	v.add_child(grid)
	for h in ["SEASON", "CLUB", "APPS", "WON", "KOS", "DMG", "TKN", "FNT", tr("AV RAT")]:
		var l := Label.new()
		l.text = h
		l.add_theme_font_size_override("font_size", 10)
		l.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
		if not h in ["SEASON", "CLUB"]:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(l)
	var current_label: String = History.season_label(GameState.season_start)
	for row in rows:
		var is_current: bool = str(row["season"]) == current_label
		var s := Label.new()
		s.text = str(row["season"]) + ("  ·" if is_current else "")
		s.tooltip_text = tr("Current season (live)") if is_current else ""
		s.add_theme_font_size_override("font_size", 13)
		s.add_theme_color_override("font_color", Color.WHITE if is_current else UI.COL_TEXT)
		grid.add_child(s)
		var c := Label.new()
		c.text = str(row["club"])
		c.add_theme_font_size_override("font_size", 13)
		c.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
		grid.add_child(c)
		var apps := int(row["apps"])
		for k in ["apps", "wins", "kos", "dmg", "taken", "faints"]:
			grid.add_child(_num_cell(str(int(row[k])) if apps > 0 else "-", apps == 0))
		var r := Label.new()
		r.text = I18n.decimal(float(row["rat"]), 2) if apps > 0 else "-"
		r.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		r.add_theme_font_size_override("font_size", 13)
		r.add_theme_color_override("font_color",
			UI.rating_color(float(row["rat"])) if apps > 0 else UI.COL_TEXT_DIM)
		grid.add_child(r)
	# totals row
	var tot: Dictionary = hist.career_totals(uid)
	if rows.size() != 1:
		var tl := Label.new()
		tl.text = "TOTAL"
		tl.add_theme_font_size_override("font_size", 12)
		tl.add_theme_color_override("font_color", Color.WHITE)
		grid.add_child(tl)
		var tc := Label.new()
		tc.text = tr("%d season%s") % [int(tot["seasons"]), "s" if int(tot["seasons"]) != 1 else ""]
		tc.add_theme_font_size_override("font_size", 12)
		tc.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
		grid.add_child(tc)
		for k in ["apps", "wins", "kos", "dmg", "taken", "faints"]:
			var n := _num_cell(str(int(tot[k])), false)
			n.add_theme_color_override("font_color", Color.WHITE)
			grid.add_child(n)
		var tr := Label.new()
		tr.text = I18n.decimal(float(tot["rat"]), 2) if int(tot["apps"]) > 0 else "-"
		tr.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		tr.add_theme_font_size_override("font_size", 12)
		tr.add_theme_color_override("font_color",
			UI.rating_color(float(tot["rat"])) if int(tot["apps"]) > 0 else UI.COL_TEXT_DIM)
		grid.add_child(tr)
	var foot := Label.new()
	foot.text = tr("Aggregated from every competitive fixture; the current season updates live and is frozen at season end.") \
		if rows.size() <= 1 else \
		tr("Past seasons are frozen records; the current season (·) updates live from competitive fixtures.")
	foot.add_theme_font_size_override("font_size", 11)
	foot.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(foot)
	return panel


func _progression_panel(hist: Node, inst: Dictionary) -> Control:
	var pk := _panel(tr("Attribute Progression"))
	var panel: PanelContainer = pk[0]
	var v: VBoxContainer = pk[1]
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var uid: String = inst["uid"]
	var d: Dictionary = hist.delta_since(uid, inst, DEV_WINDOW_DAYS)
	if not bool(d.get("has", false)):
		var none := Label.new()
		none.text = tr("No snapshots recorded yet.")
		none.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
		v.add_child(none)
		return panel

	var stats := UI.effective_stats(inst)
	var ivs: Dictionary = inst.get("ivs", {})
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 5)
	v.add_child(grid)
	var from_pretty: String = I18n.pretty_date(str(d["from"]))
	for h in ["ATTRIBUTE", tr("IV %s") % from_pretty.to_upper(), tr("IV NOW"), "CHANGE", tr("EFF THEN"), tr("EFF NOW")]:
		var l := Label.new()
		l.text = h
		l.add_theme_font_size_override("font_size", 10)
		l.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
		if h != "ATTRIBUTE":
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(l)
	for k in STAT_KEYS:
		var name_l := Label.new()
		name_l.text = STAT_NAMES[k]
		name_l.custom_minimum_size = Vector2(84, 0)
		grid.add_child(name_l)
		var iv_then := int((d["base_ivs"] as Dictionary).get(k, 8))
		var iv_now := int(ivs.get(k, 8))
		var d_iv := int((d["ivs"] as Dictionary)[k])
		grid.add_child(_num_cell("%d/15" % iv_then, true))
		var now_l := _num_cell("%d/15" % iv_now, false)
		now_l.add_theme_color_override("font_color",
			UI.COL_GOOD if d_iv > 0 else (Color.WHITE if iv_now >= 12 else UI.COL_TEXT))
		grid.add_child(now_l)
		var ch := Label.new()
		ch.text = ("+%d ^" % d_iv) if d_iv > 0 else ("%d v" % d_iv if d_iv < 0 else "=")
		ch.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		ch.add_theme_font_size_override("font_size", 13)
		ch.add_theme_color_override("font_color",
			UI.COL_GOOD if d_iv > 0 else (UI.COL_BAD if d_iv < 0 else UI.COL_TEXT_DIM))
		grid.add_child(ch)
		grid.add_child(_num_cell(str(int((d["base_stats"] as Dictionary).get(k, 0))), true))
		var eff_l := _num_cell(str(int(stats[k])), false)
		if int((d["stats"] as Dictionary)[k]) > 0:
			eff_l.add_theme_color_override("font_color", UI.COL_GOOD)
		grid.add_child(eff_l)

	v.add_child(HSeparator.new())
	var snaps: Array = hist.snapshots_for(uid)
	var tot_series: Array = []
	var val_series: Array = []
	for s in snaps:
		var t := 0
		for k in STAT_KEYS:
			t += int((s["stats"] as Dictionary).get(k, 0))
		tot_series.append(t)
		val_series.append(int(s["value"]))
	var cur_tot := 0
	for k in STAT_KEYS:
		cur_tot += int(stats[k])
	tot_series.append(cur_tot)
	val_series.append(UI.est_value(inst))
	_spark_row(v, tr("Total effective stats"), tot_series,
		str(tot_series[0]), str(cur_tot), UI.COL_ACCENT.lightened(0.2))
	_spark_row(v, tr("Market value"), val_series,
		UI.money(int(val_series[0])), UI.money(UI.est_value(inst)), UI.COL_GOOD)
	var foot := Label.new()
	foot.text = tr("%d snapshot%s since %s (weekly + on every attribute change). Development window: last %d days.") % [
		snaps.size(), "" if snaps.size() == 1 else "s",
		I18n.pretty_date(hist.joined_on(uid)), DEV_WINDOW_DAYS]
	foot.add_theme_font_size_override("font_size", 11)
	foot.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(foot)
	return panel


func _spark_row(v: VBoxContainer, label: String, series: Array,
		first_txt: String, last_txt: String, col: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(150, 0)
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	var a := Label.new()
	a.text = first_txt
	a.add_theme_font_size_override("font_size", 12)
	a.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	a.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(a)
	var spark := Sparkline.new(series, col)
	spark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	spark.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spark)
	var b := Label.new()
	b.text = last_txt
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", col)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(b)
	v.add_child(row)


const EVENT_TAGS := {
	"baseline": ["START", Color("6b7089")],
	"arrived": ["SIGNED", Color("57c979")],
	"renewal": ["RENEWAL", Color("57c979")],
	"listed": ["LISTED", Color("e0b050")],
	"unlisted": ["UNLISTED", Color("8b91a8")],
	"sold": ["SOLD", Color("e06060")],
	"released": ["RELEASED", Color("e06060")],
	"contract": ["CONTRACT", Color("8b91a8")],
	"development": ["TRAINING", Color("7b6cff")],
	"move": ["MOVE", Color("7aa7e0")],
	"level": ["LEVEL", Color("e0905a")],
}


func _events_panel(hist: Node, uid: String, title: String, types: Array, empty_text: String) -> Control:
	var pk := _panel(title)
	var panel: PanelContainer = pk[0]
	var v: VBoxContainer = pk[1]
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var events: Array = hist.events_for(uid, types)
	var count := Label.new()
	count.text = tr("%d event%s on record") % [events.size(), "" if events.size() == 1 else "s"]
	count.add_theme_font_size_override("font_size", 11)
	count.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	v.add_child(count)
	if events.is_empty():
		var none := Label.new()
		none.text = empty_text
		none.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(none)
		return panel
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for e in events.slice(0, 60):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		list.add_child(row)
		var date := Label.new()
		date.text = I18n.pretty_date(str(e["date"]))
		date.custom_minimum_size = Vector2(84, 0)
		date.add_theme_font_size_override("font_size", 12)
		date.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
		row.add_child(date)
		var tag_def: Array = EVENT_TAGS.get(str(e["type"]), ["EVENT", UI.COL_TEXT_DIM])
		var tag := PanelContainer.new()
		tag.custom_minimum_size = Vector2(76, 0)
		var sb := StyleBoxFlat.new()
		sb.bg_color = (tag_def[1] as Color).darkened(0.65)
		sb.border_color = tag_def[1]
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(3)
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		tag.add_theme_stylebox_override("panel", sb)
		tag.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		var tl := Label.new()
		tl.text = tag_def[0]
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tl.add_theme_font_size_override("font_size", 10)
		tl.add_theme_color_override("font_color", (tag_def[1] as Color).lightened(0.25))
		tag.add_child(tl)
		row.add_child(tag)
		var text := Label.new()
		text.text = str(e["text"])
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_theme_font_size_override("font_size", 12)
		text.add_theme_color_override("font_color", UI.COL_TEXT)
		row.add_child(text)
	return panel


## Minimal line chart for snapshot series (no external assets).
class Sparkline:
	extends Control
	var values: PackedFloat32Array = PackedFloat32Array()
	var color := Color.WHITE

	func _init(series: Array, col: Color) -> void:
		color = col
		custom_minimum_size = Vector2(220, 30)
		for s in series:
			values.append(float(s))

	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_rect(Rect2(0, 0, w, h), Color(1, 1, 1, 0.03))
		if values.size() < 2:
			draw_line(Vector2(2, h / 2.0), Vector2(w - 2, h / 2.0), color.darkened(0.4), 1.0)
			return
		var lo := values[0]
		var hi := values[0]
		for val in values:
			lo = minf(lo, val)
			hi = maxf(hi, val)
		var span := hi - lo
		var pts := PackedVector2Array()
		for i in values.size():
			var x := 2.0 + float(i) / float(values.size() - 1) * (w - 4.0)
			var y := h / 2.0
			if span > 0.0001:
				y = (h - 4.0) - (values[i] - lo) / span * (h - 8.0)
			pts.append(Vector2(x, y))
		draw_polyline(pts, color, 1.5, true)
		draw_circle(pts[pts.size() - 1], 2.5, color)
