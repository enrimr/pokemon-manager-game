extends Control
## Routes & Expeditions screen (routes piece) — FM-style scouting-trip centre
## for the wild routes of Kanto & Johto. Three tabs:
##   Route Map    — region-tabbed, data-dense route list with knowledge-masked
##                  species intel + the expedition planner panel.
##   Expeditions  — live tracker for parties in the field (day-by-day log).
##   History      — past expeditions + the club's capture record.
## All model logic lives in shared/sim/services/expeditions.gd.

const TB := preload("res://shared/theme/theme_builder.gd")
const Exped := preload("res://shared/sim/services/expeditions.gd")

const TIER_COL := {"common": Color("8b91a8"), "uncommon": Color("4dc3e6"),
	"rare": Color("b07be8"), "special": Color("e8c15a")}
const TERRAIN_ICON := {"grassland": "dot", "forest": "tri_up", "cave": "diamond",
	"water": "umbrella", "mountain": "tri_up", "wetland": "umbrella",
	"park": "flag", "urban": "menu", "coastal": "umbrella", "ice": "diamond_hollow"}

var _svc: RefCounted = null
var _tab := "map"
var _tab_btns := {}
var _tab_panes := {}
var _region := ""            # current region tab ("" = player's)
var _sel_route := ""         # selected route id
var _tree: Tree
var _region_btns := {}
var _planner: VBoxContainer
var _exp_box: VBoxContainer
var _hist_box: VBoxContainer
var _err: Label
# planner controls
var _dur_slider: HSlider
var _dur_lbl: Label
var _leader_opt: OptionButton
var _leader_ids: Array = []
var _approach := "balanced"
var _approach_btns := {}
var _att_spin: SpinBox
var _dest_opt: OptionButton
var _quote_lbl: Label
var _start_btn: Button


func _ready() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	root.add_child(_build_tab_bar())

	_tab_panes["map"] = _build_map_tab()
	_tab_panes["expeditions"] = _build_expeditions_tab()
	_tab_panes["history"] = _build_history_tab()
	for k in _tab_panes:
		root.add_child(_tab_panes[k])

	GameState.date_changed.connect(func(_d): _refresh())
	GameState.career_started.connect(_refresh)
	_select_tab("map")


func on_show() -> void:
	_refresh()


## Shell sub-navigation contract (screen.json "tabs" -> select_tab).
func select_tab(id: String) -> void:
	_select_tab(id)


func current_tab() -> String:
	return _tab


func _svc_ref() -> RefCounted:
	var s: RefCounted = Exped.active
	if s != null and s != _svc:
		_svc = s
		if not _svc.expeditions_changed.is_connected(_refresh):
			_svc.expeditions_changed.connect(_refresh)
	return _svc


func _select_tab(id: String) -> void:
	if not _tab_panes.has(id):
		id = "map"
	_tab = id
	for k in _tab_panes:
		(_tab_panes[k] as Control).visible = k == id
		if _tab_btns.has(k):
			(_tab_btns[k] as Button).button_pressed = k == id
	_refresh()


func _build_tab_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	for pair in [["map", "Route Map"], ["expeditions", "Expeditions"], ["history", "History"]]:
		var b := Button.new()
		b.text = tr(pair[1])
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_select_tab.bind(pair[0]))
		bar.add_child(b)
		_tab_btns[pair[0]] = b
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	var hint := Label.new()
	hint.text = tr("Send scouting parties into the wild — captures join the academy.")
	hint.add_theme_color_override("font_color", TB.COL_TEXT_DIM)
	hint.add_theme_font_size_override("font_size", 12)
	bar.add_child(hint)
	return bar


# ------------------------------------------------------------------ map tab

