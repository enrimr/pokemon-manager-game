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

## Translated at call time so a live language switch retitles the button.
func _go_academy() -> Dictionary:
	return {"label": I18n.t("Go to Academy"), "screen": "academy"}


func render(msg: Dictionary) -> Dictionary:
	match str(msg.get("academy_kind", "")):
		"intake":
			return _intake(msg)
		"preview":
			return _preview(msg)
		"promote":
			return _promote(msg)
		"release":
			return _plain(msg)
		"cull":
			return _cull(msg)
		"cull_done", "intake_full", "crowded":
			return _housekeeping(msg)
		"board_request", "board_approve", "board_reject", "facility_open":
			return _board(msg)
	return _plain(msg)


# ------------------------------------------------------- youth review (cull)

## End-of-season youth review: coach keep/release list. Stays a live decision
## (red strip in the list) until the manager applies it on the Academy screen.
func _cull(msg: Dictionary) -> Dictionary:
	var items: Array = msg.get("items", [])
	if items.is_empty():
		return _plain(msg)
	var resolved: bool = msg.get("resolved", false)
	var b := I18n.t("[color=#%s][font_size=12]END-OF-SEASON YOUTH REVIEW  ·  %d/%d BEDS[/font_size][/color]\n") % [
		C_DIM, int(msg.get("size", items.size())), int(msg.get("cap", 8))]
	b += I18n.t("[color=#%s][b]%s[/b] has reviewed every juvenile on the academy roster ahead of the new season.[/color]\n") % [
		C_WHITE, str(msg.get("sender", I18n.t("The head youth coach")))]
	if resolved:
		b += I18n.t("\n[color=#%s][b]✔ Review settled — decisions applied on the Academy screen.[/b][/color]\n") % C_GOOD
	for it in items:
		var rel := str(it.get("rec", "keep")) == "release"
		b += I18n.t("\n[table=1][cell border=#%s bg=#%s padding=10,6,10,6]") % [
			(C_BAD if rel else CARD_EDGE), CARD_BG]
		b += I18n.t("[color=#%s][b]%s[/b][/color]  [color=#%s]Lv %d · %s[/color]   ") % [
			C_WHITE, str(it.get("species", "?")), C_DIM,
			int(it.get("level", 1)), _age(int(it.get("age_months", 12)))]
		b += I18n.t("[color=#%s][b]%s[/b][/color]\n") % [
			(C_BAD if rel else C_GOOD), I18n.t("RELEASE") if rel else I18n.t("KEEP")]
		b += I18n.t("[font_size=12][color=#%s]Potential %s – %s   ·   [i]“%s”[/i][/color][/font_size][/cell][/table]") % [
			C_DIM, _stars(float(int(it.get("pot_min", 4))) / 4.0, C_GOLD),
			_stars(float(int(it.get("pot_max", 8))) / 4.0, C_GOLD), str(it.get("reason", ""))]
	if not resolved:
		b += I18n.t("\n\n[color=#%s]Tick your releases and apply the review on the Academy screen — beds free up before the season's first intake day.[/color]") % C_DIM
	return {"bbcode": b, "actions": [{"label": I18n.t("Settle the review"), "screen": "academy"}]
		if not resolved else [_go_academy()], "banner": {}}


## Roster-pressure housekeeping mail (full intake turned away / crowding
## warning / review settled) under a shared kicker.
func _housekeeping(msg: Dictionary) -> Dictionary:
	var b := I18n.t("[color=#%s][font_size=12]ACADEMY HOUSEKEEPING[/font_size][/color]\n") % C_DIM
	b += "[color=#%s]%s[/color]" % [C_WHITE, str(msg.get("body", ""))]
	if msg.has("cap") and msg.has("size"):
		b += I18n.t("\n\n[color=#%s]Beds[/color]  [color=#%s][b]%d / %d[/b][/color]") % [
			C_DIM, C_WARN if int(msg.get("size", 0)) >= int(msg.get("cap", 8)) else C_ACC,
			int(msg.get("size", 0)), int(msg.get("cap", 8))]
	return {"bbcode": b, "actions": [_go_academy()], "banner": {}}


