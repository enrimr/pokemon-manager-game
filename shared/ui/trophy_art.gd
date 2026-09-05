class_name TrophyArt
extends Object
## Procedural pixel-art trophy (cup-mail icon; same chunky-pixel language as
## PixelPortrait: dark plum outline, NEAREST upscale).
##
##   TrophyArt.tex(px, gold)          -> ImageTexture
##   TrophyArt.icon(px, opts)         -> TextureRect
## opts: {"color": Color (cup metal, default gold), "tooltip": String}

const N := 16
const OUT := Color8(38, 34, 54)

## 16x16 cup: 'o' outline · 'g' metal · 'l' shine · 'd' shade · '.' empty.
const MAP := [
	"................",
	"...oooooooooo...",
	".oollggggggddoo.",
	".oollggggggddoo.",
	".ooolggggggdooo.",
	"....olggggdo....",
	".....oggddo.....",
	"......oggo......",
	"......oggo......",
	"......oggo......",
	"....oggggggo....",
	"...oggggggggo...",
	"...oooooooooo...",
	"................",
	"................",
	"................",
]

static var _cache: Dictionary = {}


static func tex(px: int = 32, gold: Color = Color("e8c04a")) -> ImageTexture:
	var key := "%d|%s" % [px, gold.to_html()]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	var cols := {"o": OUT, "g": gold, "l": gold.lightened(0.4), "d": gold.darkened(0.28)}
	for y in MAP.size():
		var row: String = MAP[y]
		for x in row.length():
			var c := row[x]
			if cols.has(c):
				img.set_pixel(x, y, cols[c])
	var scale := maxi(1, int(ceil(float(px) / N)))
	img.resize(N * scale, N * scale, Image.INTERPOLATE_NEAREST)
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t


static func icon(px: int = 32, opts: Dictionary = {}) -> TextureRect:
	var r := TextureRect.new()
	var gold: Color = opts["color"] if opts.get("color") is Color else Color("e8c04a")
	r.texture = tex(px, gold)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.custom_minimum_size = Vector2(px, px)
	r.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if str(opts.get("tooltip", "")) != "":
		r.tooltip_text = str(opts["tooltip"])
		r.mouse_filter = Control.MOUSE_FILTER_STOP
	return r
