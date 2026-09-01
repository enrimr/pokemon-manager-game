extends RefCounted
class_name ExpeditionService
## ExpeditionService — scouting expeditions to the wild routes of Kanto &
## Johto (routes piece). Auto-loaded by the GameState services convention;
## ticked daily; state rides world.meta.services.expeditions.
##
## Model (deterministic off GameState.career_seed + expedition id + date):
##  - Plan an expedition to any route in shared/data/routes.json: pick the
##    field duration, a leader (a staff scout/coach whose judging skill drives
##    encounter quality, capture odds and IV quality — or the manager, whose
##    absence costs squad morale and a pointed board note), an approach
##    (cautious/balanced/aggressive) and a budget of capture attempts.
##  - The party travels out (route.travel days from your region hub), works
##    the route for the planned field days — one FIELD REPORT mail per day:
##    sightings, near-misses, captures — then travels home.
##  - Captures arrive at the ACADEMY (or straight into the squad if you chose
##    so and there is room; if everything is full they wait in a holding pen
##    and land the day space opens). Levels come from the route's band, IVs
##    improve with leader skill, nature/ability are rolled on capture.
##  - Costs are debited up front from the transfer budget (cost_day for every
##    day away incl. travel + capture gear per attempt).
##  - Max 2 concurrent expeditions; a worked route needs 14 days to settle
##    before another trip. Route knowledge (species pool intel on the Routes
##    screen) grows with every field day spent there.
##  - AI clubs run cheap expeditions too (seeded daily roll): a capture lands
##    in their squad depth and the press occasionally reports it.

signal expeditions_changed

static var active = null

const ROUTES_PATH := "res://shared/data/routes.json"
const MAX_ACTIVE := 2
const COOLDOWN_DAYS := 14
const ATTEMPT_COST := 600
const MIN_FIELD_DAYS := 3
const MAX_FIELD_DAYS := 14
const FIRST_TEAM_CAP := 25          # mirrors AcademyService.FIRST_TEAM_CAP
const RECENT_WINDOW := 10           # days a report line stays "used"
const MANAGER_MORALE_COST := 3      # squad morale dip while the boss is away
const KNOW_PARTIAL := 1             # field days -> commons visible
const KNOW_GOOD := 4                # -> uncommons + exact level band
const KNOW_FULL := 8                # -> rares + special rumours

const APPROACHES := {
	"cautious":   {"enc_lo": 1, "enc_hi": 2, "catch_mod":  0.12, "mishap": 0.00},
	"balanced":   {"enc_lo": 2, "enc_hi": 3, "catch_mod":  0.00, "mishap": 0.02},
	"aggressive": {"enc_lo": 3, "enc_hi": 4, "catch_mod": -0.08, "mishap": 0.08},
}
const CATCH_BASE := {"common": 0.55, "uncommon": 0.38, "rare": 0.22, "special": 0.15}
const STAT_KEYS := ["hp", "atk", "def", "spa", "spd", "spe"]

static var _routes_cache: Array = []
static var _routes_by_id: Dictionary = {}

var expeditions: Array = []      # active expedition dicts (see plan())
var history: Array = []          # newest-first completed summaries
var knowledge: Dictionary = {}   # route_id -> field days worked there
var cooldowns: Dictionary = {}   # route_id -> ISO date the route reopens
var holding: Array = []          # captured mons waiting for a free bed/slot
var next_uid: int = 1
var ai_captures: int = 0         # world-flavour counter (news, history tab)
var intro_sent: bool = false     # one-time "expeditions explained" inbox mail
var _used_lines: Array = []      # [{tid, date}] report-line recency registry
var _gs = null


# ------------------------------------------------------------------ static data

static func routes() -> Array:
	if _routes_cache.is_empty():
		var f := FileAccess.open(ROUTES_PATH, FileAccess.READ)
		if f != null:
			var data: Variant = JSON.parse_string(f.get_as_text())
			if data is Dictionary:
				_routes_cache = data.get("routes", [])
				for r in _routes_cache:
					_routes_by_id[str(r["id"])] = r
	return _routes_cache


static func route(route_id: String) -> Dictionary:
	routes()
	return _routes_by_id.get(route_id, {})


static func region_routes(region: String) -> Array:
	return routes().filter(func(r): return str(r["region"]) == region)


# ------------------------------------------------------------------ service hooks

func service_id() -> String:
	return "expeditions"


func on_career_started(gs) -> void:
	_gs = gs
	active = self
	routes()
	_send_intro(str(gs.current_date))
	expeditions_changed.emit()


func on_day(gs, date: String) -> void:
	_gs = gs
	for exp in expeditions.duplicate():
		_tick_expedition(exp, date)
	_place_holding(date)
	_ai_daily(date)
	expeditions_changed.emit()


## One-time discoverability mail: explains expeditions with a deep link to the
## Routes screen. Fires at career start (or on the first load of a save that
## predates the feature) and never again.
func _send_intro(date: String) -> void:
	if intro_sent:
		return
	intro_sent = true
	if not history.is_empty() or not expeditions.is_empty():
		return  # veteran save — they clearly found the screen already
	_post_mail(date, I18n.t("Scouting the wild routes — how expeditions work"),
		I18n.t("Boss — the wild routes of Kanto and Johto are open for fieldwork. From the Routes screen you can send a party (led by a scout, a coach, or yourself) to any route for 3-14 field days: pick an approach, buy capture gear, and the party mails back a report every day. Captures come home to the academy or straight into the squad, and every field day charts the route's species for good. Costs come out of the transfer budget. Two parties can be out at once."),
		{"cat": "scout", "exped_kind": "intro", "uid": "exped:intro"})