func _plain(msg: Dictionary) -> Dictionary:
	return {"bbcode": "[color=#%s]%s[/color]" % [C_WHITE, str(msg.get("body", ""))],
		"actions": [_go_academy()], "banner": {}}


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
		out += I18n.t("[bgcolor=#%s][color=#0e1120][b] %s [/b][/color][/bgcolor] ") % [
			c.to_html(false), I18n.type_name(String(t)).to_upper()]
	return out.strip_edges()


static func _age(months: int) -> String:
	return I18n.t("%dy %dm") % [months / 12, months % 12]


func _ceiling_tier(pot_max: int) -> Array:
	if pot_max >= 17:
		return [I18n.t("ELITE CEILING"), C_GOLD]
	if pot_max >= 13:
		return [I18n.t("FIRST-TEAM CEILING"), C_GOOD]
	if pot_max >= 9:
		return [I18n.t("SQUAD CEILING"), C_ACC]
	return [I18n.t("DEPTH AT BEST"), C_DIM]


# ---------------------------------------------------------------- intake day

func _intake(msg: Dictionary) -> Dictionary:
	var recruits: Array = msg.get("recruits", [])
	if recruits.is_empty():
		return _plain(msg)
	var golden: bool = msg.get("golden", false)
	var thin: bool = msg.get("thin", false)
	var coach := str(msg.get("coach", I18n.t("The coaching staff")))
	var b := I18n.t("[color=#%s][font_size=12]YOUTH INTAKE DAY  ·  %s (LEVEL %d)[/font_size][/color]\n") % [
		C_DIM, I18n.t(str(msg.get("facility_name", "Academy"))).to_upper(), int(msg.get("facility", 1))]
	b += I18n.t("[color=#%s][b]%s[/b] presents this month's crop of [b]%d[/b] juveniles from the club's youth programme.[/color]\n") % [
		C_WHITE, coach, recruits.size()]
	if golden:
		b += I18n.t("\n[bgcolor=#3a3113][color=#%s][b] ★ GOLDEN GENERATION — the staff are buzzing. Intakes like this come along once a decade. [/b][/color][/bgcolor]\n") % C_GOLD
	elif thin:
		b += I18n.t("\n[color=#%s][i]A thin month — the region's best young battlers went elsewhere.[/i][/color]\n") % C_WARN
	for r in recruits:
		b += _recruit_card(r, golden)
	b += I18n.t("\n[color=#%s]They begin work at the academy immediately. Set each recruit's training focus and watch the coaches narrow their potential bands over the coming weeks.[/color]") % C_DIM
	return {"bbcode": b, "actions": [_go_academy()], "banner": {}}


func _recruit_card(r: Dictionary, golden: bool) -> String:
	var tier := _ceiling_tier(int(r.get("pot_max", 0)))
	var edge: String = C_GOLD if golden else CARD_EDGE
	var head := I18n.t("[b][color=#%s]%s[/color][/b]  %s  [color=#%s]Lv %d · %s · %s[/color]") % [
		C_WHITE, str(r.get("species", "?")), _type_chips(r.get("types", [])),
		C_DIM, int(r.get("level", 1)), _age(int(r.get("age_months", 12))),
		I18n.t(str(r.get("nature", "")))]
	if r.get("best", false):
		head += I18n.t("   [color=#%s][b]● BEST OF THE CROP[/b][/color]") % C_GOLD
	var meters := I18n.t("[color=#%s]Current[/color]    %s      [color=#%s]Potential[/color]  %s [color=#%s]–[/color] %s   [color=#%s][font_size=12][b]%s[/b][/font_size][/color]") % [
		C_DIM, _stars(float(r.get("stars", 0.5)), C_ACC),
		C_DIM, _stars(float(r.get("band_lo", 0.5)), C_GOLD),
		C_DIM, _stars(float(r.get("band_hi", 0.5)), C_GOLD),
		tier[1], tier[0]]
	var moves: Array = r.get("moves", [])
	var foot := "[font_size=12][color=#%s][i]“%s”[/i]" % [C_DIM, str(r.get("note", ""))]
	if not moves.is_empty():
		var mv_names: Array = []
		for mv in moves:
			mv_names.append(I18n.move_name(str(mv)))
		foot += I18n.t("   ·   Knows: %s") % ", ".join(mv_names)
	foot += "[/color][/font_size]"
	return I18n.t("\n[table=1][cell border=#%s bg=#%s padding=12,8,12,8]%s\n%s\n%s[/cell][/table]") % [
		edge, CARD_BG, head, meters, foot]


