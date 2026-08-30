extends RefCounted
## TransferMarket — persistent transfer/scouting service for the transfers piece.
## Singleton via static instance(); survives screen navigation (screens are freed
## by the shell on navigate). Drives daily market activity from GameState.date_changed
## and persists its own state to user://transfers.json (world mutations — squads,
## finances — live inside GameState.world and ride along with the normal save).
##
## Deals are STRUCTURED, FM-style. A fee offer is a package:
##   {upfront, inst_amount, inst_years, sell_on}   (sell_on = % of next sale fee)
## A loan offer carries {wage_split, option_fee}. Personal terms are a contract:
##   {wage, years, bonus, status}  (status: Star battler / First team / Rotation / Development)
## The AI values every component differently: cash-poor sellers discount deferred
## money hard, sell-on clauses are worth more on young/high-potential targets,
## fringe battlers are loanable while key ones are not, and players trade weekly
## wage off against contract length, signing bonus and promised squad status.

signal market_updated

const STATE_PATH := "user://transfers.json"
const SELF_PATH := "res://screens/transfers/market.gd"

const SQUAD_STATUSES := ["Star battler", "First team", "Rotation", "Development"]
# How attractive each promised role makes a contract (multiplier on perceived value).
const STATUS_APPEAL := {"Star battler": 1.06, "First team": 1.0, "Rotation": 0.94, "Development": 0.90}

static var _inst: RefCounted = null


static func instance() -> RefCounted:
	if _inst == null:
		_inst = (load(SELF_PATH) as GDScript).new()
	return _inst


# ------------------------------------------------------------------ state

var knowledge: Dictionary = {}      # uid -> float 0..100 scouting knowledge
var assignments: Array = []         # [{scout, kind:"target"|"focus", uid, focus_type, days_left, days_total, started}]
var reports: Dictionary = {}        # uid -> report dict
var offers_out: Array = []          # our bids / loan offers / contract offers (structured)
var offers_in: Array = []           # AI bids for our squad (structured)
var deals: Array = []               # completed deals, newest first
var payments: Array = []            # scheduled installments [{due, amount, club_id, dir:"out"|"in", name}]
var last_tick: String = ""
var last_window_key: String = "closed"  # open-date of the window we last saw open ("" = between windows)
var _next_id: int = 1

# Terminal negotiation stages (an offer in one of these is dead).
const DEAD_STAGES := ["completed", "rejected", "withdrawn", "collapsed", "hijacked"]


func _init() -> void:
	GameState.date_changed.connect(_on_date_changed)
	GameState.career_started.connect(_on_career_started)
	_load_state()


# ------------------------------------------------------------------ persistence

func save_state() -> void:
	var data := {
		"version": 3,
		"career_seed": GameState.career_seed,
		"as_of": GameState.current_date,
		"knowledge": knowledge,
		"assignments": assignments,
		"reports": reports,
		"offers_out": offers_out,
		"offers_in": offers_in,
		"deals": deals,
		"payments": payments,
		"last_tick": last_tick,
		"last_window_key": last_window_key,
		"next_id": _next_id,
	}
	var f := FileAccess.open(STATE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))


func _load_state() -> void:
	_reset_state()
	if not FileAccess.file_exists(STATE_PATH):
		return
	var f := FileAccess.open(STATE_PATH, FileAccess.READ)
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data == null or typeof(data) != TYPE_DICTIONARY or not (int(data.get("version", 0)) in [1, 2, 3]):
		return
	# Reject state from a different / newer career (new career resets the calendar).
	if int(data.get("career_seed", -1)) != GameState.career_seed:
		return
	if String(data.get("as_of", "")) > GameState.current_date:
		return
	knowledge = data.get("knowledge", {})
	assignments = data.get("assignments", [])
	reports = data.get("reports", {})
	offers_out = data.get("offers_out", [])
	offers_in = data.get("offers_in", [])
	deals = data.get("deals", [])
	payments = data.get("payments", [])
	last_tick = String(data.get("last_tick", ""))
	last_window_key = String(data.get("last_window_key", "closed"))
	_next_id = int(data.get("next_id", 1))
	if int(data.get("version", 0)) == 1:
		_migrate_v1_offers()


func _migrate_v1_offers() -> void:
	# v1 offers were scalar {bid, ask, wage_offer, wage_demand}; lift them into packages.
	for o in offers_out:
		if not o.has("package"):
			o["package"] = {"upfront": int(o.get("bid", 0)), "inst_amount": 0, "inst_years": 2, "sell_on": 0}
		if not o.has("contract"):
			o["contract"] = {"wage": int(o.get("wage_offer", 0)), "years": 3, "bonus": 0, "status": "First team"}
		if not o.has("ask_package"):
			var ask := int(o.get("ask", 0))
			o["ask_package"] = {} if ask <= 0 else {"upfront": ask, "inst_amount": 0, "inst_years": 2, "sell_on": 0}
		o["alt_package"] = o.get("alt_package", {})
		o["contract_demand"] = o.get("contract_demand", {})
		o["loan_terms"] = o.get("loan_terms", {})
		o["loan_ask"] = o.get("loan_ask", {})
	for o in offers_in:
		if not o.has("package"):
			o["package"] = {"upfront": int(o.get("bid", 0)), "inst_amount": 0, "inst_years": 2, "sell_on": 0}
		o["ask_sell_on"] = o.get("ask_sell_on", 0)


func _reset_state() -> void:
	knowledge = {}
	assignments = []
	reports = {}
	offers_out = []
	offers_in = []
	deals = []
	payments = []
	last_tick = ""
	last_window_key = "closed"
	_next_id = 1


func _on_career_started() -> void:
	_load_state()
	market_updated.emit()


# ------------------------------------------------------------------ world queries

func find_target(uid: String) -> Dictionary:
	## Returns {inst, club_id ("" if unattached), pool: "club"|"fa"|"prospect"|"mine"} or {}.
	for c in GameState.world["clubs"]:
		for inst in c["squad"]:
			if inst["uid"] == uid:
				var pool := "mine" if GameState.is_player_club(c["id"]) else "club"
				return {"inst": inst, "club_id": c["id"], "pool": pool}
	for inst in GameState.world["free_agents"]:
		if inst["uid"] == uid:
			return {"inst": inst, "club_id": "", "pool": "fa"}
	for inst in GameState.world["prospects"]:
		if inst["uid"] == uid:
			return {"inst": inst, "club_id": "", "pool": "prospect"}
	return {}


func all_targets() -> Array:
	## Everything on the market: other clubs' squads + free agents + prospects.
	var out: Array = []
	for c in GameState.world["clubs"]:
		if GameState.is_player_club(c["id"]):
			continue
		for inst in c["squad"]:
			out.append({"inst": inst, "club_id": c["id"], "pool": "club"})
	for inst in GameState.world["free_agents"]:
		out.append({"inst": inst, "club_id": "", "pool": "fa"})
	for inst in GameState.world["prospects"]:
		out.append({"inst": inst, "club_id": "", "pool": "prospect"})
	return out


func display_name(inst: Dictionary) -> String:
	var nick: Variant = inst.get("nickname")
	if nick != null and String(nick) != "":
		return "%s (%s)" % [String(nick), inst["species"]]
	return String(inst["species"])


func exact_stats(inst: Dictionary) -> Dictionary:
	var sp: Dictionary = DataStore.species(int(inst["species_id"]))
	var out := {}
	for k in ["hp", "atk", "def", "spa", "spd", "spe"]:
		out[k] = DataStore.calc_stat(int(sp["base"][k]), int(inst["ivs"][k]), int(inst["level"]), k == "hp")
	return out


func bst(inst: Dictionary) -> int:
	var sp: Dictionary = DataStore.species(int(inst["species_id"]))
	var s := 0
	for k in sp["base"]:
		s += int(sp["base"][k])
	return s


func iv_total(inst: Dictionary) -> int:
	var s := 0
	for k in inst["ivs"]:
		s += int(inst["ivs"][k])
	return s


# ------------------------------------------------------------------ valuation

func value_of(inst: Dictionary) -> int:
	var v := float(bst(inst)) * float(inst["level"]) * 14.0
	v *= 1.0 + (float(iv_total(inst)) - 45.0) / 45.0 * 0.25
	var age_y := float(inst["age_months"]) / 12.0
	if age_y < 3.0:
		v *= 1.25
	elif age_y > 8.0:
		v *= 0.7
	if inst.has("potential"):
		v *= 0.35 + float(inst["potential"]) / 20.0 * 0.9
	return maxi(5000, int(round(v / 1000.0)) * 1000)


func importance_of(inst: Dictionary, club: Dictionary) -> float:
	var levels: Array = club["squad"].map(func(i): return int(i["level"]))
	levels.sort()
	levels.reverse()
	var rank := levels.find(int(inst["level"]))
	var m := 1.0
	if rank >= 0 and rank < 2:
		m = 1.6
	elif rank >= 0 and rank < 4:
		m = 1.35
	elif rank >= 0 and rank < 6:
		m = 1.15
	if club["squad"].size() <= 9:
		m += 0.2
	return m


func ask_price(inst: Dictionary, club_id: String) -> int:
	if club_id == "":
		return 0
	return int(round(value_of(inst) * importance_of(inst, GameState.club(club_id)) / 1000.0)) * 1000


func wage_bill(club: Dictionary) -> int:
	var s := 0
	for inst in club["squad"]:
		var sal := int(inst["contract"]["salary"])
		if inst.has("loan") and GameState.is_player_club(club["id"]):
			s += int(round(float(sal) * float(inst["loan"].get("wage_split", 100)) / 100.0))
		else:
			s += sal
	return s


func wage_room() -> int:
	var pc: Dictionary = GameState.player_club()
	return int(pc["finances"]["wage_budget"]) - wage_bill(pc)


# ------------------------------------------------------------------ transfer windows
# The market has a calendar, FM-style. Two windows a season:
#   Summer window: season start -> start+41 (deadline day)
#   Winter window: 1 Jan -> 31 Jan
# Between windows the market is LOCKED: no club-to-club transfers, no loans,
# no prospect signings — only free agents (out of contract) can be signed.
# Everything the AI does (bids, churn, rival hijacks) heats up toward the
# deadline and stops dead when the window shuts.

func windows() -> Array:
	var ss: String = GameState.season_start
	var yr := int(ss.substr(0, 4))
	return [
		{"name": "Summer window", "open": ss, "close": Season.date_add(ss, 41)},
		{"name": "Winter window", "open": "%d-01-01" % (yr + 1), "close": "%d-01-31" % (yr + 1)},
		{"name": "Summer window", "open": Season.date_add(ss, 364), "close": Season.date_add(ss, 364 + 41)},
	]


func current_window() -> Dictionary:
	for w in windows():
		if String(w["open"]) <= GameState.current_date and GameState.current_date <= String(w["close"]):
			return w
	return {}


func window_open() -> bool:
	return not current_window().is_empty()


func next_window() -> Dictionary:
	for w in windows():
		if String(w["open"]) > GameState.current_date:
			return w
	return windows().back()


func days_to_deadline() -> int:
	## Days until the current window's deadline day (-1 when the market is shut).
	var w := current_window()
	if w.is_empty():
		return -1
	return Season.days_between(GameState.current_date, String(w["close"]))


func days_to_open() -> int:
	return maxi(0, Season.days_between(GameState.current_date, String(next_window()["open"])))


func is_deadline_day() -> bool:
	return days_to_deadline() == 0


