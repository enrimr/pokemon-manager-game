class_name PortraitSVG
extends Object
## SVG composer for procedural people portraits (portraits piece) — ANIME /
## MANGA styling: big expressive eyes with highlights, tapered chin, tiny
## nose, chunky pointed hair strands, cel-flat colours with clean outlines.
## Pure function of the params dict built by Portrait.params(): returns an
## SVG string (96x96 viewBox) that Portrait rasterizes via
## Image.load_svg_from_string — same pipeline as GlyphIcons, export-safe.

const W := 96


static func compose(p: Dictionary) -> String:
	var skin: String = p["skin"]
	var line: String = p["skin_line"]
	var hair: String = p["hair"]
	var outline: String = p["brow_col"]   # hair outline = darkened hair
	var w: float = float(p["rx"])         # face half-width (15..19)
	var s := '<defs><clipPath id="c"><rect x="0" y="0" width="96" height="96" rx="18"/></clipPath></defs>'
	s += '<g clip-path="url(#c)">'
	s += '<rect width="96" height="96" fill="%s"/>' % p["bg"]
	s += _hair_back(str(p["style"]), hair, outline, w)
	# neck + shoulders/collar
	s += '<path d="M43,50 h10 v18 q0,5 -5,5 q-5,0 -5,-5 Z" fill="%s"/>' % p["skin_sh"]
	s += '<path d="M9,96 L9,93 Q12,73 32,71 L64,71 Q84,73 87,93 L87,96 Z" fill="%s"/>' % p["collar"]
	s += '<path d="M41,71 L48,80 L55,71 Z" fill="%s"/>' % p["collar2"]
	# ears + anime head (round cranium, tapered chin)
	s += '<ellipse cx="%.1f" cy="41" rx="2.6" ry="3.6" fill="%s"/><ellipse cx="%.1f" cy="41" rx="2.6" ry="3.6" fill="%s"/>' \
		% [48.0 - w, skin, 48.0 + w, skin]
	s += ('<path d="M48,61 C %.1f,58.5 %.1f,51 %.1f,40 C %.1f,23.5 %.1f,16.5 48,16.5 ' +
		'C %.1f,16.5 %.1f,23.5 %.1f,40 C %.1f,51 %.1f,58.5 48,61 Z" ' +
		'fill="%s" stroke="%s" stroke-width="1.1" stroke-opacity="0.45"/>') % [
		48.0 - w * 0.52, 48.0 - w * 0.9, 48.0 - w,
		48.0 - w, 48.0 - w * 0.52,
		48.0 + w * 0.52, 48.0 + w, 48.0 + w,
		48.0 + w * 0.9, 48.0 + w * 0.52,
		skin, line]
	if int(p["old"]) == 1:
		s += _age_lines(line)
	elif int(p.get("blush", 0)) == 1:
		s += ('<ellipse cx="%.1f" cy="48.5" rx="2.7" ry="1.3" fill="#e8837a" opacity="0.30"/>' +
			'<ellipse cx="%.1f" cy="48.5" rx="2.7" ry="1.3" fill="#e8837a" opacity="0.30"/>') % \
			[48.0 - w * 0.58, 48.0 + w * 0.58]
	s += _brows(int(p["brow"]), p["brow_col"], w)
	s += _eye(int(p["eye"]), p["eye_col"], 48.0 - w * 0.47, -1.0)
	s += _eye(int(p["eye"]), p["eye_col"], 48.0 + w * 0.47, 1.0)
	# tiny manga nose
	s += '<path d="M48.6,46.6 Q49.4,47.7 48.4,48.8" fill="none" stroke="%s" stroke-width="1.1" stroke-linecap="round" opacity="0.6"/>' % line
	s += _facial_hair(str(p["fhair"]), p["fhair_col"], w)
	s += _mouth(int(p["mouth"]), line)
	s += _hair_front(str(p["style"]), hair, outline, w)
	s += _glasses(str(p["glasses"]), w)
	s += "</g>"
	return '<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96" viewBox="0 0 96 96">%s</svg>' % s


