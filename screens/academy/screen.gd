extends Control
## Youth Academy screen — FM-style development centre.
## Facility status + board upgrade requests, monthly intake summary, and a
## dense roster table (promote / release / training focus). All model logic
## lives in res://shared/sim/services/academy.gd (AcademyService).

const TB := preload("res://shared/theme/theme_builder.gd")
const Academy := preload("res://shared/sim/services/academy.gd")
const GOLD := Color("e8c35a")

var _svc: RefCounted = null

var _fac_name: Label
var _fac_pips: HBoxContainer
var _fac_intake: Label
var _fac_roster: Label
var _upg_btn: Button
var _upg_status: Label
var _tree: Tree
var _empty_lbl: Label
var _history_box: VBoxContainer
var _detail: VBoxContainer
var _err: Label
var _selected_uid := ""


func _ready() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	root.add_child(_build_header())

	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 8)
	root.add_child(main)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	main.add_child(left)
	left.add_child(_build_table())
	left.add_child(_build_history())

	main.add_child(_build_detail())

	GameState.date_changed.connect(func(_d): _refresh())
	GameState.career_started.connect(_refresh)
	_refresh()


func on_show() -> void:
	_refresh()


func _svc_ref() -> RefCounted:
	var s: RefCounted = Academy.active
	if s != null and s != _svc:
		_svc = s
		if not _svc.academy_changed.is_connected(_refresh):
			_svc.academy_changed.connect(_refresh)
	return _svc


# ------------------------------------------------------------------ header

func _build_header() -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = TB.COL_PANEL
	sb.border_color = TB.COL_BORDER
	sb.set_border_width_all(1)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	panel.add_child(row)

	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 2)
	row.add_child(titles)
	var t := Label.new()
	t.text = "Youth Academy"
	t.add_theme_font_size_override("font_size", 24)
	titles.add_child(t)
	var sub := Label.new()
	sub.text = "Development Centre"
	sub.add_theme_color_override("font_color", TB.COL_TEXT_DIM)
	titles.add_child(sub)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var fac := VBoxContainer.new()
	fac.add_theme_constant_override("separation", 3)
	row.add_child(fac)
	var fr := HBoxContainer.new()
	fr.add_theme_constant_override("separation", 8)
	fac.add_child(fr)
	_fac_pips = HBoxContainer.new()
	_fac_pips.add_theme_constant_override("separation", 3)
	fr.add_child(_fac_pips)
	for i in 5:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(22, 10)
		_fac_pips.add_child(pip)
	_fac_name = Label.new()
	_fac_name.add_theme_font_size_override("font_size", 15)
	fr.add_child(_fac_name)
	_fac_intake = Label.new()
	_fac_intake.add_theme_color_override("font_color", TB.COL_TEXT_DIM)
	fac.add_child(_fac_intake)
	_fac_roster = Label.new()
	_fac_roster.add_theme_color_override("font_color", TB.COL_TEXT_DIM)
	fac.add_child(_fac_roster)

	var upg := VBoxContainer.new()
	upg.add_theme_constant_override("separation", 4)
	upg.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(upg)
	_upg_btn = Button.new()
	_upg_btn.pressed.connect(_on_upgrade_pressed)
	upg.add_child(_upg_btn)
	_upg_status = Label.new()
	_upg_status.add_theme_color_override("font_color", TB.COL_WARN)
	_upg_status.add_theme_font_size_override("font_size", 13)
	upg.add_child(_upg_status)
	return panel


func _on_upgrade_pressed() -> void:
	var s := _svc_ref()
	if s == null:
		return
	var err: String = s.request_upgrade()
	_refresh()
	if _err != null:
		_err.text = err


# ------------------------------------------------------------------ table

func _build_table() -> Control:
	var wrap := PanelContainer.new()
	wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	wrap.add_child(box)
	_tree = Tree.new()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.columns = 10
	_tree.column_titles_visible = true
	_tree.hide_root = true
	_tree.select_mode = Tree.SELECT_ROW
	var titles := ["Pokémon", "Type", "Age", "Lv", "Nature", "Ability", "Current", "Potential", "Dev", "Focus"]
	var widths := [150, 110, 55, 40, 80, 105, 80, 110, 70, 80]
	for i in titles.size():
		_tree.set_column_title(i, titles[i])
		_tree.set_column_custom_minimum_width(i, widths[i])
		_tree.set_column_expand(i, i == 0)
		_tree.set_column_title_alignment(i, HORIZONTAL_ALIGNMENT_LEFT)
	_tree.item_selected.connect(_on_row_selected)
	box.add_child(_tree)
	_empty_lbl = Label.new()
	_empty_lbl.add_theme_color_override("font_color", TB.COL_TEXT_DIM)
	_empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_empty_lbl)
	return wrap


