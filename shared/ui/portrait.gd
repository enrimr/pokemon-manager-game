class_name Portrait
extends Object
## Procedural people portraits (portraits piece). Every person in the world —
## the manager, rivals, journalists, scouts, coaches, the board — gets an
## ORIGINAL flat-vector face, deterministically seeded from their stable name
## so the same person always looks the same everywhere. SVG-string composed by
## PortraitSVG, rasterized at runtime (Image.load_svg_from_string, cached per
## seed+px+collar) — identical pipeline to GlyphIcons, export-build safe.
##
## API:
##   Portrait.tex(seed, px, opts)     -> Texture2D
##   Portrait.avatar(seed, px, opts)  -> TextureRect (rounded-square avatar)
##   opts: {"collar": Color (club tint), "age": int years, "variant": int}
##   Portrait.manager_seed()          -> the player manager's stable face seed
##   Portrait.person_key(sender) / is_person(sender)  -> inbox sender helpers
##   Portrait.club_collar(club)       -> club color for staff collars
##   Portrait.board_members(club)     -> [{name, role}] stable board of three

const SKINS := ["6b4226", "7d4a2b", "8d5a33", "a06a3f", "b97f52", "c98f63",
	"d9a577", "e5b88d", "efc9a3", "f6d7b8"]
const HAIRS := ["16161e", "2b2027", "3b2a1a", "6e4a2a", "a03c2e", "c2622f",
	"d9b36a", "2f4f8f", "2e7a55", "6a4a8c", "c46a8a"]
const HAIRS_OLD := ["9a9da6", "c6c9d1", "e8e9ee"]
const EYES := ["4a2e1c", "2f5fae", "2f7a4c", "6a4a9c", "a04434", "31739e"]
const COLLARS := ["4a5568", "5b4a68", "3f5a4e", "6b4a3f", "44506e", "5e4444",
	"3d5b66", "565d3f"]
const STYLES_M := ["crop", "side", "buzz", "spiky", "curly", "afro", "receding",
	"bald", "crop", "side", "curly", "buzz"]
const STYLES_F := ["bob", "long", "bun", "ponytail", "pixie", "curly", "afro",
	"crop", "bob", "long", "ponytail", "pixie"]
const MOUTHS := [0, 0, 2, 2, 4, 0, 3, 1, 2, 0]
## Name canon (anime + games): character first names, world surnames. These
## banks drive gender inference for faces AND board-member generation, so any
## first name used by gen_data.py / market.gd / people_gen.gd must appear here.
const FEM_FIRST := ["Misty", "Serena", "Dawn", "May", "Iris", "Lillie", "Mallow",
	"Lana", "Bianca", "Erika", "Sabrina", "Whitney", "Jasmine", "Clair", "Cynthia",
	"Lorelei", "Karen", "Flannery", "Winona", "Phoebe", "Jessie", "Daisy", "Casey",
	"Zoey", "Alexa", "Rhonda", "Gabby", "Mary"]
const MASC_FIRST := ["Ash", "Brock", "Gary", "Tracey", "Ritchie", "Paul", "Cilan",
	"Clemont", "Kiawe", "Goh", "Lance", "Steven", "Wallace", "Blaine", "Koga",
	"Bruno", "Falkner", "Bugsy", "Morty", "Chuck", "Pryce", "Will", "Volkner",
	"Flint", "Barry", "Silver", "Wally", "James", "Todd", "Trevor"]
const LASTS := ["Ketchum", "Oak", "Elm", "Birch", "Rowan", "Juniper", "Sycamore",
	"Kukui", "Magnolia", "Cerise", "Stone", "Waterflower", "Harrison", "Maple",
	"Berlitz", "Fuji", "Goodshow", "Ivy", "Westwood", "Hale", "Silph", "Devon",
	"Laramie", "Snap"]
## Sender fragments that are institutions, not persons (en + es catalogs).
const NOT_PEOPLE := ["Board", "Committee", "Academy", "Assistant Manager",
	"Head Coach", "Consejo", "Comit", "Academia", "League", "Liga", "Club"]

static var _cache: Dictionary = {}
static var _collar_cache: Dictionary = {}


