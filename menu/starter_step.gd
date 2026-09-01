extends Control
## Onboarding step 3 (menu piece): THE STARTER CEREMONY. The regional
## professor of the chosen club's league lays out the classic trio; the new
## manager picks a career-long protégé (mechanics: shared/sim/services/
## protege.gd) and may give it a nickname. FM-style masked stats: scout
## RANGES, not numbers — you pick with your heart plus a hint.

signal starter_selected(summary: Dictionary)
signal starter_confirmed

const Protege := preload("res://shared/sim/services/protege.gd")

var _font_bold: Font
var _font_semibold: Font
var _font_header: Font

var _league := ""
var _club_name := ""
var _selected: Dictionary = {}
var _cards: Array = []          # [{panel, id}]
var _cards_row: HBoxContainer
var _prof_title: Label
var _prof_text: Label
var _nick_edit: LineEdit
var _status: Label


func setup(bold: Font, semibold: Font, header: Font) -> void:
	_font_bold = bold
	_font_semibold = semibold
	_font_header = header


func nickname() -> String:
	return _nick_edit.text.strip_edges() if _nick_edit != null else ""


func selected_summary() -> Dictionary:
	return _selected


## Rebuild the trio when the chosen club (league) changes between visits.
func set_context(league_id: String, club_name: String) -> void:
	if league_id == _league and club_name == _club_name:
		return
	_league = league_id
	_club_name = club_name
	_selected = {}
	_refresh()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 10)
	add_child(col)

	_prof_title = Label.new()
	_prof_title.add_theme_font_override("font", _font_header)
	_prof_title.add_theme_font_size_override("font_size", 18)
	_prof_title.add_theme_color_override("font_color", Color.WHITE)
	col.add_child(_prof_title)

	_prof_text = Label.new()
	_prof_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prof_text.add_theme_font_size_override("font_size", 13)
	_prof_text.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	col.add_child(_prof_text)

	_cards_row = HBoxContainer.new()
	_cards_row.add_theme_constant_override("separation", 14)
	_cards_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_cards_row)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	var nick_lbl := Label.new()
	nick_lbl.text = tr("Nickname (optional)")
	nick_lbl.add_theme_font_override("font", _font_semibold)
	nick_lbl.add_theme_font_size_override("font_size", 12)
	foot.add_child(nick_lbl)
	_nick_edit = LineEdit.new()
	_nick_edit.placeholder_text = tr("A name only you would give it")
	_nick_edit.max_length = 20
	_nick_edit.custom_minimum_size = Vector2(280, 38)
	foot.add_child(_nick_edit)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.add_theme_font_override("font", _font_semibold)
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", ThemeBuilder.COL_WARN)
	foot.add_child(_status)
	col.add_child(foot)
	_refresh()


func _refresh() -> void:
	if _cards_row == null:
		return
	_prof_title.text = tr("%s IS WAITING IN THE LOBBY") % tr(Protege.professor_for_league(_league)).to_upper()
	_prof_text.text = tr("\"Welcome to %s, boss. Before the board gets its claws into you, an old tradition: every new manager in this league leaves my lab with a companion. Three Poké Balls, three temperaments. I won't show you their numbers — my scouts only deal in impressions. Pick with your heart. It will follow yours for the rest of your career... and mind the one you leave behind; another manager's hands are already hovering.\"") % _club_name
	for c in _cards_row.get_children():
		c.queue_free()
	_cards.clear()
	for id in Protege.trio_for_league(_league):
		var card := _build_card(int(id))
		_cards_row.add_child(card)
	_apply_styles()


func _select(id: int) -> void:
	var sp: Dictionary = DataStore.species(id)
	_selected = {"species_id": id, "name": str(sp["name"]),
		"types": (sp.get("types", []) as Array).duplicate()}
	_status.text = tr("The professor nods. %s it is.") % str(sp["name"])
	_status.add_theme_color_override("font_color", ThemeBuilder.COL_GOOD)
	_apply_styles()
	starter_selected.emit(_selected)


func _apply_styles() -> void:
	for e in _cards:
		var col: Color = e["color"]
		var on: bool = int(e["id"]) == int(_selected.get("species_id", -1))
		var sb := ThemeBuilder._flat(
			col.darkened(0.82) if on else ThemeBuilder.COL_PANEL_ALT,
			col.lightened(0.2) if on else ThemeBuilder.COL_BORDER, 10, 16, 14)
		sb.set_border_width_all(2 if on else 1)
		(e["panel"] as PanelContainer).add_theme_stylebox_override("panel", sb)


# ------------------------------------------------------------------ cards

