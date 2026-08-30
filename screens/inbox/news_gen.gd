extends RefCounted
## Inbox piece: news generation + enrichment + board/finance computations.
## Only touches GameState.inbox via the documented add_inbox_message API,
## then annotates the created message dicts with extra (JSON-safe) keys:
##   cat: "match"|"cup"|"scout"|"transfer"|"board"
##   sender, uid, urgent, fid, prospect_uid, bidder, fee, deadline...
## Everything is deterministic (career_seed + date) and duplicate-guarded
## by uid, so re-running on every screen load is safe.

const CATS := {
	"match":    {"letter": "M", "color": Color("57c979"), "label": "Match"},
	"cup":      {"letter": "C", "color": Color("e0b050"), "label": "Cup"},
	"scout":    {"letter": "S", "color": Color("4dc3e6"), "label": "Scouting"},
	"transfer": {"letter": "T", "color": Color("b07be8"), "label": "Transfers"},
	"board":    {"letter": "B", "color": Color("e06060"), "label": "Board"},
}

var _initial_finances: Dictionary = {}   # club_id -> starting balance (from static world.json)

## Live transfer market (owned by the transfers piece). We do not edit its
## code — we consume its documented singleton + public offers_in API so that
## inbox "Transfer offer" messages are the SAME offers the Transfer Centre
## shows, and Accept/Reject in the inbox moves real money and squad members.
const MARKET_PATH := "res://screens/transfers/market.gd"
var _market: RefCounted = null
var _market_checked := false


func market() -> RefCounted:
	if _market == null and not _market_checked:
		_market_checked = true
		if ResourceLoader.exists(MARKET_PATH):
			var scr: Variant = load(MARKET_PATH)
			if scr is GDScript and (scr as GDScript).can_instantiate():
				_market = (scr as GDScript).instance()
	return _market


func offer_by_id(offer_id: int) -> Dictionary:
	var mkt := market()
	if mkt == null:
		return {}
	for o in mkt.offers_in:
		if int(o["id"]) == offer_id:
			return o
	return {}


## Headline fee of an incoming offer — supports both the market's v2
## structured packages and plain v1 {bid} entries.
func offer_bid(o: Dictionary) -> int:
	var mkt := market()
	if o.has("package") and mkt != null and mkt.has_method("package_total"):
		return int(mkt.package_total(o["package"]))
	return int(o.get("bid", 0))


## Is this offer still awaiting a decision from us?
func offer_actionable(o: Dictionary) -> bool:
	if o.is_empty():
		return false
	var stage := str(o["stage"])
	if stage == "agreed":
		return true
	if stage == "open":
		return str(o.get("expires_on", "9999")) >= GameState.current_date
	return false


# ------------------------------------------------------------- enrichment

## Attach cat/sender/etc. to messages created by GameState (match reports,
## cup draws, welcome) or by older versions of this generator.
func enrich_existing() -> void:
	var pc: Dictionary = GameState.player_club()
	for m in GameState.inbox:
		if m.has("cat"):
			_refresh_urgency(m)
			continue
		var title: String = m.get("title", "")
		if title.begins_with("Match report:"):
			m["cat"] = "match"
			m["sender"] = assistant_name()
			var fid := _player_fixture_id_on(m["date"])
			if fid != "":
				m["fid"] = fid
		elif title.begins_with("Cup draw:"):
			m["cat"] = "cup"
			m["sender"] = "Indigo League Cup Committee"
			for r in range(1, 7):
				if title.contains(Season.cup_round_name(r)):
					m["round"] = r
					break
		elif title.begins_with("Welcome to"):
			m["cat"] = "board"
			m["uid"] = "board:welcome"
			m["sender"] = "%s Board of Directors" % pc.get("name", "Club")
		elif _is_market_title(title):
			m["cat"] = "transfer"
			m["sender"] = _market_sender(title)
		elif title.begins_with("Scouting:") or title.begins_with("Scout report ready:"):
			m["cat"] = "scout"
			m["sender"] = scout_name()
		else:
			m["cat"] = "board"
			m["sender"] = pc.get("name", "Club")
		_refresh_urgency(m)