static func tex(seed: String, px: int = 32, opts: Dictionary = {}) -> Texture2D:
	var collar: Color = opts.get("collar", Color.TRANSPARENT)
	var render_px: int = clampi(px * 2, 48, 192)   # 2x oversample, crisp downscale
	var key := "%s|%d|%s|%d|%d" % [seed, render_px, collar.to_html(false) if collar.a > 0.0 else "-",
		int(opts.get("age", -1)), int(opts.get("variant", 0))]
	if _cache.has(key):
		return _cache[key]
	var svg := PortraitSVG.compose(params(seed, opts))
	var img := Image.new()
	var err := img.load_svg_from_string(svg, float(render_px) / 96.0)
	if err != OK or img.is_empty():
		img = Image.create(render_px, render_px, false, Image.FORMAT_RGBA8)
		img.fill(Color("4a5568"))   # visible fallback, never empty
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t


static func avatar(seed: String, px: int = 32, opts: Dictionary = {}) -> TextureRect:
	# canon characters (gym leaders, Ash, the professors…) wear their official
	# face; everyone generated keeps the procedural anime portrait
	if TrainerArt.has_art(seed):
		return TrainerArt.avatar(seed, px, opts)
	var r := TextureRect.new()
	r.texture = tex(seed, px, opts)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.custom_minimum_size = Vector2(px, px)
	r.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if str(opts.get("tooltip", "")) != "":
		r.tooltip_text = str(opts["tooltip"])
		r.mouse_filter = Control.MOUSE_FILTER_STOP
	return r


## Deterministic facet picker — String.hash() is stable across runs/exports
## (same pattern the inbox personas persist with).
static func _pick(seed: String, facet: String, n: int) -> int:
	return absi(("%s|%s" % [seed, facet]).hash()) % maxi(1, n)


static func params(seed: String, opts: Dictionary = {}) -> Dictionary:
	var v := int(opts.get("variant", 0))
	var s := seed if v == 0 else "%s|v%d" % [seed, v]
	var fem := _is_fem(s)
	var age: int = int(opts.get("age", 27 + _pick(s, "age", 34)))
	var old := age >= 52
	var skin := Color(SKINS[_pick(s, "skin", SKINS.size())])
	var hair_c: Color
	if age >= 57:
		hair_c = Color(HAIRS_OLD[1 + _pick(s, "gray", 2)])
	elif old:
		hair_c = Color(HAIRS_OLD[0])
	else:
		hair_c = Color(HAIRS[_pick(s, "hair", HAIRS.size())])
	var style: String = str(opts.get("style", (STYLES_F if fem else STYLES_M)[_pick(s, "style", 12)]))
	if old and _pick(s, "oldbald", 3) == 0:
		style = "receding" if not fem else "bun"
	var fhair := ""
	if not fem:
		fhair = ["", "", "", "", "", "stubble", "mustache", "goatee", "beard", "beard"][_pick(s, "fh", 10)]
	var gl := _pick(s, "gl", 100)
	var collar: Color = opts.get("collar", Color.TRANSPARENT)
	if collar.a <= 0.0:
		collar = Color(COLLARS[_pick(s, "collar", COLLARS.size())])
	var bg := collar.darkened(0.58)
	bg.s = minf(bg.s, 0.5)
	return {
		"skin": _h(skin), "skin_sh": _h(skin.darkened(0.14)),
		"skin_line": _h(skin.darkened(0.48)),
		"hair": _h(hair_c), "brow_col": _h(hair_c.darkened(0.28)),
		"fhair_col": _h(hair_c.darkened(0.12)),
		"eye_col": _h(Color(EYES[_pick(s, "eye_c", EYES.size())])),
		"rx": 16.0 + float(_pick(s, "rx", 7)) * 0.5 - (0.8 if fem else 0.0),
		"ry": 19.0 + float(_pick(s, "ry", 7)) * 0.5,
		"style": style, "brow": _pick(s, "brow", 4), "eye": _pick(s, "eyes", 3),
		"mouth": MOUTHS[_pick(s, "mouth", MOUTHS.size())], "fhair": fhair,
		"glasses": "round" if gl < 8 else ("square" if gl < 16 else ""),
		"old": 1 if old else 0,
		"blush": 1 if not old and age < 40 and _pick(s, "blush", 3) == 0 else 0,
		"collar": _h(collar), "collar2": _h(collar.darkened(0.35)), "bg": _h(bg),
	}