func _build_map_tab() -> Control:
	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 8)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.75
	left.add_theme_constant_override("separation", 6)
	main.add_child(left)

	var regions := HBoxContainer.new()
	regions.add_theme_constant_override("separation", 4)
	left.add_child(regions)
	for lg in [["kanto", "Kanto"], ["johto", "Johto"]]:
		var b := Button.new()
		b.text = tr(lg[1])
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_set_region.bind(lg[0]))
		regions.add_child(b)
		_region_btns[lg[0]] = b
	var klabel := Label.new()
	klabel.name = "KnowledgeHint"
	klabel.text = tr("Species intel unlocks with field days spent on a route.")
	klabel.add_theme_color_override("font_color", TB.COL_TEXT_DIM)
	klabel.add_theme_font_size_override("font_size", 12)
	regions.add_child(klabel)

	_tree = Tree.new()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.columns = 6
	_tree.column_titles_visible = true
	_tree.hide_root = true
	_tree.select_mode = Tree.SELECT_ROW
	var titles := ["Route", "Terrain", "Levels", "Species intel", "Travel", "Cost/day"]
	for i in titles.size():
		_tree.set_column_title(i, tr(titles[i]))
		_tree.set_column_title_alignment(i, HORIZONTAL_ALIGNMENT_LEFT)
	_tree.set_column_expand(0, true)
	_tree.set_column_custom_minimum_width(0, 150)
	_tree.set_column_expand(1, false)
	_tree.set_column_custom_minimum_width(1, 100)
	_tree.set_column_expand(2, false)
	_tree.set_column_custom_minimum_width(2, 70)
	_tree.set_column_expand(3, true)
	_tree.set_column_custom_minimum_width(3, 260)
	_tree.set_column_expand(4, false)
	_tree.set_column_custom_minimum_width(4, 70)
	_tree.set_column_expand(5, false)
	_tree.set_column_custom_minimum_width(5, 80)
	_tree.item_selected.connect(_on_route_selected)
	left.add_child(_tree)

	_planner = VBoxContainer.new()
	_planner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_planner.size_flags_stretch_ratio = 1.0
	_planner.add_theme_constant_override("separation", 6)
	main.add_child(_planner)
	return main


func _set_region(region: String) -> void:
	_region = region
	_sel_route = ""
	_refresh()


func _current_region() -> String:
	if _region != "":
		return _region
	return GameState.player_league_id()


func _species_names(ids: Array) -> String:
	var out: Array = []
	for sid in ids:
		out.append(str(DataStore.species(int(sid)).get("name", "?")))
	return ", ".join(out)


## Knowledge-masked intel string for the route list (FM scouting-knowledge
## ladder: unsurveyed -> commons -> +uncommons -> +rares & rumours).
func _intel_text(r: Dictionary, tier: int) -> String:
	var pool: Dictionary = r.get("pool", {})
	match tier:
		0:
			return tr("Unsurveyed — send a party to chart it")
		1:
			return _species_names(pool.get("common", [])) + tr("  · more to chart")
		2:
			return _species_names(pool.get("common", []) + pool.get("uncommon", [])) + tr("  · rare dens unchecked")
		_:
			var txt := _species_names(pool.get("common", []) + pool.get("uncommon", []) + pool.get("rare", []))
			if not (pool.get("special", []) as Array).is_empty():
				txt += tr("  · whispers of something exceptional")
			return txt


func _level_text(r: Dictionary, tier: int) -> String:
	if tier <= 0:
		return "?"
	var lo := int(r["levels"][0])
	var hi := int(r["levels"][1])
	if tier == 1:
		return tr("~%d-%d") % [maxi(1, lo - 2), hi + 2]
	return "%d-%d" % [lo, hi]


func _refresh_tree() -> void:
	var svc := _svc_ref()
	var region := _current_region()
	for k in _region_btns:
		(_region_btns[k] as Button).button_pressed = k == region
	_tree.clear()
	var root := _tree.create_item()
	for r in Exped.region_routes(region):
		var rid := str(r["id"])
		var tier: int = svc.knowledge_tier(rid) if svc != null else 0
		var it := _tree.create_item(root)
		it.set_metadata(0, rid)
		it.set_text(0, tr(str(r["name"])))
		var status_icon := ""
		var status_col := TB.COL_TEXT
		if svc != null:
			if not svc.expedition_on(rid).is_empty():
				status_icon = "flag"
				status_col = TB.COL_ACCENT
			elif svc.cooldown_until(rid) != "":
				status_icon = "pause"
				status_col = TB.COL_TEXT_DIM
		if status_icon != "":
			it.set_icon(0, GlyphIcons.tex(status_icon, 12, status_col))
		it.set_custom_color(0, status_col)
		var terrain: Array = r.get("terrain", [])
		it.set_icon(1, GlyphIcons.tex(str(TERRAIN_ICON.get(str(terrain[0]), "dot")), 11, TB.COL_TEXT_DIM))
		var tnames: Array = []
		for t in terrain:
			tnames.append(tr(str(t)))
		it.set_text(1, ", ".join(tnames))
		it.set_custom_color(1, TB.COL_TEXT_DIM)
		it.set_text(2, _level_text(r, tier))
		it.set_custom_color(2, TB.COL_TEXT_DIM if tier <= 0 else TB.COL_TEXT)
		it.set_text(3, _intel_text(r, tier))
		it.set_custom_color(3, TB.COL_TEXT_DIM if tier <= 0 else TB.COL_TEXT)
		var travel: int = int(r["travel"].get(GameState.player_league_id(), 2))
		it.set_text(4, I18n.np(travel, "%d day", "%d days"))
		it.set_custom_color(4, TB.COL_TEXT_DIM)
		it.set_text(5, AcademyService.format_money(int(r["cost_day"])))
		it.set_custom_color(5, TB.COL_TEXT_DIM)
		if _sel_route == rid:
			it.select(0)
	if _sel_route == "":
		var first := root.get_first_child()
		if first != null:
			first.select(0)
			_sel_route = str(first.get_metadata(0))


