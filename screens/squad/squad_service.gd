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
## discipline interactions (form-justified morale effects on a cooldown,
## scaled by hidden personality), nickname changes and individual training
## focus (delegated to the training piece's TrainingService when available).
##
## Personality/happiness layer (with personality.gd):
## - every morale mutation goes through apply_morale() and lands in a per-mon
##   MOOD LEDGER ({date, delta, why}) so the morale word is always explained;
## - player match results move real morale daily (win/lose, scaled by
##   temperament) — morale reacts to the season, not just manager actions;
## - morale drifts 1/day toward the mon's computed structural happiness, so
##   concerns (playing time, contract, listing...) genuinely pull it down;
## - PROMISES are real state with deadlines: a run of battles (4 in 28 days,
##   checked against genuine appearance data), a new deal (30 days, kept by an
##   actual renewal) or removal from the transfer list (10 days). Kept and
##   broken promises have inbox mail, morale and trust consequences, and
##   broken ones poison future contract demands for a while.

signal actions_changed

const SAVE_PATH := "user://squad_actions.json"

const UI := preload("res://screens/squad/ui_helpers.gd")
const SeasonStats := preload("res://screens/squad/season_stats.gd")
const History := preload("res://screens/squad/career_history.gd")
const Personality := preload("res://screens/squad/personality.gd")

const TALK_LOCK_DAYS := 42
const INTERACT_COOLDOWN_DAYS := 10
const MAX_TALK_ROUNDS := 3
const MIN_SQUAD_SIZE := 6
const MOOD_LOG_MAX := 14

const PROMISE_DEFS := {
	"battles": {"days": 28, "target": 4, "label": "A run of battles",
		"text": "a run of battles — %d appearances within %d days"},
	"new_deal": {"days": 30, "target": 0, "label": "An improved contract",
		"text": "an improved contract within %d days"},
	"unlist": {"days": 10, "target": 0, "label": "Removal from the transfer list",
		"text": "removal from the transfer list within %d days"},
}

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
		"meta": {},     # uid -> {last_interact, last_interact_delta, talks_locked_until}
		"promises": [], # [{id, uid, name, kind, text, made_on, deadline, target, baseline, status, resolved_on}]
		"mood": {},     # uid -> [{d, delta, why}] newest first (the morale ledger)
		"mood_seen": {},  # uid -> morale at last tick (attributes external changes)
		"mood_resid": {}, # uid -> unattributed morale drift accumulator
	}


func _load_state() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		var data: Variant = JSON.parse_string(f.get_as_text())
		if typeof(data) == TYPE_DICTIONARY and int(data.get("version", 0)) == 1:
			state = data
			for k in ["promises"]:
				if not (state.get(k) is Array):
					state[k] = []
			for k in ["mood", "meta", "mood_seen", "mood_resid"]:
				if not (state.get(k) is Dictionary):
					state[k] = {}
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


# ------------------------------------------------------------------ mood ledger

## THE morale mutator: clamps, records {date, delta, why} in the mon's mood
## ledger so every point of morale on the squad table has a visible reason.
func apply_morale(inst: Dictionary, delta: int, why: String, date: String = "") -> void:
	if inst.is_empty() or delta == 0:
		return
	var before := int(inst.get("morale", 70))
	var after := clampi(before + delta, 0, 100)
	inst["morale"] = after
	var uid := str(inst["uid"])
	(state["mood_seen"] as Dictionary)[uid] = after
	if after == before:
		return
	_log_mood(uid, after - before, why, date)


func _log_mood(uid: String, delta: int, why: String, date: String = "") -> void:
	var moods: Dictionary = state["mood"]
	if not moods.has(uid):
		moods[uid] = []
	var log: Array = moods[uid]
	log.push_front({"d": (date if date != "" else GameState.current_date),
		"delta": delta, "why": why})
	while log.size() > MOOD_LOG_MAX:
		log.pop_back()


## Newest-first [{d, delta, why}] — what actually moved this mon's morale.
func mood_log(uid: String) -> Array:
	return (state["mood"] as Dictionary).get(uid, [])


