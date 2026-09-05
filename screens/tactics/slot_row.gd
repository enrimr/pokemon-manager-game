extends PanelContainer
## One battler row on the tactics board (starter slot or bench slot).
## Handles selection, drag & drop reordering and per-slot role assignment.

const Logic := preload("res://screens/tactics/tactics_logic.gd")

signal row_clicked(uid: String)
signal swap_requested(src_uid: String, dst_uid: String)
signal role_changed(uid: String, role: String)
signal nudge_requested(uid: String, dir: int)

var uid := ""
var is_starter := false
var _a: Dictionary = {}
var _role := "pivot"
var _selected := false
var _role_btn: OptionButton
var _pips: HBoxContainer
var _band_lbl: Label


func setup(analysis: Dictionary, slot_text: String, role_id: String, starter: bool) -> void:
	uid = analysis["uid"]
	_a = analysis
	_role = role_id
	is_starter = starter
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0, 60 if starter else 54)
	tooltip_text = tr("%s — drag onto another row to swap, or click two rows.") % _a["battler"]["name"]
	_restyle()

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	add_child(h)

	# nudge arrows
	var nudge := VBoxContainer.new()
	nudge.add_theme_constant_override("separation", 0)
	nudge.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(nudge)
	for dir in [-1, 1]:
		var b := Button.new()
		b.icon = GlyphIcons.tex("tri_up" if dir == -1 else "tri_down", 9, ThemeBuilder.COL_TEXT_DIM)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.flat = true
		b.custom_minimum_size = Vector2(16, 15)
		b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		b.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		b.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		b.focus_mode = Control.FOCUS_NONE
		var d: int = dir
		b.pressed.connect(func(): nudge_requested.emit(uid, d))
		nudge.add_child(b)

	# slot number
	var slot := Label.new()
	slot.text = slot_text
	slot.custom_minimum_size.x = 20
	slot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot.add_theme_font_size_override("font_size", 15)
	slot.add_theme_color_override("font_color",
		ThemeBuilder.COL_ACCENT if starter else ThemeBuilder.COL_TEXT_DIM)
	h.add_child(slot)

	# species sprite (falls back to the type-coloured monogram pre-sprites)
	h.add_child(_make_badge())

	# name / details
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 0)
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(info)

	var line1 := HBoxContainer.new()
	line1.add_theme_constant_override("separation", 6)
	info.add_child(line1)
	var name_l := Label.new()
	name_l.text = _a["battler"]["name"]
	name_l.add_theme_font_size_override("font_size", 14)
	name_l.add_theme_color_override("font_color", Color.WHITE)
	line1.add_child(name_l)
	var lv := Label.new()
	lv.text = tr("Lv %d") % int(_a["battler"]["level"])
	lv.add_theme_font_size_override("font_size", 11)
	lv.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	line1.add_child(lv)

	var line2 := HBoxContainer.new()
	line2.add_theme_constant_override("separation", 4)
	info.add_child(line2)
	for t in _a["types"]:
		var chip := Label.new()
		chip.text = str(t).to_upper().substr(0, 3)
		chip.add_theme_font_size_override("font_size", 9)
		chip.add_theme_color_override("font_color", Color("11141d"))
		var sb := StyleBoxFlat.new()
		sb.bg_color = DataStore.type_color(t)
		sb.set_corner_radius_all(2)
		sb.content_margin_left = 4
		sb.content_margin_right = 4
		sb.content_margin_top = 1
		sb.content_margin_bottom = 1
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", sb)
		pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pc.add_child(chip)
		line2.add_child(pc)
	var stats := Label.new()
	var st: Dictionary = _a["battler"]["stats"]
	stats.text = tr("HP %d  SPE %d  %d%%") % [int(st["hp"]), int(st["spe"]),
		int(_a["inst"].get("condition", 100))]
	stats.add_theme_font_size_override("font_size", 9)
	stats.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	line2.add_child(stats)

	var moves_l := Label.new()
	moves_l.text = " · ".join(_a["battler"].get("moves", []).map(func(m): return tr(str(m))))
	moves_l.clip_text = true
	moves_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	moves_l.add_theme_font_size_override("font_size", 9)
	moves_l.add_theme_color_override("font_color", Color("6d7390"))
	moves_l.tooltip_text = _moves_tooltip()
	info.add_child(moves_l)

	# role picker
	_role_btn = OptionButton.new()
	_role_btn.custom_minimum_size = Vector2(138, 30)
	_role_btn.add_theme_font_size_override("font_size", 11)
	_role_btn.fit_to_longest_item = false
	_role_btn.focus_mode = Control.FOCUS_NONE
	for i in Logic.ROLE_ORDER.size():
		var rid: String = Logic.ROLE_ORDER[i]
		var sc: int = Logic.role_score(rid, _a)["score"]
		_role_btn.add_item("%s  %d" % [tr(str(Logic.ROLES[rid]["name"])), sc], i)
		if rid == _role:
			_role_btn.select(i)
	_role_btn.item_selected.connect(_on_role_pick)
	h.add_child(_role_btn)

	# suitability pips + band
	var suit := VBoxContainer.new()
	suit.add_theme_constant_override("separation", 0)
	suit.alignment = BoxContainer.ALIGNMENT_CENTER
	suit.custom_minimum_size.x = 72
	h.add_child(suit)
	_pips = GlyphIcons.rating(0, 5, 10, ThemeBuilder.COL_TEXT_DIM)
	suit.add_child(_pips)
	_band_lbl = Label.new()
	_band_lbl.add_theme_font_size_override("font_size", 9)
	suit.add_child(_band_lbl)
	_refresh_suit()

	gui_input.connect(_on_gui)