## Titles produced by the transfers piece's market via add_inbox_message.
func _is_market_title(title: String) -> bool:
	for p in ["Transfer offer:", "Improved bid:", "Fee agreed:", "Bid rejected:",
		"Counter offer:", "Signing completed:", "Sale completed:", "Contract talks:",
		"Talks collapse:", "Deal collapsed:", "Market news:"]:
		if title.begins_with(p):
			return true
	if title.contains("withdraw interest in"):
		return true
	if title.contains(" agree ") and title.contains(" for "):
		return true
	return false


func _market_sender(title: String) -> String:
	# "<Club short> agree ..." / "<Club short> withdraw interest ..." read best
	# from the club; everything else from our own transfer department.
	for c in GameState.world["clubs"]:
		if title.begins_with(str(c["short"]) + " ") or title.contains(str(c["name"])):
			if not GameState.is_player_club(c["id"]):
				return str(c["name"])
	return "%s Transfer Centre" % GameState.player_club().get("short", "Club")


func _refresh_urgency(m: Dictionary) -> void:
	match str(m.get("cat", "")):
		"transfer":
			if m.has("offer_id"):
				return  # owned by sync_market_offers (live decision state)
			var dl: String = m.get("deadline", "")
			m["urgent"] = dl != "" and GameState.current_date <= dl and not m.get("read", false)
		"match":
			if str(m.get("uid", "")).begins_with("prematch:"):
				var f := _fixture_by_id(m.get("fid", ""))
				m["urgent"] = not f.is_empty() and not f.get("played", false)


func _player_fixture_id_on(date: String) -> String:
	for f in GameState.player_fixtures():
		if f["date"] == date and f["played"]:
			return f["id"]
	return ""


func _fixture_by_id(fid: String) -> Dictionary:
	if fid == "":
		return {}
	for f in GameState.fixtures:
		if f["id"] == fid:
			return f
	return {}


# ------------------------------------------------------------- generation

## Backfill deterministic news from season start up to the current date.
func generate() -> void:
	var have := {}
	for m in GameState.inbox:
		if m.has("uid"):
			have[m["uid"]] = true

	var start: String = GameState.season_start
	var days := _days_between(start, GameState.current_date)

	_migrate_legacy_offers()
	_gen_preseason(have, start)
	for d in range(0, days + 1):
		var date := Season.date_add(start, d)
		if d > 0 and date.ends_with("-01"):
			_gen_board_review(have, date)
		if (d > 2 and d % 9 == 3) or d == 0:
			_gen_scout_report(have, date, d, 0)
			if d == 0:
				_gen_scout_report(have, date, d, 1)
		if d % 5 == 2 or d == 0:
			_gen_transfer_interest(have, date, d)
	_gen_prematch(have)
	_gen_cup_first_round(have)
	sync_market_offers()


func _add(have: Dictionary, uid: String, date: String, title: String, body: String, extra: Dictionary) -> void:
	if have.has(uid):
		return
	GameState.add_inbox_message(date, title, body)
	var m: Dictionary = GameState.inbox[0]
	m["uid"] = uid
	for k in extra:
		m[k] = extra[k]
	# keep backfilled history reading naturally: old items arrive read —
	# except items still demanding a decision (live offers, briefings)
	if date < GameState.current_date and not m.get("urgent", false):
		m["read"] = true
	have[uid] = true


func _gen_preseason(have: Dictionary, start: String) -> void:
	var pc: Dictionary = GameState.player_club()
	_add(have, "board:preseason", start,
		"Season preview: what the board expects",
		"The board has set out its expectations for the %s campaign." % GameState.world["meta"]["league_name"],
		{"cat": "board", "sender": "%s Board of Directors" % pc["name"]})


