extends Node
## SquadService — the squad piece's management-action model.
## Lives at /root/SquadService (created lazily by the squad screen, kept alive
## across screen re-instantiation). Every action mutates live GameState data
## (contracts, squads, finances, morale) and is persisted via GameState.save_game().
## Service-local state (interaction cooldowns, talk locks, incoming bids for
## transfer-listed Pokemon) persists to user://squad_actions.json.
##
## Actions: contract renewal negotiation (wage / length / signing bonus, multi
## round, walk-away locks), transfer listing with asking price -> genuine AI
## bids over the following days -> accept/reject sale, contract termination
## (release with compensation, mon joins the free-agent pool), praise /
## discipline interactions (form-justified morale effects on a cooldown),
## nickname changes and individual training focus (delegated to the training
## piece's TrainingService when available).

signal actions_changed

const SAVE_PATH := "user://squad_actions.json"

const UI := preload("res://screens/squad/ui_helpers.gd")
const SeasonStats := preload("res://screens/squad/season_stats.gd")
const History := preload("res://screens/squad/career_history.gd")

const TALK_LOCK_DAYS := 42
const INTERACT_COOLDOWN_DAYS := 10
const MAX_TALK_ROUNDS := 3
const MIN_SQUAD_SIZE := 6

var state: Dictionary = {}
var _talks: Dictionary = {}   # uid -> {rounds:int, wage:int, years:int} live session (not persisted)

static var _instance: Node = null


static func ensure() -> Node:
	if _instance != null and is_instance_valid(_instance):
		return _instance
	var root := Engine.get_main_loop().root as Node
	var existing := root.get_node_or_null("SquadService")
	if existing != null:
		_instance = existing
		return existing
	var svc: Node = load("res://screens/squad/squad_service.gd").new()
	svc.name = "SquadService"
	svc.setup()
	_instance = svc
	root.add_child.call_deferred(svc)
	return svc


var _setup_done := false


func setup() -> void:
	if _setup_done:
		return
	_setup_done = true
	_load_state()
	GameState.date_changed.connect(_on_date_changed)
	GameState.career_started.connect(_on_career_event)
	_catch_up()


# ------------------------------------------------------------------ state

func _default_state() -> Dictionary:
	return {
		"version": 1,
		"last": GameState.current_date,
		"next_id": 1,
		"offers": [],   # [{id, uid, name, club_id, bid, stage, made_on, expires_on}]
		"meta": {},     # uid -> {last_praise, last_discipline, talks_locked_until}
	}


func _load_state() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		var data: Variant = JSON.parse_string(f.get_as_text())
		if typeof(data) == TYPE_DICTIONARY and int(data.get("version", 0)) == 1:
			state = data
			return
	state = _default_state()
	save_state()


func save_state() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(state))


func _on_career_event() -> void:
	if state.get("last", "") > GameState.current_date:
		state = _default_state()
		save_state()
		actions_changed.emit()


func _meta(uid: String) -> Dictionary:
	var metas: Dictionary = state["meta"]
	if not metas.has(uid):
		metas[uid] = {}
	return metas[uid]


# ------------------------------------------------------------------ helpers

func find_instance(uid: String) -> Dictionary:
	for inst in GameState.player_club().get("squad", []):
		if inst["uid"] == uid:
			return inst
	return {}


func wage_bill() -> int:
	var total := 0
	for inst in GameState.player_club()["squad"]:
		total += int(inst["contract"]["salary"])
	return total


func wage_budget() -> int:
	return int(GameState.player_club()["finances"]["wage_budget"])


func balance() -> int:
	return int(GameState.player_club()["finances"]["balance"])


func is_listed(inst: Dictionary) -> bool:
	return bool(inst.get("transfer_listed", false))