# ---------------------------------------------------------------- preview

## A week before intake day: the head youth coach's hedged early read.
func _preview(msg: Dictionary) -> Dictionary:
	var b := I18n.t("[color=#%s][font_size=12]INTAKE PREVIEW  ·  %s (LEVEL %d)[/font_size][/color]\n") % [
		C_DIM, I18n.t(str(msg.get("facility_name", "Academy"))).to_upper(), int(msg.get("facility", 1))]
	b += I18n.t("[color=#%s][b]%s[/b] has been watching this month's youth candidates ahead of intake day on [b]%s[/b].[/color]\n\n") % [
		C_WHITE, str(msg.get("coach", I18n.t("The head youth coach"))), I18n.pretty_date(str(msg.get("intake_on", "")))]
	match str(msg.get("mood", "normal")):
		"golden":
			b += I18n.t("[bgcolor=#3a3113][color=#%s][b] ★ Whispers of a special group — the staff can barely contain themselves. [/b][/color][/bgcolor]\n\n") % C_GOLD
		"thin":
			b += I18n.t("[color=#%s][i]Expectations are low — the region's best juveniles appear to have gone elsewhere.[/i][/color]\n\n") % C_WARN
		_:
			b += I18n.t("[color=#%s]A typical group is expected — a couple of names worth watching, nothing the staff are shouting about yet.[/color]\n\n") % C_WHITE
	b += I18n.t("[color=#%s]Expected class size[/color]  [color=#%s][b]%d–%d juveniles[/b][/color]\n") % [
		C_DIM, C_ACC, int(msg.get("expect_lo", 2)), int(msg.get("expect_hi", 3))]
	b += I18n.t("[font_size=12][color=#%s]First impressions can mislead — the coaches' potential bands only firm up once the recruits start work.[/color][/font_size]") % C_DIM
	return {"bbcode": b, "actions": [_go_academy()], "banner": {}}


# ---------------------------------------------------------------- promotion

func _promote(msg: Dictionary) -> Dictionary:
	if not msg.has("species"):
		return _plain(msg)
	var b := I18n.t("[color=#%s][font_size=12]ACADEMY GRADUATION[/font_size][/color]\n") % C_DIM
	b += I18n.t("[color=#%s][b]%s[/b] steps up from the academy to the first-team squad.[/color]\n") % [
		C_WHITE, str(msg.get("species", "?"))]
	var tier := _ceiling_tier(int(msg.get("pot_max", 0)))
	b += I18n.t("\n[table=1][cell border=#%s bg=#%s padding=12,8,12,8]") % [CARD_EDGE, CARD_BG]
	b += I18n.t("[b][color=#%s]%s[/color][/b]  %s  [color=#%s]Lv %d[/color]\n") % [
		C_WHITE, str(msg.get("species", "?")), _type_chips(msg.get("types", [])),
		C_DIM, int(msg.get("level", 1))]
	b += I18n.t("[color=#%s]Ceiling[/color]  %s [color=#%s]–[/color] %s   [color=#%s][font_size=12][b]%s[/b][/font_size][/color]\n") % [
		C_DIM, _stars(float(msg.get("band_lo", 0.5)), C_GOLD),
		C_DIM, _stars(float(msg.get("band_hi", 0.5)), C_GOLD), tier[1], tier[0]]
	b += I18n.t("[font_size=12][color=#%s]Contract to %s · wage %s/wk[/color][/font_size][/cell][/table]\n") % [
		C_DIM, I18n.pretty_date(str(msg.get("expiry", ""))), _money(int(msg.get("salary", 0)))]
	b += I18n.t("\n[color=#%s]Young battlers develop fastest alongside senior squad-mates — consider assigning a mentor on the Training screen.[/color]") % C_DIM
	return {"bbcode": b, "actions": [
		{"label": I18n.t("View Squad"), "screen": "squad"},
		{"label": I18n.t("Training"), "screen": "training"}, _go_academy()], "banner": {}}