func _on_route_selected() -> void:
	var it := _tree.get_selected()
	if it != null:
		_sel_route = str(it.get_metadata(0))
		_refresh_planner()


# ------------------------------------------------------------------ planner

func _panel(title: String) -> Array:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = TB.COL_PANEL
	sb.border_color = TB.COL_BORDER
	sb.set_border_width_all(1)
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	if title != "":
		var lbl := Label.new()
		lbl.text = title
		lbl.add_theme_color_override("font_color", TB.COL_ACCENT)
		lbl.add_theme_font_size_override("font_size", 13)
		box.add_child(lbl)
	return [panel, box]


func _kv(box: VBoxContainer, key: String, value: String, val_col: Color = TB.COL_TEXT) -> void:
	var row := HBoxContainer.new()
	var k := Label.new()
	k.text = key
	k.custom_minimum_size.x = 120
	k.add_theme_color_override("font_color", TB.COL_TEXT_DIM)
	k.add_theme_font_size_override("font_size", 12)
	row.add_child(k)
	var v := Label.new()
	v.text = value
	v.add_theme_color_override("font_color", val_col)
	v.add_theme_font_size_override("font_size", 12)
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	box.add_child(row)


func _refresh_planner() -> void:
	for c in _planner.get_children():
		c.queue_free()
	var svc := _svc_ref()
	var r := Exped.route(_sel_route)
	if r.is_empty() or svc == null:
		return
	var tier: int = svc.knowledge_tier(_sel_route)

	# --- route dossier ---
	var doss := _panel(tr(str(r["name"])).to_upper())
	_planner.add_child(doss[0])
	var dbox: VBoxContainer = doss[1]
	var blurb := Label.new()
	blurb.text = tr(str(r.get("blurb", "")))
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.add_theme_color_override("font_color", TB.COL_TEXT_DIM)
	blurb.add_theme_font_size_override("font_size", 12)
	dbox.add_child(blurb)
	var know_names := [tr("Unsurveyed"), tr("Partial"), tr("Good"), tr("Full")]
	var kd: int = svc.knowledge_days(_sel_route)
	_kv(dbox, tr("Knowledge"), "%s (%s)" % [know_names[tier], I18n.np(kd, "%d field day", "%d field days")],
		TB.COL_GOOD if tier >= 2 else TB.COL_TEXT)
	_kv(dbox, tr("Level band"), _level_text(r, tier))
	_kv(dbox, tr("Species intel"), _intel_text(r, tier))
	var cd: String = svc.cooldown_until(_sel_route)
	if cd != "":
		_kv(dbox, tr("Status"), tr("Settling — reopens %s") % I18n.pretty_date(cd), TB.COL_WARN)
	elif not svc.expedition_on(_sel_route).is_empty():
		_kv(dbox, tr("Status"), tr("A party is on site now"), TB.COL_ACCENT)

	# --- planner ---
	var plan := _panel(tr("PLAN AN EXPEDITION"))
	_planner.add_child(plan[0])
	var pbox: VBoxContainer = plan[1]

	var durrow := HBoxContainer.new()
	var durkey := Label.new()
	durkey.text = tr("Field days")
	durkey.custom_minimum_size.x = 120
	durkey.add_theme_color_override("font_color", TB.COL_TEXT_DIM)
	durkey.add_theme_font_size_override("font_size", 12)
	durrow.add_child(durkey)
	_dur_slider = HSlider.new()
	_dur_slider.min_value = Exped.MIN_FIELD_DAYS
	_dur_slider.max_value = Exped.MAX_FIELD_DAYS
	_dur_slider.step = 1
	_dur_slider.value = 6
	_dur_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dur_slider.value_changed.connect(func(_v): _refresh_quote())
	durrow.add_child(_dur_slider)
	_dur_lbl = Label.new()
	_dur_lbl.custom_minimum_size.x = 30
	durrow.add_child(_dur_lbl)
	pbox.add_child(durrow)

	var lrow := HBoxContainer.new()
	var lkey := Label.new()
	lkey.text = tr("Leader")
	lkey.custom_minimum_size.x = 120
	lkey.add_theme_color_override("font_color", TB.COL_TEXT_DIM)
	lkey.add_theme_font_size_override("font_size", 12)
	lrow.add_child(lkey)
	_leader_opt = OptionButton.new()
	_leader_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_leader_ids.clear()
	var roles := {"scout": tr("Scout"), "coach": tr("Coach"), "manager": tr("Manager (you)")}
	for l in svc.leaders():
		var tag := tr(" — in the field") if bool(l["busy"]) else ""
		_leader_opt.add_item("%s · %s %d/20%s" % [str(l["name"]),
			str(roles.get(str(l["role"]), l["role"])), int(l["skill"]), tag])
		_leader_ids.append(str(l["id"]))
		if bool(l["busy"]):
			_leader_opt.set_item_disabled(_leader_opt.item_count - 1, true)
	for i in _leader_ids.size():
		if not _leader_opt.is_item_disabled(i):
			_leader_opt.select(i)
			break
	_leader_opt.item_selected.connect(func(_i): _refresh_quote())
	lrow.add_child(_leader_opt)
	pbox.add_child(lrow)

	var arow := HBoxContainer.new()
	var akey := Label.new()
	akey.text = tr("Approach")
	akey.custom_minimum_size.x = 120
	akey.add_theme_color_override("font_color", TB.COL_TEXT_DIM)
	akey.add_theme_font_size_override("font_size", 12)
	arow.add_child(akey)
	_approach_btns.clear()
	for ap in [["cautious", "Cautious"], ["balanced", "Balanced"], ["aggressive", "Aggressive"]]:
		var b := Button.new()
		b.text = tr(ap[1])
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.button_pressed = _approach == ap[0]
		b.pressed.connect(_set_approach.bind(ap[0]))
		arow.add_child(b)
		_approach_btns[ap[0]] = b
	pbox.add_child(arow)
	var ap_hint := Label.new()
	ap_hint.name = "ApproachHint"
	ap_hint.add_theme_color_override("font_color", TB.COL_TEXT_DIM)
	ap_hint.add_theme_font_size_override("font_size", 11)
	ap_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pbox.add_child(ap_hint)

	var trow := HBoxContainer.new()
	var tkey := Label.new()
	tkey.text = tr("Capture gear")
	tkey.custom_minimum_size.x = 120
	tkey.add_theme_color_override("font_color", TB.COL_TEXT_DIM)
	tkey.add_theme_font_size_override("font_size", 12)
	trow.add_child(tkey)
	_att_spin = SpinBox.new()
	_att_spin.min_value = 1
	_att_spin.max_value = 42
	_att_spin.value = 8
	_att_spin.value_changed.connect(func(_v): _refresh_quote())
	trow.add_child(_att_spin)
	var tnote := Label.new()
	tnote.text = tr("%s per attempt") % AcademyService.format_money(Exped.ATTEMPT_COST)
	tnote.add_theme_color_override("font_color", TB.COL_TEXT_DIM)
	tnote.add_theme_font_size_override("font_size", 11)
	trow.add_child(tnote)
	pbox.add_child(trow)

	var drow := HBoxContainer.new()
	var dkey := Label.new()
	dkey.text = tr("Captures go to")
	dkey.custom_minimum_size.x = 120
	dkey.add_theme_color_override("font_color", TB.COL_TEXT_DIM)
	dkey.add_theme_font_size_override("font_size", 12)
	drow.add_child(dkey)
	_dest_opt = OptionButton.new()
	_dest_opt.add_item(tr("Academy (develop them)"))
	_dest_opt.add_item(tr("First-team squad"))
	drow.add_child(_dest_opt)
	pbox.add_child(drow)

	_quote_lbl = Label.new()
	_quote_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quote_lbl.add_theme_font_size_override("font_size", 12)
	pbox.add_child(_quote_lbl)

	_start_btn = Button.new()
	_start_btn.text = tr("Launch expedition")
	_start_btn.icon = GlyphIcons.tex("flag", 13, Color.WHITE)
	_start_btn.pressed.connect(_launch)
	pbox.add_child(_start_btn)

	_err = Label.new()
	_err.add_theme_color_override("font_color", TB.COL_BAD)
	_err.add_theme_font_size_override("font_size", 12)
	_err.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pbox.add_child(_err)

	_refresh_quote()


