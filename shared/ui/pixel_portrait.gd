class_name PixelPortrait
extends Object
## EXPERIMENT (art piece): procedural pixel-art people, in the visual family
## of the bundled official trainer sprites (gen-V palette, hard 1px outline,
## NEAREST upscaling). Deterministic per name — same facet-hash discipline as
## Portrait/PortraitSVG — and diverse: 6 skins x 9 hairstyles x 10 hair
## colours x eyes/brows/mouth/extras x 6 outfits.
##
## Busts (head + shoulders) on a 24x24 canvas: that is what every avatar slot
## in the game actually shows, and the scale pixel art is forgiving at.
##
##   PixelPortrait.tex(seed, px, opts)    -> ImageTexture (px ~ multiple of 24)
##   PixelPortrait.avatar(seed, px, opts) -> TextureRect
## opts: {"collar": Color (club kit), "age": int (grey hair when veteran)}

const N := 24                        # canvas size
const OUT := Color8(38, 34, 54)      # unified outline (gen-V dark plum)

const SKINS := ["f5d5a7", "eec39a", "d9a066", "b07a4a", "8a5a33", "6b4226"]
const HAIRS := ["2b2b33", "5a3825", "8a5a2b", "c98a3a", "e8c04a", "c94a35",
	"7a4a8a", "3a6ac9", "3a8a5a", "c95a8a"]
const GREY := "b9b9c9"
const OUTFITS := ["c94a35", "3a6ac9", "3a8a5a", "e8c04a", "7a4a8a", "e07a3a",
	"52c7a8", "8b91a8"]

static var _cache: Dictionary = {}


static func _pick(seed: String, facet: String, n: int) -> int:
	return absi(("%s|%s" % [seed, facet]).hash()) % maxi(1, n)


static func tex(seed: String, px: int = 48, opts: Dictionary = {}) -> ImageTexture:
	var key := "%s|%d|%s" % [seed, px, str(opts.get("collar", ""))]
	if _cache.has(key):
		return _cache[key]
	var img := _draw(seed, opts)
	var scale := maxi(1, px / N)
	img.resize(N * scale, N * scale, Image.INTERPOLATE_NEAREST)
	var t := ImageTexture.create_from_image(img)
	if _cache.size() > 256:
		_cache.clear()
	_cache[key] = t
	return t


static func avatar(seed: String, px: int = 32, opts: Dictionary = {}) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex(seed, maxi(px, 24), opts)
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


# ------------------------------------------------------------------ drawing

