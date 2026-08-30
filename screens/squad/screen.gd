extends Control
const EvoSvc := preload("res://shared/sim/services/evolution.gd")
## Squad screen — FM24-style squad table + full Pokémon profile.
## Owned by the "squad" piece. All data live from GameState / DataStore.

const UI := preload("res://screens/squad/ui_helpers.gd")
const SeasonStats := preload("res://screens/squad/season_stats.gd")
const ProfileView := preload("res://screens/squad/profile.gd")
const Actions := preload("res://screens/squad/actions_ui.gd")
const Service := preload("res://screens/squad/squad_service.gd")
const History := preload("res://screens/squad/career_history.gd")
const Ability := preload("res://screens/squad/ability.gd")
const Selection := preload("res://screens/squad/selection.gd")
const Personality := preload("res://screens/squad/personality.gd")
const Views := preload("res://screens/squad/views.gd")
const ViewEditor := preload("res://screens/squad/view_editor.gd")

const VERDICT_RANK := {"Key battler": 5, "First team": 4, "Develop": 3,
	"Squad depth": 2, "Aging": 1, "Surplus": 0}
const TIER_RANK := {"star": 5, "important": 4, "prospect": 3, "rotation": 2, "backup": 1}

var _records: Array = []          # one dict per squad instance, precomputed
var _sel: Dictionary = {}         # matchday selection snapshot (Selection.selection())
var _pctx: Dictionary = {}        # personality/happiness context (Personality.context())
var _view: String = "General"
var _sort_key: String = "pick"
var _sort_desc := false
var _filter := ""
var _selected_uid := ""

var _table_view: VBoxContainer
var _tree: Tree
var _header_info: Label
var _chips_box: HFlowContainer
var _views_bar: HFlowContainer
var _view_buttons: Dictionary = {}
var _active_cols: Array = []
var _footer: PanelContainer
var _footer_stats: HFlowContainer
var _footer_actions: HBoxContainer
var _profile_btn: Button
var _bids_btn: Button
var _profile: ProfileView
var _svc: Node


var _hist: Node


func _ready() -> void:
	_svc = Service.ensure()
	_hist = History.ensure()
	_view = Views.active()
	if not Views.columns(_view).has(_sort_key):
		_sort_key = "lv"
		_sort_desc = true
	_build_layout()
	_refresh()
	if not GameState.date_changed.is_connected(_on_date_changed):
		GameState.date_changed.connect(_on_date_changed)
	_svc.actions_changed.connect(_on_actions_changed)


func _on_actions_changed() -> void:
	if is_inside_tree():
		_refresh()


func on_show() -> void:
	# Temporary dev hooks for screenshot verification (env-gated, no effect in normal play).
	var adv := OS.get_environment("SQUAD_DEV_ADVANCE")
	if adv != "":
		for i in int(adv):
			GameState.advance_day()
		GameState.save_game()
	_refresh()
	if OS.get_environment("SQUAD_DEV_MAKEVIEW") != "":
		# Build a demo custom view through the real Views API, then show it.
		var vname := OS.get_environment("SQUAD_DEV_MAKEVIEW")
		if not Views.has_view(vname):
			# Deliberately wide (24 cols) to exercise responsive widths + h-scroll.
			Views.create(vname, ["pick", "name", "avail", "type", "lv", "age", "cur",
				"pot", "rec", "cond", "fit", "morale", "happy", "item", "apps", "wins",
				"kos", "dmg", "rat", "salary", "expiry", "demand", "value", "status"])
		_rebuild_views_bar()
		_on_preset(vname)
	var dev_view := OS.get_environment("SQUAD_DEV_VIEW")
	if dev_view != "" and Views.has_view(dev_view):
		_on_preset(dev_view)
		var root := _tree.get_root()
		if root != null and root.get_child_count() > 0:
			root.get_child(0).select(0)
			_on_row_selected()
	if OS.get_environment("SQUAD_DEV_LIST") != "" and _records.size() > 2 \
			and not _svc.is_listed(_records[2]["inst"]):
		_svc.set_listed(_records[2]["uid"], UI.est_value(_records[2]["inst"]))
	if OS.get_environment("SQUAD_DEV_PROMISE") != "" and not _records.is_empty() \
			and _svc.open_promise(_records[0]["uid"]).is_empty():
		_svc.make_promise(_records[0]["uid"], "battles")
	if OS.get_environment("SQUAD_DEV_PROFILE") != "" and not _records.is_empty():
		var prof_i := clampi(int(OS.get_environment("SQUAD_DEV_PROFILE")), 0, _records.size() - 1)
		_open_profile(_records[prof_i]["uid"])
		if OS.get_environment("SQUAD_DEV_TAB") != "":
			_profile._tab = OS.get_environment("SQUAD_DEV_TAB")
			_profile.refresh()
		if OS.get_environment("SQUAD_DEV_COMPARE") != "" and _records.size() > 1:
			_profile._compare_uid = _records[1]["uid"]
			_profile.refresh()
	if OS.get_environment("SQUAD_DEV_MENU") != "" and not _records.is_empty():
		Actions.open_menu(self, _records[0]["uid"], Vector2(560, 260),
			func(uid: String) -> void: _open_profile(uid))
	if OS.get_environment("SQUAD_DEV_CONTRACT") != "" and not _records.is_empty():
		Actions.open_contract_dialog(self, _records[0]["uid"])
	if OS.get_environment("SQUAD_DEV_BIDS") != "":
		Actions.open_offers_dialog(self)
	if OS.get_environment("SQUAD_DEV_VIEWEDITOR") != "":
		_open_view_editor()
	if OS.get_environment("SQUAD_DEV_EDITDRIVE") != "":
		# Drive the REAL editor UI: select Spe in the available list, press
		# Add, press Save & Apply — the live table must gain the column and
		# the General button must carry the modified marker.
		_on_preset("General")
		var dlg := _open_view_editor()
		await get_tree().process_frame
		var ils := dlg.find_children("", "ItemList", true, false)
		var avail_il: ItemList = ils[0]
		for i in avail_il.item_count:
			if str(avail_il.get_item_metadata(i)) == "spe":
				avail_il.select(i)
		for b in dlg.find_children("", "Button", true, false):
			if (b as Button).text == "Add  >":
				(b as Button).pressed.emit()
		dlg.get_ok_button().pressed.emit()
	if OS.get_environment("SQUAD_DEV_SCROLLX") != "":
		# Prove the rightmost columns are reachable: scroll fully right.
		for i in 4:
			await get_tree().process_frame
		for c in _tree.get_children(true):
			if c is HScrollBar:
				(c as HScrollBar).value = (c as HScrollBar).max_value