# ------------------------------------------------------------------ eyes
## Big anime eye at (ex, ~41.5). sgn = -1 left / +1 right (mirrors the flick).
static func _eye(kind: int, col: String, ex: float, sgn: float) -> String:
	var s := ""
	var lash := "#241d26"
	match kind:
		1:   # calm / half-lidded
			s += '<ellipse cx="%.1f" cy="42" rx="3.9" ry="3.4" fill="#fbfaf7"/>' % ex
			s += '<ellipse cx="%.1f" cy="42.4" rx="3.0" ry="2.9" fill="%s"/>' % [ex, col]
			s += '<ellipse cx="%.1f" cy="42.6" rx="1.3" ry="1.6" fill="#16121c"/>' % ex
			s += '<circle cx="%.1f" cy="41.2" r="1.0" fill="#ffffff"/>' % (ex - 1.1)
			s += '<path d="M%.1f,39.6 Q%.1f,37.8 %.1f,39.6" fill="none" stroke="%s" stroke-width="2.6" stroke-linecap="round"/>' \
				% [ex - 4.4, ex, ex + 4.4, lash]
			s += '<path d="M%.1f,40.3 L%.1f,40.3" stroke="%s" stroke-width="1.4"/>' % [ex - 3.2, ex + 3.2, lash]
		2:   # sharp, outer flick
			s += '<ellipse cx="%.1f" cy="41.8" rx="4.0" ry="4.4" fill="#fbfaf7"/>' % ex
			s += '<ellipse cx="%.1f" cy="42.2" rx="3.1" ry="3.9" fill="%s"/>' % [ex, col]
			s += '<ellipse cx="%.1f" cy="42.4" rx="1.4" ry="2.0" fill="#16121c"/>' % ex
			s += '<circle cx="%.1f" cy="40.2" r="1.3" fill="#ffffff"/>' % (ex - 1.2)
			s += '<circle cx="%.1f" cy="44.2" r="0.6" fill="#ffffff" opacity="0.85"/>' % (ex + 1.4)
			s += ('<path d="M%.1f,39.4 Q%.1f,36.2 %.1f,38.2 L%.1f,36.8" fill="none" ' +
				'stroke="%s" stroke-width="2.7" stroke-linecap="round"/>') % \
				[ex - sgn * 4.4, ex, ex + sgn * 4.6, ex + sgn * 6.0, lash]
		_:   # 0: big round sparkle
			s += '<ellipse cx="%.1f" cy="41.8" rx="4.1" ry="4.7" fill="#fbfaf7"/>' % ex
			s += '<ellipse cx="%.1f" cy="42.2" rx="3.2" ry="4.1" fill="%s"/>' % [ex, col]
			s += '<ellipse cx="%.1f" cy="42.5" rx="1.5" ry="2.1" fill="#16121c"/>' % ex
			s += '<circle cx="%.1f" cy="40.0" r="1.4" fill="#ffffff"/>' % (ex - 1.3)
			s += '<circle cx="%.1f" cy="44.4" r="0.7" fill="#ffffff" opacity="0.85"/>' % (ex + 1.5)
			s += '<path d="M%.1f,38.8 Q%.1f,36.0 %.1f,38.8" fill="none" stroke="%s" stroke-width="2.8" stroke-linecap="round"/>' \
				% [ex - 4.5, ex, ex + 4.5, lash]
	return s