static func _draw(seed: String, opts: Dictionary) -> Image:
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	var first := seed.split(" ", false)[0] if seed.strip_edges() != "" else ""
	var fem := Portrait.FEM_FIRST.has(first)
	if not fem and not Portrait.MASC_FIRST.has(first):
		fem = _pick(seed, "fem", 2) == 1   # unknown first names: stable coin flip

	var skin := Color(SKINS[_pick(seed, "skin", SKINS.size())])
	var skin_sh := skin.darkened(0.22)
	var hair_i := _pick(seed, "hair_c", HAIRS.size())
	var hair := Color(HAIRS[hair_i])
	if int(opts.get("age", 0)) >= 55 and _pick(seed, "grey", 3) > 0:
		hair = Color(GREY)
	if absf(hair.get_luminance() - skin.get_luminance()) < 0.14:
		hair = hair.darkened(0.30)   # blond-on-pale etc. must never read bald
	var hair_hi := hair.lightened(0.22)
	var style := _pick(seed, "hair_s", 9)
	var outfit := Color(OUTFITS[_pick(seed, "outfit", OUTFITS.size())])
	if opts.get("collar") is Color:
		outfit = opts["collar"]
	var outfit_sh := outfit.darkened(0.25)

	# --- shoulders/bust (rows 17..23): trapezoid widening down
	for y in range(17, N):
		var half := 5 + (y - 17)              # 5..11
		for x in range(12 - half, 12 + half):
			if x < 0 or x >= N:
				continue
			img.set_pixel(x, y, outfit if x < 12 else outfit_sh)
	# collar detail: V of skin at the neck + trim line
	for y in range(17, 19):
		for x in range(10, 14):
			img.set_pixel(x, y, skin_sh)
	var trim := _pick(seed, "trim", 4)
	if trim == 1:   # jacket zip / tie line
		for y in range(19, N):
			img.set_pixel(12, y, outfit.darkened(0.45))
	elif trim == 2: # scarf / crew band
		for x in range(7, 17):
			img.set_pixel(x, 19, outfit.lightened(0.3))
	elif trim == 3: # lab/suit lapels: pale V panel
		var lap := Color("e8e6f0") if _pick(seed, "coat", 2) == 0 else outfit.darkened(0.4)
		for y in range(19, N):
			var w := (y - 19) / 2 + 1
			for x in range(12 - w, 12 + w):
				img.set_pixel(x, y, lap)

	# --- neck (rows 15..17)
	for y in range(15, 18):
		for x in range(10, 14):
			img.set_pixel(x, y, skin_sh if y == 15 else skin)

	# --- head (rows 4..15): 10 wide, jaw variants
	var jaw := _pick(seed, "jaw", 3)          # 0 round, 1 square, 2 narrow
	for y in range(4, 16):
		var x0 := 7
		var x1 := 17
		if y <= 5:
			x0 = 8; x1 = 16
		if y >= 13:                           # chin taper
			match jaw:
				0: x0 = 8; x1 = 16
				1: x0 = 8; x1 = 16
				2: x0 = 9; x1 = 15
		if y == 15:
			x0 = 10; x1 = 14
			if jaw == 1:
				x0 = 9; x1 = 15
		for x in range(x0, x1):
			img.set_pixel(x, y, skin)
	# corner cuts: rounder skull + chin (kills the rectangle read)
	for pt in [[7, 4], [16, 4], [8, 4], [15, 4], [7, 5], [16, 5],
			[7, 12], [16, 12], [7, 13], [16, 13],
			[8, 14], [15, 14], [7, 14], [16, 14], [9, 15], [14, 15]]:
		if img.get_pixel(pt[0], pt[1]).is_equal_approx(skin):
			img.set_pixel(pt[0], pt[1], Color(0, 0, 0, 0))
	# soft cheek/jaw shading + nose + fringe shadow across the forehead
	img.set_pixel(15, 12, skin_sh)
	img.set_pixel(14, 14, skin_sh)
	img.set_pixel(9, 14, skin_sh)
	img.set_pixel(12, 12, skin_sh)              # nose
	for x in range(8, 16):
		if img.get_pixel(x, 9).is_equal_approx(skin):
			img.set_pixel(x, 9, skin.darkened(0.10))

	# --- eyes: bold 2x2 anime blocks + top-left catchlight (the refs read
	# from their big dark eyes — so must we)
	var eye := Color8(26, 24, 38)
	var eye_style := _pick(seed, "eyes", 3)
	for ex in [9, 13]:
		for dx in 2:
			img.set_pixel(ex + dx, 10, eye)
			img.set_pixel(ex + dx, 11, eye)
		if eye_style != 1:
			img.set_pixel(ex, 10, Color.WHITE.lerp(eye, 0.25))
		if eye_style == 2:                    # narrow: squint 1px tall
			img.set_pixel(ex, 10, skin)
			img.set_pixel(ex + 1, 10, skin)
	# brows (row 9, just under the fringe)
	if _pick(seed, "brow", 2) == 0:
		for ex in [9, 13]:
			img.set_pixel(ex, 9, Color(HAIRS[hair_i]).darkened(0.2))
			img.set_pixel(ex + 1, 9, Color(HAIRS[hair_i]).darkened(0.2))
	# mouth (row 13/14)
	var mouth := _pick(seed, "mouth", 3)
	var lip := skin_sh.darkened(0.45)
	img.set_pixel(11, 13, lip)
	img.set_pixel(12, 13, lip)
	if mouth == 0:                              # smile: corners up
		img.set_pixel(10, 13, lip)
	elif mouth == 2:                            # open grin
		img.set_pixel(11, 14, lip)
		img.set_pixel(12, 14, lip)
	# blush for some feminine faces
	if fem and _pick(seed, "blush", 3) == 0:
		img.set_pixel(8, 11, Color("e8908a"))
		img.set_pixel(15, 11, Color("e8908a"))
	# facial hair for some masculine faces
	if not fem and _pick(seed, "beard", 4) == 0:
		for x in range(9, 15):
			img.set_pixel(x, 14, hair)
		img.set_pixel(8, 13, hair)
		img.set_pixel(15, 13, hair)

	# --- hair (style painter). 8 = cap hat.
	match style:
		0: _hair_spiky(img, hair, hair_hi)
		1: _hair_bowl(img, hair, hair_hi)
		2: _hair_short(img, hair, hair_hi)
		3: _hair_long(img, hair, hair_hi)
		4: _hair_ponytail(img, hair, hair_hi)
		5: _hair_pigtails(img, hair, hair_hi)
		6: _hair_curly(img, hair, hair_hi)
		7: _hair_buzz(img, hair, hair_hi)
		8: _hat_cap(img, seed, hair)

	# --- unified 1px outline: any coloured pixel that touches emptiness
	var base := img.duplicate()
	for y in N:
		for x in N:
			if base.get_pixel(x, y).a == 0.0:
				continue
			var edge := x == 0 or y == 0 or x == N - 1 or y == N - 1
			if not edge:
				for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
					if base.get_pixel(x + d[0], y + d[1]).a == 0.0:
						edge = true
						break
			if edge:
				img.set_pixel(x, y, OUT)
	return img


