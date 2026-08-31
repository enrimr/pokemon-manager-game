extends Control
## FM-style new-career club selector (shell-owned overlay).
##
## Opened from the top-bar menu's "New Career". League tabs across the top
## (Kanto League / Johto League), one row per club showing crest, manager,
## reputation, bank balance and squad strength — pick a club from either
## league and start. Plain boot without a save still defaults to Pallet
## Pioneers (GameState.boot), FM's "pick me a club" equivalent.
##
## The picker reads a FRESH res://shared/data/world.json so the numbers shown
## are exactly what the new career will start with (not the current, drifted
## career state). Emits club_chosen(club_id) / cancelled; the shell drives
## GameState from there.

signal club_chosen(club_id: String)
signal cancelled

const PANEL_W := 1120.0
const PANEL_H := 740.0

var _font_bold: Font
var _font_semibold: Font
var _font_header: Font

var _leagues: Array = []            # [{id, name}]
var _clubs: Dictionary = {}         # league_id -> Array of club summary dicts
var _active_league := ""
var _selected_id := ""
var _default_id := ""               # world.json's default (Pallet Pioneers)

var _rows_box: VBoxContainer
var _start_btn: Button
var _hint_label: Label
var _tab_btns: Dictionary = {}      # league_id -> Button
var _row_panels: Dictionary = {}    # club_id -> PanelContainer


func setup(bold: Font, semibold: Font, header: Font) -> void:
	_font_bold = bold
	_font_semibold = semibold
	_font_header = header


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_load_world()
	_build_ui()
	if not _leagues.is_empty():
		_set_league(str(_leagues[0]["id"]))
	if _default_id != "":
		_select_club(_default_id)


# ------------------------------------------------------------------ data

func _load_world() -> void:
	var f := FileAccess.open("res://shared/data/world.json", FileAccess.READ)
	if f == null:
		return
	var world: Variant = JSON.parse_string(f.get_as_text())
	if typeof(world) != TYPE_DICTIONARY:
		return
	_default_id = str(world["meta"].get("player_club_id", ""))
	_leagues = world["meta"].get("leagues",
		[{"id": "kanto", "name": str(world["meta"].get("league_name", "League"))}])
	# squad strength = average level of the matchday six; star rating is the
	# club's percentile across the WHOLE world (comparable between leagues)
	var summaries: Array = []
	for c in world.get("clubs", []):
		summaries.append(_summarize(c))
	var by_strength := summaries.duplicate()
	by_strength.sort_custom(func(a, b): return float(a["avg6"]) < float(b["avg6"]))
	for i in by_strength.size():
		by_strength[i]["stars"] = 1 + int(floor(float(i) / maxf(1.0, float(by_strength.size())) * 5.0))
	for s in summaries:
		var lid: String = str(s["league"])
		if not _clubs.has(lid):
			_clubs[lid] = []
		_clubs[lid].append(s)
	for lid in _clubs:
		_clubs[lid].sort_custom(func(a, b):
			if int(a["rep"]) != int(b["rep"]):
				return int(a["rep"]) > int(b["rep"])
			return str(a["name"]) < str(b["name"]))


func _summarize(c: Dictionary) -> Dictionary:
	var levels: Array = c.get("squad", []).map(func(m): return int(m["level"]))
	levels.sort()
	levels.reverse()
	var top: Array = levels.slice(0, 6)
	var avg := 0.0
	for l in top:
		avg += float(l)
	avg /= maxf(1.0, float(top.size()))
	return {
		"id": str(c["id"]), "name": str(c["name"]), "short": str(c.get("short", "")),
		"league": str(c.get("league", "kanto")), "manager": str(c.get("manager", "")),
		"rep": int(c.get("reputation", 10)),
		"balance": int(c.get("finances", {}).get("balance", 0)),
		"squad_n": c.get("squad", []).size(),
		"avg6": avg, "stars": 3,
		"type": _primary_type(c),
	}


func _primary_type(c: Dictionary) -> String:
	var counts := {}
	for inst in c.get("squad", []):
		var sp: Dictionary = DataStore.species(int(inst["species_id"]))
		if sp.is_empty():
			continue
		var types: Array = sp.get("types", [])
		if types.size() > 0:
			counts[types[0]] = counts.get(types[0], 0) + 2
		if types.size() > 1:
			counts[types[1]] = counts.get(types[1], 0) + 1
	var best := "normal"
	var best_n := -1
	for t in counts:
		if counts[t] > best_n:
			best_n = counts[t]
			best = t
	return best

# ------------------------------------------------------------------ ui

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	panel.add_theme_stylebox_override("panel",
		ThemeBuilder._flat(ThemeBuilder.COL_PANEL, ThemeBuilder.COL_ACCENT_DIM, 8, 0, 0))
	center.add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	panel.add_child(root)

	root.add_child(_build_header())
	root.add_child(_build_tabs())
	root.add_child(_build_columns())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("separation", 3)
	scroll.add_child(_rows_box)
	var scroll_pad := MarginContainer.new()
	scroll_pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for m in ["margin_left", "margin_right"]:
		scroll_pad.add_theme_constant_override(m, 18)
	scroll_pad.add_theme_constant_override("margin_top", 6)
	scroll_pad.add_child(scroll)
	root.add_child(scroll_pad)

	root.add_child(_build_footer())