func save_state() -> Dictionary:
	return {"expeditions": expeditions.duplicate(true), "history": history.duplicate(true),
		"knowledge": knowledge.duplicate(true), "cooldowns": cooldowns.duplicate(true),
		"holding": holding.duplicate(true), "next_uid": next_uid,
		"ai_captures": ai_captures, "intro_sent": intro_sent,
		"used_lines": _used_lines.duplicate(true)}


func load_state(state: Dictionary) -> void:
	expeditions = state.get("expeditions", [])
	history = state.get("history", [])
	holding = state.get("holding", [])
	knowledge = {}
	var kn: Dictionary = state.get("knowledge", {})
	for k in kn:
		knowledge[str(k)] = int(kn[k])
	cooldowns = state.get("cooldowns", {})
	next_uid = int(state.get("next_uid", 1))
	ai_captures = int(state.get("ai_captures", 0))
	intro_sent = bool(state.get("intro_sent", false))
	_used_lines = state.get("used_lines", [])
	for exp in expeditions:
		_cast_expedition(exp)
	for m in holding:
		_cast_mon(m)
	for h in history:
		for k in ["field_days", "cost", "sightings", "near_misses", "mishaps"]:
			h[k] = int(h.get(k, 0))
		for cp in h.get("captures", []):
			cp["level"] = int(cp.get("level", 0))


func _cast_expedition(exp: Dictionary) -> void:
	for k in ["field_days", "attempts_bought", "attempts_left", "travel_days",
			"days_in_phase", "day_no", "cost", "sightings", "near_misses", "mishaps",
			"refund"]:
		exp[k] = int(exp.get(k, 0))
	exp["leader_skill"] = int(exp.get("leader_skill", 10))
	for m in exp.get("captures", []):
		_cast_mon(m)
	for e in exp.get("log", []):
		e["day"] = int(e.get("day", 0))
		e["level"] = int(e.get("level", 0))


func _cast_mon(m: Dictionary) -> void:
	for k in ["species_id", "level", "age_months", "potential", "pot_min", "pot_max"]:
		m[k] = int(m.get(k, 0))
	var ivs: Dictionary = m.get("ivs", {})
	for k in ivs:
		ivs[k] = int(ivs[k])


# ------------------------------------------------------------------ queries

func player_region() -> String:
	return _gs.player_league_id() if _gs != null else "kanto"


## Field days worked on a route (drives the Routes screen knowledge mask).
func knowledge_days(route_id: String) -> int:
	return int(knowledge.get(route_id, 0))


## 0 = unknown, 1 = partial (commons), 2 = good (+uncommons, exact levels),
## 3 = full (+rares, special rumours).
func knowledge_tier(route_id: String) -> int:
	var d := knowledge_days(route_id)
	if d >= KNOW_FULL:
		return 3
	if d >= KNOW_GOOD:
		return 2
	if d >= KNOW_PARTIAL:
		return 1
	return 0


func cooldown_until(route_id: String) -> String:
	var until := str(cooldowns.get(route_id, ""))
	if until != "" and _gs != null and until <= str(_gs.current_date):
		return ""
	return until


func expedition_on(route_id: String) -> Dictionary:
	for exp in expeditions:
		if str(exp["route_id"]) == route_id:
			return exp
	return {}


func find_expedition(exp_id: String) -> Dictionary:
	for exp in expeditions:
		if str(exp["id"]) == exp_id:
			return exp
	return {}


## Travel days from the player's region hub to a route.
func travel_days_to(r: Dictionary) -> int:
	return int(r.get("travel", {}).get(player_region(), 2))


## Full up-front cost: every day away (travel out + field + travel home)
## bills the route's daily rate, plus capture gear per attempt.
func cost_quote(route_id: String, field_days: int, attempts: int) -> int:
	var r := route(route_id)
	if r.is_empty():
		return 0
	var days := field_days + 2 * travel_days_to(r)
	return days * int(r["cost_day"]) + attempts * ATTEMPT_COST


## Who can lead: every staff scout/coach (skill = judging ability, coaches
## average their two judging ratings) plus the manager (skill from club
## reputation; going costs squad morale + a board note).
func leaders() -> Array:
	var out: Array = []
	if _gs == null:
		return out
	for s in _gs.player_club().get("staff", []):
		var role := str(s.get("role", ""))
		if role != "scout" and role != "coach":
			continue
		var rt: Dictionary = s.get("ratings", {})
		var skill := int(rt.get("judging_ability", 8))
		if role == "coach":
			skill = (int(rt.get("judging_ability", 8)) + int(rt.get("judging_potential", 8))) / 2
		out.append({"id": "staff:" + str(s["name"]), "name": str(s["name"]),
			"role": role, "skill": skill, "busy": _leader_busy("staff:" + str(s["name"]))})
	var mskill := 10 + int(_gs.player_club().get("reputation", 10)) / 4
	out.append({"id": "manager", "name": _manager_name(), "role": "manager",
		"skill": mskill, "busy": _leader_busy("manager")})
	out.sort_custom(func(a, b): return int(a["skill"]) > int(b["skill"]))
	return out


