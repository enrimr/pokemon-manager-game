extends Control
## Training screen — owned by the "training" piece.
## Five tabs, FM-style: Schedule (dated calendar), Individual (per-Pokémon
## focus + move learning), Coaches (staff assignments + workload), Mentoring
## (veteran » junior groups), Development (deltas + attribution).
## All model logic lives in training_service.gd (kept alive at /root).

const TrainingServiceScript := preload("res://screens/training/training_service.gd")
const EvoSvc := preload("res://shared/sim/services/evolution.gd")

const FOCUS_COLORS := {
	"physical": Color("e06868"), "special": Color("f085b0"), "defense": Color("6890f0"),
	"speed": Color("e8cf50"), "technique": Color("9b8cff"), "match_prep": Color("58b8d8"),
	"rest": Color("57c979"), "match": Color("e0b050"),
}

var svc: Node

var _tab_buttons: Dictionary = {}
var _tabs: Dictionary = {}
var _current_tab := "schedule"

# schedule tab
var _cal_box: VBoxContainer          # one GridContainer per visible week
var _cal_scroll: ScrollContainer
var _week_title: Label
var _view_buttons: Dictionary = {}   # weeks(int) -> Button
var _auto_check: CheckButton
var _summary_box: VBoxContainer
var _status_tree: Tree

# individual tab
var _ind_tree: Tree
var _detail_box: VBoxContainer
var _selected_uid := ""
var _move_dialog: AcceptDialog
var _move_list: ItemList
var _slot_option: OptionButton
var _move_eta_label: Label
var _dialog_moves: Array = []

# coaches tab
var _coach_cards_box: VBoxContainer
var _assign_box: VBoxContainer

# mentoring tab
var _groups_box: VBoxContainer
var _mentor_side: VBoxContainer

const PERSONALITY_COLORS := {
	"driven": Color("e06868"), "calm": Color("f085b0"), "stoic": Color("6890f0"),
	"lively": Color("e8cf50"), "studious": Color("9b8cff"), "professional": Color("58b8d8"),
}

# development tab
var _dev_tree: Tree
var _best_box: VBoxContainer
var _stag_box: VBoxContainer
var _dev_note: Label


func _ready() -> void:
	svc = TrainingServiceScript.ensure()
	if not svc.training_changed.is_connected(_on_training_changed):
		svc.training_changed.connect(_on_training_changed)
	_build_layout()
	_refresh_all()


func on_show() -> void:
	_refresh_all()


func _exit_tree() -> void:
	if svc != null and svc.training_changed.is_connected(_on_training_changed):
		svc.training_changed.disconnect(_on_training_changed)


func _on_training_changed() -> void:
	if is_inside_tree():
		_refresh_all()


# ================================================================== layout

func _build_layout() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	# --- header
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	root.add_child(head)
	var title := Label.new()
	title.text = "Training"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color.WHITE)
	head.add_child(title)
	var sub := Label.new()
	sub.text = tr("%s  ·  %d Pokémon  ·  %d coaches") % [GameState.player_club()["name"],
		svc.squad().size(), svc.coaching_staff().size()]
	sub.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	sub.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(sub)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)

	# --- tab bar
	var tabbar := HBoxContainer.new()
	tabbar.add_theme_constant_override("separation", 4)
	root.add_child(tabbar)
	for t in [["schedule", "Schedule"], ["individual", "Individual"],
			["coaches", "Coaches"], ["mentoring", "Mentoring"], ["development", "Development"]]:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(150, 34)
		b.pressed.connect(_switch_tab.bind(t[0]))
		tabbar.add_child(b)
		_tab_buttons[t[0]] = b

	# --- tab contents
	_tabs["schedule"] = _build_schedule_tab()
	_tabs["individual"] = _build_individual_tab()
	_tabs["coaches"] = _build_coaches_tab()
	_tabs["mentoring"] = _build_mentoring_tab()
	_tabs["development"] = _build_development_tab()
	for k in _tabs:
		_tabs[k].size_flags_vertical = Control.SIZE_EXPAND_FILL
		root.add_child(_tabs[k])
	_switch_tab("schedule")
	_build_move_dialog()


func _switch_tab(tab: String) -> void:
	_current_tab = tab
	for k in _tabs:
		_tabs[k].visible = (k == tab)
		_tab_buttons[k].button_pressed = (k == tab)
	_refresh_all()


func _refresh_all() -> void:
	match _current_tab:
		"schedule":
			_refresh_schedule()
		"individual":
			_refresh_individual()
		"coaches":
			_refresh_coaches()
		"mentoring":
			_refresh_mentoring()
		"development":
			_refresh_development()


# ================================================================== helpers

func _panel(title: String = "") -> Array:
	var p := PanelContainer.new()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	if title != "":
		var l := Label.new()
		l.text = title.to_upper()
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", ThemeBuilder.COL_ACCENT)
		v.add_child(l)
	return [p, v]


func _mini_bar(frac: float, col: Color, w: float = 90.0) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(w, 12)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bg := ColorRect.new()
	bg.color = Color("11141d")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(bg)
	var fg := ColorRect.new()
	fg.color = col
	fg.anchor_bottom = 1.0
	fg.anchor_right = clampf(frac, 0.0, 1.0)
	fg.offset_left = 1
	fg.offset_top = 1
	fg.offset_bottom = -1
	holder.add_child(fg)
	return holder


func _monogram(inst: Dictionary, size: float = 40.0) -> Control:
	var sp: Dictionary = DataStore.species(int(inst["species_id"]))
	var t0: String = sp["types"][0]
	var badge := Panel.new()
	badge.custom_minimum_size = Vector2(size, size)
	var sb := StyleBoxFlat.new()
	sb.bg_color = DataStore.type_color(t0).darkened(0.25)
	sb.border_color = DataStore.type_color(t0)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(int(size / 2.0))
	badge.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.text = str(sp["name"]).substr(0, 2).to_upper()
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_font_size_override("font_size", int(size * 0.38))
	badge.add_child(l)
	return badge


func _type_chip(t: String) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = DataStore.type_color(t).darkened(0.45)
	sb.border_color = DataStore.type_color(t)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = t.to_upper()
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color.WHITE)
	p.add_child(l)
	return p


func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


func _age_str(months: int) -> String:
	return tr("%dy %dm") % [months / 12, months % 12]


func _strain_color(s: float) -> Color:
	if s > 70.0:
		return ThemeBuilder.COL_BAD
	if s > 45.0:
		return ThemeBuilder.COL_WARN
	return ThemeBuilder.COL_GOOD


func _dev_stage(age_months: int) -> Array:
	var m: float = svc.age_mult(age_months)
	if m >= 1.25:
		return [tr("Rapid developer"), ThemeBuilder.COL_GOOD]
	if m >= 1.05:
		return [tr("Developing well"), ThemeBuilder.COL_GOOD]
	if m >= 0.85:
		return ["Steady", ThemeBuilder.COL_TEXT]
	if m >= 0.55:
		return [tr("Development slowing"), ThemeBuilder.COL_WARN]
	return [tr("Veteran — minimal growth"), ThemeBuilder.COL_BAD]


func _display_name(inst: Dictionary) -> String:
	var nn = inst.get("nickname")
	return str(nn) if nn else str(inst.get("species", "?"))


# ================================================================== SCHEDULE

func _build_schedule_tab() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var left_wrap := _panel(tr("Training calendar"))
	var left: VBoxContainer = left_wrap[1]
	(left_wrap[0] as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left_wrap[0])

	# Flow: the toolbar wraps on narrow widths / wide locales instead of
	# forcing a minimum width that shoves the right rail off the screen.
	var week_row := HFlowContainer.new()
	week_row.add_theme_constant_override("h_separation", 12)
	left.add_child(week_row)
	_week_title = Label.new()
	_week_title.add_theme_font_size_override("font_size", 15)
	_week_title.add_theme_color_override("font_color", Color.WHITE)
	week_row.add_child(_week_title)
	var vlab := Label.new()
	vlab.text = "View:"
	vlab.add_theme_font_size_override("font_size", 12)
	vlab.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	vlab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	week_row.add_child(vlab)
	for w in [1, 2, 4]:
		var vb := Button.new()
		vb.text = tr("%d week%s") % [w, "" if w == 1 else "s"]
		vb.toggle_mode = true
		vb.custom_minimum_size = Vector2(76, 28)
		vb.pressed.connect(func():
			svc.set_view_weeks(w)
			_refresh_schedule.call_deferred())
		week_row.add_child(vb)
		_view_buttons[w] = vb
	var wsp := Control.new()
	wsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	week_row.add_child(wsp)
	_auto_check = CheckButton.new()
	_auto_check.text = tr("Auto-adjust around matches")
	_auto_check.tooltip_text = tr("When on: no field training on matchday (warm-up only), a recovery day the morning after, and a light Match Prep day before a fixture — all editable per date; your date edits win.\nWhen off: your plan runs straight into matches — strain will spike.")
	_auto_check.toggled.connect(func(on: bool):
		svc.set_auto_match(on)
		_refresh_schedule.call_deferred())
	week_row.add_child(_auto_check)

	_cal_scroll = ScrollContainer.new()
	_cal_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_cal_scroll.size_flags_stretch_ratio = 1.5
	_cal_scroll.custom_minimum_size.y = 240
	_cal_box = VBoxContainer.new()
	_cal_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cal_box.add_theme_constant_override("separation", 10)
	_cal_scroll.add_child(_cal_box)
	left.add_child(_cal_scroll)

	left.add_child(HSeparator.new())
	var presets := HFlowContainer.new()
	presets.add_theme_constant_override("h_separation", 8)
	presets.add_theme_constant_override("v_separation", 4)
	left.add_child(presets)
	var pl := Label.new()
	pl.text = tr("Weekday template presets:")
	pl.tooltip_text = tr("Rewrites the repeating weekday DEFAULT. To plan one specific future week instead, use that week's Plan menu on the calendar.")
	pl.mouse_filter = Control.MOUSE_FILTER_STOP
	pl.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	presets.add_child(pl)
	for p in svc.PRESETS:
		var b := Button.new()
		b.text = str(svc.PRESET_LABELS[p])
		b.tooltip_text = tr("Sets the repeating weekday template. Per-date edits on the calendar stay in place on top of it.")
		b.pressed.connect(func():
			svc.apply_preset(p)
			_refresh_schedule())
		presets.add_child(b)

	var legend := Label.new()
	legend.text = tr("Every cell edits THAT DATE only (violet = date-specific plan; Template default resets it). Use a week's Plan menu to stamp a preset on just that week — a recovery week before a congested block, a heavy development block, opponent prep — or to save it as the template. Fixtures embed automatically (amber): matchday is locked, the days around it default to recovery/prep but your date edits win. High intensity trains faster but builds strain; each Pokémon also carries its own load below (Automatic rests above %d%% strain, eases above %d%%).") % [int(svc.AUTO_REST_AT), int(svc.AUTO_LIGHT_AT)]
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legend.add_theme_font_size_override("font_size", 12)
	legend.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	left.add_child(legend)

	left.add_child(HSeparator.new())
	var stl := Label.new()
	stl.text = tr("SQUAD TRAINING STATUS")
	stl.add_theme_font_size_override("font_size", 12)
	stl.add_theme_color_override("font_color", ThemeBuilder.COL_ACCENT)
	left.add_child(stl)
	_status_tree = Tree.new()
	_status_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_status_tree.columns = 10
	_status_tree.column_titles_visible = true
	_status_tree.hide_root = true
	var st_titles := ["Pokémon", "Lv", "Age", "Stage", "Workload", "Strain", "7d Δ", "Fitness", "Focus", "Learning"]
	var st_widths := [150, 40, 56, 132, 128, 58, 56, 60, 74, 130]
	for i in st_titles.size():
		_status_tree.set_column_title(i, st_titles[i])
		_status_tree.set_column_expand(i, i == 0 or i == 3 or i == 9)
		if i > 0:
			_status_tree.set_column_custom_minimum_width(i, st_widths[i])
	_status_tree.item_edited.connect(_on_status_load_edited)
	_status_tree.tooltip_text = tr("Load: each Pokémon's own training intensity — click the cell to change it. 7d Δ: its projected net strain this week at that load.")
	left.add_child(_status_tree)

	var right_wrap := _panel(tr("This week · fixtures & load"))
	(right_wrap[0] as Control).custom_minimum_size.x = 360
	_summary_box = right_wrap[1]
	row.add_child(right_wrap[0])
	return row


