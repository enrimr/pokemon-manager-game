class_name PokeArt
extends Object
## Pokémon sprite art (art piece). Classic 96x96 game sprites bundled at
## res://assets/pokemon/<national-dex-id>.png (gen 1+2, ids 1..251, sourced
## from the PokeAPI sprites mirror — see assets/pokemon/README.md). They ship
## inside the pck, so every export (web included) carries them; no CDN.
##
## API:
##   PokeArt.has_art(id)          -> bool
##   PokeArt.tex(id)              -> Texture2D or null
##   PokeArt.icon(id, px, opts)   -> Control (sprite; falls back to the
##                                   type-coloured monogram when no art)
## Sprites are pixel art: icons render with NEAREST filtering so upscales
## stay crisp instead of blurring.

static var _cache: Dictionary = {}


## National dex id from a species display name ("Dodrio" -> 85; 0 if unknown).
static func id_of(species_name: String) -> int:
	var sp: Dictionary = DataStore.pokemon_by_name.get(species_name, {})
	return int(sp.get("id", 0))


static func has_art(species_id: int) -> bool:
	return species_id >= 1 and species_id <= 251 \
		and ResourceLoader.exists("res://assets/pokemon/%d.png" % species_id)


static func tex(species_id: int) -> Texture2D:
	if _cache.has(species_id):
		return _cache[species_id]
	if not has_art(species_id):
		return null
	var t: Texture2D = load("res://assets/pokemon/%d.png" % species_id)
	_cache[species_id] = t
	return t


## Sprite icon sized for UI. opts: {"flip": bool (face right, for our side of
## a battle), "tooltip": String}. Falls back to a species-initial monogram.
static func icon(species_id: int, px: int = 40, opts: Dictionary = {}) -> Control:
	var t := tex(species_id)
	if t == null:
		return _mono_fallback(species_id, px)
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.flip_h = bool(opts.get("flip", false))
	r.custom_minimum_size = Vector2(px, px)
	r.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if str(opts.get("tooltip", "")) != "":
		r.tooltip_text = str(opts["tooltip"])
		r.mouse_filter = Control.MOUSE_FILTER_STOP
	return r


static func _mono_fallback(species_id: int, px: int) -> Control:
	var sp: Dictionary = DataStore.species(species_id)
	var types: Array = sp.get("types", [])
	var col: Color = DataStore.type_color(str(types[0]) if not types.is_empty() else "normal")
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(px, px)
	var sb := StyleBoxFlat.new()
	sb.bg_color = col.darkened(0.35)
	sb.border_color = col.lightened(0.25)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(px / 2)
	p.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = str(sp.get("name", "?")).substr(0, 1)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", int(px * 0.42))
	l.add_theme_color_override("font_color", Color.WHITE)
	p.add_child(l)
	return p
