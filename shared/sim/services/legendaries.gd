extends RefCounted
class_name LegendaryService
## LegendaryService — rare legendary sighting events (legendary events piece).
## Auto-loaded by the GameState services convention; ticked daily; state rides
## world.meta.services.legendaries. Builds on ExpeditionService (leaders,
## capture delivery) and shared/data/legendaries.json.
##
## Model (deterministic off GameState.career_seed):
##  - 1-2 sightings fire per season, league-wide, on a schedule derived purely
##    from (career_seed, season_no) — save/load safe, no stored clock.
##  - A sighting opens a LIMITED WINDOW (5-8 days): a press piece + urgent
##    mail announce it, the site appears on the Routes screen, and the club
##    may mount ONE special expedition (premium flat cost, best leader only,
##    reputation gate). Johto's beasts ROAM: they are sighted near a route,
##    can escape mid-hunt and resurface later in the season.
##  - Capture odds are LOW (single-digit % base) — modified by leader skill,
##    approach, academy facility level and scouting knowledge from previous
##    failed attempts (odds tick up every time you go home empty-handed).
##  - Success: the legendary joins (squad/academy choice), massive press,
##    board delight, squad morale, permanent legendary record. Failure: a
##    narrative field report + partial scouting knowledge. Expired windows the
##    player declined are rarely attempted by AI clubs (press if they land it).

signal legendaries_changed

static var active = null

const DATA_PATH := "res://shared/data/legendaries.json"
const SEASON_LAST_OFFSET := 200      # sightings fire within season_start+14..+200
const RESURFACE_MAX_OFFSET := 240    # roamers only resurface inside the season
const ODDS_SKILL := 0.003            # per leader skill point over 10
const ODDS_FACILITY := 0.004         # per academy facility level over 1
const ODDS_ATTEMPT := 0.015          # scouting: per prior failed attempt
const ODDS_ATTEMPT_CAP := 0.06
const APPROACH_ODDS := {"cautious": 0.01, "balanced": 0.0, "aggressive": -0.01}
const APPROACH_CONTACT := {"cautious": -0.06, "balanced": 0.0, "aggressive": 0.12}
const APPROACH_ESCAPE := {"cautious": 0.10, "balanced": 0.18, "aggressive": 0.30}
const AI_ATTEMPT_CHANCE := 0.3       # a declined window tempts a rival club...
const AI_SUCCESS_CHANCE := 0.10      # ...and they land it very rarely
const STAT_KEYS := ["hp", "atk", "def", "spa", "spd", "spe"]

static var _data_cache: Array = []
static var _data_by_id: Dictionary = {}

var sightings: Array = []    # newest-first [{uid, leg_id, date, window_end, roam_route, status, resurfaced, season, attempted}]
var hunt: Dictionary = {}    # the (single) active special expedition; {} = none
var attempts: Dictionary = {}  # leg_id -> failed player hunts (scouting knowledge)
var captured: Dictionary = {}  # leg_id -> {by, club, date, where, uid, level}
var resurface: Array = []    # [{leg_id, date, uid}]
var log: Array = []          # permanent legendary record, newest-first
var next_uid: int = 1
var _gs = null


# ------------------------------------------------------------------ static data

static func all_legendaries() -> Array:
	if _data_cache.is_empty():
		var f := FileAccess.open(DATA_PATH, FileAccess.READ)
		if f != null:
			var data: Variant = JSON.parse_string(f.get_as_text())
			if data is Dictionary:
				_data_cache = data.get("legendaries", [])
				for l in _data_cache:
					_data_by_id[str(l["id"])] = l
	return _data_cache


static func legendary(leg_id: String) -> Dictionary:
	all_legendaries()
	return _data_by_id.get(leg_id, {})


# ------------------------------------------------------------------ service hooks

func service_id() -> String:
	return "legendaries"


func on_career_started(gs) -> void:
	_gs = gs
	active = self
	all_legendaries()
	if not gs.season_rolled.is_connected(_on_season_rolled):
		gs.season_rolled.connect(_on_season_rolled)
	legendaries_changed.emit()


func on_day(gs, date: String) -> void:
	_gs = gs
	_fire_scheduled(date)
	_fire_resurfaces(date)
	if not hunt.is_empty():
		_tick_hunt(date)
	_expire_windows(date)
	legendaries_changed.emit()


func save_state() -> Dictionary:
	return {"sightings": sightings.duplicate(true), "hunt": hunt.duplicate(true),
		"attempts": attempts.duplicate(true), "captured": captured.duplicate(true),
		"resurface": resurface.duplicate(true), "log": log.duplicate(true),
		"next_uid": next_uid}


