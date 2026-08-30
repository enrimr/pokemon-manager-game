extends Control
## Squad screen — FM24-style squad table + full Pokémon profile.
## Owned by the "squad" piece. All data live from GameState / DataStore.

const UI := preload("res://screens/squad/ui_helpers.gd")
const SeasonStats := preload("res://screens/squad/season_stats.gd")
const ProfileView := preload("res://screens/squad/profile.gd")
const Actions := preload("res://screens/squad/actions_ui.gd")
const Service := preload("res://screens/squad/squad_service.gd")
const History := preload("res://screens/squad/career_history.gd")
const Ability := preload("res://screens/squad/ability.gd")

const PRESETS := {
	"General": ["name", "species", "type", "lv", "age", "cur", "pot", "rec", "cond",
		"morale", "apps", "kos", "rat", "salary", "expiry", "status"],
	"Battle Stats": ["name", "type", "lv", "cur", "pot", "hp", "atk", "def", "spa", "spd", "spe",
		"tot", "dev", "apps", "wins", "kos", "dmg", "taken", "faints", "rat"],
	"Contracts": ["name", "type", "age", "lv", "cur", "pot", "rec", "morale",
		"salary", "wage_pct", "expiry", "days_left", "demand", "value", "status"],
}

const VERDICT_RANK := {"Key battler": 5, "First team": 4, "Develop": 3,
	"Squad depth": 2, "Aging": 1, "Surplus": 0}

var _records: Array = []          # one dict per squad instance, precomputed
var _view: String = "General"
var _sort_key: String = "cur"
var _sort_desc := true
var _filter := ""
var _selected_uid := ""

var _table_view: VBoxContainer
var _tree: Tree
var _header_info: Label
var _chips_box: HBoxContainer
var _preset_buttons: Dictionary = {}
var _footer: PanelContainer
var _footer_box: HBoxContainer
var _profile_btn: Button
var _bids_btn: Button
var _profile: ProfileView
var _svc: Node


var _hist: Node