const APPROACH_HINTS := {
	"cautious": "Fewer encounters, but attempts are safer and gear is saved for the good finds.",
	"balanced": "A steady sweep of the route — a fair mix of encounters and attempts.",
	"aggressive": "Maximum ground covered and every sighting contested — riskier attempts, and rough days happen.",
}


func _set_approach(ap: String) -> void:
	_approach = ap
	for k in _approach_btns:
		(_approach_btns[k] as Button).button_pressed = k == ap
	_refresh_quote()


func _refresh_quote() -> void:
	var svc := _svc_ref()
	if svc == null or _quote_lbl == null or not is_instance_valid(_quote_lbl):
		return
	var days := int(_dur_slider.value)
	_dur_lbl.text = str(days)
	_att_spin.max_value = days * 3
	var attempts := mini(int(_att_spin.value), days * 3)
	var hint := _planner.find_child("ApproachHint", true, false)
	if hint != null:
		(hint as Label).text = tr(APPROACH_HINTS[_approach])
	var r := Exped.route(_sel_route)
	if r.is_empty():
		return
	var cost: int = svc.cost_quote(_sel_route, days, attempts)
	var travel: int = svc.travel_days_to(r)
	var fin: Dictionary = GameState.player_club()["finances"]
	var spendable: int = mini(int(fin["balance"]), int(fin.get("transfer_budget", 0)))
	var ok := spendable >= cost
	_quote_lbl.text = tr("Total: %s  (%d days away incl. %d travel each way)\nTransfer budget available: %s") % [
		AcademyService.format_money(cost), days + travel * 2, travel,
		AcademyService.format_money(spendable)]
	_quote_lbl.add_theme_color_override("font_color", TB.COL_GOOD if ok else TB.COL_BAD)
	_start_btn.disabled = not ok


