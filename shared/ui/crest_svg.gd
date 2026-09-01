class_name CrestSVG
extends Object
## SVG composer for procedural club crests (crests piece). Pure function of
## the params dict built by Crest.params(): returns an SVG string (96x96
## viewBox) rasterized by Crest via Image.load_svg_from_string — the same
## pipeline as GlyphIcons/PortraitSVG, so it works identically in exports.
##
## A crest = SHAPE silhouette (gym-badge inspired) + FIELD pattern + TYPE
## MOTIF (the squad's dominant type: flame, wave, leaf, bolt, gear, …).
## Letters are NOT drawn here (thorvg text support is unreliable) — Crest
## overlays a Label when the club's design calls for a monogram.

const SHAPES := ["shield", "round", "banner", "hex", "diamond", "kite"]
const PATTERNS := ["plain", "chief", "stripe", "split"]


static func compose(p: Dictionary) -> String:
	var shape: String = p["shape"]
	var s := '<defs><clipPath id="c">%s</clipPath></defs>' % _shape_path(shape, 0.0, "")
	# border silhouette, then the inset field clipped to the outline
	s += _shape_path(shape, 0.0, p["border"])
	s += '<g clip-path="url(#c)">'
	s += _shape_path(shape, 3.2, p["field"])
	s += _pattern(str(p["pattern"]), shape, p)
	s += "</g>"
	s += _motif(str(p["motif"]), p["ink"], p["ink2"])
	return '<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96" viewBox="0 0 96 96">%s</svg>' % s


## The six silhouettes. inset > 0 shrinks around the center (border reveal).
static func _shape_path(kind: String, inset: float, fill: String) -> String:
	var attr := ' fill="%s"' % fill if fill != "" else ""
	var t := inset
	match kind:
		"round":
			return '<circle cx="48" cy="48" r="%.1f"%s/>' % [44.0 - t, attr]
		"banner":   # pennant: straight top, tapering point at the bottom
			return '<path d="M%.1f,%.1f H%.1f V%.1f L48,%.1f L%.1f,%.1f Z"%s/>' % [
				10.0 + t, 6.0 + t, 86.0 - t, 60.0 - t * 0.4, 90.0 - t * 1.6,
				10.0 + t, 60.0 - t * 0.4, attr]
		"hex":
			return '<path d="M48,%.1f L%.1f,%.1f V%.1f L48,%.1f L%.1f,%.1f V%.1f Z"%s/>' % [
				5.0 + t, 87.0 - t, 26.5 + t * 0.5, 69.5 - t * 0.5, 91.0 - t,
				9.0 + t, 69.5 - t * 0.5, 26.5 + t * 0.5, attr]
		"diamond":
			return '<path d="M48,%.1f L%.1f,48 L48,%.1f L%.1f,48 Z"%s/>' % [
				4.0 + t * 1.3, 92.0 - t * 1.3, 92.0 - t * 1.3, 4.0 + t * 1.3, attr]
		"kite":     # rounded-top badge tapering to a point
			return '<path d="M%.1f,%.1f Q48,%.1f %.1f,%.1f V52 Q%.1f,74 48,%.1f Q%.1f,74 %.1f,52 Z"%s/>' % [
				12.0 + t, 26.0 + t * 0.6, 2.0 + t * 2.0, 84.0 - t, 26.0 + t * 0.6,
				84.0 - t, 90.0 - t * 1.7, 12.0 + t, 12.0 + t, attr]
		_:          # "shield": classic heater
			return '<path d="M%.1f,%.1f H%.1f V46 Q%.1f,74 48,%.1f Q%.1f,74 %.1f,46 Z"%s/>' % [
				11.0 + t, 10.0 + t, 85.0 - t, 85.0 - t, 90.0 - t * 1.6,
				11.0 + t, 11.0 + t, attr]


## Field patterns, drawn inside the outline clip over the base field.
static func _pattern(kind: String, shape: String, p: Dictionary) -> String:
	match kind:
		"chief":    # top band in the secondary colour
			var band_h := 26.0 if shape != "banner" else 22.0
			return '<rect x="0" y="0" width="96" height="%.1f" fill="%s"/>' % [band_h, p["field2"]]
		"stripe":   # bold diagonal
			return '<path d="M-14,66 L66,-14 L92,12 L12,92 Z" fill="%s" opacity="0.9"/>' % p["field2"]
		"split":    # vertical halves
			return '<rect x="48" y="0" width="48" height="96" fill="%s"/>' % p["field2"]
	return ""