func _on_date_changed(_d: String) -> void:
	if visible and is_inside_tree():
		_refresh()


# ------------------------------------------------------------------ layout

func _build_layout() -> void:
	_table_view = VBoxContainer.new()
	_table_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_table_view.add_theme_constant_override("separation", 8)
	add_child(_table_view)

	# --- header
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	_table_view.add_child(head)
	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 0)
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_box)
	var title := Label.new()
	title.text = "Squad"
	title.add_theme_font_size_override("font_size", 25)
	title.add_theme_color_override("font_color", Color.WHITE)
	title_box.add_child(title)
	_header_info = Label.new()
	_header_info.add_theme_font_size_override("font_size", 13)
	_header_info.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	_header_info.clip_text = true
	_header_info.mouse_filter = Control.MOUSE_FILTER_STOP
	title_box.add_child(_header_info)
	# Chips flow (and wrap) instead of clipping: at 1600x900 the rightmost
	# chip (BALANCE) must stay on screen whatever the wage/mood strings do.
	_chips_box = HFlowContainer.new()
	_chips_box.add_theme_constant_override("h_separation", 8)
	_chips_box.add_theme_constant_override("v_separation", 4)
	_chips_box.alignment = FlowContainer.ALIGNMENT_END
	_chips_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chips_box.size_flags_stretch_ratio = 1.6
	head.add_child(_chips_box)

	# --- views row (presets + custom views + editor; wraps, never clips)
	_views_bar = HFlowContainer.new()
	_views_bar.add_theme_constant_override("h_separation", 6)
	_views_bar.add_theme_constant_override("v_separation", 4)
	_table_view.add_child(_views_bar)
	_rebuild_views_bar()

	# --- toolbar
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	_table_view.add_child(bar)
	var search := LineEdit.new()
	search.placeholder_text = "Filter name / species / type..."
	search.custom_minimum_size = Vector2(240, 0)
	search.text_changed.connect(func(t: String) -> void:
		_filter = t.strip_edges().to_lower()
		_rebuild_table())
	bar.add_child(search)
	_bids_btn = Button.new()
	_bids_btn.visible = false
	_bids_btn.add_theme_color_override("font_color", UI.COL_WARN)
	_bids_btn.tooltip_text = "Respond to incoming transfer bids"
	_bids_btn.pressed.connect(func() -> void: Actions.open_offers_dialog(self))
	bar.add_child(_bids_btn)
	var sp3 := Control.new()
	sp3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(sp3)
	var hint := Label.new()
	hint.text = "Sort: click a column · profile: double-click · actions: right-click"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	hint.clip_text = true
	hint.tooltip_text = hint.text
	bar.add_child(hint)

	# --- table
	_tree = Tree.new()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.hide_root = true
	_tree.select_mode = Tree.SELECT_ROW
	_tree.column_titles_visible = true
	_tree.allow_reselect = true
	# Never lose columns to the viewport: widths scale down responsively first
	# (_apply_column_widths) and horizontal scrolling picks up beyond that.
	_tree.scroll_horizontal_enabled = true
	_tree.resized.connect(_apply_column_widths)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(UI.COL_ACCENT, 0.10)
	_tree.add_theme_stylebox_override("hovered", hover)
	_tree.add_theme_constant_override("draw_guides", 1)
	_tree.column_title_clicked.connect(_on_column_clicked)
	_tree.item_activated.connect(_open_selected_profile)
	_tree.item_selected.connect(_on_row_selected)
	_tree.allow_rmb_select = true
	_tree.item_mouse_selected.connect(_on_item_mouse_selected)
	_table_view.add_child(_tree)

	# --- footer selection strip. Stats live in a flow that WRAPS when the
	# strip is dense (a wide footer must never inflate the layout's minimum
	# width and push table columns / header chips off a 1600x900 screen);
	# action buttons stay pinned on the right.
	_footer = PanelContainer.new()
	_footer.custom_minimum_size = Vector2(0, 64)
	var footer_row := HBoxContainer.new()
	footer_row.add_theme_constant_override("separation", 12)
	_footer.add_child(footer_row)
	_footer_stats = HFlowContainer.new()
	_footer_stats.add_theme_constant_override("h_separation", 16)
	_footer_stats.add_theme_constant_override("v_separation", 4)
	_footer_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_row.add_child(_footer_stats)
	_footer_actions = HBoxContainer.new()
	_footer_actions.add_theme_constant_override("separation", 6)
	_footer_actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	footer_row.add_child(_footer_actions)
	_table_view.add_child(_footer)

	# --- profile (hidden until opened)
	_profile = ProfileView.new()
	_profile.set_anchors_preset(Control.PRESET_FULL_RECT)
	_profile.visible = false
	_profile.back_requested.connect(_close_profile)
	add_child(_profile)


# ------------------------------------------------------------------ data

func _refresh() -> void:
	var club: Dictionary = GameState.player_club()
	if club.is_empty():
		return
	SeasonStats.player_stats()
	_hist.sync()
	var wage_bill := 0
	for inst in club["squad"]:
		wage_bill += int(inst["contract"]["salary"])
	_sel = Selection.selection()
	_pctx = Personality.context(_svc)
	_records.clear()
	for inst in club["squad"]:
		_records.append(_make_record(inst, wage_bill))
	_update_header(club, wage_bill)
	var bids: Array = _svc.active_offers()
	_bids_btn.visible = not bids.is_empty()
	if not bids.is_empty():
		_bids_btn.text = "%d transfer bid%s awaiting response" % [bids.size(),
			"s" if bids.size() > 1 else ""]
	_rebuild_table()
	if _profile.visible:
		_profile.refresh()