func _on_date_session_pick(idx: int, date: String, slot: String) -> void:
	if idx < svc.FOCUSES.size():
		svc.set_date_session(date, slot, svc.FOCUSES[idx])
	else:
		svc.clear_date_slot(date, slot)  # tr("Template default")
	_refresh_schedule.call_deferred()


func _on_date_intensity_pick(idx: int, date: String) -> void:
	if idx < svc.INTENSITIES.size():
		svc.set_date_intensity(date, svc.INTENSITIES[idx])
	else:
		svc.clear_date_slot(date, "intensity")
	_refresh_schedule.call_deferred()


func _on_week_menu(id: int, start_date: String) -> void:
	if id < svc.PRESETS.size():
		svc.apply_preset_to_week(svc.PRESETS[id], start_date)
	elif id == 100:
		svc.clear_week_overrides(start_date)
	elif id == 101:
		svc.save_week_as_template(start_date)
	_refresh_schedule.call_deferred()


func _tint_focus_button(ob: OptionButton, focus: String) -> void:
	ob.add_theme_color_override("font_color", FOCUS_COLORS.get(focus, ThemeBuilder.COL_TEXT))


func _row_label(text: String, tip: String = "") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	if tip != "":
		l.tooltip_text = tip
		l.mouse_filter = Control.MOUSE_FILTER_STOP
	return l


func _locked_cell(text: String, col: Color, tip: String, strong: bool = false) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(112, 34)
	var sb := StyleBoxFlat.new()
	sb.bg_color = col.darkened(0.72) if strong else Color("161a26")
	sb.border_color = col if strong else col.darkened(0.35)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	p.add_theme_stylebox_override("panel", sb)
	p.tooltip_text = tip
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", col)
	p.add_child(l)
	return p


func _day_header(plan: Dictionary) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	var is_today: bool = plan["date"] == GameState.current_date
	var is_match: bool = not (plan["fixture"] as Dictionary).is_empty()
	var top := Label.new()
	top.text = tr(str(svc.DAY_LABELS[plan["day"]])).substr(0, 3).to_upper() + (("  · " + tr("TODAY")) if is_today else "")
	top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_theme_font_size_override("font_size", 12)
	top.add_theme_color_override("font_color",
		ThemeBuilder.COL_ACCENT if is_today else (ThemeBuilder.COL_WARN if is_match else ThemeBuilder.COL_TEXT))
	v.add_child(top)
	var parts: PackedStringArray = str(plan["date"]).split("-")
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var ov: Dictionary = plan.get("ov", {})
	var edited := false
	for k in ov:
		if bool(ov[k]):
			edited = true
	var bot := Label.new()
	bot.text = "%d %s" % [int(parts[2]), tr(months[int(parts[1]) - 1])] + ("  •" if edited else "")
	bot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bot.add_theme_font_size_override("font_size", 11)
	bot.add_theme_color_override("font_color", OVERRIDE_COL if edited else ThemeBuilder.COL_TEXT_DIM)
	if edited:
		bot.tooltip_text = tr("This date has its own plan (differs from the weekday template).")
		bot.mouse_filter = Control.MOUSE_FILTER_STOP
	v.add_child(bot)
	return v


func _fixture_cell(plan: Dictionary) -> Control:
	var fx: Dictionary = plan["fixture"]
	if fx.is_empty():
		var dash := Label.new()
		dash.text = "—"
		dash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dash.add_theme_color_override("font_color", Color("3a4058"))
		return dash
	var opp: Dictionary = svc.opponent_of(fx)
	var home: bool = svc.fixture_is_home(fx)
	var comp := tr("League R%d") % int(fx["round"]) if str(fx["comp"]) == "league" else tr("Cup R%d") % int(fx["round"])
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(112, 38)
	var sb := StyleBoxFlat.new()
	sb.bg_color = ThemeBuilder.COL_WARN.darkened(0.78)
	sb.border_color = ThemeBuilder.COL_WARN
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	p.add_theme_stylebox_override("panel", sb)
	p.tooltip_text = "%s %s, %s — %s" % ["vs" if home else "at", opp["name"], comp,
		I18n.pretty_date(str(fx["date"]))]
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	var l1 := Label.new()
	l1.text = "%s %s" % [tr("vs") if home else tr("at"), str(opp.get("short", opp["name"]))]
	l1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l1.add_theme_font_size_override("font_size", 12)
	l1.add_theme_color_override("font_color", Color.WHITE)
	v.add_child(l1)
	var l2 := Label.new()
	if bool(fx["played"]):
		var us := int(fx["score_home"] if home else fx["score_away"])
		var them := int(fx["score_away"] if home else fx["score_home"])
		l2.text = "%s %d-%d" % ["W" if us > them else "L", us, them]
		l2.add_theme_color_override("font_color",
			ThemeBuilder.COL_GOOD if us > them else ThemeBuilder.COL_BAD)
	else:
		l2.text = comp
		l2.add_theme_color_override("font_color", ThemeBuilder.COL_WARN)
	l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l2.add_theme_font_size_override("font_size", 11)
	v.add_child(l2)
	p.add_child(v)
	return p


const OVERRIDE_COL := Color("b28cff")  # violet: date-specific plan marker


## Wrap an editable cell in a violet border when that slot has a per-date edit.
func _override_wrap(inner: Control, tip: String) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = OVERRIDE_COL.darkened(0.86)
	sb.border_color = OVERRIDE_COL
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(1)
	p.add_theme_stylebox_override("panel", sb)
	p.tooltip_text = tip
	p.add_child(inner)
	return p


func _session_cell(plan: Dictionary, slot: String) -> Control:
	var kind: String = plan["kind"]
	var date: String = plan["date"]
	var focus := str(plan[slot])
	if kind == "matchday":
		if slot == "am":
			return _locked_cell("Warm-up", FOCUS_COLORS["match_prep"],
				"Matchday: only a light pre-match warm-up — no field training (locked).")
		return _locked_cell("MATCH", ThemeBuilder.COL_WARN,
			tr("The fixture itself. Starters take heavy strain from playing."), true)
	var overridden: bool = bool((plan["ov"] as Dictionary)[slot])
	var ob := OptionButton.new()
	ob.custom_minimum_size = Vector2(112, 30)
	ob.fit_to_longest_item = false
	ob.clip_text = true
	for f in svc.FOCUSES:
		ob.add_item(svc.FOCUS_LABELS[f])
	ob.add_item(tr("Template default"))
	ob.set_item_icon(ob.item_count - 1, GlyphIcons.tex("undo", 10, ThemeBuilder.COL_TEXT_DIM))
	ob.select(svc.FOCUSES.find(focus))
	_tint_focus_button(ob, focus)
	var tpl_focus: String = svc.state["schedule"][plan["day"]][slot]
	var tip := tr("Edits %s %s ONLY (per-date plan).") % [I18n.pretty_date(date), slot.to_upper()]
	if overridden:
		tip += tr("\nDate-specific: %s (template default: %s). Template default resets it.") % [
			svc.FOCUS_LABELS[focus], svc.FOCUS_LABELS[tpl_focus]]
	elif kind == "post_match":
		tip += "\nAuto: recovery after yesterday's match — pick a focus to override this date."
	elif kind == "pre_match" and slot == "pm":
		tip += tr("\nAuto: Match Prep for tomorrow's fixture — pick a focus to override this date.")
	else:
		tip += tr("\nCurrently the %s template default.") % svc.DAY_LABELS[plan["day"]]
	ob.tooltip_text = tip
	ob.item_selected.connect(_on_date_session_pick.bind(date, slot))
	return _override_wrap(ob, tip) if overridden else ob


func _intensity_cell(plan: Dictionary) -> Control:
	var date: String = plan["date"]
	if plan["kind"] == "matchday":
		return _locked_cell("—", Color("3a4058"), tr("No training intensity on matchday."))
	var overridden: bool = bool((plan["ov"] as Dictionary)["intensity"])
	var ob := OptionButton.new()
	ob.custom_minimum_size = Vector2(112, 28)
	ob.fit_to_longest_item = false
	ob.clip_text = true
	for i in svc.INTENSITIES:
		ob.add_item(svc.INTENSITY_LABELS[i])
	ob.add_item(tr("Default"))
	ob.set_item_icon(ob.item_count - 1, GlyphIcons.tex("undo", 10, ThemeBuilder.COL_TEXT_DIM))
	ob.select(svc.INTENSITIES.find(str(plan["intensity"])))
	var tip := tr("Intensity for %s ONLY.") % I18n.pretty_date(date)
	if overridden:
		tip += tr("\nDate-specific: %s. Default resets it.") % svc.INTENSITY_LABELS[plan["intensity"]]
	elif plan["kind"] == "post_match" or plan["kind"] == "pre_match":
		tip += tr("\nAuto: Light around the fixture — pick to override this date.")
	ob.tooltip_text = tip
	ob.item_selected.connect(_on_date_intensity_pick.bind(date))
	return _override_wrap(ob, tip) if overridden else ob


func _week_menu(week_idx: int, start_date: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	var l := Label.new()
	l.text = tr("THIS WEEK") if week_idx == 0 else tr("WEEK +%d") % week_idx
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", ThemeBuilder.COL_ACCENT if week_idx == 0 else ThemeBuilder.COL_TEXT_DIM)
	v.add_child(l)
	var mb := MenuButton.new()
	mb.text = tr("Plan")
	mb.icon = GlyphIcons.tex("caret_down", 9, ThemeBuilder.COL_TEXT)
	mb.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mb.flat = false
	mb.custom_minimum_size = Vector2(74, 26)
	mb.tooltip_text = tr("Plan THIS specific week: stamp a preset on it (per-date, template untouched), reset it to the template, or save it as the new weekday template.")
	var pop := mb.get_popup()
	for i in svc.PRESETS.size():
		pop.add_item(tr("Preset: %s") % svc.PRESET_LABELS[svc.PRESETS[i]], i)
	pop.add_separator()
	pop.add_item(tr("Reset week to template"), 100)
	pop.add_item(tr("Save week as template"), 101)
	pop.id_pressed.connect(_on_week_menu.bind(start_date))
	v.add_child(mb)
	return v


func _week_grid(week_idx: int, dates: Array) -> Control:
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 5)
	var plans: Array = dates.map(func(d): return svc.effective_plan(d))

	grid.add_child(_week_menu(week_idx, str(dates[0])))
	for plan in plans:
		grid.add_child(_day_header(plan))

	grid.add_child(_row_label("FIXTURE"))
	for plan in plans:
		grid.add_child(_fixture_cell(plan))

	for slot in ["am", "pm"]:
		grid.add_child(_row_label(str(slot).to_upper()))
		for plan in plans:
			grid.add_child(_session_cell(plan, slot))

	grid.add_child(_row_label("INTENSITY"))
	for plan in plans:
		grid.add_child(_intensity_cell(plan))

	grid.add_child(_row_label(tr("NET STRAIN"),
		"Estimated strain change per Pokémon for that day, including match load (negative = recovering)."))
	for plan in plans:
		var dload: float = svc.day_strain_load(str(plan["date"]))
		var lab := Label.new()
		lab.text = "%+.0f" % dload
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.add_theme_font_size_override("font_size", 12)
		lab.add_theme_color_override("font_color",
			ThemeBuilder.COL_GOOD if dload < 0 else (ThemeBuilder.COL_WARN if dload < 8 else ThemeBuilder.COL_BAD))
		grid.add_child(lab)
	return grid