func _leader_busy(leader_id: String) -> bool:
	if expeditions.any(func(e): return str(e["leader_id"]) == leader_id):
		return true
	# legendary hunts (legendaries.gd) borrow the same leader pool
	var leg: RefCounted = LegendaryService.active
	return leg != null and leg.leader_on_hunt(leader_id)


func _manager_name() -> String:
	var n := str(_gs.world.get("meta", {}).get("manager_name", ""))
	if n == "":
		n = str(_gs.player_club().get("manager", I18n.t("The manager")))
	return n


# ------------------------------------------------------------------ planning

## Validate + start an expedition. Returns "" or an error string.
## leader_id: "manager" or "staff:<name>" (see leaders()).
## approach: "cautious" | "balanced" | "aggressive".
## dest: "academy" | "squad" — where captures are sent on return.
func plan(route_id: String, field_days: int, leader_id: String, approach: String,
		attempts: int, dest: String = "academy") -> String:
	var r := route(route_id)
	if r.is_empty():
		return I18n.t("Unknown route.")
	if expeditions.size() >= MAX_ACTIVE:
		return I18n.t("Both expedition parties are already in the field.")
	if not expedition_on(route_id).is_empty():
		return I18n.t("A party is already working that route.")
	if cooldown_until(route_id) != "":
		return I18n.t("That route needs to settle — open again on %s.") % I18n.pretty_date(cooldown_until(route_id))
	if field_days < MIN_FIELD_DAYS or field_days > MAX_FIELD_DAYS:
		return I18n.t("Field duration must be between %d and %d days.") % [MIN_FIELD_DAYS, MAX_FIELD_DAYS]
	if not APPROACHES.has(approach):
		return I18n.t("Pick an approach: cautious, balanced or aggressive.")
	if dest != "academy" and dest != "squad":
		return I18n.t("Captures must be routed to the academy or the squad.")
	attempts = clampi(attempts, 1, field_days * 3)
	if _leader_busy(leader_id):
		return I18n.t("That leader is already out on an expedition.")
	var leader := {}
	for l in leaders():
		if str(l["id"]) == leader_id:
			leader = l
	if leader.is_empty():
		return I18n.t("Pick an expedition leader.")
	var cost := cost_quote(route_id, field_days, attempts)
	var fin: Dictionary = _gs.player_club()["finances"]
	var spendable := mini(int(fin["balance"]), int(fin.get("transfer_budget", 0)))
	if spendable < cost:
		return I18n.t("Not enough transfer budget — %s %d needed, %s %d released by the board.") % [
			_gs.world["meta"]["currency"], cost, _gs.world["meta"]["currency"], maxi(0, spendable)]
	fin["balance"] = int(fin["balance"]) - cost
	fin["transfer_budget"] = int(fin.get("transfer_budget", 0)) - cost
	_gs.inventory_changed.emit()

	var travel := travel_days_to(r)
	var exp := {
		"id": "exp%04d" % next_uid, "route_id": route_id, "route_name": str(r["name"]),
		"region": str(r["region"]), "leader_id": leader_id,
		"leader": str(leader["name"]), "leader_role": str(leader["role"]),
		"leader_skill": int(leader["skill"]), "approach": approach,
		"field_days": field_days, "attempts_bought": attempts, "attempts_left": attempts,
		"dest": dest, "phase": "travel_out", "days_in_phase": 0, "day_no": 0,
		"travel_days": travel, "started": str(_gs.current_date), "cost": cost,
		"sightings": 0, "near_misses": 0, "captures": [], "log": [],
		"special_seen": false, "mishaps": 0, "recalled": false, "refund": 0,
	}
	next_uid += 1
	expeditions.append(exp)
	_log(exp, "depart", I18n.t("Party of %s departs for %s (%d field days, %d capture attempts budgeted).") % [
		str(leader["name"]), str(r["name"]), field_days, attempts])
	if leader_id == "manager":
		for m in _gs.player_club()["squad"]:
			m["morale"] = maxi(0, int(m.get("morale", 70)) - MANAGER_MORALE_COST)
		_post_mail(_gs.current_date, I18n.t("Board notes your absence"),
			I18n.t("The board has been informed that you are personally leading the %s expedition. They trust the assistant staff to mind the shop — but a manager in the field is a manager away from the squad, and the dressing room feels it.") % I18n.t(str(r["name"])),
			{"cat": "board", "exped_kind": "board_absence",
			"uid": "exped:absence:%s" % exp["id"], "route_name": str(r["name"])})
	_post_mail(_gs.current_date, I18n.t("Expedition departs: %s") % I18n.t(str(r["name"])),
		_depart_body(exp, r), _mail_extra(exp, "plan", []))
	expeditions_changed.emit()
	return ""


func _depart_body(exp: Dictionary, r: Dictionary) -> String:
	return I18n.t("%s leads a %d-day expedition to %s (%s). Travel: %d day(s) each way. Budget: %s for supplies plus capture gear for %d attempts. Approach: %s. First field report expected on arrival.") % [
		str(exp["leader"]), int(exp["field_days"]), I18n.t(str(r["name"])),
		I18n.t(str(r["region"]).capitalize()), int(exp["travel_days"]),
		AcademyService.format_money(int(exp["cost"])), int(exp["attempts_bought"]),
		I18n.t(str(exp["approach"]).capitalize())]


