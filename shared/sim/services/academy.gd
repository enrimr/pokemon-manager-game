extends RefCounted
class_name AcademyService
## AcademyService — the youth academy (academy piece). Auto-loaded by the
## GameState services convention; ticked daily; state rides world.meta.services.
##
## Model (all deterministic off GameState.career_seed + date):
##  - Facility level 1-5, upgraded via a board request (decision after 3 days:
##    approved iff the club can pay the cost AND keep a 150k reserve; then a
##    construction period before the new level opens).
##  - Monthly INTAKE DAY (the 15th): 2-5 juveniles join, count and potential
##    scale with facility level; ~6% "golden generation" months, ~10% thin ones.
##  - Breeding bias (documented, deterministic): candidate species are
##    non-legendary lines with BST <= 425; weight = 2 + 3 per squad member
##    sharing a type, +14 if the candidate's evolutionary line (family root
##    via evolutions.json) is already represented in our squad ("our own
##    lines breed true"), x2.5 for the club's native region (Kanto ids
##    1-151, Johto 152-251).
##  - Potential 1-20 is HIDDEN; coaches expose an uncertainty band
##    [pot_min, pot_max] whose centre error and width depend on the best
##    coach's judging_potential; the band narrows over time toward the truth.
##  - Daily development: xp -> level-ups (slower than first-team training),
##    each level-up adds an IV point weighted by the mon's training focus and
##    can teach the next learnset move. Academy level cap 28.
##  - promote() moves a mon onto the first-team squad (cap 25) with a real
##    contract — from there normal training/mentoring applies. release() cuts.

signal academy_changed

static var active = null

const INTAKE_DAY := 15
const FIRST_TEAM_CAP := 25
const ACADEMY_LEVEL_CAP := 28
const BOARD_RESERVE := 150000
const GOLDEN_CHANCE := 0.06
const THIN_CHANCE := 0.10
## Roster cap by facility level — intakes never take the academy past it, and
## the end-of-season youth review (cull) exists to keep you honest below it.
const ROSTER_CAP := {1: 8, 2: 10, 3: 12, 4: 14, 5: 16}

const FOCUSES := ["balanced", "physical", "special", "defense", "speed"]
const FOCUS_LABELS := {"balanced": "Balanced", "physical": "Physical",
	"special": "Special", "defense": "Defensive", "speed": "Speed"}
const FOCUS_STATS := {
	"balanced": {"hp": 1.0, "atk": 1.0, "def": 1.0, "spa": 1.0, "spd": 1.0, "spe": 1.0},
	"physical": {"atk": 3.0, "hp": 2.0, "def": 1.0},
	"special": {"spa": 3.0, "spd": 2.0, "hp": 1.0},
	"defense": {"def": 3.0, "spd": 2.0, "hp": 1.0},
	"speed": {"spe": 3.0, "atk": 1.0, "hp": 1.0},
}

const UPGRADE_COST := {2: 250000, 3: 600000, 4: 1250000, 5: 2500000}
const CONSTRUCTION_DAYS := {2: 10, 3: 14, 4: 21, 5: 28}
const FACILITY_NAMES := {1: "Basic Facilities", 2: "Adequate Facilities",
	3: "Established Academy", 4: "Excellent Academy", 5: "State-of-the-Art Academy"}
const INTAKE_MIN := {1: 2, 2: 2, 3: 3, 4: 3, 5: 4}
const INTAKE_MAX := {1: 3, 2: 4, 3: 4, 4: 5, 5: 5}
const LEGENDARIES := [144, 145, 146, 150, 151, 201, 243, 244, 245, 249, 250, 251]
const STAT_KEYS := ["hp", "atk", "def", "spa", "spd", "spe"]

var facility_level: int = 1
var roster: Array = []       # academy mon dicts (see _make_recruit)
var pending: Dictionary = {} # board upgrade request
var history: Array = []      # newest-first intake summaries
var next_uid: int = 1
var cull: Dictionary = {}    # open end-of-season youth review (see _open_cull_review)
var _crowd_warned := false   # roster-pressure mail sent for the current squeeze
var _gs = null
var _evo_parent: Dictionary = {}  # child species id -> pre-evo id (lazy)


## Family root of a species (walks evolutions.json backwards). Charizard -> 4.
func _root_of(id: int) -> int:
	if _evo_parent.is_empty():
		var f := FileAccess.open("res://shared/data/evolutions.json", FileAccess.READ)
		if f != null:
			var data: Variant = JSON.parse_string(f.get_as_text())
			var evos: Dictionary = data.get("evolutions", {}) if data is Dictionary else {}
			for from_id in evos:
				for e in evos[from_id]:
					_evo_parent[int(e["to"])] = int(from_id)
		_evo_parent[-1] = -1  # sentinel: parsed once even if empty
	var cur := id
	var hops := 0
	while _evo_parent.has(cur) and hops < 6:
		cur = int(_evo_parent[cur])
		hops += 1
	return cur