func load_state(state: Dictionary) -> void:
	sightings = state.get("sightings", [])
	hunt = state.get("hunt", {})
	resurface = state.get("resurface", [])
	log = state.get("log", [])
	next_uid = int(state.get("next_uid", 1))
	attempts = {}
	var at: Dictionary = state.get("attempts", {})
	for k in at:
		attempts[str(k)] = int(at[k])
	captured = state.get("captured", {})
	for s in sightings:
		for k in ["window_days", "season"]:
			s[k] = int(s.get(k, 0))
		s["attempted"] = bool(s.get("attempted", false))
		s["resurfaced"] = bool(s.get("resurfaced", false))
	if not hunt.is_empty():
		for k in ["travel_days", "hunt_days", "day_no", "days_in_phase", "cost",
				"leader_skill", "contacts"]:
			hunt[k] = int(hunt.get(k, 0))
		hunt["odds"] = float(hunt.get("odds", 0.05))
	for e in log:
		e["season"] = int(e.get("season", 1))
		e["level"] = int(e.get("level", 0))


# ------------------------------------------------------------------ schedule

## The season's sighting schedule is a PURE function of (career_seed,
## season_no): 1-2 events, each a legendary + a fire date + a window length.
## Captured legendaries are skipped for the next candidate in the shuffle, so
## the schedule stays deterministic whatever the world state.
func season_schedule() -> Array:
	var season := int(_gs.season_no())
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_gs.career_seed) + hash("legsched|%d" % season)
	var n := 1 + (1 if rng.randf() < 0.55 else 0)
	var order: Array = []
	for l in all_legendaries():
		if season >= int(l.get("min_season", 1)):
			order.append(str(l["id"]))
	# seeded Fisher-Yates
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = order[i]
		order[i] = order[j]
		order[j] = tmp
	var out: Array = []
	for i in n:
		var offset := 14 + rng.randi_range(0, SEASON_LAST_OFFSET - 14)
		var window := rng.randi_range(5, 8)
		if i < order.size():
			out.append({"idx": i, "leg_id": order[i],
				"date": Season.date_add(str(_gs.season_start), offset),
				"window_days": window})
	return out


func _fire_scheduled(date: String) -> void:
	for ev in season_schedule():
		if str(ev["date"]) != date:
			continue
		var leg_id := str(ev["leg_id"])
		# captured legendaries never resurface: hand the slot to the next
		# uncaptured candidate so seasons stay lively (still deterministic).
		if captured.has(leg_id):
			for alt in all_legendaries():
				var aid := str(alt["id"])
				if not captured.has(aid) and int(_gs.season_no()) >= int(alt.get("min_season", 1)):
					leg_id = aid
					break
			if captured.has(leg_id):
				continue
		var sched_uid := "s%d.%d" % [int(_gs.season_no()), int(ev["idx"])]
		if _sighting_by_uid(sched_uid) != null:
			continue
		_spawn_sighting(leg_id, date, int(ev["window_days"]), sched_uid, false)


func _fire_resurfaces(date: String) -> void:
	for r in resurface.duplicate():
		if str(r["date"]) != date:
			continue
		resurface.erase(r)
		if captured.has(str(r["leg_id"])):
			continue
		_spawn_sighting(str(r["leg_id"]), date, 6, str(r["uid"]), true)


func _sighting_by_uid(uid: String):
	for s in sightings:
		if str(s["uid"]) == uid:
			return s
	return null