## Order a party home early. Returns "" or an error string.
## Cost implication: days already paid are sunk; unused capture gear is sold
## back to the outfitter at HALF price (credited to balance + transfer budget).
func recall(exp_id: String) -> String:
	var exp := find_expedition(exp_id)
	if exp.is_empty():
		return I18n.t("That party is no longer in the field.")
	if str(exp["phase"]) == "travel_home":
		return I18n.t("The party is already on its way home.")
	var refund := recall_refund(exp)
	if refund > 0:
		var fin: Dictionary = _gs.player_club()["finances"]
		fin["balance"] = int(fin["balance"]) + refund
		fin["transfer_budget"] = int(fin.get("transfer_budget", 0)) + refund
		_gs.inventory_changed.emit()
	exp["attempts_left"] = 0
	exp["recalled"] = true
	exp["refund"] = refund
	var covered := int(exp["days_in_phase"]) if str(exp["phase"]) == "travel_out" else int(exp["travel_days"])
	exp["phase"] = "travel_home"
	exp["days_in_phase"] = int(exp["travel_days"]) - maxi(1, covered)
	_log(exp, "recall", I18n.t("Recall order received — the party breaks camp and turns for home."))
	_post_mail(_gs.current_date, I18n.t("Recall order sent to %s") % I18n.t(str(exp["route_name"])),
		I18n.t("%s acknowledges the recall: the party breaks camp at %s and heads home. Unused capture gear sold back for %s; the days already funded are not recoverable.") % [
			str(exp["leader"]), I18n.t(str(exp["route_name"])), AcademyService.format_money(refund)],
		{"cat": "scout", "exped_kind": "recall",
		"uid": "exped:recall:%s" % str(exp["id"]), "route_name": str(exp["route_name"])})
	expeditions_changed.emit()
	return ""


## What a recall would hand back right now (half the unspent gear).
func recall_refund(exp: Dictionary) -> int:
	return int(exp["attempts_left"]) * ATTEMPT_COST / 2


# ------------------------------------------------------------------ daily tick

func _tick_expedition(exp: Dictionary, date: String) -> void:
	exp["days_in_phase"] = int(exp["days_in_phase"]) + 1
	match str(exp["phase"]):
		"travel_out":
			if int(exp["days_in_phase"]) >= int(exp["travel_days"]):
				exp["phase"] = "field"
				exp["days_in_phase"] = 0
		"field":
			exp["day_no"] = int(exp["day_no"]) + 1
			_run_field_day(exp, date)
			if int(exp["day_no"]) >= int(exp["field_days"]):
				exp["phase"] = "travel_home"
				exp["days_in_phase"] = 0
		"travel_home":
			if int(exp["days_in_phase"]) >= int(exp["travel_days"]):
				_arrive_home(exp, date)


## One worked day on the route: encounters roll off (career_seed, id, date) —
## deterministic; leader skill lifts rare odds, catch odds and IV quality.
func _run_field_day(exp: Dictionary, date: String) -> void:
	var r := route(str(exp["route_id"]))
	knowledge[str(exp["route_id"])] = knowledge_days(str(exp["route_id"])) + 1
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_gs.career_seed) + hash("exped|%s|%s" % [str(exp["id"]), date])
	var ap: Dictionary = APPROACHES[str(exp["approach"])]
	var skill := int(exp["leader_skill"])
	var events: Array = []
	if rng.randf() < float(ap["mishap"]):
		exp["mishaps"] = int(exp["mishaps"]) + 1
		events.append({"kind": "mishap", "species": "", "species_id": 0, "level": 0, "tier": ""})
	else:
		var n := rng.randi_range(int(ap["enc_lo"]), int(ap["enc_hi"]))
		for i in n:
			events.append(_roll_encounter(exp, r, rng, ap, skill))
	for ev in events:
		exp["log"].append({"date": date, "day": int(exp["day_no"]), "kind": str(ev["kind"]),
			"species": str(ev["species"]), "level": int(ev["level"]), "tier": str(ev["tier"])})
	if exp["log"].size() > 120:
		exp["log"] = exp["log"].slice(exp["log"].size() - 120)
	_post_mail(date, I18n.t("Field report: %s — day %d of %d") % [
		I18n.t(str(exp["route_name"])), int(exp["day_no"]), int(exp["field_days"])],
		_day_body(exp, events, date), _mail_extra(exp, "day", events))


func _roll_encounter(exp: Dictionary, r: Dictionary, rng: RandomNumberGenerator,
		ap: Dictionary, skill: int) -> Dictionary:
	var pool: Dictionary = r.get("pool", {})
	var tier := "common"
	var specials: Array = pool.get("special", [])
	if not specials.is_empty() and not bool(exp["special_seen"]) \
			and rng.randf() < 0.02 * (0.5 + float(skill) / 20.0):
		tier = "special"
		exp["special_seen"] = true
	else:
		var w_common := 68.0
		var w_uncommon := 26.0
		var w_rare := 6.0 * (0.7 + float(skill) / 20.0)   # sharp eyes find rare dens
		var roll := rng.randf() * (w_common + w_uncommon + w_rare)
		if roll >= w_common + w_uncommon:
			tier = "rare"
		elif roll >= w_common:
			tier = "uncommon"
	var ids: Array = pool.get(tier, [])
	if ids.is_empty():
		ids = pool.get("common", [1])
	var sid := int(ids[rng.randi_range(0, ids.size() - 1)])
	var sp: Dictionary = DataStore.species(sid)
	var lv := rng.randi_range(int(r["levels"][0]), int(r["levels"][1]))
	if tier == "special":
		lv = int(r["levels"][1]) + rng.randi_range(0, 2)
	var ev := {"kind": "sight", "species": str(sp.get("name", "?")), "species_id": sid,
		"level": lv, "tier": tier}
	exp["sightings"] = int(exp["sightings"]) + 1
	if int(exp["attempts_left"]) <= 0:
		return ev
	# Approach decides which sightings are worth spending gear on.
	var try_it := true
	match str(exp["approach"]):
		"cautious":
			try_it = tier != "common" or rng.randf() < 0.25
		"balanced":
			try_it = tier != "common" or rng.randf() < 0.55
		"aggressive":
			try_it = true
	if not try_it:
		return ev
	exp["attempts_left"] = int(exp["attempts_left"]) - 1
	var p := float(CATCH_BASE[tier]) + float(ap["catch_mod"])
	p *= 0.75 + float(skill) * 0.025
	p = clampf(p, 0.05, 0.95)
	if rng.randf() < p:
		ev["kind"] = "catch"
		var mon := _build_capture(exp, sid, lv, tier, rng)
		(exp["captures"] as Array).append(mon)
	else:
		ev["kind"] = "near"
		exp["near_misses"] = int(exp["near_misses"]) + 1
	return ev