# ---------------------------------------------------------------- board mail

func _board(msg: Dictionary) -> Dictionary:
	var kind := str(msg.get("academy_kind", ""))
	var b := I18n.t("[color=#%s][font_size=12]ACADEMY FACILITIES[/font_size][/color]\n") % C_DIM
	if not msg.has("to_level"):
		# Mail from before the snapshot era (old save): the plain body already
		# carries the facts — present it under the facilities kicker.
		b += "[color=#%s]%s[/color]" % [C_WHITE, str(msg.get("body", ""))]
		return {"bbcode": b, "actions": [_go_academy()], "banner": {}}
	match kind:
		"board_request":
			b += I18n.t("[color=#%s]You have asked the board to fund [b]Level %d[/b] facilities — [b]%s[/b].[/color]\n\n") % [
				C_WHITE, int(msg.get("to_level", 2)), I18n.t(str(msg.get("facility_name", "")))]
			b += I18n.t("[color=#%s]Cost[/color]  [color=#%s][b]%s[/b][/color]\n") % [
				C_DIM, C_WARN, _money(int(msg.get("cost", 0)))]
			b += I18n.t("[color=#%s]The directors will respond by [b]%s[/b]. They approve only if the club can pay while keeping a %s operating reserve.[/color]") % [
				C_DIM, I18n.pretty_date(str(msg.get("decide_on", ""))), _money(int(msg.get("reserve", 150000)))]
		"board_approve":
			b += I18n.t("[color=#%s]The board has [color=#%s][b]APPROVED[/b][/color] your request and released [b]%s[/b] for [b]Level %d[/b] facilities.[/color]\n\n") % [
				C_WHITE, C_GOOD, _money(int(msg.get("cost", 0))), int(msg.get("to_level", 2))]
			b += I18n.t("[color=#%s]Construction completes on [b]%s[/b]. Expect larger, higher-quality intakes from then on.[/color]") % [
				C_DIM, I18n.pretty_date(str(msg.get("complete_on", "")))]
		"board_reject":
			b += I18n.t("[color=#%s]The board has [color=#%s][b]REJECTED[/b][/color] your request for [b]Level %d[/b] facilities.[/color]\n\n") % [
				C_WHITE, C_BAD, int(msg.get("to_level", 2))]
			b += I18n.t("[color=#%s]The club cannot commit %s while keeping a %s operating reserve. Improve the balance and ask again.[/color]") % [
				C_DIM, _money(int(msg.get("cost", 0))), _money(int(msg.get("reserve", 150000)))]
		"facility_open":
			b += I18n.t("[color=#%s]The [b]%s[/b] (Level %d) are open. The youth programme's reach and the quality of raw material both improve immediately.[/color]\n\n") % [
				C_WHITE, I18n.t(str(msg.get("facility_name", ""))), int(msg.get("to_level", 1))]
			b += I18n.t("[color=#%s]Next intake: the 15th of the month. Bigger classes, higher ceilings.[/color]") % C_DIM
		_:
			return _plain(msg)
	return {"bbcode": b, "actions": [_go_academy()], "banner": {}}


static func _money(v: int) -> String:
	return "$" + I18n.number(v)