func _make_record(inst: Dictionary, wage_bill: int) -> Dictionary:
	var sp: Dictionary = DataStore.species(int(inst["species_id"]))
	var stats := UI.effective_stats(inst)
	var tot := 0
	for k in stats:
		tot += int(stats[k])
	var uid: String = inst["uid"]
	var apps := SeasonStats.stat_of(uid, "battles")
	var salary := int(inst["contract"]["salary"])
	var expiry: String = inst["contract"]["expiry"]
	var rep: Dictionary = Ability.report(inst)
	var pick: Dictionary = Selection.pick_info(uid, _sel)
	var flags: Array = Selection.flags(inst)
	var item_id := str(inst.get("held_item")) if inst.get("held_item") else ""
	var item: Dictionary = DataStore.item(item_id) if item_id != "" else {}
	var happy: Dictionary = Personality.happiness(inst, _svc, _pctx)
	var promise: Dictionary = _svc.open_promise(uid)
	if promise.is_empty():
		promise = _svc.recent_promise(uid, "broken", 45)
	if promise.is_empty():
		promise = _svc.recent_promise(uid, "kept", 30)
	# live evolution state (pending approval / stone route ready)
	var evo_pending := false
	var evo_ready := false
	var evo_to := ""
	var evo_svc: RefCounted = EvoSvc.instance
	if evo_svc != null:
		var pend: Dictionary = evo_svc.pending_for(uid)
		if not pend.is_empty():
			evo_pending = true
			evo_to = str(pend["to_name"])
		elif not evo_svc.chain_of(int(inst["species_id"])).is_empty():
			for o in evo_svc.eligibility(inst):
				if o["ok"]:
					evo_ready = true
					evo_to = str(o["to_name"])
					break
	return {
		"evo_pending": evo_pending, "evo_ready": evo_ready, "evo_to": evo_to,
		"happy": happy, "happy_score": int(happy["score"]),
		"pers": str((happy["arch"] as Dictionary)["name"]),
		"sstat": happy["status"], "concern": str(happy["top_concern"]),
		"promise": promise,
		"pick": pick, "pick_rank": int(pick["rank"]),
		"flags": flags, "role": str(pick["role"]),
		"item_id": item_id, "item": item, "item_name": str(item.get("name", "")),
		"babil": UI.ability_label(inst), "babil_tip": UI.ability_tip(inst),
		"nature": UI.nature_text(inst), "nature_tip": UI.nature_tip(inst),
		"nature_name": UI.nature_name(inst),
		"cur": float(rep["now"]), "pot": float(rep["pot"]),
		"rec": str(rep["verdict"]), "report": rep,
		"inst": inst, "uid": uid,
		"name": UI.display_name(inst), "species": inst["species"],
		"types": sp["types"], "lv": int(inst["level"]),
		"age": int(inst["age_months"]),
		"cond": int(inst["condition"]), "fit": int(inst["fitness"]),
		"morale": int(inst["morale"]),
		"hp": int(stats["hp"]), "atk": int(stats["atk"]), "def": int(stats["def"]),
		"spa": int(stats["spa"]), "spd": int(stats["spd"]), "spe": int(stats["spe"]),
		"tot": tot,
		"dev": _hist.dev_gain(uid, inst),
		"apps": apps, "wins": SeasonStats.stat_of(uid, "wins"),
		"kos": SeasonStats.stat_of(uid, "kos"), "dmg": SeasonStats.stat_of(uid, "dmg"),
		"taken": SeasonStats.stat_of(uid, "taken"), "faints": SeasonStats.stat_of(uid, "faints"),
		"rat": SeasonStats.avg_rating(uid),
		"salary": salary, "expiry": expiry,
		"days_left": UI.days_between(GameState.current_date, expiry),
		"wage_pct": (float(salary) / float(wage_bill) * 100.0) if wage_bill > 0 else 0.0,
		"value": UI.est_value(inst),
		"listed": _svc.is_listed(inst),
		"ask": int(inst.get("asking_price", 0)),
		"bids": _svc.offers_for(uid).size(),
		"demand": int(_svc.contract_demand(inst)["wage"]),
		"talks_locked": _svc.talks_locked(uid),
	}


func _update_header(club: Dictionary, wage_bill: int) -> void:
	var squad: Array = club["squad"]
	var pos := GameState.player_table_position()
	var suffix := "th"
	if pos % 10 == 1 and pos % 100 != 11: suffix = "st"
	elif pos % 10 == 2 and pos % 100 != 12: suffix = "nd"
	elif pos % 10 == 3 and pos % 100 != 13: suffix = "rd"
	var pos_txt := "%d%s" % [pos, suffix]
	for r in GameState.league_table():
		if GameState.is_player_club(r["club_id"]) and int(r.get("played", 0)) == 0:
			pos_txt = "—"   # pre-season: a table position would be alphabetical noise
	_header_info.text = "%s · %s · %s in the %s · %s · Tactic: %s%s" % [
		club["name"], Season.pretty_date(GameState.current_date), pos_txt,
		GameState.world["meta"]["league_name"], "Manager: %s" % club["manager"],
		_sel.get("name", "-"), "" if _sel.get("source", "") == "tactic" else " (auto)"]
	_header_info.tooltip_text = _header_info.text
	for c in _chips_box.get_children():
		c.queue_free()
	var lv_sum := 0
	var cond_sum := 0
	for inst in squad:
		lv_sum += int(inst["level"])
		cond_sum += int(inst["condition"])
	var n := maxi(squad.size(), 1)
	_chips_box.add_child(_chip("POKEMON", str(squad.size()), UI.COL_TEXT))
	var picked_fit := 0
	var avail_all := 0
	for rec in _records:
		var red := false
		for fl in rec["flags"]:
			if int(fl["sev"]) >= 2:
				red = true
		if not red:
			avail_all += 1
			if rec["pick"]["kind"] == "starter":
				picked_fit += 1
	var picked_n: int = (_sel.get("slot", {}) as Dictionary).size()
	var six_chip := _chip("PICKED SIX", "%d/%d fit" % [picked_fit, maxi(picked_n, 1)],
		UI.COL_GOOD if picked_fit >= picked_n else UI.COL_WARN)
	six_chip.tooltip_text = ("Starters of the saved tactic '%s' clear of serious availability doubts (%d of the %d-strong squad fully available)." %
		[_sel.get("name", "-"), avail_all, squad.size()]) if _sel.get("source", "") == "tactic" \
		else "No tactic saved yet: the six are auto-picked by level and condition. Set a lineup on the Tactics screen."
	_chips_box.add_child(six_chip)
	_chips_box.add_child(_chip("AVG LEVEL", "%.1f" % (float(lv_sum) / n), UI.COL_TEXT))
	_chips_box.add_child(_chip("AVG COND", "%d%%" % int(float(cond_sum) / n),
		UI.pct_color(int(float(cond_sum) / n))))
	var happy_sum := 0
	var unhappy: Array = []
	for rec in _records:
		happy_sum += int(rec["happy_score"])
		if int(rec["happy_score"]) < 38:
			unhappy.append("%s — %s" % [rec["name"], rec["concern"] if rec["concern"] != "" else "unhappy"])
	var mood_avg := int(float(happy_sum) / n)
	var mood_chip := _chip("MOOD",
		Personality.happiness_word(mood_avg) + ((" · %d unhappy" % unhappy.size()) if not unhappy.is_empty() else ""),
		Personality.happiness_color(mood_avg) if unhappy.is_empty() else UI.COL_WARN)
	mood_chip.tooltip_text = ("Average squad happiness %d/100. Concerns needing attention:\n%s" %
		[mood_avg, "\n".join(PackedStringArray(unhappy))]) if not unhappy.is_empty() else \
		"Average squad happiness %d/100 — no one is agitating. The Happiness view shows every factor." % mood_avg
	_chips_box.add_child(mood_chip)
	var evo_svc: RefCounted = EvoSvc.instance
	if evo_svc != null and not evo_svc.pending().is_empty():
		var pend: Array = evo_svc.pending()
		var evo_chip := _chip("EVOLUTION", "%d awaiting approval" % pend.size(), UI.COL_GOOD)
		evo_chip.tooltip_text = "Manager approval needed — decide from the profile or the inbox:\n" + \
			"\n".join(PackedStringArray(pend.map(func(e): return "%s -> %s" % [e["name"], e["to_name"]])))
		_chips_box.add_child(evo_chip)
	var nf: Dictionary = GameState.next_player_fixture()
	if not nf.is_empty():
		var we_home: bool = GameState.is_player_club(str(nf["home"]))
		var opp_id: String = str(nf["away"] if we_home else nf["home"])
		var opp: Dictionary = GameState.club(opp_id)
		var is_cup: bool = str(nf.get("league", "")) == ""
		var comp: String = GameState.cup_name() if is_cup else GameState.league_name(str(nf["league"]))
		var cross: bool = is_cup and GameState.league_of(opp_id) != GameState.player_league_id()
		var next_chip := _chip("NEXT", "%s %s (%s)" % ["vs" if we_home else "@", str(opp["short"]),
			("CUP·" + GameState.league_name(GameState.league_of(opp_id)).trim_suffix(" League")) if cross else comp.trim_suffix(" League")],
			UI.COL_ACCENT if cross else UI.COL_TEXT)
		next_chip.tooltip_text = "%s — %s %s, %s.%s" % [comp, "home to" if we_home else "away at", str(opp["name"]),
			Season.pretty_date(str(nf["date"])),
			("\nCross-league cup tie: they play in the %s — check their squad on the Transfers search." % GameState.league_name(GameState.league_of(opp_id))) if cross
			else ("\nCup ties are best-of-3 and game 2 is 2v2 doubles — set your pair on Tactics." if is_cup else "")]
		_chips_box.add_child(next_chip)
	var wages_chip := _chip("WAGES /WK", "%s of %s" % [UI.money(wage_bill),
		UI.money(int(club["finances"]["wage_budget"]))],
		UI.COL_WARN if wage_bill > int(club["finances"]["wage_budget"]) else UI.COL_TEXT)
	wages_chip.tooltip_text = "Weekly wage bill against the wage budget."
	_chips_box.add_child(wages_chip)
	_chips_box.add_child(_chip("T. BUDGET", UI.money(maxi(0, int(club["finances"].get("transfer_budget", 0)))), UI.COL_GOOD))
	_chips_box.add_child(_chip("BALANCE", UI.money(int(club["finances"]["balance"])), UI.COL_TEXT_DIM))