func service_id() -> String:
	return "academy"


func on_career_started(gs) -> void:
	_gs = gs
	active = self
	if not gs.season_rolled.is_connected(_on_season_rolled):
		gs.season_rolled.connect(_on_season_rolled)
	academy_changed.emit()


## New season: FM's youth-review moment. If the academy holds anyone, the head
## youth coach files a keep/release recommendation list and asks for decisions.
func _on_season_rolled(_season_no: int) -> void:
	if _gs != null and not roster.is_empty():
		_open_cull_review()


func on_day(gs, date: String) -> void:
	_gs = gs
	_tick_upgrade(date)
	if int(date.substr(8, 2)) == INTAKE_DAY - 7:
		_post_intake_preview(date)
	if int(date.substr(8, 2)) == INTAKE_DAY:
		_run_intake(date)
	_tick_development(date)
	if date.ends_with("-01"):
		for m in roster:
			m["age_months"] = int(m["age_months"]) + 1
	if roster.size() < roster_cap() - 1:
		_crowd_warned = false   # pressure relieved; warn again on the next squeeze
	academy_changed.emit()


func save_state() -> Dictionary:
	return {"facility_level": facility_level, "roster": roster.duplicate(true),
		"pending": pending.duplicate(true), "history": history.duplicate(true),
		"next_uid": next_uid, "cull": cull.duplicate(true),
		"crowd_warned": _crowd_warned}


func load_state(state: Dictionary) -> void:
	facility_level = int(state.get("facility_level", 1))
	roster = state.get("roster", [])
	for m in roster:
		_cast_mon(m)
	pending = state.get("pending", {})
	if not pending.is_empty():
		pending["to_level"] = int(pending.get("to_level", 2))
		pending["cost"] = int(pending.get("cost", 0))
	history = state.get("history", [])
	next_uid = int(state.get("next_uid", 1))
	cull = state.get("cull", {}) if typeof(state.get("cull")) == TYPE_DICTIONARY else {}
	if not cull.is_empty():
		cull["season"] = int(cull.get("season", 0))
	_crowd_warned = bool(state.get("crowd_warned", false))


func _cast_mon(m: Dictionary) -> void:
	for k in ["species_id", "level", "potential", "pot_min", "pot_max", "age_months"]:
		m[k] = int(m.get(k, 0))
	m["xp"] = float(m.get("xp", 0.0))
	m["stars"] = float(m.get("stars", 1.0))
	var ivs: Dictionary = m.get("ivs", {})
	for k in ivs:
		ivs[k] = int(ivs[k])


# ------------------------------------------------------------------ coaches

func _coach_rating(key: String) -> int:
	var best := 8
	if _gs == null:
		return best
	for s in _gs.player_club().get("staff", []):
		if String(s.get("role", "")) == "coach":
			best = maxi(best, int(s.get("ratings", {}).get(key, 8)))
	return best


func head_youth_coach() -> String:
	var best := -1
	var who := I18n.t("the coaching staff")
	if _gs == null:
		return who
	for s in _gs.player_club().get("staff", []):
		if String(s.get("role", "")) == "coach" and int(s.get("ratings", {}).get("youth", 0)) > best:
			best = int(s["ratings"].get("youth", 0))
			who = String(s["name"])
	return who


# ------------------------------------------------------------------ mail

## Post an inbox mail with the routing key and a JSON-safe snapshot already
## attached. report_gen routes any message carrying academy_kind (or an
## "academy:" uid) to screens/academy/mail_gen.gd, and news_gen's enrichment
## skips messages that arrive with a cat — so these mails NEVER fall back to
## the generic board-review template, and the snapshot is taken on the day the
## mail is sent (intake-day truth, not first-read truth). The plain body stays
## as a fallback for installs without the academy screen.
func _post_mail(date: String, title: String, body: String, extra: Dictionary) -> void:
	_gs.add_inbox_message(date, title, body)
	var m: Dictionary = _gs.inbox[0]
	if str(m.get("title", "")) == title:
		m.merge(extra, true)
		_gs.inbox_updated.emit()


func _board_sender() -> String:
	return "%s Board of Directors" % str(_gs.player_club().get("name", "Club"))


# ------------------------------------------------------------------ intake

func next_intake_date() -> String:
	if _gs == null:
		return ""
	var d: String = _gs.current_date
	if int(d.substr(8, 2)) < INTAKE_DAY:
		return d.substr(0, 8) + "%02d" % INTAKE_DAY
	var y := int(d.substr(0, 4))
	var mo := int(d.substr(5, 2)) + 1
	if mo > 12:
		mo = 1
		y += 1
	return "%04d-%02d-%02d" % [y, mo, INTAKE_DAY]