func _launch() -> void:
	var svc := _svc_ref()
	if svc == null:
		return
	var leader_id := "manager"
	if _leader_opt.selected >= 0 and _leader_opt.selected < _leader_ids.size():
		leader_id = str(_leader_ids[_leader_opt.selected])
	var dest := "academy" if _dest_opt.selected == 0 else "squad"
	var err: String = svc.plan(_sel_route, int(_dur_slider.value), leader_id,
		_approach, int(_att_spin.value), dest)
	if err != "":
		_err.text = err
		return
	_err.text = ""
	GameState.save_game()
	_select_tab("expeditions")


# ------------------------------------------------------------------ expeditions tab

func _build_expeditions_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_exp_box = VBoxContainer.new()
	_exp_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_exp_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_exp_box)
	return scroll


func _refresh_expeditions() -> void:
	for c in _exp_box.get_children():
		c.queue_free()
	var svc := _svc_ref()
	if svc == null:
		return
	if (svc.expeditions as Array).is_empty():
		var empty := Label.new()
		empty.text = tr("No parties in the field. Plan an expedition from the Route Map tab.")
		empty.add_theme_color_override("font_color", TB.COL_TEXT_DIM)
		_exp_box.add_child(empty)
	for exp in svc.expeditions:
		_exp_box.add_child(_expedition_card(exp))
	if not (svc.holding as Array).is_empty():
		var hold := _panel(tr("HOLDING PEN — WAITING FOR SPACE"))
		_exp_box.add_child(hold[0])
		for mon in svc.holding:
			var l := Label.new()
			l.text = tr("Lv %d %s (caught at %s) — will settle in as soon as a bed or squad slot opens.") % [
				int(mon["level"]), str(mon["species"]), tr(str(mon["caught_route"]))]
			l.add_theme_font_size_override("font_size", 12)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			(hold[1] as VBoxContainer).add_child(l)