# ------------------------------------------------------------------ captures

## Roll the captured mon. IV quality scales with leader skill (each stat keeps
## the best of several rolls); specials are exceptional specimens (IV floor).
func _build_capture(exp: Dictionary, sid: int, lv: int, tier: String,
		rng: RandomNumberGenerator) -> Dictionary:
	var sp: Dictionary = DataStore.species(sid)
	var skill := int(exp["leader_skill"])
	var ivs := {}
	var iv_rolls := 1 + skill / 7
	for k in STAT_KEYS:
		var best := 0
		for i in iv_rolls:
			best = maxi(best, rng.randi_range(0, 15))
		if tier == "special":
			best = maxi(best, 10 + rng.randi_range(0, 5))
		ivs[k] = best
	var learn: Array = sp.get("learnset", [])
	var count := clampi(1 + lv / 8, 2, 4)
	var moves: Array = []
	for mv in learn:
		if moves.size() >= count:
			break
		moves.append(mv)
	var nk: Array = DataStore.natures.keys()
	nk.sort()
	var pot_base: int = {"common": 4, "uncommon": 6, "rare": 9, "special": 13}[tier]
	var pot: int = clampi(pot_base + rng.randi_range(0, 6) + skill / 8, 1, 20)
	var err := (20 - skill) / 5
	var centre := clampi(pot + rng.randi_range(-err, err), 1, 20)
	var half_w := 2 + (20 - skill) / 6
	var pot_min := clampi(centre - half_w, 1, 20)
	var pot_max := clampi(centre + half_w, pot_min + 2, 20)
	var mon := {
		"uid": "expd%04d" % next_uid, "species_id": sid, "species": str(sp["name"]),
		"level": lv, "ivs": ivs, "moves": moves,
		"nature": str(nk[rng.randi_range(0, nk.size() - 1)]),
		"ability": str(sp.get("ability", "")),
		"age_months": maxi(6, lv) + rng.randi_range(0, 8),
		"potential": pot, "pot_min": pot_min, "pot_max": pot_max,
		"tier": tier, "caught_route": str(exp["route_name"]),
		"caught_date": str(_gs.current_date), "caught_by": str(exp["leader"]),
		"dest": str(exp["dest"]),
	}
	next_uid += 1
	return mon


## Party home: deliver captures, settle knowledge/cooldown, file the report.
func _arrive_home(exp: Dictionary, date: String) -> void:
	expeditions.erase(exp)
	cooldowns[str(exp["route_id"])] = Season.date_add(date, COOLDOWN_DAYS)
	var placements: Array = []
	for mon in exp["captures"]:
		placements.append({"uid": str(mon["uid"]), "species": str(mon["species"]),
			"level": int(mon["level"]), "tier": str(mon["tier"]),
			"where": _deliver(mon, str(exp["dest"]), date)})
	if str(exp["leader_id"]) == "manager":
		for m in _gs.player_club()["squad"]:
			m["morale"] = clampi(int(m.get("morale", 70)) + 1, 0, 100)
	var entry := {
		"id": str(exp["id"]), "route_id": str(exp["route_id"]),
		"route_name": str(exp["route_name"]), "region": str(exp["region"]),
		"leader": str(exp["leader"]), "leader_role": str(exp["leader_role"]),
		"approach": str(exp["approach"]), "started": str(exp["started"]), "ended": date,
		"field_days": int(exp["field_days"]), "cost": int(exp["cost"]),
		"sightings": int(exp["sightings"]), "near_misses": int(exp["near_misses"]),
		"mishaps": int(exp["mishaps"]),
		"recalled": bool(exp.get("recalled", false)),
		"captures": placements,
	}
	history.push_front(entry)
	if history.size() > 40:
		history.resize(40)
	_post_mail(date, I18n.t("Expedition returns: %s (%d caught)") % [
		I18n.t(str(exp["route_name"])), placements.size()],
		_final_body(exp, placements), _mail_extra(exp, "final", []))


## Route a captured mon home. Preferred destination first, the other as
## fallback; if the club is bursting it waits in the holding pen.
## Returns "academy" | "squad" | "holding".
func _deliver(mon: Dictionary, dest: String, date: String) -> String:
	var order := ["academy", "squad"] if dest == "academy" else ["squad", "academy"]
	for where in order:
		if where == "academy" and _academy_place(mon, date):
			return "academy"
		if where == "squad" and _squad_place(mon, date):
			return "squad"
	mon["held_since"] = date
	holding.append(mon)
	return "holding"