## Weighted species pool for intake — the documented "breeding" bias.
func _weighted_pool() -> Array:
	var squad: Array = _gs.player_club()["squad"]
	var squad_lines := {}
	var type_count := {}
	for inst in squad:
		squad_lines[_root_of(int(inst["species_id"]))] = true
		var isp: Dictionary = DataStore.species(int(inst["species_id"]))
		for t in isp.get("types", []):
			type_count[t] = int(type_count.get(t, 0)) + 1
	var league := String(_gs.player_club().get("league", "kanto"))
	var out: Array = []
	for sp in DataStore.pokemon:
		var id := int(sp["id"])
		if id in LEGENDARIES:
			continue
		var bst := 0
		for k in sp["base"]:
			bst += int(sp["base"][k])
		if bst > 425:
			continue  # juveniles come from early-stage lines
		var w := 2.0
		for t in sp["types"]:
			w += 3.0 * float(type_count.get(t, 0))
		if squad_lines.has(_root_of(id)):
			w += 14.0  # our own lines breed true
		var native_johto := id > 151
		if (league == "johto") == native_johto:
			w *= 2.5   # regional identity
		out.append([sp, w])
	return out


func _pick_weighted(r: RandomNumberGenerator, pool: Array) -> Dictionary:
	var total := 0.0
	for e in pool:
		total += float(e[1])
	var roll := r.randf() * total
	for e in pool:
		roll -= float(e[1])
		if roll <= 0.0:
			return e[0]
	return pool.back()[0]


## The month's intake roll (seeded off career + month — the preview a week
## out and intake day itself see the SAME class). Returns {r, count, golden,
## thin}; r is the RNG mid-stream, ready to generate the recruits.
func _roll_intake(date: String) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = int(_gs.career_seed) + hash("academy|intake|" + date.substr(0, 7))
	var lo: int = INTAKE_MIN[facility_level]
	var hi: int = INTAKE_MAX[facility_level]
	var count := lo + int(r.randi() % (hi - lo + 1))
	var golden := r.randf() < GOLDEN_CHANCE
	var thin := (not golden) and r.randf() < THIN_CHANCE
	return {"r": r, "count": count, "golden": golden, "thin": thin}


## FM's iconic intake-preview mail: a week before intake day the head youth
## coach sends an early, hedged read on the incoming class.
func _post_intake_preview(date: String) -> void:
	var roll := _roll_intake(date)
	var coach := head_youth_coach()
	var mood := "normal"
	if bool(roll["golden"]):
		mood = "golden"
	elif bool(roll["thin"]):
		mood = "thin"
	var intake_on := date.substr(0, 8) + "%02d" % INTAKE_DAY
	var body := I18n.t("%s has been watching the youth candidates ahead of intake day on %s. ") % [coach, I18n.pretty_date(intake_on)]
	match mood:
		"golden":
			body += I18n.t("Whispers from the programme suggest a special group is coming through — the staff can barely contain themselves.")
		"thin":
			body += I18n.t("Expectations are low this month; the region's best juveniles appear to have gone elsewhere.")
		_:
			body += I18n.t("A typical group is expected — a couple of names worth watching, nothing the staff are shouting about yet.")
	var space := roster_cap() - roster.size()
	if space <= 0:
		body += I18n.t(" One problem: the academy is FULL (%d/%d beds) — the whole class will be turned away unless beds open up first.") % [
			roster.size(), roster_cap()]
	elif space < int(INTAKE_MIN[facility_level]):
		body += I18n.t(" Space is tight (%d/%d beds taken) — only %d can be housed.") % [
			roster.size(), roster_cap(), space]
	_post_mail(date, I18n.t("Youth intake preview"), body, {
		"cat": "staff", "sender": coach, "coach": coach,
		"academy_kind": "preview", "uid": "academy:preview:" + date,
		"mood": mood, "intake_on": intake_on,
		"expect_lo": int(INTAKE_MIN[facility_level]),
		"expect_hi": int(INTAKE_MAX[facility_level]),
		"facility": facility_level,
		"facility_name": String(FACILITY_NAMES[facility_level]),
	})


