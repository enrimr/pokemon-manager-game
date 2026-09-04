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
	var key := "%s|%d|%s|%s" % [seed, px, str(opts.get("collar", "")), str(opts.get("pose", ""))]
	if _cache.has(key):
		return _cache[key]
	var img := _draw(seed, opts)
	var scale := maxi(1, int(round(float(px) / float(N))))
	img.resize(N * scale, N * scale, Image.INTERPOLATE_NEAREST)
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
	var hair_i := _pick(seed, "hair_c", HAIRS.size())
	var hair := Color(HAIRS[hair_i])
	if int(opts.get("age", 0)) >= 55 and _pick(seed, "grey", 3) > 0:
		hair = Color(GREY)
	if absf(hair.get_luminance() - skin.get_luminance()) < 0.14:
		hair = hair.darkened(0.30)
	var hair_sh := hair.darkened(0.22)
	var hair_hi := hair.lightened(0.20)
	var style := _pick(seed, "hair_s", 14)
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
	for y in range(34, N):
		var t2 := clampf(float(y - 34) / 7.0, 0.0, 1.0)
		var ease := 1.0 - (1.0 - t2) * (1.0 - t2)          # fast then settle
		var half := 5 + int(round(ease * float(max_half - 5)))
		# lean pose: the shoulder opposite the lean rides one row higher
		var raise_l := 1 if pose == 5 and head_dx > 0 and y < 40 else 0
		var raise_r := 1 if pose == 5 and head_dx < 0 and y < 40 else 0
		var tl := clampf(float(y - 34 + raise_l) / 7.0, 0.0, 1.0)
		var tr := clampf(float(y - 34 + raise_r) / 7.0, 0.0, 1.0)
		var half_l := 5 + int(round((1.0 - (1.0 - tl) * (1.0 - tl)) * float(max_half - 5)))
		var half_r := 5 + int(round((1.0 - (1.0 - tr) * (1.0 - tr)) * float(max_half - 5)))
		if pose != 5:
			half_l = half
			half_r = half
		for x in range(CX - half_l, CX + half_r + 1):
			_px(img, x, y, outfit if x < CX + 2 else outfit_sh)
	# arm seams: a darker vertical line where the sleeves start
	for y in range(40, N):
		_px(img, CX - max_half + 3, y, outfit_sh.darkened(0.18))
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
	if jaw == 1:                              # square: fill the jaw corners
		_rect(head, CX - 7, 26, CX + 7, 29, skin)
	else:
		_rect(head, CX - 6, 26, CX + 6, 28, skin)
		for x in range(CX - 4, CX + 5):
			_px(head, x, 29, skin)
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
	# beard/stubble
	if not fem and _pick(seed, "beard", 4) == 0:
		for x in range(CX - 6, CX + 7):
			_px(head, x, 29, hair_sh)
			if absi(x - CX) > 2:
				_px(head, x, 28, hair_sh)
		_rect(head, CX - 7, 25, CX - 6, 28, hair_sh)
		_rect(head, CX + 6, 25, CX + 7, 28, hair_sh)

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
		8: _hat_cap(head, seed, hair, hair_sh)
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

	# --- unified 1px outline
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
	# five spikes: triangles rising from the dome
	for s in [[-9, 4], [-4, 6], [1, 7], [6, 5], [10, 3]]:
		var sx: int = CX + int(s[0])
		var sh_n: int = int(s[1])
		for h in range(sh_n):
			for w in range(maxi(1, sh_n - h - 1)):
				_px(img, sx + w, 6 - h, c if h < sh_n - 2 else hi)
	# jagged fringe teeth
	for x in range(CX - 9, CX + 10, 3):
		_px(img, x, 16, c)
		_px(img, x + 1, 16, c)


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


static func _hat_cap(img: Image, seed: String, hair: Color, hair_sh: Color) -> void:
	var cap := Color(OUTFITS[_pick(seed, "cap_c", OUTFITS.size())])
	for y in range(4, 15):
		var t := (float(y) - 14.0) / 10.0
		var w := 12.0 * sqrt(maxf(0.0, 1.0 - t * t))
		for x in range(CX - int(round(w)), CX + int(round(w)) + 1):
			_px(img, x, y, cap)
	# front panel + button
	_rect(img, CX - 4, 6, CX + 3, 11, cap.lightened(0.22))
	_px(img, CX, 4, cap.darkened(0.3))
	# brim sweeping right
	for x in range(CX + 2, CX + 16):
		_px(img, x, 15, cap.darkened(0.2))
		_px(img, x, 16, cap.darkened(0.28))
	# hair under the cap
	for x in range(CX - 10, CX + 2):
		_px(img, x, 15, hair)
		_px(img, x, 16, hair_sh)
	_rect(img, CX - 11, 15, CX - 10, 20, hair)
	_rect(img, CX + 10, 17, CX + 11, 20, hair_sh)


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
	for s in [[-12, 9, -1], [-10, 5, -1], [-5, 3, 0], [0, 2, 0], [5, 3, 1], [9, 5, 1], [12, 9, 1]]:
		var sx: int = CX + int(s[0])
		var sy: int = int(s[1])
		var lean: int = int(s[2])
		for k in 3:
			_px(img, sx + lean * k, sy - k, c if k < 2 else hi)
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


## One hand raised beside the head, waving — official-sprite energy.
## The arm is 3px thick: the outline pass eats both edges of anything
## thinner, leaving a floating dark stick (found the hard way).
static func _hand_up(img: Image, seed: String, outfit: Color, outfit_sh: Color,
		skin: Color, max_half: int) -> void:
	var side := 1 if _pick(seed, "wavedir", 2) == 0 else -1
	var ax := CX + side * 18                 # well clear of even the big hairdos
	var sleeve := outfit.darkened(0.10) if side > 0 else outfit
	# underarm wedge: connects the shoulder to the raised arm (no floating)
	for y in range(35, 42):
		var t := clampf(float(y - 34) / 7.0, 0.0, 1.0)
		var half := 5 + int(round((1.0 - (1.0 - t) * (1.0 - t)) * float(max_half - 5)))
		var x_in := CX + side * (half - 3)
		for x in range(mini(x_in, ax - 1), maxi(x_in, ax + 1) + 1):
			_px(img, x, y, sleeve)
	# upper arm: vertical, 4px thick
	for y in range(16, 36):
		for dx in range(-1, 3):
			_px(img, ax + dx * side, y, sleeve if dx <= 0 else outfit_sh)
	# cuff
	for dx in range(-1, 3):
		_px(img, ax + dx * side, 15, outfit_sh.darkened(0.15))
	# open hand ABOVE the hairline: palm + three fingers
	_rect(img, ax - 2, 10, ax + 2, 14, skin)
	for f in [-2, 0, 2]:
		_px(img, ax + f, 9, skin)
		_px(img, ax + f, 8, skin)
	_px(img, ax + side, 12, skin.darkened(0.12))