func _phase_text(exp: Dictionary) -> String:
	match str(exp["phase"]):
		"travel_out":
			return tr("Travelling out (day %d of %d)") % [int(exp["days_in_phase"]) + 1, int(exp["travel_days"])]
		"travel_home":
			return tr("Travelling home (day %d of %d)") % [int(exp["days_in_phase"]) + 1, int(exp["travel_days"])]
	return tr("In the field — day %d of %d") % [int(exp["day_no"]), int(exp["field_days"])]


func _expedition_card(exp: Dictionary) -> Control:
	var card := _panel("")
	var box: VBoxContainer = card[1]
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(GlyphIcons.icon("flag", 16, TB.COL_ACCENT))
	var title := Label.new()
	title.text = "%s — %s" % [tr(str(exp["route_name"])), str(exp["leader"])]
	title.add_theme_font_size_override("font_size", 15)
	head.add_child(title)
	var phase := Label.new()
	phase.text = _phase_text(exp)
	phase.add_theme_color_override("font_color", TB.COL_ACCENT)
	phase.add_theme_font_size_override("font_size", 12)
	head.add_child(phase)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var stats := Label.new()
	stats.text = tr("Gear %d/%d · Captures %d · Sightings %d") % [
		int(exp["attempts_left"]), int(exp["attempts_bought"]),
		(exp["captures"] as Array).size(), int(exp["sightings"])]
	stats.add_theme_color_override("font_color", TB.COL_TEXT_DIM)
	stats.add_theme_font_size_override("font_size", 12)
	head.add_child(stats)
	box.add_child(head)

	var prog := ProgressBar.new()
	var total := int(exp["field_days"]) + 2 * int(exp["travel_days"])
	var done := 0
	match str(exp["phase"]):
		"travel_out":
			done = int(exp["days_in_phase"])
		"field":
			done = int(exp["travel_days"]) + int(exp["day_no"])
		"travel_home":
			done = int(exp["travel_days"]) + int(exp["field_days"]) + int(exp["days_in_phase"])
	prog.max_value = total
	prog.value = done
	prog.show_percentage = false
	prog.custom_minimum_size.y = 6
	box.add_child(prog)

	var log: Array = exp.get("log", [])
	var recent := log.slice(maxi(0, log.size() - 8))
	recent.reverse()
	for e in recent:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var kind := str(e.get("kind", ""))
		var icon := "dot"
		var col := TB.COL_TEXT_DIM
		var txt := ""
		match kind:
			"catch":
				icon = "check"
				col = TB.COL_GOOD
				txt = tr("Day %d — CAPTURED a Lv %d %s") % [int(e["day"]), int(e["level"]), str(e["species"])]
			"near":
				icon = "cross"
				col = TB.COL_WARN
				txt = tr("Day %d — a Lv %d %s got away") % [int(e["day"]), int(e["level"]), str(e["species"])]
			"sight":
				icon = "target"
				txt = tr("Day %d — sighted a Lv %d %s") % [int(e["day"]), int(e["level"]), str(e["species"])]
			"mishap":
				icon = "warning"
				col = TB.COL_BAD
				txt = tr("Day %d — a mishap cost the party the day") % int(e["day"])
			_:
				txt = str(e.get("note", ""))
		if str(e.get("tier", "")) == "special" and kind != "mishap":
			col = TIER_COL["special"]
		row.add_child(GlyphIcons.icon(icon, 11, col))
		var l := Label.new()
		l.text = txt
		l.add_theme_color_override("font_color", col)
		l.add_theme_font_size_override("font_size", 12)
		row.add_child(l)
		box.add_child(row)
	return card[0]


# ------------------------------------------------------------------ history tab

func _build_history_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hist_box = VBoxContainer.new()
	_hist_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hist_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_hist_box)
	return scroll