func _run_intake(date: String) -> void:
	var roll := _roll_intake(date)
	var r: RandomNumberGenerator = roll["r"]
	var count: int = roll["count"]
	var golden: bool = roll["golden"]
	var thin: bool = roll["thin"]
	# The facility can only house so many juveniles: intake shrinks to fit,
	# and a FULL academy turns the class away entirely (with a pointed mail).
	var space := roster_cap() - roster.size()
	if space <= 0:
		_post_mail(date, I18n.t("Youth intake suspended — the academy is full"),
			(I18n.t("%s had a class of %d lined up but the %s can house only %d juveniles ")
			+ I18n.t("and every bed is taken (%d on the roster). Promote or release someone ")
			+ I18n.t("— or expand the facilities — before the %dth of next month.")) % [
			head_youth_coach(), count, I18n.t(FACILITY_NAMES[facility_level]), roster_cap(),
			roster.size(), INTAKE_DAY], {
			"cat": "staff", "sender": head_youth_coach(),
			"academy_kind": "intake_full", "uid": "academy:full:" + date,
			"cap": roster_cap(), "size": roster.size(),
			"facility_name": String(FACILITY_NAMES[facility_level])})
		return
	count = mini(count, space)
	var pool := _weighted_pool()
	var recruits: Array = []
	for i in count:
		recruits.append(_make_recruit(r, pool, golden, thin, date))
	roster.append_array(recruits)
	var best: Dictionary = recruits[0]
	for m in recruits:
		if int(m["pot_max"]) > int(best["pot_max"]):
			best = m
	history.push_front({"date": date, "count": count, "golden": golden, "thin": thin,
		"best": String(best["species"]), "facility": facility_level})
	if history.size() > 24:
		history.resize(24)
	var coach := head_youth_coach()
	var snap: Array = []
	for m in recruits:
		var sp: Dictionary = DataStore.species(int(m["species_id"]))
		var band := potential_stars(m)
		snap.append({
			"species": String(m["species"]), "types": (sp.get("types", []) as Array).duplicate(),
			"level": int(m["level"]), "age_months": int(m["age_months"]),
			"nature": String(m["nature"]), "stars": float(m["stars"]),
			"band_lo": float(band[0]), "band_hi": float(band[1]),
			"pot_max": int(m["pot_max"]), "moves": (m["moves"] as Array).duplicate(),
			"note": _pot_note(int(m["pot_max"])),
			"best": String(m["uid"]) == String(best["uid"]),
		})
	_post_mail(date, I18n.t("Youth intake day: %d new recruits") % count,
		_intake_report(recruits, golden, thin), {
			"cat": "staff", "sender": coach, "coach": coach,
			"academy_kind": "intake", "uid": "academy:intake:" + date,
			"recruits": snap, "golden": golden, "thin": thin,
			"facility": facility_level,
			"facility_name": String(FACILITY_NAMES[facility_level]),
		})
	_check_crowding(date)


# ------------------------------------------------------------------ housekeeping

## Bed count of the current facilities (upgrades literally add room).
func roster_cap() -> int:
	return int(ROSTER_CAP.get(facility_level, 8))


## The academy is ballooning: one warning mail per squeeze (resets once the
## roster drops back under pressure level = cap - 1).
func _check_crowding(date: String) -> void:
	var cap := roster_cap()
	if roster.size() < cap - 1:
		_crowd_warned = false
		return
	if _crowd_warned:
		return
	_crowd_warned = true
	var full := roster.size() >= cap
	_post_mail(date, I18n.t("Academy roster is %s (%d/%d)") % [
		I18n.t("full") if full else I18n.t("nearly full"), roster.size(), cap],
		(I18n.t("%s flags a housekeeping problem: the %s has %d of %d beds taken. %s ")
		+ I18n.t("Development time gets diluted in an overcrowded academy — promote the ")
		+ I18n.t("ready ones, release the depth, or ask the board for bigger facilities.")) % [
		head_youth_coach(), I18n.t(FACILITY_NAMES[facility_level]), roster.size(), roster_cap(),
		I18n.t("Next month's intake will be turned away entirely.") if full
			else I18n.t("Anything beyond a token intake will be turned away.")], {
		"cat": "staff", "sender": head_youth_coach(),
		"academy_kind": "crowded", "uid": "academy:crowded:" + date,
		"cap": cap, "size": roster.size(),
		"facility_name": String(FACILITY_NAMES[facility_level])})


## FM's end-of-season youth review: every academy mon gets a coach
## recommendation (KEEP / RELEASE, with a stated reason); the manager settles
## it on the Academy screen (apply_cull) — the mail stays a live decision
## until then. Deterministic: pure function of the roster + coach quality.
func _open_cull_review() -> void:
	var items: Array = []
	for m in roster:
		var rec := _cull_recommendation(m)
		items.append({"uid": String(m["uid"]), "species": String(m["species"]),
			"level": int(m["level"]), "age_months": int(m["age_months"]),
			"stars": float(m["stars"]), "pot_min": int(m["pot_min"]),
			"pot_max": int(m["pot_max"]), "rec": rec[0], "reason": rec[1]})
	items.sort_custom(func(a, b): return int(a["pot_max"]) > int(b["pot_max"]))
	var releases := items.filter(func(i): return String(i["rec"]) == "release").size()
	cull = {"season": _gs.season_no(), "date": _gs.current_date,
		"items": items, "resolved": false}
	_post_mail(_gs.current_date, I18n.t("Youth review: %s recommends %s") % [
		head_youth_coach(),
		(I18n.t("releasing %d of %d juveniles") % [releases, items.size()]) if releases > 0
			else I18n.t("keeping the whole group")],
		_cull_body(items, releases), {
		"cat": "staff", "sender": head_youth_coach(),
		"academy_kind": "cull", "uid": "academy:cull:S%d" % _gs.season_no(),
		"items": cull["items"], "resolved": false,
		"cap": roster_cap(), "size": roster.size()})
	if not _gs.inbox.is_empty() and str(_gs.inbox[0].get("uid", "")) == "academy:cull:S%d" % _gs.season_no():
		_gs.inbox[0]["urgent"] = true
	academy_changed.emit()