func _gen_board_review(have: Dictionary, date: String) -> void:
	var pc: Dictionary = GameState.player_club()
	var months := ["", "January", "February", "March", "April", "May", "June",
		"July", "August", "September", "October", "November", "December"]
	var month_name: String = months[int(date.split("-")[1])]
	_add(have, "board:%s" % date.substr(0, 7), date,
		"Board review: %s" % month_name,
		"The board has met to review the club's progress on and off the pitch.",
		{"cat": "board", "sender": "%s Board of Directors" % pc["name"]})


func _gen_scout_report(have: Dictionary, date: String, day: int, salt: int) -> void:
	var prospects: Array = GameState.prospects()
	if prospects.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.career_seed + day * 131 + salt * 7 + 5
	var p: Dictionary = prospects[rng.randi_range(0, prospects.size() - 1)]
	var uid := "scout:%s:%d" % [date, salt]
	_add(have, uid, date,
		"Scout report: %s (%s)" % [display_name(p), p["species"]],
		"%s has filed a full report on a prospect he has been tracking." % scout_name(),
		{"cat": "scout", "sender": scout_name(), "prospect_uid": p["uid"]})


## Deterministic transfer interest — but REAL: the offer is registered in the
## transfers market's offers_in ledger, so accepting it here (or in the
## Transfer Centre) genuinely moves the squad member and the fee.
func _gen_transfer_interest(have: Dictionary, date: String, day: int) -> void:
	var mkt := market()
	if mkt == null:
		return
	var uid := "transfer:%s" % date
	if have.has(uid):
		return
	var deadline := Season.date_add(date, 5)
	if deadline < GameState.current_date:
		return  # window already closed — never mint dead "decision" mail
	for o in mkt.active_offers_in():
		# one live saga at a time; the market also generates its own.
		# (an "open" offer past its deadline no longer blocks — the market
		# only stamps it "expired" on its next daily tick)
		if str(o["stage"]) != "open" or str(o.get("expires_on", "9999")) >= GameState.current_date:
			return
	var pc: Dictionary = GameState.player_club()
	if pc["squad"].size() <= 6:
		return  # league minimum — nobody bids a club into extinction
	var squad: Array = pc["squad"].duplicate()
	squad.sort_custom(func(a, b): return int(a["level"]) > int(b["level"]))
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.career_seed + day * 977 + 13
	var target: Dictionary = squad[rng.randi_range(0, mini(5, squad.size() - 1))]
	var others: Array = GameState.world["clubs"].filter(func(c): return not GameState.is_player_club(c["id"]))
	var bidder: Dictionary = others[rng.randi_range(0, others.size() - 1)]
	var fee := int(round(float(mkt.value_of(target)) * (0.8 + rng.randf() * 0.45) / 1000.0)) * 1000
	fee = mini(fee, int(bidder["finances"]["balance"]))
	if fee < 1000:
		return
	var oid := _register_market_offer(target, bidder["id"], fee, date, deadline)
	if oid < 0:
		return
	_add(have, uid, date,
		"Transfer offer: %s bid %s for %s" % [bidder["name"], money(fee), display_name(target)],
		"%s have submitted a formal offer for %s. The offer expires on %s." %
			[bidder["name"], display_name(target), Season.pretty_date(deadline)],
		{"cat": "transfer", "sender": bidder["name"], "bidder": bidder["id"],
			"target_uid": target["uid"], "fee": fee, "deadline": deadline,
			"offer_id": oid, "urgent": true})