func _chip(label: String, value: String, col: Color) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UI.COL_PANEL
	sb.border_color = UI.COL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	p.add_child(v)
	var l1 := Label.new()
	l1.text = label
	l1.add_theme_font_size_override("font_size", 10)
	l1.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	v.add_child(l1)
	var l2 := Label.new()
	l2.text = value
	l2.add_theme_font_size_override("font_size", 14)
	l2.add_theme_color_override("font_color", col)
	v.add_child(l2)
	return p


# ------------------------------------------------------------------ columns

func _col_def(id: String) -> Dictionary:
	return Views.col_def(id)


func _cell_text(rec: Dictionary, id: String) -> String:
	match id:
		"pick": return (rec["pick"] as Dictionary)["text"]
		"avail": return Selection.flags_text(rec["flags"])
		"item": return rec["item_name"] if rec["item_name"] != "" else "-"
		"babil": return rec["babil"]
		"role": return rec["role"] if rec["role"] != "" else "-"
		"cur", "pot": return ""  # star icon cells
		"rec": return rec["rec"]
		"type": return "/".join(rec["types"].map(func(t): return UI.type_abbr(t)))
		"age": return UI.age_str(rec["age"])
		"cond": return "%d%%" % rec["cond"]
		"fit": return "%d%%" % rec["fit"]
		"morale": return UI.morale_word(rec["morale"])
		"happy": return str((rec["happy"] as Dictionary)["word"])
		"sstat": return str((rec["sstat"] as Dictionary)["label"])
		"concern": return rec["concern"] if rec["concern"] != "" else "-"
		"promise": return _promise_cell(rec["promise"])
		"rat": return "%.2f" % rec["rat"] if rec["apps"] > 0 else "-"
		"salary": return UI.money(rec["salary"]) + "/wk"
		"wage_pct": return "%.1f%%" % rec["wage_pct"]
		"expiry": return Season.pretty_date(rec["expiry"])
		"value": return UI.money(rec["value"])
		"demand": return "~%s/wk" % UI.money(rec["demand"])
		"status": return _status_text(rec)
		"dev": return ("+%d" % rec["dev"]) if rec["dev"] > 0 else "-"
		"dmg", "taken": return str(rec[id]) if rec["apps"] > 0 else "-"
		"apps", "wins", "kos", "faints": return str(rec[id]) if rec["apps"] > 0 else "-"
	return str(rec[id])


func _cell_color(rec: Dictionary, id: String) -> Color:
	match id:
		"pick": return (rec["pick"] as Dictionary)["color"]
		"avail": return Selection.worst_color(rec["flags"])
		"item": return UI.rarity_color(str((rec["item"] as Dictionary).get("rarity", ""))) \
			if rec["item_name"] != "" else UI.COL_TEXT_DIM
		"babil": return UI.COL_ACCENT.lightened(0.25) \
			if not UI.ability_immunities(UI.ability_id(rec["inst"])).is_empty() else UI.COL_TEXT
		"nature": return UI.COL_TEXT_DIM if rec["nature"].ends_with("(neutral)") else UI.COL_TEXT
		"role": return UI.COL_TEXT if rec["role"] != "" else UI.COL_TEXT_DIM
		"rec": return (rec["report"] as Dictionary)["verdict_color"]
		"name": return Color.WHITE
		"species": return UI.COL_TEXT_DIM
		"type": return DataStore.type_color(rec["types"][0]).lightened(0.2)
		"cond": return UI.pct_color(rec["cond"])
		"fit": return UI.pct_color(rec["fit"])
		"morale": return UI.pct_color(rec["morale"])
		"happy": return (rec["happy"] as Dictionary)["color"]
		"pers": return UI.COL_TEXT
		"sstat": return (rec["sstat"] as Dictionary)["color"]
		"concern": return UI.COL_WARN if rec["concern"] != "" else UI.COL_TEXT_DIM
		"promise": return _promise_color(rec["promise"])
		"rat": return UI.rating_color(rec["rat"]) if rec["apps"] > 0 else UI.COL_TEXT_DIM
		"expiry", "days_left":
			if rec["days_left"] < 90: return UI.COL_BAD
			if rec["days_left"] < 240: return UI.COL_WARN
			return UI.COL_TEXT
		"salary", "value", "wage_pct": return UI.COL_TEXT
		"dev": return UI.COL_GOOD if rec["dev"] > 0 else UI.COL_TEXT_DIM
		"demand": return UI.COL_WARN if rec["demand"] > rec["salary"] * 2 else UI.COL_TEXT_DIM
		"status":
			if rec["evo_pending"] or rec["evo_ready"]: return UI.COL_GOOD
			if rec["bids"] > 0: return UI.COL_WARN
			if rec["listed"]: return UI.COL_BAD
			return UI.COL_TEXT_DIM
		"hp", "atk", "def", "spa", "spd", "spe":
			return UI.attr_color(UI.base_to_20(int(DataStore.species(
				int(rec["inst"]["species_id"]))["base"][id])))
	return UI.COL_TEXT