func _build_header() -> Control:
	var wrap := PanelContainer.new()
	var sb := ThemeBuilder._flat(ThemeBuilder.COL_PANEL_ALT, ThemeBuilder.COL_BORDER, 0, 22, 14)
	sb.border_width_left = 0
	sb.border_width_right = 0
	sb.border_width_top = 0
	wrap.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	var title := Label.new()
	title.text = "START A NEW CAREER"
	title.add_theme_font_override("font", _font_header)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color.WHITE)
	col.add_child(title)
	var sub := Label.new()
	sub.text = "Choose the club you'll manage — 32 clubs across two leagues, all meeting in the Indigo Cup."
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	col.add_child(sub)
	wrap.add_child(col)
	return wrap


func _build_tabs() -> Control:
	var pad := MarginContainer.new()
	for m in ["margin_left", "margin_right"]:
		pad.add_theme_constant_override(m, 18)
	pad.add_theme_constant_override("margin_top", 14)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for lg in _leagues:
		var lid: String = str(lg["id"])
		var b := Button.new()
		b.text = tr(str(lg["name"])).to_upper()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(220, 38)
		b.add_theme_font_override("font", _font_header)
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(func(): _set_league(lid))
		row.add_child(b)
		_tab_btns[lid] = b
	var note := Label.new()
	note.text = "  %d clubs per league · double round-robin championship" % 16
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	row.add_child(note)
	pad.add_child(row)
	return pad


func _build_columns() -> Control:
	var pad := MarginContainer.new()
	for m in ["margin_left", "margin_right"]:
		pad.add_theme_constant_override(m, 18)
	pad.add_theme_constant_override("margin_top", 12)
	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel",
		ThemeBuilder._flat(ThemeBuilder.COL_PANEL_ALT, ThemeBuilder.COL_BORDER, 4, 12, 5))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	for spec in [["CLUB", 330.0], ["MANAGER", 180.0], ["REPUTATION", 170.0],
			["BALANCE", 130.0], ["SQUAD STRENGTH", 0.0]]:
		var l := Label.new()
		l.text = str(spec[0])
		l.add_theme_font_override("font", _font_header)
		l.add_theme_font_size_override("font_size", 11)
		l.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
		if float(spec[1]) > 0.0:
			l.custom_minimum_size.x = float(spec[1])
		else:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
	head.add_child(row)
	pad.add_child(head)
	return pad


func _build_footer() -> Control:
	var wrap := PanelContainer.new()
	var sb := ThemeBuilder._flat(ThemeBuilder.COL_PANEL_ALT, ThemeBuilder.COL_BORDER, 0, 18, 12)
	sb.border_width_left = 0
	sb.border_width_right = 0
	sb.border_width_bottom = 0
	wrap.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_hint_label = Label.new()
	_hint_label.text = "Starting a new career deletes the current save."
	_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hint_label.add_theme_font_size_override("font_size", 12)
	_hint_label.add_theme_color_override("font_color", ThemeBuilder.COL_WARN)
	row.add_child(_hint_label)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(110, 40)
	cancel.pressed.connect(func():
		cancelled.emit()
		queue_free())
	row.add_child(cancel)
	_start_btn = Button.new()
	_start_btn.text = "Start Career"
	_start_btn.disabled = true
	_start_btn.custom_minimum_size = Vector2(260, 40)
	_start_btn.add_theme_font_override("font", _font_bold)
	_start_btn.add_theme_font_size_override("font_size", 15)
	_start_btn.pressed.connect(func():
		if _selected_id != "":
			club_chosen.emit(_selected_id))
	row.add_child(_start_btn)
	wrap.add_child(row)
	return wrap


# ------------------------------------------------------------------ rows

func _set_league(lid: String) -> void:
	_active_league = lid
	for t in _tab_btns:
		var b: Button = _tab_btns[t]
		b.set_pressed_no_signal(t == lid)
		b.add_theme_color_override("font_color",
			Color.WHITE if t == lid else ThemeBuilder.COL_TEXT_DIM)
	for child in _rows_box.get_children():
		child.queue_free()
	_row_panels.clear()
	for s in _clubs.get(lid, []):
		_rows_box.add_child(_club_row(s))
	_apply_selection_styles()