func deadline_factor() -> float:
	## Market temperature. 0 = window shut. 1 = mid-window. Ramps through the
	## final fortnight into a deadline-day frenzy — AI bids, AI-AI churn and
	## rival hijack attempts all scale with this.
	var d := days_to_deadline()
	if d < 0:
		return 0.0
	if d == 0:
		return 4.5
	if d <= 2:
		return 3.0
	if d <= 7:
		return 2.0
	if d <= 14:
		return 1.3
	return 1.0


func temperature_label() -> String:
	var f := deadline_factor()
	if f <= 0.0:
		return "frozen"
	if f >= 4.0:
		return "FRENZY"
	if f >= 3.0:
		return "hot"
	if f >= 2.0:
		return "warming"
	if f > 1.0:
		return "stirring"
	return "normal"


func market_locked_reason() -> String:
	## "" while a window is open; otherwise why transfers are blocked.
	if window_open():
		return ""
	var w := next_window()
	return "The transfer window is CLOSED. It reopens %s (%s, %d days). Only free agents can be signed until then." % [
		Season.pretty_date(String(w["open"])), String(w["name"]), days_to_open()]


func _response_delay(salt: int) -> int:
	## Clubs and agents answer in 1-2 days normally, next day in deadline week,
	## and within hours (same day) on deadline day.
	var d := days_to_deadline()
	if d == 0:
		return 0
	if d >= 1 and d <= 3:
		return 1
	return 1 + (salt % 2)


func _respond_now(o: Dictionary) -> void:
	## Deadline-day negotiations resolve same-day: the other party replies at
	## once, so several rounds can happen inside the final day.
	var t := find_target(String(o["uid"]))
	if t.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.career_seed ^ GameState.current_date.hash() ^ (int(o["id"]) * 7919)
	match String(o["stage"]):
		"bid_pending":
			if o["kind"] == "loan":
				_respond_to_loan(o, t, rng)
			else:
				_respond_to_package(o, t, rng)
		"wage_pending":
			_respond_to_contract(o, t, rng)


func _tick_windows() -> void:
	## Fires window open/shut transitions: inbox drama, and at the shut every
	## unfinished negotiation dies on the spot.
	var w := current_window()
	var key := "" if w.is_empty() else String(w["open"])
	if key == last_window_key:
		return
	var old_key := last_window_key
	last_window_key = key
	if key != "":
		GameState.add_inbox_message(GameState.current_date,
			"%s OPEN — deadline day %s" % [String(w["name"]).to_upper(), Season.pretty_date(String(w["close"]))],
			"The %s is open. Club-to-club transfers, loans and prospect signings are live until %s (%d days). The market always heats up toward the deadline — move early or scramble late." % [
				String(w["name"]), Season.pretty_date(String(w["close"])), days_to_deadline()])
	else:
		_close_window(old_key)


func _close_window(old_key: String) -> void:
	var closed_w: Dictionary = {}
	for w in windows():
		if String(w["open"]) == old_key:
			closed_w = w
			break
	# Kill every unfinished market negotiation (free-agent talks survive).
	var died := 0
	for o in offers_out:
		if String(o["stage"]) in DEAD_STAGES or String(o["kind"]) == "fa":
			continue
		o["stage"] = "collapsed"
		o["rival"] = {}
		o["log"].append(_log_line("The window shut before the deal was done."))
		died += 1
		GameState.add_inbox_message(GameState.current_date, "Missed the deadline: %s" % o["name"],
			"The transfer window closed before our deal for %s could be completed. Talks are off until the market reopens." % o["name"])
	for o in offers_in:
		if String(o["stage"]) in ["open", "counter_pending", "agreed"]:
			o["stage"] = "expired"
			o["log"].append(_log_line("Window shut — offer lapsed."))
	if closed_w.is_empty():
		return
	# Window round-up: everything that moved while the market was open.
	var in_window: Array = deals.filter(func(d):
		return String(closed_w["open"]) <= String(d["date"]) and String(d["date"]) <= String(closed_w["close"]))
	var pc_name := String(GameState.player_club()["name"])
	var ours: int = in_window.filter(func(d): return String(d["from"]) == pc_name or String(d["to"]) == pc_name).size()
	var spend := 0
	for d in in_window:
		if String(d["to"]) == pc_name:
			spend += int(d["fee"])
	var nw := next_window()
	GameState.add_inbox_message(GameState.current_date,
		"%s SHUT — %d deals done across the league" % [String(closed_w["name"]).to_upper(), in_window.size()],
		"The %s has closed. League-wide: %d completed deals. Our business: %d deals, %s spent on fees.%s The market reopens %s (%s)." % [
			String(closed_w["name"]), in_window.size(), ours, fmt_money(spend),
			(" %d of our negotiations died at the deadline." % died) if died > 0 else "",
			Season.pretty_date(String(nw["open"])), String(nw["name"])])


# ------------------------------------------------------------------ deal-structure valuation (the AI's brain)

func blank_package(upfront: int = 0) -> Dictionary:
	return {"upfront": upfront, "inst_amount": 0, "inst_years": 2, "sell_on": 0}


func package_total(pkg: Dictionary) -> int:
	## Headline (face) value of a package, ignoring time value and sell-on.
	return int(pkg.get("upfront", 0)) + int(pkg.get("inst_amount", 0))


func cash_pressure(club: Dictionary) -> float:
	## 0 = flush with cash, 0.6 = desperate. Poor clubs want money NOW: they
	## discount installments and sell-on clauses hard.
	return clampf(1.0 - float(club["finances"]["balance"]) / 700000.0, 0.0, 0.6)


func resale_factor(inst: Dictionary) -> float:
	## How much future resale the seller expects — drives sell-on clause value.
	## Young / high-potential targets ≈ 1.0+, veterans ≈ 0.1.
	var age_y := float(inst["age_months"]) / 12.0
	var f := clampf((7.5 - age_y) / 6.0, 0.1, 1.0)
	if inst.has("potential"):
		f = clampf(f + float(inst["potential"]) / 40.0, 0.1, 1.25)
	return f


func installment_discount(years: int, seller: Dictionary) -> float:
	## What £1 of deferred money is worth to this seller.
	return clampf(0.96 - 0.05 * float(years) - cash_pressure(seller) * 0.30, 0.40, 0.90)


func sell_on_unit_value(inst: Dictionary, seller: Dictionary) -> float:
	## Perceived value (to the seller) of ONE percent of sell-on clause.
	return float(value_of(inst)) / 100.0 * resale_factor(inst) * (1.0 - cash_pressure(seller) * 0.5)


func package_value(pkg: Dictionary, inst: Dictionary, seller: Dictionary) -> int:
	## The seller's perceived value of a structured package. Cash counts 1:1;
	## installments and sell-on are discounted per THIS club's situation.
	var v := float(pkg.get("upfront", 0))
	v += float(pkg.get("inst_amount", 0)) * installment_discount(int(pkg.get("inst_years", 2)), seller)
	v += float(pkg.get("sell_on", 0)) * sell_on_unit_value(inst, seller)
	return int(v)


func contract_weekly_equiv(con: Dictionary) -> float:
	## Weekly-wage equivalent of a contract (bonus amortised over the term).
	return float(con.get("wage", 0)) + float(con.get("bonus", 0)) / (float(maxi(1, int(con.get("years", 3)))) * 52.0)


func contract_appeal(con: Dictionary, inst: Dictionary) -> float:
	## The player's perceived value of a contract offer, in weekly-wage units.
	## Longer deals = security (worth more to veterans); a big promised role
	## sweetens the package; signing bonus converts straight into appeal.
	var age_y := float(inst["age_months"]) / 12.0
	var sec_rate := 0.05 if age_y > 8.0 else (0.035 if age_y > 3.0 else 0.022)
	var years := clampi(int(con.get("years", 3)), 1, 4)
	var security := 1.0 + float(years - 1) * sec_rate
	var status := String(con.get("status", "First team"))
	var appeal_mult: float = STATUS_APPEAL.get(status, 1.0)
	return contract_weekly_equiv(con) * security * appeal_mult


func describe_package(pkg: Dictionary) -> String:
	var parts: Array = []
	if int(pkg.get("upfront", 0)) > 0:
		parts.append("%s up front" % fmt_money(int(pkg["upfront"])))
	if int(pkg.get("inst_amount", 0)) > 0:
		parts.append("%s over %d yr%s" % [fmt_money(int(pkg["inst_amount"])), int(pkg.get("inst_years", 2)),
			"" if int(pkg.get("inst_years", 2)) == 1 else "s"])
	if int(pkg.get("sell_on", 0)) > 0:
		parts.append("%d%% sell-on" % int(pkg["sell_on"]))
	if parts.is_empty():
		return "Free"
	return " + ".join(parts)


func describe_loan(lt: Dictionary) -> String:
	var s := "Loan: %d%% wages covered" % int(lt.get("wage_split", 100))
	if int(lt.get("option_fee", 0)) > 0:
		s += ", option to buy %s" % fmt_money(int(lt["option_fee"]))
	return s


func describe_contract(con: Dictionary) -> String:
	var s := "%s/wk · %d yr%s" % [fmt_money(int(con.get("wage", 0))), int(con.get("years", 3)),
		"" if int(con.get("years", 3)) == 1 else "s"]
	if int(con.get("bonus", 0)) > 0:
		s += " · %s signing bonus" % fmt_money(int(con["bonus"]))
	s += " · %s" % String(con.get("status", "First team"))
	return s


func offer_hint(uid: String, pkg: Dictionary) -> String:
	## Coarse negotiator guidance for the offer sheet. Precision scales with
	## scouting knowledge — a barely-known target gives vague advice.
	var t := find_target(uid)
	if t.is_empty() or t["pool"] != "club":
		return ""
	var seller: Dictionary = GameState.club(t["club_id"])
	var pc: Dictionary = GameState.player_club()
	var rep_factor := 1.0 + float(int(seller["reputation"]) - int(pc["reputation"])) * 0.015
	var base := float(ask_price(t["inst"], t["club_id"])) * rep_factor
	var know := knowledge_of(uid)
	if know < 50.0:
		# blurred read on their valuation
		var h := _mask_hash(uid, "hint")
		base *= 0.85 + float(h % 31) / 100.0
	var r := float(package_value(pkg, t["inst"], seller)) / maxf(1.0, base)
	var pre := "" if know >= 50.0 else "(low knowledge — rough read) "
	if r >= 1.02:
		return pre + "Negotiators: this package should be accepted."
	if r >= 0.92:
		return pre + "Negotiators: very close — expect a small counter."
	if r >= 0.68:
		return pre + "Negotiators: short of their valuation — they will counter with structure."
	return pre + "Negotiators: likely to be dismissed outright."


func loan_hint(uid: String) -> String:
	var t := find_target(uid)
	if t.is_empty() or t["pool"] != "club":
		return ""
	var imp := importance_of(t["inst"], GameState.club(t["club_id"]))
	if imp >= 1.5 or GameState.club(t["club_id"])["squad"].size() <= 8:
		return "Negotiators: a key battler — they will NOT loan them out."
	if imp >= 1.3:
		return "Negotiators: first-team regular — a loan needs 100% wages and a big option to buy."
	if imp >= 1.15:
		return "Negotiators: squad member — expect demands for most wages plus an option fee."
	return "Negotiators: fringe battler — a loan with decent wage cover is very gettable."