## Spawn a sighting window + the press piece (fires exactly once per uid).
func _spawn_sighting(leg_id: String, date: String, window_days: int,
		sched_uid: String, resurfaced: bool) -> void:
	var leg := legendary(leg_id)
	if leg.is_empty() or captured.has(leg_id):
		return
	var roam_route := ""
	if bool(leg.get("roaming", false)):
		var jroutes := ExpeditionService.region_routes(str(leg["region"]))
		if not jroutes.is_empty():
			var rng := RandomNumberGenerator.new()
			rng.seed = int(_gs.career_seed) + hash("legroam|%s" % sched_uid)
			roam_route = str(jroutes[rng.randi_range(0, jroutes.size() - 1)]["name"])
	var s := {"uid": sched_uid, "leg_id": leg_id, "date": date,
		"window_end": Season.date_add(date, window_days - 1),
		"window_days": window_days, "roam_route": roam_route,
		"status": "active", "resurfaced": resurfaced, "attempted": false,
		"season": int(_gs.season_no())}
	sightings.push_front(s)
	if sightings.size() > 24:
		sightings.resize(24)
	var site := site_label(s)
	var title := I18n.t("PRESS: %s sighted near %s!") % [str(leg["name"]), site] \
		if roam_route != "" else I18n.t("PRESS: %s sighted at %s!") % [str(leg["name"]), site]
	if resurfaced:
		title = I18n.t("PRESS: %s has resurfaced near %s!") % [str(leg["name"]), site]
	var body := I18n.t("Trainers across the region are talking about one thing only: a confirmed sighting of the legendary %s. Field experts believe the trail stays warm for %d days at most — a club with the nerve (and the budget) could mount a special expedition before it goes cold. Capture chances are minimal. Nobody cares: this is %s.") % [
		str(leg["name"]), window_days, str(leg["name"])]
	_post_mail(date, title, body, {"cat": "media", "urgent": true,
		"exped_kind": "leg_sighting", "uid": "exped:leg:sight:%s" % sched_uid,
		"leg_id": leg_id, "leg_name": str(leg["name"]), "site": site,
		"window_end": str(s["window_end"]), "window_days": window_days,
		"resurfaced": resurfaced,
		"types": (DataStore.species(int(leg["species_id"])).get("types", []) as Array).duplicate()})
	_log_entry("sighting", leg_id, date, {"site": site})


# ------------------------------------------------------------------ queries

func active_sightings() -> Array:
	return sightings.filter(func(s): return str(s["status"]) == "active")


func find_sighting(uid: String) -> Dictionary:
	var s = _sighting_by_uid(uid)
	return s if s != null else {}


## Where the trail is: the fixed site, or "near <route>" for roamers.
func site_label(s: Dictionary) -> String:
	if str(s.get("roam_route", "")) != "":
		return I18n.t(str(s["roam_route"]))
	return I18n.t(str(legendary(str(s["leg_id"])).get("site", "?")))


## Days of the window still open, counting today. 0 = closed.
func days_left(s: Dictionary) -> int:
	if str(s["status"]) != "active" or _gs == null:
		return 0
	return maxi(0, Season.days_between(str(_gs.current_date), str(s["window_end"])) + 1)


## The hunt demands your very best: the top judging skill on the books.
func best_leader_skill() -> int:
	var exped: RefCounted = ExpeditionService.active
	if exped == null:
		return 0
	var best := 0
	for l in exped.leaders():
		best = maxi(best, int(l["skill"]))
	return best


func leader_on_hunt(leader_id: String) -> bool:
	return not hunt.is_empty() and str(hunt.get("leader_id", "")) == leader_id


## Live capture odds for a plan — low by design. Returns the breakdown too so
## the planner can show WHY the number is what it is.
func odds_quote(leg_id: String, leader_skill: int, approach: String) -> Dictionary:
	var leg := legendary(leg_id)
	var base := float(leg.get("base_odds", 0.05))
	var skill_mod := ODDS_SKILL * float(leader_skill - 10)
	var fac_level := 1
	if AcademyService.active != null:
		fac_level = int(AcademyService.active.facility_level)
	var fac_mod := ODDS_FACILITY * float(fac_level - 1)
	var scout_mod: float = minf(ODDS_ATTEMPT_CAP, ODDS_ATTEMPT * float(int(attempts.get(leg_id, 0))))
	var ap_mod := float(APPROACH_ODDS.get(approach, 0.0))
	var total: float = clampf(base + skill_mod + fac_mod + scout_mod + ap_mod, 0.02, 0.35)
	return {"base": base, "skill": skill_mod, "facility": fac_mod,
		"scouting": scout_mod, "approach": ap_mod, "total": total,
		"prior_attempts": int(attempts.get(leg_id, 0))}


## Flat premium cost of the special expedition (site cost, gear included).
func hunt_cost(leg_id: String) -> int:
	return int(legendary(leg_id).get("cost", 20000))


func travel_days_to(leg_id: String) -> int:
	var leg := legendary(leg_id)
	var region := "kanto"
	if _gs != null:
		region = str(_gs.player_league_id())
	return int(leg.get("travel", {}).get(region, 3))