func _refresh_schedule() -> void:
	if _cal_box == null or not is_instance_valid(_cal_box):
		return
	var weeks: int = svc.view_weeks()
	var all_dates: Array = svc.calendar_dates(weeks)
	_week_title.text = "%s  —  %s" % [I18n.pretty_date(all_dates[0]),
		I18n.pretty_date(all_dates[all_dates.size() - 1])]
	for w in _view_buttons:
		(_view_buttons[w] as Button).set_pressed_no_signal(int(w) == weeks)
	_auto_check.set_pressed_no_signal(bool(svc.state.get("auto_match", true)))
	_clear(_cal_box)
	for w in weeks:
		_cal_box.add_child(_week_grid(w, all_dates.slice(w * 7, w * 7 + 7)))
		if w < weeks - 1:
			_cal_box.add_child(HSeparator.new())

	_refresh_status_tree()
	_refresh_schedule_summary()


func _on_status_load_edited() -> void:
	var it := _status_tree.get_edited()
	if it == null or _status_tree.get_edited_column() != 4:
		return
	var idx := int(it.get_range(4))
	if idx >= 0 and idx < svc.LOADS.size():
		svc.set_load(str(it.get_metadata(0)), svc.LOADS[idx])
	_refresh_schedule.call_deferred()


func _load_column_options(inst: Dictionary) -> String:
	# First entry shows what Automatic resolves to right now for THIS Pokémon.
	var opts: Array = ["Auto » %s" % tr(str(svc.LOAD_LABELS[svc.resolve_auto_load(inst)]))]
	for i in range(1, svc.LOADS.size()):
		opts.append(tr(str(svc.LOAD_LABELS[svc.LOADS[i]])))
	return ",".join(opts)


func _refresh_status_tree() -> void:
	_status_tree.clear()
	var root := _status_tree.create_item()
	for inst in svc.squad():
		var it := _status_tree.create_item(root)
		var sp: Dictionary = DataStore.species(int(inst["species_id"]))
		var ms: Dictionary = svc.mon_state(inst["uid"])
		it.set_metadata(0, str(inst["uid"]))
		it.set_text(0, _display_name(inst))
		it.set_custom_color(0, DataStore.type_color(sp["types"][0]).lightened(0.25))
		it.set_text(1, str(int(inst["level"])))
		it.set_text(2, _age_str(int(inst["age_months"])))
		it.set_custom_color(2, ThemeBuilder.COL_TEXT_DIM)
		var stage: Array = _dev_stage(int(inst["age_months"]))
		it.set_text(3, stage[0])
		it.set_custom_color(3, stage[1])
		# --- per-Pokémon workload: editable dropdown right in the table
		var setting: String = svc.load_setting(str(inst["uid"]))
		var reaction: String = svc.workload_reaction(inst)
		it.set_cell_mode(4, TreeItem.CELL_MODE_RANGE)
		it.set_text(4, _load_column_options(inst))
		it.set_range(4, maxi(0, svc.LOADS.find(setting)))
		it.set_editable(4, true)
		if reaction == "overworked":
			it.set_custom_color(4, ThemeBuilder.COL_BAD)
		elif reaction == "wants_more":
			it.set_custom_color(4, ThemeBuilder.COL_WARN)
		else:
			it.set_custom_color(4, ThemeBuilder.COL_TEXT_DIM if setting == "auto" else ThemeBuilder.COL_ACCENT)
		it.set_tooltip_text(4, _load_tooltip(inst, setting, reaction))
		var s: float = svc.strain(inst["uid"])
		it.set_text(5, "%d%%" % int(s))
		it.set_custom_color(5, _strain_color(s))
		var wk: float = svc.personal_week_strain(inst)
		it.set_text(6, "%+.0f" % wk)
		it.set_custom_color(6,
			ThemeBuilder.COL_GOOD if wk < 0.0 else (ThemeBuilder.COL_WARN if wk < 10.0 else ThemeBuilder.COL_BAD))
		it.set_tooltip_text(6, tr("Projected net strain over the next 7 days at %s load%s.") % [
			tr(str(svc.LOAD_LABELS[svc.effective_load(inst)])),
			tr(" (likely starter — carries match strain)") if svc.likely_starter_uids().has(str(inst["uid"])) else ""])
		var fit := int(inst.get("fitness", 0))
		it.set_text(7, "%d%%" % fit)
		it.set_custom_color(7, ThemeBuilder.COL_GOOD if fit >= 85 else (ThemeBuilder.COL_WARN if fit >= 65 else ThemeBuilder.COL_BAD))
		var focus: String = ms.get("focus", "")
		it.set_text(8, svc.STAT_LABELS.get(focus, "—") if focus != "" else "—")
		it.set_custom_color(8, ThemeBuilder.COL_ACCENT if focus != "" else Color("3a4058"))
		if ms["move"] != null:
			it.set_text(9, "%s · %d%%" % [ms["move"]["name"], int(ms["move"]["progress"])])
			it.set_custom_color(9, ThemeBuilder.COL_GOOD)
		else:
			it.set_text(9, "—")
			it.set_custom_color(9, Color("3a4058"))


func _load_tooltip(inst: Dictionary, setting: String, reaction: String) -> String:
	var eff: String = svc.effective_load(inst)
	var txt := ""
	if setting == "auto":
		txt = tr("Automatic » %s (%s).") % [tr(str(svc.LOAD_LABELS[eff])), svc.auto_load_reason(inst)]
	else:
		txt = tr("Manual override: %s (×%.2f development, ×%.2f strain).") % [tr(str(svc.LOAD_LABELS[eff])),
			float(svc.LOAD_MULT[eff]), float(svc.LOAD_STRAIN[eff])]
	if reaction == "overworked":
		txt += I18n.t("\nReacting badly: overworked at %d%% strain — morale dropping, injury risk up.") % int(svc.strain(str(inst["uid"])))
	elif reaction == "wants_more":
		txt += tr("\nUnhappy: fresh rapid developer being held back — wants to train more.")
	return txt


func _refresh_schedule_summary() -> void:
	_clear(_summary_box)

	# --- upcoming fixtures embedded in the training week
	var fl := Label.new()
	fl.text = tr("UPCOMING FIXTURES · 14 DAYS")
	fl.add_theme_font_size_override("font_size", 11)
	fl.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	_summary_box.add_child(fl)
	var upcoming: Array = svc.upcoming_player_fixtures(14)
	if upcoming.is_empty():
		var none := Label.new()
		none.text = tr("No fixtures in the next two weeks — a free run of full training.")
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.add_theme_font_size_override("font_size", 12)
		none.add_theme_color_override("font_color", ThemeBuilder.COL_GOOD)
		_summary_box.add_child(none)
	for fx in upcoming:
		var opp: Dictionary = svc.opponent_of(fx)
		var home: bool = svc.fixture_is_home(fx)
		var days_away := 0
		var d0 := GameState.current_date
		while d0 < str(fx["date"]) and days_away < 30:
			d0 = Season.date_add(d0, 1)
			days_away += 1
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 8)
		var when := Label.new()
		when.text = tr("today") if days_away == 0 else tr("in %dd") % days_away
		when.custom_minimum_size.x = 52
		when.add_theme_font_size_override("font_size", 12)
		when.add_theme_color_override("font_color",
			ThemeBuilder.COL_WARN if days_away <= 1 else ThemeBuilder.COL_TEXT_DIM)
		r.add_child(when)
		var who := Label.new()
		who.text = "%s %s %s" % [tr("vs") if home else tr("at"), opp["name"], tr("(H)") if home else tr("(A)")]
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		who.add_theme_font_size_override("font_size", 12)
		who.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT)
		who.clip_text = true
		r.add_child(who)
		var comp := Label.new()
		comp.text = tr("League") if str(fx["comp"]) == "league" else tr("Cup")
		comp.add_theme_font_size_override("font_size", 11)
		comp.add_theme_color_override("font_color", ThemeBuilder.COL_ACCENT)
		r.add_child(comp)
		if days_away >= 1:
			var prep := Button.new()
			prep.text = "Prep"
			prep.custom_minimum_size = Vector2(44, 22)
			prep.add_theme_font_size_override("font_size", 11)
			prep.tooltip_text = tr("Plan opponent prep for THIS fixture: light Match-Prep-heavy plans on the %d day(s) before %s %s (per-date — the weekday template is untouched). Match Prep raises condition, which the match sim rates battlers by.") % [
				mini(days_away, 3), tr("vs") if home else tr("at"), opp["short"]]
			var fx_date := str(fx["date"])
			prep.pressed.connect(func():
				svc.plan_prep_for_fixture(fx_date, 3)
				_refresh_schedule.call_deferred())
			r.add_child(prep)
		_summary_box.add_child(r)
	var in_week := 0
	for date in svc.week_dates():
		if not (svc.player_fixture_on(date) as Dictionary).is_empty():
			in_week += 1
	var cong := Label.new()
	if in_week >= 2:
		cong.text = tr("Congested week: %d matches in 7 days — training auto-drops to recovery and prep around them; expect little development.") % in_week
		cong.add_theme_color_override("font_color", ThemeBuilder.COL_WARN)
	elif in_week == 1:
		cong.text = tr("1 match this week — the schedule rests the squad on matchday and the morning after.")
		cong.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	else:
		cong.text = tr("Free week — no fixtures interrupt training.")
		cong.add_theme_color_override("font_color", ThemeBuilder.COL_GOOD)
	if not bool(svc.state.get("auto_match", true)) and in_week > 0:
		cong.text += tr("\nAuto-adjust is OFF: full training runs into matchdays and strain will spike.")
		cong.add_theme_color_override("font_color", ThemeBuilder.COL_BAD)
	cong.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cong.add_theme_font_size_override("font_size", 12)
	_summary_box.add_child(cong)

	# --- per-date plans laid down on the calendar (next 28 days)
	_summary_box.add_child(HSeparator.new())
	var pdl := Label.new()
	pdl.text = tr("PLANNED DAYS · NEXT 28")
	pdl.tooltip_text = tr("Dates you planned individually on the calendar (or via a week's Plan preset). They override the weekday template on that date only.")
	pdl.mouse_filter = Control.MOUSE_FILTER_STOP
	pdl.add_theme_font_size_override("font_size", 11)
	pdl.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	_summary_box.add_child(pdl)
	var planned: Array = svc.planned_custom_dates(28)
	if planned.is_empty():
		var nop := Label.new()
		nop.text = tr("None — every day runs the weekday template. Edit any calendar cell or use a week's Plan menu.")
		nop.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nop.add_theme_font_size_override("font_size", 12)
		nop.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
		_summary_box.add_child(nop)
	for i in mini(planned.size(), 6):
		var date: String = planned[i]
		var plan: Dictionary = svc.effective_plan(date)
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 8)
		var dl := Label.new()
		dl.text = I18n.pretty_date(date)
		dl.custom_minimum_size.x = 76
		dl.add_theme_font_size_override("font_size", 12)
		dl.add_theme_color_override("font_color", OVERRIDE_COL)
		r.add_child(dl)
		var what := Label.new()
		if plan["kind"] == "matchday":
			what.text = tr("matchday — plan resumes around the fixture")
		else:
			what.text = "%s / %s · %s" % [svc.FOCUS_LABELS.get(str(plan["am"]), "?"),
				svc.FOCUS_LABELS.get(str(plan["pm"]), "?"),
				svc.INTENSITY_LABELS.get(str(plan["intensity"]), "?")]
		what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		what.clip_text = true
		what.add_theme_font_size_override("font_size", 12)
		what.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT)
		r.add_child(what)
		var x := Button.new()
		x.icon = GlyphIcons.tex("undo", 11, ThemeBuilder.COL_TEXT)
		x.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		x.custom_minimum_size = Vector2(26, 22)
		x.tooltip_text = tr("Reset this date to the weekday template.")
		x.pressed.connect(func():
			svc.clear_date_override(date)
			_refresh_schedule.call_deferred())
		r.add_child(x)
		_summary_box.add_child(r)
	if planned.size() > 6:
		var more := Label.new()
		more.text = tr("… and %d more planned day%s") % [planned.size() - 6, "" if planned.size() == 7 else "s"]
		more.add_theme_font_size_override("font_size", 11)
		more.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
		_summary_box.add_child(more)

	_summary_box.add_child(HSeparator.new())
	var counts: Dictionary = svc.sessions_per_focus()
	var sl := Label.new()
	sl.text = tr("SESSIONS THIS WEEK (FIXTURE-ADJUSTED)")
	sl.add_theme_font_size_override("font_size", 11)
	sl.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	_summary_box.add_child(sl)
	var focus_rows: Array = svc.FOCUSES.duplicate()
	if int(counts.get("match", 0)) > 0:
		focus_rows.append("match")
	for f in focus_rows:
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 8)
		var nm := Label.new()
		nm.text = str(svc.FOCUS_LABELS.get(f, "Matches"))
		nm.custom_minimum_size.x = 110
		nm.add_theme_color_override("font_color", FOCUS_COLORS.get(f, ThemeBuilder.COL_WARN))
		r.add_child(nm)
		r.add_child(_mini_bar(float(counts[f]) / 8.0, FOCUS_COLORS.get(f, ThemeBuilder.COL_WARN), 130))
		var c := Label.new()
		c.text = tr("%d / wk") % int(counts[f])
		c.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
		r.add_child(c)
		_summary_box.add_child(r)

	_summary_box.add_child(HSeparator.new())
	var bal: float = svc.weekly_strain_balance()
	var bl := Label.new()
	if bal > 5.0:
		bl.text = tr("Overtraining: %+.0f strain per week.\nSquad will accumulate fatigue — add Recovery sessions or lower intensity.") % bal
		bl.add_theme_color_override("font_color", ThemeBuilder.COL_BAD)
	elif bal > -5.0:
		bl.text = tr("Sustainable load (%+.0f strain / week).") % bal
		bl.add_theme_color_override("font_color", ThemeBuilder.COL_WARN)
	else:
		bl.text = tr("Light load (%+.0f strain / week).\nSquad recovers; development will be slower.") % bal
		bl.add_theme_color_override("font_color", ThemeBuilder.COL_GOOD)
	bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary_box.add_child(bl)

	_summary_box.add_child(HSeparator.new())
	var wl := Label.new()
	wl.text = tr("STRAIN WATCHLIST")
	wl.add_theme_font_size_override("font_size", 11)
	wl.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	_summary_box.add_child(wl)
	var listed := 0
	var sq: Array = svc.squad().duplicate()
	sq.sort_custom(func(a, b): return svc.strain(a["uid"]) > svc.strain(b["uid"]))
	for inst in sq:
		var s: float = svc.strain(inst["uid"])
		if s <= 45.0 or listed >= 5:
			continue
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 8)
		var nm := Label.new()
		nm.text = _display_name(inst)
		nm.custom_minimum_size.x = 110
		r.add_child(nm)
		r.add_child(_mini_bar(s / 100.0, _strain_color(s), 90))
		var v := Label.new()
		var setting: String = svc.load_setting(str(inst["uid"]))
		var eff_lbl: String = str(svc.LOAD_LABELS[svc.effective_load(inst)])
		v.text = "%d%% · %s" % [int(s), ("auto » " + eff_lbl) if setting == "auto" else eff_lbl]
		v.add_theme_font_size_override("font_size", 12)
		v.add_theme_color_override("font_color", _strain_color(s))
		v.tooltip_text = _load_tooltip(inst, setting, svc.workload_reaction(inst))
		v.mouse_filter = Control.MOUSE_FILTER_STOP
		r.add_child(v)
		_summary_box.add_child(r)
		listed += 1
	if listed == 0:
		var ok := Label.new()
		ok.text = tr("No fatigue concerns — all Pokémon fresh.")
		ok.add_theme_color_override("font_color", ThemeBuilder.COL_GOOD)
		_summary_box.add_child(ok)

	for cat in svc.CATEGORIES:
		if str(svc.state["coaches"].get(cat, "")) == "":
			var warn := Label.new()
			warn.text = tr("No coach covers %s — training there is much less effective.") % svc.CAT_LABELS[cat]
			warn.add_theme_color_override("font_color", ThemeBuilder.COL_WARN)
			warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_summary_box.add_child(warn)


