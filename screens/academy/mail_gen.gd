extends RefCounted
## Academy mail renderer (academy piece). The inbox's report_gen routes any
## message whose uid starts with "academy:" here (defensive hook — the inbox
## works unchanged if this file is absent). Contract mirrors report_gen:
##   render(msg) -> {"bbcode": String, "actions": [{"label","screen"}], "banner": {}}
## All message fields were snapshotted JSON-safe on the day the mail was sent,
## so reports show intake-day truth even after the recruits develop or leave.

const C_GOOD := "57c979"
const C_BAD := "e06060"
const C_WARN := "e0b050"
const C_DIM := "8b91a8"
const C_ACC := "9d92ff"
const C_WHITE := "e8ebf5"
const C_GOLD := "e8c15a"
const C_EMPTY := "494f68"
const CARD_BG := "202741"
const CARD_EDGE := "39415f"

const GO_ACADEMY := {"label": "Go to Academy", "screen": "academy"}


func render(msg: Dictionary) -> Dictionary:
	match str(msg.get("academy_kind", "")):
		"intake":
			return _intake(msg)
		"promote":
			return _promote(msg)
		"release":
			return _plain(msg)
		"board_request", "board_approve", "board_reject", "facility_open":
			return _board(msg)
	return _plain(msg)


func _plain(msg: Dictionary) -> Dictionary:
	return {"bbcode": "[color=#%s]%s[/color]" % [C_WHITE, str(msg.get("body", ""))],
		"actions": [GO_ACADEMY], "banner": {}}


## Padded 5-star meter: ★★★½☆ with the fill coloured and the rest dim.
func _stars(v: float, col: String) -> String:
	var full := int(v)
	var half := v - float(full) >= 0.49
	var fill := ""
	for i in full:
		fill += "★"
	if half:
		fill += "½"
	var pad := ""
	for i in (5 - full - (1 if half else 0)):
		pad += "☆"
	return "[color=#%s]%s[/color][color=#%s]%s[/color]" % [col, fill, C_EMPTY, pad]


func _type_chips(types: Array) -> String:
	var out := ""
	for t in types:
		var c: Color = DataStore.type_color(String(t))
		out += "[bgcolor=#%s][color=#0e1120][b] %s [/b][/color][/bgcolor] " % [
			c.to_html(false), String(t).to_upper()]
	return out.strip_edges()


static func _age(months: int) -> String:
	return "%dy %dm" % [months / 12, months % 12]


func _ceiling_tier(pot_max: int) -> Array:
	if pot_max >= 17:
		return ["ELITE CEILING", C_GOLD]
	if pot_max >= 13:
		return ["FIRST-TEAM CEILING", C_GOOD]
	if pot_max >= 9:
		return ["SQUAD CEILING", C_ACC]
	return ["DEPTH AT BEST", C_DIM]


# ---------------------------------------------------------------- intake day

func _intake(msg: Dictionary) -> Dictionary:
	var recruits: Array = msg.get("recruits", [])
	if recruits.is_empty():
		return _plain(msg)
	var golden: bool = msg.get("golden", false)
	var thin: bool = msg.get("thin", false)
	var coach := str(msg.get("coach", "The coaching staff"))
	var b := "[color=#%s][font_size=12]YOUTH INTAKE DAY  ·  %s (LEVEL %d)[/font_size][/color]\n" % [
		C_DIM, str(msg.get("facility_name", "Academy")).to_upper(), int(msg.get("facility", 1))]
	b += "[color=#%s][b]%s[/b] presents this month's crop of [b]%d[/b] juveniles from the club's youth programme.[/color]\n" % [
		C_WHITE, coach, recruits.size()]
	if golden:
		b += "\n[bgcolor=#3a3113][color=#%s][b] ★ GOLDEN GENERATION — the staff are buzzing. Intakes like this come along once a decade. [/b][/color][/bgcolor]\n" % C_GOLD
	elif thin:
		b += "\n[color=#%s][i]A thin month — the region's best young battlers went elsewhere.[/i][/color]\n" % C_WARN
	for r in recruits:
		b += _recruit_card(r, golden)
	b += "\n[color=#%s]They begin work at the academy immediately. Set each recruit's training focus and watch the coaches narrow their potential bands over the coming weeks.[/color]" % C_DIM
	return {"bbcode": b, "actions": [GO_ACADEMY], "banner": {}}


func _recruit_card(r: Dictionary, golden: bool) -> String:
	var tier := _ceiling_tier(int(r.get("pot_max", 0)))
	var edge: String = C_GOLD if golden else CARD_EDGE
	var head := "[b][color=#%s]%s[/color][/b]  %s  [color=#%s]Lv %d · %s · %s[/color]" % [
		C_WHITE, str(r.get("species", "?")), _type_chips(r.get("types", [])),
		C_DIM, int(r.get("level", 1)), _age(int(r.get("age_months", 12))),
		str(r.get("nature", ""))]
	if r.get("best", false):
		head += "   [color=#%s][b]● BEST OF THE CROP[/b][/color]" % C_GOLD
	var meters := "[color=#%s]Current[/color]    %s      [color=#%s]Potential[/color]  %s [color=#%s]–[/color] %s   [color=#%s][font_size=12][b]%s[/b][/font_size][/color]" % [
		C_DIM, _stars(float(r.get("stars", 0.5)), C_ACC),
		C_DIM, _stars(float(r.get("band_lo", 0.5)), C_GOLD),
		C_DIM, _stars(float(r.get("band_hi", 0.5)), C_GOLD),
		tier[1], tier[0]]
	var moves: Array = r.get("moves", [])
	var foot := "[font_size=12][color=#%s][i]“%s”[/i]" % [C_DIM, str(r.get("note", ""))]
	if not moves.is_empty():
		foot += "   ·   Knows: %s" % ", ".join(moves)
	foot += "[/color][/font_size]"
	return "\n[table=1][cell border=#%s bg=#%s padding=12,8,12,8]%s\n%s\n%s[/cell][/table]" % [
		edge, CARD_BG, head, meters, foot]