## Type motifs: one bold, centered emblem per type — readable at 26px.
static func _motif(t: String, ink: String, ink2: String) -> String:
	match t:
		"fire":     # flame
			return ('<path d="M48,22 Q60,34 58,47 Q66,42 64,33 Q74,44 71,56 Q68,69 48,71 ' +
				'Q28,69 25,56 Q23,45 32,36 Q31,46 38,49 Q34,34 48,22 Z" fill="%s"/>' +
				'<path d="M48,42 Q55,50 53,58 Q51,64 48,64 Q41,62 42,54 Q43,47 48,42 Z" fill="%s"/>') % [ink, ink2]
		"water":    # cascading waves
			return ('<path d="M22,44 Q30,36 39,44 Q48,52 57,44 Q66,36 74,44 L74,52 Q66,44 57,52 ' +
				'Q48,60 39,52 Q30,44 22,52 Z" fill="%s"/>' +
				'<path d="M22,58 Q30,50 39,58 Q48,66 57,58 Q66,50 74,58 L74,66 Q66,58 57,66 ' +
				'Q48,74 39,66 Q30,58 22,66 Z" fill="%s" opacity="0.75"/>') % [ink, ink2]
		"grass":    # leaf with midrib
			return ('<path d="M32,66 Q26,40 44,28 Q62,17 70,26 Q76,44 60,58 Q46,68 32,66 Z" fill="%s"/>' +
				'<path d="M36,63 Q50,52 64,30" stroke="%s" stroke-width="3" fill="none" stroke-linecap="round"/>') % [ink, ink2]
		"electric": # bolt
			return '<path d="M54,18 L32,52 L45,52 L40,76 L64,42 L50,42 Z" fill="%s"/>' % ink
		"ice":      # six-spoke snowflake
			return ('<g stroke="%s" stroke-width="4" stroke-linecap="round">' +
				'<path d="M48,24 V70 M28,35 L68,59 M68,35 L28,59"/></g>' +
				'<circle cx="48" cy="47" r="5" fill="%s"/>') % [ink, ink2]
		"fighting": # impact burst
			return ('<path d="M48,20 L54,38 L72,32 L60,47 L74,58 L55,57 L57,75 L46,60 L32,72 ' +
				'L38,54 L21,50 L39,45 Z" fill="%s"/>' +
				'<circle cx="48" cy="48" r="7" fill="%s"/>') % [ink, ink2]
		"poison":   # heavy drop
			return ('<path d="M48,20 Q66,44 66,57 Q66,73 48,73 Q30,73 30,57 Q30,44 48,20 Z" fill="%s"/>' +
				'<circle cx="42" cy="57" r="5" fill="%s" opacity="0.8"/>') % [ink, ink2]
		"ground":   # layered hills
			return ('<path d="M20,64 Q34,40 48,58 Q60,38 76,64 Z" fill="%s"/>' +
				'<path d="M20,70 H76 V64 H20 Z" fill="%s" opacity="0.8"/>') % [ink, ink2]
		"rock":     # angular boulder
			return ('<path d="M32,68 L24,50 L38,30 L62,26 L73,44 L66,68 Z" fill="%s"/>' +
				'<path d="M38,30 L48,48 L66,68 M48,48 L32,68" stroke="%s" stroke-width="2.4" fill="none"/>') % [ink, ink2]
		"flying":   # swept wing
			return ('<path d="M24,58 Q40,54 46,42 Q44,54 52,52 Q64,48 72,30 Q74,52 58,62 Q42,70 24,58 Z" fill="%s"/>' +
				'<path d="M30,57 Q48,52 60,42" stroke="%s" stroke-width="2.4" fill="none" stroke-linecap="round"/>') % [ink, ink2]
		"psychic":  # eye
			return ('<path d="M22,48 Q38,30 48,30 Q58,30 74,48 Q58,66 48,66 Q38,66 22,48 Z" fill="%s"/>' +
				'<circle cx="48" cy="48" r="9" fill="%s"/>') % [ink, ink2]
		"bug":      # beetle: body + antennae
			return ('<ellipse cx="48" cy="52" rx="13" ry="17" fill="%s"/>' +
				'<circle cx="48" cy="33" r="7" fill="%s"/>' +
				'<path d="M44,28 Q38,20 31,18 M52,28 Q58,20 65,18 M48,38 V68" ' +
				'stroke="%s" stroke-width="3" fill="none" stroke-linecap="round"/>') % [ink, ink, ink2]
		"ghost":    # wisp with wavy hem
			return ('<path d="M30,48 Q30,26 48,26 Q66,26 66,48 V62 L60,56 L54,64 L48,57 L42,64 ' +
				'L36,56 L30,62 Z" fill="%s"/>' +
				'<circle cx="41" cy="43" r="3.6" fill="%s"/><circle cx="55" cy="43" r="3.6" fill="%s"/>') % [ink, ink2, ink2]
		"dragon":   # paired fangs
			return ('<path d="M34,26 Q28,48 40,70 Q44,52 42,34 Z" fill="%s"/>' +
				'<path d="M62,26 Q68,48 56,70 Q52,52 54,34 Z" fill="%s"/>' +
				'<path d="M42,30 Q48,24 54,30" stroke="%s" stroke-width="3.4" fill="none" stroke-linecap="round"/>') % [ink, ink, ink2]
		"dark":     # crescent moon
			return ('<path d="M58,22 Q40,28 40,48 Q40,68 58,74 Q34,76 27,57 Q22,36 42,26 Q50,22 58,22 Z" fill="%s"/>' +
				'<circle cx="61" cy="34" r="3.4" fill="%s"/>') % [ink, ink2]
		"steel":    # gear
			var teeth := ""
			for i in 8:
				teeth += '<rect x="44" y="18" width="8" height="12" rx="2" fill="%s" transform="rotate(%d 48 48)"/>' % [ink, i * 45]
			return teeth + ('<circle cx="48" cy="48" r="17" fill="%s"/>' % ink) + \
				('<circle cx="48" cy="48" r="7.5" fill="%s"/>' % ink2)
		"fairy":    # sparkle trio
			return ('<path d="M48,24 L53,41 L70,46 L53,51 L48,68 L43,51 L26,46 L43,41 Z" fill="%s"/>' +
				'<path d="M66,26 L68,32 L74,34 L68,36 L66,42 L64,36 L58,34 L64,32 Z" fill="%s"/>' +
				'<path d="M30,58 L32,64 L38,66 L32,68 L30,74 L28,68 L22,66 L28,64 Z" fill="%s"/>') % [ink, ink2, ink2]
	# "normal" and anything unknown: four-point compass star
	return ('<path d="M48,20 L54,42 L76,48 L54,54 L48,76 L42,54 L20,48 L42,42 Z" fill="%s"/>' +
		'<circle cx="48" cy="48" r="5.5" fill="%s"/>') % [ink, ink2]