# ================================================================== INDIVIDUAL

func _build_individual_tab() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	_ind_tree = Tree.new()
	_ind_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ind_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ind_tree.columns = 9
	_ind_tree.column_titles_visible = true
	_ind_tree.hide_root = true
	_ind_tree.select_mode = Tree.SELECT_ROW
	var titles := ["Pokémon", "Lv", "Age", "Growth rate", "Focus", "Workload", "Strain", "Learning", "Progress"]
	var widths := [170, 44, 60, 90, 82, 108, 62, 124, 84]
	for i in titles.size():
		_ind_tree.set_column_title(i, titles[i])
		_ind_tree.set_column_expand(i, i == 0)
		if i > 0:
			_ind_tree.set_column_custom_minimum_width(i, widths[i])
	_ind_tree.item_selected.connect(_on_ind_selected)
	row.add_child(_ind_tree)

	var wrap := _panel(tr("Pokémon detail"))
	(wrap[0] as Control).custom_minimum_size.x = 430
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_box = VBoxContainer.new()
	_detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_detail_box)
	(wrap[1] as VBoxContainer).add_child(scroll)
	(wrap[1] as VBoxContainer).size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(wrap[0])
	return row


func _refresh_individual() -> void:
	_ind_tree.clear()
	var root := _ind_tree.create_item()
	var to_select: TreeItem = null
	for inst in svc.squad():
		var it := _ind_tree.create_item(root)
		var ms: Dictionary = svc.mon_state(inst["uid"])
		it.set_metadata(0, inst["uid"])
		var sp: Dictionary = DataStore.species(int(inst["species_id"]))
		it.set_text(0, "%s  (%s)" % [_display_name(inst), I18n.types_join(sp["types"])])
		it.set_custom_color(0, DataStore.type_color(sp["types"][0]).lightened(0.25))
		it.set_text(1, str(int(inst["level"])))
		it.set_text(2, _age_str(int(inst["age_months"])))
		it.set_text(3, str(sp["growth"]).replace("_", " "))
		it.set_custom_color(3, ThemeBuilder.COL_TEXT_DIM)
		var focus: String = ms.get("focus", "")
		it.set_text(4, svc.STAT_LABELS.get(focus, "—") if focus != "" else "—")
		it.set_custom_color(4, ThemeBuilder.COL_ACCENT if focus != "" else ThemeBuilder.COL_TEXT_DIM)
		var setting: String = svc.load_setting(str(inst["uid"]))
		var eff_lbl: String = str(svc.LOAD_LABELS[svc.effective_load(inst)])
		var reaction: String = svc.workload_reaction(inst)
		it.set_text(5, ("auto » " + eff_lbl) if setting == "auto" else eff_lbl)
		if reaction == "overworked":
			it.set_custom_color(5, ThemeBuilder.COL_BAD)
		elif reaction == "wants_more":
			it.set_custom_color(5, ThemeBuilder.COL_WARN)
		else:
			it.set_custom_color(5, ThemeBuilder.COL_TEXT_DIM if setting == "auto" else ThemeBuilder.COL_ACCENT)
		it.set_tooltip_text(5, _load_tooltip(inst, setting, reaction))
		var s: float = svc.strain(inst["uid"])
		it.set_text(6, "%d%%" % int(s))
		it.set_custom_color(6, _strain_color(s))
		if ms["move"] != null:
			var mv: Dictionary = ms["move"]
			it.set_text(7, str(mv["name"]))
			it.set_custom_color(7, ThemeBuilder.COL_ACCENT)
			it.set_text(8, "%d%%" % int(mv["progress"]))
			it.set_custom_color(8, ThemeBuilder.COL_GOOD)
		else:
			it.set_text(7, "—")
			it.set_custom_color(7, ThemeBuilder.COL_TEXT_DIM)
			it.set_text(8, "")
		if str(inst["uid"]) == _selected_uid:
			to_select = it
	if to_select == null:
		to_select = root.get_first_child()
	if to_select != null:
		to_select.select(0)
		_selected_uid = str(to_select.get_metadata(0))
	_refresh_detail()


func _on_ind_selected() -> void:
	var it := _ind_tree.get_selected()
	if it != null:
		_selected_uid = str(it.get_metadata(0))
		_refresh_detail()