# Painters own the whole scalp: a solid cap rows 3..8 (down to the brow) so
# nobody reads as bald, then the style's silhouette on top. Fringe leaves the
# eye rows (10+) clear.
static func _cap_base(img: Image, c: Color, hi: Color, fringe_y: int = 8) -> void:
	for x in range(7, 17):
		for y in range(3, fringe_y + 1):
			img.set_pixel(x, y, c)
	for x in range(9, 15):
		img.set_pixel(x, 3, hi)
	# temples framing the face
	for y in range(fringe_y, 11):
		img.set_pixel(7, y, c)
		img.set_pixel(16, y, c)


static func _hair_spiky(img: Image, c: Color, hi: Color) -> void:
	_cap_base(img, c, hi, 7)
	for x in [8, 11, 14]:        # three bold spikes
		img.set_pixel(x, 2, c)
		img.set_pixel(x + 1, 2, c)
		img.set_pixel(x, 1, hi if x == 11 else c)
	img.set_pixel(17, 4, c)      # flick at the temple
	img.set_pixel(6, 4, c)
	# jagged fringe: alternate teeth over the forehead
	for x in range(8, 16):
		if x % 2 == 0:
			img.set_pixel(x, 8, c)


static func _hair_bowl(img: Image, c: Color, hi: Color) -> void:
	_cap_base(img, c, hi, 8)
	for y in range(9, 12):
		img.set_pixel(7, y, c)
		img.set_pixel(8, y, c)
		img.set_pixel(15, y, c)
		img.set_pixel(16, y, c)


static func _hair_short(img: Image, c: Color, hi: Color) -> void:
	_cap_base(img, c, hi, 7)
	for x in range(8, 16):
		if x <= 11:
			img.set_pixel(x, 8, c)   # side-swept fringe


static func _hair_long(img: Image, c: Color, hi: Color) -> void:
	_cap_base(img, c, hi, 8)
	for y in range(9, 21):
		for x in [5, 6, 17, 18]:
			img.set_pixel(x, y, c if x <= 6 else c.darkened(0.12))
	for y in range(9, 13):
		img.set_pixel(7, y, c)
		img.set_pixel(16, y, c)


static func _hair_ponytail(img: Image, c: Color, hi: Color) -> void:
	_cap_base(img, c, hi, 7)
	for y in range(3, 16):
		img.set_pixel(18, y, c)
		img.set_pixel(19, y, c.darkened(0.12))
	img.set_pixel(18, 3, hi)
	img.set_pixel(17, 4, c)


static func _hair_pigtails(img: Image, c: Color, hi: Color) -> void:
	_cap_base(img, c, hi, 8)
	for y in range(5, 14):
		for x in [4, 5]:
			img.set_pixel(x, y, c)
		for x in [18, 19]:
			img.set_pixel(x, y, c.darkened(0.12))
	img.set_pixel(4, 5, hi)


static func _hair_curly(img: Image, c: Color, hi: Color) -> void:
	_cap_base(img, c, hi, 8)
	for x in range(6, 18):
		if (x % 3) != 1:
			img.set_pixel(x, 2, c)
		if x % 4 == 2:
			img.set_pixel(x, 1, c)
	for y in range(8, 12):
		img.set_pixel(6, y, c)
		img.set_pixel(17, y, c)
	img.set_pixel(8, 2, hi)
	img.set_pixel(13, 2, hi)


static func _hair_buzz(img: Image, c: Color, _hi: Color) -> void:
	var cc := c.darkened(0.35)   # always darker than any skin tone
	for x in range(7, 17):
		for y in range(3, 7):
			img.set_pixel(x, y, cc)
	for y in range(7, 9):
		img.set_pixel(7, y, cc)
		img.set_pixel(16, y, cc)


static func _hat_cap(img: Image, seed: String, hair: Color) -> void:
	var cap := Color(OUTFITS[_pick(seed, "cap_c", OUTFITS.size())])
	for x in range(7, 17):
		for y in range(2, 7):
			img.set_pixel(x, y, cap)
	for x in range(13, 20):      # brim to the right
		img.set_pixel(x, 7, cap.darkened(0.2))
	for x in range(9, 12):       # front panel
		img.set_pixel(x, 3, cap.lightened(0.25))
	for x in range(7, 17):       # fringe under the cap
		img.set_pixel(x, 7, hair)
	for y in range(8, 10):       # sideburns
		img.set_pixel(7, y, hair)
		img.set_pixel(16, y, hair)