## Why can't this hunt launch right now? "" = it can.
func hunt_blocker(sighting_uid: String, leader_id: String = "") -> String:
	var s := find_sighting(sighting_uid)
	if s.is_empty() or str(s["status"]) != "active" or captured.has(str(s.get("leg_id", ""))):
		return I18n.t("The trail has gone cold — the window is closed.")
	if not hunt.is_empty():
		return I18n.t("The special task force is already in the field.")
	var leg := legendary(str(s["leg_id"]))
	var rep := int(_gs.player_club().get("reputation", 10))
	if rep < int(leg.get("min_rep", 10)):
		return I18n.t("The club's reputation (%d/20) is too low — %d needed before anyone sells us this trail.") % [rep, int(leg.get("min_rep", 10))]
	var travel := travel_days_to(str(s["leg_id"]))
	if days_left(s) - travel < 1:
		return I18n.t("Too far: the trail would be %d day(s) cold before the party arrived.") % maxi(1, travel - days_left(s) + 1)
	var exped: RefCounted = ExpeditionService.active
	if leader_id != "":
		var best := best_leader_skill()
		var lskill := -1
		for l in exped.leaders():
			if str(l["id"]) == leader_id:
				lskill = int(l["skill"])
		if lskill < best:
			return I18n.t("A hunt like this demands your very best leader (judging %d/20).") % best
		if exped._leader_busy(leader_id):
			return I18n.t("That leader is already out on an expedition.")
	var cost := hunt_cost(str(s["leg_id"]))
	var fin: Dictionary = _gs.player_club()["finances"]
	var spendable := mini(int(fin["balance"]), int(fin.get("transfer_budget", 0)))
	if spendable < cost:
		return I18n.t("Not enough transfer budget — %s %d needed, %s %d released by the board.") % [
			_gs.world["meta"]["currency"], cost, _gs.world["meta"]["currency"], maxi(0, spendable)]
	return ""


# ------------------------------------------------------------------ the hunt

## Mount the special expedition. Returns "" or an error string.
func start_hunt(sighting_uid: String, leader_id: String, approach: String,
		dest: String = "squad") -> String:
	var blocker := hunt_blocker(sighting_uid, leader_id)
	if blocker != "":
		return blocker
	if not APPROACH_ODDS.has(approach):
		return I18n.t("Pick an approach: cautious, balanced or aggressive.")
	if dest != "academy" and dest != "squad":
		return I18n.t("Captures must be routed to the academy or the squad.")
	var s := find_sighting(sighting_uid)
	var leg := legendary(str(s["leg_id"]))
	var exped: RefCounted = ExpeditionService.active
	var leader := {}
	for l in exped.leaders():
		if str(l["id"]) == leader_id:
			leader = l
	if leader.is_empty():
		return I18n.t("Pick an expedition leader.")
	var cost := hunt_cost(str(s["leg_id"]))
	var fin: Dictionary = _gs.player_club()["finances"]
	fin["balance"] = int(fin["balance"]) - cost
	fin["transfer_budget"] = int(fin.get("transfer_budget", 0)) - cost
	_gs.inventory_changed.emit()
	var travel := travel_days_to(str(s["leg_id"]))
	var hunt_days := maxi(1, days_left(s) - travel)
	s["attempted"] = true
	hunt = {"id": "hunt%03d" % next_uid, "sighting_uid": sighting_uid,
		"leg_id": str(s["leg_id"]), "leg_name": str(leg["name"]),
		"site": site_label(s), "leader_id": leader_id,
		"leader": str(leader["name"]), "leader_role": str(leader["role"]),
		"leader_skill": int(leader["skill"]), "approach": approach, "dest": dest,
		"phase": "travel_out", "days_in_phase": 0, "day_no": 0,
		"travel_days": travel, "hunt_days": hunt_days, "cost": cost,
		"contacts": 0, "started": str(_gs.current_date), "outcome": "",
		"odds": float(odds_quote(str(s["leg_id"]), int(leader["skill"]), approach)["total"]),
		"log": []}
	next_uid += 1
	if leader_id == "manager":
		for m in _gs.player_club()["squad"]:
			m["morale"] = maxi(0, int(m.get("morale", 70)) - ExpeditionService.MANAGER_MORALE_COST)
	_post_mail(_gs.current_date, I18n.t("Special expedition departs: the hunt for %s") % str(leg["name"]),
		I18n.t("%s leads the club's finest into the field: destination %s, on the trail of %s (Lv %d). %s of travel, then every remaining day of the window on the hunt. Cost: %s, paid up front. The odds are terrible. Godspeed.") % [
			str(leader["name"]), site_label(s), str(leg["name"]), int(leg["level"]),
			I18n.np(travel, "%d day", "%d days"), AcademyService.format_money(cost)],
		_hunt_mail_extra("leg_depart", []))
	legendaries_changed.emit()
	return ""