func _cull_recommendation(m: Dictionary) -> Array:
	var pot_max := int(m["pot_max"])
	var pot_mid := (int(m["pot_min"]) + pot_max) / 2
	var age := int(m["age_months"])
	if pot_max <= 8:
		return ["release", I18n.t("ceiling is depth-chart at best — a bed wasted")]
	if age >= 42 and pot_mid < 12:
		return ["release", I18n.t("overage for the programme and the ceiling never came")]
	if age >= 30 and float(m["stars"]) < 1.5 and pot_max < 13:
		return ["release", I18n.t("development has stalled well behind the age curve")]
	if pot_max >= 15:
		return ["keep", I18n.t("genuine first-team ceiling — protect this one")]
	if int(m["level"]) >= ACADEMY_LEVEL_CAP - 2:
		return ["keep", I18n.t("ready for a first-team look — promote rather than release")]
	return ["keep", I18n.t("worth another season of development")]


func _cull_body(items: Array, releases: int) -> String:
	var lines: Array = []
	lines.append(I18n.t("%s has completed the end-of-season review of the academy (%d/%d beds).") % [
		head_youth_coach(), roster.size(), roster_cap()])
	lines.append("")
	for i in items:
		lines.append(I18n.t("%s  %s (Lv %d, %s) — %s") % [
			I18n.t("RELEASE") if String(i["rec"]) == "release" else I18n.t("KEEP") + "   ",
			String(i["species"]), int(i["level"]), _age_text(int(i["age_months"])),
			String(i["reason"])])
	lines.append("")
	lines.append(I18n.t("Settle the list on the Academy screen — releases free beds before the season's first intake day.")
		if releases > 0 else I18n.t("No cuts advised, but the decision is yours — review them on the Academy screen."))
	return "\n".join(lines)


## Apply the manager's decisions on the open youth review: release the given
## uids, mark the review (and its mail) resolved, confirm by mail.
func apply_cull(release_uids: Array) -> String:
	if cull.is_empty() or bool(cull.get("resolved", false)):
		return I18n.t("No youth review is awaiting decisions.")
	var released: Array = []
	for uid in release_uids:
		var m := find(String(uid))
		if not m.is_empty():
			released.append(String(m["species"]))
			roster.erase(m)
	cull["resolved"] = true
	cull["released"] = released.size()
	for mail in _gs.inbox:
		if str(mail.get("academy_kind", "")) == "cull" and not bool(mail.get("resolved", false)):
			mail["resolved"] = true
			mail["urgent"] = false
	_post_mail(_gs.current_date, I18n.t("Youth review settled: %s") % (
		(I18n.t("%d released, %d kept") % [released.size(), roster.size()]) if not released.is_empty()
			else I18n.t("everyone stays")),
		(I18n.t("The academy heads into the new season with %d of %d beds filled.%s")) % [
			roster.size(), roster_cap(),
			(I18n.t(" Released: %s. The staff wish them well.") % ", ".join(released)) if not released.is_empty() else ""], {
		"cat": "staff", "sender": head_youth_coach(),
		"academy_kind": "cull_done", "uid": "academy:cull_done:" + _gs.current_date,
		"released": released, "kept": roster.size(), "cap": roster_cap()})
	_gs.inbox_updated.emit()
	academy_changed.emit()
	return ""