static func _brows(kind: int, c: String, w: float) -> String:
	var lx := 48.0 - w * 0.47
	var rx := 48.0 + w * 0.47
	match kind:
		0:  # soft arch
			return ('<path d="M%.1f,33.6 Q%.1f,31.8 %.1f,33.2 M%.1f,33.2 Q%.1f,31.8 %.1f,33.6" ' +
				'fill="none" stroke="%s" stroke-width="1.7" stroke-linecap="round"/>') % \
				[lx - 4.2, lx, lx + 4.2, rx - 4.2, rx, rx + 4.2, c]
		1:  # determined (angled in)
			return ('<path d="M%.1f,32.4 L%.1f,34.4 M%.1f,34.4 L%.1f,32.4" ' +
				'fill="none" stroke="%s" stroke-width="2.0" stroke-linecap="round"/>') % \
				[lx - 4.2, lx + 4.0, rx - 4.0, rx + 4.2, c]
		2:  # thick straight
			return ('<path d="M%.1f,33.2 L%.1f,33.0 M%.1f,33.0 L%.1f,33.2" ' +
				'fill="none" stroke="%s" stroke-width="2.6" stroke-linecap="round"/>') % \
				[lx - 4.4, lx + 4.2, rx - 4.2, rx + 4.4, c]
		_:  # short high (surprised-soft)
			return ('<path d="M%.1f,32.2 Q%.1f,31.2 %.1f,32.4 M%.1f,32.4 Q%.1f,31.2 %.1f,32.2" ' +
				'fill="none" stroke="%s" stroke-width="1.7" stroke-linecap="round"/>') % \
				[lx - 3.2, lx, lx + 3.2, rx - 3.2, rx, rx + 3.2, c]


static func _mouth(kind: int, c: String) -> String:
	match kind:
		0:  # smile
			return '<path d="M44.6,53.2 Q48,56.2 51.4,53.2" fill="none" stroke="%s" stroke-width="1.9" stroke-linecap="round"/>' % c
		1:  # open grin (manga triangle)
			return ('<path d="M44.4,52.6 Q48,58.8 51.6,52.6 Z" fill="#5b2730"/>' +
				'<path d="M45.4,53.1 h5.2" stroke="#ffffff" stroke-width="1.4"/>')
		2:  # neutral
			return '<path d="M45.4,54 h5.2" stroke="%s" stroke-width="1.7" stroke-linecap="round"/>' % c
		3:  # slight frown
			return '<path d="M45,55.2 Q48,52.8 51,55.2" fill="none" stroke="%s" stroke-width="1.8" stroke-linecap="round"/>' % c
		_:  # smirk
			return '<path d="M44.8,53.8 Q49.4,56.2 52,52.8" fill="none" stroke="%s" stroke-width="1.8" stroke-linecap="round"/>' % c


# ------------------------------------------------------------------ hair
## Back layers (behind the head).
static func _hair_back(style: String, c: String, o: String, w: float) -> String:
	var L := 48.0 - w
	var R := 48.0 + w
	match style:
		"afro":
			return '<circle cx="48" cy="26.5" r="%.1f" fill="%s" stroke="%s" stroke-width="1.2"/>' % [w + 6.5, c, o]
		"bob":
			return ('<path d="M%.1f,34 Q%.1f,12 48,12 Q%.1f,12 %.1f,34 L%.1f,52 L%.1f,58 L%.1f,58 ' +
				'L%.1f,52 Z" fill="%s" stroke="%s" stroke-width="1.2"/>') % \
				[L - 4.0, L - 3.0, R + 3.0, R + 4.0, R + 4.0, R - 1.0, L + 1.0, L - 4.0, c, o]
		"long":
			return ('<path d="M%.1f,34 Q%.1f,11 48,11 Q%.1f,11 %.1f,34 L%.1f,74 L%.1f,80 L%.1f,68 ' +
				'L%.1f,80 L%.1f,74 Z" fill="%s" stroke="%s" stroke-width="1.2"/>') % \
				[L - 4.5, L - 3.5, R + 3.5, R + 4.5, R + 5.0, R - 3.0, 48.0, L + 3.0, L - 5.0, c, o]
		"bun":
			return ('<circle cx="48" cy="9.5" r="7.5" fill="%s" stroke="%s" stroke-width="1.2"/>' +
				'<circle cx="48" cy="9.5" r="3.2" fill="none" stroke="%s" stroke-width="1" opacity="0.5"/>') % [c, o, o]
		"ponytail":
			return ('<path d="M%.1f,22 Q%.1f,26 %.1f,44 Q%.1f,60 %.1f,72 L%.1f,64 Q%.1f,48 %.1f,30 Z" ' +
				'fill="%s" stroke="%s" stroke-width="1.2"/>') % \
				[R - 3.0, R + 10.0, R + 9.0, R + 8.0, R + 1.0, R - 4.0, R + 3.0, R - 5.0, c, o]
	return ""