func _club_row(s: Dictionary) -> Control:
	var cid: String = str(s["id"])
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			if _selected_id == cid and ev.double_click:
				club_chosen.emit(cid)
			else:
				_select_club(cid))
	_row_panels[cid] = panel

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)

	# club: crest + name + short
	var club_cell := HBoxContainer.new()
	club_cell.custom_minimum_size.x = 330
	club_cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	club_cell.add_theme_constant_override("separation", 10)
	club_cell.add_child(_crest(s, 34))
	var name_col := VBoxContainer.new()
	name_col.alignment = BoxContainer.ALIGNMENT_CENTER
	name_col.add_theme_constant_override("separation", 0)
	name_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nm := Label.new()
	nm.text = str(s["name"])
	nm.add_theme_font_override("font", _font_bold)
	nm.add_theme_font_size_override("font_size", 14)
	nm.add_theme_color_override("font_color", Color.WHITE)
	name_col.add_child(nm)
	var sub := Label.new()
	sub.text = tr("%s · %d in squad") % [str(s["short"]), int(s["squad_n"])]
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	name_col.add_child(sub)
	club_cell.add_child(name_col)
	row.add_child(club_cell)

	# manager
	var mgr := Label.new()
	mgr.text = str(s["manager"])
	mgr.custom_minimum_size.x = 180
	mgr.add_theme_font_size_override("font_size", 13)
	mgr.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT)
	row.add_child(mgr)

	# reputation: number + bar
	var rep_cell := HBoxContainer.new()
	rep_cell.custom_minimum_size.x = 170
	rep_cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rep_cell.add_theme_constant_override("separation", 8)
	var rep_n := Label.new()
	rep_n.text = "%d" % int(s["rep"])
	rep_n.custom_minimum_size.x = 22
	rep_n.add_theme_font_override("font", _font_semibold)
	rep_n.add_theme_font_size_override("font_size", 13)
	rep_n.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT)
	rep_cell.add_child(rep_n)
	rep_cell.add_child(_meter(float(s["rep"]) / 20.0, ThemeBuilder.COL_ACCENT))
	row.add_child(rep_cell)

	# balance
	var bal := Label.new()
	bal.text = "P$ %s" % _thousands(int(s["balance"]))
	bal.custom_minimum_size.x = 130
	bal.add_theme_font_size_override("font_size", 13)
	bal.add_theme_color_override("font_color", ThemeBuilder.COL_GOOD)
	row.add_child(bal)

	# squad strength: stars + avg level of the matchday six
	var str_cell := HBoxContainer.new()
	str_cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	str_cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	str_cell.add_theme_constant_override("separation", 8)
	var stars := Label.new()
	var n := clampi(int(s["stars"]), 1, 5)
	stars.text = "★".repeat(n) + "☆".repeat(5 - n)
	stars.add_theme_font_size_override("font_size", 14)
	stars.add_theme_color_override("font_color", ThemeBuilder.COL_WARN)
	str_cell.add_child(stars)
	var avg := Label.new()
	avg.text = tr("top six avg Lv %.0f") % float(s["avg6"])
	avg.add_theme_font_size_override("font_size", 12)
	avg.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	str_cell.add_child(avg)
	row.add_child(str_cell)

	panel.add_child(row)
	return panel


func _select_club(cid: String) -> void:
	_selected_id = cid
	var s := _find_summary(cid)
	if _start_btn != null:
		_start_btn.disabled = s.is_empty()
		if not s.is_empty():
			_start_btn.text = tr("Start at %s") % str(s["name"])
	_apply_selection_styles()


func _find_summary(cid: String) -> Dictionary:
	for lid in _clubs:
		for s in _clubs[lid]:
			if str(s["id"]) == cid:
				return s
	return {}


func _apply_selection_styles() -> void:
	for cid in _row_panels:
		var selected: bool = str(cid) == _selected_id
		var bg: Color = ThemeBuilder.COL_ACCENT_DIM if selected else ThemeBuilder.COL_PANEL_ALT
		var border: Color = ThemeBuilder.COL_ACCENT if selected else ThemeBuilder.COL_BORDER
		(_row_panels[cid] as PanelContainer).add_theme_stylebox_override("panel",
			ThemeBuilder._flat(bg, border, 5, 10, 7))


func _crest(s: Dictionary, px: int) -> Control:
	var col: Color = DataStore.type_color(str(s["type"]))
	var crest := PanelContainer.new()
	crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crest.custom_minimum_size = Vector2(px, px)
	var sb := StyleBoxFlat.new()
	sb.bg_color = col.darkened(0.25)
	sb.border_color = col.lightened(0.25)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(px / 4)
	crest.add_theme_stylebox_override("panel", sb)
	var letter := Label.new()
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	letter.add_theme_font_override("font", _font_header)
	letter.add_theme_font_size_override("font_size", int(px * 0.32))
	letter.add_theme_color_override("font_color", Color.WHITE)
	letter.text = str(s["short"])
	crest.add_child(letter)
	return crest


func _meter(frac: float, col: Color) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(110, 8)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := ColorRect.new()
	bg.color = ThemeBuilder.COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(bg)
	var fill := ColorRect.new()
	fill.color = col
	fill.anchor_right = clampf(frac, 0.02, 1.0)
	fill.anchor_bottom = 1.0
	holder.add_child(fill)
	return holder


func _thousands(n: int) -> String:
	return ("-" if n < 0 else "") + I18n.number(absi(n))
