extends RefCounted
## Inbox piece: the BOARD ROOM — a two-way "Request from the Board" system.
##
## The manager submits a request (wage budget increase / transfer funds
## injection / scouting network investment). The board deliberates for a few
## days, weighing its live confidence score, the club's real cash position,
## the size of the ask and how often the manager has come knocking lately —
## then answers with an inbox message. A grant MUTATES the club's real
## finances in GameState.world (the same ledger the transfers market and the
## top-bar balance read), so the money is genuinely spendable afterwards.
##
## Deliberation is deterministic (career_seed + request id), so the same
## career always produces the same boardroom behaviour. State persists to
## user://inbox_board.json (same pattern as the transfers market's state
## file) and resets automatically on a new career.

const STATE_PATH := "user://inbox_board.json"

## Request kinds. Amounts are computed live from the club's actual numbers.
const KIND_WAGE := "wage"          # raise finances.wage_budget
const KIND_FUNDS := "funds"        # inject cash into finances.balance
const KIND_SCOUT := "scouting"     # spend balance -> +knowledge on every prospect

const SCOUT_KNOWLEDGE_GAIN := 15   # scouted_pct points added to each prospect

var news: RefCounted               # news_gen.gd (confidence / finance maths)
var economy: RefCounted            # economy.gd (operating cash flow) — set by screen.gd

var requests: Array = []           # [{id, kind, amount, label, date, decide_on,
                                   #   status: pending|granted|partial|denied,
                                   #   granted, reasons:[..], score, confidence,
                                   #   before, after, decided_on}]
var ledger: Array = []             # [{date, text, amount, kind}] board-caused cash moves
var _next_id := 1


func _init(news_gen: RefCounted) -> void:
	news = news_gen
	_load_state()


## A record dated after "today" can only mean the career was restarted
## (GameState signals connect poorly to a screen-lifetime RefCounted, so we
## detect restarts from the data itself). Wipe and start clean.
func _guard_career_restart() -> void:
	var stale := requests.any(func(r): return str(r["date"]) > GameState.current_date) \
		or ledger.any(func(e): return str(e["date"]) > GameState.current_date)
	if stale:
		requests = []
		ledger = []
		_next_id = 1
		save_state()


# ------------------------------------------------------------------ persistence

func save_state() -> void:
	var f := FileAccess.open(STATE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("board_room: cannot write %s" % STATE_PATH)
		return
	f.store_string(JSON.stringify({
		"version": 1,
		"career_seed": GameState.career_seed,
		"next_id": _next_id,
		"requests": requests,
		"ledger": ledger,
	}))


func _load_state() -> void:
	if not FileAccess.file_exists(STATE_PATH):
		return
	var f := FileAccess.open(STATE_PATH, FileAccess.READ)
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) != 1:
		return
	if int(data.get("career_seed", 0)) != GameState.career_seed:
		return  # stale career — start clean
	requests = data.get("requests", [])
	ledger = data.get("ledger", [])
	_next_id = int(data.get("next_id", 1))
	_guard_career_restart()


# ------------------------------------------------------------------ queries

func request_by_id(id: int) -> Dictionary:
	for r in requests:
		if int(r["id"]) == id:
			return r
	return {}


func pending_request() -> Dictionary:
	for r in requests:
		if str(r["status"]) == "pending":
			return r
	return {}


func resolved_requests() -> Array:
	var out: Array = requests.filter(func(r): return str(r["status"]) != "pending")
	out.sort_custom(func(a, b): return str(a.get("decided_on", "")) > str(b.get("decided_on", "")))
	return out


func recent_request_count(days: int) -> int:
	var n := 0
	for r in requests:
		if Season.days_between(str(r["date"]), GameState.current_date) <= days:
			n += 1
	return n


func kind_title(kind: String) -> String:
	match kind:
		KIND_WAGE: return "Wage budget increase"
		KIND_FUNDS: return "Transfer funds injection"
		KIND_SCOUT: return "Scouting network investment"
	return kind