func _status_text(rec: Dictionary) -> String:
	var parts: Array = []
	if rec["evo_pending"]:
		parts.append("Evolve? -> %s" % rec["evo_to"])
	elif rec["evo_ready"]:
		parts.append("Stone ready")
	if rec["bids"] > 0:
		parts.append("%d bid%s" % [rec["bids"], "s" if rec["bids"] > 1 else ""])
	if rec["listed"]:
		parts.append("Listed")
	if rec["talks_locked"]:
		parts.append("Talks off")
	return " · ".join(PackedStringArray(parts)) if not parts.is_empty() else "-"


func _status_tip(rec: Dictionary) -> String:
	var lines: Array = []
	if rec["evo_pending"]:
		lines.append("Ready to evolve into %s — approve or postpone from the profile or the inbox decision message." % rec["evo_to"])
	elif rec["evo_ready"]:
		lines.append("An evolution stone in the storeroom would evolve it into %s — apply it from the profile or the Items screen." % rec["evo_to"])
	if rec["bids"] > 0:
		lines.append("%d active transfer bid%s awaiting your response (respond from the footer or right-click)." %
			[rec["bids"], "s" if rec["bids"] > 1 else ""])
	if rec["listed"]:
		lines.append("Transfer listed at %s." % UI.money(rec["ask"]))
	if rec["talks_locked"]:
		lines.append("Contract talks broke down — locked until %s." %
			Season.pretty_date(_svc.talks_locked_until(rec["uid"])))
	return "\n".join(PackedStringArray(lines)) if not lines.is_empty() \
		else "No live transfer/contract state: no bids, not listed, talks open."


const PROMISE_SHORT := {"battles": "Battles", "new_deal": "New deal", "unlist": "Unlist"}


func _promise_cell(p: Dictionary) -> String:
	if p.is_empty():
		return "-"
	var kind := str(PROMISE_SHORT.get(str(p["kind"]), "Promise"))
	match str(p["status"]):
		"open": return "%s · %s" % [kind,
			" ".join(Season.pretty_date(str(p["deadline"])).split(" ").slice(0, 2))]
		"kept": return "Kept · %s" % kind
		"broken": return "BROKEN · %s" % kind
	return "-"


func _promise_color(p: Dictionary) -> Color:
	if p.is_empty():
		return UI.COL_TEXT_DIM
	match str(p["status"]):
		"open": return UI.COL_ACCENT.lightened(0.25)
		"kept": return UI.COL_GOOD
		"broken": return UI.COL_BAD
	return UI.COL_TEXT_DIM


func _promise_tip(p: Dictionary) -> String:
	if p.is_empty():
		return "No promise outstanding. Make one from the right-click menu — promises are tracked with deadlines and real consequences."
	match str(p["status"]):
		"open": return "Your word, given %s: %s Deadline %s — break it and morale, trust and future contract talks all pay." % \
			[Season.pretty_date(str(p["made_on"])), str(p["text"]), Season.pretty_date(str(p["deadline"]))]
		"kept": return "Promise kept on %s: %s Trust has deepened." % \
			[Season.pretty_date(str(p["resolved_on"])), str(p["text"])]
		"broken": return "Promise BROKEN on %s: %s The distrust lingers for weeks and poisons contract talks." % \
			[Season.pretty_date(str(p["resolved_on"])), str(p["text"])]
	return ""


## Morale tooltip: the mood ledger — every recent change with its reason.
func _morale_tip(rec: Dictionary) -> String:
	var lines: Array = ["Morale %s (%d) — day-to-day mood." % [UI.morale_word(rec["morale"]), rec["morale"]]]
	var log: Array = _svc.mood_log(rec["uid"])
	if log.is_empty():
		lines.append("No recorded morale events yet.")
	else:
		lines.append("Recent morale events:")
		for e in log.slice(0, 7):
			lines.append("  %s  %+d  %s" % [Season.pretty_date(str(e["d"])), int(e["delta"]), str(e["why"])])
	var h: Dictionary = rec["happy"]
	var gap: int = int(h["score"]) - int(rec["morale"])
	if absi(gap) > 6:
		lines.append("Drifting %s toward their underlying happiness (%s, %d)." %
			["up" if gap > 0 else "down", str(h["word"]), int(h["score"])])
	lines.append("See the Happiness view / profile for the full breakdown.")
	return "\n".join(PackedStringArray(lines))


func _sort_value(rec: Dictionary, id: String) -> Variant:
	if id == "happy":
		return rec["happy_score"]
	if id == "sstat":
		return TIER_RANK.get(str((rec["sstat"] as Dictionary)["key"]), 0)
	if id == "concern":
		var cs: Array = (rec["happy"] as Dictionary)["concerns"]
		return float(cs[0]["w"]) if not cs.is_empty() else 1.0
	if id == "promise":
		return {"open": 3, "broken": 2, "kept": 1}.get(str(rec["promise"].get("status", "")), 0)
	if id == "pick":
		return rec["pick_rank"]
	if id == "avail":
		var total := 0
		for fl in rec["flags"]:
			total += int(fl["sev"]) * 10 + 1
		return total
	if id == "item":
		return rec["item_name"] if rec["item_name"] != "" else "zzz"
	if id == "role":
		return rec["role"] if rec["role"] != "" else "zzz"
	if id == "type":
		return rec["types"][0]
	if id == "rec":
		return VERDICT_RANK.get(rec["rec"], 0)
	if id == "status":
		return rec["bids"] * 10 + (2 if rec["listed"] else 0) + (1 if rec["talks_locked"] else 0)
	return rec.get(id, 0)


# ------------------------------------------------------------------ table build