func _rng_for(salt: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.career_seed + absi((salt + GameState.current_date).hash()) % 100000000
	return rng


# ------------------------------------------------------------------ contract renewal

## Deterministic wage/length demands from live value, form, morale, age and
## contract leverage. Returns {wage, years, expiry, factors: Array[String]}.
func contract_demand(inst: Dictionary) -> Dictionary:
	SeasonStats.player_stats()
	var uid: String = inst["uid"]
	var salary := int(inst["contract"]["salary"])
	var value := UI.est_value(inst)
	var factors: Array = []

	var mult := 1.0
	var apps := SeasonStats.stat_of(uid, "battles")
	var rating := SeasonStats.avg_rating(uid)
	if apps > 0:
		var perf := clampf((rating - 6.6) * 0.13, -0.18, 0.45)
		mult += perf
		if perf > 0.06:
			factors.append("Strong form this season (av %.2f) pushes the price up." % rating)
		elif perf < -0.06:
			factors.append("Weak form (av %.2f) keeps demands modest." % rating)
	var morale := int(inst["morale"])
	if morale < 45:
		mult += 0.15
		factors.append("Low morale: wants convincing to stay.")
	if is_listed(inst):
		mult -= 0.10
		factors.append("Transfer-listed: negotiating from weakness.")
	var months := int(inst["age_months"])
	var years := 2
	if months < 24:
		mult += 0.06
		years = 3
		factors.append("Young with high ceiling: wants a long deal.")
	elif months >= 84:
		mult -= 0.22
		years = 1
		factors.append("Veteran: happy with a short extension.")
	elif months >= 60:
		mult -= 0.08
	var days_left := UI.days_between(GameState.current_date, inst["contract"]["expiry"])
	if days_left < 120:
		mult += 0.10
		factors.append("Contract nearly up: knows the leverage is theirs.")

	var by_value := float(value) * 0.0115
	var wage := int(round(maxf(float(salary) * 1.12, by_value * mult) / 10.0)) * 10
	wage = maxi(wage, 60)
	return {
		"wage": wage, "years": years,
		"expiry": Season.date_add(GameState.current_date, years * 364),
		"factors": factors,
	}


func talks_locked_until(uid: String) -> String:
	return str(_meta(uid).get("talks_locked_until", ""))


func talks_locked(uid: String) -> bool:
	return talks_locked_until(uid) > GameState.current_date


## Open (or resume) a negotiation session. Returns {"error": ...} or
## {"wage", "years", "round", "factors"}.
func open_talks(uid: String) -> Dictionary:
	var inst := find_instance(uid)
	if inst.is_empty():
		return {"error": "No longer in the squad."}
	if talks_locked(uid):
		return {"error": "Talks broke down recently. %s will not renegotiate before %s." %
			[UI.display_name(inst), Season.pretty_date(talks_locked_until(uid))]}
	if not _talks.has(uid):
		var d := contract_demand(inst)
		_talks[uid] = {"rounds": 0, "wage": int(d["wage"]), "years": int(d["years"]),
			"factors": d["factors"]}
	var t: Dictionary = _talks[uid]
	return {"wage": t["wage"], "years": t["years"], "round": t["rounds"], "factors": t["factors"]}


## Submit an offer. Returns {status: accepted|countered|walked|blocked, message,
## wage, years} where wage/years are the (possibly softened) current demands.
func negotiate_contract(uid: String, wage_offer: int, years_offer: int, bonus: int) -> Dictionary:
	var inst := find_instance(uid)
	if inst.is_empty():
		return {"status": "blocked", "message": "No longer in the squad."}
	var opened := open_talks(uid)
	if opened.has("error"):
		return {"status": "blocked", "message": opened["error"]}
	var t: Dictionary = _talks[uid]
	var name := UI.display_name(inst)

	# Budget guards use live finances.
	var new_bill := wage_bill() - int(inst["contract"]["salary"]) + wage_offer
	if new_bill > wage_budget():
		return {"status": "blocked", "wage": t["wage"], "years": t["years"],
			"message": "That wage takes the bill to %s/wk, over our %s/wk budget." %
				[UI.money(new_bill), UI.money(wage_budget())]}
	if bonus > balance():
		return {"status": "blocked", "wage": t["wage"], "years": t["years"],
			"message": "We cannot afford a %s signing bonus (balance %s)." %
				[UI.money(bonus), UI.money(balance())]}

	# A signing bonus sweetens the weekly figure; a shorter deal than they
	# want costs a little goodwill, a longer one buys some.
	var effective := float(wage_offer) + float(bonus) / (float(maxi(years_offer, 1)) * 26.0)
	effective *= 1.0 + 0.04 * float(years_offer - int(t["years"]))
	var demand := float(t["wage"])
	t["rounds"] = int(t["rounds"]) + 1

	if effective >= demand * 0.97:
		_apply_renewal(inst, wage_offer, years_offer, bonus)
		_talks.erase(uid)
		return {"status": "accepted", "wage": wage_offer, "years": years_offer,
			"message": "%s signs a new %d-year deal at %s/wk%s." % [name, years_offer,
				UI.money(wage_offer), (" with a %s bonus" % UI.money(bonus)) if bonus > 0 else ""]}

	if effective >= demand * 0.74 and int(t["rounds"]) < MAX_TALK_ROUNDS:
		# They concede a little each round they stay at the table.
		t["wage"] = int(round(demand * 0.965 / 10.0)) * 10
		var final_note := " This is close to their final position." if int(t["rounds"]) == MAX_TALK_ROUNDS - 1 else ""
		return {"status": "countered", "wage": t["wage"], "years": t["years"],
			"message": "%s rejects the offer but lowers the demand to %s/wk.%s" %
				[name, UI.money(int(t["wage"])), final_note]}

	# Insulted or out of patience: talks collapse.
	_talks.erase(uid)
	_meta(uid)["talks_locked_until"] = Season.date_add(GameState.current_date, TALK_LOCK_DAYS)
	inst["morale"] = clampi(int(inst["morale"]) - 7, 0, 100)
	GameState.add_inbox_message(GameState.current_date, "Contract talks collapse: %s" % name,
		"%s walked out of contract talks after an offer of %s/wk against a demand of %s/wk. They will not return to the table before %s, and morale has taken a hit." %
		[name, UI.money(wage_offer), UI.money(int(demand)), Season.pretty_date(talks_locked_until(uid))])
	save_state()
	GameState.save_game()
	actions_changed.emit()
	return {"status": "walked", "wage": int(demand), "years": t.get("years", 2),
		"message": "%s is insulted and walks out. No talks before %s." %
			[name, Season.pretty_date(talks_locked_until(uid))]}


func _apply_renewal(inst: Dictionary, wage: int, years: int, bonus: int) -> void:
	var name := UI.display_name(inst)
	var old_wage := int(inst["contract"]["salary"])
	inst["contract"]["salary"] = wage
	inst["contract"]["expiry"] = Season.date_add(GameState.current_date, years * 364)
	inst["morale"] = clampi(int(inst["morale"]) + 9, 0, 100)
	History.ensure().on_renewal(inst, old_wage, wage, years, bonus)
	if bonus > 0:
		var pc: Dictionary = GameState.player_club()
		pc["finances"]["balance"] = int(pc["finances"]["balance"]) - bonus
	GameState.add_inbox_message(GameState.current_date, "Contract renewed: %s" % name,
		"%s has signed a new %d-year contract at %s/wk (was %s/wk)%s. The deal runs to %s." %
		[name, years, UI.money(wage), UI.money(old_wage),
		(", plus a %s signing bonus" % UI.money(bonus)) if bonus > 0 else "",
		Season.pretty_date(inst["contract"]["expiry"])])
	save_state()
	GameState.save_game()
	actions_changed.emit()


# ------------------------------------------------------------------ transfer listing

## Returns "" on success, else an error string.
func set_listed(uid: String, asking: int) -> String:
	var inst := find_instance(uid)
	if inst.is_empty():
		return "No longer in the squad."
	if GameState.player_club()["squad"].size() <= MIN_SQUAD_SIZE:
		return "Cannot list anyone — the squad is already at the minimum of %d." % MIN_SQUAD_SIZE
	var name := UI.display_name(inst)
	inst["transfer_listed"] = true
	inst["asking_price"] = maxi(asking, 250)
	inst["morale"] = clampi(int(inst["morale"]) - 8, 0, 100)
	History.ensure().on_listed(inst, int(inst["asking_price"]))
	GameState.add_inbox_message(GameState.current_date, "Transfer listed: %s" % name,
		"%s has been placed on the transfer list at %s. Rival clubs will weigh the price against our %s valuation; morale has dipped. Bids will arrive in the Squad screen." %
		[name, UI.money(int(inst["asking_price"])), UI.money(UI.est_value(inst))])
	save_state()
	GameState.save_game()
	actions_changed.emit()
	return ""


func unlist(uid: String) -> String:
	var inst := find_instance(uid)
	if inst.is_empty():
		return "No longer in the squad."
	inst.erase("transfer_listed")
	inst.erase("asking_price")
	inst["morale"] = clampi(int(inst["morale"]) + 4, 0, 100)
	History.ensure().on_unlisted(inst)
	# Withdraw open bids for the mon.
	for o in state["offers"]:
		if o["uid"] == uid and o["stage"] == "open":
			o["stage"] = "withdrawn"
	GameState.add_inbox_message(GameState.current_date, "Removed from transfer list: %s" % UI.display_name(inst),
		"%s is no longer for sale. Any open bids have been withdrawn." % UI.display_name(inst))
	save_state()
	GameState.save_game()
	actions_changed.emit()
	return ""


func offers_for(uid: String) -> Array:
	return state["offers"].filter(func(o): return o["uid"] == uid and o["stage"] == "open")


func active_offers() -> Array:
	return state["offers"].filter(func(o): return o["stage"] == "open")


func accept_offer(offer_id: int) -> String:
	var o := _offer(offer_id)
	if o.is_empty() or o["stage"] != "open":
		return "That bid is no longer live."
	var inst := find_instance(str(o["uid"]))
	if inst.is_empty():
		o["stage"] = "collapsed"
		save_state()
		return "They are no longer in our squad."
	var pc: Dictionary = GameState.player_club()
	if pc["squad"].size() <= MIN_SQUAD_SIZE:
		return "Cannot sell — we need at least %d in the squad." % MIN_SQUAD_SIZE
	var buyer: Dictionary = GameState.club(str(o["club_id"]))
	if buyer.is_empty():
		return "The bidding club no longer exists."
	var fee := mini(int(o["bid"]), int(buyer["finances"]["balance"]))
	var name := UI.display_name(inst)
	History.ensure().on_sold(inst, str(buyer["name"]), fee)
	inst.erase("transfer_listed")
	inst.erase("asking_price")
	pc["squad"].erase(inst)
	buyer["squad"].append(inst)
	pc["finances"]["balance"] = int(pc["finances"]["balance"]) + fee
	buyer["finances"]["balance"] = int(buyer["finances"]["balance"]) - fee
	o["stage"] = "completed"
	for other in state["offers"]:
		if other["uid"] == o["uid"] and other["stage"] == "open":
			other["stage"] = "withdrawn"
	GameState.add_inbox_message(GameState.current_date, "Sale completed: %s to %s" % [name, buyer["short"]],
		"%s leaves for %s in a %s deal. The fee has been added to our balance (now %s)." %
		[name, buyer["name"], UI.money(fee), UI.money(int(pc["finances"]["balance"]))])
	save_state()
	GameState.save_game()
	actions_changed.emit()
	return ""


func reject_offer(offer_id: int) -> void:
	var o := _offer(offer_id)
	if o.is_empty():
		return
	o["stage"] = "rejected"
	save_state()
	actions_changed.emit()


func _offer(offer_id: int) -> Dictionary:
	for o in state["offers"]:
		if int(o["id"]) == offer_id:
			return o
	return {}


# ------------------------------------------------------------------ release

func release_compensation(inst: Dictionary) -> int:
	var days := maxi(UI.days_between(GameState.current_date, inst["contract"]["expiry"]), 0)
	var weeks := int(ceil(days / 7.0))
	return int(round(float(weeks) * float(inst["contract"]["salary"]) * 0.5 / 10.0)) * 10


func release(uid: String) -> String:
	var inst := find_instance(uid)
	if inst.is_empty():
		return "No longer in the squad."
	var pc: Dictionary = GameState.player_club()
	if pc["squad"].size() <= MIN_SQUAD_SIZE:
		return "Cannot release anyone — we need at least %d in the squad." % MIN_SQUAD_SIZE
	var comp := release_compensation(inst)
	if comp > int(pc["finances"]["balance"]):
		return "We cannot afford the %s compensation payout (balance %s)." % \
			[UI.money(comp), UI.money(int(pc["finances"]["balance"]))]
	var name := UI.display_name(inst)
	History.ensure().on_released(inst, comp)
	pc["squad"].erase(inst)
	pc["finances"]["balance"] = int(pc["finances"]["balance"]) - comp
	inst.erase("transfer_listed")
	inst.erase("asking_price")
	# Joins the free-agent pool looking for a new club at a realistic wage.
	inst["contract"]["salary"] = maxi(int(round(float(inst["contract"]["salary"]) * 0.9 / 10.0)) * 10, 50)
	inst["contract"]["expiry"] = GameState.current_date
	GameState.world["free_agents"].append(inst)
	for o in state["offers"]:
		if o["uid"] == uid and o["stage"] == "open":
			o["stage"] = "collapsed"
	# The dressing room notices.
	for mate in pc["squad"]:
		mate["morale"] = clampi(int(mate["morale"]) - 2, 0, 100)
	GameState.add_inbox_message(GameState.current_date, "Contract terminated: %s" % name,
		"%s has been released%s and enters free agency. The rest of the squad's morale dipped slightly." %
		[name, (" at a cost of %s in compensation" % UI.money(comp)) if comp > 0 else ""])
	save_state()
	GameState.save_game()
	actions_changed.emit()
	return ""


# ------------------------------------------------------------------ praise / discipline

func interaction_available_on(uid: String) -> String:
	var last := str(_meta(uid).get("last_interact", ""))
	if last == "":
		return GameState.current_date
	return Season.date_add(last, INTERACT_COOLDOWN_DAYS)


func can_interact(uid: String) -> bool:
	return interaction_available_on(uid) <= GameState.current_date


## Returns {ok, message, delta}. Form-justified praise lands; hollow praise or
## unfair criticism backfires. 10-day cooldown per Pokemon.
func praise(uid: String) -> Dictionary:
	return _interact(uid, true)


func discipline(uid: String) -> Dictionary:
	return _interact(uid, false)


func _interact(uid: String, is_praise: bool) -> Dictionary:
	var inst := find_instance(uid)
	if inst.is_empty():
		return {"ok": false, "message": "No longer in the squad.", "delta": 0}
	if not can_interact(uid):
		return {"ok": false, "delta": 0, "message":
			"You spoke to %s recently. Wait until %s before another chat." %
			[UI.display_name(inst), Season.pretty_date(interaction_available_on(uid))]}
	SeasonStats.player_stats()
	var apps := SeasonStats.stat_of(uid, "battles")
	var rating := SeasonStats.avg_rating(uid)
	var name := UI.display_name(inst)
	var delta := 0
	var msg := ""
	if is_praise:
		if apps > 0 and rating >= 7.0:
			delta = 10
			msg = "%s beams at the recognition of a %.2f-rated season. Morale +%d." % [name, rating, 10]
		elif apps == 0 or rating >= 6.3:
			delta = 4
			msg = "%s appreciates the encouragement. Morale +%d." % [name, 4]
		else:
			delta = -4
			msg = "%s knows the recent form (%.2f) does not merit praise and doubts your judgement. Morale %d." % [name, rating, -4]
	else:
		if apps > 0 and rating < 6.3:
			delta = -3
			msg = "%s accepts the criticism of a %.2f-rated run and vows to respond. Morale %d." % [name, rating, -3]
		elif apps == 0:
			delta = -6
			msg = "%s feels hard done by — they have not even battled yet. Morale %d." % [name, -6]
		else:
			delta = -9
			msg = "%s is furious: a %.2f average does not deserve a dressing-down. Morale %d." % [name, rating, -9]
	inst["morale"] = clampi(int(inst["morale"]) + delta, 0, 100)
	_meta(uid)["last_interact"] = GameState.current_date
	save_state()
	GameState.save_game()
	actions_changed.emit()
	return {"ok": true, "message": msg, "delta": delta}


# ------------------------------------------------------------------ nickname

func set_nickname(uid: String, nick: String) -> String:
	var inst := find_instance(uid)
	if inst.is_empty():
		return "No longer in the squad."
	nick = nick.strip_edges().substr(0, 14)
	if nick == "" or nick == str(inst["species"]):
		inst["nickname"] = null
	else:
		inst["nickname"] = nick
	GameState.save_game()
	actions_changed.emit()
	return ""


# ------------------------------------------------------------------ training focus (bridged to the training piece)

func _training_service() -> Node:
	var script: Variant = load("res://screens/training/training_service.gd")
	if script == null:
		return null
	var svc: Variant = script.ensure()
	if svc is Node and svc.has_method("set_focus") and svc.has_method("mon_state"):
		return svc
	return null


func training_focus(uid: String) -> String:
	var svc := _training_service()
	if svc == null:
		return str(_meta(uid).get("focus", ""))
	return str(svc.mon_state(uid).get("focus", ""))


func set_training_focus(uid: String, stat: String) -> void:
	var svc := _training_service()
	if svc != null:
		svc.set_focus(uid, stat)
	else:
		_meta(uid)["focus"] = stat
		save_state()
	var inst := find_instance(uid)
	if not inst.is_empty():
		GameState.add_inbox_message(GameState.current_date, "Training focus: %s" % UI.display_name(inst),
			("%s will now focus individual training on %s." % [UI.display_name(inst),
				{"hp": "HP", "atk": "Attack", "def": "Defence", "spa": "Sp. Attack",
				"spd": "Sp. Defence", "spe": "Speed"}.get(stat, stat)])
			if stat != "" else "%s returns to a balanced individual programme." % UI.display_name(inst))
	actions_changed.emit()


# ------------------------------------------------------------------ daily tick

func _on_date_changed(_d: String) -> void:
	_catch_up()


func _catch_up() -> void:
	if state.get("last", "") > GameState.current_date:
		_on_career_event()
	var processed := 0
	var changed := false
	while state["last"] < GameState.current_date and processed < 400:
		state["last"] = Season.date_add(state["last"], 1)
		changed = _process_day(state["last"]) or changed
		processed += 1
	if processed > 0:
		save_state()
		if changed:
			actions_changed.emit()


func _process_day(date: String) -> bool:
	var changed := false
	# Expire stale bids.
	for o in state["offers"]:
		if o["stage"] == "open" and str(o["expires_on"]) <= date:
			o["stage"] = "expired"
			GameState.add_inbox_message(date, "Bid expired: %s" % o["name"],
				"%s's %s bid for %s has expired without a response." %
				[GameState.club(str(o["club_id"])).get("short", "?"), UI.money(int(o["bid"])), o["name"]])
			changed = true
	# Listed Pokemon attract genuine bids, priced against our asking price.
	var rng := _rng_for("squadbids:" + date)
	for inst in GameState.player_club().get("squad", []):
		if not is_listed(inst):
			continue
		if not offers_for(str(inst["uid"])).is_empty():
			continue
		var value := UI.est_value(inst)
		var ask := int(inst.get("asking_price", value))
		var ratio := float(ask) / maxf(float(value), 1.0)
		var chance := 0.30 if ratio <= 1.0 else (0.18 if ratio <= 1.35 else 0.05)
		if rng.randf() >= chance:
			continue
		var buyers: Array = GameState.world["clubs"].filter(func(c):
			return not GameState.is_player_club(c["id"]) and int(c["finances"]["balance"]) > int(float(ask) * 0.7))
		if buyers.is_empty():
			continue
		var buyer: Dictionary = buyers[rng.randi() % buyers.size()]
		var bid := int(round(float(ask) * (0.78 + rng.randf() * 0.26) / 250.0)) * 250
		bid = clampi(bid, 250, int(buyer["finances"]["balance"]))
		var name := UI.display_name(inst)
		state["offers"].append({
			"id": int(state["next_id"]), "uid": inst["uid"], "name": name,
			"club_id": buyer["id"], "bid": bid, "stage": "open",
			"made_on": date, "expires_on": Season.date_add(date, 6),
		})
		state["next_id"] = int(state["next_id"]) + 1
		GameState.add_inbox_message(date, "Bid received: %s offer %s for %s" %
			[buyer["short"], UI.money(bid), name],
			"%s have bid %s for the transfer-listed %s (asking price %s). Accept or reject the bid from the Squad screen before %s." %
			[buyer["name"], UI.money(bid), name, UI.money(ask),
			Season.pretty_date(Season.date_add(date, 6))])
		changed = true
	return changed