## The live menu of things the manager can ask for, with amounts computed
## from the club's REAL numbers and a dry-run receptiveness hint.
func request_defs() -> Array:
	var pc: Dictionary = GameState.player_club()
	var budget := int(pc["finances"]["wage_budget"])
	var rep := int(pc["reputation"])
	var defs: Array = []

	var w_mod := _round_money(int(budget * 0.10), 100)
	var w_amb := _round_money(int(budget * 0.25), 100)
	defs.append({"kind": KIND_WAGE, "title": kind_title(KIND_WAGE),
		"desc": "Raise the monthly wage budget so we can afford better contracts.",
		"options": [{"label": "+%s /mo" % news.money(w_mod), "amount": w_mod},
			{"label": "+%s /mo" % news.money(w_amb), "amount": w_amb}]})

	var f_mod := _round_money(rep * 9000, 1000)
	var f_amb := _round_money(rep * 22000, 1000)
	defs.append({"kind": KIND_FUNDS, "title": kind_title(KIND_FUNDS),
		"desc": "Ask the owners to put their own money into the transfer kitty.",
		"options": [{"label": news.money(f_mod), "amount": f_mod},
			{"label": news.money(f_amb), "amount": f_amb}]})

	var s_cost := _round_money(rep * 5000, 1000)
	defs.append({"kind": KIND_SCOUT, "title": kind_title(KIND_SCOUT),
		"desc": "Spend %s of club funds: +%d%% knowledge on all %d prospect files." %
			[news.money(s_cost), SCOUT_KNOWLEDGE_GAIN, GameState.prospects().size()],
		"options": [{"label": "Invest %s" % news.money(s_cost), "amount": s_cost}]})

	for d in defs:
		for o in d["options"]:
			var a := _assess(str(d["kind"]), int(o["amount"]))
			o["hint"] = _hint_for_score(float(a["score"]), a["reasons"])
	return defs


func _hint_for_score(score: float, reasons: Array) -> Dictionary:
	# dry-run (no roll) receptiveness — FM-style "how will this land?"
	for rs in reasons:
		if str(rs).begins_with("HARD:"):
			return {"word": "will refuse", "color": ThemeBuilder.COL_BAD}
	if score >= 62.0:
		return {"word": "receptive", "color": ThemeBuilder.COL_GOOD}
	if score >= 47.0:
		return {"word": "could go either way", "color": ThemeBuilder.COL_WARN}
	return {"word": "likely to refuse", "color": ThemeBuilder.COL_BAD}


# ------------------------------------------------------------------ submit

## Submit a request. Returns "" on success or an error string.
func submit(kind: String, amount: int) -> String:
	if not pending_request().is_empty():
		return "The board is already considering a request — wait for its answer."
	if amount <= 0:
		return "Nothing requested."
	var pc: Dictionary = GameState.player_club()
	if kind == KIND_SCOUT and int(pc["finances"]["balance"]) < amount:
		return "The club cannot cover a %s investment right now." % news.money(amount)
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.career_seed + _next_id * 7919 + 3
	var decide_on := Season.date_add(GameState.current_date, 2 + rng.randi_range(0, 2))
	var r := {
		"id": _next_id, "kind": kind, "amount": amount,
		"label": kind_title(kind), "date": GameState.current_date,
		"decide_on": decide_on, "status": "pending",
		"granted": 0, "reasons": [], "score": 0.0, "confidence": 0.0,
		"before": 0, "after": 0, "decided_on": "",
	}
	_next_id += 1
	requests.push_front(r)
	save_state()

	GameState.add_inbox_message(GameState.current_date,
		"Board request submitted: %s" % kind_title(kind).to_lower(),
		"Your request has been tabled for the board's next sitting. A decision is expected by %s." %
			Season.pretty_date(decide_on))
	var m: Dictionary = GameState.inbox[0]
	m["cat"] = "board"
	m["uid"] = "boardreq:%d" % int(r["id"])
	m["req_id"] = int(r["id"])
	m["sender"] = "%s Club Secretary" % pc["name"]
	return ""


# ------------------------------------------------------------------ resolution

## Called on every date change / screen load: answer any request whose
## deliberation window has passed. Grants mutate the club's REAL finances.
func tick() -> void:
	_guard_career_restart()
	var changed := false
	for r in requests:
		if str(r["status"]) == "pending" and str(r["decide_on"]) <= GameState.current_date:
			_resolve(r)
			changed = true
	if changed:
		save_state()
		GameState.save_game()