func _tick_hunt(date: String) -> void:
	hunt["days_in_phase"] = int(hunt["days_in_phase"]) + 1
	match str(hunt["phase"]):
		"travel_out":
			if int(hunt["days_in_phase"]) >= int(hunt["travel_days"]):
				hunt["phase"] = "hunting"
				hunt["days_in_phase"] = 0
		"hunting":
			hunt["day_no"] = int(hunt["day_no"]) + 1
			_run_hunt_day(date)
			if not hunt.is_empty() and str(hunt["phase"]) == "hunting" \
					and int(hunt["day_no"]) >= int(hunt["hunt_days"]):
				hunt["phase"] = "travel_home"
				hunt["days_in_phase"] = 0
				if str(hunt["outcome"]) == "":
					hunt["outcome"] = "fail"
		"travel_home":
			if int(hunt["days_in_phase"]) >= int(hunt["travel_days"]):
				_finish_hunt(date)


## One day on the trail: maybe contact, then a LOW capture roll; roamers can
## bolt for good. Deterministic off (career_seed, hunt id, date).
func _run_hunt_day(date: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_gs.career_seed) + hash("leghunt|%s|%s" % [str(hunt["id"]), date])
	var leg := legendary(str(hunt["leg_id"]))
	var approach := str(hunt["approach"])
	var contact_p: float = clampf(0.4 + float(int(hunt["leader_skill"])) * 0.01
		+ float(APPROACH_CONTACT.get(approach, 0.0)), 0.1, 0.9)
	var line := ""
	var kind := "cold"
	if rng.randf() < contact_p:
		hunt["contacts"] = int(hunt["contacts"]) + 1
		if rng.randf() < float(hunt["odds"]):
			kind = "capture"
			line = I18n.t("CONTACT — and this time the ring HELD. %s is secured. Nobody in this party will ever forget today.") % str(leg["name"])
			_capture(date, rng)
		elif bool(leg.get("roaming", false)) and rng.randf() < float(APPROACH_ESCAPE.get(approach, 0.18)):
			kind = "escape"
			line = I18n.t("CONTACT — %s met our eyes, turned, and simply LEFT the region. The trail is dead. It will resurface somewhere, someday.") % str(leg["name"])
			_roamer_escaped(date)
		else:
			kind = "contact"
			line = I18n.t("CONTACT — we had %s in front of us and it slipped away. The party is shaking. We go again tomorrow.") % str(leg["name"])
	else:
		line = I18n.t("Cold trail today: prints, scorched ground, nothing more. The party holds its nerve.")
	if hunt.is_empty():
		return
	(hunt["log"] as Array).append({"date": date, "day": int(hunt["day_no"]),
		"kind": kind, "note": line})
	if str(hunt["phase"]) == "hunting" or kind == "capture" or kind == "escape":
		_post_mail(date, I18n.t("Hunt report: %s — day %d") % [str(hunt["leg_name"]), int(hunt["day_no"])],
			line + "\n\n" + I18n.t("Capture chance per contact: %d%%. Contacts so far: %d.") % [
				int(round(float(hunt["odds"]) * 100.0)), int(hunt["contacts"])],
			_hunt_mail_extra("leg_day", [{"kind": kind}]))


# ------------------------------------------------------------------ outcomes