func _make_recruit(r: RandomNumberGenerator, pool: Array, golden: bool, thin: bool,
		date: String) -> Dictionary:
	var sp := _pick_weighted(r, pool)
	var pot := 4 + facility_level + int(r.randi() % 7)
	if golden:
		pot += 4 + int(r.randi() % 3)
	if thin:
		pot -= 2
	pot = clampi(pot, 1, 20)
	var level := 3 + int(r.randi() % 3) + (1 if facility_level >= 4 else 0)
	var ivs := {}
	for k in STAT_KEYS:
		var v := int(r.randi() % 16)
		if facility_level >= 3:
			v = maxi(v, int(r.randi() % 16))  # better facilities, better raw material
		ivs[k] = v
	# Starter moves are juvenile-appropriate: the first learnset entries whose
	# power a Lv-5 recruit could plausibly wield (no "Knows: Hyper Beam").
	var learn: Array = sp.get("learnset", [])
	var moves: Array = []
	for mv in learn:
		if moves.size() >= 2:
			break
		if int(DataStore.move(String(mv)).get("power", 0)) <= 60:
			moves.append(mv)
	for i in mini(2, learn.size()):
		if moves.size() >= 2:
			break
		if not (learn[i] in moves):
			moves.append(learn[i])
	var nk: Array = DataStore.natures.keys()
	nk.sort()
	var jp := _coach_rating("judging_potential")
	var err := float(20 - jp) / 4.0
	var centre := clampi(pot + int(round((r.randf() * 2.0 - 1.0) * err)), 1, 20)
	var half_w := 2 + int((20 - jp) / 5)
	var pot_min := clampi(centre - half_w, 1, 20)
	var pot_max := clampi(centre + half_w, pot_min + 2, 20)
	var uid := "aca%04d" % next_uid
	next_uid += 1
	var m := {
		"uid": uid, "species_id": int(sp["id"]), "species": String(sp["name"]),
		"level": level, "ivs": ivs, "moves": moves,
		"nature": String(nk[r.randi() % nk.size()]), "ability": String(sp.get("ability", "")),
		"age_months": 8 + int(r.randi() % 10), "joined": date,
		"potential": pot, "pot_min": pot_min, "pot_max": pot_max,
		"focus": "balanced", "xp": 0.0, "stars": 0.0,
	}
	m["stars"] = _ability_stars(m)
	return m


## Coach-judged CURRENT ability, 0.5..5 stars in halves.
func _ability_stars(m: Dictionary) -> float:
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


func potential_stars(m: Dictionary) -> Array:
	## [lo, hi] star floats from the coaches' uncertainty band.
	return [clampf(snappedf(float(int(m["pot_min"])) / 4.0, 0.5), 0.5, 5.0),
		clampf(snappedf(float(int(m["pot_max"])) / 4.0, 0.5), 0.5, 5.0)]


func _pot_note(pot_max: int) -> String:
	if pot_max >= 17:
		return I18n.t("could lead the first team for a decade")
	if pot_max >= 13:
		return I18n.t("a genuine prospect worth developing")
	if pot_max >= 9:
		return I18n.t("solid foundations, needs game time")
	return I18n.t("one for the depth chart at best")


func _intake_report(recruits: Array, golden: bool, thin: bool) -> String:
	var coach := head_youth_coach()
	var lines: Array = []
	lines.append(I18n.t("%s presents this month's academy intake (%s, level %d).") % [
		coach, I18n.t(FACILITY_NAMES[facility_level]), facility_level])
	if golden:
		lines.append(I18n.t("The staff are buzzing — early signs suggest this could be a GOLDEN GENERATION."))
	elif thin:
		lines.append(I18n.t("A thin month; the region's best young battlers went elsewhere."))
	lines.append("")
	for m in recruits:
		var sp: Dictionary = DataStore.species(int(m["species_id"]))
		var band := potential_stars(m)
		lines.append(I18n.t("%s  (%s)  — Lv %d, %s") % [String(m["species"]),
			I18n.types_join(sp.get("types", []), ", "), int(m["level"]), _age_text(int(m["age_months"]))])
		lines.append(I18n.t("    Current %s   Potential %s – %s   \"%s\"") % [
			star_text(float(m["stars"])), star_text(band[0]), star_text(band[1]),
			_pot_note(int(m["pot_max"]))])
	lines.append("")
	lines.append(I18n.t("They begin work at the academy immediately. Review them on the Academy screen."))
	return "\n".join(lines)


## Star meter as BBCode [img] tags (mail bodies render through RichTextLabel;
## the bundled web font has no star glyph, so stars are drawn SVG icons).
static func star_text(v: float) -> String:
	var out := ""
	for i in int(v):
		out += "[img=13x13]res://shared/theme/icons/star_gold.svg[/img]"
	if v - float(int(v)) >= 0.49 or v < 1.0:
		out += "[img=13x13]res://shared/theme/icons/star_half_gold.svg[/img]"
	return out


static func _age_text(months: int) -> String:
	return I18n.t("%dy %dm") % [months / 12, months % 12]


# ------------------------------------------------------------------ development

func _xp_needed(level: int) -> float:
	return 6.0 + float(level) * 0.85


func dev_progress(m: Dictionary) -> float:
	return clampf(float(m["xp"]) / _xp_needed(int(m["level"])), 0.0, 1.0)