func _refresh_detail() -> void:
	_clear(_detail_box)
	var inst: Dictionary = {}
	for i in svc.squad():
		if str(i["uid"]) == _selected_uid:
			inst = i
			break
	if inst.is_empty():
		return
	var sp: Dictionary = DataStore.species(int(inst["species_id"]))
	var ms: Dictionary = svc.mon_state(inst["uid"])

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.add_child(_monogram(inst, 46))
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 2)
	var nm := Label.new()
	nm.text = _display_name(inst)
	nm.add_theme_font_size_override("font_size", 19)
	nm.add_theme_color_override("font_color", Color.WHITE)
	hv.add_child(nm)
	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", 6)
	var lv := Label.new()
	lv.text = tr("%s · Lv %d") % [sp["name"], int(inst["level"])]
	lv.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	meta.add_child(lv)
	for t in sp["types"]:
		meta.add_child(_type_chip(t))
	hv.add_child(meta)
	head.add_child(hv)
	_detail_box.add_child(head)

	var stage: Array = _dev_stage(int(inst["age_months"]))
	var dl := Label.new()
	dl.text = I18n.t("%s · %s growth · %s") % [_age_str(int(inst["age_months"])),
		str(sp["growth"]).replace("_", " "), stage[0]]
	dl.add_theme_color_override("font_color", stage[1])
	dl.add_theme_font_size_override("font_size", 12)
	_detail_box.add_child(dl)

	var strain_row := HBoxContainer.new()
	strain_row.add_theme_constant_override("separation", 8)
	var stl := Label.new()
	stl.text = "Strain"
	stl.custom_minimum_size.x = 70
	stl.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	strain_row.add_child(stl)
	var sv: float = svc.strain(inst["uid"])
	strain_row.add_child(_mini_bar(sv / 100.0, _strain_color(sv), 160))
	var stv := Label.new()
	stv.text = tr("%d%%  ·  fitness %d%%") % [int(sv), int(inst.get("fitness", 0))]
	stv.add_theme_color_override("font_color", _strain_color(sv))
	strain_row.add_child(stv)
	_detail_box.add_child(strain_row)

	_detail_box.add_child(HSeparator.new())

	# --- individual workload (FM-style per-Pokémon training intensity)
	var wl := Label.new()
	wl.text = tr("TRAINING WORKLOAD")
	wl.add_theme_font_size_override("font_size", 11)
	wl.add_theme_color_override("font_color", ThemeBuilder.COL_ACCENT)
	_detail_box.add_child(wl)
	var setting: String = svc.load_setting(str(inst["uid"]))
	var eff: String = svc.effective_load(inst)
	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", 8)
	var wob := OptionButton.new()
	wob.custom_minimum_size = Vector2(160, 32)
	for l in svc.LOADS:
		wob.add_item(svc.LOAD_LABELS[l])
	wob.select(maxi(0, svc.LOADS.find(setting)))
	wob.item_selected.connect(func(idx: int):
		svc.set_load(str(inst["uid"]), svc.LOADS[idx])
		_refresh_individual())
	wrow.add_child(wob)
	var wnow := Label.new()
	if setting == "auto":
		wnow.text = tr("» %s today") % svc.LOAD_LABELS[eff]
		wnow.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT)
	else:
		wnow.text = tr("manual override")
		wnow.add_theme_color_override("font_color", ThemeBuilder.COL_ACCENT)
	wnow.add_theme_font_size_override("font_size", 12)
	wrow.add_child(wnow)
	_detail_box.add_child(wrow)
	var wdetail := Label.new()
	if setting == "auto":
		wdetail.text = tr("Rule: %s.\nEffect: ×%.2f development · ×%.2f strain intake · %+.0f strain projected over 7 days.") % [
			svc.auto_load_reason(inst), float(svc.LOAD_MULT[eff]), float(svc.LOAD_STRAIN[eff]),
			svc.personal_week_strain(inst)]
	else:
		wdetail.text = tr("Effect: ×%.2f development · ×%.2f strain intake · %+.0f strain projected over 7 days.\n(Automatic would run %s: %s)") % [
			float(svc.LOAD_MULT[eff]), float(svc.LOAD_STRAIN[eff]), svc.personal_week_strain(inst),
			svc.LOAD_LABELS[svc.resolve_auto_load(inst)], svc.auto_load_reason(inst)]
	wdetail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wdetail.add_theme_font_size_override("font_size", 12)
	wdetail.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	_detail_box.add_child(wdetail)
	var reaction: String = svc.workload_reaction(inst)
	if reaction != "":
		var rl := Label.new()
		if reaction == "overworked":
			rl.text = tr("Reacting badly: overworked at %d%% strain on a forced %s load — morale %d%% and dropping, injury risk raised. Ease off or set Automatic.") % [
				int(sv), svc.LOAD_LABELS[eff], int(inst.get("morale", 70))]
			rl.add_theme_color_override("font_color", ThemeBuilder.COL_BAD)
		else:
			rl.text = tr("Unhappy: fresh (%d%% strain) rapid developer held on %s — wants to train more; growth is being wasted.") % [
				int(sv), svc.LOAD_LABELS[eff]]
			rl.add_theme_color_override("font_color", ThemeBuilder.COL_WARN)
		rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rl.add_theme_font_size_override("font_size", 12)
		_detail_box.add_child(rl)

	_detail_box.add_child(HSeparator.new())

	# --- individual focus
	var fl := Label.new()
	fl.text = tr("INDIVIDUAL FOCUS")
	fl.add_theme_font_size_override("font_size", 11)
	fl.add_theme_color_override("font_color", ThemeBuilder.COL_ACCENT)
	_detail_box.add_child(fl)
	var frow := HBoxContainer.new()
	frow.add_theme_constant_override("separation", 8)
	var fob := OptionButton.new()
	fob.custom_minimum_size = Vector2(160, 32)
	fob.add_item(tr("No focus"))
	for s in svc.STATS:
		fob.add_item(svc.STAT_LABELS[s])
	var cur_focus: String = ms.get("focus", "")
	fob.select(0 if cur_focus == "" else svc.STATS.find(cur_focus) + 1)
	fob.item_selected.connect(func(idx: int):
		svc.set_focus(str(inst["uid"]), "" if idx == 0 else svc.STATS[idx - 1])
		_refresh_individual())
	frow.add_child(fob)
	var fhint := Label.new()
	fhint.text = tr("+75% on focused stat, −25% elsewhere")
	fhint.add_theme_font_size_override("font_size", 12)
	fhint.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	frow.add_child(fhint)
	_detail_box.add_child(frow)

	# --- projected gains
	var pl := Label.new()
	pl.text = I18n.t("PROJECTED DEVELOPMENT · NEXT 7 DAYS (FIXTURES + %s LOAD)") % str(svc.LOAD_LABELS[eff]).to_upper()
	pl.add_theme_font_size_override("font_size", 11)
	pl.add_theme_color_override("font_color", ThemeBuilder.COL_ACCENT)
	_detail_box.add_child(pl)
	var proj: Dictionary = svc.weekly_projection(inst)
	var max_pts := 0.001
	for s in svc.STATS:
		max_pts = maxf(max_pts, float(proj[s]))
	for s in svc.STATS:
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 8)
		var sl := Label.new()
		sl.text = svc.STAT_LABELS[s]
		sl.custom_minimum_size.x = 70
		r.add_child(sl)
		var iv := int(inst["ivs"].get(s, 8))
		var col: Color = ThemeBuilder.COL_ACCENT if cur_focus != s else ThemeBuilder.COL_GOOD
		r.add_child(_mini_bar(float(proj[s]) / max_pts, col, 130))
		var v := Label.new()
		if iv >= 15:
			v.text = tr("trained to potential")
			v.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
		else:
			var eta: int = svc.eta_days(inst, s)
			v.text = tr("%.1f pts/wk · %s") % [float(proj[s]),
				(tr("+1 in ~%dd") % eta) if eta > 0 else tr("no gain")]
			v.add_theme_color_override("font_color",
				ThemeBuilder.COL_TEXT if eta > 0 else ThemeBuilder.COL_TEXT_DIM)
		v.add_theme_font_size_override("font_size", 12)
		r.add_child(v)
		_detail_box.add_child(r)

	_detail_box.add_child(HSeparator.new())

	# --- mentoring status
	var mtl := Label.new()
	mtl.text = "MENTORING"
	mtl.add_theme_font_size_override("font_size", 11)
	mtl.add_theme_color_override("font_color", ThemeBuilder.COL_ACCENT)
	_detail_box.add_child(mtl)
	var mline := Label.new()
	var meff: Dictionary = svc.mentoring_effect(str(inst["uid"]))
	if not meff.is_empty():
		mline.text = tr("Learning from %s (%s): ×%.2f development%s%s%s — included in the projection above.") % [
			str(meff["mentor_name"]), svc.PERSONALITIES[meff["personality"]]["label"],
			float(meff["mult"]),
			tr(", ×1.25 on %s") % " & ".join((meff["stat_mult"] as Dictionary).keys().map(
				func(s): return str(svc.STAT_LABELS[s]))) if not (meff["stat_mult"] as Dictionary).is_empty() else "",
			tr(", moves ×%.1f") % float(meff["move_mult"]) if float(meff["move_mult"]) > 1.0 else "",
			tr(", strain ×%.2f") % float(meff["strain_mult"]) if float(meff["strain_mult"]) < 1.0 else ""]
		mline.add_theme_color_override("font_color", ThemeBuilder.COL_GOOD)
	elif svc.is_mentor(str(inst["uid"])):
		var grp: Dictionary = svc.group_of(str(inst["uid"]))
		var jnames: Array = (grp["juniors"] as Array).map(func(u):
			var ji: Dictionary = svc._find_instance(str(u))
			return _display_name(ji) if not ji.is_empty() else "?")
		mline.text = tr("Mentoring %s — passing on its %s example gives this veteran renewed purpose (morale %d%%).") % [
			", ".join(jnames) if not jnames.is_empty() else tr("no one yet"),
			svc.personality_label(inst), int(inst.get("morale", 70))]
		mline.add_theme_color_override("font_color", ThemeBuilder.COL_ACCENT)
	elif svc.mentor_eligible(inst):
		mline.text = tr("Eligible mentor (%s personality) with no group — set one up in the Mentoring tab to give this veteran purpose.") % svc.personality_label(inst)
		mline.add_theme_color_override("font_color", ThemeBuilder.COL_WARN)
	elif svc.junior_eligible(inst):
		mline.text = tr("In rapid development and unmentored — pairing it with a veteran (Mentoring tab) would add +12–31% development speed.")
		mline.add_theme_color_override("font_color", ThemeBuilder.COL_WARN)
	else:
		mline.text = tr("Not eligible: mentoring links veterans with Pokémon still in rapid development.")
		mline.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	mline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mline.add_theme_font_size_override("font_size", 12)
	_detail_box.add_child(mline)

	_detail_box.add_child(HSeparator.new())

	# --- move learning
	var ml := Label.new()
	ml.text = tr("MOVE LEARNING")
	ml.add_theme_font_size_override("font_size", 11)
	ml.add_theme_color_override("font_color", ThemeBuilder.COL_ACCENT)
	_detail_box.add_child(ml)
	var known := Label.new()
	known.text = tr("Knows: %s") % ", ".join(inst.get("moves", []).map(func(m): return tr(str(m))))
	known.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	known.add_theme_font_size_override("font_size", 12)
	known.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	_detail_box.add_child(known)

	if ms["move"] != null:
		var mv: Dictionary = ms["move"]
		var lrow := HBoxContainer.new()
		lrow.add_theme_constant_override("separation", 8)
		var lname := Label.new()
		lname.text = tr("Learning %s") % mv["name"]
		lname.add_theme_color_override("font_color", Color.WHITE)
		lrow.add_child(lname)
		_detail_box.add_child(lrow)
		var prow := HBoxContainer.new()
		prow.add_theme_constant_override("separation", 8)
		prow.add_child(_mini_bar(float(mv["progress"]) / 100.0, ThemeBuilder.COL_GOOD, 180))
		var rate: float = svc.move_learn_rate(inst)
		var pv := Label.new()
		if rate <= 0.02:
			pv.text = tr("%d%%  ·  paused (individual load: No Training)") % int(mv["progress"])
			pv.add_theme_color_override("font_color", ThemeBuilder.COL_WARN)
		else:
			var eta_d := int(ceil((100.0 - float(mv["progress"])) / maxf(rate, 0.01)))
			pv.text = tr("%d%%  ·  ~%d days left") % [int(mv["progress"]), eta_d]
		prow.add_child(pv)
		var cancel := Button.new()
		cancel.text = "Cancel"
		cancel.pressed.connect(func():
			svc.cancel_move_learning(str(inst["uid"]))
			_refresh_individual())
		prow.add_child(cancel)
		_detail_box.add_child(prow)
		var repl := Label.new()
		repl.text = tr("Will replace %s when mastered.") % inst["moves"][int(mv["slot"])]
		repl.add_theme_font_size_override("font_size", 12)
		repl.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
		_detail_box.add_child(repl)
	else:
		var eligible: Array = svc.eligible_moves(inst)
		var btn := Button.new()
		btn.text = tr("Start learning a move…  (%d eligible)") % eligible.size()
		btn.disabled = eligible.is_empty()
		btn.pressed.connect(_open_move_dialog.bind(inst))
		_detail_box.add_child(btn)
		var note := Label.new()
		var tech: int = svc.technique_sessions_per_week()
		note.text = tr("Learning speed: %.1f%%/day (Move Practice ×%d per week, coach %s, %s individual load)") % [
			svc.move_learn_rate(inst), tech,
			str(svc.state["coaches"].get("technique", "")) if str(svc.state["coaches"].get("technique", "")) != "" else "unassigned",
			svc.LOAD_LABELS[svc.effective_load(inst)]]
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_font_size_override("font_size", 12)
		note.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
		_detail_box.add_child(note)

	var learned: Array = ms.get("learned", [])
	if not learned.is_empty():
		var ll := Label.new()
		var parts: Array = []
		for e in learned:
			parts.append("%s (%s)" % [e["move"], e["date"]])
		ll.text = tr("Learned this season: %s") % ", ".join(parts)
		ll.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ll.add_theme_font_size_override("font_size", 12)
		ll.add_theme_color_override("font_color", ThemeBuilder.COL_GOOD)
		_detail_box.add_child(ll)


# ------------------------------------------------------------------ move dialog

func _build_move_dialog() -> void:
	_move_dialog = AcceptDialog.new()
	_move_dialog.title = tr("Start move learning")
	_move_dialog.ok_button_text = tr("Begin training")
	_move_dialog.min_size = Vector2i(540, 500)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 10
	v.offset_top = 10
	v.offset_right = -10
	v.offset_bottom = -50
	v.add_theme_constant_override("separation", 8)
	var hint := Label.new()
	hint.text = tr("Pick a move from this Pokémon's learnset. Progress advances every training day; Move Practice sessions and the technique coach speed it up.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	v.add_child(hint)
	_move_list = ItemList.new()
	_move_list.custom_minimum_size = Vector2(480, 260)
	_move_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_move_list)
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 8)
	var sl := Label.new()
	sl.text = "Replaces:"
	srow.add_child(sl)
	_slot_option = OptionButton.new()
	_slot_option.custom_minimum_size.x = 200
	srow.add_child(_slot_option)
	v.add_child(srow)
	_move_eta_label = Label.new()
	_move_eta_label.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	v.add_child(_move_eta_label)
	_move_dialog.add_child(v)
	_move_dialog.confirmed.connect(_on_move_confirmed)
	add_child(_move_dialog)


