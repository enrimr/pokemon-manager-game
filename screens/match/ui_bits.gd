extends RefCounted
## Small factory helpers shared by the match views (badges, bars, panels).

const COL_PANEL := Color("1a1f2e")
const COL_PANEL_ALT := Color("222840")
const COL_BORDER := Color("2e3550")
const COL_ACCENT := Color("7b6cff")
const COL_TEXT := Color("d6dae6")
const COL_DIM := Color("8b91a8")
const COL_GOOD := Color("57c979")
const COL_BAD := Color("e06060")
const COL_WARN := Color("e0b050")

const STATUS_COLORS := {
	"burn": Color("f08030"), "para": Color("f8d030"), "sleep": Color("8b91a8"),
	"poison": Color("a040a0"), "freeze": Color("98d8d8"), "confused": Color("e0b050"),
}
const STATUS_SHORT := {
	"burn": "BRN", "para": "PAR", "sleep": "SLP", "poison": "PSN", "freeze": "FRZ",
	"confused": "CNF",
}


static func panel(title: String = "", alt := false) -> Array:
	## Returns [PanelContainer, VBoxContainer content].
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL_ALT if alt else COL_PANEL
	sb.border_color = COL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	p.add_child(box)
	if title != "":
		var t := Label.new()
		t.text = I18n.t(title).to_upper()
		t.add_theme_font_size_override("font_size", 11)
		t.add_theme_color_override("font_color", COL_DIM)
		box.add_child(t)
	return [p, box]


static func label(text: String, size := 14, color := COL_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func type_badge(type: String, size := 11) -> Label:
	var l := Label.new()
	l.text = I18n.type_name(type).to_upper()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color("11141d"))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = DataStore.type_color(type)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	l.add_theme_stylebox_override("normal", sb)
	return l


static func status_chip(status: String, size := 11) -> Label:
	var l := Label.new()
	l.text = STATUS_SHORT.get(status, status.to_upper())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color("11141d"))
	var sb := StyleBoxFlat.new()
	sb.bg_color = STATUS_COLORS.get(status, COL_DIM)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	l.add_theme_stylebox_override("normal", sb)
	return l


static func monogram(short_name: String, color: Color, diameter := 34) -> Control:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(diameter, diameter)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(int(diameter / 2.0))
	p.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.text = short_name.substr(0, 3)
	l.add_theme_font_size_override("font_size", int(diameter * 0.32))
	l.add_theme_color_override("font_color", Color.WHITE)
	p.add_child(l)
	return p


static func club_color(club: Dictionary) -> Color:
	## Deterministic identity color from the club id (no copyrighted art).
	var h := absi(str(club.get("id", "x")).hash())
	return Color.from_hsv(float(h % 360) / 360.0, 0.55, 0.72)


static func hp_color(frac: float) -> Color:
	if frac > 0.5:
		return COL_GOOD
	if frac > 0.22:
		return COL_WARN
	return COL_BAD


static func hbox(sep := 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func vbox(sep := 6) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func spacer_h() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func spacer_v() -> Control:
	var c := Control.new()
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


static func stage_text(stages: Dictionary) -> String:
	## Compact "+2 Atk  -1 Spe" summary of non-zero stat stages.
	var names := {"atk": "Atk", "def": "Def", "spa": "SpA", "spd": "SpD",
		"spe": "Spe", "acc": "Acc", "eva": "Eva"}
	var parts: Array = []
	for k in ["atk", "def", "spa", "spd", "spe", "acc", "eva"]:
		var v := int(stages.get(k, 0))
		if v != 0:
			var arrows := ("+".repeat(mini(v, 3)) if v > 0 else "−".repeat(mini(-v, 3)))
			parts.append("%s%s" % [arrows, I18n.t(names[k])])
	return "  ".join(parts)


static func result_chip(won: bool) -> Label:
	var l := Label.new()
	l.text = "W" if won else "L"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(22, 22)
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color("11141d"))
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_GOOD if won else COL_BAD
	sb.set_corner_radius_all(3)
	l.add_theme_stylebox_override("normal", sb)
	return l
