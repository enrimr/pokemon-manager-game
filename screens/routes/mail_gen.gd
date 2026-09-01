extends RefCounted
## Expedition mail renderer (routes piece). The inbox's report_gen routes any
## message whose uid starts with "exped:" (or carrying exped_kind) here —
## defensive hook, the inbox works unchanged if this file is absent.
## Contract mirrors report_gen: render(msg) -> {"bbcode", "actions", "banner"}.
## Fields were snapshotted JSON-safe on send day, so reports stay truthful.

const C_GOOD := "57c979"
const C_BAD := "e06060"
const C_WARN := "e0b050"
const C_DIM := "8b91a8"
const C_ACC := "9d92ff"
const C_WHITE := "e8ebf5"
const C_GOLD := "e8c15a"
const CARD_BG := "202741"
const CARD_EDGE := "39415f"

const TIER_LABEL := {"common": "COMMON", "uncommon": "UNCOMMON", "rare": "RARE", "special": "EXCEPTIONAL"}
const TIER_COL := {"common": "8b91a8", "uncommon": "4dc3e6", "rare": "b07be8", "special": "e8c15a"}


func _go_routes() -> Dictionary:
	return {"label": I18n.t("Go to Routes"), "screen": "routes"}


func render(msg: Dictionary) -> Dictionary:
	match str(msg.get("exped_kind", "")):
		"day":
			return _day(msg)
		"final":
			return _final(msg)
		"plan":
			return _plan(msg)
	return _plain(msg, str(msg.get("exped_kind", "")) != "ai_news")


func _plain(msg: Dictionary, with_action: bool = true) -> Dictionary:
	return {"bbcode": "[color=#%s]%s[/color]" % [C_WHITE, str(msg.get("body", ""))],
		"actions": [_go_routes()] if with_action else [], "banner": {}}


func _header(msg: Dictionary, tag: String) -> String:
	return I18n.t("[color=#%s][font_size=12]%s  ·  %s  ·  LED BY %s (%s)[/font_size][/color]\n") % [
		C_DIM, tag, I18n.t(str(msg.get("route_name", "?"))).to_upper(),
		str(msg.get("leader", "?")).to_upper(),
		I18n.t(str(msg.get("approach", "balanced")).capitalize()).to_upper()]


func _type_chips(types: Array) -> String:
	var out := ""
	for t in types:
		out += "[bgcolor=#%s][color=#0d0f16] %s [/color][/bgcolor] " % [
			DataStore.type_color(str(t)).to_html(false), I18n.type_name(str(t)).to_upper()]
	return out


func _plan(msg: Dictionary) -> Dictionary:
	var b := _header(msg, I18n.t("EXPEDITION DEPARTS"))
	b += "[color=#%s]%s[/color]\n" % [C_WHITE, str(msg.get("body", ""))]
	b += I18n.t("\n[color=#%s]Field days %d   ·   Capture gear %d   ·   Cost %s   ·   Captures to the %s[/color]") % [
		C_DIM, int(msg.get("field_days", 0)), int(msg.get("attempts_bought", 0)),
		AcademyService.format_money(int(msg.get("cost", 0))),
		I18n.t("academy") if str(msg.get("dest", "academy")) == "academy" else I18n.t("first team")]
	return {"bbcode": b, "actions": [_go_routes()], "banner": {}}


func _day(msg: Dictionary) -> Dictionary:
	var b := _header(msg, I18n.t("FIELD REPORT — DAY %d/%d") % [
		int(msg.get("day_no", 1)), int(msg.get("field_days", 1))])
	var events: Array = msg.get("events", [])
	if events.is_empty():
		b += I18n.t("[color=#%s]A quiet day in the field — no encounters logged.[/color]\n") % C_DIM
	for ev in events:
		var kind := str(ev.get("kind", "sight"))
		var tier := str(ev.get("tier", "common"))
		var edge := CARD_EDGE
		var head := I18n.t("SIGHTED")
		var head_col := C_DIM
		match kind:
			"catch":
				edge = C_GOOD
				head = I18n.t("CAPTURED")
				head_col = C_GOOD
			"near":
				head = I18n.t("GOT AWAY")
				head_col = C_WARN
			"mishap":
				edge = C_BAD
				head = I18n.t("MISHAP")
				head_col = C_BAD
		b += "\n[table=1][cell border=#%s bg=#%s padding=10,6,10,6]" % [edge, CARD_BG]
		if kind == "mishap":
			b += I18n.t("[color=#%s][b]MISHAP[/b][/color]  [color=#%s]The day was lost — no fieldwork completed.[/color]") % [C_BAD, C_DIM]
		else:
			b += I18n.t("[color=#%s][b]%s[/b][/color]  [color=#%s][b]%s[/b][/color]  [color=#%s]Lv %d[/color]  %s") % [
				head_col, head, C_WHITE, str(ev.get("species", "?")), C_DIM,
				int(ev.get("level", 1)), _type_chips(ev.get("types", []))]
			b += "\n[font_size=12][color=#%s]%s[/color][/font_size]" % [
				str(TIER_COL.get(tier, C_DIM)), I18n.t(str(TIER_LABEL.get(tier, "COMMON")))]
		b += "[/cell][/table]"
	b += I18n.t("\n\n[color=#%s]Capture gear left %d/%d   ·   Captures so far %d[/color]") % [
		C_DIM, int(msg.get("attempts_left", 0)), int(msg.get("attempts_bought", 0)),
		(msg.get("captures", []) as Array).size()]
	return {"bbcode": b, "actions": [_go_routes()], "banner": {}}


func _final(msg: Dictionary) -> Dictionary:
	var b := _header(msg, I18n.t("EXPEDITION RETURNS"))
	var caps: Array = msg.get("captures", [])
	if caps.is_empty():
		b += I18n.t("[color=#%s]The crates came home empty — but every field day sharpened our route intel.[/color]\n") % C_DIM
	for cp in caps:
		var tier := str(cp.get("tier", "common"))
		b += "\n[table=1][cell border=#%s bg=#%s padding=10,6,10,6]" % [
			(C_GOLD if tier == "special" else CARD_EDGE), CARD_BG]
		b += I18n.t("[color=#%s][b]%s[/b][/color]  [color=#%s]Lv %d · %s[/color]  [color=#%s]%s[/color]") % [
			C_WHITE, str(cp.get("species", "?")), C_DIM, int(cp.get("level", 1)),
			I18n.t(str(cp.get("nature", "Hardy"))),
			str(TIER_COL.get(tier, C_DIM)), I18n.t(str(TIER_LABEL.get(tier, "COMMON")))]
		b += I18n.t("\n[font_size=12][color=#%s]Coach-judged potential %s – %s[/color][/font_size]") % [
			C_DIM, AcademyService.star_text(clampf(float(int(cp.get("pot_min", 4))) / 4.0, 0.5, 5.0),),
			AcademyService.star_text(clampf(float(int(cp.get("pot_max", 8))) / 4.0, 0.5, 5.0))]
		b += "[/cell][/table]"
	b += "\n\n[color=#%s]%s[/color]" % [C_WHITE, str(msg.get("body", "")).split("\n")[0]]
	return {"bbcode": b, "actions": [_go_routes()], "banner": {}}