## The once-a-career moment: build the legendary, deliver it, light the press.
func _capture(date: String, rng: RandomNumberGenerator) -> void:
	var leg := legendary(str(hunt["leg_id"]))
	var mon := _build_legendary_mon(leg, rng)
	var exped: RefCounted = ExpeditionService.active
	var where := "holding"
	if exped != null:
		where = str(exped._deliver(mon, str(hunt["dest"]), date))
	hunt["outcome"] = "captured"
	hunt["phase"] = "travel_home"
	hunt["days_in_phase"] = 0
	var s := find_sighting(str(hunt["sighting_uid"]))
	if not s.is_empty():
		s["status"] = "captured"
	captured[str(hunt["leg_id"])] = {"by": "player",
		"club": str(_gs.player_club()["name"]), "date": date, "where": where,
		"uid": str(mon["uid"]), "level": int(mon["level"])}
	_log_entry("capture", str(hunt["leg_id"]), date, {"leader": str(hunt["leader"]),
		"level": int(mon["level"]), "where": where, "uid": str(mon["uid"])})
	# board + dressing room float out of the building
	for m in _gs.player_club()["squad"]:
		m["morale"] = clampi(int(m.get("morale", 70)) + 6, 0, 100)
	var club: Dictionary = _gs.player_club()
	club["reputation"] = clampi(int(club.get("reputation", 10)) + 1, 1, 20)
	var wtxt := I18n.t("the first-team squad") if where == "squad" else \
		(I18n.t("the academy") if where == "academy" else I18n.t("the holding pen (the club is full!)"))
	_post_mail(date, I18n.t("HISTORY MADE: %s captures %s!") % [str(club["name"]), str(leg["name"])],
		I18n.t("Every front page in both regions carries the same photograph: %s, secured by %s after %d day(s) on the trail at %s. Veteran reporters are calling it the recruitment coup of the era. The legendary %s (Lv %d) joins %s. Nothing about this club will be seen the same way again — reputation +1.") % [
			str(leg["name"]), str(hunt["leader"]), int(hunt["day_no"]),
			str(hunt["site"]), str(leg["name"]), int(mon["level"]), wtxt],
		{"cat": "media", "urgent": true, "exped_kind": "leg_success",
		"uid": "exped:leg:capture:%s" % str(hunt["sighting_uid"]),
		"leg_id": str(hunt["leg_id"]), "leg_name": str(leg["name"]),
		"level": int(mon["level"]), "where": where, "leader": str(hunt["leader"]),
		"site": str(hunt["site"]), "mon_uid": str(mon["uid"]),
		"types": (DataStore.species(int(leg["species_id"])).get("types", []) as Array).duplicate()})
	_post_mail(date, I18n.t("The board is ecstatic"),
		I18n.t("Boss — the chairman has been on the phone since dawn. Sponsors want signing ceremonies, season tickets are moving, and the dressing room is walking two feet off the ground. The board records its formal congratulations on the capture of %s. Days like this buy a manager years.") % str(leg["name"]),
		{"cat": "board", "exped_kind": "leg_board",
		"uid": "exped:leg:board:%s" % str(hunt["sighting_uid"]),
		"leg_name": str(leg["name"])})


## Exceptional specimen: high IV floor, top potential, the site's level.
func _build_legendary_mon(leg: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var sp: Dictionary = DataStore.species(int(leg["species_id"]))
	var ivs := {}
	for k in STAT_KEYS:
		ivs[k] = 12 + rng.randi_range(0, 3)
	var learn: Array = sp.get("learnset", [])
	var moves: Array = learn.slice(maxi(0, learn.size() - 4))
	var nk: Array = DataStore.natures.keys()
	nk.sort()
	var mon := {"uid": "legd%03d" % next_uid, "species_id": int(leg["species_id"]),
		"species": str(sp["name"]), "level": int(leg["level"]), "ivs": ivs,
		"moves": moves, "nature": str(nk[rng.randi_range(0, nk.size() - 1)]),
		"ability": str(sp.get("ability", "")), "age_months": 240,
		"potential": 20, "pot_min": 18, "pot_max": 20, "tier": "special",
		"caught_route": str(hunt["site"]), "caught_date": str(_gs.current_date),
		"caught_by": str(hunt["leader"]), "dest": str(hunt["dest"])}
	next_uid += 1
	return mon


## A roamer bolts mid-hunt: the window dies, a resurface is pencilled in.
func _roamer_escaped(date: String) -> void:
	hunt["outcome"] = "escaped"
	hunt["phase"] = "travel_home"
	hunt["days_in_phase"] = 0
	var s := find_sighting(str(hunt["sighting_uid"]))
	if not s.is_empty():
		s["status"] = "escaped"
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_gs.career_seed) + hash("legresurf|%s" % str(hunt["sighting_uid"]))
	var delay := 12 + rng.randi_range(0, 14)
	var when := Season.date_add(date, delay)
	if Season.days_between(str(_gs.season_start), when) <= RESURFACE_MAX_OFFSET:
		resurface.append({"leg_id": str(hunt["leg_id"]), "date": when,
			"uid": "r.%s" % str(hunt["sighting_uid"])})
	_log_entry("escape", str(hunt["leg_id"]), date, {"leader": str(hunt["leader"])})


