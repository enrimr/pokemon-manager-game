extends RefCounted
## Squad piece: shared UI helper statics (badges, monograms, icons, colors, formatting).
## Preloaded (no class_name to avoid global namespace collisions with other pieces).

const COL_TEXT := Color("d6dae6")
const COL_TEXT_DIM := Color("8b91a8")
const COL_GOOD := Color("57c979")
const COL_WARN := Color("e0b050")
const COL_BAD := Color("e06060")
const COL_PANEL := Color("1a1f2e")
const COL_PANEL_ALT := Color("222840")
const COL_BORDER := Color("2e3550")
const COL_ACCENT := Color("7b6cff")

static var _icon_cache: Dictionary = {}

const TYPE_ABBR := {
	"normal": "NOR", "fire": "FIR", "water": "WAT", "grass": "GRA", "electric": "ELE",
	"ice": "ICE", "fighting": "FIG", "poison": "POI", "ground": "GRO", "flying": "FLY",
	"psychic": "PSY", "bug": "BUG", "rock": "ROC", "ghost": "GHO", "dragon": "DRA",
}


static func type_abbr(t: String) -> String:
	return TYPE_ABBR.get(t, t.substr(0, 3).to_upper())


## Small solid pill texture: one or two type colors side-by-side. Cached.
static func type_icon(types: Array, w: int = 22, h: int = 12) -> ImageTexture:
	var key := "ti:%s:%d:%d" % ["/".join(PackedStringArray(types)), w, h]
	if _icon_cache.has(key):
		return _icon_cache[key]
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var c1: Color = DataStore.type_color(types[0])
	var c2: Color = DataStore.type_color(types[1]) if types.size() > 1 else c1
	for x in w:
		for y in h:
			var edge := x == 0 or y == 0 or x == w - 1 or y == h - 1
			var c: Color = c1 if x < w / 2 else c2
			img.set_pixel(x, y, c.darkened(0.35) if edge else c)
	var tex := ImageTexture.create_from_image(img)
	_icon_cache[key] = tex
	return tex


## Small filled circle icon (morale dots etc). Cached by color.
static func dot_icon(col: Color, d: int = 11) -> ImageTexture:
	var key := "dot:%s:%d" % [col.to_html(), d]
	if _icon_cache.has(key):
		return _icon_cache[key]
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := d / 2.0 - 0.5
	var cx := (d - 1) / 2.0
	for x in d:
		for y in d:
			var dist := Vector2(x - cx, y - cx).length()
			if dist <= r:
				img.set_pixel(x, y, col if dist <= r - 1.0 else col.darkened(0.3))
	var tex := ImageTexture.create_from_image(img)
	_icon_cache[key] = tex
	return tex


## Type badge control: colored pill with uppercase type name.
static func type_badge(t: String, font_size: int = 11) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	var c: Color = DataStore.type_color(t)
	sb.bg_color = c
	sb.border_color = c.darkened(0.3)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = t.to_upper()
	l.add_theme_font_size_override("font_size", font_size)
	var lum := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
	l.add_theme_color_override("font_color", Color("11141d") if lum > 0.5 else Color("f2f4fa"))
	p.add_child(l)
	return p


## Monogram square: primary type color background, 2-letter initials.
static func monogram(display_name: String, types: Array, size: int = 64, font_size: int = 26) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(size, size)
	var c: Color = DataStore.type_color(types[0]) if types.size() > 0 else Color("555b77")
	var sb := StyleBoxFlat.new()
	sb.bg_color = c.darkened(0.15)
	sb.border_color = c.lightened(0.25)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	p.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = display_name.substr(0, 2).to_upper()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	var lum := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
	l.add_theme_color_override("font_color", Color("11141d") if lum > 0.5 else Color("f2f4fa"))
	p.add_child(l)
	return p


# ------------------------------------------------------------------ colors

