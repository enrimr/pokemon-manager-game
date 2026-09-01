class_name PortraitSVG
extends Object
## SVG composer for procedural people portraits (portraits piece).
## Pure function of the params dict built by Portrait.params(): returns an
## SVG string (96x96 viewBox, flat original vector art, rounded-square crop)
## that Portrait rasterizes via Image.load_svg_from_string — same pipeline
## GlyphIcons uses, so it works identically in exported builds.

const W := 96


static func compose(p: Dictionary) -> String:
	var skin: String = p["skin"]
	var line: String = p["skin_line"]
	var hair: String = p["hair"]
	var rx: float = p["rx"]
	var ry: float = p["ry"]
	var s := '<defs><clipPath id="c"><rect x="0" y="0" width="96" height="96" rx="18"/></clipPath></defs>'
	s += '<g clip-path="url(#c)">'
	s += '<rect width="96" height="96" fill="%s"/>' % p["bg"]
	s += _hair_back(str(p["style"]), hair)
	# body: neck, then shoulders/clothing over its base
	s += '<path d="M42,50 h12 v18 q0,5 -6,5 q-6,0 -6,-5 Z" fill="%s"/>' % p["skin_sh"]
	s += '<path d="M9,96 L9,93 Q12,73 32,71 L64,71 Q84,73 87,93 L87,96 Z" fill="%s"/>' % p["collar"]
	s += '<path d="M41,71 L48,80 L55,71 Z" fill="%s"/>' % p["collar2"]
	# ears + head
	s += '<circle cx="%.1f" cy="42" r="3.7" fill="%s"/><circle cx="%.1f" cy="42" r="3.7" fill="%s"/>' \
		% [48.0 - rx, skin, 48.0 + rx, skin]
	s += '<ellipse cx="48" cy="40" rx="%.1f" ry="%.1f" fill="%s"/>' % [rx, ry, skin]
	if int(p["old"]) == 1:
		s += _age_lines(line)
	s += _brows(int(p["brow"]), p["brow_col"])
	s += _eyes(int(p["eye"]), p["eye_col"])
	s += '<path d="M48,44 q1.6,4 0,6.2" fill="none" stroke="%s" stroke-width="1.5" stroke-linecap="round" opacity="0.55"/>' % line
	s += _facial_hair(str(p["fhair"]), p["fhair_col"])
	s += _mouth(int(p["mouth"]), line)
	s += _hair_front(str(p["style"]), hair)
	s += _glasses(str(p["glasses"]))
	s += "</g>"
	return '<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96" viewBox="0 0 96 96">%s</svg>' % s


static func _hair_back(style: String, c: String) -> String:
	match style:
		"afro":
			return '<circle cx="48" cy="33" r="26" fill="%s"/>' % c
		"bob":
			return '<path d="M25,32 Q25,14 48,14 Q71,14 71,32 L71,58 Q71,64 64,64 L32,64 Q25,64 25,58 Z" fill="%s"/>' % c
		"long":
			return '<path d="M26,32 Q26,13 48,13 Q70,13 70,32 L70,76 Q70,82 63,82 L33,82 Q26,82 26,76 Z" fill="%s"/>' % c
		"bun":
			return '<circle cx="48" cy="15" r="8" fill="%s"/>' % c
		"ponytail":
			return '<path d="M61,24 Q77,29 75,52 Q74,66 66,72 L61,63 Q69,50 63,32 Z" fill="%s"/>' % c
	return ""