func _resolve(r: Dictionary) -> void:
	var kind := str(r["kind"])
	var amount := int(r["amount"])
	var a := _assess(kind, amount)
	var score := float(a["score"])
	var reasons: Array = a["reasons"]

	# deterministic boardroom mood on the day
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.career_seed + int(r["id"]) * 7919
	score += rng.randf_range(-7.0, 7.0)

	var hard_no := reasons.any(func(x): return str(x).begins_with("HARD:"))
	var status := "denied"
	var granted := 0
	if not hard_no:
		if score >= 60.0:
			status = "granted"
			granted = amount
		elif score >= 47.0 and kind != KIND_SCOUT:
			status = "partial"
			granted = _round_money(int(amount * rng.randf_range(0.5, 0.62)),
				100 if kind == KIND_WAGE else 1000)
		elif score >= 52.0 and kind == KIND_SCOUT:
			status = "granted"
			granted = amount

	r["status"] = status
	r["granted"] = granted
	r["score"] = score
	r["confidence"] = float(news.board_confidence()["score"])
	r["reasons"] = reasons.map(func(x): return str(x).trim_prefix("HARD:"))
	r["decided_on"] = GameState.current_date
	_apply_grant(r)
	_send_decision_mail(r)


## The actual mutation: this is the money the rest of the game sees.
func _apply_grant(r: Dictionary) -> void:
	var pc: Dictionary = GameState.player_club()
	var fin: Dictionary = pc["finances"]
	var granted := int(r["granted"])
	match str(r["kind"]):
		KIND_WAGE:
			r["before"] = int(fin["wage_budget"])
			if granted > 0:
				fin["wage_budget"] = int(fin["wage_budget"]) + granted
				ledger.push_front({"date": GameState.current_date, "amount": 0,
					"kind": "wage_budget",
					"text": "Board raised wage budget by %s /mo" % news.money(granted)})
			r["after"] = int(fin["wage_budget"])
		KIND_FUNDS:
			r["before"] = int(fin["balance"])
			if granted > 0:
				fin["balance"] = int(fin["balance"]) + granted
				# the injection is earmarked for squad building: it raises the
				# board's transfer budget by the same amount
				fin["transfer_budget"] = int(fin.get("transfer_budget", 0)) + granted
				ledger.push_front({"date": GameState.current_date, "amount": granted,
					"kind": "injection",
					"text": "Board funds injection (transfer budget +%s)" % news.money(granted)})
			r["after"] = int(fin["balance"])
		KIND_SCOUT:
			r["before"] = int(fin["balance"])
			if granted > 0:
				fin["balance"] = int(fin["balance"]) - granted
				var touched := 0
				for p in GameState.prospects():
					p["scouted_pct"] = mini(100, int(p.get("scouted_pct", 0)) + SCOUT_KNOWLEDGE_GAIN)
					touched += 1
				r["prospects_updated"] = touched
				ledger.push_front({"date": GameState.current_date, "amount": -granted,
					"kind": "scouting",
					"text": "Scouting network investment (%d prospect files +%d%%)" % [touched, SCOUT_KNOWLEDGE_GAIN]})
			r["after"] = int(fin["balance"])


func _send_decision_mail(r: Dictionary) -> void:
	var pc: Dictionary = GameState.player_club()
	var status := str(r["status"])
	var title: String
	var body: String
	match status:
		"granted":
			title = "Board approves your request: %s" % kind_title(str(r["kind"])).to_lower()
			body = "The board has agreed to your request in full."
		"partial":
			title = "Board partially grants your request: %s" % kind_title(str(r["kind"])).to_lower()
			body = "The board cannot stretch to the full amount but has made a counter-offer."
		_:
			title = "Board rejects your request: %s" % kind_title(str(r["kind"])).to_lower()
			body = "The board has turned down your request."
	GameState.add_inbox_message(str(r["decided_on"]), title, body)
	var m: Dictionary = GameState.inbox[0]
	m["cat"] = "board"
	m["uid"] = "boarddec:%d" % int(r["id"])
	m["req_id"] = int(r["id"])
	m["sender"] = "%s Board of Directors" % pc["name"]
	m["urgent"] = true


# ------------------------------------------------------------------ the model
# How the board decides. Returns {"score": float, "reasons": [String]}.
# Reasons prefixed "HARD:" are outright vetoes regardless of score.