## Append a well-formed offer to the market ledger (same schema the market's
## own generator uses). Returns the offer id, or -1.
func _register_market_offer(target: Dictionary, bidder_id: String, fee: int, date: String, deadline: String) -> int:
	var mkt := market()
	if mkt == null:
		return -1
	for o in mkt.offers_in:
		if str(o["uid"]) == str(target["uid"]) and str(o["stage"]) in ["open", "counter_pending", "agreed"]:
			return -1
	var bidder: Dictionary = GameState.club(bidder_id)
	if bidder.is_empty():
		return -1
	var oid := int(mkt._next_id)
	mkt._next_id = oid + 1
	var offer := {
		"id": oid, "uid": str(target["uid"]), "club_id": bidder_id,
		"bid": fee, "ask": 0, "ask_sell_on": 0, "stage": "open",
		"name": mkt.display_name(target), "respond_on": "", "expires_on": deadline,
		"log": [{"date": date, "text": "%s bid %s." % [bidder["short"], mkt.fmt_money(fee)]}],
	}
	# v2 markets deal in structured packages; keep "bid" too for older schemas
	if mkt.has_method("blank_package"):
		offer["package"] = mkt.blank_package(fee)
	mkt.offers_in.append(offer)
	mkt.save_state()
	mkt.market_updated.emit()
	return oid


## Older saves carried purely-cosmetic offer messages (fee/deadline but no
## market entry). Give live ones a real market offer; retire dead ones.
func _migrate_legacy_offers() -> void:
	var mkt := market()
	for m in GameState.inbox:
		if str(m.get("cat", "")) != "transfer" or m.has("offer_id") or not m.has("target_uid"):
			continue
		if not str(m.get("uid", "")).begins_with("transfer:") or m.get("legacy_expired", false):
			continue
		var dl := str(m.get("deadline", ""))
		var t: Dictionary = {} if mkt == null else mkt.find_target(str(m["target_uid"]))
		if mkt == null or dl == "" or dl < GameState.current_date \
			or t.is_empty() or str(t["pool"]) != "mine":
			m["legacy_expired"] = true
			m["urgent"] = false
			continue
		var oid := _register_market_offer(t["inst"], str(m.get("bidder", "")),
			int(m.get("fee", 0)), str(m["date"]), dl)
		if oid >= 0:
			m["offer_id"] = oid
		else:
			m["legacy_expired"] = true
			m["urgent"] = false


## Mirror every market offer into the inbox and keep decision flags live:
## adopt the market's own notification mail where one exists, create one
## otherwise, and keep `urgent` = "still needs a decision from the manager".
func sync_market_offers() -> void:
	var mkt := market()
	if mkt == null:
		return
	var linked := {}   # offer_id -> [msgs]
	for m in GameState.inbox:
		if m.has("offer_id"):
			var k := int(m["offer_id"])
			if not linked.has(k):
				linked[k] = []
			linked[k].append(m)
	for o in mkt.offers_in:
		var oid := int(o["id"])
		if not linked.has(oid):
			var m := _adopt_offer_message(o)
			# only mint fresh mail for offers still worth reading about —
			# stale expired-open entries stay in the ledger, not the inbox
			if m.is_empty() and (offer_actionable(o) or str(o["stage"]) == "counter_pending"):
				m = _create_offer_message(o)
			if not m.is_empty():
				linked[oid] = [m]
		for m2 in linked.get(oid, []):
			_refresh_offer_msg(m2, o)


func _adopt_offer_message(o: Dictionary) -> Dictionary:
	var nm := str(o["name"])
	for m in GameState.inbox:   # inbox is newest-first
		if m.has("offer_id"):
			continue
		var title := str(m.get("title", ""))
		if not title.contains(nm):
			continue
		if title.begins_with("Transfer offer:") or title.begins_with("Improved bid:") \
			or (title.contains(" agree ") and title.contains(" for ")):
			m["offer_id"] = int(o["id"])
			m["cat"] = "transfer"
			var bidder: Dictionary = GameState.club(str(o["club_id"]))
			if not bidder.is_empty():
				m["sender"] = bidder["name"]
				m["bidder"] = bidder["id"]
			m["target_uid"] = str(o["uid"])
			return m
	return {}