func _academy_place(mon: Dictionary, date: String) -> bool:
	var aca: RefCounted = AcademyService.active
	if aca == null or aca.roster.size() >= aca.roster_cap():
		return false
	var m := mon.duplicate(true)
	m["joined"] = date
	m["focus"] = "balanced"
	m["xp"] = 0.0
	m["from_expedition"] = true
	m["stars"] = _rough_stars(m)
	aca.roster.append(m)
	if aca.has_signal("academy_changed"):
		aca.academy_changed.emit()
	return true


func _squad_place(mon: Dictionary, date: String) -> bool:
	var squad: Array = _gs.player_club()["squad"]
	if squad.size() >= FIRST_TEAM_CAP:
		return false
	var sp: Dictionary = DataStore.species(int(mon["species_id"]))
	var bst := 0
	for k in sp.get("base", {}):
		bst += int(sp["base"][k])
	var yr := int(date.substr(0, 4)) + 3
	squad.append({
		"uid": str(mon["uid"]), "species_id": int(mon["species_id"]),
		"species": str(mon["species"]), "nickname": null, "level": int(mon["level"]),
		"ivs": (mon["ivs"] as Dictionary).duplicate(), "moves": (mon["moves"] as Array).duplicate(),
		"held_item": null, "condition": 80, "fitness": 85, "morale": 80,
		"age_months": int(mon["age_months"]),
		"contract": {"salary": int(float(bst) * 1.5 + float(int(mon["level"])) * 40.0),
			"expiry": "%04d-06-30" % yr},
		"nature": str(mon["nature"]), "ability": str(mon["ability"]),
		"potential": int(mon["potential"]), "from_expedition": true,
	})
	return true


## Same current-ability heuristic the academy uses for its star meter.
func _rough_stars(m: Dictionary) -> float:
	var sp: Dictionary = DataStore.species(int(m["species_id"]))
	var bst := 0
	for k in sp.get("base", {}):
		bst += int(sp["base"][k])
	var iv_sum := 0
	for k in m.get("ivs", {}):
		iv_sum += int(m["ivs"][k])
	var v := 0.5 + float(int(m["level"]) - 3) * 0.16 + float(bst) / 450.0 * 1.5 \
		+ float(iv_sum) / 90.0 * 0.8
	return clampf(snappedf(v, 0.5), 0.5, 5.0)


## Holding pen: mons that came home to a full club land when space opens.
func _place_holding(date: String) -> void:
	if holding.is_empty():
		return
	for mon in holding.duplicate():
		var where := ""
		var order := ["academy", "squad"] if str(mon.get("dest", "academy")) == "academy" else ["squad", "academy"]
		for w in order:
			if w == "academy" and _academy_place(mon, date):
				where = "academy"
				break
			if w == "squad" and _squad_place(mon, date):
				where = "squad"
				break
		if where != "":
			holding.erase(mon)
			_post_mail(date, I18n.t("%s has settled in at the club") % str(mon["species"]),
				I18n.t("The %s caught on the %s expedition finally has a place: it joins the %s today.") % [
					str(mon["species"]), I18n.t(str(mon["caught_route"])),
					I18n.t("academy") if where == "academy" else I18n.t("first-team squad")],
				{"cat": "scout", "exped_kind": "placed",
				"uid": "exped:placed:%s:%s" % [date, str(mon["uid"])],
				"species": str(mon["species"]), "where": where})


# ------------------------------------------------------------------ AI expeditions

## AI clubs quietly run their own trips: a seeded daily roll drops a capture
## into a club's squad depth and the press reports the notable ones — the
## world keeps hunting even when you don't. Deterministic per (seed, date, club).
func _ai_daily(date: String) -> void:
	for c in _gs.world["clubs"]:
		if _gs.is_player_club(str(c["id"])):
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = int(_gs.career_seed) + hash("expedai|%s|%s" % [date, str(c["id"])])
		if rng.randf() > 0.012:
			continue
		if (c["squad"] as Array).size() >= 22:
			continue
		var pool := region_routes(str(c.get("league", "kanto")))
		if pool.is_empty():
			continue
		var r: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
		var tier := "common"
		var t_roll := rng.randf()
		if t_roll > 0.93:
			tier = "rare"
		elif t_roll > 0.70:
			tier = "uncommon"
		var ids: Array = r["pool"].get(tier, r["pool"]["common"])
		var sid := int(ids[rng.randi_range(0, ids.size() - 1)])
		var sp: Dictionary = DataStore.species(sid)
		var lv := rng.randi_range(int(r["levels"][0]), int(r["levels"][1]))
		var ivs := {}
		for k in STAT_KEYS:
			ivs[k] = rng.randi_range(0, 15)
		var learn: Array = sp.get("learnset", [])
		var moves: Array = []
		for mv in learn:
			if moves.size() >= clampi(1 + lv / 8, 2, 4):
				break
			moves.append(mv)
		var nk: Array = DataStore.natures.keys()
		nk.sort()
		var bst := 0
		for k in sp.get("base", {}):
			bst += int(sp["base"][k])
		(c["squad"] as Array).append({
			"uid": "expai%s%04d" % [str(c["id"]).substr(4), ai_captures + 1],
			"species_id": sid, "species": str(sp["name"]), "nickname": null,
			"level": lv, "ivs": ivs, "moves": moves, "held_item": null,
			"condition": 80, "fitness": 85, "morale": 75,
			"age_months": maxi(6, lv) + rng.randi_range(0, 8),
			"contract": {"salary": int(float(bst) * 1.2 + float(lv) * 30.0),
				"expiry": "%04d-06-30" % (int(date.substr(0, 4)) + 2)},
			"nature": str(nk[rng.randi_range(0, nk.size() - 1)]),
			"ability": str(sp.get("ability", "")), "from_expedition": true,
		})
		ai_captures += 1
		if tier != "common" or rng.randf() < 0.25:
			_post_mail(date, I18n.t("Wild capture: %s land a %s") % [str(c["name"]), str(sp["name"])],
				I18n.t("Word from %s: an expedition party sent to %s has returned with a Lv %d %s for the club's development ranks. Rival recruitment never sleeps.") % [
					str(c["name"]), I18n.t(str(r["name"])), lv, str(sp["name"])],
				{"cat": "media", "exped_kind": "ai_news",
				"uid": "exped:ai:%s:%s" % [date, str(c["id"])],
				"club": str(c["name"]), "species": str(sp["name"]),
				"level": lv, "tier": tier, "route_name": str(r["name"])})