func _ready() -> void:
	_svc = Service.ensure()
	_hist = History.ensure()
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
	var dev_view := OS.get_environment("SQUAD_DEV_VIEW")
	if dev_view != "" and PRESETS.has(dev_view):
		_on_preset(dev_view)
		var root := _tree.get_root()
		if root != null and root.get_child_count() > 0:
			root.get_child(0).select(0)
			_on_row_selected()
	if OS.get_environment("SQUAD_DEV_LIST") != "" and _records.size() > 2 \
			and not _svc.is_listed(_records[2]["inst"]):
		_svc.set_listed(_records[2]["uid"], UI.est_value(_records[2]["inst"]))
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
	head.add_child(title_box)
	var title := Label.new()
	title.text = "Squad"
	title.add_theme_font_size_override("font_size", 25)
	title.add_theme_color_override("font_color", Color.WHITE)
	title_box.add_child(title)
	_header_info = Label.new()
	_header_info.add_theme_font_size_override("font_size", 13)
	_header_info.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	title_box.add_child(_header_info)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	_chips_box = HBoxContainer.new()
	_chips_box.add_theme_constant_override("separation", 8)
	head.add_child(_chips_box)

	# --- toolbar
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	_table_view.add_child(bar)
	var view_lbl := Label.new()
	view_lbl.text = "View:"
	view_lbl.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	bar.add_child(view_lbl)
	for preset in PRESETS:
		var b := Button.new()
		b.text = preset
		b.toggle_mode = true
		b.button_pressed = preset == _view
		b.pressed.connect(_on_preset.bind(preset))
		bar.add_child(b)
		_preset_buttons[preset] = b
	var sp2 := Control.new()
	sp2.custom_minimum_size = Vector2(18, 0)
	bar.add_child(sp2)
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
	bar.add_child(hint)

	# --- table
	_tree = Tree.new()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.hide_root = true
	_tree.select_mode = Tree.SELECT_ROW
	_tree.column_titles_visible = true
	_tree.allow_reselect = true
	_tree.scroll_horizontal_enabled = false
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

	# --- footer selection strip
	_footer = PanelContainer.new()
	_footer.custom_minimum_size = Vector2(0, 64)
	_footer_box = HBoxContainer.new()
	_footer_box.add_theme_constant_override("separation", 16)
	_footer.add_child(_footer_box)
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
	return {
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
	_header_info.text = "%s · %s · %d%s in the %s · %s" % [
		club["name"], Season.pretty_date(GameState.current_date), pos, suffix,
		GameState.world["meta"]["league_name"], "Manager: %s" % club["manager"]]
	for c in _chips_box.get_children():
		c.queue_free()
	var lv_sum := 0
	var cond_sum := 0
	for inst in squad:
		lv_sum += int(inst["level"])
		cond_sum += int(inst["condition"])
	var n := maxi(squad.size(), 1)
	_chips_box.add_child(_chip("POKEMON", str(squad.size()), UI.COL_TEXT))
	_chips_box.add_child(_chip("AVG LEVEL", "%.1f" % (float(lv_sum) / n), UI.COL_TEXT))
	_chips_box.add_child(_chip("AVG COND", "%d%%" % int(float(cond_sum) / n),
		UI.pct_color(int(float(cond_sum) / n))))
	_chips_box.add_child(_chip("WAGE BILL", UI.money(wage_bill) + "/wk",
		UI.COL_WARN if wage_bill > int(club["finances"]["wage_budget"]) else UI.COL_TEXT))
	_chips_box.add_child(_chip("WAGE BUDGET", UI.money(int(club["finances"]["wage_budget"])) + "/wk", UI.COL_TEXT_DIM))
	_chips_box.add_child(_chip("BALANCE", UI.money(int(club["finances"]["balance"])), UI.COL_GOOD))


func _chip(label: String, value: String, col: Color) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UI.COL_PANEL
	sb.border_color = UI.COL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
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
	l2.add_theme_font_size_override("font_size", 15)
	l2.add_theme_color_override("font_color", col)
	v.add_child(l2)
	return p


# ------------------------------------------------------------------ columns

func _col_def(id: String) -> Dictionary:
	match id:
		"name": return {"title": "Name", "w": 140, "expand": true, "num": false}
		"species": return {"title": "Species", "w": 108, "expand": true, "num": false}
		"type": return {"title": "Type", "w": 96, "expand": false, "num": false}
		"lv": return {"title": "Lv", "w": 40, "expand": false, "num": true}
		"cur": return {"title": "Ability", "w": 84, "expand": false, "num": true}
		"pot": return {"title": "Potential", "w": 84, "expand": false, "num": true}
		"rec": return {"title": "Coach Call", "w": 98, "expand": false, "num": false}
		"age": return {"title": "Age", "w": 56, "expand": false, "num": true}
		"cond": return {"title": "Cond", "w": 56, "expand": false, "num": true}
		"fit": return {"title": "Fit", "w": 52, "expand": false, "num": true}
		"morale": return {"title": "Morale", "w": 86, "expand": false, "num": false}
		"hp": return {"title": "HP", "w": 50, "expand": false, "num": true}
		"atk": return {"title": "Atk", "w": 50, "expand": false, "num": true}
		"def": return {"title": "Def", "w": 50, "expand": false, "num": true}
		"spa": return {"title": "SpA", "w": 50, "expand": false, "num": true}
		"spd": return {"title": "SpD", "w": 50, "expand": false, "num": true}
		"spe": return {"title": "Spe", "w": 50, "expand": false, "num": true}
		"tot": return {"title": "Tot", "w": 56, "expand": false, "num": true}
		"dev": return {"title": "Dev", "w": 52, "expand": false, "num": true}
		"apps": return {"title": "Apps", "w": 52, "expand": false, "num": true}
		"wins": return {"title": "Won", "w": 50, "expand": false, "num": true}
		"kos": return {"title": "KOs", "w": 48, "expand": false, "num": true}
		"dmg": return {"title": "Dmg", "w": 62, "expand": false, "num": true}
		"taken": return {"title": "Tkn", "w": 62, "expand": false, "num": true}
		"faints": return {"title": "Fnt", "w": 44, "expand": false, "num": true}
		"rat": return {"title": "Av Rat", "w": 60, "expand": false, "num": true}
		"salary": return {"title": "Salary", "w": 88, "expand": false, "num": true}
		"wage_pct": return {"title": "Wage %", "w": 64, "expand": false, "num": true}
		"expiry": return {"title": "Expires", "w": 96, "expand": false, "num": true}
		"days_left": return {"title": "Days", "w": 54, "expand": false, "num": true}
		"value": return {"title": "Value", "w": 88, "expand": false, "num": true}
		"demand": return {"title": "Wants", "w": 100, "expand": false, "num": true}
		"status": return {"title": "Status", "w": 92, "expand": false, "num": false}
	return {"title": id, "w": 60, "expand": false, "num": false}


func _cell_text(rec: Dictionary, id: String) -> String:
	match id:
		"cur", "pot": return ""  # star icon cells
		"rec": return rec["rec"]
		"type": return "/".join(rec["types"].map(func(t): return UI.type_abbr(t)))
		"age": return UI.age_str(rec["age"])
		"cond": return "%d%%" % rec["cond"]
		"fit": return "%d%%" % rec["fit"]
		"morale": return UI.morale_word(rec["morale"])
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
		"rec": return (rec["report"] as Dictionary)["verdict_color"]
		"name": return Color.WHITE
		"species": return UI.COL_TEXT_DIM
		"type": return DataStore.type_color(rec["types"][0]).lightened(0.2)
		"cond": return UI.pct_color(rec["cond"])
		"fit": return UI.pct_color(rec["fit"])
		"morale": return UI.pct_color(rec["morale"])
		"rat": return UI.rating_color(rec["rat"]) if rec["apps"] > 0 else UI.COL_TEXT_DIM
		"expiry", "days_left":
			if rec["days_left"] < 90: return UI.COL_BAD
			if rec["days_left"] < 240: return UI.COL_WARN
			return UI.COL_TEXT
		"salary", "value", "wage_pct": return UI.COL_TEXT
		"dev": return UI.COL_GOOD if rec["dev"] > 0 else UI.COL_TEXT_DIM
		"demand": return UI.COL_WARN if rec["demand"] > rec["salary"] * 2 else UI.COL_TEXT_DIM
		"status":
			if rec["bids"] > 0: return UI.COL_WARN
			if rec["listed"]: return UI.COL_BAD
			return UI.COL_TEXT_DIM
		"hp", "atk", "def", "spa", "spd", "spe":
			return UI.attr_color(UI.base_to_20(int(DataStore.species(
				int(rec["inst"]["species_id"]))["base"][id])))
	return UI.COL_TEXT


func _status_text(rec: Dictionary) -> String:
	var parts: Array = []
	if rec["bids"] > 0:
		parts.append("%d bid%s" % [rec["bids"], "s" if rec["bids"] > 1 else ""])
	if rec["listed"]:
		parts.append("Listed")
	if rec["talks_locked"]:
		parts.append("Talks off")
	return " · ".join(PackedStringArray(parts)) if not parts.is_empty() else "-"


func _sort_value(rec: Dictionary, id: String) -> Variant:
	if id == "type":
		return rec["types"][0]
	if id == "rec":
		return VERDICT_RANK.get(rec["rec"], 0)
	if id == "status":
		return rec["bids"] * 10 + (2 if rec["listed"] else 0) + (1 if rec["talks_locked"] else 0)
	return rec.get(id, 0)


# ------------------------------------------------------------------ table build

func _rebuild_table() -> void:
	var cols: Array = PRESETS[_view]
	_tree.clear()
	_tree.columns = cols.size()
	for i in cols.size():
		var def := _col_def(cols[i])
		var arrow := ""
		if cols[i] == _sort_key:
			arrow = "  v" if _sort_desc else "  ^"
		_tree.set_column_title(i, def["title"] + arrow)
		_tree.set_column_expand(i, def["expand"])
		_tree.set_column_custom_minimum_width(i, def["w"])
		_tree.set_column_title_alignment(i,
			HORIZONTAL_ALIGNMENT_RIGHT if def["num"] else HORIZONTAL_ALIGNMENT_LEFT)
		_tree.set_column_clip_content(i, true)

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


func _on_preset(preset: String) -> void:
	_view = preset
	for p in _preset_buttons:
		_preset_buttons[p].button_pressed = p == preset
	if not PRESETS[preset].has(_sort_key):
		_sort_key = "lv"
		_sort_desc = true
	_rebuild_table()


func _on_column_clicked(column: int, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_LEFT:
		return
	var cols: Array = PRESETS[_view]
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
	for c in _footer_box.get_children():
		c.queue_free()
	var rec := _selected_record()
	if rec.is_empty():
		var l := Label.new()
		l.text = "Select a Pokemon for a quick summary, double-click to open its full profile."
		l.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_footer_box.add_child(l)
		return
	var mono := UI.monogram(rec["name"], rec["types"], 44, 18)
	mono.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_footer_box.add_child(mono)
	var idbox := VBoxContainer.new()
	idbox.add_theme_constant_override("separation", 2)
	idbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_footer_box.add_child(idbox)
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

	var rep: Dictionary = rec["report"]
	_footer_box.add_child(_footer_stars("ABILITY", Ability.stars_icon(rec["cur"], -1.0, Ability.COL_STARS_NOW, 12),
		Ability.ability_word(rec["cur"])))
	_footer_box.add_child(_footer_stars("POTENTIAL",
		Ability.stars_icon(float(rep["pot_lo"]), float(rep["pot_hi"]), Ability.COL_STARS_POT, 12),
		"%s conf." % rep["confidence"]))
	_footer_box.add_child(_footer_stat("COACH CALL", rec["rec"], rep["verdict_color"]))
	_footer_box.add_child(_footer_stat("COND / FIT", "%d%% / %d%%" % [rec["cond"], rec["fit"]],
		UI.pct_color(mini(rec["cond"], rec["fit"]))))
	_footer_box.add_child(_footer_stat("MORALE", UI.morale_word(rec["morale"]), UI.pct_color(rec["morale"])))
	_footer_box.add_child(_footer_stat("SEASON",
		"%d apps · %d KOs · av %s" % [rec["apps"], rec["kos"],
			("%.2f" % rec["rat"]) if rec["apps"] > 0 else "-"],
		UI.rating_color(rec["rat"]) if rec["apps"] > 0 else UI.COL_TEXT))
	if rec["listed"]:
		_footer_box.add_child(_footer_stat("TRANSFER",
			"Listed at %s" % UI.money(rec["ask"]), UI.COL_BAD))

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer_box.add_child(sp)
	var uid: String = rec["uid"]
	if rec["bids"] > 0:
		var bids_b := Button.new()
		bids_b.text = "Respond To %d Bid%s" % [rec["bids"], "s" if rec["bids"] > 1 else ""]
		bids_b.add_theme_color_override("font_color", UI.COL_WARN)
		bids_b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bids_b.pressed.connect(func() -> void: Actions.open_offers_dialog(self, uid))
		_footer_box.add_child(bids_b)
	var contract_b := Button.new()
	contract_b.text = "New Contract"
	contract_b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	contract_b.disabled = rec["talks_locked"]
	contract_b.tooltip_text = "Open contract renewal talks" if not rec["talks_locked"] \
		else "Talks broke down recently — locked until %s" % Season.pretty_date(_svc.talks_locked_until(uid))
	contract_b.pressed.connect(func() -> void: Actions.open_contract_dialog(self, uid))
	_footer_box.add_child(contract_b)
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
	_footer_box.add_child(list_b)
	var actions_b := Button.new()
	actions_b.text = "Actions..."
	actions_b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	actions_b.pressed.connect(func() -> void:
		Actions.open_menu(self, uid, get_global_mouse_position() - Vector2(160, 240),
			func(u: String) -> void: _open_profile(u)))
	_footer_box.add_child(actions_b)
	_profile_btn = Button.new()
	_profile_btn.text = "Open Profile"
	_profile_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_profile_btn.pressed.connect(_open_selected_profile)
	_footer_box.add_child(_profile_btn)


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