## Last praise/criticism: {date, delta} or {}.
func last_interaction(uid: String) -> Dictionary:
	var m := _meta(uid)
	if not m.has("last_interact"):
		return {}
	return {"date": str(m["last_interact"]), "delta": int(m.get("last_interact_delta", 0))}


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
			factors.append(I18n.t("Strong form this season (av %.2f) pushes the price up.") % rating)
		elif perf < -0.06:
			factors.append(I18n.t("Weak form (av %.2f) keeps demands modest.") % rating)
	var morale := int(inst["morale"])
	if morale < 45:
		mult += 0.15
		factors.append(I18n.t("Low morale: wants convincing to stay."))
	if is_listed(inst):
		mult -= 0.10
		factors.append(I18n.t("Transfer-listed: negotiating from weakness."))
	var pa := Personality.attrs(uid)
	if int(pa["ambition"]) >= 15:
		mult += 0.07
		factors.append(I18n.t("Ambitious character: expects wages to match their standing."))
	elif int(pa["loyalty"]) >= 15 and not is_listed(inst):
		mult -= 0.07
		factors.append(I18n.t("Loyal to the club: flexible to get a deal done."))
	if not recent_promise(uid, "broken", 45).is_empty():
		mult += 0.10
		factors.append(I18n.t("Still smarting from a broken promise: wants proof in writing."))
	var months := int(inst["age_months"])
	var years := 2
	if months < 24:
		mult += 0.06
		years = 3
		factors.append(I18n.t("Young with high ceiling: wants a long deal."))
	elif months >= 84:
		mult -= 0.22
		years = 1
		factors.append(I18n.t("Veteran: happy with a short extension."))
	elif months >= 60:
		mult -= 0.08
	var days_left := UI.days_between(GameState.current_date, inst["contract"]["expiry"])
	if days_left < 120:
		mult += 0.10
		factors.append(I18n.t("Contract nearly up: knows the leverage is theirs."))

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
		return {"error": I18n.t("No longer in the squad.")}
	if talks_locked(uid):
		return {"error": I18n.t("Talks broke down recently. %s will not renegotiate before %s.") %
			[UI.display_name(inst), I18n.pretty_date(talks_locked_until(uid))]}
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
		return {"status": "blocked", "message": I18n.t("No longer in the squad.")}
	var opened := open_talks(uid)
	if opened.has("error"):
		return {"status": "blocked", "message": opened["error"]}
	var t: Dictionary = _talks[uid]
	var name := UI.display_name(inst)

	# Budget guards use live finances.
	var new_bill := wage_bill() - int(inst["contract"]["salary"]) + wage_offer
	if new_bill > wage_budget():
		return {"status": "blocked", "wage": t["wage"], "years": t["years"],
			"message": I18n.t("That wage takes the bill to %s/wk, over our %s/wk budget.") %
				[UI.money(new_bill), UI.money(wage_budget())]}
	if bonus > balance():
		return {"status": "blocked", "wage": t["wage"], "years": t["years"],
			"message": I18n.t("We cannot afford a %s signing bonus (balance %s).") %
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
			"message": I18n.t("%s signs a new %d-year deal at %s/wk%s.") % [name, years_offer,
				UI.money(wage_offer), (I18n.t(" with a %s bonus") % UI.money(bonus)) if bonus > 0 else ""]}

	# Volatile characters walk out earlier; calm professionals keep talking.
	var pa := Personality.attrs(uid)
	var patience := 0.74 if int(pa["temperament"]) >= 8 else 0.78
	if effective >= demand * patience and int(t["rounds"]) < MAX_TALK_ROUNDS:
		# They concede a little each round they stay at the table.
		t["wage"] = int(round(demand * 0.965 / 10.0)) * 10
		var final_note := I18n.t(" This is close to their final position.") if int(t["rounds"]) == MAX_TALK_ROUNDS - 1 else ""
		return {"status": "countered", "wage": t["wage"], "years": t["years"],
			"message": I18n.t("%s rejects the offer but lowers the demand to %s/wk.%s") %
				[name, UI.money(int(t["wage"])), final_note]}

	# Insulted or out of patience: talks collapse.
	_talks.erase(uid)
	_meta(uid)["talks_locked_until"] = Season.date_add(GameState.current_date, TALK_LOCK_DAYS)
	apply_morale(inst, -9 if int(pa["temperament"]) <= 7 else -7, I18n.t("Contract talks collapsed"))
	_break_promise_kind(uid, "new_deal", I18n.t("Contract talks collapsed instead of a new deal."))
	GameState.add_inbox_message(GameState.current_date, I18n.t("Contract talks collapse: %s") % name,
		I18n.t("%s walked out of contract talks after an offer of %s/wk against a demand of %s/wk. They will not return to the table before %s, and morale has taken a hit.") %
		[name, UI.money(wage_offer), UI.money(int(demand)), I18n.pretty_date(talks_locked_until(uid))])
	save_state()
	GameState.save_game()
	actions_changed.emit()
	return {"status": "walked", "wage": int(demand), "years": t.get("years", 2),
		"message": I18n.t("%s is insulted and walks out. No talks before %s.") %
			[name, I18n.pretty_date(talks_locked_until(uid))]}


