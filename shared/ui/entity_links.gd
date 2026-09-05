class_name EntityLinks
extends Object
## Inline entity deep-links (user request 2026-09-05): club names, rival
## managers and our own squad's Pokémon mentioned inside inbox copy become
## clickable links that navigate to that entity — the same destinations the
## global search uses.
##
##   EntityLinks.linkify(bbcode) -> bbcode with [url=kind:id] wraps
##   EntityLinks.resolve(meta)   -> navigate_to context ({} if unknown)
##
## The index is rebuilt per call (≈80 names, trivially cheap) so new signings
## and career switches are always current.

const LINK_COLOR := "#9a8dff"

static var _index: Array = []   # [{name, meta}] — longest names first


static func linkify(bbcode: String) -> String:
	_build()
	if _index.is_empty():
		return bbcode
	# only plain-text segments get linkified; existing [tags] pass through
	var tag_re := RegEx.create_from_string("\\[[^\\]]*\\]")
	var out := ""
	var pos := 0
	for m in tag_re.search_all(bbcode):
		out += _link_plain(bbcode.substr(pos, m.get_start() - pos))
		out += m.get_string()
		pos = m.get_end()
	out += _link_plain(bbcode.substr(pos))
	return out


static func resolve(meta: String) -> Dictionary:
	var sep := meta.find(":")
	if sep <= 0:
		return {}
	var kind := meta.substr(0, sep)
	var id := meta.substr(sep + 1)
	match kind:
		"club":
			return {"screen": "competition", "kind": "club", "id": id, "tab": "table"}
		"pokemon":
			return {"screen": "squad", "kind": "pokemon", "id": id}
	return {}


static func _build() -> void:
	_index.clear()
	for c in GameState.world.get("clubs", []):
		var cid := str(c["id"])
		if GameState.is_player_club(cid):
			continue   # our own club name in mail is flavour, not navigation
		_index.append({"name": str(c["name"]), "meta": "club:%s" % cid})
		var mgr := str(c.get("manager", ""))
		if mgr != "":
			_index.append({"name": mgr, "meta": "club:%s" % cid})
	for inst in GameState.player_club().get("squad", []):
		var nick = inst.get("nickname")
		var display := str(nick) if nick != null and str(nick) != "" else str(inst["species"])
		_index.append({"name": display, "meta": "pokemon:%s" % str(inst["uid"])})
	_index.sort_custom(func(a, b): return str(a["name"]).length() > str(b["name"]).length())


## Single left-to-right scan: earliest match wins (ties go to the longest
## name), and inserted link markup is never rescanned.
static func _link_plain(text: String) -> String:
	var out := ""
	var pos := 0
	while pos < text.length():
		var best := -1
		var best_at := text.length()
		for i in _index.size():
			var at := _find_word(text, str(_index[i]["name"]), pos)
			if at >= 0 and at < best_at:
				best_at = at
				best = i
		if best < 0:
			out += text.substr(pos)
			break
		var name := str(_index[best]["name"])
		out += text.substr(pos, best_at - pos)
		out += "[url=%s][color=%s]%s[/color][/url]" % [_index[best]["meta"], LINK_COLOR, name]
		pos = best_at + name.length()
	return out


static func _find_word(text: String, name: String, from_pos: int) -> int:
	var at := text.find(name, from_pos)
	while at >= 0:
		var before_ok := at == 0 or not _wordc(text[at - 1])
		var after := at + name.length()
		var after_ok := after >= text.length() or not _wordc(text[after])
		if before_ok and after_ok:
			return at
		at = text.find(name, at + 1)
	return -1


static func _wordc(c: String) -> bool:
	return c.to_lower() != c.to_upper() or (c >= "0" and c <= "9")