## Party home: settle the record; failures buy scouting knowledge for next time.
func _finish_hunt(date: String) -> void:
	var h := hunt
	hunt = {}
	var leg := legendary(str(h["leg_id"]))
	match str(h["outcome"]):
		"captured":
			pass  # the capture-day press said it all
		"escaped":
			attempts[str(h["leg_id"])] = int(attempts.get(str(h["leg_id"]), 0)) + 1
			_post_mail(date, I18n.t("Field report: the hunt for %s is over") % str(h["leg_name"]),
				I18n.t("%s files the closing report from %s: '%d contacts. On the last one it looked straight through us, and then it was gone — out of the region entirely. You do not corner a legend twice in one week.' The party is home. Watch the press: it WILL resurface.") % [
					str(h["leader"]), str(h["site"]), int(h["contacts"])],
				_finished_mail_extra(h, "leg_final"))
		_:
			attempts[str(h["leg_id"])] = int(attempts.get(str(h["leg_id"]), 0)) + 1
			var s := find_sighting(str(h["sighting_uid"]))
			if not s.is_empty() and str(s["status"]) == "active":
				s["status"] = "expired"
			var next_odds := odds_quote(str(h["leg_id"]), int(h["leader_skill"]), str(h["approach"]))
			_post_mail(date, I18n.t("Field report: the hunt for %s is over") % str(h["leg_name"]),
				I18n.t("%s files the closing report from %s: 'We had it in front of us and it escaped. %d contacts, every snare tested, and the window closed on us. But we mapped its dens, its water, its habits — next time the trail opens, we start ahead.' Scouting knowledge banked: capture odds rise to %d%% on the next attempt.") % [
					str(h["leader"]), str(h["site"]), int(h["contacts"]),
					int(round(float(next_odds["total"]) * 100.0))],
				_finished_mail_extra(h, "leg_final"))
			_log_entry("fail", str(h["leg_id"]), date, {"leader": str(h["leader"]),
				"contacts": int(h["contacts"])})
	legendaries_changed.emit()


# ------------------------------------------------------------------ expiry + AI

## Close windows that ran out; a declined window may tempt a rival club.
func _expire_windows(date: String) -> void:
	for s in sightings:
		if str(s["status"]) != "active" or str(s["window_end"]) >= date:
			continue
		if not hunt.is_empty() and str(hunt.get("sighting_uid", "")) == str(s["uid"]):
			continue  # party is on site working the trail out
		s["status"] = "expired"
		if not bool(s.get("attempted", false)):
			_ai_attempt(s, date)


## The world hunts too: a sighting the player let expire is rarely attempted
## by an eligible AI club — and very rarely landed. Painful by design.
## Deterministic per (career_seed, sighting uid).
func _ai_attempt(s: Dictionary, date: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_gs.career_seed) + hash("legai|%s" % str(s["uid"]))
	if rng.randf() >= AI_ATTEMPT_CHANCE:
		return
	var leg := legendary(str(s["leg_id"]))
	var candidates: Array = []
	for c in _gs.world["clubs"]:
		if _gs.is_player_club(str(c["id"])):
			continue
		if int(c.get("reputation", 10)) >= int(leg.get("min_rep", 10)) - 2:
			candidates.append(c)
	if candidates.is_empty():
		return
	var club: Dictionary = candidates[rng.randi_range(0, candidates.size() - 1)]
	if rng.randf() >= AI_SUCCESS_CHANCE:
		return  # they tried and failed, quietly — the world moves on
	var mon := {"uid": "legai%03d" % next_uid, "species_id": int(leg["species_id"]),
		"species": str(leg["name"]), "nickname": null, "level": int(leg["level"]),
		"ivs": {}, "moves": [], "held_item": null, "condition": 85, "fitness": 90,
		"morale": 90, "age_months": 240,
		"contract": {"salary": 9000, "expiry": "%04d-06-30" % (int(date.substr(0, 4)) + 3)},
		"nature": "Hardy", "ability": str(DataStore.species(int(leg["species_id"])).get("ability", "")),
		"from_expedition": true}
	next_uid += 1
	for k in STAT_KEYS:
		mon["ivs"][k] = 10 + rng.randi_range(0, 5)
	var learn: Array = DataStore.species(int(leg["species_id"])).get("learnset", [])
	mon["moves"] = learn.slice(maxi(0, learn.size() - 4))
	(club["squad"] as Array).append(mon)
	captured[str(s["leg_id"])] = {"by": str(club["id"]), "club": str(club["name"]),
		"date": date, "where": "rival", "uid": str(mon["uid"]),
		"level": int(leg["level"])}
	_log_entry("rival", str(s["leg_id"]), date, {"club": str(club["name"])})
	_post_mail(date, I18n.t("PRESS: %s capture %s — the one that got away") % [
		str(club["name"]), str(leg["name"])],
		I18n.t("The photographs are real: while the rest of the league sat on its hands, %s quietly mounted an expedition of their own — and this morning the legendary %s (Lv %d) trains in their colours. The window was open for everyone. Only one club walked through it.") % [
			str(club["name"]), str(leg["name"]), int(leg["level"])],
		{"cat": "media", "exped_kind": "leg_ai",
		"uid": "exped:leg:ai:%s" % str(s["uid"]), "leg_id": str(s["leg_id"]),
		"leg_name": str(leg["name"]), "club": str(club["name"]),
		"level": int(leg["level"]),
		"types": (DataStore.species(int(leg["species_id"])).get("types", []) as Array).duplicate()})


