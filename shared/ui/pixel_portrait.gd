class_name PixelPortrait
extends Object
## Procedural pixel-art people (art piece), v2: 48x48 busts in the visual
## family of the bundled official trainer sprites — gen-V palette, hard 1px
## unified outline, big Pokémon-style eyes (sclera + coloured iris + catch-
## light), banded hair shading. Deterministic per name (facet hashes) and
## diverse: 6 skins x 9 hairstyles x 10 hair colours x 5 iris colours x
## brows/mouths/blush/beards x outfits with club-collar override + greying.
##
##   PixelPortrait.tex(seed, px, opts)    -> ImageTexture
##   PixelPortrait.avatar(seed, px, opts) -> TextureRect
## opts: {"collar": Color (club kit), "age": int, "tooltip": String}

const N := 48
const OUT := Color8(38, 34, 54)      # unified outline (gen-V dark plum)
const CX := 24                       # head centre column

const SKINS := ["f5d5a7", "eec39a", "d9a066", "b07a4a", "8a5a33", "6b4226"]
const HAIRS := ["2b2b33", "5a3825", "8a5a2b", "c98a3a", "e8c04a", "c94a35",
	"7a4a8a", "3a6ac9", "3a8a5a", "c95a8a"]
const IRISES := ["5a3825", "3a6ac9", "3a8a5a", "b06a2a", "7a4a8a"]
const GREY := "b9b9c9"
const OUTFITS := ["c94a35", "3a6ac9", "3a8a5a", "e8c04a", "7a4a8a", "e07a3a",
	"52c7a8", "8b91a8"]

static var _cache: Dictionary = {}


static func _pick(seed: String, facet: String, n: int) -> int:
	return absi(("%s|%s" % [seed, facet]).hash()) % maxi(1, n)


static func tex(seed: String, px: int = 48, opts: Dictionary = {}) -> ImageTexture:
	var key := "%s|%d|%s|%s|%s|%s" % [seed, px, str(opts.get("collar", "")),
		str(opts.get("pose", "")), str(opts.get("hair_s", "")), str(opts.get("hair_c", ""))]
	if _cache.has(key):
		return _cache[key]
	var img := _draw(seed, opts)
	if px >= 56:
		# big slots get the EPX/Scale2x treatment: 48 -> 96 edge-aware pixel
		# doubling — finer curves, same palette, still honest pixel art
		img = _scale2x(img)
	var side_n := img.get_width()
	var scale := maxi(1, int(round(float(px) / float(side_n))))
	img.resize(side_n * scale, side_n * scale, Image.INTERPOLATE_NEAREST)
	var t := ImageTexture.create_from_image(img)
	if _cache.size() > 256:
		_cache.clear()
	_cache[key] = t
	return t


static func avatar(seed: String, px: int = 32, opts: Dictionary = {}) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex(seed, maxi(px, N), opts)
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


# ------------------------------------------------------------------ helpers