static func _hair_front(style: String, c: String) -> String:
	match style:
		"buzz":
			return '<path d="M30,36 Q31,18 48,18 Q65,18 66,36 Q60,24 48,24 Q36,24 30,36 Z" fill="%s" opacity="0.62"/>' % c
		"crop", "bun", "ponytail":
			return '<path d="M29.5,38 Q29,17 48,17 Q67,17 66.5,38 Q62,25 48,25.5 Q34,25 29.5,38 Z" fill="%s"/>' % c
		"side":
			return '<path d="M29.5,38 Q29,16 48,16 Q67,16 66.5,36 Q57,20 42,25 Q33,28 29.5,38 Z" fill="%s"/>' % c
		"spiky":
			return '<path d="M29,36 L31,25 L36,29 L41,20 L45,27 L50,19 L54,27 L59,21 L62,29 L65,25 L67,36 Q58,27 48,27 Q36,27 29,36 Z" fill="%s"/>' % c
		"curly":
			return ('<circle cx="36" cy="24" r="8.5" fill="%s"/><circle cx="48" cy="20" r="9.5" fill="%s"/>' +
				'<circle cx="60" cy="24" r="8.5" fill="%s"/><circle cx="30" cy="32" r="6" fill="%s"/>' +
				'<circle cx="66" cy="32" r="6" fill="%s"/>') % [c, c, c, c, c]
		"afro":
			return '<path d="M29,38 Q28,20 48,19 Q68,20 67,38 Q62,26 48,26 Q34,26 29,38 Z" fill="%s"/>' % c
		"receding":
			return ('<path d="M30,36 Q31,26 36,24 L38,30 Q33,32 30,36 Z" fill="%s"/>' +
				'<path d="M66,36 Q65,26 60,24 L58,30 Q63,32 66,36 Z" fill="%s"/>') % [c, c]
		"bob", "long":
			return '<path d="M28,34 Q28,16 48,16 Q68,16 68,34 L64,34 Q64,24 48,24 Q32,24 32,34 Z" fill="%s"/>' % c
		"pixie":
			return '<path d="M29,40 Q27,15 50,16 Q69,18 66.5,34 Q63,24 50,25 Q40,25.5 37,31 Q33,35 29,40 Z" fill="%s"/>' % c
	return ""   # bald


static func _brows(kind: int, c: String) -> String:
	match kind:
		0:  # flat
			return '<rect x="35.5" y="33" width="9" height="2.2" rx="1.1" fill="%s"/><rect x="51.5" y="33" width="9" height="2.2" rx="1.1" fill="%s"/>' % [c, c]
		1:  # angled
			return '<path d="M35.5,35 L44.5,33 M51.5,33 L60.5,35" stroke="%s" stroke-width="2.4" stroke-linecap="round"/>' % c
		2:  # thick
			return '<rect x="35" y="32.2" width="10" height="3.4" rx="1.6" fill="%s"/><rect x="51" y="32.2" width="10" height="3.4" rx="1.6" fill="%s"/>' % [c, c]
		_:  # arched
			return '<path d="M35.5,35 Q40,31.4 44.5,34 M51.5,34 Q56,31.4 60.5,35" stroke="%s" stroke-width="2.2" fill="none" stroke-linecap="round"/>' % c


static func _eyes(kind: int, c: String) -> String:
	match kind:
		0:  # round + highlight
			return ('<circle cx="40.5" cy="41" r="2.7" fill="%s"/><circle cx="55.5" cy="41" r="2.7" fill="%s"/>' +
				'<circle cx="41.3" cy="40.2" r="0.8" fill="#ffffff" opacity="0.85"/><circle cx="56.3" cy="40.2" r="0.8" fill="#ffffff" opacity="0.85"/>') % [c, c]
		1:  # narrow
			return '<ellipse cx="40.5" cy="41.2" rx="3" ry="1.9" fill="%s"/><ellipse cx="55.5" cy="41.2" rx="3" ry="1.9" fill="%s"/>' % [c, c]
		_:  # wide
			return ('<circle cx="40.5" cy="41" r="3.1" fill="%s"/><circle cx="55.5" cy="41" r="3.1" fill="%s"/>' +
				'<circle cx="41.5" cy="40" r="1" fill="#ffffff" opacity="0.9"/><circle cx="56.5" cy="40" r="1" fill="#ffffff" opacity="0.9"/>') % [c, c]