func _tick_development(date: String) -> void:
	if roster.is_empty():
		return
	var youth := _coach_rating("youth")
	var day_seed := int(_gs.career_seed) + hash("academy|dev|" + date)
	for m in roster:
		var r := RandomNumberGenerator.new()
		r.seed = day_seed + hash(String(m["uid"]))
		var pot := int(m["potential"])
		# Deliberately slower than first-team training: juveniles marinate.
		var gain := 0.55 * (0.85 + 0.15 * float(facility_level)) \
			* (0.7 + float(youth) / 40.0) * (0.55 + float(pot) / 22.0) \
			* (0.85 + r.randf() * 0.3)
		m["xp"] = float(m["xp"]) + gain
		var need := _xp_needed(int(m["level"]))
		if float(m["xp"]) >= need and int(m["level"]) < ACADEMY_LEVEL_CAP:
			m["xp"] = float(m["xp"]) - need
			m["level"] = int(m["level"]) + 1
			_on_level_up(m, r)
		if r.randf() < 0.18:
			_narrow_band(m)
		m["stars"] = _ability_stars(m)


func _on_level_up(m: Dictionary, r: RandomNumberGenerator) -> void:
	# IV point in a focus-weighted stat (cap 15 like every IV in the game).
	var weights: Dictionary = FOCUS_STATS.get(String(m.get("focus", "balanced")), FOCUS_STATS["balanced"])
	var open: Array = []
	var total := 0.0
	for k in weights:
		if int(m["ivs"].get(k, 0)) < 15:
			open.append(k)
			total += float(weights[k])
	if open.is_empty():
		for k in STAT_KEYS:
			if int(m["ivs"].get(k, 0)) < 15:
				open.append(k)
				total += 1.0
	if not open.is_empty():
		var roll := r.randf() * total
		for k in open:
			roll -= float(FOCUS_STATS.get(String(m.get("focus", "balanced")), {}).get(k, 1.0))
			if roll <= 0.0:
				m["ivs"][k] = int(m["ivs"][k]) + 1
				break
	# Learn the next unknown learnset move if a slot is free.
	var moves: Array = m["moves"]
	if moves.size() < 4:
		for mv in DataStore.species(int(m["species_id"])).get("learnset", []):
			if not (mv in moves):
				moves.append(mv)
				break


func _narrow_band(m: Dictionary) -> void:
	var jp := _coach_rating("judging_potential")
	var min_w := maxi(2, int((20 - jp) / 6))
	if int(m["pot_max"]) - int(m["pot_min"]) <= min_w:
		return
	var pot := int(m["potential"])
	if pot - int(m["pot_min"]) > int(m["pot_max"]) - pot:
		m["pot_min"] = int(m["pot_min"]) + 1
	else:
		m["pot_max"] = int(m["pot_max"]) - 1


# ------------------------------------------------------------------ actions

func find(uid: String) -> Dictionary:
	for m in roster:
		if String(m["uid"]) == uid:
			return m
	return {}


func set_focus(uid: String, focus: String) -> void:
	var m := find(uid)
	if not m.is_empty() and focus in FOCUSES:
		m["focus"] = focus
		academy_changed.emit()


func promote(uid: String) -> String:
	var m := find(uid)
	if m.is_empty():
		return I18n.t("Not in the academy.")
	var squad: Array = _gs.player_club()["squad"]
	if squad.size() >= FIRST_TEAM_CAP:
		return I18n.t("First-team squad is full (%d/%d). Release or sell first.") % [squad.size(), FIRST_TEAM_CAP]
	var sp: Dictionary = DataStore.species(int(m["species_id"]))
	var bst := 0
	for k in sp.get("base", {}):
		bst += int(sp["base"][k])
	var moves: Array = (m["moves"] as Array).duplicate()
	for mv in sp.get("learnset", []):
		if moves.size() >= 4:
			break
		if not (mv in moves):
			moves.append(mv)
	var yr := int(_gs.current_date.substr(0, 4)) + 3
	var inst := {
		"uid": String(m["uid"]), "species_id": int(m["species_id"]),
		"species": String(m["species"]), "nickname": null, "level": int(m["level"]),
		"ivs": (m["ivs"] as Dictionary).duplicate(), "moves": moves, "held_item": null,
		"condition": 75, "fitness": 90, "morale": 85, "age_months": int(m["age_months"]),
		"contract": {"salary": int(float(bst) * 1.5 + float(int(m["level"])) * 40.0),
			"expiry": "%04d-06-30" % yr},
		"nature": String(m["nature"]), "ability": String(m["ability"]),
		"potential": int(m["potential"]), "from_academy": true,
	}
	squad.append(inst)
	roster.erase(m)
	var band := potential_stars(m)
	_post_mail(_gs.current_date, I18n.t("%s promoted to the first team") % inst["species"],
		I18n.t("%s steps up from the academy on a contract to %s. Coaches rate the ceiling %s – %s. Young battlers develop fastest alongside senior squad-mates — consider a mentor.") % [
			inst["species"], I18n.pretty_date(str(inst["contract"]["expiry"])),
			star_text(band[0]), star_text(band[1])], {
			"cat": "staff", "sender": head_youth_coach(),
			"academy_kind": "promote",
			"uid": "academy:promote:%s:%s" % [_gs.current_date, String(m["uid"])],
			"species": String(inst["species"]),
			"types": (sp.get("types", []) as Array).duplicate(),
			"level": int(inst["level"]),
			"band_lo": float(band[0]), "band_hi": float(band[1]),
			"pot_max": int(m["pot_max"]),
			"salary": int(inst["contract"]["salary"]),
			"expiry": String(inst["contract"]["expiry"]),
		})
	academy_changed.emit()
	return ""