func _rebuild_table() -> void:
	var cols: Array = Views.columns(_view)
	_active_cols = cols
	_tree.clear()
	_tree.columns = cols.size()
	for i in cols.size():
		var def := _col_def(cols[i])
		var arrow := ""
		if cols[i] == _sort_key:
			arrow = "  v" if _sort_desc else "  ^"
		_tree.set_column_title(i, def["title"] + arrow)
		_tree.set_column_expand(i, def["expand"])
		_tree.set_column_title_alignment(i,
			HORIZONTAL_ALIGNMENT_RIGHT if def["num"] else HORIZONTAL_ALIGNMENT_LEFT)
		_tree.set_column_clip_content(i, true)
	_apply_column_widths()

	var rows := _records.filter(_passes_filter)
	var key := _sort_key
	var desc := _sort_desc
	rows.sort_custom(func(a, b):
		var va: Variant = _sort_value(a, key)
		var vb: Variant = _sort_value(b, key)
		if typeof(va) == TYPE_STRING:
			return (str(va) > str(vb)) if desc else (str(va) < str(vb))
		return (float(va) > float(vb)) if desc else (float(va) < float(vb)))

	var root := _tree.create_item()
	var row_i := 0
	for rec in rows:
		var it := _tree.create_item(root)
		it.set_metadata(0, rec["uid"])
		for i in cols.size():
			var id: String = cols[i]
			var def := _col_def(id)
			it.set_text(i, _cell_text(rec, id))
			it.set_custom_color(i, _cell_color(rec, id))
			if def["num"]:
				it.set_text_alignment(i, HORIZONTAL_ALIGNMENT_RIGHT)
			if row_i % 2 == 1:
				it.set_custom_bg_color(i, Color(1, 1, 1, 0.025))
		# icons
		var rep: Dictionary = rec["report"]
		var cur_col := cols.find("cur")
		if cur_col >= 0:
			it.set_icon(cur_col, Ability.stars_icon(rec["cur"]))
			it.set_tooltip_text(cur_col, "Current ability %s stars — %s.\nCoach report by %s (judging ability %d/20); top %d%% of the league's %d battlers." %
				[Ability.stars_text(rec["cur"]), Ability.ability_word(rec["cur"]),
				rep["ja_name"], int(rep["ja"]),
				maxi(int(round((1.0 - float(rep["pct_now"])) * 100.0)), 1), int(rep["league_n"])])
		var pot_col := cols.find("pot")
		if pot_col >= 0:
			it.set_icon(pot_col, Ability.stars_icon(float(rep["pot_lo"]), float(rep["pot_hi"]), Ability.COL_STARS_POT))
			it.set_tooltip_text(pot_col, "Potential %s stars (%s confidence — %s, judging potential %d/20).\nCeiling from trainable IVs (%d%% -> ~%d%%) and the full learnset." %
				[Ability.stars_range_text(float(rep["pot_lo"]), float(rep["pot_hi"])),
				rep["confidence"], rep["jp_name"], int(rep["jp"]),
				int(rep["iv_pct"]), int(rep["iv_pct_peak"])])
		var rec_col := cols.find("rec")
		if rec_col >= 0:
			it.set_tooltip_text(rec_col, str(rep["reason"]))
		var type_col := cols.find("type")
		if type_col >= 0:
			it.set_icon(type_col, UI.type_icon(rec["types"]))
		var morale_col := cols.find("morale")
		if morale_col >= 0:
			it.set_icon(morale_col, UI.dot_icon(UI.pct_color(rec["morale"])))
			it.set_tooltip_text(morale_col, _morale_tip(rec))
		var happy_col := cols.find("happy")
		if happy_col >= 0:
			var h: Dictionary = rec["happy"]
			it.set_icon(happy_col, UI.dot_icon(h["color"]))
			it.set_tooltip_text(happy_col, Personality.factors_tip(h))
		var pers_col := cols.find("pers")
		if pers_col >= 0:
			var hh: Dictionary = rec["happy"]
			it.set_tooltip_text(pers_col, "%s — %s\nCoach's read: %s." %
				[(hh["arch"] as Dictionary)["name"], (hh["arch"] as Dictionary)["desc"],
				Personality.attrs_line(hh["attrs"])])
		var sstat_col := cols.find("sstat")
		if sstat_col >= 0:
			var stt: Dictionary = rec["sstat"]
			it.set_tooltip_text(sstat_col, "%s (rated %d of %d in the squad). %s" %
				[stt["label"], int(stt["rank"]), int(stt["n"]), stt["expect"]])
		var concern_col := cols.find("concern")
		if concern_col >= 0:
			var cs: Array = (rec["happy"] as Dictionary)["concerns"]
			it.set_tooltip_text(concern_col, "\n".join(cs.map(func(c):
				return "%s — %s" % [str(c["short"]), str(c["detail"])])) if not cs.is_empty()
				else "No active concerns.")
			if not cs.is_empty():
				it.set_icon(concern_col, UI.dot_icon(
					UI.COL_BAD if float(cs[0]["w"]) <= -8.0 else UI.COL_WARN, 9))
		var promise_col := cols.find("promise")
		if promise_col >= 0:
			it.set_tooltip_text(promise_col, _promise_tip(rec["promise"]))
		var status_col := cols.find("status")
		if status_col >= 0:
			it.set_tooltip_text(status_col, _status_tip(rec))
		var pick_col := cols.find("pick")
		if pick_col >= 0:
			var pick: Dictionary = rec["pick"]
			it.set_tooltip_text(pick_col, str(pick["tip"]))
			if pick["kind"] == "starter":
				it.set_icon(pick_col, UI.dot_icon(UI.COL_ACCENT.lightened(0.1), 9))
				it.set_custom_bg_color(pick_col, Color(UI.COL_ACCENT, 0.13))
		var avail_col := cols.find("avail")
		if avail_col >= 0:
			var flags: Array = rec["flags"]
			it.set_tooltip_text(avail_col, Selection.flags_tip(flags))
			if not flags.is_empty():
				it.set_icon(avail_col, UI.dots_icon(flags.map(func(fl): return fl["color"])))
		var item_col := cols.find("item")
		if item_col >= 0:
			if rec["item_name"] != "":
				var item: Dictionary = rec["item"]
				it.set_icon(item_col, UI.dot_icon(UI.rarity_color(str(item.get("rarity", ""))), 9))
				it.set_tooltip_text(item_col, "%s (%s, held)\n%s\nEquip or swap items from the Items screen." %
					[item.get("name", "?"), item.get("rarity", "?"), item.get("desc", "")])
			else:
				it.set_tooltip_text(item_col, "No held item — equip one from the Items screen storeroom.")
		var babil_col := cols.find("babil")
		if babil_col >= 0:
			it.set_tooltip_text(babil_col, rec["babil_tip"])
		var nature_col := cols.find("nature")
		if nature_col >= 0:
			it.set_tooltip_text(nature_col, rec["nature_tip"])
		for sk in ["hp", "atk", "def", "spa", "spd", "spe"]:
			var s_col := cols.find(sk)
			if s_col < 0:
				continue
			var dir := UI.nature_dir(rec["inst"], sk)
			var tip := "Battle-real %s: %d — the number the match engine fights with." % \
				[UI.STAT_SHORT[sk], int(rec[sk])]
			if dir != 0:
				tip += "\nIncludes the %s nature's %s10%% %s." % [rec["nature_name"],
					"+" if dir > 0 else "−", "boost" if dir > 0 else "drop"]
				it.set_custom_color(s_col, UI.COL_GOOD if dir > 0 else UI.COL_WARN)
			it.set_tooltip_text(s_col, tip)
		var name_col := cols.find("name")
		if name_col >= 0:
			it.set_icon(name_col, UI.dot_icon(DataStore.type_color(rec["types"][0]), 9))
		if rec["uid"] == _selected_uid:
			it.select(0)
		row_i += 1
	_update_footer()


