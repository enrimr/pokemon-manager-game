class_name TrainerArt
extends Object
## Official character portraits (art piece). The canon faces — gym leaders,
## Ash/Gary/Red/Lance, the professors — bundled at res://assets/trainers/
## <slug>.png (80x80 Pokémon Showdown trainer sprites, see the README there;
## personal fan project, never distribute commercially). Everyone ELSE keeps
## their procedural anime portrait: Portrait.avatar() consults has_art() and
## routes canon names here, so call sites don't need to know who is famous.
##
## API:
##   TrainerArt.has_art(name)          -> bool ("Lt. Surge", "Professor Oak"…)
##   TrainerArt.tex(name)              -> Texture2D or null
##   TrainerArt.avatar(name, px, opts) -> TextureRect (crisp NEAREST upscale)

static var _cache: Dictionary = {}


## Canon display name -> bundled file slug ("Lt. Surge" -> "lt_surge").
static func slug(display_name: String) -> String:
	var s := display_name.strip_edges().to_lower()
	var out := ""
	for ch in s:
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	return out.trim_prefix("_").trim_suffix("_")


static func has_art(display_name: String) -> bool:
	return ResourceLoader.exists("res://assets/trainers/%s.png" % slug(display_name))


static func tex(display_name: String) -> Texture2D:
	var sl := slug(display_name)
	if _cache.has(sl):
		return _cache[sl]
	if not ResourceLoader.exists("res://assets/trainers/%s.png" % sl):
		return null
	var t: Texture2D = load("res://assets/trainers/%s.png" % sl)
	_cache[sl] = t
	return t


## Head crop for small avatar slots (the sprites are full-body 80x80: at
## 30px a whole body is an ant). AtlasTexture over the top-centre band.
static func face_tex(display_name: String) -> Texture2D:
	var sl := "face|" + slug(display_name)
	if _cache.has(sl):
		return _cache[sl]
	var t := tex(display_name)
	if t == null:
		return null
	var at := AtlasTexture.new()
	at.atlas = t
	var s := t.get_size()
	at.region = Rect2(s.x * 0.24, s.y * 0.02, s.x * 0.52, s.y * 0.52)
	_cache[sl] = at
	return at


## opts: {"full": bool (full-body sprite; default face crop), "tooltip"}
static func avatar(display_name: String, px: int = 32, opts: Dictionary = {}) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex(display_name) if bool(opts.get("full", false)) else face_tex(display_name)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # pixel art
	r.custom_minimum_size = Vector2(px, px)
	r.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if str(opts.get("tooltip", "")) != "":
		r.tooltip_text = str(opts["tooltip"])
		r.mouse_filter = Control.MOUSE_FILTER_STOP
	return r