static func _mouth(kind: int, c: String) -> String:
	match kind:
		0:  # smile
			return '<path d="M42,54.5 Q48,59.5 54,54.5" fill="none" stroke="%s" stroke-width="2.1" stroke-linecap="round"/>' % c
		1:  # open grin
			return '<path d="M42,54 Q48,62 54,54 Z" fill="%s"/><path d="M43.5,54.6 h9" stroke="#ffffff" stroke-width="1.6" opacity="0.9"/>' % c
		2:  # neutral
			return '<path d="M43,56 h10" stroke="%s" stroke-width="2" stroke-linecap="round"/>' % c
		3:  # slight frown
			return '<path d="M42.5,57.5 Q48,54 53.5,57.5" fill="none" stroke="%s" stroke-width="2" stroke-linecap="round"/>' % c
		_:  # smirk
			return '<path d="M43,55.5 Q49,58.5 54,54.2" fill="none" stroke="%s" stroke-width="2" stroke-linecap="round"/>' % c


static func _facial_hair(kind: String, c: String) -> String:
	const BEARD := "M30.5,44 Q32,66.5 48,66.5 Q64,66.5 65.5,44 Q65,58.5 48,60 Q31,58.5 30.5,44 Z"
	match kind:
		"mustache":
			return '<path d="M41.5,52.3 Q48,56 54.5,52.3" fill="none" stroke="%s" stroke-width="3" stroke-linecap="round"/>' % c
		"goatee":
			return ('<ellipse cx="48" cy="60.5" rx="5.4" ry="4.2" fill="%s"/>' +
				'<path d="M42,52.5 Q48,55.5 54,52.5" fill="none" stroke="%s" stroke-width="2.6" stroke-linecap="round"/>') % [c, c]
		"beard":
			return ('<path d="%s" fill="%s"/>' % [BEARD, c]) + \
				('<path d="M41.5,52.3 Q48,56 54.5,52.3" fill="none" stroke="%s" stroke-width="3" stroke-linecap="round"/>' % c)
		"stubble":
			return '<path d="%s" fill="%s" opacity="0.3"/>' % [BEARD, c]
	return ""


static func _glasses(kind: String) -> String:
	const GC := "#232733"
	match kind:
		"round":
			return ('<circle cx="40.5" cy="41.4" r="5.6" fill="none" stroke="%s" stroke-width="1.8"/>' +
				'<circle cx="55.5" cy="41.4" r="5.6" fill="none" stroke="%s" stroke-width="1.8"/>' +
				'<path d="M46.1,41 h3.8 M34.9,40.4 L31,39.4 M61.1,40.4 L65,39.4" stroke="%s" stroke-width="1.8"/>') % [GC, GC, GC]
		"square":
			return ('<rect x="34.7" y="36.6" width="11.4" height="9" rx="2.4" fill="none" stroke="%s" stroke-width="1.8"/>' +
				'<rect x="49.9" y="36.6" width="11.4" height="9" rx="2.4" fill="none" stroke="%s" stroke-width="1.8"/>' +
				'<path d="M46.1,40.5 h3.8 M34.7,39.6 L31,38.8 M61.3,39.6 L65,38.8" stroke="%s" stroke-width="1.8"/>') % [GC, GC, GC]
	return ""


static func _age_lines(c: String) -> String:
	return ('<path d="M41.5,48.5 q-2.2,4 -1.2,6.4 M54.5,48.5 q2.2,4 1.2,6.4" fill="none" stroke="%s" stroke-width="1.2" opacity="0.42"/>' +
		'<path d="M40,28.5 q8,-2.6 16,0 M37.5,44.8 q1.6,1.4 3.4,1.2 M58.5,44.8 q-1.6,1.4 -3.4,1.2" fill="none" stroke="%s" stroke-width="1.1" opacity="0.4"/>') % [c, c]