static func pct_color(v: int) -> Color:
	if v >= 85:
		return COL_GOOD
	if v >= 65:
		return Color("a8c96a")
	if v >= 45:
		return COL_WARN
	return COL_BAD


static func morale_word(v: int) -> String:
	if v >= 90:
		return "Superb"
	if v >= 75:
		return "Good"
	if v >= 55:
		return "Okay"
	if v >= 35:
		return "Poor"
	return "Abysmal"


static func rating_color(r: float) -> Color:
	if r >= 8.0:
		return COL_GOOD
	if r >= 7.0:
		return Color("a8c96a")
	if r >= 6.4:
		return COL_TEXT
	return COL_WARN


## FM-style attribute color for a 1-20 value.
static func attr_color(v: int) -> Color:
	if v >= 15:
		return COL_GOOD
	if v >= 10:
		return Color("b9c96a")
	if v >= 6:
		return COL_TEXT
	return Color("6b7089")


## Map a base stat (roughly 5..190) onto FM's 1-20 attribute scale.
static func base_to_20(base: int) -> int:
	return clampi(int(round(base / 9.0)), 1, 20)


# ------------------------------------------------------------------ formatting

static func money(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	out = s + out
	var cur: String = GameState.world["meta"]["currency"]
	return ("-" if n < 0 else "") + cur + out


static func age_str(months: int) -> String:
	return "%dy %dm" % [months / 12, months % 12]


static func age_stage(months: int) -> String:
	if months < 24:
		return "Developing"
	if months < 60:
		return "Peak years"
	if months < 84:
		return "Experienced"
	return "Veteran"


static func growth_label(g: String) -> String:
	match g:
		"fast": return "Fast"
		"medium_fast": return "Medium-Fast"
		"medium_slow": return "Medium-Slow"
		"slow": return "Slow"
	return g.capitalize()


static func days_between(from_date: String, to_date: String) -> int:
	var pa := from_date.split("-")
	var pb := to_date.split("-")
	var ua := Time.get_unix_time_from_datetime_dict({"year": int(pa[0]), "month": int(pa[1]),
		"day": int(pa[2]), "hour": 12, "minute": 0, "second": 0})
	var ub := Time.get_unix_time_from_datetime_dict({"year": int(pb[0]), "month": int(pb[1]),
		"day": int(pb[2]), "hour": 12, "minute": 0, "second": 0})
	return int((ub - ua) / 86400)


## Effective battle stats for a squad instance (same math the engine uses).
static func effective_stats(inst: Dictionary) -> Dictionary:
	var sp: Dictionary = DataStore.species(int(inst["species_id"]))
	var lvl := int(inst.get("level", 20))
	var ivs: Dictionary = inst.get("ivs", {})
	var base: Dictionary = sp["base"]
	var out := {}
	for k in ["hp", "atk", "def", "spa", "spd", "spe"]:
		out[k] = DataStore.calc_stat(int(base[k]), int(ivs.get(k, 8)), lvl, k == "hp")
	return out


static func display_name(inst: Dictionary) -> String:
	var nn = inst.get("nickname")
	return str(nn) if nn else str(inst["species"])


## Rough market value estimate from level, base stat total, IVs and age.
static func est_value(inst: Dictionary) -> int:
	var sp: Dictionary = DataStore.species(int(inst["species_id"]))
	var bst := 0
	for k in sp["base"]:
		bst += int(sp["base"][k])
	var iv_sum := 0
	var ivs: Dictionary = inst.get("ivs", {})
	for k in ivs:
		iv_sum += int(ivs[k])
	var age_mult := 1.0
	var m := int(inst.get("age_months", 36))
	if m < 24:
		age_mult = 1.3
	elif m >= 84:
		age_mult = 0.55
	elif m >= 60:
		age_mult = 0.8
	var v := float(bst) * float(inst["level"]) * (0.8 + iv_sum / 180.0) * age_mult * 9.0
	return int(round(v / 250.0)) * 250