func _refresh_history() -> void:
	for c in _hist_box.get_children():
		c.queue_free()
	var svc := _svc_ref()
	if svc == null:
		return
	var hist: Array = svc.history
	# capture record summary
	var total_caught := 0
	var total_cost := 0
	var best := {}
	for h in hist:
		total_cost += int(h["cost"])
		for cp in h.get("captures", []):
			total_caught += 1
			if best.is_empty() or _tier_rank(str(cp["tier"])) > _tier_rank(str(best.get("tier", "common"))) \
					or (_tier_rank(str(cp["tier"])) == _tier_rank(str(best.get("tier", "common"))) and int(cp["level"]) > int(best.get("level", 0))):
				best = cp
	var sum := _panel(tr("CAPTURE RECORD"))
	_hist_box.add_child(sum[0])
	var sbox: VBoxContainer = sum[1]
	_kv(sbox, tr("Expeditions run"), str(hist.size()))
	_kv(sbox, tr("Pokémon captured"), str(total_caught), TB.COL_GOOD if total_caught > 0 else TB.COL_TEXT)
	_kv(sbox, tr("Total invested"), AcademyService.format_money(total_cost))
	if not best.is_empty():
		_kv(sbox, tr("Best find"), tr("Lv %d %s (%s)") % [int(best["level"]), str(best["species"]),
			tr(str(best["tier"]).capitalize())], TIER_COL.get(str(best["tier"]), TB.COL_TEXT))
	_kv(sbox, tr("Rival captures reported"), str(svc.ai_captures), TB.COL_TEXT_DIM)

	if hist.is_empty():
		var empty := Label.new()
		empty.text = tr("No expeditions completed yet — the wild routes are waiting.")
		empty.add_theme_color_override("font_color", TB.COL_TEXT_DIM)
		_hist_box.add_child(empty)
		return

	var tree := Tree.new()
	tree.custom_minimum_size.y = 320
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.columns = 7
	tree.column_titles_visible = true
	tree.hide_root = true
	var titles := ["Returned", "Route", "Leader", "Days", "Cost", "Sightings", "Captures"]
	for i in titles.size():
		tree.set_column_title(i, tr(titles[i]))
		tree.set_column_title_alignment(i, HORIZONTAL_ALIGNMENT_LEFT)
	tree.set_column_expand(0, false)
	tree.set_column_custom_minimum_width(0, 90)
	tree.set_column_expand(1, false)
	tree.set_column_custom_minimum_width(1, 140)
	tree.set_column_expand(2, false)
	tree.set_column_custom_minimum_width(2, 150)
	tree.set_column_expand(3, false)
	tree.set_column_custom_minimum_width(3, 50)
	tree.set_column_expand(4, false)
	tree.set_column_custom_minimum_width(4, 90)
	tree.set_column_expand(5, false)
	tree.set_column_custom_minimum_width(5, 70)
	tree.set_column_expand(6, true)
	tree.set_column_custom_minimum_width(6, 220)
	var root := tree.create_item()
	for h in hist:
		var it := tree.create_item(root)
		it.set_text(0, I18n.short_date(str(h["ended"])))
		it.set_custom_color(0, TB.COL_TEXT_DIM)
		it.set_text(1, tr(str(h["route_name"])))
		it.set_text(2, "%s (%s)" % [str(h["leader"]), tr(str(h["leader_role"]).capitalize())])
		it.set_custom_color(2, TB.COL_TEXT_DIM)
		it.set_text(3, str(int(h["field_days"])))
		it.set_custom_color(3, TB.COL_TEXT_DIM)
		it.set_text(4, AcademyService.format_money(int(h["cost"])))
		it.set_custom_color(4, TB.COL_TEXT_DIM)
		it.set_text(5, str(int(h["sightings"])))
		it.set_custom_color(5, TB.COL_TEXT_DIM)
		var caps: Array = h.get("captures", [])
		if caps.is_empty():
			it.set_text(6, tr("none"))
			it.set_custom_color(6, TB.COL_TEXT_DIM)
		else:
			var parts: Array = []
			var best_tier := "common"
			for cp in caps:
				parts.append(tr("%s Lv %d") % [str(cp["species"]), int(cp["level"])])
				if _tier_rank(str(cp["tier"])) > _tier_rank(best_tier):
					best_tier = str(cp["tier"])
			it.set_text(6, ", ".join(parts))
			it.set_custom_color(6, TIER_COL.get(best_tier, TB.COL_GOOD))
			it.set_icon(6, GlyphIcons.tex("check", 11, TB.COL_GOOD))
	_hist_box.add_child(tree)


func _tier_rank(t: String) -> int:
	return {"common": 0, "uncommon": 1, "rare": 2, "special": 3}.get(t, 0)


# ------------------------------------------------------------------ refresh

func _refresh() -> void:
	if not is_inside_tree():
		return
	match _tab:
		"map":
			_refresh_tree()
			_refresh_planner()
		"expeditions":
			_refresh_expeditions()
		"history":
			_refresh_history()