func release(uid: String) -> String:
	var m := find(uid)
	if m.is_empty():
		return I18n.t("Not in the academy.")
	roster.erase(m)
	_post_mail(_gs.current_date, I18n.t("%s released from the academy") % m["species"],
		I18n.t("%s leaves the club's youth setup. The staff wish them well.") % m["species"], {
			"cat": "staff", "sender": head_youth_coach(),
			"academy_kind": "release",
			"uid": "academy:release:%s:%s" % [_gs.current_date, String(m["uid"])],
			"species": String(m["species"]),
		})
	academy_changed.emit()
	return ""


# ------------------------------------------------------------------ facility

func facility_name() -> String:
	return FACILITY_NAMES[facility_level]


func upgrade_cost() -> int:
	return int(UPGRADE_COST.get(facility_level + 1, 0))


func request_upgrade() -> String:
	if facility_level >= 5:
		return I18n.t("The academy is already state of the art.")
	if not pending.is_empty():
		return I18n.t("A request is already with the board.")
	var cost := upgrade_cost()
	pending = {"to_level": facility_level + 1, "cost": cost, "status": "pending",
		"requested": _gs.current_date, "decide_on": Season.date_add(_gs.current_date, 3),
		"complete_on": ""}
	_post_mail(_gs.current_date, I18n.t("Board considering academy investment"),
		I18n.t("You have asked the board to fund Level %d academy facilities (%s). They will respond within days.") % [
			facility_level + 1, format_money(cost)], {
			"cat": "board", "sender": _board_sender(),
			"academy_kind": "board_request",
			"uid": "academy:board:req:" + _gs.current_date,
			"to_level": facility_level + 1,
			"facility_name": String(FACILITY_NAMES[facility_level + 1]),
			"cost": cost, "decide_on": String(pending["decide_on"]),
			"reserve": BOARD_RESERVE,
		})
	academy_changed.emit()
	return ""


func _tick_upgrade(date: String) -> void:
	if pending.is_empty():
		return
	var to := int(pending["to_level"])
	var cost := int(pending["cost"])
	if String(pending["status"]) == "pending" and date >= String(pending["decide_on"]):
		var fin: Dictionary = _gs.player_club()["finances"]
		if int(fin["balance"]) >= cost + BOARD_RESERVE:
			fin["balance"] = int(fin["balance"]) - cost
			pending["status"] = "building"
			pending["complete_on"] = Season.date_add(date, int(CONSTRUCTION_DAYS[to]))
			_post_mail(date, I18n.t("Board approves academy expansion"),
				I18n.t("The board has released %s for Level %d facilities. Construction completes on %s.") % [
					format_money(cost), to, I18n.pretty_date(str(pending["complete_on"]))], {
					"cat": "board", "sender": _board_sender(),
					"academy_kind": "board_approve",
					"uid": "academy:board:ok:" + date,
					"to_level": to, "cost": cost,
					"facility_name": String(FACILITY_NAMES[to]),
					"complete_on": String(pending["complete_on"]),
				})
		else:
			pending = {}
			_post_mail(date, I18n.t("Board rejects academy request"),
				I18n.t("The club cannot commit %s while keeping a %s operating reserve. Improve the balance and ask again.") % [
					format_money(cost), format_money(BOARD_RESERVE)], {
					"cat": "board", "sender": _board_sender(),
					"academy_kind": "board_reject",
					"uid": "academy:board:no:" + date,
					"to_level": to, "cost": cost, "reserve": BOARD_RESERVE,
					"facility_name": String(FACILITY_NAMES[to]),
				})
	elif String(pending["status"]) == "building" and date >= String(pending["complete_on"]):
		facility_level = to
		pending = {}
		_post_mail(date, I18n.t("New academy facilities open"),
			I18n.t("The %s (Level %d) are ready. Expect larger, higher-quality intakes from the %dth of each month.") % [
				I18n.t(FACILITY_NAMES[facility_level]), facility_level, INTAKE_DAY], {
				"cat": "board", "sender": _board_sender(),
				"academy_kind": "facility_open",
				"uid": "academy:board:open:" + date,
				"to_level": facility_level,
				"facility_name": String(FACILITY_NAMES[facility_level]),
			})


static func format_money(v: int) -> String:
	var cur := str(GameState.world.get("meta", {}).get("currency", "P$")) if GameState.world is Dictionary else "P$"
	return cur + I18n.number(v)