func _assess(kind: String, amount: int) -> Dictionary:
	var conf: Dictionary = news.board_confidence()
	var fin: Dictionary = news.finance_summary()
	var pc: Dictionary = GameState.player_club()
	var score := float(conf["score"])
	var reasons: Array = []
	reasons.append("Board confidence stands at %d%% (%s)." % [int(conf["score"]), str(conf["word"]).to_lower()])

	# request fatigue — boards tire of managers who keep coming back
	var recent := 0
	var denied_recent := 0
	for r in requests:
		if str(r["status"]) == "pending":
			continue
		var age := Season.days_between(str(r["date"]), GameState.current_date)
		if age <= 60:
			recent += 1
		if str(r["status"]) == "denied" and age <= 90:
			denied_recent += 1
	if recent > 0:
		score -= recent * 10.0
		reasons.append("You have made %d request%s in the last 60 days — patience is wearing thin." %
			[recent, "" if recent == 1 else "s"])
	if denied_recent > 0:
		score -= denied_recent * 6.0
		reasons.append("A recently refused request still colours the discussion.")

	var balance := int(fin["balance"])
	var avg := int(fin["league_avg_balance"])
	match kind:
		KIND_WAGE:
			var usage := float(fin["wage_bill"]) / maxf(1.0, float(fin["wage_budget"]))
			if usage >= 0.92:
				score += 14.0
				reasons.append("The wage bill (%d%% of budget) presses hard against the ceiling — a rise is justifiable." % int(usage * 100))
			elif usage >= 0.75:
				score += 4.0
				reasons.append("Wage spending (%d%% of budget) leaves only modest headroom." % int(usage * 100))
			else:
				score -= 22.0
				reasons.append("Only %d%% of the existing wage budget is being used — the board sees no need for more." % int(usage * 100))
			var ar := float(amount) / maxf(1.0, float(fin["wage_budget"]))
			if ar > 0.12:
				score -= (ar - 0.12) * 90.0
				reasons.append("A %d%% rise is an aggressive ask." % int(ar * 100))
			if balance < int(avg * 0.6):
				score -= 10.0
				reasons.append("The club's weak cash position argues against higher fixed commitments.")
		KIND_FUNDS:
			var cap := int(pc["reputation"]) * 25000
			if amount > cap:
				reasons.append("HARD:An injection of %s is simply beyond the owners' means (they could stretch to about %s)." %
					[news.money(amount), news.money(cap)])
			if balance < 0:
				score += 20.0
				reasons.append("The club is in the red — the owners accept the need to act.")
			elif balance < int(avg * 0.75):
				score += 10.0
				reasons.append("Reserves sit below the league average of %s." % news.money(avg))
			elif balance > int(avg * 1.3):
				score -= 18.0
				reasons.append("With %s in the bank the owners see no case for reaching into their own pockets." % news.money(balance))
			else:
				reasons.append("The bank balance of %s is broadly in line with the league." % news.money(balance))
			score -= (float(amount) / maxf(1.0, float(cap))) * 18.0
		KIND_SCOUT:
			if balance - amount >= int(fin["wage_bill"]) * 4:
				score += 8.0
				reasons.append("The investment is comfortably affordable from club funds.")
			else:
				score -= 25.0
				reasons.append("Spending %s would cut dangerously into working capital." % news.money(amount))
	return {"score": score, "reasons": reasons}


# ------------------------------------------------------------------ ledger

## Season income & expenditure: operating cash flow (gates, prize money,
## payroll, sponsorship... from economy.gd) + board-caused cash moves + every
## completed transfer deal involving our club from the market's deals ledger.
func ledger_rows(limit: int = 12) -> Array:
	var rows: Array = []
	for e in ledger:
		rows.append({"date": str(e["date"]), "text": str(e["text"]),
			"amount": int(e["amount"]), "kind": str(e["kind"])})
	if economy != null:
		for e in economy.rows():
			rows.append({"date": str(e["date"]), "text": str(e["text"]),
				"amount": int(e["amount"]), "kind": str(e["kind"])})
	var mkt: RefCounted = news.market()
	var us := str(GameState.player_club()["name"])
	if mkt != null:
		for d in mkt.deals:
			var fee := int(d.get("fee", 0))
			if fee <= 0:
				continue
			if str(d.get("from", "")) == us:
				rows.append({"date": str(d["date"]), "amount": fee, "kind": "sale",
					"text": "Sold %s to %s" % [str(d["name"]), str(d["to"])]})
			elif str(d.get("to", "")) == us:
				rows.append({"date": str(d["date"]), "amount": -fee, "kind": "signing",
					"text": "Signed %s from %s" % [str(d["name"]), str(d["from"])]})
	rows.sort_custom(func(a, b): return str(a["date"]) > str(b["date"]))
	return rows.slice(0, limit)


func ledger_net() -> int:
	var net := 0
	for r in ledger_rows(999):
		net += int(r["amount"])
	return net


func _round_money(v: int, step: int) -> int:
	return maxi(step, int(round(float(v) / step)) * step)