# ---------------------------------------------------------------- promotion

func _promote(msg: Dictionary) -> Dictionary:
	if not msg.has("species"):
		return _plain(msg)
	var b := "[color=#%s][font_size=12]ACADEMY GRADUATION[/font_size][/color]\n" % C_DIM
	b += "[color=#%s][b]%s[/b] steps up from the academy to the first-team squad.[/color]\n" % [
		C_WHITE, str(msg.get("species", "?"))]
	var tier := _ceiling_tier(int(msg.get("pot_max", 0)))
	b += "\n[table=1][cell border=#%s bg=#%s padding=12,8,12,8]" % [CARD_EDGE, CARD_BG]
	b += "[b][color=#%s]%s[/color][/b]  %s  [color=#%s]Lv %d[/color]\n" % [
		C_WHITE, str(msg.get("species", "?")), _type_chips(msg.get("types", [])),
		C_DIM, int(msg.get("level", 1))]
	b += "[color=#%s]Ceiling[/color]  %s [color=#%s]–[/color] %s   [color=#%s][font_size=12][b]%s[/b][/font_size][/color]\n" % [
		C_DIM, _stars(float(msg.get("band_lo", 0.5)), C_GOLD),
		C_DIM, _stars(float(msg.get("band_hi", 0.5)), C_GOLD), tier[1], tier[0]]
	b += "[font_size=12][color=#%s]Contract to %s · wage %s/wk[/color][/font_size][/cell][/table]\n" % [
		C_DIM, str(msg.get("expiry", "")), _money(int(msg.get("salary", 0)))]
	b += "\n[color=#%s]Young battlers develop fastest alongside senior squad-mates — consider assigning a mentor on the Training screen.[/color]" % C_DIM
	return {"bbcode": b, "actions": [
		{"label": "View Squad", "screen": "squad"},
		{"label": "Training", "screen": "training"}, GO_ACADEMY], "banner": {}}


# ---------------------------------------------------------------- board mail

func _board(msg: Dictionary) -> Dictionary:
	var kind := str(msg.get("academy_kind", ""))
	var b := "[color=#%s][font_size=12]ACADEMY FACILITIES[/font_size][/color]\n" % C_DIM
	match kind:
		"board_request":
			b += "[color=#%s]You have asked the board to fund [b]Level %d[/b] facilities — [b]%s[/b].[/color]\n\n" % [
				C_WHITE, int(msg.get("to_level", 2)), str(msg.get("facility_name", ""))]
			b += "[color=#%s]Cost[/color]  [color=#%s][b]%s[/b][/color]\n" % [
				C_DIM, C_WARN, _money(int(msg.get("cost", 0)))]
			b += "[color=#%s]The directors will respond by [b]%s[/b]. They approve only if the club can pay while keeping a %s operating reserve.[/color]" % [
				C_DIM, str(msg.get("decide_on", "")), _money(int(msg.get("reserve", 150000)))]
		"board_approve":
			b += "[color=#%s]The board has [color=#%s][b]APPROVED[/b][/color] your request and released [b]%s[/b] for [b]Level %d[/b] facilities.[/color]\n\n" % [
				C_WHITE, C_GOOD, _money(int(msg.get("cost", 0))), int(msg.get("to_level", 2))]
			b += "[color=#%s]Construction completes on [b]%s[/b]. Expect larger, higher-quality intakes from then on.[/color]" % [
				C_DIM, str(msg.get("complete_on", ""))]
		"board_reject":
			b += "[color=#%s]The board has [color=#%s][b]REJECTED[/b][/color] your request for [b]Level %d[/b] facilities.[/color]\n\n" % [
				C_WHITE, C_BAD, int(msg.get("to_level", 2))]
			b += "[color=#%s]The club cannot commit %s while keeping a %s operating reserve. Improve the balance and ask again.[/color]" % [
				C_DIM, _money(int(msg.get("cost", 0))), _money(int(msg.get("reserve", 150000)))]
		"facility_open":
			b += "[color=#%s]The [b]%s[/b] (Level %d) are open. The youth programme's reach and the quality of raw material both improve immediately.[/color]\n\n" % [
				C_WHITE, str(msg.get("facility_name", "")), int(msg.get("to_level", 1))]
			b += "[color=#%s]Next intake: the 15th of the month. Bigger classes, higher ceilings.[/color]" % C_DIM
		_:
			return _plain(msg)
	return {"bbcode": b, "actions": [GO_ACADEMY], "banner": {}}


static func _money(v: int) -> String:
	var s := str(v)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return "$" + s + out