## EPX/Scale2x: each pixel becomes 2x2, corners adopt a neighbour when two
## orthogonal neighbours agree — curves round off, no new colours appear.
static func _scale2x(src: Image) -> Image:
	var n := src.get_width()
	var dst := Image.create(n * 2, n * 2, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var p := src.get_pixel(x, y)
			var a := src.get_pixel(x, y - 1) if y > 0 else p
			var c := src.get_pixel(x - 1, y) if x > 0 else p
			var bb := src.get_pixel(x + 1, y) if x < n - 1 else p
			var d := src.get_pixel(x, y + 1) if y < n - 1 else p
			var e0 := p
			var e1 := p
			var e2 := p
			var e3 := p
			if c.is_equal_approx(a) and not c.is_equal_approx(d) and not a.is_equal_approx(bb):
				e0 = a
			if a.is_equal_approx(bb) and not a.is_equal_approx(c) and not bb.is_equal_approx(d):
				e1 = bb
			if d.is_equal_approx(c) and not d.is_equal_approx(bb) and not c.is_equal_approx(a):
				e2 = c
			if bb.is_equal_approx(d) and not bb.is_equal_approx(a) and not d.is_equal_approx(c):
				e3 = bb
			dst.set_pixel(x * 2, y * 2, e0)
			dst.set_pixel(x * 2 + 1, y * 2, e1)
			dst.set_pixel(x * 2, y * 2 + 1, e2)
			dst.set_pixel(x * 2 + 1, y * 2 + 1, e3)
	return dst


static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and x < N and y >= 0 and y < N:
		img.set_pixel(x, y, c)


static func _rect(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			_px(img, x, y, c)


## Horizontal-scanline ellipse fill.
static func _ellipse(img: Image, cx: int, cy: int, rx: float, ry: float, c: Color) -> void:
	for y in range(cy - int(ry), cy + int(ry) + 1):
		var t := (float(y) - cy) / ry
		var w := rx * sqrt(maxf(0.0, 1.0 - t * t))
		for x in range(cx - int(round(w)), cx + int(round(w)) + 1):
			_px(img, x, y, c)


# ------------------------------------------------------------------ drawing

static func _draw(seed: String, opts: Dictionary) -> Image:
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	var first := seed.split(" ", false)[0] if seed.strip_edges() != "" else ""
	var fem := Portrait.FEM_FIRST.has(first)
	if not fem and not Portrait.MASC_FIRST.has(first):
		fem = _pick(seed, "fem", 2) == 1

	var skin := Color(SKINS[_pick(seed, "skin", SKINS.size())])
	var skin_sh := skin.darkened(0.18)
	var hair_i := int(opts.get("hair_c", _pick(seed, "hair_c", HAIRS.size()))) % HAIRS.size()
	var hair := Color(HAIRS[hair_i])
	if int(opts.get("age", 0)) >= 55 and _pick(seed, "grey", 3) > 0:
		hair = Color(GREY)
	if absf(hair.get_luminance() - skin.get_luminance()) < 0.14:
		hair = hair.darkened(0.30)
	var hair_sh := hair.darkened(0.22)
	var hair_hi := hair.lightened(0.20)
	var style := int(opts.get("hair_s", _pick(seed, "hair_s", 14)))
	var iris := Color(IRISES[_pick(seed, "iris", IRISES.size())])
	var outfit := Color(OUTFITS[_pick(seed, "outfit", OUTFITS.size())])
	if opts.get("collar") is Color:
		outfit = opts["collar"]
	var outfit_sh := outfit.darkened(0.25)
	var outfit_hi := outfit.lightened(0.18)

	# --- pose (user request): the head lives on its own layer so it can turn
	# and lean; arms get their own painters on the body layer.
	#   0-2 front · 3 turn L · 4 turn R · 5 lean · 6 arms crossed · 7 hand up
	var pose := int(opts.get("pose", _pick(seed, "pose", 8)))
	var turn := -1 if pose == 3 else (1 if pose == 4 else 0)
	var fdx := turn * 2                    # facial features slide into the turn
	var head_dx := turn                    # whole head follows, gently
	var head_dy := 0
	if pose == 5:
		head_dx = 1 if _pick(seed, "leandir", 2) == 0 else -1
		head_dy = 1

	# --- shoulders/bust (rows 34..47): ROUNDED slope (ease-out curve), body
	# build variants, arm seams and a left key light
	var build := _pick(seed, "build", 3)      # 0 slim, 1 average, 2 broad
	var max_half := 14 + build                # final width at the bottom row
	var wave_side := 0                        # which side raises the ball (pose 7)
	if pose == 7:
		wave_side = 1 if _pick(seed, "wavedir", 2) == 0 else -1
	for y in range(34, N):
		var t2 := clampf(float(y - 34) / 7.0, 0.0, 1.0)
		var ease := 1.0 - (1.0 - t2) * (1.0 - t2)          # fast then settle
		var half := 5 + int(round(ease * float(max_half - 5)))
		# lean pose: the shoulder opposite the lean rides one row higher;
		# ball pose: the raising shoulder SHRUGS two rows up
		var raise_l := 0
		var raise_r := 0
		if pose == 5 and y < 40:
			raise_l = 1 if head_dx > 0 else 0
			raise_r = 1 if head_dx < 0 else 0
		elif pose == 7 and y < 42:
			raise_l = 2 if wave_side == -1 else 0
			raise_r = 2 if wave_side == 1 else 0
		var tl := clampf(float(y - 34 + raise_l) / 7.0, 0.0, 1.0)
		var tr := clampf(float(y - 34 + raise_r) / 7.0, 0.0, 1.0)
		var half_l := 5 + int(round((1.0 - (1.0 - tl) * (1.0 - tl)) * float(max_half - 5)))
		var half_r := 5 + int(round((1.0 - (1.0 - tr) * (1.0 - tr)) * float(max_half - 5)))
		if pose != 5 and pose != 7:
			half_l = half
			half_r = half
		for x in range(CX - half_l, CX + half_r + 1):
			_px(img, x, y, outfit if x < CX + 2 else outfit_sh)
	# arm seams: a darker vertical line where the sleeves start (skipped on
	# the side that raises the Poké Ball — it read as a third arm)
	for y in range(40, N):
		if wave_side != -1:
			_px(img, CX - max_half + 3, y, outfit_sh.darkened(0.18))
		if wave_side != 1:
			_px(img, CX + max_half - 3, y, outfit_sh.darkened(0.25))
	# key light along the left shoulder curve
	for y in range(35, 40):
		var t3 := clampf(float(y - 34) / 7.0, 0.0, 1.0)
		var e3 := 1.0 - (1.0 - t3) * (1.0 - t3)
		var hx := CX - (5 + int(round(e3 * float(max_half - 5)))) + 1
		_px(img, hx, y, outfit_hi)
		_px(img, hx + 1, y, outfit_hi)
	# fabric fold hints on the chest (not under crossed arms)
	if pose != 6:
		_px(img, CX - 6, 43, outfit_sh)
		_px(img, CX - 5, 44, outfit_sh)
		_px(img, CX + 7, 44, outfit_sh.darkened(0.12))
	# collar/neckline variants
	var trim := _pick(seed, "trim", 4)
	if trim == 0:              # V-neck kit: pale tee under
		for dy in 5:
			for x in range(CX - 4 + dy, CX + 5 - dy):
				_px(img, x, 34 + dy, Color("e8e6f0") if dy >= 2 else skin_sh)
	elif trim == 1:            # zipped jacket: centre line + collar flaps
		for y in range(36, N):
			_px(img, CX, y, outfit.darkened(0.45))
		_rect(img, CX - 6, 35, CX - 2, 37, outfit_hi)
		_rect(img, CX + 2, 35, CX + 6, 37, outfit_hi)
	elif trim == 2:            # crew band / scarf
		for x in range(CX - 8, CX + 9):
			_px(img, x, 36, outfit.lightened(0.35))
			_px(img, x, 37, outfit.lightened(0.35))
	else:                      # lapels: lab coat (pale) or suit (dark)
		var lap := Color("e8e6f0") if _pick(seed, "coat", 2) == 0 else outfit.darkened(0.42)
		for y in range(35, N):
			var w := 1 + (y - 35) / 2
			for x in range(CX - w, CX + w + 1):
				_px(img, x, y, lap)

	# --- neck (rows 29..35)
	_rect(img, CX - 3, 29, CX + 3, 35, skin)
	for x in range(CX - 3, CX + 4):
		_px(img, x, 29, skin_sh)
		_px(img, x, 30, skin_sh)

	# --- arms (body layer, before the head so long hair falls over them)
	if pose == 6:
		_arms_crossed(img, outfit, outfit_sh, skin)

	# --- head layer: ellipse + jaw variants (features slide by fdx on a turn)
	var head := Image.create(N, N, false, Image.FORMAT_RGBA8)
	var jaw := _pick(seed, "jaw", 3)          # 0 round, 1 square, 2 narrow
	var rx := 10.0 if jaw != 2 else 9.0
	_ellipse(head, CX, 19, rx, 11.0, skin)
	# chin: a real taper (the old full-width blocks squared every face)
	var chin_w := [6, 5, 3] if jaw != 1 else [7, 6, 4]
	for i in 3:
		for x in range(CX - int(chin_w[i]), CX + int(chin_w[i]) + 1):
			_px(head, x, 27 + i, skin)
	if jaw == 1:                              # square: a touch more jawline
		_px(head, CX - 8, 25, skin)
		_px(head, CX + 8, 25, skin)
	# ears at eye height — on a turn only the trailing ear stays visible
	if turn >= 0:
		_rect(head, CX - 12, 19, CX - 11, 23, skin)
		_px(head, CX - 11, 21, skin_sh)
	if turn <= 0:
		_rect(head, CX + 11, 19, CX + 12, 23, skin)
		_px(head, CX + 11, 21, skin_sh)
	# jaw shading (falls on the side away from the gaze)
	for x in range(CX + 3 - fdx, CX + 8 - fdx):
		_px(head, x, 27, skin_sh)
	for x in range(CX - 3, CX + 4):
		_px(head, x, 28 if jaw != 1 else 29, skin.darkened(0.10))
	# turned head: shade the vacated cheek so the face reads rotated
	if turn != 0:
		for y in range(19, 27):
			_px(head, CX - turn * 8, y, skin_sh)
			_px(head, CX - turn * 9, y, skin_sh)

	# --- eyes (rows 18..23): big sclera + iris + pupil + catchlight
	var eye_style := _pick(seed, "eyes", 3)
	var lash := Color8(30, 28, 40)
	for side in [-1, 1]:
		var x0 := CX + fdx + (2 if side > 0 else -8)
		var x1 := x0 + 6
		if eye_style == 2:                       # narrow/squint
			_rect(head, x0 + 1, 21, x1 - 1, 22, Color.WHITE)
			_rect(head, x0 + 2, 21, x1 - 2, 22, iris)
			for x in range(x0 + 1, x1):
				_px(head, x, 20, lash)
		else:
			_rect(head, x0 + 1, 19, x1 - 1, 23, Color.WHITE)
			_rect(head, x0 + 2, 19, x1 - 2, 23, iris)
			_rect(head, x0 + 3, 21, x1 - 3, 22, iris.darkened(0.45))  # pupil
			_px(head, x0 + 2, 19, Color.WHITE)                        # catchlight
			for x in range(x0 + 1, x1):
				_px(head, x, 18, lash)                                # lash line
	# brows
	var brow := Color(HAIRS[hair_i]).darkened(0.25)
	var brow_y := 15 + _pick(seed, "brow_h", 2)
	for side in [-1, 1]:
		for dx in range(2, 7):
			_px(head, CX + fdx + side * dx, brow_y, brow)
		_px(head, CX + fdx + side * 6, brow_y + 1, brow)

	# --- nose + mouth
	_px(head, CX + fdx + 1, 25, skin_sh.darkened(0.15))
	_px(head, CX + fdx + 1, 24, skin_sh)
	var mouth := _pick(seed, "mouth", 3)
	var lip := skin_sh.darkened(0.45)
	if mouth == 0:                            # smile
		for x in range(CX + fdx - 2, CX + fdx + 3):
			_px(head, x, 27, lip)
		_px(head, CX + fdx - 3, 26, lip)
		_px(head, CX + fdx + 3, 26, lip)
	elif mouth == 1:                          # neutral
		for x in range(CX + fdx - 2, CX + fdx + 3):
			_px(head, x, 27, lip)
	else:                                     # open grin
		for x in range(CX + fdx - 2, CX + fdx + 3):
			_px(head, x, 26, lip)
			_px(head, x, 27, Color("e8908a").darkened(0.2))
		for x in range(CX + fdx - 1, CX + fdx + 2):
			_px(head, x, 28, lip)
	# blush
	if fem and _pick(seed, "blush", 3) == 0:
		for side in [-1, 1]:
			_px(head, CX + fdx + side * 7, 24, Color("e8908a"))
			_px(head, CX + fdx + side * 8, 24, Color("e8908a"))
	# facial hair: full beard / moustache / goatee (masc facet)
	if not fem:
		var fh := _pick(seed, "beard", 8)   # 0 beard · 1 moustache · 2 goatee
		if fh == 0:
			for x in range(CX - 6, CX + 7):
				_px(head, x, 29, hair_sh)
				if absi(x - CX) > 2:
					_px(head, x, 28, hair_sh)
			_rect(head, CX - 7, 25, CX - 6, 28, hair_sh)
			_rect(head, CX + 6, 25, CX + 7, 28, hair_sh)
		elif fh == 1:
			for x in range(CX + fdx - 3, CX + fdx + 4):   # moustache over the lip
				_px(head, x, 26, hair_sh)
			_px(head, CX + fdx - 3, 27, hair_sh)
			_px(head, CX + fdx + 3, 27, hair_sh)
		elif fh == 2:
			_rect(head, CX - 2, 28, CX + 2, 29, hair_sh)  # goatee on the chin
	# a glint of an earring inside the ear (silhouette-safe for despeckle)
	if _pick(seed, "earring", 5) == 0:
		if turn >= 0:
			_px(head, CX - 11, 22, Color("e8c04a"))
		if turn <= 0:
			_px(head, CX + 11, 22, Color("e8c04a"))

	# --- glasses (facet ~1 in 6): round or rectangular frames + temple arms
	if _pick(seed, "specs", 6) == 0:
		var fr := Color8(40, 38, 58) if _pick(seed, "spec_c", 2) == 0 else Color("6b5a2b")
		var rounded := _pick(seed, "spec_s", 2) == 0
		for side in [-1, 1]:
			var gx0 := CX + fdx + (1 if side > 0 else -9)
			var gx1 := gx0 + 8
			for x in range(gx0 + 1, gx1):
				_px(head, x, 17, fr)
				_px(head, x, 24, fr)
			for y in range(18, 24):
				_px(head, gx0 if not rounded or (y > 18 and y < 23) else gx0 + 1, y, fr)
				_px(head, gx1 if not rounded or (y > 18 and y < 23) else gx1 - 1, y, fr)
		_px(head, CX + fdx, 20, fr)          # bridge
		_px(head, CX + fdx - 1, 20, fr)
		_px(head, CX + fdx + 1, 20, fr)
		for side2 in [-1, 1]:                # temple arms to the ears
			_px(head, CX + side2 * 10, 19, fr)
			_px(head, CX + side2 * 11, 20, fr)

	# --- hair (drawn on the head layer so it turns/leans with it)
	match style:
		0: _hair_spiky(head, hair, hair_sh, hair_hi)
		1: _hair_bowl(head, hair, hair_sh, hair_hi)
		2: _hair_swept(head, hair, hair_sh, hair_hi)
		3: _hair_long(head, hair, hair_sh, hair_hi)
		4: _hair_ponytail(head, hair, hair_sh, hair_hi)
		5: _hair_pigtails(head, hair, hair_sh, hair_hi)
		6: _hair_curly(head, hair, hair_sh, hair_hi)
		7: _hair_buzz(head, hair, hair_sh)
		8: _hat_cap(head, seed, hair, hair_sh, turn)
		9: _hair_afro(head, hair, hair_sh, hair_hi)
		10: _hair_mohawk(head, hair, hair_sh, hair_hi)
		11: _hair_bun(head, hair, hair_sh, hair_hi)
		12: _hair_braid(head, hair, hair_sh, hair_hi)
		13: _hair_messy(head, hair, hair_sh, hair_hi)

	# --- compose: head over body, shifted by the pose
	img.blend_rect(head, Rect2i(0, 0, N, N), Vector2i(head_dx, head_dy))

	# --- raised hand (after the head: the hand waves in front)
	if pose == 7:
		_hand_up(img, seed, outfit, outfit_sh, skin, max_half)

	# --- clean-up passes (pixel-art polish): despeckle 1px nubs off the
	# silhouette, fill 1px notches, THEN outline, then soften stair corners
	_despeckle(img)
	_fill_notches(img)
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
	_soften_corners(img)
	return img


## A filled pixel with <= 1 filled orthogonal neighbour is a stray nub
## sticking off the silhouette — delete it (two passes catch chains of 2).
static func _despeckle(img: Image) -> void:
	for _pass in 2:
		var base := img.duplicate()
		for y in N:
			for x in N:
				if base.get_pixel(x, y).a == 0.0:
					continue
				var n := 0
				for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
					var nx: int = x + d[0]
					var ny: int = y + d[1]
					if nx >= 0 and nx < N and ny >= 0 and ny < N 							and base.get_pixel(nx, ny).a > 0.0:
						n += 1
				if n <= 1:
					img.set_pixel(x, y, Color(0, 0, 0, 0))


## An empty pixel walled in by >= 3 filled orthogonal neighbours is a nick
## in the silhouette — fill it with a neighbour's colour.
static func _fill_notches(img: Image) -> void:
	var base := img.duplicate()
	for y in range(1, N - 1):
		for x in range(1, N - 1):
			if base.get_pixel(x, y).a > 0.0:
				continue
			var n := 0
			var fill := Color(0, 0, 0, 0)
			for d in [[0, -1], [1, 0], [-1, 0], [0, 1]]:
				var c: Color = base.get_pixel(x + int(d[0]), y + int(d[1]))
				if c.a > 0.0:
					n += 1
					if fill.a == 0.0:
						fill = c
			if n >= 3:
				img.set_pixel(x, y, fill)


## Selective anti-aliasing, the hand-polish trick of the official sprites:
## a fill pixel cornered by TWO orthogonal outline pixels sits on a stair
## step — pull it partway toward the outline so the jaggy melts.
static func _soften_corners(img: Image) -> void:
	var base := img.duplicate()
	for y in range(1, N - 1):
		for x in range(1, N - 1):
			var c: Color = base.get_pixel(x, y)
			if c.a == 0.0 or c.is_equal_approx(OUT):
				continue
			var h: bool = base.get_pixel(x - 1, y).is_equal_approx(OUT) 				or base.get_pixel(x + 1, y).is_equal_approx(OUT)
			var v: bool = base.get_pixel(x, y - 1).is_equal_approx(OUT) 				or base.get_pixel(x, y + 1).is_equal_approx(OUT)
			if h and v:
				img.set_pixel(x, y, c.lerp(OUT, 0.42))


# ------------------------------------------------------------------ hair
# Every style owns the scalp: dome over the skull down to the brow line with
# a highlight arc + a shadow row where hair meets forehead, then silhouette.

static func _dome(img: Image, c: Color, sh: Color, hi: Color, fringe_y: int = 15) -> void:
	# skull-hugging cap CLIPPED at the fringe line — never over the eyes
	for y in range(3, fringe_y + 1):
		var t := (float(y) - 15.0) / 12.0
		var w := 12.0 * sqrt(maxf(0.0, 1.0 - t * t))
		for x in range(CX - int(round(w)), CX + int(round(w)) + 1):
			_px(img, x, y, c)
	# shadow where the fringe sits on the forehead
	for x in range(CX - 8, CX + 9):
		_px(img, x, fringe_y + 1, sh)
	# highlight arc top-left
	for x in range(CX - 7, CX):
		_px(img, x, 7, hi)
		_px(img, x + 1, 8, hi)
	# temples framing the face
	_rect(img, CX - 11, fringe_y, CX - 10, 20, c)
	_rect(img, CX + 10, fringe_y, CX + 11, 20, c)


static func _hair_spiky(img: Image, c: Color, sh: Color, hi: Color) -> void:
	_dome(img, c, sh, hi, 14)
	# four soft tufts: chunky 2px-stepped mounds, not needles
	for s in [[-9, 3], [-3, 4], [3, 4], [8, 3]]:
		var sx: int = CX + int(s[0])
		var hgt: int = int(s[1])
		for h in range(hgt):
			var w := maxi(2, 4 - h)
			for k in range(w):
				_px(img, sx + k, 6 - h, hi if h == hgt - 1 else c)
	# fringe teeth: paired pixels so the clean-up keeps them
	for x in range(CX - 8, CX + 9, 4):
		_px(img, x, 16, c)
		_px(img, x + 1, 16, c)
		_px(img, x, 17, sh)
		_px(img, x + 1, 17, sh)


static func _hair_bowl(img: Image, c: Color, sh: Color, hi: Color) -> void:
	_dome(img, c, sh, hi, 16)
	# curtains to the jaw
	_rect(img, CX - 12, 14, CX - 10, 26, c)
	_rect(img, CX + 10, 14, CX + 12, 26, sh)


static func _hair_swept(img: Image, c: Color, sh: Color, hi: Color) -> void:
	_dome(img, c, sh, hi, 13)
	# diagonal fringe sweeping right (clipped above the lash line)
	for x in range(CX - 10, CX + 8):
		var drop := mini(int(float(x - (CX - 10)) / 3.2), 3)
		_px(img, x, 14 + drop, c)
		if x < CX:
			_px(img, x, mini(15 + drop, 17), c)
	_rect(img, CX + 9, 13, CX + 11, 19, c)


static func _hair_long(img: Image, c: Color, sh: Color, hi: Color) -> void:
	_dome(img, c, sh, hi, 15)
	# flowing curtains to the shoulders
	for y in range(15, 40):
		var wob := 0 if y < 30 else (1 if y % 4 < 2 else 0)
		_rect(img, CX - 14 - wob, y, CX - 11, y, c)
		_rect(img, CX + 11, y, CX + 14 + wob, y, sh)
	for y in range(15, 38, 4):   # strand highlights
		_px(img, CX - 13, y, hi)
		_px(img, CX + 12, y, c)


static func _hair_ponytail(img: Image, c: Color, sh: Color, hi: Color) -> void:
	_dome(img, c, sh, hi, 13)
	# pulled-back look: tail arcing down the right
	for y in range(8, 30):
		var sway := int(2.5 * sin(float(y - 8) * 0.30))
		_rect(img, CX + 12 + sway, y, CX + 14 + sway, y, c if y < 20 else sh)
	_px(img, CX + 13, 9, hi)
	_px(img, CX + 13, 10, hi)
	# fringe wisp
	for x in range(CX - 8, CX - 2):
		_px(img, x, 14, c)


static func _hair_pigtails(img: Image, c: Color, sh: Color, hi: Color) -> void:
	_dome(img, c, sh, hi, 15)
	for side in [-1, 1]:
		var bx: int = CX + side * 14
		_ellipse(img, bx, 16, 3.0, 5.0, c if side < 0 else sh)
		_px(img, bx - 1, 12, hi)
		# tie pixel where the bunch meets the head
		_px(img, CX + side * 11, 14, c.darkened(0.4))


static func _hair_curly(img: Image, c: Color, sh: Color, hi: Color) -> void:
	_dome(img, c, sh, hi, 15)
	# bumpy crown: little circles along the silhouette
	for b in [[-10, 9], [-6, 6], [-1, 5], [4, 6], [9, 8]]:
		_ellipse(img, CX + int(b[0]), int(b[1]), 2.6, 2.6, c)
		_px(img, CX + int(b[0]) - 1, int(b[1]) - 1, hi)
	_rect(img, CX - 12, 14, CX - 10, 23, c)
	_rect(img, CX + 10, 14, CX + 12, 23, sh)


static func _hair_buzz(img: Image, c: Color, sh: Color) -> void:
	var cc := c.darkened(0.30)
	for y in range(5, 14):
		var t := (float(y) - 13.0) / 9.0
		var w := 11.0 * sqrt(maxf(0.0, 1.0 - t * t))
		for x in range(CX - int(round(w)), CX + int(round(w)) + 1):
			_px(img, x, y, cc)
	for x in range(CX - 8, CX + 9):
		_px(img, x, 14, sh.darkened(0.2))


static func _hat_cap(img: Image, seed: String, hair: Color, hair_sh: Color,
		turn: int = 0) -> void:
	# a cap must READ as a cap (user note): flatter dome, a crown seam, and a
	# bold 2-row brim jutting well past the face — and the brim FOLLOWS THE
	# GAZE on turned heads (user note #2); front-facing folk vary by seed
	var dir := turn if turn != 0 else (1 if _pick(seed, "capdir", 2) == 0 else -1)
	var cap := Color(OUTFITS[_pick(seed, "cap_c", OUTFITS.size())])
	for y in range(5, 14):
		var t := (float(y) - 13.0) / 9.0
		var w := 12.0 * sqrt(maxf(0.0, 1.0 - t * t))
		for x in range(CX - int(round(w)), CX + int(round(w)) + 1):
			_px(img, x, y, cap)
	# crown seams + button (baseball-cap panels)
	_px(img, CX, 4, cap.darkened(0.35))
	for y in range(5, 12):
		_px(img, CX, y, cap.darkened(0.18))
	_rect(img, CX - 5 * dir, 7, CX - 1 * dir, 12, cap.lightened(0.20))  # lit front panel
	# THE BRIM: 3 rows tall (user note: beefier), flat, well past the head
	for k in range(-3, 18):
		_px(img, CX + k * dir, 14, cap.lightened(0.10))
		_px(img, CX + k * dir, 15, cap)
		_px(img, CX + k * dir, 16, cap.darkened(0.25))
	# fringe peeking under the brim (doubles as the brim's cast shadow)
	for k in range(-8, 6):
		_px(img, CX + k * dir, 17, hair_sh)
	# hair peeking at the back (opposite the brim) + sideburns
	for y in range(14, 20):
		_px(img, CX - 11 * dir, y, hair)
		_px(img, CX - 10 * dir, y, hair)
	for y in range(16, 20):
		_px(img, CX + 10 * dir, y, hair_sh)


static func _hair_afro(img: Image, c: Color, sh: Color, hi: Color) -> void:
	# big proud sphere, well past the skull, with a lit crescent
	_ellipse(img, CX, 10, 14.0, 9.5, c)
	for y in range(3, 9):
		var t := (float(y) - 10.0) / 9.5
		var w := 14.0 * sqrt(maxf(0.0, 1.0 - t * t))
		_px(img, CX - int(round(w)) + 1, y, hi)
		_px(img, CX - int(round(w)) + 2, y, hi)
	# sits down the sides of the face
	_rect(img, CX - 14, 10, CX - 11, 22, c)
	_rect(img, CX + 11, 10, CX + 14, 22, sh)
	for x in range(CX - 9, CX + 10):
		_px(img, x, 16, sh)


static func _hair_mohawk(img: Image, c: Color, sh: Color, hi: Color) -> void:
	# clean-shaven sides (bare skin) + a tall central crest, punk style
	for y in range(1, 15):
		var cw := 2 if y > 5 else 1
		for x in range(CX - cw, CX + cw + 1):
			_px(img, x, y, c if y > 3 else hi)
	for x in range(CX - 3, CX + 4):   # crest root shadow on the scalp
		_px(img, x, 13, sh)
	# a hint of stubble above the ears
	for x in range(CX - 10, CX - 7):
		_px(img, x, 12, sh.darkened(0.1))
	for x in range(CX + 8, CX + 11):
		_px(img, x, 12, sh.darkened(0.1))


static func _hair_bun(img: Image, c: Color, sh: Color, hi: Color) -> void:
	# slick pulled-back hair + top knot
	_dome(img, c, sh, hi, 13)
	_ellipse(img, CX, 3, 4.0, 3.0, c)
	_px(img, CX - 2, 2, hi)
	_px(img, CX - 1, 2, hi)
	for x in range(CX - 3, CX + 4):   # tie shadow under the knot
		_px(img, x, 6, sh)


static func _hair_braid(img: Image, c: Color, sh: Color, hi: Color) -> void:
	# framed dome + a plait falling over the right shoulder
	_dome(img, c, sh, hi, 15)
	_rect(img, CX - 12, 14, CX - 10, 24, c)
	var bx := CX + 11
	for y in range(14, 38):
		var wob := 1 if (y / 3) % 2 == 0 else 0
		_rect(img, bx + wob, y, bx + 2 + wob, y, c if (y / 3) % 2 == 0 else sh)
	_px(img, bx + 1, 38, sh)          # tuft at the tip
	_px(img, bx + 1, 15, hi)


static func _hair_messy(img: Image, c: Color, sh: Color, hi: Color) -> void:
	# bedhead: dome + strands poking out at odd angles
	_dome(img, c, sh, hi, 15)
	for s in [[-12, 9, -1], [-9, 5, -1], [-3, 3, 0], [3, 3, 0], [8, 5, 1], [11, 9, 1]]:
		var sx: int = CX + int(s[0])
		var sy: int = int(s[1])
		var lean: int = int(s[2])
		for k in 2:
			_px(img, sx + lean * k, sy - k, c)
			_px(img, sx + lean * k + 1, sy - k, c if k == 0 else hi)
	# uneven fringe teeth
	for x in range(CX - 9, CX + 10, 2):
		_px(img, x, 16, c)
		if x % 4 == 0:
			_px(img, x, 17, c)


# ------------------------------------------------------------------ arms

## Arms folded across the chest: two sleeve bars meeting at the middle, a
## tucked hand peeking at each elbow.
static func _arms_crossed(img: Image, outfit: Color, outfit_sh: Color, skin: Color) -> void:
	var sleeve := outfit.darkened(0.12)
	for y in range(41, 46):
		for x in range(CX - 12, CX + 13):
			_px(img, x, y, sleeve if y < 44 else outfit_sh.darkened(0.1))
	# the two forearms cross: a seam sloping each way
	for k in 10:
		_px(img, CX - 11 + k, 42 + k / 4, outfit_sh.darkened(0.2))
		_px(img, CX + 11 - k, 41 + k / 3, sleeve.lightened(0.12))
	# tucked hands
	_rect(img, CX + 7, 41, CX + 9, 42, skin)
	_rect(img, CX - 9, 44, CX - 7, 45, skin.darkened(0.08))


## One arm raised, fist presenting a Poké Ball — the classic victory pose.
## Arm parts stay >= 4px thick: the outline pass eats both edges of
## anything thinner, leaving a floating dark stick (found the hard way).
static func _hand_up(img: Image, seed: String, outfit: Color, outfit_sh: Color,
		skin: Color, max_half: int) -> void:
	var side := 1 if _pick(seed, "wavedir", 2) == 0 else -1
	var ax := CX + side * 17                 # clear of even the big hairdos
	var sleeve := outfit.darkened(0.10) if side > 0 else outfit
	# sturdy arm, uniform thickness. The elbow is a QUARTER-ARC (user note:
	# the stepped diagonal read as broken) — the arm rises straight, then its
	# centreline sweeps continuously into the shoulder along a circle.
	var arc_r := 4.0
	for y in range(22, N):                   # the full limb: down the body's side
		var inset := 0
		if y > 43:                           # small hook into the torso at the hip
			var dy := minf(float(y - 43), arc_r)
			inset = int(round(arc_r - sqrt(maxf(0.0, arc_r * arc_r - dy * dy))))
		var cx0 := ax - side * inset
		for dx in range(-2, 3):              # 5px fill -> 4px visible + outline
			_px(img, cx0 + dx, y, sleeve if dx * side <= 0 else outfit_sh)
	# cuff
	for dx in range(-2, 3):
		_px(img, ax + dx, 21, outfit_sh.darkened(0.15))
	# closed fist gripping under the ball (no splayed fingers)
	var fx := ax                             # fist sits square on the wrist
	_rect(img, fx - 2, 18, fx + 2, 21, skin)
	_px(img, fx - side * 2, 19, skin.darkened(0.15))   # thumb crease
	_px(img, fx + side * 2, 20, skin.darkened(0.10))
	# --- the ball, resting on the fist: Poké (common), Super or Master
	var roll := _pick(seed, "balltype", 6)   # 0-2 Poké · 3-4 Super · 5 Master
	var top := Color("e03028")
	var gloss := Color("ff9a8a")
	if roll >= 3 and roll <= 4:
		top = Color("3a6ac9")                # Super Ball blue
		gloss = Color("8ab4ff")
	elif roll == 5:
		top = Color("7a3fa8")                # Master Ball purple
		gloss = Color("c98ae0")
	var ball_w := Color("f2f2f5")
	var bx := fx
	var by := 13
	for y in range(by - 4, by + 5):
		var t2 := (float(y) - by) / 4.6
		var w := 4.6 * sqrt(maxf(0.0, 1.0 - t2 * t2))
		for x in range(bx - int(round(w)), bx + int(round(w)) + 1):
			_px(img, x, y, top if y < by else ball_w)
	# band across the middle + centre button
	for x in range(bx - 4, bx + 5):
		_px(img, x, by, OUT)
	_px(img, bx - 1, by, ball_w)
	_px(img, bx, by, ball_w)
	_px(img, bx - 1, by - 1, OUT)
	_px(img, bx, by - 1, OUT)
	_px(img, bx - 1, by + 1, OUT)
	_px(img, bx, by + 1, OUT)
	# type accents on the top hemisphere
	if roll >= 3 and roll <= 4:              # Super: red racing stripes
		for dy in [-3, -2]:
			_px(img, bx - 3, by + dy, Color("e03028"))
			_px(img, bx + 2, by + dy, Color("e03028"))
	elif roll == 5:                          # Master: pink pips + white M dot
		_px(img, bx - 3, by - 2, Color("f08ae0"))
		_px(img, bx + 2, by - 2, Color("f08ae0"))
		_px(img, bx - 1, by - 2, ball_w)
		_px(img, bx, by - 2, ball_w)
	# glossy highlight
	_px(img, bx - 2, by - 3, gloss)
	_px(img, bx - 1, by - 3, gloss)
	_px(img, bx - 2, by - 2, gloss)