func _moves_tooltip() -> String:
	var lines: Array = []
	for mn in _a["battler"].get("moves", []):
		var mv: Dictionary = DataStore.move(mn)
		if mv.is_empty():
			continue
		var pw := int(mv.get("power", 0))
		lines.append(I18n.t("%s — %s %s, %s, acc %s") % [tr(str(mn)), tr(str(mv["type"]).capitalize()),
			mv.get("category", ""), (tr("pow %d") % pw) if pw > 0 else tr("status"),
			str(int(mv.get("accuracy", 0))) + "%" if int(mv.get("accuracy", 0)) > 0 else "—"])
	return "\n".join(lines)


func set_selected(sel: bool) -> void:
	_selected = sel
	_restyle()


func _refresh_suit() -> void:
	var res: Dictionary = Logic.role_score(_role, _a)
	var score: int = res["score"]
	var b: Array = Logic.band(score)
	var filled := int(round(score / 20.0))
	GlyphIcons.set_rating(_pips, filled, b[1])
	_band_lbl.text = str(b[0])
	_band_lbl.add_theme_color_override("font_color", b[1])
	var tip := tr("%s as %s: %d/100 (%s)\n") % [_a["battler"]["name"], tr(Logic.ROLES[_role]["name"]), score, tr(str(b[0]))]
	for w in res["why"]:
		tip += "\n· " + str(w)
	_pips.tooltip_text = tip
	_band_lbl.tooltip_text = tip
	if _role_btn:
		_role_btn.tooltip_text = tr("%s\n\nSuited to: %s") % [tr(Logic.ROLES[_role]["desc"]), tr(Logic.ROLES[_role]["wants"])]


func _on_role_pick(idx: int) -> void:
	_role = Logic.ROLE_ORDER[idx]
	_refresh_suit()
	role_changed.emit(uid, _role)


func _on_gui(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
		row_clicked.emit(uid)


func _restyle() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = ThemeBuilder.COL_PANEL_ALT if is_starter else ThemeBuilder.COL_PANEL
	sb.border_color = ThemeBuilder.COL_ACCENT if _selected else ThemeBuilder.COL_BORDER
	sb.set_border_width_all(2 if _selected else 1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 6
	sb.content_margin_right = 8
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	add_theme_stylebox_override("panel", sb)


func _make_badge() -> Control:
	var sid := PokeArt.id_of(str(_a["battler"]["species"]))
	if sid > 0 and PokeArt.has_art(sid):
		return PokeArt.icon(sid, 32)
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(32, 32)
	var types: Array = _a["types"]
	var sb := StyleBoxFlat.new()
	sb.bg_color = DataStore.type_color(types[0]).darkened(0.25)
	sb.border_color = DataStore.type_color(types[1] if types.size() > 1 else types[0]).lightened(0.1)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(16)
	badge.add_theme_stylebox_override("panel", sb)
	var mono := Label.new()
	mono.text = str(_a["battler"]["species"]).substr(0, 1)
	mono.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mono.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mono.add_theme_font_size_override("font_size", 16)
	mono.add_theme_color_override("font_color", Color.WHITE)
	badge.add_child(mono)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mono.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return badge


# --------------------------------------------------------- drag & drop

func _get_drag_data(_pos: Vector2) -> Variant:
	var preview := Label.new()
	preview.text = "  %s  " % _a["battler"]["name"]
	preview.add_theme_color_override("font_color", Color.WHITE)
	var sb := StyleBoxFlat.new()
	sb.bg_color = ThemeBuilder.COL_ACCENT_DIM
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", sb)
	pc.add_child(preview)
	set_drag_preview(pc)
	return {"tactics_uid": uid}


func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.has("tactics_uid") and data["tactics_uid"] != uid


func _drop_data(_pos: Vector2, data: Variant) -> void:
	swap_requested.emit(data["tactics_uid"], uid)