func contract_hint(uid: String, con: Dictionary, known_demand: int = 0) -> String:
	var t := find_target(uid)
	if t.is_empty():
		return ""
	var inst: Dictionary = t["inst"]
	var demand := known_demand
	var pre := ""
	if demand <= 0:
		demand = int(float(inst["contract"]["salary"]) * 1.15)
		if knowledge_of(uid) < 100.0:
			pre = "(estimated) "
	var appeal := contract_appeal(con, inst)
	if appeal >= float(demand) * 0.99:
		return pre + "Agent: these terms should get it done."
	if appeal >= float(demand) * 0.9:
		return pre + "Agent: close — length, bonus or a bigger promised role could bridge it."
	return pre + "Agent: well short of what they'll sign for."


func committed_installments() -> int:
	var s := 0
	for p in payments:
		if String(p["dir"]) == "out":
			s += int(p["amount"])
	return s


func incoming_installments() -> int:
	var s := 0
	for p in payments:
		if String(p["dir"]) == "in":
			s += int(p["amount"])
	return s


# ------------------------------------------------------------------ knowledge / masking

func knowledge_of(uid: String) -> float:
	var t := find_target(uid)
	if not t.is_empty() and t["pool"] == "mine":
		return 100.0
	if knowledge.has(uid):
		return float(knowledge[uid])
	if not t.is_empty() and t["inst"].has("scouted_pct"):
		return float(t["inst"]["scouted_pct"])
	return 0.0


func _mask_hash(uid: String, key: String) -> int:
	return absi(("%s|%s|%d" % [uid, key, GameState.career_seed]).hash())


func masked_bounds(uid: String, key: String, exact: int) -> Array:
	## FM-style knowledge masking: below full knowledge, a deterministic range.
	var know := knowledge_of(uid)
	if know >= 100.0:
		return [exact, exact]
	var spread := maxi(4, int(round(float(exact) * 0.38 * (1.0 - know / 100.0))) + 2)
	var h := _mask_hash(uid, key)
	var lo := maxi(1, exact - (h % spread) - spread / 2)
	var hi := lo + spread + ((h / 7) % 3)
	if exact > hi:
		hi = exact + ((h / 11) % 3)
	return [lo, hi]


func masked_int(uid: String, key: String, exact: int) -> String:
	var b := masked_bounds(uid, key, exact)
	if b[0] == b[1]:
		return str(exact)
	return "%d-%d" % [b[0], b[1]]


func masked_money(uid: String, key: String, exact: int) -> String:
	var know := knowledge_of(uid)
	if know >= 100.0:
		return fmt_money(exact)
	var frac := 0.45 * (1.0 - know / 100.0) + 0.08
	var h := _mask_hash(uid, key)
	var lo := int(float(exact) * (1.0 - frac * (0.5 + float(h % 50) / 100.0)))
	var hi := int(float(exact) * (1.0 + frac * (0.5 + float((h / 3) % 50) / 100.0)))
	return "%s%s-%s" % [GameState.world["meta"]["currency"], _fmt_short(maxi(1000, lo)), _fmt_short(hi)]


func _fmt_short(v: int) -> String:
	if v >= 1000000:
		return "%.1fM" % (float(v) / 1000000.0)
	if v >= 10000:
		return "%dK" % int(round(float(v) / 1000.0))
	if v >= 1000:
		return "%.1fK" % (float(v) / 1000.0)
	return str(v)


func fmt_money(v: int) -> String:
	var cur: String = GameState.world["meta"]["currency"]
	var a := absi(v)
	if a >= 1000000:
		return "%s%s%.2fM" % [("-" if v < 0 else ""), cur, float(a) / 1000000.0]
	if a >= 1000:
		return "%s%s%.1fK" % [("-" if v < 0 else ""), cur, float(a) / 1000.0]
	return "%s%s%d" % [("-" if v < 0 else ""), cur, a]