func _fill_table(s: RefCounted) -> void:
	_tree.clear()
	var root := _tree.create_item()
	var sel: TreeItem = null
	var sorted: Array = s.roster.duplicate()
	sorted.sort_custom(func(a, b): return int(a["pot_max"]) > int(b["pot_max"]))
	for m in sorted:
		var it := _tree.create_item(root)
		it.set_metadata(0, String(m["uid"]))
		var sp: Dictionary = DataStore.species(int(m["species_id"]))
		it.set_text(0, String(m["species"]))
		var types: Array = sp.get("types", [])
		it.set_text(1, " / ".join(types.map(func(x): return String(x).capitalize())))
		if not types.is_empty():
			it.set_custom_color(1, DataStore.type_color(String(types[0])).lightened(0.25))
		it.set_text(2, Academy._age_text(int(m["age_months"])))
		it.set_text(3, str(int(m["level"])))
		it.set_text(4, String(m["nature"]))
		it.set_text(5, DataStore.ability_name(String(m["ability"])))
		it.set_text(6, Academy.star_text(float(m["stars"])))
		it.set_custom_color(6, TB.COL_ACCENT.lightened(0.25))
		var band: Array = s.potential_stars(m)
		it.set_text(7, "%s – %s" % [Academy.star_text(band[0]), Academy.star_text(band[1])])
		it.set_custom_color(7, GOLD)
		it.set_text(8, "%d%%" % int(round(s.dev_progress(m) * 100.0)))
		it.set_custom_color(8, TB.COL_GOOD)
		it.set_text(9, Academy.FOCUS_LABELS[String(m.get("focus", "balanced"))])
		it.set_custom_color(2, TB.COL_TEXT_DIM)
		it.set_custom_color(4, TB.COL_TEXT_DIM)
		it.set_custom_color(5, TB.COL_TEXT_DIM)
		it.set_custom_color(9, TB.COL_TEXT_DIM)
		if String(m["uid"]) == _selected_uid:
			sel = it
	if sel != null:
		sel.select(0)
	_empty_lbl.visible = s.roster.is_empty()
	_empty_lbl.text = "No academy recruits yet — the next intake day is %s." % s.next_intake_date()


func _on_row_selected() -> void:
	var it := _tree.get_selected()
	if it != null:
		_selected_uid = String(it.get_metadata(0))
		_fill_detail()


# ------------------------------------------------------------------ history

func _build_history() -> Control:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)
	var h := Label.new()
	h.text = "INTAKE HISTORY"
	h.add_theme_font_size_override("font_size", 12)
	h.add_theme_color_override("font_color", TB.COL_TEXT_DIM)
	box.add_child(h)
	_history_box = VBoxContainer.new()
	_history_box.add_theme_constant_override("separation", 2)
	box.add_child(_history_box)
	return panel


func _fill_history(s: RefCounted) -> void:
	for c in _history_box.get_children():
		c.queue_free()
	if s.history.is_empty():
		var l := Label.new()
		l.text = "No intakes yet this season."
		l.add_theme_color_override("font_color", TB.COL_TEXT_DIM)
		_history_box.add_child(l)
		return
	for i in mini(4, s.history.size()):
		var e: Dictionary = s.history[i]
		var l := Label.new()
		var tag := ""
		if bool(e.get("golden", false)):
			tag = "   GOLDEN GENERATION"
		elif bool(e.get("thin", false)):
			tag = "   thin month"
		l.text = "%s   %d recruits (facility L%d)   best: %s%s" % [String(e["date"]),
			int(e["count"]), int(e.get("facility", 1)), String(e["best"]), tag]
		l.add_theme_font_size_override("font_size", 13)
		if tag.begins_with("   GOLDEN"):
			l.add_theme_color_override("font_color", GOLD)
		else:
			l.add_theme_color_override("font_color", TB.COL_TEXT_DIM)
		_history_box.add_child(l)


# ------------------------------------------------------------------ detail

func _build_detail() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(340, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = TB.COL_PANEL
	sb.border_color = TB.COL_BORDER
	sb.set_border_width_all(1)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 6)
	panel.add_child(_detail)
	return panel