func _create_offer_message(o: Dictionary) -> Dictionary:
	var mkt := market()
	var bidder: Dictionary = GameState.club(str(o["club_id"]))
	if bidder.is_empty() or mkt == null:
		return {}
	var logs: Array = o.get("log", [])
	var date: String = str(logs[0]["date"]) if not logs.is_empty() else GameState.current_date
	GameState.add_inbox_message(date,
		"Transfer offer: %s bid %s for %s" % [bidder["name"], money(offer_bid(o)), str(o["name"])],
		"%s have made a formal offer for %s. A decision is required." % [bidder["name"], str(o["name"])])
	var m: Dictionary = GameState.inbox[0]
	m["uid"] = "offerin:%d" % int(o["id"])
	m["cat"] = "transfer"
	m["sender"] = bidder["name"]
	m["bidder"] = bidder["id"]
	m["target_uid"] = str(o["uid"])
	m["offer_id"] = int(o["id"])
	return m


func _refresh_offer_msg(m: Dictionary, o: Dictionary) -> void:
	m["urgent"] = offer_actionable(o)
	m["stage"] = str(o["stage"])
	if o.has("expires_on") and str(o["expires_on"]) != "":
		m["deadline"] = str(o["expires_on"])
	m["fee"] = int(o["ask"]) if str(o["stage"]) == "agreed" and int(o["ask"]) > 0 else offer_bid(o)


func _gen_prematch(have: Dictionary) -> void:
	var f: Dictionary = GameState.next_player_fixture()
	if f.is_empty():
		return
	if _days_between(GameState.current_date, f["date"]) > 7:
		return
	var we_home: bool = GameState.is_player_club(f["home"])
	var opp: Dictionary = GameState.club(f["away"] if we_home else f["home"])
	var comp_label: String = "league" if f["comp"] == "league" else Season.cup_round_name(int(f["round"])) + " cup tie"
	_add(have, "prematch:%s" % f["id"], GameState.current_date,
		"Next match: %s %s (%s)" % ["vs" if we_home else "at", opp["name"], comp_label],
		"Pre-match briefing prepared ahead of the %s meeting with %s on %s." %
			[comp_label, opp["name"], Season.pretty_date(f["date"])],
		{"cat": "match", "sender": assistant_name(), "fid": f["id"], "urgent": true})


func _gen_cup_first_round(have: Dictionary) -> void:
	var r1: Array = GameState.fixtures.filter(func(f): return f["comp"] == "cup" and int(f["round"]) == 1)
	if r1.is_empty():
		return
	_add(have, "cupdraw:1", GameState.season_start,
		"Cup draw: %s" % Season.cup_round_name(1),
		"The %s draw for the Indigo Cup has been made." % Season.cup_round_name(1),
		{"cat": "cup", "sender": "Indigo League Cup Committee", "round": 1})


# ------------------------------------------------------------- board maths

## Expected league position = club's rank by reputation (1..N).
func expected_position() -> int:
	var clubs: Array = GameState.world["clubs"]
	var mine: Dictionary = GameState.player_club()
	var better := 0
	for c in clubs:
		if c["id"] == mine["id"]:
			continue
		if int(c["reputation"]) > int(mine["reputation"]) or \
			(int(c["reputation"]) == int(mine["reputation"]) and str(c["id"]) < str(mine["id"])):
			better += 1
	return better + 1


func league_expectation_text() -> String:
	var e := expected_position()
	if e <= 2:
		return "challenge for the league title"
	if e <= 5:
		return "push for a top-four finish"
	if e <= 8:
		return "finish in the top half of the table"
	if e <= 12:
		return "secure a comfortable mid-table finish"
	return "stay well clear of the bottom places"


func cup_expectation_text() -> String:
	var e := expected_position()
	if e <= 4:
		return "reach the Indigo Cup Final"
	if e <= 8:
		return "reach the Indigo Cup Semi-Final"
	return "reach the Indigo Cup Quarter-Final"