func _open_move_dialog(inst: Dictionary) -> void:
	_move_dialog.set_meta("uid", inst["uid"])
	_move_list.clear()
	_dialog_moves = svc.eligible_moves(inst)
	for m in _dialog_moves:
		var md: Dictionary = DataStore.move(m)
		var pw := tr("%d pow") % int(md.get("power", 0)) if int(md.get("power", 0)) > 0 else "status"
		_move_list.add_item("%s   ·  %s  ·  %s  ·  %s" % [m, md.get("type", "?"), pw,
			str(md.get("category", "?"))])
		_move_list.set_item_custom_fg_color(_move_list.item_count - 1,
			DataStore.type_color(str(md.get("type", ""))).lightened(0.3))
	if _move_list.item_count > 0:
		_move_list.select(0)
	_slot_option.clear()
	for m in inst.get("moves", []):
		_slot_option.add_item(str(m))
	var rate: float = svc.move_learn_rate(inst)
	if rate <= 0.02:
		_move_eta_label.text = tr("Progress is PAUSED: this Pokémon's individual load is No Training. It will resume when it trains again.")
	else:
		_move_eta_label.text = tr("Estimated time to master: ~%d days at the current schedule and individual load.") % int(ceil(100.0 / maxf(rate, 0.01)))
	_move_dialog.popup_centered()


func _on_move_confirmed() -> void:
	var sel := _move_list.get_selected_items()
	if sel.is_empty() or _dialog_moves.is_empty():
		return
	svc.start_move_learning(str(_move_dialog.get_meta("uid")),
		str(_dialog_moves[sel[0]]), _slot_option.selected)
	_refresh_individual()


# ================================================================== COACHES

func _build_coaches_tab() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var left := ScrollContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_coach_cards_box = VBoxContainer.new()
	_coach_cards_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_coach_cards_box.add_theme_constant_override("separation", 10)
	left.add_child(_coach_cards_box)
	row.add_child(left)

	var wrap := _panel(tr("Category assignments"))
	(wrap[0] as Control).custom_minimum_size.x = 560
	_assign_box = wrap[1]
	row.add_child(wrap[0])
	return row


func _refresh_coaches() -> void:
	_clear(_coach_cards_box)
	for coach in svc.coaching_staff():
		_coach_cards_box.add_child(_coach_card(coach))
	var physios: Array = GameState.player_club().get("staff", []).filter(
		func(s): return s["role"] != "coach")
	if not physios.is_empty():
		var orow := HBoxContainer.new()
		orow.add_theme_constant_override("separation", 6)
		var other := Label.new()
		other.text = tr("Other staff:")
		other.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
		other.add_theme_font_size_override("font_size", 12)
		orow.add_child(other)
		var collar := Portrait.club_collar(GameState.player_club())
		for s in physios:
			orow.add_child(Portrait.avatar(str(s["name"]), 20, {"collar": collar}))
			var pl := Label.new()
			pl.text = "%s (%s)  " % [s["name"], s["role"]]
			pl.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
			pl.add_theme_font_size_override("font_size", 12)
			orow.add_child(pl)
		_coach_cards_box.add_child(orow)

	_clear(_assign_box)
	var mons_per_coach := float(svc.squad().size()) / maxf(1.0, float(svc.coaching_staff().size()))
	var head := Label.new()
	head.text = tr("Assign one coach to each training category. A coach covering 3+ areas loses effectiveness.")
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_theme_font_size_override("font_size", 12)
	head.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	_assign_box.add_child(head)
	for cat in svc.CATEGORIES:
		_assign_box.add_child(_assignment_row(cat))
	_assign_box.add_child(HSeparator.new())
	var foot := Label.new()
	foot.text = tr("Squad-to-coach ratio: %.1f Pokémon per coach%s") % [mons_per_coach,
		tr("  — consider asking the board for more coaches.") if mons_per_coach > 6.0 else "."]
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	foot.add_theme_font_size_override("font_size", 12)
	foot.add_theme_color_override("font_color",
		ThemeBuilder.COL_WARN if mons_per_coach > 6.0 else ThemeBuilder.COL_TEXT_DIM)
	_assign_box.add_child(foot)


func _coach_card(coach: Dictionary) -> Control:
	var wrap := _panel()
	var v: VBoxContainer = wrap[1]
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.add_child(Portrait.avatar(str(coach["name"]), 34,
		{"collar": Portrait.club_collar(GameState.player_club())}))
	var nm := Label.new()
	nm.text = coach["name"]
	nm.add_theme_font_size_override("font_size", 17)
	nm.add_theme_color_override("font_color", Color.WHITE)
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(nm)
	var role := Label.new()
	role.text = "Coach"
	role.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	role.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(role)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var nload: int = svc.coach_load(coach["name"])
	var pen: float = svc.workload_penalty(coach["name"])
	var wl := Label.new()
	if pen > 0.0:
		wl.text = tr("Workload: %d areas — quality −%d%%") % [nload, int(round(pen * 100))]
		wl.add_theme_color_override("font_color", ThemeBuilder.COL_BAD if pen >= 0.14 else ThemeBuilder.COL_WARN)
	else:
		wl.text = tr("Workload: %d area%s — fine") % [nload, "" if nload == 1 else "s"]
		wl.add_theme_color_override("font_color", ThemeBuilder.COL_GOOD)
	head.add_child(wl)
	v.add_child(head)

	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 2)
	var rat: Dictionary = coach["ratings"]
	var shown := [["attacking", "Attacking"], ["defending", "Defending"], ["fitness", "Fitness"],
		["judging_ability", tr("Judge Ability")], ["judging_potential", tr("Judge Potential")], ["youth", "Youth"]]
	for pair in shown:
		var l := Label.new()
		l.text = pair[1]
		l.add_theme_font_size_override("font_size", 11)
		l.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
		grid.add_child(l)
	for pair in shown:
		var r := int(rat.get(pair[0], 0))
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 6)
		var col: Color = ThemeBuilder.COL_GOOD if r >= 14 else (ThemeBuilder.COL_WARN if r >= 9 else ThemeBuilder.COL_BAD)
		cell.add_child(_mini_bar(float(r) / 20.0, col, 60))
		var vl := Label.new()
		vl.text = str(r)
		vl.add_theme_color_override("font_color", col)
		cell.add_child(vl)
		grid.add_child(cell)
	v.add_child(grid)

	var cats: Array = []
	for cat in svc.CATEGORIES:
		if str(svc.state["coaches"].get(cat, "")) == str(coach["name"]):
			cats.append(str(svc.CAT_LABELS[cat]))
	var al := Label.new()
	al.text = tr("Assigned: %s") % (", ".join(cats) if not cats.is_empty() else "nothing")
	al.add_theme_font_size_override("font_size", 12)
	al.add_theme_color_override("font_color", ThemeBuilder.COL_ACCENT if not cats.is_empty() else ThemeBuilder.COL_TEXT_DIM)
	v.add_child(al)
	return wrap[0]


func _assignment_row(cat: String) -> Control:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 10)
	var l := Label.new()
	l.text = svc.CAT_LABELS[cat]
	l.custom_minimum_size.x = 150
	r.add_child(l)
	var ob := OptionButton.new()
	ob.custom_minimum_size = Vector2(170, 32)
	ob.add_item("(unassigned)")
	var names: Array = svc.coaching_staff().map(func(c): return str(c["name"]))
	for n in names:
		ob.add_item(n)
	var cur: String = str(svc.state["coaches"].get(cat, ""))
	ob.select(names.find(cur) + 1 if cur != "" else 0)
	ob.item_selected.connect(func(idx: int):
		svc.assign_coach(cat, "" if idx == 0 else names[idx - 1])
		_refresh_coaches())
	r.add_child(ob)
	var mult: float = svc.coach_mult(cat)
	var sessions := int(svc.sessions_per_focus().get("rest" if cat == "recovery" else cat, 0))
	var eff := Label.new()
	var col: Color = ThemeBuilder.COL_GOOD if mult >= 1.15 else (ThemeBuilder.COL_TEXT if mult >= 0.95 else ThemeBuilder.COL_WARN)
	if cur == "":
		eff.text = tr("no coach — ×0.55 · %d sessions/wk") % sessions
		col = ThemeBuilder.COL_BAD
	else:
		var coach: Dictionary = svc.staff_by_name(cur)
		var rating := int(coach["ratings"].get(svc.CAT_SOURCE[cat], 0))
		eff.text = tr("×%.2f  (uses %s %d/20%s) · %d sessions/wk") % [mult,
			str(svc.CAT_SOURCE[cat]).capitalize().replace("_", " "), rating,
			tr(", stretched") if svc.workload_penalty(cur) > 0.0 else "", sessions]
	eff.add_theme_font_size_override("font_size", 12)
	eff.add_theme_color_override("font_color", col)
	r.add_child(eff)
	return r


# ================================================================== MENTORING