func _apply_renewal(inst: Dictionary, wage: int, years: int, bonus: int) -> void:
	var name := UI.display_name(inst)
	var old_wage := int(inst["contract"]["salary"])
	inst["contract"]["salary"] = wage
	inst["contract"]["expiry"] = Season.date_add(GameState.current_date, years * 364)
	apply_morale(inst, 9, I18n.t("Signed a new %d-year deal at %s/wk") % [years, UI.money(wage)])
	if wage > old_wage:
		_keep_promise_kind(str(inst["uid"]), "new_deal")
	History.ensure().on_renewal(inst, old_wage, wage, years, bonus)
	if bonus > 0:
		var pc: Dictionary = GameState.player_club()
		pc["finances"]["balance"] = int(pc["finances"]["balance"]) - bonus
	GameState.add_inbox_message(GameState.current_date, I18n.t("Contract renewed: %s") % name,
		I18n.t("%s has signed a new %d-year contract at %s/wk (was %s/wk)%s. The deal runs to %s.") %
		[name, years, UI.money(wage), UI.money(old_wage),
		(I18n.t(", plus a %s signing bonus") % UI.money(bonus)) if bonus > 0 else "",
		I18n.pretty_date(inst["contract"]["expiry"])])
	save_state()
	GameState.save_game()
	actions_changed.emit()


# ------------------------------------------------------------------ transfer listing

## Returns "" on success, else an error string.
func set_listed(uid: String, asking: int) -> String:
	var inst := find_instance(uid)
	if inst.is_empty():
		return I18n.t("No longer in the squad.")
	if GameState.player_club()["squad"].size() <= MIN_SQUAD_SIZE:
		return I18n.t("Cannot list anyone — the squad is already at the minimum of %d.") % MIN_SQUAD_SIZE
	var name := UI.display_name(inst)
	inst["transfer_listed"] = true
	inst["asking_price"] = maxi(asking, 250)
	var loy := int(Personality.attrs(uid)["loyalty"])
	apply_morale(inst, -11 if loy >= 15 else -8,
		I18n.t("Placed on the transfer list") + (I18n.t(" — loyalty deepens the wound") if loy >= 15 else ""))
	History.ensure().on_listed(inst, int(inst["asking_price"]))
	GameState.add_inbox_message(GameState.current_date, I18n.t("Transfer listed: %s") % name,
		I18n.t("%s has been placed on the transfer list at %s. Rival clubs will weigh the price against our %s valuation; morale has dipped. Bids will arrive in the Squad screen.") %
		[name, UI.money(int(inst["asking_price"])), UI.money(UI.est_value(inst))])
	save_state()
	GameState.save_game()
	actions_changed.emit()
	return ""