## Front layers (over the face): chunky pointed manga strands.
static func _hair_front(style: String, c: String, o: String, w: float) -> String:
	var L := 48.0 - w
	var R := 48.0 + w
	var attr := 'fill="%s" stroke="%s" stroke-width="1.2" stroke-linejoin="round"' % [c, o]
	# shared jagged-bang lower edge (right -> left), points reach y26..33
	var bangs := ('L%.1f,33 L%.1f,30.5 L%.1f,25.5 L%.1f,31.5 L%.1f,25 L%.1f,30.5 L%.1f,26.5 L%.1f,33 Z') % [
		R - 1.5, 48.0 + w * 0.55, 48.0 + w * 0.28, 48.0 + w * 0.02,
		48.0 - w * 0.25, 48.0 - w * 0.5, 48.0 - w * 0.72, L + 1.5]
	var dome := 'M%.1f,40 Q%.1f,12.5 48,12.5 Q%.1f,12.5 %.1f,40 ' % [L - 1.5, L - 1.0, R + 1.0, R + 1.5]
	match style:
		"buzz":
			return ('<path d="M%.1f,36 Q%.1f,15.5 48,15.5 Q%.1f,15.5 %.1f,36 Q%.1f,24 48,23 Q%.1f,24 %.1f,36 Z" ' +
				'fill="%s" opacity="0.62"/>') % [L, L + 1.0, R - 1.0, R, R - 4.0, L + 4.0, L, c]
		"crop", "bun":
			return '<path d="%s%s" %s/>' % [dome, bangs, attr]
		"side", "ponytail":
			return ('<path d="%sL%.1f,36 L%.1f,33.5 L%.1f,27 L%.1f,30 L%.1f,23.5 L%.1f,31 Z" %s/>') % [
				dome, R - 1.0, 48.0 + w * 0.4, 48.0 + w * 0.1,
				48.0 - w * 0.3, 48.0 - w * 0.62, L + 1.5, attr]
		"spiky":
			return ('<path d="M%.1f,38 L%.1f,23 L%.1f,25 L%.1f,10.5 L%.1f,19.5 L48,8 L%.1f,19.5 ' +
				'L%.1f,10.5 L%.1f,25 L%.1f,23 L%.1f,38 %s" %s/>') % [
				L - 2.0, L - 6.5, L + 2.5, 48.0 - 10.0, 48.0 - 4.0, 48.0 + 6.0,
				48.0 + 11.0, R - 2.0, R + 6.5, R + 2.0, bangs, attr]
		"curly":
			return ('<circle cx="%.1f" cy="22" r="8" %s/><circle cx="48" cy="17.5" r="9" %s/>' +
				'<circle cx="%.1f" cy="22" r="8" %s/><circle cx="%.1f" cy="30" r="6" %s/>' +
				'<circle cx="%.1f" cy="30" r="6" %s/>') % \
				[48.0 - w * 0.62, attr, attr, 48.0 + w * 0.62, attr, L + 0.5, attr, R - 0.5, attr]
		"afro":
			return '<path d="%sQ%.1f,22 48,21.5 Q%.1f,22 %.1f,40 Z" %s/>' % \
				[dome, R - 3.0, L + 3.0, L - 1.5, attr]
		"receding":
			return ('<path d="M%.1f,36 Q%.1f,24 %.1f,21.5 L%.1f,28 Q%.1f,29 %.1f,36 Z" %s/>' +
				'<path d="M%.1f,36 Q%.1f,24 %.1f,21.5 L%.1f,28 Q%.1f,29 %.1f,36 Z" %s/>') % \
				[L, L + 0.5, L + 5.0, L + 6.5, L + 2.0, L + 1.0, attr,
				R, R - 0.5, R - 5.0, R - 6.5, R - 2.0, R - 1.0, attr]
		"bob", "long":
			return '<path d="%s%s" %s/>' % [dome, bangs, attr]
		"pixie":
			return ('<path d="%sL%.1f,38 L%.1f,34 L%.1f,26.5 L%.1f,33.5 L%.1f,25 L%.1f,36 L%.1f,42 Z" %s/>') % [
				dome, R - 1.0, 48.0 + w * 0.45, 48.0 + w * 0.15,
				48.0 - w * 0.2, 48.0 - w * 0.5, 48.0 - w * 0.8, L - 1.0, attr]
	return ""   # bald