func _build_mentoring_tab() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var left_wrap := _panel(tr("Mentor groups"))
	(left_wrap[0] as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_groups_box = VBoxContainer.new()
	_groups_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_groups_box.add_theme_constant_override("separation", 10)
	scroll.add_child(_groups_box)
	(left_wrap[1] as VBoxContainer).add_child(scroll)
	(left_wrap[1] as VBoxContainer).size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(left_wrap[0])

	var right_wrap := _panel(tr("Eligibility & personalities"))
	(right_wrap[0] as Control).custom_minimum_size.x = 460
	var rscroll := ScrollContainer.new()
	rscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_mentor_side = VBoxContainer.new()
	_mentor_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mentor_side.add_theme_constant_override("separation", 6)
	rscroll.add_child(_mentor_side)
	(right_wrap[1] as VBoxContainer).add_child(rscroll)
	(right_wrap[1] as VBoxContainer).size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(right_wrap[0])
	return row


func _personality_chip(key: String) -> Control:
	var p := PanelContainer.new()
	var col: Color = PERSONALITY_COLORS.get(key, ThemeBuilder.COL_ACCENT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = col.darkened(0.72)
	sb.border_color = col
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	p.tooltip_text = str(svc.PERSONALITIES[key]["desc"])
	var l := Label.new()
	l.text = str(svc.PERSONALITIES[key]["label"]).to_upper()
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", col.lightened(0.35))
	p.add_child(l)
	return p


## Juniors that could join THIS mentor's group right now.
func _addable_juniors(mentor: Dictionary) -> Array:
	var out: Array = []
	for inst in svc.squad():
		if str(inst["uid"]) == str(mentor["uid"]):
			continue
		if not svc.junior_eligible(inst):
			continue
		if not (svc.group_of(str(inst["uid"])) as Dictionary).is_empty():
			continue
		if svc.can_mentor(mentor, inst) != "":
			continue
		out.append(inst)
	return out


func _mentor_group_card(g: Dictionary) -> Control:
	var mentor: Dictionary = {}
	for i in svc.squad():
		if str(i["uid"]) == str(g["mentor"]):
			mentor = i
	if mentor.is_empty():
		return Control.new()
	var pk: String = svc.personality(mentor)
	var wrap := _panel()
	var v: VBoxContainer = wrap[1]

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.add_child(_monogram(mentor, 40))
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 0)
	var nm := Label.new()
	nm.text = _display_name(mentor)
	nm.add_theme_font_size_override("font_size", 17)
	nm.add_theme_color_override("font_color", Color.WHITE)
	hv.add_child(nm)
	var sub := Label.new()
	sub.text = tr("Lv %d · %s · veteran mentor · morale %d%%") % [int(mentor["level"]),
		_age_str(int(mentor["age_months"])), int(mentor.get("morale", 70))]
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	hv.add_child(sub)
	head.add_child(hv)
	head.add_child(_personality_chip(pk))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var disband := Button.new()
	disband.text = "Disband"
	disband.tooltip_text = tr("Remove this mentor group. Juniors lose the development bonus immediately.")
	disband.pressed.connect(func():
		svc.disband_mentor_group(str(mentor["uid"]))
		_refresh_mentoring.call_deferred())
	head.add_child(disband)
	v.add_child(head)

	var pdesc := Label.new()
	pdesc.text = "%s — %s." % [svc.personality_label(mentor), str(svc.PERSONALITIES[pk]["desc"])]
	pdesc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pdesc.add_theme_font_size_override("font_size", 12)
	pdesc.add_theme_color_override("font_color", PERSONALITY_COLORS.get(pk, ThemeBuilder.COL_TEXT_DIM))
	v.add_child(pdesc)

	var juniors: Array = g["juniors"]
	if juniors.is_empty():
		var none := Label.new()
		none.text = tr("No juniors yet — add one below to start the daily transfer.")
		none.add_theme_font_size_override("font_size", 12)
		none.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
		v.add_child(none)
	for jid in juniors:
		var junior: Dictionary = {}
		for i in svc.squad():
			if str(i["uid"]) == str(jid):
				junior = i
		if junior.is_empty():
			continue
		var eff: Dictionary = svc.mentoring_effect(str(jid))
		var jms: Dictionary = svc.mon_state(str(jid))
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 8)
		r.add_child(_monogram(junior, 26))
		var jn := Label.new()
		jn.text = tr("%s  Lv %d · %s") % [_display_name(junior), int(junior["level"]),
			_age_str(int(junior["age_months"]))]
		jn.custom_minimum_size.x = 190
		jn.add_theme_font_size_override("font_size", 12)
		jn.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT)
		r.add_child(jn)
		var lrn := Label.new()
		if eff.is_empty():
			lrn.text = tr("pairing no longer valid")
			lrn.add_theme_color_override("font_color", ThemeBuilder.COL_WARN)
		else:
			var stat_bias: Array = (eff["stat_mult"] as Dictionary).keys().map(
				func(s): return str(svc.STAT_LABELS[s]))
			var extras: Array = []
			if not stat_bias.is_empty():
				extras.append("×1.25 %s" % " & ".join(stat_bias))
			if float(eff["move_mult"]) > 1.0:
				extras.append(tr("moves ×%.1f") % float(eff["move_mult"]))
			if float(eff["strain_mult"]) < 1.0:
				extras.append(tr("strain ×%.2f") % float(eff["strain_mult"]))
			lrn.text = tr("learning from %s · +%d%% dev%s") % [eff["mentor_name"],
				int(round((float(eff["mult"]) - 1.0) * 100.0)),
				(" · " + " · ".join(extras)) if not extras.is_empty() else ""]
			lrn.add_theme_color_override("font_color", ThemeBuilder.COL_GOOD)
			lrn.tooltip_text = tr("Base +%d%%%s · level gap +%d%%%s%s.\nAttributed so far: +%.1f training points, %d IVs.") % [
				int(svc.MENTOR_BASE_BONUS * 100),
				tr(" · shared type +%d%%") % int(svc.MENTOR_TYPE_BONUS * 100) if bool(eff["compat"]) else "",
				int(round(minf(svc.MENTOR_GAP_BONUS_CAP, svc.MENTOR_GAP_BONUS_PER_LVL
					* float(int(eff["mentor"]["level"]) - int(junior["level"]))) * 100.0)),
				" · Professional +5%" if str(eff["personality"]) == "professional" else "",
				tr(" · split attention −%d%%") % int(svc.MENTOR_SPLIT_PENALTY * 100) if juniors.size() >= 2 else "",
				float(jms.get("mentor_pts", 0.0)), int(jms.get("mentor_ivs", 0))]
			lrn.mouse_filter = Control.MOUSE_FILTER_STOP
		lrn.add_theme_font_size_override("font_size", 12)
		lrn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lrn.clip_text = true
		r.add_child(lrn)
		var mor := Label.new()
		mor.text = tr("morale %d%%") % int(junior.get("morale", 70))
		mor.add_theme_font_size_override("font_size", 11)
		mor.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
		r.add_child(mor)
		var x := Button.new()
		x.icon = GlyphIcons.tex("cross", 10, ThemeBuilder.COL_TEXT)
		x.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		x.custom_minimum_size = Vector2(26, 22)
		x.tooltip_text = tr("Remove %s from the group.") % _display_name(junior)
		x.pressed.connect(func():
			svc.remove_junior(str(jid))
			_refresh_mentoring.call_deferred())
		r.add_child(x)
		v.add_child(r)

	# --- add-junior row
	if juniors.size() < svc.MENTOR_MAX_JUNIORS:
		var addable := _addable_juniors(mentor)
		var ar := HBoxContainer.new()
		ar.add_theme_constant_override("separation", 8)
		if addable.is_empty():
			var no := Label.new()
			no.text = tr("No further eligible juniors (young, ≥%d levels and ≥%d months below %s, not already mentored).") % [
				svc.MENTOR_LEVEL_GAP, svc.MENTOR_AGE_GAP, _display_name(mentor)]
			no.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			no.add_theme_font_size_override("font_size", 12)
			no.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
			ar.add_child(no)
		else:
			var ob := OptionButton.new()
			ob.custom_minimum_size = Vector2(280, 30)
			for j in addable:
				ob.add_item(tr("%s  (Lv %d · %s · +%d%% dev)") % [_display_name(j), int(j["level"]),
					_age_str(int(j["age_months"])),
					int(round((svc.pairing_mult(mentor, j, juniors.size() + 1) - 1.0) * 100.0))])
			ar.add_child(ob)
			var add := Button.new()
			add.text = tr("Add junior")
			add.pressed.connect(func():
				var idx: int = ob.selected
				if idx >= 0 and idx < addable.size():
					var err: String = svc.add_junior(str(mentor["uid"]), str(addable[idx]["uid"]))
					if err != "":
						push_warning(err)
				_refresh_mentoring.call_deferred())
			ar.add_child(add)
		v.add_child(ar)
	else:
		var full := Label.new()
		full.text = tr("Group full — a mentor can watch %d juniors (attention already split: −%d%% each).") % [
			svc.MENTOR_MAX_JUNIORS, int(svc.MENTOR_SPLIT_PENALTY * 100)]
		full.add_theme_font_size_override("font_size", 12)
		full.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
		v.add_child(full)
	return wrap[0]


func _refresh_mentoring() -> void:
	if _groups_box == null or not is_instance_valid(_groups_box):
		return
	_clear(_groups_box)

	var intro := Label.new()
	intro.text = tr("Group a senior Pokémon with up to %d rapid developers. Every training day the juniors gain development speed and morale from the mentor's example — the mentor's personality steers WHICH stats bite hardest — and the veteran gets renewed purpose. Gains are attributed in the Development report.") % svc.MENTOR_MAX_JUNIORS
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_font_size_override("font_size", 12)
	intro.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	_groups_box.add_child(intro)

	var groups: Array = svc.mentor_groups()
	for g in groups:
		_groups_box.add_child(_mentor_group_card(g))
	if groups.is_empty():
		var none := Label.new()
		none.text = tr("No mentor groups yet.")
		none.add_theme_font_size_override("font_size", 13)
		none.add_theme_color_override("font_color", ThemeBuilder.COL_WARN)
		_groups_box.add_child(none)

	# --- new group
	var free_mentors: Array = svc.squad().filter(func(i):
		return svc.mentor_eligible(i) and (svc.group_of(str(i["uid"])) as Dictionary).is_empty())
	_groups_box.add_child(HSeparator.new())
	var nr := HBoxContainer.new()
	nr.add_theme_constant_override("separation", 8)
	var nl := Label.new()
	nl.text = tr("New group:")
	nl.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	nr.add_child(nl)
	if free_mentors.is_empty():
		var no := Label.new()
		no.text = tr("no free veterans — every eligible mentor already leads a group.")
		no.add_theme_font_size_override("font_size", 12)
		no.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
		nr.add_child(no)
	else:
		var ob := OptionButton.new()
		ob.custom_minimum_size = Vector2(300, 30)
		for m in free_mentors:
			ob.add_item(tr("%s  (Lv %d · %s · %s)") % [_display_name(m), int(m["level"]),
				_age_str(int(m["age_months"])), svc.personality_label(m)])
		nr.add_child(ob)
		var mk := Button.new()
		mk.text = tr("Create group")
		mk.pressed.connect(func():
			var idx: int = ob.selected
			if idx >= 0 and idx < free_mentors.size():
				svc.create_mentor_group(str(free_mentors[idx]["uid"]))
			_refresh_mentoring.call_deferred())
		nr.add_child(mk)
	_groups_box.add_child(nr)

	_refresh_mentor_side()


func _side_head(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	return l


func _refresh_mentor_side() -> void:
	_clear(_mentor_side)

	var rules := Label.new()
	rules.text = tr("Eligibility: mentors are veterans whose own development has flattened (age ≥ ~5y7m); juniors are in rapid development (age ≤ 4y) and must sit ≥%d levels and ≥%d months below their mentor. Effect: +%d%% development base, +%d%% shared type, up to +%d%% for a big level gap; −%d%% each when attention splits across two juniors.") % [
		svc.MENTOR_LEVEL_GAP, svc.MENTOR_AGE_GAP, int(svc.MENTOR_BASE_BONUS * 100),
		int(svc.MENTOR_TYPE_BONUS * 100), int(svc.MENTOR_GAP_BONUS_CAP * 100),
		int(svc.MENTOR_SPLIT_PENALTY * 100)]
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules.add_theme_font_size_override("font_size", 12)
	rules.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	_mentor_side.add_child(rules)

	_mentor_side.add_child(HSeparator.new())
	_mentor_side.add_child(_side_head(tr("ELIGIBLE MENTORS (VETERANS)")))
	var any_m := false
	for inst in svc.squad():
		if not svc.mentor_eligible(inst):
			continue
		any_m = true
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 8)
		var nm := Label.new()
		nm.text = tr("%s  Lv %d · %s") % [_display_name(inst), int(inst["level"]),
			_age_str(int(inst["age_months"]))]
		nm.custom_minimum_size.x = 190
		nm.add_theme_font_size_override("font_size", 12)
		r.add_child(nm)
		r.add_child(_personality_chip(svc.personality(inst)))
		var st := Label.new()
		var grp: Dictionary = svc.group_of(str(inst["uid"]))
		if not grp.is_empty() and str(grp.get("mentor", "")) == str(inst["uid"]):
			st.text = tr("mentoring %d") % (grp["juniors"] as Array).size()
			st.add_theme_color_override("font_color", ThemeBuilder.COL_GOOD)
		else:
			st.text = "available"
			st.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
		st.add_theme_font_size_override("font_size", 12)
		r.add_child(st)
		_mentor_side.add_child(r)
	if not any_m:
		var no := Label.new()
		no.text = tr("No veterans in the squad.")
		no.add_theme_font_size_override("font_size", 12)
		no.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
		_mentor_side.add_child(no)

	_mentor_side.add_child(HSeparator.new())
	_mentor_side.add_child(_side_head(tr("ELIGIBLE JUNIORS (RAPID DEVELOPERS)")))
	var any_j := false
	for inst in svc.squad():
		if not svc.junior_eligible(inst):
			continue
		any_j = true
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 8)
		var nm := Label.new()
		nm.text = tr("%s  Lv %d · %s") % [_display_name(inst), int(inst["level"]),
			_age_str(int(inst["age_months"]))]
		nm.custom_minimum_size.x = 190
		nm.add_theme_font_size_override("font_size", 12)
		r.add_child(nm)
		var st := Label.new()
		var mentor: Dictionary = svc.mentor_of(str(inst["uid"]))
		if not mentor.is_empty():
			st.text = tr("learning from %s") % _display_name(mentor)
			st.add_theme_color_override("font_color", ThemeBuilder.COL_GOOD)
		else:
			# is anyone in the squad actually able to take this junior?
			var fits: Array = svc.squad().filter(func(m):
				return svc.mentor_eligible(m) and svc.can_mentor(m, inst) == "")
			if fits.is_empty():
				st.text = tr("no valid mentor (level/age gap)")
				st.add_theme_color_override("font_color", ThemeBuilder.COL_WARN)
			else:
				st.text = I18n.np(fits.size(), "unmentored — %d possible mentor", "unmentored — %d possible mentors")
				st.add_theme_color_override("font_color", ThemeBuilder.COL_WARN)
		st.add_theme_font_size_override("font_size", 12)
		st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		st.clip_text = true
		r.add_child(st)
		_mentor_side.add_child(r)
	if not any_j:
		var no := Label.new()
		no.text = tr("No rapid developers in the squad — sign or promote young Pokémon.")
		no.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		no.add_theme_font_size_override("font_size", 12)
		no.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
		_mentor_side.add_child(no)

	_mentor_side.add_child(HSeparator.new())
	_mentor_side.add_child(_side_head(tr("MENTOR PERSONALITIES")))
	for pk in svc.PERSONALITIES:
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 8)
		r.add_child(_personality_chip(pk))
		var d := Label.new()
		d.text = str(svc.PERSONALITIES[pk]["desc"])
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.add_theme_font_size_override("font_size", 11)
		d.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
		d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(d)
		_mentor_side.add_child(r)


