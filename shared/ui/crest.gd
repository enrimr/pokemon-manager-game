class_name Crest
extends Object
## Procedural club crests (crests piece). Every club gets an ORIGINAL
## gym-badge-style crest, deterministically derived from its stable id (shape,
## field pattern, monogram-or-not) and its squad's dominant Pokémon type (the
## motif and colours: flames for a fire core, waves for water, a gear for
## steel, …) — the same "one type = one identity" language gym leaders have.
## SVG composed by CrestSVG, rasterized at runtime and cached per club+px —
## identical pipeline to GlyphIcons/Portrait, export-build safe.
##
## API:
##   Crest.icon(club, px)  -> Control   (crest + optional monogram overlay)
##   Crest.tex(club, px)   -> Texture2D (raw crest texture, no letters)
##   Crest.params(club)    -> the design dict (cached per club id)

static var _cache: Dictionary = {}         # "id|px" -> Texture2D
static var _params_cache: Dictionary = {}  # id -> params

static var _font_bold: Font = null


## Dominant + secondary primary-type of the squad (primary slot weighs double).
static func _type_core(club: Dictionary) -> Array:
	var counts := {}
	for inst in club.get("squad", []):
		var sp: Dictionary = DataStore.species(int(inst.get("species_id", 0)))
		if sp.is_empty():
			continue
		var types: Array = sp.get("types", [])
		if types.size() > 0:
			counts[str(types[0])] = int(counts.get(str(types[0]), 0)) + 2
		if types.size() > 1:
			counts[str(types[1])] = int(counts.get(str(types[1]), 0)) + 1
	var ranked := counts.keys()
	ranked.sort_custom(func(a, b):
		if counts[a] != counts[b]:
			return counts[a] > counts[b]
		return str(a) < str(b))   # deterministic tie-break
	if ranked.is_empty():
		return ["normal", "normal"]
	return [str(ranked[0]), str(ranked[1]) if ranked.size() > 1 else str(ranked[0])]


static func _pick(seed: String, facet: String, n: int) -> int:
	return absi(("%s|%s" % [seed, facet]).hash()) % maxi(1, n)


static func params(club: Dictionary) -> Dictionary:
	var id := str(club.get("id", club.get("name", "club")))
	if _params_cache.has(id):
		return _params_cache[id]
	var core := _type_core(club)
	var t1 := str(core[0])
	var t2 := str(core[1])
	var c1: Color = DataStore.type_color(t1)
	var c2: Color = DataStore.type_color(t2)
	# per-club hue nudge so two same-type clubs never share the exact field
	c1.h = wrapf(c1.h + (float(_pick(id, "hue", 9)) - 4.0) * 0.008, 0.0, 1.0)
	var field := c1.darkened(0.42)
	field.s = minf(field.s * 1.1, 0.85)
	var field2 := c2.darkened(0.22) if t2 != t1 else c1.darkened(0.12)
	# gym identity: a normal-core squad with a clear second type wears THAT
	# motif — "normal" star crests would otherwise dominate the league
	var motif := t1
	if t1 == "normal" and t2 != "normal":
		motif = t2
	var p := {
		"type": t1, "type2": t2,
		"shape": CrestSVG.SHAPES[_pick(id, "shape", CrestSVG.SHAPES.size())],
		"pattern": CrestSVG.PATTERNS[_pick(id, "pattern", CrestSVG.PATTERNS.size())],
		"motif": motif,
		"letters": _pick(id, "letters", 100) < 45,   # ~half the league wears a monogram
		"border": _h(c1.lightened(0.22)),
		"field": _h(field), "field2": _h(field2),
		"ink": _h(c1.lightened(0.38)), "ink2": _h(field.darkened(0.35)),
	}
	_params_cache[id] = p
	return p


static func tex(club: Dictionary, px: int = 32) -> Texture2D:
	var id := str(club.get("id", club.get("name", "club")))
	var render_px: int = clampi(px * 2, 48, 192)   # 2x oversample, crisp downscale
	var key := "%s|%d" % [id, render_px]
	if _cache.has(key):
		return _cache[key]
	var svg := CrestSVG.compose(params(club))
	var img := Image.new()
	var err := img.load_svg_from_string(svg, float(render_px) / 96.0)
	if err != OK or img.is_empty():
		img = Image.create(render_px, render_px, false, Image.FORMAT_RGBA8)
		img.fill(DataStore.type_color(str(params(club)["type"])).darkened(0.3))
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t


## Crest control: texture + (per-design) monogram overlay + tooltip. A drop-in
## replacement for the old StyleBox monogram crests at every size.
static func icon(club: Dictionary, px: int = 32, opts: Dictionary = {}) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(px, px)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var r := TextureRect.new()
	r.texture = tex(club, px)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(r)
	var p := params(club)
	if bool(p["letters"]) and px >= 22 and not bool(opts.get("no_letters", false)):
		var l := Label.new()
		l.text = str(club.get("short", "?")).substr(0, 3)
		l.set_anchors_preset(Control.PRESET_FULL_RECT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		# monogram design reserves the zone under the top-riding motif
		# (divider at 40/96): centre the letters in that clear band
		l.offset_top = px * 0.24
		var fs := maxi(7, int(px * (0.30 if px < 40 else 0.26)))
		if _font_bold == null:
			var f := SystemFont.new()   # same stack the shell uses
			f.font_names = PackedStringArray(["Avenir Next", "Helvetica Neue", "Arial"])
			f.font_weight = 700
			_font_bold = f
		l.add_theme_font_override("font", _font_bold)
		l.add_theme_font_size_override("font_size", fs)
		l.add_theme_color_override("font_color", Color.WHITE)
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
		l.add_theme_constant_override("shadow_offset_y", 1)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(l)
	if not bool(opts.get("no_tooltip", false)):
		holder.tooltip_text = I18n.t("%s · %s-type core") % [str(club.get("name", "")),
			I18n.t(str(p["type"]).capitalize())]
		holder.mouse_filter = Control.MOUSE_FILTER_STOP
	return holder


static func _h(c: Color) -> String:
	return "#" + c.to_html(false)