## Last n player results, newest first: [{f, won, us, them, opp_name, comp}]
func recent_results(n: int = 5) -> Array:
	var played: Array = GameState.player_fixtures().filter(func(f): return f["played"])
	played.reverse()
	var out: Array = []
	for f in played.slice(0, n):
		var we_home: bool = GameState.is_player_club(f["home"])
		var us: int = f["score_home"] if we_home else f["score_away"]
		var them: int = f["score_away"] if we_home else f["score_home"]
		out.append({"f": f, "won": us > them, "us": us, "them": them,
			"opp": GameState.club(f["away"] if we_home else f["home"])["name"], "comp": f["comp"]})
	return out


## Cup status: {alive, round, text}
func cup_status() -> Dictionary:
	var pid: String = GameState.world["meta"]["player_club_id"]
	var ours: Array = GameState.fixtures.filter(func(f):
		return f["comp"] == "cup" and (f["home"] == pid or f["away"] == pid))
	if ours.is_empty():
		return {"alive": false, "round": 0, "text": "Not entered"}
	var last: Dictionary = ours.back()
	var rnd := int(last["round"])
	if not last["played"]:
		return {"alive": true, "round": rnd, "text": "In the %s (tie on %s)" % [Season.cup_round_name(rnd), Season.pretty_date(last["date"])]}
	var we_home: bool = GameState.is_player_club(last["home"])
	var won: bool = (last["score_home"] > last["score_away"]) == we_home
	if won:
		if rnd >= 4:
			return {"alive": false, "round": rnd, "text": "INDIGO CUP WINNERS"}
		return {"alive": true, "round": rnd + 1, "text": "Through to the %s" % Season.cup_round_name(rnd + 1)}
	return {"alive": false, "round": rnd, "text": "Eliminated in the %s" % Season.cup_round_name(rnd)}


## Board confidence 0..100 + descriptor, computed from results vs expectations.
func board_confidence() -> Dictionary:
	var pos := GameState.player_table_position()
	var e := expected_position()
	var row := _player_table_row()
	var played := int(row.get("played", 0))
	var score := 62.0
	if played > 0:
		# position component ramps in as the sample grows (fully by 6 matches)
		var weight := minf(played / 6.0, 1.0)
		score = 62.0 + (e - pos) * 4.0 * weight
		var form := recent_results(5)
		for r in form:
			score += 3.0 if r["won"] else -2.5
	var cs := cup_status()
	if cs["alive"]:
		score += 2.0 + cs["round"]
	elif cs["round"] >= 1 and cs["text"].begins_with("Eliminated"):
		score -= (5.0 - cs["round"])
	score = clampf(score, 4.0, 98.0)
	var word := "Satisfied"
	var col: Color = ThemeBuilder.COL_TEXT
	if score >= 80:
		word = "Delighted"
		col = ThemeBuilder.COL_GOOD
	elif score >= 65:
		word = "Pleased"
		col = Color("8fd98a")
	elif score >= 50:
		word = "Satisfied"
		col = ThemeBuilder.COL_TEXT
	elif score >= 38:
		word = "Concerned"
		col = ThemeBuilder.COL_WARN
	elif score >= 25:
		word = "Worried"
		col = Color("e08a50")
	else:
		word = "Insecure"
		col = ThemeBuilder.COL_BAD
	var statement: String
	if played == 0:
		statement = "The board is content to give you time to settle in before judging results."
	elif pos <= e - 3:
		statement = "The board is thrilled that the team is far exceeding its league expectations."
	elif pos <= e:
		statement = "The board notes with approval that results are on course for its stated aims."
	elif pos <= e + 3:
		statement = "The board expects an improvement on the current league position before long."
	else:
		statement = "The board is alarmed by results falling well short of what was demanded."
	return {"score": score, "word": word, "color": col, "pos": pos, "expected": e,
		"played": played, "statement": statement}