func unlist(uid: String) -> String:
	var inst := find_instance(uid)
	if inst.is_empty():
		return I18n.t("No longer in the squad.")
	inst.erase("transfer_listed")
	inst.erase("asking_price")
	apply_morale(inst, 4, I18n.t("Taken off the transfer list"))
	_keep_promise_kind(uid, "unlist")
	History.ensure().on_unlisted(inst)
	# Withdraw open bids for the mon.
	for o in state["offers"]:
		if o["uid"] == uid and o["stage"] == "open":
			o["stage"] = "withdrawn"
	GameState.add_inbox_message(GameState.current_date, I18n.t("Removed from transfer list: %s") % UI.display_name(inst),
		I18n.t("%s is no longer for sale. Any open bids have been withdrawn.") % UI.display_name(inst))
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
		return I18n.t("That bid is no longer live.")
	var inst := find_instance(str(o["uid"]))
	if inst.is_empty():
		o["stage"] = "collapsed"
		save_state()
		return I18n.t("They are no longer in our squad.")
	var pc: Dictionary = GameState.player_club()
	if pc["squad"].size() <= MIN_SQUAD_SIZE:
		return I18n.t("Cannot sell — we need at least %d in the squad.") % MIN_SQUAD_SIZE
	var buyer: Dictionary = GameState.club(str(o["club_id"]))
	if buyer.is_empty():
		return I18n.t("The bidding club no longer exists.")
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
	_void_promises(str(o["uid"]))
	GameState.add_inbox_message(GameState.current_date, I18n.t("Sale completed: %s to %s") % [name, buyer["short"]],
		I18n.t("%s leaves for %s in a %s deal. The fee has been added to our balance (now %s).") %
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
		return I18n.t("No longer in the squad.")
	var pc: Dictionary = GameState.player_club()
	if pc["squad"].size() <= MIN_SQUAD_SIZE:
		return I18n.t("Cannot release anyone — we need at least %d in the squad.") % MIN_SQUAD_SIZE
	var comp := release_compensation(inst)
	if comp > int(pc["finances"]["balance"]):
		return I18n.t("We cannot afford the %s compensation payout (balance %s).") % \
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
	_void_promises(uid)
	# The dressing room notices.
	for mate in pc["squad"]:
		apply_morale(mate, -2, I18n.t("%s was released — the dressing room noticed") % name)
	GameState.add_inbox_message(GameState.current_date, I18n.t("Contract terminated: %s") % name,
		I18n.t("%s has been released%s and enters free agency. The rest of the squad's morale dipped slightly.") %
		[name, (I18n.t(" at a cost of %s in compensation") % UI.money(comp)) if comp > 0 else ""])
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
		return {"ok": false, "message": I18n.t("No longer in the squad."), "delta": 0}
	if not can_interact(uid):
		return {"ok": false, "delta": 0, "message":
			I18n.t("You spoke to %s recently. Wait until %s before another chat.") %
			[UI.display_name(inst), I18n.pretty_date(interaction_available_on(uid))]}
	SeasonStats.player_stats()
	var apps := SeasonStats.stat_of(uid, "battles")
	var rating := SeasonStats.avg_rating(uid)
	var name := UI.display_name(inst)
	var a := Personality.attrs(uid)
	var arch: String = str(Personality.archetype(a)["name"])
	var volatile := int(a["temperament"]) <= 7
	var pro := int(a["professionalism"]) >= 14
	var delta := 0
	var msg := ""
	var why := ""
	if is_praise:
		if apps > 0 and rating >= 7.0:
			delta = 12 if volatile else 10
			msg = I18n.t("%s beams at the recognition of a %.2f-rated season. Morale +%d.") % [name, rating, delta]
			why = I18n.t("Praised for a %.2f-rated run of form") % rating
		elif apps == 0 or rating >= 6.3:
			delta = 3 if pro else 4
			msg = I18n.t("%s appreciates the encouragement%s. Morale +%d.") % [name,
				I18n.t(" (though a %s barely needs it)") % arch if pro else "", delta]
			why = I18n.t("Encouraged by the manager")
		else:
			delta = -6 if pro else -4
			msg = I18n.t("%s knows the recent form (%.2f) does not merit praise and doubts your judgement%s. Morale %d.") % [
				name, rating, I18n.t(" — a %s hates hollow flattery") % arch if pro else "", delta]
			why = I18n.t("Saw through hollow praise")
	else:
		if apps > 0 and rating < 6.3:
			delta = -1 if pro else (-5 if volatile else -3)
			msg = I18n.t("%s accepts the criticism of a %.2f-rated run and vows to respond%s. Morale %d.") % [
				name, rating, I18n.t(" — the professionalism shows") if pro else (I18n.t(" — though the %s temper flares") % arch if volatile else ""), delta]
			why = I18n.t("Fairly criticised for weak form")
		elif apps == 0:
			delta = -9 if volatile else -6
			msg = I18n.t("%s feels hard done by — they have not even battled yet%s. Morale %d.") % [
				name, I18n.t(" — and a %s does not forget it") % arch if volatile else "", delta]
			why = I18n.t("Criticised without having battled")
		else:
			delta = -13 if volatile else -9
			msg = I18n.t("%s is furious: a %.2f average does not deserve a dressing-down%s. Morale %d.") % [
				name, rating, I18n.t(" — expect the %s reaction to linger") % arch if volatile else "", delta]
			why = I18n.t("Unfairly criticised despite good form")
	apply_morale(inst, delta, why)
	_meta(uid)["last_interact"] = GameState.current_date
	_meta(uid)["last_interact_delta"] = delta
	save_state()
	GameState.save_game()
	actions_changed.emit()
	return {"ok": true, "message": msg, "delta": delta}


# ------------------------------------------------------------------ promises
## Real tracked commitments with deadlines and consequences (FM promises).
## Kinds: "battles" (4 appearances in 28 days, checked against genuine
## appearance data), "new_deal" (an actual renewal within 30 days),
## "unlist" (off the transfer list within 10 days).

func promises_for(uid: String) -> Array:
	return (state["promises"] as Array).filter(func(p): return str(p["uid"]) == uid)


func open_promise(uid: String) -> Dictionary:
	for p in state["promises"]:
		if str(p["uid"]) == uid and str(p["status"]) == "open":
			return p
	return {}


## Most recent promise with `status` resolved within the last `days`. {} if none.
func recent_promise(uid: String, status: String, days: int) -> Dictionary:
	var best: Dictionary = {}
	for p in state["promises"]:
		if str(p["uid"]) != uid or str(p["status"]) != status:
			continue
		var res := str(p.get("resolved_on", ""))
		if res == "" or UI.days_between(res, GameState.current_date) > days:
			continue
		if best.is_empty() or res > str(best.get("resolved_on", "")):
			best = p
	return best


## "" if the promise can be made, else the reason it cannot.
func can_promise(uid: String, kind: String) -> String:
	var inst := find_instance(uid)
	if inst.is_empty():
		return I18n.t("No longer in the squad.")
	if not PROMISE_DEFS.has(kind):
		return I18n.t("Unknown promise.")
	var open_p := open_promise(uid)
	if not open_p.is_empty():
		return I18n.t("A promise is already outstanding (%s, deadline %s). One at a time — your word has to mean something.") % \
			[str(open_p["text"]), I18n.pretty_date(str(open_p["deadline"]))]
	match kind:
		"unlist":
			if not is_listed(inst):
				return I18n.t("%s is not on the transfer list.") % UI.display_name(inst)
		"new_deal":
			if talks_locked(uid):
				return I18n.t("Talks broke down recently — promising a new deal now would ring hollow (locked until %s).") % \
					I18n.pretty_date(talks_locked_until(uid))
	return ""


## Make the promise: immediate trust bump, tracked deadline, inbox record.
func make_promise(uid: String, kind: String) -> Dictionary:
	var err := can_promise(uid, kind)
	if err != "":
		return {"ok": false, "message": err}
	var inst := find_instance(uid)
	var def: Dictionary = PROMISE_DEFS[kind]
	var days := int(def["days"])
	var target := int(def["target"])
	var deadline := Season.date_add(GameState.current_date, days)
	SeasonStats.player_stats()
	var text: String
	match kind:
		"battles": text = I18n.t(str(def["text"])) % [target, days] + "."
		_: text = I18n.t(str(def["text"])) % days + "."
	var name := UI.display_name(inst)
	state["promises"].append({
		"id": int(state["next_id"]), "uid": uid, "name": name, "kind": kind,
		"text": text, "made_on": GameState.current_date,
		"deadline": deadline, "target": target,
		"baseline": SeasonStats.stat_of(uid, "battles"),
		"status": "open", "resolved_on": "",
	})
	state["next_id"] = int(state["next_id"]) + 1
	apply_morale(inst, 6, I18n.t("The manager promised %s") % I18n.t(str(def["label"])).to_lower())
	GameState.add_inbox_message(GameState.current_date, I18n.t("Promise made: %s") % name,
		I18n.t("You promised %s %s The squad screen tracks it; keep it by %s or the trust you bought today comes back with interest.") %
		[name, text, I18n.pretty_date(deadline)])
	save_state()
	GameState.save_game()
	actions_changed.emit()
	return {"ok": true, "message": I18n.t("%s leaves the office with your word: %s Deadline %s.") %
		[name, text, I18n.pretty_date(deadline)]}


func _keep_promise_kind(uid: String, kind: String) -> void:
	var p := open_promise(uid)
	if not p.is_empty() and str(p["kind"]) == kind:
		_resolve_promise(p, true, GameState.current_date)


func _break_promise_kind(uid: String, kind: String, _note: String) -> void:
	var p := open_promise(uid)
	if not p.is_empty() and str(p["kind"]) == kind:
		_resolve_promise(p, false, GameState.current_date)


func _void_promises(uid: String) -> void:
	for p in state["promises"]:
		if str(p["uid"]) == uid and str(p["status"]) == "open":
			p["status"] = "void"
			p["resolved_on"] = GameState.current_date


## Broken promises hit harder on volatile / loyal characters.
func _promise_break_penalty(uid: String) -> int:
	var a: Dictionary = Personality.attrs(uid)
	var p := 12
	if int(a["temperament"]) <= 7:
		p += 4
	if int(a["loyalty"]) >= 15:
		p += 2
	if int(a["professionalism"]) >= 16:
		p -= 3
	return clampi(p, 8, 18)


func _resolve_promise(p: Dictionary, kept: bool, date: String) -> void:
	p["status"] = "kept" if kept else "broken"
	p["resolved_on"] = date
	var uid := str(p["uid"])
	var inst := find_instance(uid)
	if inst.is_empty():
		p["status"] = "void"
		return
	var name := UI.display_name(inst)
	if kept:
		apply_morale(inst, 8, "The manager kept a promise (%s)" % str(p["kind"]).replace("_", " "), date)
		GameState.add_inbox_message(date, I18n.t("Promise kept: %s") % name,
			I18n.t("Your word held: %s %s noticed — and so did the rest of the squad. Promises kept are the cheapest morale tool a manager has.") %
			[str(p["text"]), name])
	else:
		var pen := _promise_break_penalty(uid)
		apply_morale(inst, -pen, "The manager broke a promise (%s)" % str(p["kind"]).replace("_", " "), date)
		for mate in GameState.player_club().get("squad", []):
			if str(mate["uid"]) != uid:
				apply_morale(mate, -1, I18n.t("Saw the manager break a promise to %s") % name, date)
		GameState.add_inbox_message(date, I18n.t("Promise broken: %s") % name,
			I18n.t("The deadline passed on your promise to %s (%s). Morale has taken a real hit (%d), the distrust will poison contract talks for weeks, and the rest of the squad saw it happen.") %
			[name, str(p["text"]), -pen])


## Open coach-brokered pledges from the Inbox piece (read-only surface):
## the inbox tracks "promised battles" pledges on its messages; show them here
## so the squad screen is the one place all commitments are visible.
func inbox_pledges(uid: String) -> Array:
	var out: Array = []
	for m in GameState.inbox:
		var pl: Variant = m.get("pledge")
		if pl is Dictionary and str((pl as Dictionary).get("mon_uid", "")) == uid:
			out.append(pl)
	return out


# ------------------------------------------------------------------ nickname

func set_nickname(uid: String, nick: String) -> String:
	var inst := find_instance(uid)
	if inst.is_empty():
		return I18n.t("No longer in the squad.")
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
		GameState.add_inbox_message(GameState.current_date, I18n.t("Training focus: %s") % UI.display_name(inst),
			(I18n.t("%s will now focus individual training on %s.") % [UI.display_name(inst),
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
			GameState.save_game()
			actions_changed.emit()


func _process_day(date: String) -> bool:
	var changed := false
	changed = _tick_residual(date) or changed
	changed = _tick_result_morale(date) or changed
	changed = _tick_promises(date) or changed
	changed = _tick_happiness_drift() or changed
	_sync_seen()
	# Expire stale bids.
	for o in state["offers"]:
		if o["stage"] == "open" and str(o["expires_on"]) <= date:
			o["stage"] = "expired"
			GameState.add_inbox_message(date, I18n.t("Bid expired: %s") % o["name"],
				I18n.t("%s's %s bid for %s has expired without a response.") %
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
		GameState.add_inbox_message(date, I18n.t("Bid received: %s offer %s for %s") %
			[buyer["short"], UI.money(bid), name],
			I18n.t("%s have bid %s for the transfer-listed %s (asking price %s). Accept or reject the bid from the Squad screen before %s.") %
			[buyer["name"], UI.money(bid), name, UI.money(ask),
			I18n.pretty_date(Season.date_add(date, 6))])
		changed = true
	return changed


## Attribute morale changes made OUTSIDE this service (training strain,
## inbox events...) so the ledger explains every point once the swing is
## noticeable. Accumulates small daily nudges into a single honest entry.
func _tick_residual(date: String) -> bool:
	var changed := false
	var seen: Dictionary = state["mood_seen"]
	var resid: Dictionary = state["mood_resid"]
	for inst in GameState.player_club().get("squad", []):
		var uid := str(inst["uid"])
		var now := int(inst.get("morale", 70))
		if seen.has(uid):
			var d := now - int(seen[uid])
			if d != 0:
				resid[uid] = int(resid.get(uid, 0)) + d
				if absi(int(resid[uid])) >= 3:
					_log_mood(uid, int(resid[uid]),
						I18n.t("Day-to-day life: training load, coach handling and small events"), date)
					resid[uid] = 0
					changed = true
		seen[uid] = now
	return changed


func _sync_seen() -> void:
	var seen: Dictionary = state["mood_seen"]
	for inst in GameState.player_club().get("squad", []):
		seen[str(inst["uid"])] = int(inst.get("morale", 70))


## Player match results move real morale — wins lift the squad, defeats sting,
## volatile temperaments swing harder. Every change lands in the mood ledger.
func _tick_result_morale(date: String) -> bool:
	var changed := false
	for f in GameState.fixtures_on(date):
		if not f.get("played", false):
			continue
		var home := GameState.is_player_club(str(f["home"]))
		if not home and not GameState.is_player_club(str(f["away"])):
			continue
		var us := int(f["score_home"]) if home else int(f["score_away"])
		var them := int(f["score_away"]) if home else int(f["score_home"])
		var opp_id := str(f["away"]) if home else str(f["home"])
		var won := us > them
		var why := "%s %d-%d vs %s" % ["Won" if won else "Lost", us, them,
			GameState.club(opp_id).get("short", "?")]
		for inst in GameState.player_club().get("squad", []):
			var volatile: bool = int(Personality.attrs(str(inst["uid"]))["temperament"]) <= 7
			apply_morale(inst, (3 if volatile else 2) * (1 if won else -1), why, date)
		changed = true
	return changed


## Resolve promise deadlines and appearance targets against real data.
func _tick_promises(date: String) -> bool:
	var changed := false
	SeasonStats.player_stats()
	for p in state["promises"]:
		if str(p["status"]) != "open":
			continue
		var uid := str(p["uid"])
		var inst := find_instance(uid)
		if inst.is_empty():
			p["status"] = "void"
			p["resolved_on"] = date
			changed = true
			continue
		if str(p["kind"]) == "battles" \
				and SeasonStats.stat_of(uid, "battles") - int(p["baseline"]) >= int(p["target"]):
			_resolve_promise(p, true, date)
			changed = true
			continue
		if str(p["deadline"]) < date:
			_resolve_promise(p, false, date)
			changed = true
	return changed


## Day-to-day morale drifts one point toward each mon's structural happiness,
## so unaddressed concerns (playing time, contract, listing...) genuinely
## drag the morale word down over time — and fixes genuinely lift it.
func _tick_happiness_drift() -> bool:
	var squad: Array = GameState.player_club().get("squad", [])
	if squad.is_empty():
		return false
	var ctx: Dictionary = Personality.context(self)
	var changed := false
	for inst in squad:
		var h: Dictionary = Personality.happiness(inst, self, ctx)
		var gap := int(h["score"]) - int(inst.get("morale", 70))
		if absi(gap) > 6:
			inst["morale"] = clampi(int(inst["morale"]) + signi(gap), 0, 100)
			changed = true
	return changed
