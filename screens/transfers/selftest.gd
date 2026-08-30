extends Node
## Headless logic check for the transfers piece. Run:
##   Godot --headless --path . res://screens/transfers/selftest.tscn
## Prints TRANSFERS SELFTEST OK on success, exits nonzero on failure.

const Market := preload("res://screens/transfers/market.gd")

var _fail := 0


func _ok(cond: bool, label: String) -> void:
	if cond:
		print("  ok: %s" % label)
	else:
		_fail += 1
		printerr("  FAIL: %s" % label)


func _advance(n: int) -> void:
	for i in n:
		GameState.auto_sim_player_matches = true
		GameState.advance_day()


func _ready() -> void:
	await get_tree().process_frame
	GameState.delete_save()
	GameState.auto_sim_player_matches = true
	GameState.new_career()
	# wipe any stale market state
	if FileAccess.file_exists("user://transfers.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://transfers.json"))
	Market._inst = null
	var m: RefCounted = Market.instance()

	print("=== transfers: window calendar ===")
	_ok(m.window_open(), "summer window open at season start")
	var w0: Dictionary = m.current_window()
	_ok(String(w0.get("name", "")) == "Summer window", "current window is the summer window")
	_ok(m.days_to_deadline() == 41, "deadline day is start+41 (%d days out)" % m.days_to_deadline())
	_ok(m.market_locked_reason() == "", "no lock reason while the window is open")
	_ok(m.deadline_factor() == 1.0, "mid-window market temperature is baseline")
	_ok(String(m.next_window()["name"]) == "Winter window", "winter window queued next")

	print("=== transfers: search pool ===")
	var targets: Array = m.all_targets()
	_ok(targets.size() > 200, "market has %d targets (clubs + 80 FA + 30 prospects)" % targets.size())
	var club_t: Dictionary = targets.filter(func(t): return t["pool"] == "club").front()
	var uid: String = club_t["inst"]["uid"]
	_ok(m.knowledge_of(uid) < 100.0, "club target starts unscouted")
	var stats: Dictionary = m.exact_stats(club_t["inst"])
	var masked: String = m.masked_int(uid, "atk", int(stats["atk"]))
	_ok(masked.contains("-"), "unscouted attack shown as range (%s)" % masked)
	var b: Array = m.masked_bounds(uid, "atk", int(stats["atk"]))
	_ok(int(b[0]) <= int(stats["atk"]) and int(stats["atk"]) <= int(b[1]), "range contains true value")

	print("=== transfers: scouting ===")
	var scouts: Array = m.player_scouts()
	_ok(scouts.size() >= 1, "%d staff can scout" % scouts.size())
	var sname: String = scouts[0]["name"]
	_ok(m.assign_scout_to_target(sname, uid) == "", "scout assigned to target")
	_ok(m.assign_scout_to_target(sname, uid) != "", "busy scout cannot be double-assigned")
	var days: int = m.scout_days_for(scouts[0])
	_advance(days)
	_ok(m.knowledge_of(uid) >= 100.0, "knowledge unlocked after %d days" % days)
	_ok(m.reports.has(uid), "written report filed")
	if m.reports.has(uid):
		var r: Dictionary = m.reports[uid]
		_ok(not r["pros"].is_empty() and not r["cons"].is_empty(), "report has pros and cons")
		_ok(float(r["ability_stars"]) > 0.0, "report has star ratings")
	_ok(m.masked_int(uid, "atk", int(stats["atk"])) == str(int(stats["atk"])), "exact stats now shown")
	if scouts.size() > 1:
		_ok(m.assign_scout_to_focus(scouts[1]["name"], "water") == "", "second scout set to type focus")

	print("=== transfers: deal-structure valuation (AI brain) ===")
	var seller: Dictionary = GameState.club(club_t["club_id"])
	var inst0: Dictionary = club_t["inst"]
	var cash_pkg: Dictionary = {"upfront": 200000, "inst_amount": 0, "inst_years": 2, "sell_on": 0}
	var inst_pkg: Dictionary = {"upfront": 0, "inst_amount": 200000, "inst_years": 2, "sell_on": 0}
	var pv_cash: int = m.package_value(cash_pkg, inst0, seller)
	var pv_inst: int = m.package_value(inst_pkg, inst0, seller)
	_ok(pv_cash == 200000, "cash counts 1:1 (%d)" % pv_cash)
	_ok(pv_inst < pv_cash and pv_inst > 80000, "installments discounted below cash (%d < %d)" % [pv_inst, pv_cash])
	var so_pkg: Dictionary = {"upfront": 200000, "inst_amount": 0, "inst_years": 2, "sell_on": 30}
	_ok(m.package_value(so_pkg, inst0, seller) > pv_cash, "sell-on clause adds seller value")
	# a longer installment term is worth less to the seller
	var inst3: Dictionary = {"upfront": 0, "inst_amount": 200000, "inst_years": 3, "sell_on": 0}
	_ok(m.package_value(inst3, inst0, seller) < pv_inst, "3-year installments worth less than 2-year")
	# contract structure: length / bonus / status trade against wage
	var flat: Dictionary = {"wage": 500, "years": 1, "bonus": 0, "status": "First team"}
	var long_c: Dictionary = {"wage": 500, "years": 4, "bonus": 0, "status": "First team"}
	var star_c: Dictionary = {"wage": 500, "years": 1, "bonus": 0, "status": "Star battler"}
	var bonus_c: Dictionary = {"wage": 500, "years": 1, "bonus": 10000, "status": "First team"}
	_ok(m.contract_appeal(long_c, inst0) > m.contract_appeal(flat, inst0), "longer contract raises appeal")
	_ok(m.contract_appeal(star_c, inst0) > m.contract_appeal(flat, inst0), "Star promise raises appeal")
	_ok(m.contract_appeal(bonus_c, inst0) > m.contract_appeal(flat, inst0), "signing bonus raises appeal")

	print("=== transfers: structured fee negotiation ===")
	var pc: Dictionary = GameState.player_club()
	var ask: int = m.ask_price(inst0, club_t["club_id"])
	var bal0: int = int(pc["finances"]["balance"])
	_ok(m.make_offer(uid, {"upfront": bal0 + 999000, "inst_amount": 0, "inst_years": 2, "sell_on": 0}) != "",
		"up-front above balance blocked")
	# lowball but structured: ~88% of ask in perceived value (upfront+installments+sell-on)
	var pkg := {"upfront": int(ask * 0.6), "inst_amount": int(ask * 0.25), "inst_years": 2, "sell_on": 15}
	_ok(m.make_offer(uid, pkg) == "", "structured package submitted (ask %d)" % ask)
	var o: Dictionary = m.offer_for_target(uid)
	_advance(4)
	_ok(String(o["stage"]) in ["countered", "fee_agreed", "rejected"], "club responded (stage=%s)" % o["stage"])
	if String(o["stage"]) == "countered":
		_ok(not o["ask_package"].is_empty(), "counter is a structured package: %s" % m.describe_package(o["ask_package"]))
		var pv_ask: int = m.package_value(o["ask_package"], inst0, seller)
		_ok(pv_ask > m.package_value(o["package"], inst0, seller), "their counter is worth more than our offer")
		if not o["alt_package"].is_empty():
			var alt: Dictionary = o["alt_package"]
			_ok(int(alt["upfront"]) < int(o["ask_package"]["upfront"]),
				"alternative trades up-front cash for structure: %s" % m.describe_package(alt))
		_ok(m.accept_package(int(o["id"]), "ask") == "", "accepted their proposal")
		_advance(3)
	_ok(String(o["stage"]) == "fee_agreed", "package agreed (stage=%s)" % o["stage"])
	if String(o["stage"]) == "fee_agreed":
		var demand: Dictionary = o["contract_demand"]
		_ok(int(demand["wage"]) > 0, "wage demand set (%d/wk)" % int(demand["wage"]))
		_ok(m.offer_contract(int(o["id"]), {"wage": 999999, "years": 3, "bonus": 0, "status": "First team"}) != "",
			"wage above budget room blocked")
		_ok(m.offer_contract(int(o["id"]), {"wage": int(demand["wage"]), "years": int(demand["years"]),
			"bonus": 0, "status": "First team"}) == "", "contract offered at demand")
		var size0: int = pc["squad"].size()
		_advance(3)
		_ok(String(o["stage"]) == "completed", "transfer completed (stage=%s)" % o["stage"])
		_ok(pc["squad"].size() == size0 + 1, "squad grew to %d" % pc["squad"].size())
		_ok(int(pc["finances"]["balance"]) < bal0, "up-front fee deducted (balance %d)" % int(pc["finances"]["balance"]))
		if int(o["package"]["inst_amount"]) > 0:
			_ok(m.committed_installments() > 0, "installments scheduled (%s owed)" % m.fmt_money(m.committed_installments()))
		if int(o["package"]["sell_on"]) > 0:
			var signed: Dictionary = pc["squad"].back()
			_ok(signed.has("sell_on") and int(signed["sell_on"]["pct"]) == int(o["package"]["sell_on"]),
				"sell-on clause recorded on the signed battler")
		var exp_year := int(GameState.current_date.substr(0, 4)) + int(o["contract"]["years"])
		var signed2: Dictionary = pc["squad"].back()
		_ok(String(signed2["contract"]["expiry"]).begins_with(str(exp_year)), "contract length drives expiry (%s)" % signed2["contract"]["expiry"])
		_ok(not m.deals.is_empty() and String(m.deals[0].get("terms", "")) != "", "deal logged with structure terms")

	print("=== transfers: loan with wage split + option to buy ===")
	# find a fringe battler at a big-squad club (importance low => loanable)
	var loan_t: Dictionary = {}
	for t2 in m.all_targets():
		if t2["pool"] != "club":
			continue
		var c2: Dictionary = GameState.club(t2["club_id"])
		if c2["squad"].size() > 9 and m.importance_of(t2["inst"], c2) < 1.15 and m.offer_for_target(t2["inst"]["uid"]).is_empty():
			loan_t = t2
			break
	_ok(not loan_t.is_empty(), "found a loanable fringe target")
	if not loan_t.is_empty():
		var luid: String = loan_t["inst"]["uid"]
		var opt_fee: int = m.ask_price(loan_t["inst"], loan_t["club_id"])
		_ok(m.make_loan_offer(luid, 100, opt_fee) == "", "loan offer submitted (100%% wages, option %d)" % opt_fee)
		var lo: Dictionary = m.offer_for_target(luid)
		_advance(4)
		if String(lo["stage"]) == "countered":
			_ok(not lo["loan_ask"].is_empty(), "loan countered with terms: %s" % m.describe_loan(lo["loan_ask"]))
			m.accept_package(int(lo["id"]))
			_advance(3)
		_ok(String(lo["stage"]) == "completed", "loan completed (stage=%s)" % lo["stage"])
		var loanees: Array = m.loaned_in()
		_ok(loanees.size() == 1, "loanee in our squad with loan marker")
		if loanees.size() == 1:
			var lin: Dictionary = loanees[0]
			_ok(String(lin["loan"]["owner"]) == String(loan_t["club_id"]), "loan remembers owning club")
			var bal_l: int = int(pc["finances"]["balance"])
			var fee2: int = int(lin["loan"]["option_fee"])
			if fee2 > 0 and fee2 <= bal_l:
				_ok(m.exercise_loan_option(luid) == "", "option to buy exercised")
				_ok(not lin.has("loan"), "loan marker cleared — signed permanently")
				_ok(int(pc["finances"]["balance"]) == bal_l - fee2, "option fee paid")

	print("=== transfers: free agent (contract structure) ===")
	var fas: Array = GameState.free_agents().duplicate()
	fas.sort_custom(func(a, b): return int(a["contract"]["salary"]) < int(b["contract"]["salary"]))
	var fa: Dictionary = fas[0]
	var fa_uid: String = fa["uid"]
	var fa_salary: int = int(fa["contract"]["salary"])
	var fa_err: String = m.sign_free_agent(fa_uid, {"wage": int(fa_salary * 1.6), "years": 2, "bonus": 2000, "status": "First team"})
	_ok(fa_err == "", "generous structured contract offered to free agent (%s)" % fa_err)
	var fo: Dictionary = m.offer_for_target(fa_uid)
	var size1: int = pc["squad"].size()
	_advance(4)
	_ok(String(fo["stage"]) in ["completed", "wage_countered"], "free agent responded (stage=%s)" % fo["stage"])
	if String(fo["stage"]) == "wage_countered":
		m.offer_contract(int(fo["id"]), {"wage": int(fo["contract_demand"]["wage"]),
			"years": int(fo["contract_demand"]["years"]), "bonus": 0, "status": "First team"})
		_advance(3)
	_ok(String(fo["stage"]) == "completed", "free agent signed on wages alone")
	_ok(pc["squad"].size() == size1 + 1, "free agent in squad")

	print("=== transfers: living world ===")
	_advance(25)
	var ai_deals: Array = m.deals.filter(func(d): return d["kind"] in ["ai", "ai_fa"])
	_ok(not ai_deals.is_empty(), "AI clubs traded among themselves (%d AI deals)" % ai_deals.size())

	print("=== transfers: window shut — market locked ===")
	# All the trading above happened inside the summer window; the "living
	# world" advance carried us past deadline day.
	_ok(not m.window_open(), "market closed after the summer deadline (%s)" % GameState.current_date)
	_ok(m.days_to_deadline() == -1, "no deadline countdown between windows")
	_ok(m.deadline_factor() == 0.0, "AI transfer churn frozen between windows")
	var lock_t: Dictionary = {}
	for t3 in m.all_targets():
		if t3["pool"] == "club" and m.offer_for_target(t3["inst"]["uid"]).is_empty():
			lock_t = t3
			break
	var lock_uid: String = lock_t["inst"]["uid"]
	var lock_err: String = m.make_offer(lock_uid, {"upfront": 50000, "inst_amount": 0, "inst_years": 2, "sell_on": 0})
	_ok(lock_err.contains("CLOSED"), "club-to-club offer blocked: %s" % lock_err)
	_ok(m.make_loan_offer(lock_uid, 50, 0) != "", "loan blocked between windows")
	var pr: Dictionary = GameState.prospects()[0]
	_ok(m.sign_free_agent(pr["uid"], {"wage": 500, "years": 3, "bonus": 0, "status": "Development"}) != "",
		"prospect signing blocked between windows")
	var fas2: Array = GameState.free_agents().duplicate()
	fas2.sort_custom(func(a, b): return int(a["contract"]["salary"]) < int(b["contract"]["salary"]))
	if not fas2.is_empty():
		var fa2: Dictionary = fas2[0]
		var fa2_wage: int = clampi(int(fa2["contract"]["salary"]) * 2, 50, m.wage_room())
		var fa2_err: String = m.sign_free_agent(fa2["uid"], {"wage": fa2_wage, "years": 2, "bonus": 0, "status": "Rotation"})
		_ok(fa2_err == "", "free agents CAN still be signed with the window shut (%s)" % fa2_err)
		var fo2: Dictionary = m.offer_for_target(fa2["uid"])
		if not fo2.is_empty():
			m.withdraw_offer(int(fo2["id"]))
	var ai_deals_closed: Array = m.deals.filter(func(d): return d["kind"] == "ai" and String(d["date"]) > String(w0["close"]))
	_ok(ai_deals_closed.is_empty(), "no AI club-to-club deals after the window shut")

	print("=== transfers: winter window, rival hijack, deadline collapse ===")
	_advance(Season.days_between(GameState.current_date, "2027-01-01"))
	_ok(m.window_open() and String(m.current_window()["name"]) == "Winter window",
		"winter window opened on 1 Jan (%s)" % GameState.current_date)
	_ok(m.make_offer(lock_uid, {"upfront": 1000, "inst_amount": 0, "inst_years": 2, "sell_on": 0}) == "",
		"market unlocked again in the winter window")
	# Rival hijack: a richer rival decides today with a package we clearly cannot match.
	var oA: Dictionary = m.offer_for_target(lock_uid)
	var tA: Dictionary = m.find_target(lock_uid)
	var sellerA_id: String = String(tA["club_id"])
	var rich: Dictionary = {}
	for c3 in GameState.world["clubs"]:
		if not GameState.is_player_club(c3["id"]) and String(c3["id"]) != sellerA_id:
			if rich.is_empty() or int(c3["finances"]["balance"]) > int(rich["finances"]["balance"]):
				rich = c3
	var pvA: int = m.package_value(oA["package"], tA["inst"], GameState.club(sellerA_id))
	var rv_val: int = mini(pvA * 3 + 20000, int(rich["finances"]["balance"]))
	oA["rival"] = {"club_id": rich["id"], "club": rich["short"], "value": rv_val, "decides_on": GameState.current_date}
	var rrng := RandomNumberGenerator.new()
	rrng.seed = 12345
	m._resolve_rival(oA, tA, rrng)
	_ok(String(oA["stage"]) == "hijacked", "clearly-outbid deal gets hijacked (stage=%s)" % oA["stage"])
	var after_h: Dictionary = m.find_target(lock_uid)
	_ok(String(after_h.get("club_id", "")) == String(rich["id"]), "target actually moved to the rival club")
	_ok(String(m.deals[0]["kind"]) == "ai" and String(m.deals[0]["to"]) == String(rich["name"]), "hijack logged as a league deal")
	# Rival seen off: our package outguns a token rival, deal survives.
	var oB_t: Dictionary = {}
	for t4 in m.all_targets():
		if t4["pool"] == "club" and m.offer_for_target(t4["inst"]["uid"]).is_empty():
			oB_t = t4
			break
	var uidB: String = oB_t["inst"]["uid"]
	_ok(m.make_offer(uidB, {"upfront": 60000, "inst_amount": 0, "inst_years": 2, "sell_on": 0}) == "", "second winter offer in")
	var oB: Dictionary = m.offer_for_target(uidB)
	oB["rival"] = {"club_id": rich["id"], "club": rich["short"], "value": 1000, "decides_on": GameState.current_date}
	m._resolve_rival(oB, m.find_target(uidB), rrng)
	_ok(not (String(oB["stage"]) in m.DEAD_STAGES) and oB["rival"].is_empty(), "weak rival seen off — our deal survives")
	m.withdraw_offer(int(oB["id"]))
	# Deadline collapse: an unfinished negotiation dies when the window shuts.
	_advance(Season.days_between(GameState.current_date, "2027-01-29"))
	_ok(m.days_to_deadline() == 2 and m.deadline_factor() == 3.0, "deadline run-in: market temperature spikes (%.1f)" % m.deadline_factor())
	var pcC: Dictionary = GameState.player_club()
	var oC_t: Dictionary = {}
	for t5 in m.all_targets():
		if t5["pool"] != "club" or not m.offer_for_target(t5["inst"]["uid"]).is_empty():
			continue
		var sc5: Dictionary = GameState.club(t5["club_id"])
		if int(sc5["reputation"]) <= int(pcC["reputation"]) and sc5["squad"].size() > 7:
			var ask5: int = m.ask_price(t5["inst"], t5["club_id"])
			if int(float(ask5) * 0.9) <= int(pcC["finances"]["balance"]):
				oC_t = t5
				break
	_ok(not oC_t.is_empty(), "found a late-window target we can afford")
	if not oC_t.is_empty():
		var uidC: String = oC_t["inst"]["uid"]
		var askC: int = m.ask_price(oC_t["inst"], oC_t["club_id"])
		_ok(m.make_offer(uidC, {"upfront": int(float(askC) * 0.9), "inst_amount": 0, "inst_years": 2, "sell_on": 0}) == "",
			"offer tabled 2 days before the deadline")
		var oC: Dictionary = m.offer_for_target(uidC)
		_advance(5)
		_ok(not m.window_open(), "winter window shut (%s)" % GameState.current_date)
		_ok(String(oC["stage"]) in ["collapsed", "hijacked", "completed"],
			"deal did not survive past the deadline unresolved (stage=%s)" % oC["stage"])

	print("=== transfers: save/load roundtrip ===")
	var know_before: float = m.knowledge_of(uid)
	var deals_before: int = m.deals.size()
	var pay_before: int = m.payments.size()
	GameState.save_game()
	m.save_state()
	_ok(GameState.load_game(), "load_game succeeds")
	_ok(m.knowledge_of(uid) == know_before, "scouting knowledge survives load")
	_ok(m.deals.size() == deals_before, "deals log survives load")
	_ok(m.payments.size() == pay_before, "installment schedule survives load")
	_ok(not m.reports.is_empty(), "reports survive load")

	if _fail == 0:
		print("TRANSFERS SELFTEST OK")
		get_tree().quit(0)
	else:
		printerr("TRANSFERS SELFTEST FAILED (%d)" % _fail)
		get_tree().quit(1)