func _player_table_row() -> Dictionary:
	for r in GameState.league_table():
		if GameState.is_player_club(r["club_id"]):
			return r
	return {}


# ------------------------------------------------------------- finances

func finance_summary() -> Dictionary:
	_load_initial_finances()
	var pc: Dictionary = GameState.player_club()
	var balance := int(pc["finances"]["balance"])
	var budget := int(pc["finances"]["wage_budget"])
	var bill := 0
	var earners: Array = []
	for inst in pc["squad"]:
		var sal := int(inst["contract"]["salary"])
		bill += sal
		earners.append({"name": display_name(inst), "species": inst["species"],
			"salary": sal, "expiry": inst["contract"]["expiry"], "level": int(inst["level"])})
	earners.sort_custom(func(a, b): return a["salary"] > b["salary"])
	var initial := int(_initial_finances.get(pc["id"], balance))
	# net transfer spend from the market's completed-deals ledger (the balance
	# itself also moves with wages/gates/etc., so start-minus-now is NOT it)
	var spend := 0
	var mkt := market()
	if mkt != null:
		var us := str(pc["name"])
		for d in mkt.deals:
			var fee := int(d.get("fee", 0))
			if str(d.get("to", "")) == us:
				spend += fee
			elif str(d.get("from", "")) == us:
				spend -= fee
	var avg_f := 0.0
	for c in GameState.world["clubs"]:
		avg_f += int(c["finances"]["balance"])
	var avg := int(avg_f / GameState.world["clubs"].size())
	var max_bal := 0
	for c in GameState.world["clubs"]:
		max_bal = maxi(max_bal, int(c["finances"]["balance"]))
	return {"balance": balance, "wage_budget": budget, "wage_bill": bill,
		"earners": earners, "initial_balance": initial,
		"transfer_spend": spend, "league_avg_balance": avg,
		"league_max_balance": max_bal, "squad_size": pc["squad"].size()}


func _load_initial_finances() -> void:
	if not _initial_finances.is_empty():
		return
	var f := FileAccess.open("res://shared/data/world.json", FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	for c in data["clubs"]:
		_initial_finances[c["id"]] = int(c["finances"]["balance"])


# ------------------------------------------------------------- helpers

func assistant_name() -> String:
	var staff: Array = GameState.player_club().get("staff", [])
	for s in staff:
		if s["role"] == "coach":
			return "%s (Assistant)" % s["name"]
	return "Assistant Manager"


func scout_name() -> String:
	var staff: Array = GameState.player_club().get("staff", [])
	var best := {}
	var best_j := -1
	for s in staff:
		if s["role"] == "scout":
			return "%s (Scout)" % s["name"]
		var j := int(s["ratings"].get("judging_potential", 0))
		if j > best_j:
			best_j = j
			best = s
	if not best.is_empty():
		return "%s (Scout)" % best["name"]
	return "Chief Scout"


func display_name(inst: Dictionary) -> String:
	var nick = inst.get("nickname")
	if nick != null and str(nick) != "":
		return str(nick)
	return str(inst.get("species", "?"))


func money(v: int) -> String:
	var cur: String = GameState.world["meta"].get("currency", "P$")
	var neg := v < 0
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	out = s + out
	return "%s%s%s" % ["-" if neg else "", cur, out]


static func _days_between(a: String, b: String) -> int:
	# both ISO; small helper for scheduling
	var pa := a.split("-")
	var pb := b.split("-")
	var ua := Time.get_unix_time_from_datetime_dict({"year": int(pa[0]), "month": int(pa[1]), "day": int(pa[2]), "hour": 12, "minute": 0, "second": 0})
	var ub := Time.get_unix_time_from_datetime_dict({"year": int(pb[0]), "month": int(pb[1]), "day": int(pb[2]), "hour": 12, "minute": 0, "second": 0})
	return int((ub - ua) / 86400)