func _dl(text: String, color: Color = TB.COL_TEXT, size: int = 14) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _type_badges(types: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for t in types:
		var badge := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = DataStore.type_color(String(t))
		sb.set_corner_radius_all(3)
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.content_margin_top = 1
		sb.content_margin_bottom = 1
		badge.add_theme_stylebox_override("panel", sb)
		var l := Label.new()
		l.text = String(t).to_upper()
		l.add_theme_font_size_override("font_size", 11)
		l.add_theme_color_override("font_color", Color("101018"))
		badge.add_child(l)
		row.add_child(badge)
	return row


func _fill_detail() -> void:
	for c in _detail.get_children():
		c.queue_free()
	var s := _svc_ref()
	if s == null:
		return
	var m: Dictionary = s.find(_selected_uid)
	if m.is_empty():
		_detail.add_child(_dl("Select a recruit to review development,\nset a focus, promote or release.", TB.COL_TEXT_DIM))
		_err = _dl("", TB.COL_BAD, 13)
		_detail.add_child(_err)
		return
	var sp: Dictionary = DataStore.species(int(m["species_id"]))
	_detail.add_child(_dl(String(m["species"]), TB.COL_TEXT, 20))
	_detail.add_child(_type_badges(sp.get("types", [])))
	var band: Array = s.potential_stars(m)
	_detail.add_child(_dl("Current  %s" % Academy.star_text(float(m["stars"])), TB.COL_ACCENT.lightened(0.25), 15))
	_detail.add_child(_dl("Potential  %s – %s" % [Academy.star_text(band[0]),
		Academy.star_text(band[1])], GOLD, 15))
	_detail.add_child(_dl("Coach view: %s." % s._pot_note(int(m["pot_max"])), TB.COL_TEXT_DIM, 13))
	_detail.add_child(HSeparator.new())
	_detail.add_child(_dl("Level %d   ·   %s   ·   joined %s" % [int(m["level"]),
		Academy._age_text(int(m["age_months"])), String(m["joined"])], TB.COL_TEXT_DIM, 13))
	_detail.add_child(_dl("Nature %s   ·   %s" % [String(m["nature"]),
		DataStore.ability_name(String(m["ability"]))], TB.COL_TEXT_DIM, 13))
	var ivs: Dictionary = m["ivs"]
	_detail.add_child(_dl("IVs  HP %d  ATK %d  DEF %d  SPA %d  SPD %d  SPE %d" % [
		int(ivs["hp"]), int(ivs["atk"]), int(ivs["def"]), int(ivs["spa"]),
		int(ivs["spd"]), int(ivs["spe"])], TB.COL_TEXT, 13))
	_detail.add_child(_dl("Moves: %s" % ", ".join(m["moves"]), TB.COL_TEXT, 13))
	_detail.add_child(_dl("Next level: %d%%" % int(round(s.dev_progress(m) * 100.0)), TB.COL_GOOD, 13))
	_detail.add_child(HSeparator.new())

	var frow := HBoxContainer.new()
	frow.add_theme_constant_override("separation", 8)
	var fl := _dl("Training focus", TB.COL_TEXT_DIM, 13)
	fl.autowrap_mode = TextServer.AUTOWRAP_OFF
	frow.add_child(fl)
	var opt := OptionButton.new()
	for f in Academy.FOCUSES:
		opt.add_item(Academy.FOCUS_LABELS[f])
	opt.selected = Academy.FOCUSES.find(String(m.get("focus", "balanced")))
	opt.item_selected.connect(func(idx): s.set_focus(_selected_uid, Academy.FOCUSES[idx]))
	frow.add_child(opt)
	_detail.add_child(frow)

	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 8)
	var promote := Button.new()
	promote.text = "Promote to First Team"
	promote.pressed.connect(func():
		var e: String = s.promote(_selected_uid)
		_refresh()
		_err.text = e)
	brow.add_child(promote)
	var rel := Button.new()
	rel.text = "Release"
	rel.pressed.connect(func():
		var e: String = s.release(_selected_uid)
		_refresh()
		_err.text = e)
	brow.add_child(rel)
	_detail.add_child(brow)
	_detail.add_child(_dl("Squad %d/%d — promotion respects the squad cap." % [
		GameState.player_club()["squad"].size(), Academy.FIRST_TEAM_CAP], TB.COL_TEXT_DIM, 12))
	_err = _dl("", TB.COL_BAD, 13)
	_detail.add_child(_err)


# ------------------------------------------------------------------ refresh

func _refresh() -> void:
	var s := _svc_ref()
	if s == null or not is_inside_tree():
		return
	for i in 5:
		var pip: ColorRect = _fac_pips.get_child(i)
		pip.color = TB.COL_ACCENT if i < s.facility_level else TB.COL_BORDER
	_fac_name.text = "Level %d — %s" % [s.facility_level, s.facility_name()]
	_fac_intake.text = "Next intake day: %s   ·   %d–%d recruits/month" % [
		s.next_intake_date(), Academy.INTAKE_MIN[s.facility_level],
		Academy.INTAKE_MAX[s.facility_level]]
	_fac_roster.text = "Academy roster: %d   ·   Head youth coach: %s" % [
		s.roster.size(), s.head_youth_coach()]
	if not s.pending.is_empty():
		_upg_btn.visible = false
		_upg_status.visible = true
		if String(s.pending["status"]) == "pending":
			_upg_status.text = "Board deciding — answer due %s" % String(s.pending["decide_on"])
		else:
			_upg_status.text = "Under construction — opens %s" % String(s.pending["complete_on"])
	elif s.facility_level >= 5:
		_upg_btn.visible = false
		_upg_status.visible = true
		_upg_status.text = "Facilities are state of the art"
	else:
		_upg_btn.visible = true
		_upg_status.visible = false
		_upg_btn.text = "Request Level %d upgrade  (%s)" % [s.facility_level + 1,
			Academy.format_money(s.upgrade_cost())]
	_fill_table(s)
	_fill_history(s)
	_fill_detail()