func _blurb(id: int) -> String:
	match id:
		1: return tr("The dependable one. It naps in the sun outside the lab and never starts a fight — but it has never once backed out of one either. Patient, steady, blooms late and blooms big.")
		4: return tr("The heart-on-tail one. It follows the professor around like a small shadow and burns brightest when it has something to prove. Handle with warmth and it will scorch the record books.")
		7: return tr("The cheeky one. It hides in its shell, waits for you to look away, then soaks you. Loves a crowd, and plays visibly better when one is watching.")
		152: return tr("The sweet-scented one. It calms every room it walks into and sulks magnificently when ignored. Wins hearts first, battles shortly after.")
		155: return tr("The shy flame. It keeps its fire banked until the moment matters — then its back ignites and the room goes quiet. Timid in the corridor, fearless between the lines.")
		158: return tr("The biter. It chews everything: ropes, benches, clipboards, reputations. Boundless energy that a patient manager could shape into something genuinely frightening.")
	return ""


func _hint(id: int) -> String:
	match id:
		1: return tr("Scout's whisper: grows into a wall that wins wars of patience.")
		4: return tr("Scout's whisper: the ceiling on this one frightens our instruments.")
		7: return tr("Scout's whisper: balanced everywhere, brittle nowhere. A captain someday.")
		152: return tr("Scout's whisper: the squad trains calmer on days it's around.")
		155: return tr("Scout's whisper: quickest ignition we have ever measured in a juvenile.")
		158: return tr("Scout's whisper: that jaw will decide cup ties one day.")
	return ""


## FM masked stats: the scouts translate base tendencies into RANGES on a
## five-star scale, deliberately fuzzy — impressions, not numbers.
func _band(v: float) -> Array:
	return [clampf(v - 0.75, 0.5, 5.0), clampf(v + 0.75, 1.0, 5.0)]


func _build_card(id: int) -> Control:
	var sp: Dictionary = DataStore.species(id)
	var types: Array = sp.get("types", [])
	var col: Color = DataStore.type_color(str(types[0]) if not types.is_empty() else "normal")
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	# monogram: type-coloured disc + initial (no copyrighted art, ever)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var mono := PanelContainer.new()
	mono.custom_minimum_size = Vector2(56, 56)
	mono.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var msb := StyleBoxFlat.new()
	msb.bg_color = col.darkened(0.35)
	msb.border_color = col.lightened(0.25)
	msb.set_border_width_all(2)
	msb.set_corner_radius_all(28)
	mono.add_theme_stylebox_override("panel", msb)
	var letter := Label.new()
	letter.text = str(sp["name"]).substr(0, 1)
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	letter.add_theme_font_override("font", _font_header)
	letter.add_theme_font_size_override("font_size", 26)
	letter.add_theme_color_override("font_color", Color.WHITE)
	mono.add_child(letter)
	head.add_child(mono)
	var name_col := VBoxContainer.new()
	name_col.alignment = BoxContainer.ALIGNMENT_CENTER
	name_col.add_theme_constant_override("separation", 2)
	var nm := Label.new()
	nm.text = str(sp["name"])
	nm.add_theme_font_override("font", _font_bold)
	nm.add_theme_font_size_override("font_size", 19)
	nm.add_theme_color_override("font_color", Color.WHITE)
	name_col.add_child(nm)
	var ty := Label.new()
	ty.text = I18n.types_join(types, " / ")
	ty.add_theme_font_size_override("font_size", 12)
	ty.add_theme_color_override("font_color", col.lightened(0.35))
	name_col.add_child(ty)
	head.add_child(name_col)
	box.add_child(head)

	var blurb := Label.new()
	blurb.text = _blurb(id)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size.y = 96
	blurb.add_theme_font_size_override("font_size", 13)
	blurb.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT)
	box.add_child(blurb)
	box.add_child(HSeparator.new())

	# masked scout ranges (no exact numbers anywhere on this panel)
	var base: Dictionary = sp.get("base", {})
	var atk := maxf(float(base.get("atk", 50)), float(base.get("spa", 50)))
	var dfn := (float(base.get("def", 50)) + float(base.get("spd", 50)) + float(base.get("hp", 50))) / 3.0
	var spe := float(base.get("spe", 50))
	for row in [[tr("Attack"), _band(atk / 66.0 * 3.2)], [tr("Defense"), _band(dfn / 66.0 * 3.2)],
			[tr("Speed"), _band(spe / 66.0 * 3.2)]]:
		box.add_child(_range_row(str(row[0]), row[1], ThemeBuilder.COL_ACCENT.lightened(0.25)))
	box.add_child(_range_row(tr("Potential"), [4.5, 5.0], Color("e8c15a")))

	var hint := Label.new()
	hint.text = _hint(id)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	box.add_child(hint)

	var btn := Button.new()
	btn.text = tr("I choose %s") % str(sp["name"])
	btn.custom_minimum_size.y = 38
	btn.add_theme_font_override("font", _font_semibold)
	btn.pressed.connect(func(): _select(id))
	box.add_child(btn)

	panel.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			if int(_selected.get("species_id", -1)) == id and ev.double_click:
				starter_confirmed.emit()
			else:
				_select(id))
	_cards.append({"panel": panel, "id": id, "color": col})
	return panel


func _range_row(label: String, band: Array, col: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 92
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	row.add_child(l)
	var stars := TextureRect.new()
	stars.texture = GlyphIcons.rating_range_tex(float(band[0]), float(band[1]), 5, 13, col)
	stars.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	row.add_child(stars)
	return row
