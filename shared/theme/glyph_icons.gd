class_name GlyphIcons
extends Object
## Engine-drawn replacements for unicode symbol glyphs (the web build only
## ships the bundled font — geometric shapes / arrows / dingbats render as
## tofu boxes there). Icons are tiny SVG strings rasterized at runtime via
## Image.load_svg_from_string, cached per (kind, px, colors).
##
## API:
##   GlyphIcons.tex(kind, px, col)            -> Texture2D   (Button.icon, TreeItem.set_icon, RTL.add_image)
##   GlyphIcons.icon(kind, px, col)           -> TextureRect (inline in containers)
##   GlyphIcons.rating(filled, total, px, c)  -> HBoxContainer of pips (kind "dot" or "star")
##   GlyphIcons.set_rating(row, filled, col)  -> update a rating row in place

static var _cache: Dictionary = {}


static func tex(kind: String, px: int = 12, col: Color = Color.WHITE, col2: Color = Color.TRANSPARENT) -> Texture2D:
	var key := "%s|%d|%s|%s" % [kind, px, col.to_html(), col2.to_html()]
	if _cache.has(key):
		return _cache[key]
	var img := Image.new()
	var err := img.load_svg_from_string(_svg(kind, col, col2), float(px) / 24.0)
	if err != OK or img.is_empty():
		img = Image.create(px, px, false, Image.FORMAT_RGBA8)
		img.fill(col)  # visible square fallback, never tofu
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t


static func icon(kind: String, px: int = 12, col: Color = Color.WHITE) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex(kind, px, col)
	r.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	r.custom_minimum_size = Vector2(px, px)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func rating(filled: int, total: int, px: int = 11, col: Color = Color.WHITE, kind: String = "dot") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", maxi(1, px / 5))
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.set_meta("rating_kind", kind)
	row.set_meta("rating_px", px)
	for i in total:
		row.add_child(icon(kind if i < filled else kind + "_empty", px, col))
	return row


static func set_rating(row: HBoxContainer, filled: int, col: Color) -> void:
	var kind: String = row.get_meta("rating_kind", "dot")
	var px: int = row.get_meta("rating_px", 11)
	var i := 0
	for c in row.get_children():
		if c is TextureRect:
			c.texture = tex(kind if i < filled else kind + "_empty", px, col)
			i += 1


## One texture of a whole star meter (supports halves: v = 3.5). Usable where
## only a single texture fits (TreeItem.set_icon, Button.icon).
static func rating_tex(v: float, total: int = 5, px: int = 12, col: Color = Color("e8c15a"), empty_col: Color = Color("494f68"), kind: String = "star") -> Texture2D:
	var key := "meter|%s|%.1f|%d|%d|%s|%s" % [kind, v, total, px, col.to_html(), empty_col.to_html()]
	if _cache.has(key):
		return _cache[key]
	var gap := maxi(1, px / 6)
	var img := Image.create(total * (px + gap), px, false, Image.FORMAT_RGBA8)
	var full := int(v)
	var half := v - float(full) >= 0.49
	for i in total:
		var t: Texture2D
		if i < full:
			t = tex(kind, px, col)
		elif i == full and half:
			t = tex(kind + "_half", px, col, empty_col)
		else:
			t = tex(kind + "_empty", px, empty_col)
		var cell := t.get_image()
		cell.convert(Image.FORMAT_RGBA8)
		img.blend_rect(cell, Rect2i(0, 0, px, px), Vector2i(i * (px + gap), 0))
	var out := ImageTexture.create_from_image(img)
	_cache[key] = out
	return out