func _passes_filter(rec: Dictionary) -> bool:
	if _filter == "":
		return true
	if rec["name"].to_lower().contains(_filter) or rec["species"].to_lower().contains(_filter):
		return true
	for t in rec["types"]:
		if str(t).contains(_filter):
			return true
	return false


func _on_preset(view_name: String) -> void:
	if not Views.has_view(view_name):
		view_name = "General"
	_view = view_name
	Views.set_active(view_name)
	for p in _view_buttons:
		(_view_buttons[p] as Button).button_pressed = p == view_name
	if not Views.columns(view_name).has(_sort_key):
		_sort_key = "lv"
		_sort_desc = true
	_rebuild_table()


## Responsive widths: shrink columns (to a floor) when the view is wider than
## the tree, so a dense view fits at 1600x900; anything beyond the floor is
## reachable via the tree's horizontal scrollbar. Re-runs on every resize.
func _apply_column_widths() -> void:
	if _tree == null or _tree.columns != _active_cols.size() or _active_cols.is_empty():
		return
	var total := 0
	for id in _active_cols:
		total += int(_col_def(id)["w"])
	var avail := _tree.size.x - 14.0   # leave room for the vertical scrollbar
	var scale := 1.0
	if avail > 0.0 and float(total) > avail:
		scale = maxf(avail / float(total), 0.86)
	for i in _active_cols.size():
		_tree.set_column_custom_minimum_width(i,
			int(floor(float(_col_def(_active_cols[i])["w"]) * scale)))


func _rebuild_views_bar() -> void:
	for c in _views_bar.get_children():
		c.queue_free()
	_view_buttons.clear()
	var view_lbl := Label.new()
	view_lbl.text = "View:"
	view_lbl.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	_views_bar.add_child(view_lbl)
	for vn in Views.view_names():
		var b := Button.new()
		b.text = str(vn) + ("*" if Views.is_modified(vn) else "")
		b.toggle_mode = true
		b.button_pressed = vn == _view
		if Views.is_preset(vn):
			b.tooltip_text = ("Preset view (carrying your edits — Columns... to change or reset)"
				if Views.is_modified(vn) else "Preset view — an editable starting point (Columns...)")
		else:
			b.tooltip_text = "Your custom view — saved in this career's save file"
			b.add_theme_color_override("font_color", UI.COL_ACCENT.lightened(0.35))
		b.pressed.connect(_on_preset.bind(str(vn)))
		_views_bar.add_child(b)
		_view_buttons[str(vn)] = b
	var edit_b := Button.new()
	edit_b.text = "Columns..."
	edit_b.tooltip_text = ("Customize this view: add, remove and reorder columns,\n" +
		"save it over '%s' or as a new view. Saved views live in the career save.") % _view
	edit_b.pressed.connect(_open_view_editor)
	_views_bar.add_child(edit_b)


func _open_view_editor() -> AcceptDialog:
	return ViewEditor.open(self, _view, func(shown: String) -> void:
		_view = shown
		Views.set_active(shown)
		if not Views.columns(shown).has(_sort_key):
			_sort_key = "lv"
			_sort_desc = true
		_rebuild_views_bar()
		_rebuild_table())