func fmt_money_full(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	var n := s.length()
	for i in n:
		out += s[i]
		var left := n - i - 1
		if left > 0 and left % 3 == 0:
			out += ","
	return "%s%s%s" % [("-" if v < 0 else ""), GameState.world["meta"]["currency"], out]


# ------------------------------------------------------------------ scouting

func player_scouts() -> Array:
	## Any staff member with judging ratings can be sent scouting; dedicated
	## scouts are simply better labelled. Player club staff only.
	return GameState.player_club()["staff"].filter(
		func(s): return s["ratings"].has("judging_ability"))


func assignment_for_scout(scout_name: String) -> Dictionary:
	for a in assignments:
		if a["scout"] == scout_name:
			return a
	return {}


func assignment_for_target(uid: String) -> Dictionary:
	for a in assignments:
		if a.get("kind", "") == "target" and a.get("uid", "") == uid:
			return a
	return {}


func scout_days_for(scout: Dictionary) -> int:
	return clampi(13 - int(scout["ratings"]["judging_ability"]) / 2, 4, 12)


func assign_scout_to_target(scout_name: String, uid: String) -> String:
	var scout := _scout_by_name(scout_name)
	if scout.is_empty():
		return "No such scout."
	if not assignment_for_scout(scout_name).is_empty():
		return "%s is already on assignment — recall them first." % scout_name
	var t := find_target(uid)
	if t.is_empty() or t["pool"] == "mine":
		return "Invalid scouting target."
	if knowledge_of(uid) >= 100.0:
		return "%s is already fully scouted." % display_name(t["inst"])
	var days := scout_days_for(scout)
	assignments.append({
		"scout": scout_name, "kind": "target", "uid": uid, "focus_type": "",
		"days_left": days, "days_total": days, "started": GameState.current_date,
	})
	save_state()
	market_updated.emit()
	return ""


func assign_scout_to_focus(scout_name: String, focus_type: String) -> String:
	var scout := _scout_by_name(scout_name)
	if scout.is_empty():
		return "No such scout."
	if not assignment_for_scout(scout_name).is_empty():
		return "%s is already on assignment — recall them first." % scout_name
	assignments.append({
		"scout": scout_name, "kind": "focus", "uid": "", "focus_type": focus_type,
		"days_left": -1, "days_total": -1, "started": GameState.current_date,
	})
	save_state()
	market_updated.emit()
	return ""


func recall_scout(scout_name: String) -> void:
	assignments = assignments.filter(func(a): return a["scout"] != scout_name)
	save_state()
	market_updated.emit()


func _scout_by_name(n: String) -> Dictionary:
	for s in player_scouts():
		if s["name"] == n:
			return s
	return {}


func _tick_scouting(rng: RandomNumberGenerator) -> void:
	var done: Array = []
	for a in assignments:
		if a["kind"] == "target":
			a["days_left"] = int(a["days_left"]) - 1
			if int(a["days_left"]) <= 0:
				var uid: String = a["uid"]
				knowledge[uid] = 100.0
				_generate_report(uid, a["scout"])
				done.append(a)
		else:
			# Region/type focus: build knowledge on matching targets each day.
			var scout := _scout_by_name(a["scout"])
			var ja := 12 if scout.is_empty() else int(scout["ratings"]["judging_ability"])
			var pool := all_targets().filter(func(t):
				return knowledge_of(t["inst"]["uid"]) < 100.0 and _matches_focus(t["inst"], a["focus_type"]))
			pool.sort_custom(func(x, y):
				return knowledge_of(x["inst"]["uid"]) > knowledge_of(y["inst"]["uid"]))
			for i in mini(2, pool.size()):
				var uid2: String = pool[i]["inst"]["uid"]
				var gain := float(ja) * (0.9 + rng.randf() * 0.6)
				knowledge[uid2] = minf(100.0, knowledge_of(uid2) + gain)
				if knowledge[uid2] >= 100.0:
					_generate_report(uid2, a["scout"])
					GameState.add_inbox_message(GameState.current_date,
						"Scouting: report filed on %s" % display_name(pool[i]["inst"]),
						"%s (focus: %s) has completed a full assessment of %s. The report is available in the Transfers > Scouting tab." % [
							a["scout"], a["focus_type"], display_name(pool[i]["inst"])])
	for a in done:
		assignments.erase(a)
		var t := find_target(a["uid"])
		var nm := "the target" if t.is_empty() else display_name(t["inst"])
		GameState.add_inbox_message(GameState.current_date,
			"Scout report ready: %s" % nm,
			"%s has returned with a full report on %s. Exact attributes are now unlocked in Transfers." % [a["scout"], nm])


func _matches_focus(inst: Dictionary, focus_type: String) -> bool:
	if focus_type == "Any":
		return true
	if focus_type == "Prospects":
		return inst.has("potential")
	if focus_type == "Free agents":
		var t := find_target(inst["uid"])
		return not t.is_empty() and t["pool"] == "fa"
	var sp: Dictionary = DataStore.species(int(inst["species_id"]))
	return focus_type in sp["types"]


func _generate_report(uid: String, scout_name: String) -> void:
	var t := find_target(uid)
	if t.is_empty():
		return
	var inst: Dictionary = t["inst"]
	var scout := _scout_by_name(scout_name)
	var ja := 12 if scout.is_empty() else int(scout["ratings"]["judging_ability"])
	var jp := 10 if scout.is_empty() else int(scout["ratings"]["judging_potential"])
	var stats := exact_stats(inst)
	var sp: Dictionary = DataStore.species(int(inst["species_id"]))

	# Ability stars: percentile of level-weighted power vs the whole world.
	var power := float(bst(inst)) * (0.5 + float(inst["level"]) / 60.0) * (1.0 + float(iv_total(inst)) / 300.0)
	var ability := clampf(0.5 + (power - 200.0) / 180.0, 0.5, 5.0)
	# Potential: prospects carry a rating; otherwise infer from age + IVs.
	var pot: float
	if inst.has("potential"):
		pot = clampf(float(inst["potential"]) / 4.0, ability, 5.0)
	else:
		var age_y := float(inst["age_months"]) / 12.0
		pot = clampf(ability + maxf(0.0, (5.0 - age_y)) * 0.35 + (float(iv_total(inst)) - 45.0) / 60.0, 0.5, 5.0)
	# Judging skill blurs the estimate slightly.
	var blur := (20.0 - float(ja)) * 0.02
	ability = clampf(ability + blur * (float(_mask_hash(uid, "ab") % 3) - 1.0), 0.5, 5.0)
	var blur_p := (20.0 - float(jp)) * 0.03
	pot = clampf(pot + blur_p * (float(_mask_hash(uid, "po") % 3) - 1.0), 0.5, 5.0)

	var pros: Array = []
	var cons: Array = []
	var names := {"hp": "HP", "atk": "Attack", "def": "Defense", "spa": "Sp. Attack", "spd": "Sp. Defense", "spe": "Speed"}
	var keys := ["atk", "spa", "spe", "def", "spd", "hp"]
	var ranked := keys.duplicate()
	ranked.sort_custom(func(a, b): return int(stats[a]) > int(stats[b]))
	pros.append("Standout %s (%d) for its level" % [names[ranked[0]], stats[ranked[0]]])
	if int(stats[ranked[1]]) > 60:
		pros.append("Strong secondary %s (%d)" % [names[ranked[1]], stats[ranked[1]]])
	if int(stats["spe"]) >= int(stats[ranked[1]]):
		pros.append("Wins the speed tie in most match-ups")
	if iv_total(inst) >= 60:
		pros.append("Excellent underlying genetics (IV %d/90)" % iv_total(inst))
	if float(inst["age_months"]) / 12.0 < 3.0:
		pros.append("Young — years of development ahead")
	var cats := {}
	for m in inst["moves"]:
		var mv: Dictionary = DataStore.move(m)
		if not mv.is_empty():
			cats[mv["category"]] = true
	if cats.size() >= 2:
		pros.append("Versatile move set (%s)" % ", ".join(inst["moves"]))
	cons.append("Weak %s (%d) is exploitable" % [names[ranked[5]], stats[ranked[5]]])
	if int(stats[ranked[4]]) < 45:
		cons.append("Below-par %s (%d) too" % [names[ranked[4]], stats[ranked[4]]])
	if iv_total(inst) < 35:
		cons.append("Modest genetics (IV %d/90) cap its ceiling" % iv_total(inst))
	if float(inst["age_months"]) / 12.0 > 8.0:
		cons.append("Ageing — resale value will only fall")
	if int(inst["condition"]) < 70:
		cons.append("Arrived at trials in poor condition (%d%%)" % int(inst["condition"]))
	if cats.size() == 1:
		cons.append("One-dimensional move set")

	var verdict: String
	if ability >= 4.0:
		verdict = "Sign at almost any cost — a genuine difference-maker."
	elif ability >= 3.0:
		verdict = "Would strengthen our first team immediately. Recommended."
	elif pot >= 3.5:
		verdict = "Raw today, but the ceiling justifies a development signing."
	elif ability >= 2.0:
		verdict = "Useful squad depth at the right price; do not overpay."
	else:
		verdict = "Not recommended — below the level we need."

	reports[uid] = {
		"uid": uid, "date": GameState.current_date, "scout": scout_name,
		"name": display_name(inst), "species": inst["species"],
		"types": sp["types"], "level": int(inst["level"]),
		"ability_stars": snappedf(ability, 0.5), "potential_stars": snappedf(pot, 0.5),
		"pros": pros, "cons": cons, "verdict": verdict,
	}


# ------------------------------------------------------------------ outgoing offers (buying)

func offer_for_target(uid: String) -> Dictionary:
	for o in offers_out:
		if o["uid"] == uid and not (o["stage"] in DEAD_STAGES):
			return o
	return {}


func make_offer(uid: String, pkg: Dictionary) -> String:
	## Submit a structured permanent-transfer package to the owning club.
	var t := find_target(uid)
	if t.is_empty() or t["pool"] != "club":
		return "That target cannot be bought with a transfer fee."
	if not window_open():
		return market_locked_reason()
	if not offer_for_target(uid).is_empty():
		return "There is already an active offer for this target."
	var err := _validate_package(pkg)
	if err != "":
		return err
	var o := _new_offer(uid, t, "buy")
	o["package"] = _norm_package(pkg)
	o["log"].append(_log_line("Offered %s to %s." % [describe_package(o["package"]), GameState.club(t["club_id"])["name"]]))
	offers_out.append(o)
	if is_deadline_day():
		_respond_now(o)
	save_state()
	market_updated.emit()
	return ""


func make_loan_offer(uid: String, wage_split: int, option_fee: int) -> String:
	var t := find_target(uid)
	if t.is_empty() or t["pool"] != "club":
		return "That target cannot be taken on loan."
	if not window_open():
		return market_locked_reason()
	if not offer_for_target(uid).is_empty():
		return "There is already an active offer for this target."
	wage_split = clampi(wage_split, 0, 100)
	var extra_wage := int(round(float(t["inst"]["contract"]["salary"]) * float(wage_split) / 100.0))
	if extra_wage > wage_room():
		return "Covering %d%% of their wages breaks our wage budget (room: %s/wk)." % [wage_split, fmt_money(wage_room())]
	var o := _new_offer(uid, t, "loan")
	o["loan_terms"] = {"wage_split": wage_split, "option_fee": maxi(0, option_fee)}
	o["log"].append(_log_line("Loan proposed to %s — %s." % [GameState.club(t["club_id"])["short"], describe_loan(o["loan_terms"])]))
	offers_out.append(o)
	if is_deadline_day():
		_respond_now(o)
	save_state()
	market_updated.emit()
	return ""


func _new_offer(uid: String, t: Dictionary, kind: String) -> Dictionary:
	var o := {
		"id": _next_id, "uid": uid, "club_id": t["club_id"], "kind": kind,
		"stage": "bid_pending",
		"package": blank_package(), "ask_package": {}, "alt_package": {},
		"loan_terms": {}, "loan_ask": {},
		"contract": {}, "contract_demand": {}, "rival": {},
		"rounds": 0, "respond_on": Season.date_add(GameState.current_date, _response_delay(_next_id)),
		"name": display_name(t["inst"]),
		"log": [],
	}
	_next_id += 1
	return o


func _validate_package(pkg: Dictionary) -> String:
	var pc: Dictionary = GameState.player_club()
	var up := int(pkg.get("upfront", 0))
	if up > int(pc["finances"]["balance"]):
		return "Up-front fee exceeds our transfer balance (%s)." % fmt_money(int(pc["finances"]["balance"]))
	if package_total(pkg) < 1000 and int(pkg.get("sell_on", 0)) <= 0:
		return "Offer something — minimum package is %s." % fmt_money(1000)
	if int(pkg.get("sell_on", 0)) < 0 or int(pkg.get("sell_on", 0)) > 50:
		return "Sell-on clause must be between 0%% and 50%%."
	return ""


func _norm_package(pkg: Dictionary) -> Dictionary:
	return {
		"upfront": maxi(0, int(pkg.get("upfront", 0))),
		"inst_amount": maxi(0, int(pkg.get("inst_amount", 0))),
		"inst_years": clampi(int(pkg.get("inst_years", 2)), 1, 3),
		"sell_on": clampi(int(pkg.get("sell_on", 0)), 0, 50),
	}


func revise_offer(offer_id: int, pkg: Dictionary) -> String:
	var o := _offer_out(offer_id)
	if o.is_empty() or o["stage"] != "countered" or o["kind"] != "buy":
		return "This offer is not awaiting a revised package."
	if not window_open():
		return market_locked_reason()
	var err := _validate_package(pkg)
	if err != "":
		return err
	var t := find_target(String(o["uid"]))
	if t.is_empty():
		return "Target no longer available."
	var seller: Dictionary = GameState.club(String(o["club_id"]))
	var new_pkg := _norm_package(pkg)
	if package_value(new_pkg, t["inst"], seller) <= package_value(o["package"], t["inst"], seller):
		return "The revised package must improve on the last one (in their eyes)."
	o["package"] = new_pkg
	o["stage"] = "bid_pending"
	o["respond_on"] = Season.date_add(GameState.current_date, _response_delay(int(o["id"])))
	o["log"].append(_log_line("Revised package: %s." % describe_package(new_pkg)))
	if is_deadline_day():
		_respond_now(o)
	save_state()
	market_updated.emit()
	return ""


func revise_loan(offer_id: int, wage_split: int, option_fee: int) -> String:
	var o := _offer_out(offer_id)
	if o.is_empty() or o["stage"] != "countered" or o["kind"] != "loan":
		return "This loan offer is not awaiting revised terms."
	if not window_open():
		return market_locked_reason()
	var t := find_target(String(o["uid"]))
	if t.is_empty():
		return "Target no longer available."
	wage_split = clampi(wage_split, 0, 100)
	var extra_wage := int(round(float(t["inst"]["contract"]["salary"]) * float(wage_split) / 100.0))
	if extra_wage > wage_room():
		return "Covering %d%% of their wages breaks our wage budget." % wage_split
	o["loan_terms"] = {"wage_split": wage_split, "option_fee": maxi(0, option_fee)}
	o["stage"] = "bid_pending"
	o["respond_on"] = Season.date_add(GameState.current_date, mini(1, _response_delay(int(o["id"]))))
	o["log"].append(_log_line("Revised loan terms: %s." % describe_loan(o["loan_terms"])))
	if is_deadline_day():
		_respond_now(o)
	save_state()
	market_updated.emit()
	return ""


func accept_package(offer_id: int, which: String = "ask") -> String:
	## Accept the seller's counter-proposal ("ask") or their structured alternative ("alt").
	var o := _offer_out(offer_id)
	if o.is_empty() or o["stage"] != "countered":
		return "Nothing to accept."
	if not window_open():
		return market_locked_reason()
	if o["kind"] == "loan":
		if o["loan_ask"].is_empty():
			return "No loan terms on the table."
		var t2 := find_target(String(o["uid"]))
		if t2.is_empty():
			return "Target no longer available."
		var split := int(o["loan_ask"].get("wage_split", 100))
		var extra_wage := int(round(float(t2["inst"]["contract"]["salary"]) * float(split) / 100.0))
		if extra_wage > wage_room():
			return "Their demanded wage cover breaks our wage budget."
		o["loan_terms"] = o["loan_ask"].duplicate()
		o["binding"] = true
		o["stage"] = "bid_pending"
		o["respond_on"] = Season.date_add(GameState.current_date, mini(1, _response_delay(int(o["id"]))))
		o["log"].append(_log_line("We accepted their loan terms: %s." % describe_loan(o["loan_terms"])))
		if is_deadline_day():
			_respond_now(o)
		save_state()
		market_updated.emit()
		return ""
	var pkg: Dictionary = o["alt_package"] if which == "alt" else o["ask_package"]
	if pkg.is_empty():
		return "That proposal is not on the table."
	var pc: Dictionary = GameState.player_club()
	if int(pkg.get("upfront", 0)) > int(pc["finances"]["balance"]):
		return "We cannot afford the up-front part of that package (%s)." % fmt_money(int(pkg.get("upfront", 0)))
	o["package"] = pkg.duplicate()
	o["binding"] = true
	o["stage"] = "bid_pending"
	o["respond_on"] = Season.date_add(GameState.current_date, mini(1, _response_delay(int(o["id"]))))
	o["log"].append(_log_line("We accepted their proposal: %s." % describe_package(pkg)))
	if is_deadline_day():
		_respond_now(o)
	save_state()
	market_updated.emit()
	return ""


func offer_contract(offer_id: int, con: Dictionary) -> String:
	## Personal terms: wage + years + signing bonus + squad status.
	var o := _offer_out(offer_id)
	if o.is_empty() or not (o["stage"] in ["fee_agreed", "wage_countered"]):
		return "Contract talks are not open on this deal."
	if String(o["kind"]) in ["buy", "prospect"] and not window_open():
		return market_locked_reason()
	var wage := int(con.get("wage", 0))
	var bonus := int(con.get("bonus", 0))
	if wage > wage_room():
		return "That wage breaks our wage budget (room: %s/wk)." % fmt_money(wage_room())
	var pc: Dictionary = GameState.player_club()
	var cash_needed := bonus + int(o["package"].get("upfront", 0))
	if cash_needed > int(pc["finances"]["balance"]):
		return "Signing bonus plus the up-front fee exceeds our balance."
	if wage < 50:
		return "Offer a serious wage."
	o["contract"] = {
		"wage": wage, "years": clampi(int(con.get("years", 3)), 1, 4),
		"bonus": maxi(0, bonus), "status": String(con.get("status", "First team")),
	}
	o["stage"] = "wage_pending"
	o["respond_on"] = Season.date_add(GameState.current_date, mini(1, _response_delay(int(o["id"]))))
	o["log"].append(_log_line("Contract offered: %s." % describe_contract(o["contract"])))
	if is_deadline_day():
		_respond_now(o)
	save_state()
	market_updated.emit()
	return ""


func withdraw_offer(offer_id: int) -> void:
	var o := _offer_out(offer_id)
	if o.is_empty():
		return
	o["stage"] = "withdrawn"
	o["log"].append(_log_line("Offer withdrawn."))
	save_state()
	market_updated.emit()


func sign_free_agent(uid: String, con: Dictionary) -> String:
	## Free agents / prospects sign on a contract alone (prospects carry a comp fee).
	var t := find_target(uid)
	if t.is_empty() or not (t["pool"] in ["fa", "prospect"]):
		return "Not a free agent."
	if t["pool"] == "prospect" and not window_open():
		return "Prospect signings carry a development fee — window business only. " + market_locked_reason()
	if not offer_for_target(uid).is_empty():
		return "There is already an active offer for this target."
	var fee := 0
	if t["pool"] == "prospect":
		fee = int(round(value_of(t["inst"]) * 0.35 / 1000.0)) * 1000
	var wage := int(con.get("wage", 0))
	var bonus := maxi(0, int(con.get("bonus", 0)))
	if fee + bonus > int(GameState.player_club()["finances"]["balance"]):
		return "Compensation plus signing bonus (%s) exceeds our balance." % fmt_money(fee + bonus)
	if wage > wage_room():
		return "That wage breaks our wage budget (room: %s/wk)." % fmt_money(wage_room())
	if wage < 50:
		return "Offer a serious wage."
	var o := _new_offer(uid, t, "prospect" if t["pool"] == "prospect" else "fa")
	o["package"] = blank_package(fee)
	o["contract"] = {
		"wage": wage, "years": clampi(int(con.get("years", 3)), 1, 4),
		"bonus": bonus, "status": String(con.get("status", "First team")),
	}
	o["stage"] = "wage_pending"
	o["log"].append(_log_line("Contract offered: %s%s." % [describe_contract(o["contract"]),
		(" (plus %s development compensation)" % fmt_money(fee)) if fee > 0 else ""]))
	offers_out.append(o)
	if is_deadline_day():
		_respond_now(o)
	save_state()
	market_updated.emit()
	return ""


func _offer_out(offer_id: int) -> Dictionary:
	for o in offers_out:
		if int(o["id"]) == offer_id:
			return o
	return {}


func _tick_offers_out(rng: RandomNumberGenerator) -> void:
	for o in offers_out:
		if o["stage"] in DEAD_STAGES:
			continue
		if String(o["respond_on"]) > GameState.current_date:
			continue
		var t := find_target(o["uid"])
		if t.is_empty() or (o["kind"] in ["buy", "loan"] and t["club_id"] != o["club_id"]):
			o["stage"] = "collapsed"
			o["log"].append(_log_line("Deal collapsed — the target is no longer available."))
			GameState.add_inbox_message(GameState.current_date, "Deal collapsed: %s" % o["name"],
				"Our move for %s is off — they are no longer available." % o["name"])
			continue
		match String(o["stage"]):
			"bid_pending":
				if o["kind"] == "loan":
					_respond_to_loan(o, t, rng)
				else:
					_respond_to_package(o, t, rng)
			"wage_pending":
				_respond_to_contract(o, t, rng)


func _respond_to_package(o: Dictionary, t: Dictionary, rng: RandomNumberGenerator) -> void:
	var inst: Dictionary = t["inst"]
	var seller: Dictionary = GameState.club(o["club_id"])
	var pc: Dictionary = GameState.player_club()
	# Won't sell below a working squad.
	if seller["squad"].size() <= 7:
		o["stage"] = "rejected"
		o["log"].append(_log_line("%s reject the offer — their squad is too thin to sell." % seller["short"]))
		GameState.add_inbox_message(GameState.current_date, "Offer rejected: %s" % o["name"],
			"%s will not sell %s at any price right now — their squad is too small." % [seller["name"], o["name"]])
		return
	var rep_factor := 1.0 + float(int(seller["reputation"]) - int(pc["reputation"])) * 0.015
	var mood := 0.97 + rng.randf() * 0.15 - float(int(o["rounds"])) * 0.03
	var threshold := int(float(ask_price(inst, o["club_id"])) * rep_factor * maxf(0.85, mood))
	# A live rival bid props the seller's price up — beat it or lose the race.
	var rv: Dictionary = o.get("rival", {})
	if not rv.is_empty():
		threshold = maxi(threshold, int(float(int(rv["value"])) * 1.03))
	var pv := package_value(o["package"], inst, seller)
	o["rounds"] = int(o["rounds"]) + 1
	if bool(o.get("binding", false)) or pv >= int(float(threshold) * 0.97):
		o["stage"] = "fee_agreed"
		var demand := int(round(float(inst["contract"]["salary"]) * (1.15 + rng.randf() * 0.35) / 10.0)) * 10
		o["contract_demand"] = _make_contract_demand(inst, demand)
		o["log"].append(_log_line("%s accept the package (%s). Wage demand: %s/wk." % [
			seller["short"], describe_package(o["package"]), fmt_money(demand)]))
		GameState.add_inbox_message(GameState.current_date, "Package agreed: %s (%s)" % [o["name"], describe_package(o["package"])],
			"%s have accepted our package for %s — %s. Agree personal terms in the Transfer Centre — they want around %s/wk." % [
				seller["name"], o["name"], describe_package(o["package"]), fmt_money(demand)])
	elif pv >= int(float(threshold) * 0.68) and int(o["rounds"]) <= 3:
		_build_counter_packages(o, inst, seller, threshold, pv)
		o["stage"] = "countered"
		var firm := " This is their final position." if int(o["rounds"]) >= 3 else ""
		var rival_txt := "" if rv.is_empty() else " They point to %s's rival bid (~%s)." % [String(rv["club"]), fmt_money(int(rv["value"]))]
		var alt_txt := "" if o["alt_package"].is_empty() else " — or, structured: %s" % describe_package(o["alt_package"])
		o["log"].append(_log_line("%s counter: %s%s.%s%s" % [seller["short"], describe_package(o["ask_package"]), alt_txt, firm, rival_txt]))
		GameState.add_inbox_message(GameState.current_date, "Counter offer: %s want more for %s" % [seller["short"], o["name"]],
			"%s rejected our package (%s) for %s. They propose: %s.%s%s%s" % [
				seller["name"], describe_package(o["package"]), o["name"], describe_package(o["ask_package"]),
				("" if o["alt_package"].is_empty() else " Alternatively they would take %s." % describe_package(o["alt_package"])), firm, rival_txt])
	else:
		o["stage"] = "rejected"
		o["log"].append(_log_line("%s reject the offer outright." % seller["short"]))
		GameState.add_inbox_message(GameState.current_date, "Offer rejected: %s" % o["name"],
			"%s consider our package (%s) for %s derisory and have ended talks." % [
				seller["name"], describe_package(o["package"]), o["name"]])


func _build_counter_packages(o: Dictionary, inst: Dictionary, seller: Dictionary, threshold: int, pv: int) -> void:
	## The seller counters with a cash-forward proposal, and — if they are not
	## desperate for cash — a structured alternative that leans on installments
	## and a sell-on clause instead of up-front money.
	var target_v := int(float(threshold) * 1.04)
	var gap := target_v - pv
	var pkg: Dictionary = o["package"]
	# Primary ask: same structure, gap closed with cash.
	var ask := pkg.duplicate()
	ask["upfront"] = int(round(float(int(pkg["upfront"]) + gap) / 1000.0)) * 1000
	o["ask_package"] = _norm_package(ask)
	# Structured alternative: close the gap with sell-on % first, then installments.
	o["alt_package"] = {}
	if cash_pressure(seller) < 0.45:
		var alt := pkg.duplicate()
		var so_unit := sell_on_unit_value(inst, seller)
		var remaining := float(gap)
		if so_unit > 1.0:
			var want_pct := int(ceil(remaining / so_unit / 5.0)) * 5
			var add_pct := clampi(want_pct, 5, 40 - int(alt["sell_on"]))
			if add_pct > 0:
				alt["sell_on"] = int(alt["sell_on"]) + add_pct
				remaining -= float(add_pct) * so_unit
		if remaining > 1000.0:
			var years := 2
			var disc := installment_discount(years, seller)
			alt["inst_years"] = years
			alt["inst_amount"] = int(alt["inst_amount"]) + int(ceil(remaining / disc / 1000.0)) * 1000
		var altn := _norm_package(alt)
		# Only present it if it is genuinely different and genuinely cheaper up front.
		if altn != o["ask_package"] and int(altn["upfront"]) < int(o["ask_package"]["upfront"]):
			o["alt_package"] = altn


func _respond_to_loan(o: Dictionary, t: Dictionary, rng: RandomNumberGenerator) -> void:
	var inst: Dictionary = t["inst"]
	var seller: Dictionary = GameState.club(o["club_id"])
	var imp := importance_of(inst, seller)
	if imp >= 1.5 or seller["squad"].size() <= 8:
		o["stage"] = "rejected"
		o["log"].append(_log_line("%s refuse to loan out a key battler." % seller["short"]))
		GameState.add_inbox_message(GameState.current_date, "Loan refused: %s" % o["name"],
			"%s will not loan %s — they are central to their plans." % [seller["name"], o["name"]])
		return
	var req_split := 100 if imp >= 1.3 else (80 if imp >= 1.15 else 50 + (rng.randi() % 3) * 10)
	var ask := ask_price(inst, o["club_id"])
	var req_opt := 0
	if imp >= 1.3:
		req_opt = int(round(float(ask) * 0.85 / 1000.0)) * 1000
	elif imp >= 1.15:
		req_opt = int(round(float(ask) * 0.5 / 1000.0)) * 1000
	var lt: Dictionary = o["loan_terms"]
	o["rounds"] = int(o["rounds"]) + 1
	if bool(o.get("binding", false)) or (int(lt.get("wage_split", 0)) >= req_split and int(lt.get("option_fee", 0)) >= int(float(req_opt) * 0.95)):
		_complete_incoming_signing(o, t)
	elif int(o["rounds"]) <= 3:
		o["loan_ask"] = {"wage_split": req_split, "option_fee": req_opt}
		o["stage"] = "countered"
		o["log"].append(_log_line("%s counter on the loan: %s." % [seller["short"], describe_loan(o["loan_ask"])]))
		GameState.add_inbox_message(GameState.current_date, "Loan counter: %s" % o["name"],
			"%s would loan %s only on these terms — %s. Respond in the Transfer Centre." % [
				seller["name"], o["name"], describe_loan(o["loan_ask"])])
	else:
		o["stage"] = "rejected"
		o["log"].append(_log_line("%s end the loan talks." % seller["short"]))
		GameState.add_inbox_message(GameState.current_date, "Loan talks over: %s" % o["name"],
			"%s have ended loan negotiations for %s." % [seller["name"], o["name"]])


func _make_contract_demand(inst: Dictionary, wage_demand: int) -> Dictionary:
	var age_y := float(inst["age_months"]) / 12.0
	var pref_years := 2 if age_y > 8.0 else (4 if age_y < 3.0 else 3)
	var pref_status := "First team" if age_y >= 2.5 else "Development"
	return {"wage": wage_demand, "years": pref_years, "status": pref_status}


func _respond_to_contract(o: Dictionary, t: Dictionary, rng: RandomNumberGenerator) -> void:
	var inst: Dictionary = t["inst"]
	var pc: Dictionary = GameState.player_club()
	if o["contract_demand"].is_empty():
		var rep_disc := 1.12 - float(int(pc["reputation"])) * 0.01
		var demand := int(round(float(inst["contract"]["salary"]) * (1.05 + rng.randf() * 0.25) * rep_disc / 10.0)) * 10
		o["contract_demand"] = _make_contract_demand(inst, demand)
	var demand_wage := int(o["contract_demand"]["wage"])
	var appeal := contract_appeal(o["contract"], inst)
	if appeal >= float(demand_wage) * 0.97:
		_complete_incoming_signing(o, t)
	elif int(o["rounds"]) < 4:
		o["rounds"] = int(o["rounds"]) + 1
		o["stage"] = "wage_countered"
		var alt := _contract_alternative(o["contract_demand"], inst)
		o["log"].append(_log_line("%s wants %s/wk — or would take %s." % [
			o["name"], fmt_money(demand_wage), describe_contract(alt)]))
		GameState.add_inbox_message(GameState.current_date, "Contract talks: %s wants %s/wk" % [o["name"], fmt_money(demand_wage)],
			"%s turned down our terms (%s). They want %s/wk as offered — or would accept a structured deal: %s. Respond in the Transfer Centre." % [
				o["name"], describe_contract(o["contract"]), fmt_money(demand_wage), describe_contract(alt)])
	else:
		o["stage"] = "collapsed"
		o["log"].append(_log_line("%s walks away from contract talks." % o["name"]))
		GameState.add_inbox_message(GameState.current_date, "Talks collapse: %s" % o["name"],
			"%s has broken off contract negotiations after repeated low offers." % o["name"])


func _contract_alternative(demand: Dictionary, inst: Dictionary) -> Dictionary:
	## A cheaper-wage package the player would also sign: longer deal + Star
	## status trades directly against weekly money.
	var years := clampi(int(demand.get("years", 3)) + 1, 1, 4)
	var probe := {"wage": 100, "years": years, "bonus": 0, "status": "Star battler"}
	var mult := contract_appeal(probe, inst) / 100.0
	var wage := int(ceil(float(int(demand["wage"])) * 0.97 / mult / 10.0)) * 10
	return {"wage": wage, "years": years, "bonus": 0, "status": "Star battler"}


func loan_until() -> String:
	## Loans run to the end of the season (or ~4 months if signed very late).
	var end := Season.date_add(GameState.season_start, 231)
	if end <= Season.date_add(GameState.current_date, 28):
		end = Season.date_add(GameState.current_date, 112)
	return end


func _complete_incoming_signing(o: Dictionary, t: Dictionary) -> void:
	var inst: Dictionary = t["inst"]
	var pc: Dictionary = GameState.player_club()
	var pkg: Dictionary = o["package"]
	var con: Dictionary = o["contract"]
	var upfront := int(pkg.get("upfront", 0))
	var bonus := int(con.get("bonus", 0))

	if o["kind"] == "loan":
		var lt: Dictionary = o["loan_terms"]
		var split := int(lt.get("wage_split", 100))
		var extra_wage := int(round(float(inst["contract"]["salary"]) * float(split) / 100.0))
		if extra_wage > wage_room():
			o["stage"] = "collapsed"
			o["log"].append(_log_line("Loan collapsed — wage budget no longer covers our share."))
			return
		var owner: Dictionary = GameState.club(o["club_id"])
		owner["squad"].erase(inst)
		inst["loan"] = {"owner": o["club_id"], "until": loan_until(),
			"wage_split": split, "option_fee": int(lt.get("option_fee", 0)), "warned": false}
		pc["squad"].append(inst)
		knowledge[inst["uid"]] = 100.0
		o["stage"] = "completed"
		o["log"].append(_log_line("Loan agreed. %s joins %s until %s." % [o["name"], pc["short"], Season.pretty_date(inst["loan"]["until"])]))
		_log_deal(o["name"], owner["name"], pc["name"], 0, extra_wage, "loan", describe_loan(lt))
		GameState.add_inbox_message(GameState.current_date, "Loan completed: %s" % o["name"],
			"%s joins %s on loan from %s until %s. We cover %d%% of their %s/wk wages%s." % [
				o["name"], pc["name"], owner["name"], Season.pretty_date(inst["loan"]["until"]), split,
				fmt_money(int(inst["contract"]["salary"])),
				(", with an option to buy for %s" % fmt_money(int(lt.get("option_fee", 0)))) if int(lt.get("option_fee", 0)) > 0 else ""])
		GameState.save_game()
		return

	if upfront + bonus > int(pc["finances"]["balance"]) or int(con.get("wage", 0)) > wage_room():
		o["stage"] = "collapsed"
		o["log"].append(_log_line("Deal collapsed — budget no longer covers the terms."))
		return

	# Move the instance to our squad.
	match String(o["kind"]):
		"buy":
			var seller: Dictionary = GameState.club(o["club_id"])
			seller["squad"].erase(inst)
			seller["finances"]["balance"] = int(seller["finances"]["balance"]) + upfront
			# Any existing sell-on clause held by a third party pays out of the seller's fee.
			_pay_sell_on(inst, package_total(pkg), seller)
			# Schedule the installments we owe.
			_schedule_installments(pkg, o["club_id"], "out", o["name"])
			# Record the new sell-on clause the seller negotiated.
			if int(pkg.get("sell_on", 0)) > 0:
				inst["sell_on"] = {"club_id": o["club_id"], "pct": int(pkg["sell_on"])}
			else:
				inst.erase("sell_on")
		"fa":
			GameState.world["free_agents"].erase(inst)
		"prospect":
			GameState.world["prospects"].erase(inst)
	inst.erase("scouted_pct")
	inst["contract"]["salary"] = int(con.get("wage", 0))
	inst["contract"]["expiry"] = "%d-06-30" % (int(GameState.current_date.substr(0, 4)) + clampi(int(con.get("years", 3)), 1, 4))
	inst["squad_status"] = String(con.get("status", "First team"))
	pc["squad"].append(inst)
	pc["finances"]["balance"] = int(pc["finances"]["balance"]) - upfront - bonus
	knowledge[inst["uid"]] = 100.0
	o["stage"] = "completed"
	o["log"].append(_log_line("Deal done. %s joins %s." % [o["name"], pc["short"]]))
	var from_name: String = "Free agency" if o["club_id"] == "" else String(GameState.club(o["club_id"])["name"])
	var terms := describe_package(pkg) + " · " + describe_contract(con)
	_log_deal(o["name"], from_name, pc["name"], package_total(pkg), int(con.get("wage", 0)),
		"buy" if o["kind"] == "buy" else "fa_in", terms)
	GameState.add_inbox_message(GameState.current_date, "Signing completed: %s" % o["name"],
		"%s joins %s from %s. Deal: %s. Contract: %s (until %s)." % [
			o["name"], pc["name"], from_name, describe_package(pkg),
			describe_contract(con), inst["contract"]["expiry"]])
	GameState.save_game()


func _schedule_installments(pkg: Dictionary, club_id: String, dir: String, pname: String) -> void:
	var total := int(pkg.get("inst_amount", 0))
	if total <= 0:
		return
	var years := clampi(int(pkg.get("inst_years", 2)), 1, 3)
	var per := int(round(float(total) / float(years) / 10.0)) * 10
	for k in years:
		var amount := per if k < years - 1 else total - per * (years - 1)
		payments.append({
			"due": Season.date_add(GameState.current_date, 364 * (k + 1)),
			"amount": amount, "club_id": club_id, "dir": dir, "name": pname,
		})


func _pay_sell_on(inst: Dictionary, fee: int, seller: Dictionary) -> void:
	## Executes an existing sell-on clause when `seller` sells this instance.
	if not inst.has("sell_on") or fee <= 0:
		return
	var so: Dictionary = inst["sell_on"]
	var owner_id := String(so.get("club_id", ""))
	if owner_id == "" or owner_id == String(seller["id"]):
		inst.erase("sell_on")
		return
	var cut := int(round(float(fee) * float(so.get("pct", 0)) / 100.0))
	if cut > 0:
		seller["finances"]["balance"] = int(seller["finances"]["balance"]) - cut
		if GameState.is_player_club(owner_id):
			var pc: Dictionary = GameState.player_club()
			pc["finances"]["balance"] = int(pc["finances"]["balance"]) + cut
			GameState.add_inbox_message(GameState.current_date,
				"Sell-on clause pays out: %s (%s)" % [display_name(inst), fmt_money(cut)],
				"Our %d%% sell-on clause on %s has paid out %s from their %s move." % [
					int(so.get("pct", 0)), display_name(inst), fmt_money(cut), fmt_money(fee)])
		else:
			var owner: Dictionary = GameState.club(owner_id)
			owner["finances"]["balance"] = int(owner["finances"]["balance"]) + cut
	inst.erase("sell_on")


# ------------------------------------------------------------------ loans (running)

func loaned_in() -> Array:
	return GameState.player_club()["squad"].filter(func(i): return i.has("loan"))


func exercise_loan_option(uid: String) -> String:
	var pc: Dictionary = GameState.player_club()
	for inst in pc["squad"]:
		if inst["uid"] == uid and inst.has("loan"):
			var fee := int(inst["loan"].get("option_fee", 0))
			if fee <= 0:
				return "No option to buy in this loan."
			if fee > int(pc["finances"]["balance"]):
				return "We cannot afford the option fee (%s)." % fmt_money(fee)
			var owner_id := String(inst["loan"]["owner"])
			var owner: Dictionary = GameState.club(owner_id)
			pc["finances"]["balance"] = int(pc["finances"]["balance"]) - fee
			owner["finances"]["balance"] = int(owner["finances"]["balance"]) + fee
			inst.erase("loan")
			inst["contract"]["expiry"] = "%d-06-30" % (int(GameState.current_date.substr(0, 4)) + 2)
			_log_deal(display_name(inst), owner["name"], pc["name"], fee,
				int(inst["contract"]["salary"]), "buy", "Loan option exercised")
			GameState.add_inbox_message(GameState.current_date, "Option exercised: %s signs permanently" % display_name(inst),
				"We have exercised the %s option to buy on %s. They join permanently from %s." % [
					fmt_money(fee), display_name(inst), owner["name"]])
			GameState.save_game()
			save_state()
			market_updated.emit()
			return ""
	return "No such loanee."


func _tick_loans() -> void:
	var pc: Dictionary = GameState.player_club()
	var returning: Array = []
	for inst in pc["squad"]:
		if not inst.has("loan"):
			continue
		var lo: Dictionary = inst["loan"]
		if String(lo["until"]) <= GameState.current_date:
			returning.append(inst)
		elif not bool(lo.get("warned", false)) and Season.date_add(GameState.current_date, 7) >= String(lo["until"]):
			lo["warned"] = true
			var opt := int(lo.get("option_fee", 0))
			GameState.add_inbox_message(GameState.current_date, "Loan ending soon: %s" % display_name(inst),
				"%s returns to %s on %s.%s" % [display_name(inst), GameState.club(String(lo["owner"]))["name"],
					Season.pretty_date(String(lo["until"])),
					(" Exercise our %s option to buy in the Transfer Centre to keep them." % fmt_money(opt)) if opt > 0 else ""])
	for inst in returning:
		var owner: Dictionary = GameState.club(String(inst["loan"]["owner"]))
		pc["squad"].erase(inst)
		inst.erase("loan")
		owner["squad"].append(inst)
		GameState.add_inbox_message(GameState.current_date, "Loan ended: %s returns to %s" % [display_name(inst), owner["short"]],
			"%s's loan spell with us is over — they have returned to %s." % [display_name(inst), owner["name"]])
	if not returning.is_empty():
		GameState.save_game()


func _tick_payments() -> void:
	var pc: Dictionary = GameState.player_club()
	var due: Array = payments.filter(func(p): return String(p["due"]) <= GameState.current_date)
	for p in due:
		payments.erase(p)
		var amount := int(p["amount"])
		var other: Dictionary = GameState.club(String(p["club_id"])) if String(p["club_id"]) != "" else {}
		if String(p["dir"]) == "out":
			pc["finances"]["balance"] = int(pc["finances"]["balance"]) - amount
			if not other.is_empty():
				other["finances"]["balance"] = int(other["finances"]["balance"]) + amount
			GameState.add_inbox_message(GameState.current_date, "Installment paid: %s (%s)" % [String(p["name"]), fmt_money(amount)],
				"A scheduled transfer installment of %s for %s has been paid%s." % [
					fmt_money(amount), String(p["name"]),
					(" to %s" % other["name"]) if not other.is_empty() else ""])
		else:
			pc["finances"]["balance"] = int(pc["finances"]["balance"]) + amount
			if not other.is_empty():
				other["finances"]["balance"] = int(other["finances"]["balance"]) - amount
			GameState.add_inbox_message(GameState.current_date, "Installment received: %s (%s)" % [String(p["name"]), fmt_money(amount)],
				"A scheduled transfer installment of %s for %s has arrived%s." % [
					fmt_money(amount), String(p["name"]),
					(" from %s" % other["name"]) if not other.is_empty() else ""])
	if not due.is_empty():
		GameState.save_game()


# ------------------------------------------------------------------ rival bids (deal hijacking)
# While we negotiate for a target, rival clubs can enter the race — far more
# likely as the deadline nears. A rival bid props up the seller's demands and,
# if we don't beat it before the rival's decision date, the rival can complete
# the signing under our nose (FM's classic hijack).

func _tick_rivals(rng: RandomNumberGenerator) -> void:
	if not window_open():
		return
	var factor := deadline_factor()
	for o in offers_out:
		if String(o["kind"]) != "buy" or String(o["stage"]) in DEAD_STAGES:
			continue
		var t := find_target(String(o["uid"]))
		if t.is_empty() or t["pool"] != "club":
			continue
		var rv: Dictionary = o.get("rival", {})
		if not rv.is_empty():
			if String(rv["decides_on"]) <= GameState.current_date:
				_resolve_rival(o, t, rng)
			continue
		# Chance a rival enters the race — scales with market temperature.
		var chance := 0.055 * factor
		if bool(o.get("binding", false)):
			chance *= 0.5
		if rng.randf() >= chance:
			continue
		_spawn_rival(o, t, rng)


func _spawn_rival(o: Dictionary, t: Dictionary, rng: RandomNumberGenerator) -> void:
	var inst: Dictionary = t["inst"]
	var seller: Dictionary = GameState.club(String(o["club_id"]))
	var val := ask_price(inst, String(o["club_id"]))
	var rivals: Array = GameState.world["clubs"].filter(func(c):
		return not GameState.is_player_club(c["id"]) and String(c["id"]) != String(o["club_id"]) \
			and int(c["finances"]["balance"]) > int(float(val) * 0.9))
	if rivals.is_empty():
		return
	var rc: Dictionary = rivals[rng.randi() % rivals.size()]
	var rv_val := int(round(float(val) * (0.92 + rng.randf() * 0.22) / 1000.0)) * 1000
	var decide := Season.date_add(GameState.current_date, 1 + (rng.randi() % 3))
	var close := String(current_window()["close"])
	if decide > close:
		decide = close
	o["rival"] = {"club_id": String(rc["id"]), "club": String(rc["short"]), "value": rv_val, "decides_on": decide}
	o["log"].append(_log_line("RIVAL BID — %s enter the race with a package worth ~%s. %s decide by %s." % [
		rc["short"], fmt_money(rv_val), seller["short"], Season.pretty_date(decide)]))
	GameState.add_inbox_message(GameState.current_date,
		"Rival bid: %s move for %s" % [rc["short"], o["name"]],
		"%s have tabled a rival package worth around %s for %s while we negotiate. %s will pick a buyer by %s — improve our offer above theirs or risk losing the deal.%s" % [
			rc["name"], fmt_money(rv_val), o["name"], seller["name"], Season.pretty_date(decide),
			" It is deadline week — expect them to move FAST." if days_to_deadline() <= 7 else ""])


func _resolve_rival(o: Dictionary, t: Dictionary, rng: RandomNumberGenerator) -> void:
	var inst: Dictionary = t["inst"]
	var seller: Dictionary = GameState.club(String(o["club_id"]))
	var rv: Dictionary = o["rival"]
	var rival_club: Dictionary = GameState.club(String(rv["club_id"]))
	var our_pv := package_value(o["package"], inst, seller)
	# An agreed fee / signed-off package earns us the benefit of the doubt.
	var edge := 1.06 if (bool(o.get("binding", false)) or String(o["stage"]) in ["fee_agreed", "wage_pending", "wage_countered"]) else 1.0
	var rv_val := int(rv["value"])
	if float(our_pv) * edge >= float(rv_val) or int(rival_club["finances"]["balance"]) < rv_val:
		o["rival"] = {}
		o["log"].append(_log_line("%s pull out of the race — our package is the stronger one." % rv["club"]))
		GameState.add_inbox_message(GameState.current_date, "Rival seen off: %s" % o["name"],
			"%s have withdrawn their interest in %s. Our package (worth %s to %s) beat their %s." % [
				rival_club["name"], o["name"], fmt_money(our_pv), seller["short"], fmt_money(rv_val)])
	elif rv_val > int(float(our_pv) * 1.2) or rng.randf() < 0.75:
		_hijack_deal(o, t, rv)
	else:
		o["rival"] = {}
		o["log"].append(_log_line("%s hesitate and drop out without completing their bid." % rv["club"]))
		GameState.add_inbox_message(GameState.current_date, "Rival blinks: %s" % o["name"],
			"%s failed to close their move for %s. We are back in the driving seat — but we were outbid; do not count on a second escape." % [
				rival_club["name"], o["name"]])


func _hijack_deal(o: Dictionary, t: Dictionary, rv: Dictionary) -> void:
	var inst: Dictionary = t["inst"]
	var seller: Dictionary = GameState.club(String(o["club_id"]))
	var buyer: Dictionary = GameState.club(String(rv["club_id"]))
	var fee := mini(int(rv["value"]), int(buyer["finances"]["balance"]))
	seller["squad"].erase(inst)
	buyer["squad"].append(inst)
	buyer["finances"]["balance"] = int(buyer["finances"]["balance"]) - fee
	seller["finances"]["balance"] = int(seller["finances"]["balance"]) + fee
	_pay_sell_on(inst, fee, seller)
	_log_deal(display_name(inst), seller["name"], buyer["name"], fee,
		int(inst["contract"]["salary"]), "ai", "%s cash (hijacked our deal)" % fmt_money(fee))
	o["stage"] = "hijacked"
	o["rival"] = {}
	o["log"].append(_log_line("HIJACKED — %s complete a %s deal for %s." % [buyer["short"], fmt_money(fee), o["name"]]))
	GameState.add_inbox_message(GameState.current_date,
		"Deal hijacked: %s sign %s" % [buyer["short"], o["name"]],
		"%s have gazumped us. While we haggled, they met %s's demands with a %s package and %s is theirs. Rival interest only grows toward the deadline — next time, close faster or bid stronger." % [
			buyer["name"], seller["name"], fmt_money(fee), o["name"]])
	GameState.save_game()


# ------------------------------------------------------------------ incoming offers (selling)

func active_offers_in() -> Array:
	return offers_in.filter(func(o): return o["stage"] in ["open", "counter_pending", "agreed"])


func accept_offer_in(offer_id: int) -> String:
	var o := _offer_in(offer_id)
	if o.is_empty() or not (o["stage"] in ["open", "agreed"]):
		return "Offer is no longer live."
	return _complete_sale(o)


func reject_offer_in(offer_id: int) -> void:
	var o := _offer_in(offer_id)
	if o.is_empty():
		return
	o["stage"] = "rejected"
	o["log"].append(_log_line("Offer rejected."))
	save_state()
	market_updated.emit()


func counter_offer_in(offer_id: int, ask: int, ask_sell_on: int = 0) -> String:
	## Counter an incoming bid: demand a cash fee, and optionally a sell-on
	## clause on the buyer's next sale. The buyer weighs BOTH against what
	## they are willing to spend.
	var o := _offer_in(offer_id)
	if o.is_empty() or o["stage"] != "open":
		return "Offer cannot be countered."
	if ask <= package_total(o["package"]):
		return "Ask more than their current package (%s)." % fmt_money(package_total(o["package"]))
	if ask_sell_on < 0 or ask_sell_on > 50:
		return "Sell-on demand must be between 0% and 50%."
	o["ask"] = ask
	o["ask_sell_on"] = ask_sell_on
	o["stage"] = "counter_pending"
	o["respond_on"] = Season.date_add(GameState.current_date, _response_delay(int(o["id"])))
	var txt := "We demanded %s" % fmt_money(ask)
	if ask_sell_on > 0:
		txt += " plus a %d%% sell-on clause" % ask_sell_on
	o["log"].append(_log_line(txt + "."))
	if is_deadline_day():
		var rng := RandomNumberGenerator.new()
		rng.seed = GameState.career_seed ^ GameState.current_date.hash() ^ (int(o["id"]) * 104729)
		_respond_counter_in(o, rng)
	save_state()
	market_updated.emit()
	return ""


func _complete_sale(o: Dictionary) -> String:
	var pc: Dictionary = GameState.player_club()
	if pc["squad"].size() <= 6:
		return "Cannot sell — we need at least 6 in the squad."
	var t := find_target(o["uid"])
	if t.is_empty() or t["pool"] != "mine":
		return "That squad member is no longer ours."
	var inst: Dictionary = t["inst"]
	if inst.has("loan"):
		return "They are on loan from another club — we cannot sell them."
	var buyer: Dictionary = GameState.club(o["club_id"])
	var agreed: bool = o["stage"] == "agreed" and int(o.get("ask", 0)) > 0
	var upfront: int
	var total_fee: int
	if agreed:
		upfront = int(o["ask"])
		total_fee = upfront
	else:
		upfront = int(o["package"].get("upfront", 0))
		total_fee = package_total(o["package"])
	if upfront > int(buyer["finances"]["balance"]):
		upfront = int(buyer["finances"]["balance"])
	pc["squad"].erase(inst)
	buyer["squad"].append(inst)
	pc["finances"]["balance"] = int(pc["finances"]["balance"]) + upfront
	buyer["finances"]["balance"] = int(buyer["finances"]["balance"]) - upfront
	# Sell-on we owe a third party pays out of the total fee.
	_pay_sell_on(inst, total_fee, pc)
	# Deferred part of THEIR package flows to us over time.
	if not agreed:
		_schedule_installments(o["package"], o["club_id"], "in", display_name(inst))
	# The sell-on clause we negotiated on the way out.
	var kept_pct := int(o.get("ask_sell_on", 0)) if agreed else 0
	if kept_pct > 0:
		inst["sell_on"] = {"club_id": pc["id"], "pct": kept_pct}
	var terms: String
	if agreed:
		terms = "%s up front" % fmt_money(upfront)
		if kept_pct > 0:
			terms += " + %d%% sell-on" % kept_pct
	else:
		terms = describe_package(o["package"])
	o["stage"] = "completed"
	o["log"].append(_log_line("Sale completed — %s." % terms))
	_log_deal(display_name(inst), pc["name"], buyer["name"], total_fee, int(inst["contract"]["salary"]), "sale", terms)
	GameState.add_inbox_message(GameState.current_date, "Sale completed: %s" % display_name(inst),
		"%s leaves %s for %s. Deal: %s." % [display_name(inst), pc["name"], buyer["name"], terms])
	GameState.save_game()
	save_state()
	market_updated.emit()
	return ""


func _offer_in(offer_id: int) -> Dictionary:
	for o in offers_in:
		if int(o["id"]) == offer_id:
			return o
	return {}


func _respond_counter_in(o: Dictionary, rng: RandomNumberGenerator) -> void:
	## The buying club weighs our fee + sell-on demands: meet them, table a
	## final improved cash bid, or walk away.
	var buyer: Dictionary = GameState.club(o["club_id"])
	var t := find_target(o["uid"])
	if t.is_empty() or t["pool"] != "mine":
		o["stage"] = "withdrawn"
		return
	var willing := int(float(package_total(o["package"])) * (1.12 + rng.randf() * 0.28))
	# Deadline pressure loosens the buyer's purse strings.
	if days_to_deadline() >= 0 and days_to_deadline() <= 2:
		willing = int(float(willing) * 1.12)
	willing = mini(willing, int(buyer["finances"]["balance"]))
	# Our sell-on demand is a real cost to the buyer (discounted future money).
	var so_cost := int(float(value_of(t["inst"])) * float(int(o.get("ask_sell_on", 0))) / 100.0 * resale_factor(t["inst"]) * 0.55)
	var total_cost := int(o["ask"]) + so_cost
	if total_cost <= willing:
		o["stage"] = "agreed"
		var so_txt := "" if int(o.get("ask_sell_on", 0)) <= 0 else " plus a %d%% sell-on" % int(o["ask_sell_on"])
		o["log"].append(_log_line("%s agree to pay %s%s. Awaiting our confirmation." % [buyer["short"], fmt_money(int(o["ask"])), so_txt]))
		GameState.add_inbox_message(GameState.current_date, "%s agree %s for %s" % [
			buyer["short"], fmt_money(int(o["ask"])), o["name"]],
			"%s have met our demands for %s — %s%s. Confirm or reject the sale in the Transfer Centre." % [
				buyer["name"], o["name"], fmt_money(int(o["ask"])), so_txt])
	elif total_cost <= int(float(willing) * 1.2):
		var old_ask := int(o["ask"])
		o["package"] = blank_package(int(round(float(willing) / 1000.0)) * 1000)
		o["ask"] = 0
		o["ask_sell_on"] = 0
		o["stage"] = "open"
		o["expires_on"] = _offer_expiry(5)
		o["log"].append(_log_line("%s improve their bid to %s (final, cash only)." % [buyer["short"], fmt_money(package_total(o["package"]))]))
		GameState.add_inbox_message(GameState.current_date, "Improved bid: %s offer %s for %s" % [
			buyer["short"], fmt_money(package_total(o["package"])), o["name"]],
			"%s could not meet %s but tabled a final cash bid of %s for %s." % [
				buyer["name"], fmt_money(old_ask), fmt_money(package_total(o["package"])), o["name"]])
	else:
		o["stage"] = "withdrawn"
		o["log"].append(_log_line("%s walk away from the deal." % buyer["short"]))
		GameState.add_inbox_message(GameState.current_date, "%s withdraw interest in %s" % [buyer["short"], o["name"]],
			"Our demands for %s were too rich for %s. They have moved on." % [
				o["name"], buyer["name"]])


func _offer_expiry(days: int) -> String:
	## Incoming bids never outlive the window: on deadline day they expire tonight.
	var exp := Season.date_add(GameState.current_date, days)
	var w := current_window()
	if not w.is_empty() and exp > String(w["close"]):
		exp = String(w["close"])
	return exp


func _tick_offers_in(rng: RandomNumberGenerator) -> void:
	var pc: Dictionary = GameState.player_club()
	# Respond to our counters / expire stale offers.
	for o in offers_in:
		if o["stage"] == "counter_pending" and String(o["respond_on"]) <= GameState.current_date:
			_respond_counter_in(o, rng)
		elif o["stage"] == "open" and String(o.get("expires_on", "9999")) <= GameState.current_date:
			o["stage"] = "expired"
			o["log"].append(_log_line("Offer expired."))
	# New incoming bids only arrive while the window is open — and pour in near
	# the deadline (panic buys can go well above our valuation).
	var factor := deadline_factor()
	if factor <= 0.0 or pc["squad"].size() <= 6:
		return
	var panic := days_to_deadline() <= 1
	var chance := minf(0.62, 0.10 * factor)
	if rng.randf() < chance:
		var candidates: Array = pc["squad"].filter(func(i):
			return not i.has("loan") and active_offers_in().all(func(o2): return o2["uid"] != i["uid"]))
		if not candidates.is_empty():
			candidates.sort_custom(func(a, b): return value_of(a) > value_of(b))
			var pick_pool := mini(2, candidates.size()) if panic else mini(4, candidates.size())
			var inst: Dictionary = candidates[rng.randi() % pick_pool]
			var clubs: Array = GameState.world["clubs"].filter(func(c):
				return not GameState.is_player_club(c["id"]) and int(c["finances"]["balance"]) > int(float(value_of(inst)) * 0.7))
			if not clubs.is_empty():
				var buyer2: Dictionary = clubs[rng.randi() % clubs.size()]
				# Panic bids on deadline day run 100-135% of value; normal bids 75-115%.
				var mult := (1.0 + rng.randf() * 0.35) if panic else (0.75 + rng.randf() * 0.4)
				var bid := int(round(float(value_of(inst)) * mult / 1000.0)) * 1000
				bid = mini(bid, int(buyer2["finances"]["balance"]))
				var pkg := blank_package(bid)
				if not panic and rng.randf() < 0.35:
					# Structured: part of the fee arrives in installments.
					var up := int(round(float(bid) * (0.55 + rng.randf() * 0.25) / 1000.0)) * 1000
					pkg = {"upfront": up, "inst_amount": bid - up, "inst_years": 1 + (rng.randi() % 2), "sell_on": 0}
				var expires := _offer_expiry(6)
				offers_in.append({
					"id": _next_id, "uid": inst["uid"], "club_id": buyer2["id"],
					"package": pkg, "ask": 0, "ask_sell_on": 0, "stage": "open", "name": display_name(inst),
					"respond_on": "", "expires_on": expires,
					"log": [_log_line("%s bid %s.%s" % [buyer2["short"], describe_package(pkg),
						" DEADLINE-DAY BID — decide today." if panic else ""])],
				})
				_next_id += 1
				GameState.add_inbox_message(GameState.current_date,
					"%s: %s bid %s for %s" % ["DEADLINE-DAY OFFER" if panic else "Transfer offer",
						buyer2["short"], fmt_money(package_total(pkg)), display_name(inst)],
					"%s have offered %s for %s (our valuation: %s). Accept, reject or negotiate — you can demand more cash and a sell-on clause — before %s.%s" % [
						buyer2["name"], describe_package(pkg), display_name(inst),
						fmt_money(value_of(inst)), Season.pretty_date(expires),
						" The window shuts tonight: this bid dies at midnight." if panic else ""])


# ------------------------------------------------------------------ AI <-> AI market activity

func _tick_ai_market(rng: RandomNumberGenerator) -> void:
	## AI churn follows the calendar: club-to-club deals ONLY inside a window,
	## ramping through deadline week into a multi-deal deadline-day scramble.
	## Free agents (no fee) trickle onto AI squads all year round, FM-style.
	var factor := deadline_factor()
	if factor > 0.0:
		var attempts := 1
		if days_to_deadline() <= 1:
			attempts = 3  # end-of-window scramble
		for i in attempts:
			if rng.randf() < minf(0.85, 0.22 * factor):
				_ai_club_deal(rng)
	# AI club signs a free agent (year-round; slow trickle when the window is shut).
	var fa_chance := minf(0.6, 0.18 * factor) if factor > 0.0 else 0.05
	if rng.randf() < fa_chance and not GameState.world["free_agents"].is_empty():
		var clubs2: Array = GameState.world["clubs"].filter(func(c):
			return not GameState.is_player_club(c["id"]) and c["squad"].size() < 14)
		if not clubs2.is_empty():
			var club: Dictionary = clubs2[rng.randi() % clubs2.size()]
			var fa: Dictionary = GameState.world["free_agents"][rng.randi() % GameState.world["free_agents"].size()]
			if offer_for_target(fa["uid"]).is_empty():
				GameState.world["free_agents"].erase(fa)
				club["squad"].append(fa)
				_log_deal(display_name(fa), "Free agency", club["name"], 0,
					int(fa["contract"]["salary"]), "ai_fa", "Free transfer")


func _ai_club_deal(rng: RandomNumberGenerator) -> void:
	var clubs: Array = GameState.world["clubs"].filter(func(c): return not GameState.is_player_club(c["id"]))
	var buyer: Dictionary = clubs[rng.randi() % clubs.size()]
	var sellers: Array = clubs.filter(func(c): return c["id"] != buyer["id"] and c["squad"].size() > 9)
	if sellers.is_empty():
		return
	var seller: Dictionary = sellers[rng.randi() % sellers.size()]
	var sellable: Array = seller["squad"].duplicate()
	sellable.sort_custom(func(a, b): return int(a["level"]) > int(b["level"]))
	sellable = sellable.slice(4)  # keep their stars at home
	if sellable.is_empty():
		return
	var inst: Dictionary = sellable[rng.randi() % sellable.size()]
	# Deadline-day fees run hot.
	var mult := (0.95 + rng.randf() * 0.35) if days_to_deadline() <= 1 else (0.85 + rng.randf() * 0.3)
	var fee := int(round(float(value_of(inst)) * mult / 1000.0)) * 1000
	if fee > int(float(buyer["finances"]["balance"]) * 0.5):
		return
	seller["squad"].erase(inst)
	buyer["squad"].append(inst)
	buyer["finances"]["balance"] = int(buyer["finances"]["balance"]) - fee
	seller["finances"]["balance"] = int(seller["finances"]["balance"]) + fee
	# Sell-on clauses (including OURS) pay out on AI-to-AI moves.
	_pay_sell_on(inst, fee, seller)
	var tag := " (deadline day)" if is_deadline_day() else ""
	_log_deal(display_name(inst), seller["name"], buyer["name"], fee,
		int(inst["contract"]["salary"]), "ai", fmt_money(fee) + " cash" + tag)
	if fee >= 250000 or is_deadline_day():
		GameState.add_inbox_message(GameState.current_date,
			"%s: %s sign %s" % ["Deadline-day move" if is_deadline_day() else "Market news",
				buyer["short"], display_name(inst)],
			"%s have paid %s a fee of %s for %s (Lv %d)%s. One to watch when we face them." % [
				buyer["name"], seller["name"], fmt_money(fee), display_name(inst), int(inst["level"]),
				" as the window slams shut" if is_deadline_day() else ""])


# ------------------------------------------------------------------ daily tick

func _on_date_changed(date: String) -> void:
	if date <= last_tick:
		return
	last_tick = date
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.career_seed ^ date.hash()
	_tick_windows()
	_tick_scouting(rng)
	_tick_offers_out(rng)
	_tick_offers_in(rng)
	_tick_rivals(rng)
	_tick_loans()
	_tick_payments()
	_tick_ai_market(rng)
	save_state()
	market_updated.emit()


func _log_line(text: String) -> Dictionary:
	return {"date": GameState.current_date, "text": text}


func _log_deal(pname: String, from_name: String, to_name: String, fee: int, wage: int, kind: String, terms: String = "") -> void:
	deals.push_front({
		"date": GameState.current_date, "name": pname, "from": from_name,
		"to": to_name, "fee": fee, "wage": wage, "kind": kind, "terms": terms,
	})
	if deals.size() > 120:
		deals.resize(120)