## "lo – hi" star-meter range as one texture (for Tree cells).
static func rating_range_tex(lo: float, hi: float, total: int = 5, px: int = 12, col: Color = Color("e8c15a"), empty_col: Color = Color("494f68")) -> Texture2D:
	var key := "range|%.1f|%.1f|%d|%d|%s|%s" % [lo, hi, total, px, col.to_html(), empty_col.to_html()]
	if _cache.has(key):
		return _cache[key]
	var a := rating_tex(lo, total, px, col, empty_col).get_image()
	var b := rating_tex(hi, total, px, col, empty_col).get_image()
	a.convert(Image.FORMAT_RGBA8)
	b.convert(Image.FORMAT_RGBA8)
	var dash := maxi(6, px / 2 + 2)
	var img := Image.create(a.get_width() + dash + 4 + b.get_width(), px, false, Image.FORMAT_RGBA8)
	img.blend_rect(a, Rect2i(0, 0, a.get_width(), px), Vector2i.ZERO)
	img.fill_rect(Rect2i(a.get_width() + 2, px / 2 - 1, dash, 2), empty_col.lightened(0.2))
	img.blend_rect(b, Rect2i(0, 0, b.get_width(), px), Vector2i(a.get_width() + dash + 4, 0))
	var out := ImageTexture.create_from_image(img)
	_cache[key] = out
	return out


const _STAR := "12 2.5 14.9 9.2 22 9.9 16.6 14.7 18.2 21.8 12 18 5.8 21.8 7.4 14.7 2 9.9 9.1 9.2"