func _on_column_clicked(column: int, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_LEFT:
		return
	var cols: Array = _active_cols
	if column < 0 or column >= cols.size():
		return
	var id: String = cols[column]
	if _sort_key == id:
		_sort_desc = not _sort_desc
	else:
		_sort_key = id
		_sort_desc = _col_def(id)["num"]  # numbers default high-to-low, text A-Z
	_rebuild_table()


# ------------------------------------------------------------------ selection footer

func _selected_record() -> Dictionary:
	var it := _tree.get_selected()
	if it == null:
		return {}
	var uid: String = it.get_metadata(0)
	for rec in _records:
		if rec["uid"] == uid:
			return rec
	return {}


func _on_row_selected() -> void:
	var rec := _selected_record()
	_selected_uid = rec.get("uid", "")
	_update_footer()


func _on_item_mouse_selected(_pos: Vector2, mouse_button_index: int) -> void:
	_on_row_selected()
	if mouse_button_index == MOUSE_BUTTON_RIGHT:
		var rec := _selected_record()
		if not rec.is_empty():
			Actions.open_menu(self, rec["uid"], get_global_mouse_position(),
				func(uid: String) -> void: _open_profile(uid))


func _update_footer() -> void:
	for c in _footer_stats.get_children():
		c.queue_free()
	for c in _footer_actions.get_children():
		c.queue_free()
	var rec := _selected_record()
	if rec.is_empty():
		var l := Label.new()
		l.text = "Select a Pokemon for a quick summary, double-click to open its full profile."
		l.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_footer_stats.add_child(l)
		return
	var mono := UI.monogram(rec["name"], rec["types"], 44, 18)
	mono.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_footer_stats.add_child(mono)
	var idbox := VBoxContainer.new()
	idbox.add_theme_constant_override("separation", 2)
	idbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_footer_stats.add_child(idbox)
	var nm := Label.new()
	nm.text = "%s  ·  Lv %d %s" % [rec["name"], rec["lv"], rec["species"]]
	nm.add_theme_font_size_override("font_size", 16)
	nm.add_theme_color_override("font_color", Color.WHITE)
	idbox.add_child(nm)
	var badges := HBoxContainer.new()
	badges.add_theme_constant_override("separation", 4)
	for t in rec["types"]:
		badges.add_child(UI.type_badge(t, 10))
	idbox.add_child(badges)

	var pick: Dictionary = rec["pick"]
	var sel_stat := _footer_stat("PICKED",
		("Starter %d" % int(pick["rank"])) if pick["kind"] == "starter" else str(pick["text"]).replace("S", "Sub "),
		UI.COL_ACCENT.lightened(0.2) if pick["kind"] == "starter" else UI.COL_TEXT_DIM)
	sel_stat.tooltip_text = str(pick["tip"])
	_footer_stats.add_child(sel_stat)
	var item_stat := _footer_stat("HELD ITEM",
		rec["item_name"] if rec["item_name"] != "" else "None",
		UI.rarity_color(str((rec["item"] as Dictionary).get("rarity", ""))) if rec["item_name"] != "" else UI.COL_TEXT_DIM)
	item_stat.tooltip_text = ("%s\nManage from the Items screen." % (rec["item"] as Dictionary).get("desc", "")) \
		if rec["item_name"] != "" else "No held item — equip one from the Items screen."
	_footer_stats.add_child(item_stat)
	if not (rec["flags"] as Array).is_empty():
		var av_stat := _footer_stat("AVAILABILITY", Selection.flags_text(rec["flags"]),
			Selection.worst_color(rec["flags"]))
		av_stat.tooltip_text = Selection.flags_tip(rec["flags"])
		_footer_stats.add_child(av_stat)
	var rep: Dictionary = rec["report"]
	_footer_stats.add_child(_footer_stars("ABILITY", Ability.stars_icon(rec["cur"], -1.0, Ability.COL_STARS_NOW, 12),
		Ability.ability_word(rec["cur"])))
	_footer_stats.add_child(_footer_stars("POTENTIAL",
		Ability.stars_icon(float(rep["pot_lo"]), float(rep["pot_hi"]), Ability.COL_STARS_POT, 12),
		"%s conf." % rep["confidence"]))
	_footer_stats.add_child(_footer_stat("COACH CALL", rec["rec"], rep["verdict_color"]))
	var h: Dictionary = rec["happy"]
	var happy_stat := _footer_stat("HAPPINESS", str(h["word"]), h["color"])
	happy_stat.tooltip_text = Personality.factors_tip(h)
	_footer_stats.add_child(happy_stat)
	if rec["concern"] != "" and int(rec["happy_score"]) < 55:
		var concern_stat := _footer_stat("TOP CONCERN", rec["concern"], UI.COL_WARN)
		concern_stat.tooltip_text = "\n".join((h["concerns"] as Array).map(func(c):
			return "%s — %s" % [str(c["short"]), str(c["detail"])]))
		_footer_stats.add_child(concern_stat)
	if (rec["flags"] as Array).is_empty():
		_footer_stats.add_child(_footer_stat("COND / FIT", "%d%% / %d%%" % [rec["cond"], rec["fit"]],
			UI.pct_color(mini(rec["cond"], rec["fit"]))))
	_footer_stats.add_child(_footer_stat("SEASON",
		"%d apps · %d KOs · av %s" % [rec["apps"], rec["kos"],
			("%.2f" % rec["rat"]) if rec["apps"] > 0 else "-"],
		UI.rating_color(rec["rat"]) if rec["apps"] > 0 else UI.COL_TEXT))
	if rec["listed"]:
		_footer_stats.add_child(_footer_stat("TRANSFER",
			"Listed at %s" % UI.money(rec["ask"]), UI.COL_BAD))

	var uid: String = rec["uid"]
	if rec["bids"] > 0:
		var bids_b := Button.new()
		bids_b.text = "Respond To %d Bid%s" % [rec["bids"], "s" if rec["bids"] > 1 else ""]
		bids_b.add_theme_color_override("font_color", UI.COL_WARN)
		bids_b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bids_b.pressed.connect(func() -> void: Actions.open_offers_dialog(self, uid))
		_footer_actions.add_child(bids_b)
	var contract_b := Button.new()
	contract_b.text = "Contract..."
	contract_b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	contract_b.disabled = rec["talks_locked"]
	contract_b.tooltip_text = "Open contract renewal talks" if not rec["talks_locked"] \
		else "Talks broke down recently — locked until %s" % Season.pretty_date(_svc.talks_locked_until(uid))
	contract_b.pressed.connect(func() -> void: Actions.open_contract_dialog(self, uid))
	_footer_actions.add_child(contract_b)
	var list_b := Button.new()
	list_b.text = "Unlist" if rec["listed"] else "Transfer List"
	list_b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	list_b.pressed.connect(func() -> void:
		if _svc.is_listed(_svc.find_instance(uid)):
			var err: String = _svc.unlist(uid)
			if err != "":
				Actions.notice(self, "Transfer list", err)
		else:
			Actions.open_list_dialog(self, uid))
	_footer_actions.add_child(list_b)
	var actions_b := Button.new()
	actions_b.text = "Actions..."
	actions_b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	actions_b.pressed.connect(func() -> void:
		Actions.open_menu(self, uid, get_global_mouse_position() - Vector2(160, 240),
			func(u: String) -> void: _open_profile(u)))
	_footer_actions.add_child(actions_b)
	_profile_btn = Button.new()
	_profile_btn.text = "Profile"
	_profile_btn.tooltip_text = "Open the full profile (or double-click the row)"
	_profile_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_profile_btn.pressed.connect(_open_selected_profile)
	_footer_actions.add_child(_profile_btn)


func _footer_stars(label: String, tex: ImageTexture, sub: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l1 := Label.new()
	l1.text = label
	l1.add_theme_font_size_override("font_size", 10)
	l1.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	v.add_child(l1)
	var tr := TextureRect.new()
	tr.texture = tex
	tr.stretch_mode = TextureRect.STRETCH_KEEP
	v.add_child(tr)
	var l2 := Label.new()
	l2.text = sub
	l2.add_theme_font_size_override("font_size", 10)
	l2.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	v.add_child(l2)
	return v


func _footer_stat(label: String, value: String, col: Color) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l1 := Label.new()
	l1.text = label
	l1.add_theme_font_size_override("font_size", 10)
	l1.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	v.add_child(l1)
	var l2 := Label.new()
	l2.text = value
	l2.add_theme_font_size_override("font_size", 14)
	l2.add_theme_color_override("font_color", col)
	v.add_child(l2)
	return v


# ------------------------------------------------------------------ profile

func _open_selected_profile() -> void:
	var rec := _selected_record()
	if rec.is_empty():
		if not _records.is_empty():
			rec = _records[0]
		else:
			return
	_open_profile(rec["uid"])


func _open_profile(uid: String) -> void:
	_profile.open(uid)
	_profile.visible = true
	_table_view.visible = false


func _close_profile() -> void:
	_profile.visible = false
	_table_view.visible = true
	_refresh()