static func _facial_hair(kind: String, c: String, w: float) -> String:
	var L := 48.0 - w
	var R := 48.0 + w
	var beard := ('M%.1f,42 C%.1f,52 %.1f,60.5 48,62.5 C%.1f,60.5 %.1f,52 %.1f,42 ' +
		'C%.1f,52 %.1f,57.5 48,58.5 C%.1f,57.5 %.1f,52 %.1f,42 Z') % [
		L + 0.8, L + 1.2, 48.0 - w * 0.5, 48.0 + w * 0.5, R - 1.2, R - 0.8,
		R - 2.6, 48.0 + w * 0.4, 48.0 - w * 0.4, L + 2.6, L + 0.8]
	match kind:
		"mustache":
			return '<path d="M43.6,51 Q48,53.8 52.4,51" fill="none" stroke="%s" stroke-width="2.5" stroke-linecap="round"/>' % c
		"goatee":
			return ('<path d="M45,56.5 Q48,63.5 51,56.5 Q48,59.5 45,56.5 Z" fill="%s"/>' +
				'<path d="M44,51.4 Q48,53.8 52,51.4" fill="none" stroke="%s" stroke-width="2.2" stroke-linecap="round"/>') % [c, c]
		"beard":
			return ('<path d="%s" fill="%s"/>' % [beard, c]) + \
				('<path d="M43.6,51 Q48,53.8 52.4,51" fill="none" stroke="%s" stroke-width="2.5" stroke-linecap="round"/>' % c)
		"stubble":
			return '<path d="%s" fill="%s" opacity="0.28"/>' % [beard, c]
	return ""


static func _glasses(kind: String, w: float) -> String:
	const GC := "#232733"
	var lx := 48.0 - w * 0.47
	var rx := 48.0 + w * 0.47
	match kind:
		"round":
			return ('<circle cx="%.1f" cy="41.8" r="5.6" fill="none" stroke="%s" stroke-width="1.7"/>' +
				'<circle cx="%.1f" cy="41.8" r="5.6" fill="none" stroke="%s" stroke-width="1.7"/>' +
				'<path d="M%.1f,41.2 Q48,40 %.1f,41.2 M%.1f,40.8 L%.1f,39.8 M%.1f,40.8 L%.1f,39.8" ' +
				'stroke="%s" stroke-width="1.7" fill="none"/>') % \
				[lx, GC, rx, GC, lx + 5.5, rx - 5.5, lx - 5.5, 48.0 - w - 0.5, rx + 5.5, 48.0 + w + 0.5, GC]
		"square":
			return ('<rect x="%.1f" y="36.8" width="11" height="9.4" rx="2.6" fill="none" stroke="%s" stroke-width="1.7"/>' +
				'<rect x="%.1f" y="36.8" width="11" height="9.4" rx="2.6" fill="none" stroke="%s" stroke-width="1.7"/>' +
				'<path d="M%.1f,41 Q48,39.8 %.1f,41 M%.1f,40.6 L%.1f,39.6 M%.1f,40.6 L%.1f,39.6" ' +
				'stroke="%s" stroke-width="1.7" fill="none"/>') % \
				[lx - 5.5, GC, rx - 5.5, GC, lx + 5.5, rx - 5.5, lx - 5.5, 48.0 - w - 0.5, rx + 5.5, 48.0 + w + 0.5, GC]
	return ""


static func _age_lines(c: String) -> String:
	return ('<path d="M42,49.5 q-2,3.4 -1.1,5.6 M54,49.5 q2,3.4 1.1,5.6" fill="none" stroke="%s" stroke-width="1.1" opacity="0.4"/>' +
		'<path d="M41,28.6 q7,-2.2 14,0 M38.5,45.6 q1.4,1.2 3,1 M57.5,45.6 q-1.4,1.2 -3,1" fill="none" stroke="%s" stroke-width="1" opacity="0.38"/>') % [c, c]