# ------------------------------------------------------------------ mail bodies

## Report-line banks. English templates are the catalog keys (the es catalog
## carries the Spanish line for each); {slots} are filled after translation.
## Variety follows the people_gen recency pattern: a line used within
## RECENT_WINDOW days is excluded, else least-recently-used wins.
const LINES := {
	"arrive": [
		"The party has pitched camp at {route}. {leader} likes the look of the terrain.",
		"Camp is up at {route}; trails were marked before sundown.",
		"{leader} reports the party safely arrived and glassing {route} at first light.",
	],
	"sight": [
		"Tracked a Lv {lv} {species} through the {terrain} — logged for the files, no gear spent.",
		"A Lv {lv} {species} crossed the trail at dawn; the party held back and took notes.",
		"Spotted a Lv {lv} {species} from the ridge. {leader} judged it not worth the gear.",
		"A {species} (Lv {lv}) kept its distance all afternoon; sketches and prints archived.",
		"Fresh {species} signs everywhere — one Lv {lv} specimen observed at length.",
	],
	"near": [
		"Cornered a Lv {lv} {species} but it slipped the net at the last instant. Gear spent.",
		"A Lv {lv} {species} broke for the undergrowth mid-attempt — so close {leader} could taste it.",
		"Failed attempt on a Lv {lv} {species}; it outlasted the snare and vanished.",
		"The Lv {lv} {species} fought free of the capture ring. One attempt written off.",
		"Had a Lv {lv} {species} half-secured before it wriggled loose. The team is furious.",
	],
	"catch": [
		"CAPTURE — a Lv {lv} {species} secured cleanly. {leader} rates it {stars}.",
		"CAPTURE — the party brought in a Lv {lv} {species} after a long stalk.",
		"CAPTURE — Lv {lv} {species} netted at dusk; calm in the travel crate already.",
		"CAPTURE — a Lv {lv} {species} taken on the first pass. Textbook work.",
		"CAPTURE — Lv {lv} {species} secured after a two-hour standoff.",
	],
	"catch_special": [
		"EXCEPTIONAL CAPTURE — a Lv {lv} {species}! {leader} says finds like this come once a career.",
		"EXCEPTIONAL CAPTURE — the rumours were true: a Lv {lv} {species} is in the crate.",
	],
	"sight_special": [
		"Unconfirmed sighting of something extraordinary — {leader} swears it was a {species}.",
		"The locals spoke of a {species} in these parts; today the party saw it with their own eyes.",
	],
	"mishap": [
		"A rough day: the party was chased off its grid by an angry swarm. No fieldwork logged.",
		"Storms flooded the camp overnight; the day went to repairs, not scouting.",
		"A wrong turn cost the whole day — {leader} takes the blame and promises better tomorrow.",
	],
	"quiet": [
		"A quiet day on {route} — trails cold, hides empty. It happens.",
		"Nothing worth the logbook today; the party rotated to fresh ground for tomorrow.",
		"Long hours, no encounters. {leader} suspects the weather pushed everything to ground.",
	],
}


func _load_used_ok(tid: String, date: String) -> bool:
	for e in _used_lines:
		if str(e["tid"]) == tid and absi(Season.days_between(str(e["date"]), date)) <= RECENT_WINDOW:
			return false
	return true


## people_gen-style pick: fresh lines first, else least-recently-used.
func _pick_line(key: String, rng: RandomNumberGenerator, date: String) -> String:
	var bank: Array = LINES.get(key, ["..."])
	var fresh: Array = []
	for i in bank.size():
		if _load_used_ok("%s.%d" % [key, i], date):
			fresh.append(i)
	var idx := 0
	if not fresh.is_empty():
		idx = int(fresh[rng.randi_range(0, fresh.size() - 1)])
	else:
		var best_last := "9999-99-99"
		for i in bank.size():
			var last := ""
			for e in _used_lines:
				if str(e["tid"]) == "%s.%d" % [key, i] and str(e["date"]) > last:
					last = str(e["date"])
			if last < best_last:
				best_last = last
				idx = i
	_used_lines.append({"tid": "%s.%d" % [key, idx], "date": date})
	if _used_lines.size() > 220:
		_used_lines = _used_lines.slice(_used_lines.size() - 220)
	return str(bank[idx])


