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


## Deep link into the Routes screen. Field reports land on the live tracker,
## return reports on History, everything else on the Route Map.
func _go_routes(tab: String = "expeditions") -> Dictionary:
	return {"label": I18n.t("Go to Routes"), "screen": "routes", "tab": tab}


func render(msg: Dictionary) -> Dictionary:
	match str(msg.get("exped_kind", "")):
		"day":
			return _day(msg)
		"final":
			return _final(msg)
		"plan":
			return _plan(msg)
		"intro":
			return _plain(msg, true, "map")
		"recall":
			return _plain(msg, true, "expeditions")
		"leg_sighting":
			return _leg_sighting(msg)
		"leg_success", "leg_ai":
			return _leg_press(msg)
		"leg_depart", "leg_day":
			return _leg_hunt(msg, "expeditions")
		"leg_final":
			return _leg_hunt(msg, "history")
		"leg_board":
			return _plain(msg, false)
	return _plain(msg, str(msg.get("exped_kind", "")) != "ai_news")


# ------------------------------------------------------------------ legendaries

func _leg_banner(msg: Dictionary, tag: String, edge: String) -> String:
	var b := "[table=1][cell border=#%s bg=#%s padding=12,8,12,8]" % [edge, CARD_BG]
	b += "[color=#%s][font_size=12]%s[/font_size][/color]\n" % [C_GOLD, tag]
	b += "[color=#%s][b][font_size=18]%s[/font_size][/b][/color]  %s" % [
		C_WHITE, str(msg.get("leg_name", "?")), _type_chips(msg.get("types", []))]
	b += "[/cell][/table]\n"
	return b


func _leg_sighting(msg: Dictionary) -> Dictionary:
	var b := _leg_banner(msg, I18n.t("LEGENDARY SIGHTING"), C_GOLD)
	b += "[color=#%s]%s[/color]\n" % [C_WHITE, str(msg.get("body", ""))]
	b += I18n.t("\n[color=#%s][b]Trail: %s   ·   Window closes %s (%d days)[/b][/color]") % [
		C_GOLD, str(msg.get("site", "?")),
		I18n.pretty_date(str(msg.get("window_end", ""))), int(msg.get("window_days", 0))]
	return {"bbcode": b, "actions": [_go_routes("map")], "banner": {}}


func _leg_press(msg: Dictionary) -> Dictionary:
	var ours := str(msg.get("exped_kind", "")) == "leg_success"
	var b := _leg_banner(msg, I18n.t("HISTORY MADE") if ours else I18n.t("CAPTURED BY A RIVAL"),
		C_GOLD if ours else C_BAD)
	b += "[color=#%s]%s[/color]" % [C_WHITE, str(msg.get("body", ""))]
	return {"bbcode": b, "actions": [_go_routes("history")], "banner": {}}


func _leg_hunt(msg: Dictionary, tab: String) -> Dictionary:
	var b := _leg_banner(msg, I18n.t("SPECIAL EXPEDITION"), C_ACC)
	b += "[color=#%s]%s[/color]" % [C_WHITE, str(msg.get("body", ""))]
	if msg.has("odds"):
		b += I18n.t("\n\n[color=#%s]Site %s   ·   Led by %s   ·   Capture odds %d%%[/color]") % [
			C_DIM, str(msg.get("site", "?")), str(msg.get("leader", "?")),
			int(round(float(msg.get("odds", 0.0)) * 100.0))]
	return {"bbcode": b, "actions": [_go_routes(tab)], "banner": {}}


func _plain(msg: Dictionary, with_action: bool = true, tab: String = "expeditions") -> Dictionary:
	return {"bbcode": "[color=#%s]%s[/color]" % [C_WHITE, str(msg.get("body", ""))],
		"actions": [_go_routes(tab)] if with_action else [], "banner": {}}


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
	# The leader's prose (arrival notes, stalking stories, mishap excuses) IS
	# the report — render it above the event cards. The body's final line is
	# the gear summary the footer already covers, so it is dropped here.
	var prose: Array = str(msg.get("body", "")).split("\n")
	while not prose.is_empty() and str(prose.back()).strip_edges() == "":
		prose.pop_back()
	if not prose.is_empty():
		prose.pop_back()  # trailing "Capture gear left ..." line
	while not prose.is_empty() and str(prose.back()).strip_edges() == "":
		prose.pop_back()
	if not prose.is_empty():
		b += "[color=#%s]%s[/color]\n" % [C_WHITE, "\n".join(prose)]
	var events: Array = msg.get("events", [])
	if events.is_empty() and prose.is_empty():
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
	return {"bbcode": b, "actions": [_go_routes("history")], "banner": {}}