# ------------------------------------------------------------------ season review

## When the season rolls, annotate the just-written history entry with the
## season's legendary story (additive key; the History tab ignores unknowns).
func _on_season_rolled(new_season_no: int) -> void:
	var closed := new_season_no - 1
	var notes: Array = []
	for e in log:
		if int(e.get("season", 0)) != closed:
			continue
		var nm := str(legendary(str(e["leg_id"])).get("name", "?"))
		match str(e["kind"]):
			"capture":
				notes.append(I18n.t("%s captured by %s") % [nm, str(e.get("leader", "?"))])
			"rival":
				notes.append(I18n.t("%s captured by rivals %s") % [nm, str(e.get("club", "?"))])
			"fail":
				notes.append(I18n.t("%s hunted, not caught") % nm)
			"escape":
				notes.append(I18n.t("%s escaped mid-hunt") % nm)
			"sighting":
				notes.append(I18n.t("%s sighted") % nm)
	if notes.is_empty():
		return
	for h in _gs.season_history():
		if int(h.get("season", 0)) == closed:
			h["legendaries"] = notes
			return


# ------------------------------------------------------------------ helpers

func _log_entry(kind: String, leg_id: String, date: String, extra: Dictionary) -> void:
	var e := {"kind": kind, "leg_id": leg_id,
		"leg_name": str(legendary(leg_id).get("name", "?")), "date": date,
		"season": int(_gs.season_no()), "level": 0}
	e.merge(extra, true)
	log.push_front(e)
	if log.size() > 60:
		log.resize(60)


## Inbox mail with routing keys (report_gen routes exped_kind mails to
## screens/routes/mail_gen.gd). Deduped by uid: the press fires exactly once.
func _post_mail(date: String, title: String, body: String, extra: Dictionary) -> void:
	var uid := str(extra.get("uid", ""))
	if uid != "":
		for m in _gs.inbox:
			if str(m.get("uid", "")) == uid:
				return
	_gs.add_inbox_message(date, title, body)
	var m: Dictionary = _gs.inbox[0]
	if str(m.get("title", "")) == title:
		if not extra.has("cat"):
			extra["cat"] = "media"
		m.merge(extra, true)
		_gs.inbox_updated.emit()


func _hunt_mail_extra(kind: String, events: Array) -> Dictionary:
	var leg := legendary(str(hunt["leg_id"]))
	return {"cat": "scout", "exped_kind": kind,
		"uid": "exped:%s:%s:%s" % [kind, str(hunt["id"]), str(_gs.current_date)],
		"hunt_id": str(hunt["id"]), "leg_id": str(hunt["leg_id"]),
		"leg_name": str(hunt["leg_name"]), "site": str(hunt["site"]),
		"leader": str(hunt["leader"]), "approach": str(hunt["approach"]),
		"day_no": int(hunt["day_no"]), "hunt_days": int(hunt["hunt_days"]),
		"odds": float(hunt["odds"]), "contacts": int(hunt["contacts"]),
		"cost": int(hunt["cost"]), "dest": str(hunt["dest"]), "events": events,
		"types": (DataStore.species(int(leg["species_id"])).get("types", []) as Array).duplicate()}


func _finished_mail_extra(h: Dictionary, kind: String) -> Dictionary:
	var leg := legendary(str(h["leg_id"]))
	return {"cat": "scout", "exped_kind": kind,
		"uid": "exped:%s:%s" % [kind, str(h["id"])],
		"hunt_id": str(h["id"]), "leg_id": str(h["leg_id"]),
		"leg_name": str(h["leg_name"]), "site": str(h["site"]),
		"leader": str(h["leader"]), "outcome": str(h["outcome"]),
		"contacts": int(h["contacts"]), "cost": int(h["cost"]),
		"types": (DataStore.species(int(leg["species_id"])).get("types", []) as Array).duplicate()}


## Driver/QA hook: force a sighting window open today (deterministic uid).
func debug_spawn(leg_id: String, window_days: int = 6) -> Dictionary:
	var uid := "dbg%03d" % next_uid
	next_uid += 1
	_spawn_sighting(leg_id, str(_gs.current_date), window_days, uid, false)
	legendaries_changed.emit()
	return find_sighting(uid)