# ================================================================== DEVELOPMENT

func _build_development_tab() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	var best_wrap := _panel(tr("Best developers · last 28 days"))
	(best_wrap[0] as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_best_box = best_wrap[1]
	top.add_child(best_wrap[0])
	var stag_wrap := _panel(tr("Needs attention"))
	(stag_wrap[0] as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stag_box = stag_wrap[1]
	top.add_child(stag_wrap[0])
	v.add_child(top)

	_dev_tree = Tree.new()
	_dev_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dev_tree.columns = 13
	_dev_tree.column_titles_visible = true
	_dev_tree.hide_root = true
	var titles := ["Pokémon", "Lv", "HP", "Atk", "Def", "SpA", "SpD", "Spe", tr("IV gains"), "Strain", "Moves", "Mentoring", "Evolution"]
	for i in titles.size():
		_dev_tree.set_column_title(i, titles[i])
		_dev_tree.set_column_expand(i, i == 0 or i == 11 or i == 12)
		if i > 0:
			_dev_tree.set_column_custom_minimum_width(i, 62 if i < 9 else (70 if i < 11 else 168))
	v.add_child(_dev_tree)

	_dev_note = Label.new()
	_dev_note.add_theme_font_size_override("font_size", 12)
	_dev_note.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	v.add_child(_dev_note)
	return v


func _refresh_development() -> void:
	_dev_tree.clear()
	var root := _dev_tree.create_item()
	var rows: Array = []
	for inst in svc.squad():
		var d: Dictionary = svc.deltas(inst, 28)
		var total := 0
		for s in svc.STATS:
			total += int(d[s])
		rows.append({"inst": inst, "d": d, "total": total, "gained": svc.total_gained(str(inst["uid"]))})
	rows.sort_custom(func(a, b): return a["total"] > b["total"])

	var tracked := 0
	for row in rows:
		var inst: Dictionary = row["inst"]
		tracked = maxi(tracked, svc.days_tracked(str(inst["uid"])))
		var sp: Dictionary = DataStore.species(int(inst["species_id"]))
		var it := _dev_tree.create_item(root)
		it.set_text(0, "%s  ·  %s" % [_display_name(inst), _age_str(int(inst["age_months"]))])
		it.set_custom_color(0, DataStore.type_color(sp["types"][0]).lightened(0.25))
		it.set_text(1, str(int(inst["level"])))
		for i in svc.STATS.size():
			var dv := int(row["d"][svc.STATS[i]])
			if dv > 0:
				it.set_text(2 + i, "+%d" % dv)
				it.set_custom_color(2 + i, ThemeBuilder.COL_GOOD)
			elif dv < 0:
				it.set_text(2 + i, "−%d" % absi(dv))
				it.set_custom_color(2 + i, ThemeBuilder.COL_BAD)
			else:
				it.set_text(2 + i, "—")
				it.set_custom_color(2 + i, Color("3a4058"))
		it.set_text(8, "+%d" % int(row["gained"]))
		it.set_custom_color(8, ThemeBuilder.COL_GOOD if int(row["gained"]) > 0 else Color("3a4058"))
		var s: float = svc.strain(str(inst["uid"]))
		it.set_text(9, "%d%%" % int(s))
		it.set_custom_color(9, _strain_color(s))
		var learned: Array = svc.mon_state(str(inst["uid"]))["learned"]
		it.set_text(10, str(learned.size()) if not learned.is_empty() else "—")
		it.set_custom_color(10, ThemeBuilder.COL_ACCENT if not learned.is_empty() else Color("3a4058"))
		# --- mentoring attribution: who is teaching whom, and what it earned
		var jms: Dictionary = svc.mon_state(str(inst["uid"]))
		var mentor: Dictionary = svc.mentor_of(str(inst["uid"]))
		if not mentor.is_empty():
			it.set_text(11, tr("learning from %s") % _display_name(mentor))
			it.set_custom_color(11, ThemeBuilder.COL_GOOD)
			it.set_tooltip_text(11, tr("Mentored by %s (%s): +%.1f bonus training points, %d of its IV gains attributed to mentoring.") % [
				_display_name(mentor), svc.personality_label(mentor),
				float(jms.get("mentor_pts", 0.0)), int(jms.get("mentor_ivs", 0))])
		elif svc.is_mentor(str(inst["uid"])):
			var grp: Dictionary = svc.group_of(str(inst["uid"]))
			var jnames: Array = (grp["juniors"] as Array).map(func(u):
				var ji: Dictionary = svc._find_instance(str(u))
				return _display_name(ji) if not ji.is_empty() else "?")
			it.set_text(11, tr("mentoring %s") % ", ".join(jnames))
			it.set_custom_color(11, ThemeBuilder.COL_ACCENT)
			it.set_tooltip_text(11, tr("%s personality — renewed purpose from mentoring lifts its morale (currently %d%%).") % [
				svc.personality_label(inst), int(inst.get("morale", 70))])
		else:
			it.set_text(11, "—")
			it.set_custom_color(11, Color("3a4058"))
		# --- evolution linkage: what this development is buying
		var evo := _evo_cell(inst)
		it.set_text(12, evo["text"])
		it.set_custom_color(12, evo["color"])
		it.set_tooltip_text(12, evo["tip"])

	_dev_note.text = tr("Attribute changes over the last 28 training days (tracking %d day%s so far). +N marks real stat increases from training — IVs are capped at 15 per stat.\nEvolution: every %d development points = +1 effective level toward evolution thresholds (decisions land in the Inbox). Need more rapid developers? Promote from the Academy — its intake pipeline feeds this squad.") % [tracked, "" if tracked == 1 else "s", _evo_dev_per_level()]

	_clear(_best_box)
	var best := 0
	for row in rows:
		if int(row["total"]) <= 0 or best >= 3:
			continue
		var detail := tr("+%d stat points · %d IVs gained") % [int(row["total"]), int(row["gained"])]
		var mrow: Dictionary = svc.mentor_of(str((row["inst"] as Dictionary)["uid"]))
		if not mrow.is_empty():
			detail += tr(" · learning from %s") % _display_name(mrow)
		_best_box.add_child(_dev_summary_row(row["inst"], detail, ThemeBuilder.COL_GOOD))
		best += 1
	if best == 0:
		var l := Label.new()
		l.text = tr("No measurable gains yet — development shows here as training days pass.")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
		_best_box.add_child(l)

	_clear(_stag_box)
	var listed := 0
	for row in rows:
		var inst: Dictionary = row["inst"]
		var age := int(inst["age_months"])
		var s: float = svc.strain(str(inst["uid"]))
		var reaction: String = svc.workload_reaction(inst)
		var reason := ""
		if reaction == "overworked":
			reason = tr("unhappy: forced %s load at %d%% strain — morale %d%%, injury risk up. Ease the individual load.") % [
				svc.LOAD_LABELS[svc.effective_load(inst)], int(s), int(inst.get("morale", 70))]
		elif s > 70.0:
			var setting: String = svc.load_setting(str(inst["uid"]))
			reason = tr("strain %d%% — overtrained, gains reduced%s") % [int(s),
				" (Automatic has eased it to %s)" % svc.LOAD_LABELS[svc.effective_load(inst)] if setting == "auto"
				else tr(" — set the individual load to Light or Automatic")]
		elif reaction == "wants_more":
			reason = tr("held on %s while fresh — a rapid developer wasting growth; raise the individual load") % \
				svc.LOAD_LABELS[svc.effective_load(inst)]
		elif svc.age_mult(age) <= 0.6 and int(row["total"]) <= 0 and not svc.is_mentor(str(inst["uid"])):
			reason = I18n.t("veteran (%s) — stagnating; give it purpose as a mentor (Mentoring tab)") % _age_str(age)
		if reason == "" or listed >= 3:
			continue
		_stag_box.add_child(_dev_summary_row(inst, reason,
			ThemeBuilder.COL_BAD if (s > 70.0 or reaction == "overworked") else ThemeBuilder.COL_WARN))
		listed += 1
	if listed == 0:
		var ok := Label.new()
		ok.text = tr("No concerns — workload and age profile look healthy.")
		ok.add_theme_color_override("font_color", ThemeBuilder.COL_GOOD)
		_stag_box.add_child(ok)


func _dev_summary_row(inst: Dictionary, detail: String, col: Color) -> Control:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 10)
	r.add_child(_monogram(inst, 28))
	var nm := Label.new()
	nm.text = _display_name(inst)
	nm.custom_minimum_size.x = 100
	nm.add_theme_color_override("font_color", Color.WHITE)
	r.add_child(nm)
	var dl := Label.new()
	dl.text = detail
	dl.add_theme_font_size_override("font_size", 12)
	dl.add_theme_color_override("font_color", col)
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(dl)
	return r


# ------------------------------------------------- evolution-development linkage

func _evo_dev_per_level() -> int:
	var s = EvoSvc.instance
	return maxi(1, int(s._dev_per_level)) if s != null else 6


## One-line evolution status for the Development table: what this mon's
## training points are buying, and how far it still has to go.
func _evo_cell(inst: Dictionary) -> Dictionary:
	var s = EvoSvc.instance
	if s == null:
		return {"text": "—", "color": Color("3a4058"), "tip": ""}
	var uid := str(inst.get("uid", ""))
	var pend: Dictionary = s.pending_for(uid)
	if not pend.is_empty():
		var pto := str(DataStore.species(int(pend.get("to", 0))).get("name", "?"))
		return {"text": tr("» %s AWAITING APPROVAL") % pto, "color": ThemeBuilder.COL_GOOD,
			"tip": tr("Requirements met — approve or postpone the evolution from the Inbox or this Pokémon's profile.")}
	var opts: Array = s.eligibility(inst)
	if opts.is_empty():
		return {"text": tr("final form"), "color": Color("3a4058"),
			"tip": tr("%s does not evolve — development here is pure stat growth.") % _display_name(inst)}
	# nearest milestone: an ok option first, else the first with a readable gap
	for o in opts:
		if o["ok"]:
			if str(o["method"]) == "stone":
				return {"text": tr("» %s (use stone)") % o["to_name"], "color": ThemeBuilder.COL_ACCENT,
					"tip": tr("A stone in the storeroom can evolve it today — Items screen, or the profile's evolution panel.")}
			return {"text": tr("» %s ready") % o["to_name"], "color": ThemeBuilder.COL_GOOD,
				"tip": tr("Requirements met — the offer will land in your Inbox on the next training day.")}
	var best: Dictionary = opts[0]
	var txt := "» %s · %s" % [best["to_name"], best["why"]]
	var tip := tr("Development points from training push evolution milestones: %d pts = +1 effective level.\nDev so far: %d pts (+%d eff. levels).") % [
		_evo_dev_per_level(), int(s.dev_points(uid)), int(s.dev_levels(uid))]
	if str(best["method"]) == "stone":
		tip += tr("\nStone routes are bought in the Items screen and applied from there or the profile.")
	if opts.size() > 1:
		tip += tr("\nBranches: ") + ", ".join(opts.map(func(o): return str(o["to_name"])))
	return {"text": txt, "color": ThemeBuilder.COL_WARN if str(best["method"]) != "stone" else ThemeBuilder.COL_ACCENT, "tip": tip}