func _day_body(exp: Dictionary, events: Array, date: String) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_gs.career_seed) + hash("expedtxt|%s|%s" % [str(exp["id"]), date])
	var r := route(str(exp["route_id"]))
	var terrain := I18n.t(str((r.get("terrain", ["wilds"]) as Array)[0]))
	var params := {"route": I18n.t(str(exp["route_name"])), "leader": str(exp["leader"]),
		"terrain": terrain, "species": "", "lv": 0, "stars": ""}
	var lines: Array = []
	if int(exp["day_no"]) == 1:
		lines.append(I18n.t(_pick_line("arrive", rng, date)).format(params))
	if events.is_empty():
		lines.append(I18n.t(_pick_line("quiet", rng, date)).format(params))
	for ev in events:
		var key := ""
		match str(ev["kind"]):
			"mishap":
				key = "mishap"
			"sight":
				key = "sight_special" if str(ev["tier"]) == "special" else "sight"
			"near":
				key = "near"
			"catch":
				key = "catch_special" if str(ev["tier"]) == "special" else "catch"
		var p := params.duplicate()
		p["species"] = str(ev["species"])
		p["lv"] = int(ev["level"])
		p["stars"] = I18n.t("a real find") if str(ev["tier"]) != "common" else I18n.t("solid stock")
		lines.append(I18n.t(_pick_line(key, rng, date)).format(p))
	lines.append("")
	lines.append(I18n.t("Capture gear left: %d of %d. Captures so far: %d.") % [
		int(exp["attempts_left"]), int(exp["attempts_bought"]),
		(exp["captures"] as Array).size()])
	return "\n".join(lines)


func _final_body(exp: Dictionary, placements: Array) -> String:
	var lines: Array = []
	if bool(exp.get("recalled", false)):
		lines.append(I18n.t("The party returned early on your recall order (%s recovered from unused gear).") % AcademyService.format_money(int(exp.get("refund", 0))))
	lines.append(I18n.t("%s is back from %s: %d days in the field, %d sightings, %d capture(s), %d near miss(es). Total cost %s.") % [
		str(exp["leader"]), I18n.t(str(exp["route_name"])), int(exp["field_days"]),
		int(exp["sightings"]), placements.size(), int(exp["near_misses"]),
		AcademyService.format_money(int(exp["cost"]))])
	for pl in placements:
		var where: String
		match str(pl["where"]):
			"academy":
				where = I18n.t("joins the academy")
			"squad":
				where = I18n.t("goes straight into the first-team squad")
			_:
				where = I18n.t("waits in the holding pen until a bed opens")
		lines.append(I18n.t("- Lv %d %s — %s.") % [int(pl["level"]), str(pl["species"]), where])
	if placements.is_empty():
		lines.append(I18n.t("The crates came home empty this time — the intel gathered still sharpens our picture of the route."))
	lines.append(I18n.t("Route knowledge updated. %s reopens for expeditions on %s.") % [
		I18n.t(str(exp["route_name"])), I18n.pretty_date(str(cooldowns.get(str(exp["route_id"]), "")))])
	return "\n".join(lines)


## Inbox mail with routing key + JSON-safe snapshot (academy _post_mail
## pattern: report_gen routes exped mails to screens/routes/mail_gen.gd, and
## arriving WITH a cat skips news_gen enrichment; the plain body remains a
## faithful fallback).
func _post_mail(date: String, title: String, body: String, extra: Dictionary) -> void:
	_gs.add_inbox_message(date, title, body)
	var m: Dictionary = _gs.inbox[0]
	if str(m.get("title", "")) == title:
		if not extra.has("cat"):
			extra["cat"] = "scout"
		m.merge(extra, true)
		_gs.inbox_updated.emit()


func _mail_extra(exp: Dictionary, kind: String, events: Array) -> Dictionary:
	var evs: Array = []
	for ev in events:
		var sp: Dictionary = DataStore.species(int(ev.get("species_id", 0)))
		evs.append({"kind": str(ev["kind"]), "species": str(ev["species"]),
			"level": int(ev["level"]), "tier": str(ev["tier"]),
			"types": (sp.get("types", []) as Array).duplicate()})
	var caps: Array = []
	for mon in exp.get("captures", []):
		caps.append({"species": str(mon["species"]), "level": int(mon["level"]),
			"tier": str(mon["tier"]), "pot_min": int(mon["pot_min"]),
			"pot_max": int(mon["pot_max"]), "nature": str(mon["nature"])})
	return {"cat": "scout", "exped_kind": kind,
		"uid": "exped:%s:%s:%s" % [kind, str(exp["id"]), str(_gs.current_date)],
		"exp_id": str(exp["id"]), "route_name": str(exp["route_name"]),
		"region": str(exp["region"]), "leader": str(exp["leader"]),
		"leader_role": str(exp["leader_role"]), "approach": str(exp["approach"]),
		"day_no": int(exp["day_no"]), "field_days": int(exp["field_days"]),
		"attempts_left": int(exp["attempts_left"]),
		"attempts_bought": int(exp["attempts_bought"]),
		"cost": int(exp["cost"]), "dest": str(exp["dest"]),
		"events": evs, "captures": caps}


func _log(exp: Dictionary, kind: String, text: String) -> void:
	exp["log"].append({"date": str(_gs.current_date), "day": 0, "kind": kind,
		"species": "", "level": 0, "tier": "", "note": text})