static func _h(c: Color) -> String:
	return "#" + c.to_html(false)


static func _is_fem(seed: String) -> bool:
	var first := seed.get_slice("|", 0).get_slice(" ", 0)
	if first in FEM_FIRST:
		return true
	if first in MASC_FIRST:
		return false
	return _pick(seed, "fem", 2) == 0


# ------------------------------------------------------- world-wiring helpers

## The player manager's stable face seed: name + reroll variant chosen during
## onboarding (world.meta.manager_face_variant). Pre-menu careers fall back to
## the club's generated manager name — still a stable, unique face.
static func manager_seed() -> String:
	var meta: Dictionary = GameState.world.get("meta", {})
	var nm := str(meta.get("manager_name", ""))
	if nm == "":
		nm = str(GameState.player_club().get("manager", "The Manager"))
	var v := int(meta.get("manager_face_variant", 0))
	return nm if v == 0 else "%s|v%d" % [nm, v]


## Extract the bare person name from a decorated inbox sender:
## "Yuki Serrano (Coach)" / "Ada Okafor — The Indigo Gazette" -> the name.
static func person_key(raw: String) -> String:
	var s := raw.strip_edges()
	for sep in [" — ", " - "]:
		var d := s.find(sep)
		if d >= 0:
			s = s.substr(0, d)
	var par := s.find(" (")
	if par >= 0:
		s = s.substr(0, par)
	return s.strip_edges()


## Heuristic: does this sender string name a person (vs an institution)?
static func is_person(raw: String) -> bool:
	var s := person_key(raw)
	if s == "":
		return false
	for w in NOT_PEOPLE:
		if s.findn(w) >= 0:
			return false
	var parts := s.split(" ", false)
	if parts.size() < 2 or parts.size() > 3:
		return false
	for p in parts:
		var head: String = String(p).left(1)
		if head != head.to_upper() or head == head.to_lower():
			return false
	return true


## Club tint for staff/manager collars: the squad's dominant primary type.
static func club_collar(club: Dictionary) -> Color:
	var id := str(club.get("id", ""))
	if id != "" and _collar_cache.has(id):
		return _collar_cache[id]
	var counts := {}
	for inst in club.get("squad", []):
		var sp: Dictionary = DataStore.species(int(inst.get("species_id", 0)))
		if sp.is_empty():
			continue
		var t := str((sp["types"] as Array)[0])
		counts[t] = int(counts.get(t, 0)) + 1
	var best := "normal"
	var best_n := -1
	for t in counts:
		if counts[t] > best_n:
			best_n = counts[t]
			best = t
	var col := DataStore.type_color(best).darkened(0.18)
	if id != "":
		_collar_cache[id] = col
	return col


## Find the club a rival manager runs (for their collar tint). {} if unknown.
static func club_of_manager(name: String) -> Dictionary:
	for c in GameState.world.get("clubs", []):
		if str(c.get("manager", "")) == name:
			return c
	return {}


## Deterministic original person name (used for board members).
static func gen_name(seed: String) -> String:
	var bank: Array = FEM_FIRST if _pick(seed, "fem", 2) == 0 else MASC_FIRST
	return "%s %s" % [bank[_pick(seed, "first", bank.size())],
		LASTS[_pick(seed, "last", LASTS.size())]]


## The club's boardroom: chair + two directors, stable per club, distinct
## names, senior faces (the chair skews oldest).
static func board_members(club: Dictionary) -> Array:
	var id := str(club.get("id", "club"))
	var out: Array = []
	var used := {str(club.get("manager", "")): true}
	for i in 3:
		var n := gen_name("%s|board%d" % [id, i])
		var bump := 0
		while used.has(n) and bump < 8:
			bump += 1
			n = gen_name("%s|board%d_%d" % [id, i, bump])
		used[n] = true
		out.append({"name": n, "role": "Chair" if i == 0 else "Director",
			"age": 60 - i * 6 + _pick(id + n, "bage", 5)})
	return out