static func _svg(kind: String, col: Color, col2: Color) -> String:
	var c := "#" + col.to_html(false)
	var o := col.a
	var c2 := "#" + col2.to_html(false)
	var body := ""
	match kind:
		"dot":
			body = '<circle cx="12" cy="12" r="7" fill="%s"/>' % c
		"dot_empty":
			body = '<circle cx="12" cy="12" r="6" fill="none" stroke="%s" stroke-width="2.2"/>' % c
		"star":
			body = '<polygon points="%s" fill="%s"/>' % [_STAR, c]
		"star_empty":
			body = '<polygon points="%s" fill="none" stroke="%s" stroke-width="1.7"/>' % [_STAR, c]
		"star_half":  # left half col, outline col2
			body = ('<polygon points="%s" fill="none" stroke="%s" stroke-width="1.7"/>' % [_STAR, c2]) + \
				('<clipPath id="h"><rect x="0" y="0" width="12" height="24"/></clipPath>' +
				'<polygon points="%s" fill="%s" clip-path="url(#h)"/>' % [_STAR, c])
		"tri_up":
			body = '<polygon points="12,4 21.5,19 2.5,19" fill="%s"/>' % c
		"tri_down":
			body = '<polygon points="12,20 21.5,5 2.5,5" fill="%s"/>' % c
		"tri_right":
			body = '<polygon points="5,3 20.5,12 5,21" fill="%s"/>' % c
		"tri_left":
			body = '<polygon points="19,3 3.5,12 19,21" fill="%s"/>' % c
		"tri_right_hollow":
			body = '<polygon points="6,4.5 19,12 6,19.5" fill="none" stroke="%s" stroke-width="2.2"/>' % c
		"caret_down":
			body = '<polygon points="4,7.5 20,7.5 12,17.5" fill="%s"/>' % c
		"caret_right":
			body = '<polygon points="7.5,4 17.5,12 7.5,20" fill="%s"/>' % c
		"arrow_right":
			body = '<path d="M3 12h15M12 5.5l6.5 6.5-6.5 6.5" fill="none" stroke="%s" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/>' % c
		"arrow_left":
			body = '<path d="M21 12H6M12 5.5L5.5 12l6.5 6.5" fill="none" stroke="%s" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/>' % c
		"arrow_up":
			body = '<path d="M12 21V6M5.5 12L12 5.5l6.5 6.5" fill="none" stroke="%s" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/>' % c
		"arrow_down":
			body = '<path d="M12 3v15M5.5 12l6.5 6.5 6.5-6.5" fill="none" stroke="%s" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/>' % c
		"diamond":
			body = '<polygon points="12,2.5 21.5,12 12,21.5 2.5,12" fill="%s"/>' % c
		"diamond_hollow":
			body = '<polygon points="12,3.5 20.5,12 12,20.5 3.5,12" fill="none" stroke="%s" stroke-width="2.2"/>' % c
		"check":
			body = '<path d="M4 13l5 5L20 6" fill="none" stroke="%s" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>' % c
		"cross":
			body = '<path d="M5.5 5.5l13 13M18.5 5.5l-13 13" fill="none" stroke="%s" stroke-width="2.8" stroke-linecap="round"/>' % c
		"drag_handle", "menu":
			body = '<path d="M4 6.5h16M4 12h16M4 17.5h16" fill="none" stroke="%s" stroke-width="2.4" stroke-linecap="round"/>' % c
		"pause":
			body = '<rect x="5.5" y="4" width="4.6" height="16" fill="%s"/><rect x="13.9" y="4" width="4.6" height="16" fill="%s"/>' % [c, c]
		"fast_forward":
			body = '<polygon points="3,5 12,12 3,19" fill="%s"/><polygon points="12,5 21,12 12,19" fill="%s"/>' % [c, c]
		"skip":
			body = '<polygon points="4,4.5 16,12 4,19.5" fill="%s"/><rect x="17" y="4.5" width="3" height="15" fill="%s"/>' % [c, c]
		"skip_all":
			body = '<polygon points="2,5.5 10,12 2,18.5" fill="%s"/><polygon points="10,5.5 18,12 10,18.5" fill="%s"/><rect x="19" y="5.5" width="2.8" height="13" fill="%s"/>' % [c, c, c]
		"swap":
			body = '<path d="M4 8h13M13.5 4.5L17 8l-3.5 3.5M20 16H7M10.5 12.5L7 16l3.5 3.5" fill="none" stroke="%s" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round"/>' % c
		"undo":
			body = '<path d="M6.5 9A8 7.2 0 1 1 5 14.5" fill="none" stroke="%s" stroke-width="2.4" stroke-linecap="round"/><polygon points="2.5,4.5 9.5,6 4.5,11" fill="%s"/>' % [c, c]
		"warning":
			body = ('<polygon points="12,3 22,20.5 2,20.5" fill="none" stroke="%s" stroke-width="2" stroke-linejoin="round"/>' % c) + \
				('<rect x="10.9" y="9" width="2.2" height="6" rx="1" fill="%s"/><circle cx="12" cy="17.6" r="1.4" fill="%s"/>' % [c, c])
		"flag":
			body = '<path d="M6 21V4" stroke="%s" stroke-width="2.4" stroke-linecap="round"/><path d="M7 4.5h11l-3 4 3 4H7z" fill="%s"/>' % [c, c]
		"umbrella":
			body = ('<path d="M3 12a9 9 0 0 1 18 0z" fill="%s"/>' % c) + \
				('<path d="M12 12v7a2 2 0 0 1-4 0" fill="none" stroke="%s" stroke-width="2.2" stroke-linecap="round"/>' % c)
		"target":
			body = '<circle cx="12" cy="12" r="8.5" fill="none" stroke="%s" stroke-width="2.2"/><circle cx="12" cy="12" r="3" fill="%s"/>' % [c, c]
		"bag":
			body = ('<rect x="2.5" y="8.5" width="19" height="11.5" rx="2" fill="%s"/>' % c) + \
				('<path d="M8 8.5V7a2.5 2.5 0 0 1 2.5-2.5h3A2.5 2.5 0 0 1 16 7v1.5" fill="none" stroke="%s" stroke-width="2.2"/>' % c)
		"spin0", "spin1", "spin2", "spin3":
			var rot := 90 * int(kind.substr(4))
			body = '<g transform="rotate(%d 12 12)"><path d="M12 3a9 9 0 0 1 9 9" fill="none" stroke="%s" stroke-width="3.2" stroke-linecap="round"/></g>' % [rot, c]
		_:
			body = '<rect x="4" y="4" width="16" height="16" fill="%s"/>' % c
	return '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g opacity="%.2f">%s</g></svg>' % [o, body]
