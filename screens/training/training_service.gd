extends Node
## TrainingService — the training model for the "training" piece.
## Lives at /root/TrainingService (created lazily by the training screen and
## kept alive across screen re-instantiation). Listens to GameState.date_changed
## and applies real daily training effects to the player squad:
##   - fractional stat progress that converts into IV points (capped at 15)
##   - strain (overtraining) that drags fitness down and can cause knocks
##   - move-learning pipelines that complete with an inbox message
## Persists its own state to user://training.json. Squad mutations (ivs, moves,
## fitness, condition) live in GameState.world and are saved by GameState.

signal training_changed

const SAVE_PATH := "user://training.json"

const DAY_KEYS := ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
const DAY_LABELS := {"mon": "Monday", "tue": "Tuesday", "wed": "Wednesday",
	"thu": "Thursday", "fri": "Friday", "sat": "Saturday", "sun": "Sunday"}

const FOCUSES := ["physical", "special", "defense", "speed", "technique", "match_prep", "rest"]
const FOCUS_LABELS := {"physical": "Physical", "special": "Special", "defense": "Defense",
	"speed": "Speed", "technique": "Move Practice", "match_prep": "Match Prep", "rest": "Recovery"}
# Which stats each session focus trains (primary 1.0, secondary weights).
const FOCUS_STATS := {
	"physical": {"atk": 1.0, "hp": 0.45},
	"special": {"spa": 1.0, "spd": 0.35},
	"defense": {"def": 1.0, "spd": 0.5},
	"speed": {"spe": 1.0, "hp": 0.2},
	"technique": {},
	"match_prep": {},
	"rest": {},
}

const INTENSITIES := ["light", "normal", "high"]
const INTENSITY_LABELS := {"light": "Light", "normal": "Normal", "high": "High"}
const INTENSITY_MULT := {"light": 0.6, "normal": 1.0, "high": 1.55}
const INTENSITY_STRAIN := {"light": 2.5, "normal": 5.0, "high": 9.5}

# --- 7-day preset plans -----------------------------------------------------
# Each preset is a full week: 7 [am, pm] pairs plus 7 intensities. They can be
# written into the repeating weekday template (apply_preset) OR stamped onto
# one specific future calendar week as per-date overrides
# (apply_preset_to_week) — e.g. a deliberate recovery week before a congested
# block, a heavy development block in a free week, or an opponent-prep week.
const PRESETS := ["balanced", "attacking", "defensive", "development", "recovery", "prep"]
const PRESET_LABELS := {"balanced": "Balanced", "attacking": "Attack Heavy",
	"defensive": "Defensive", "development": "Heavy Development",
	"recovery": "Recovery Week", "prep": "Match Prep Week"}
const PRESET_PLANS := {
	"balanced": {
		"rota": [["physical", "technique"], ["special", "speed"], ["defense", "physical"],
			["technique", "special"], ["speed", "defense"], ["physical", "technique"], ["rest", "rest"]],
		"inten": ["normal", "normal", "normal", "normal", "normal", "normal", "light"],
	},
	"attacking": {
		"rota": [["physical", "special"], ["special", "technique"], ["physical", "speed"],
			["special", "physical"], ["technique", "special"], ["physical", "special"], ["rest", "rest"]],
		"inten": ["high", "high", "high", "high", "high", "high", "light"],
	},
	"defensive": {
		"rota": [["defense", "physical"], ["defense", "technique"], ["speed", "defense"],
			["defense", "special"], ["technique", "defense"], ["defense", "speed"], ["rest", "rest"]],
		"inten": ["normal", "normal", "normal", "normal", "normal", "normal", "light"],
	},
	"development": {
		"rota": [["physical", "special"], ["speed", "technique"], ["defense", "physical"],
			["special", "speed"], ["physical", "defense"], ["special", "technique"], ["rest", "rest"]],
		"inten": ["high", "high", "high", "high", "high", "high", "light"],
	},
	"recovery": {
		"rota": [["rest", "technique"], ["speed", "rest"], ["rest", "rest"],
			["technique", "rest"], ["rest", "speed"], ["rest", "technique"], ["rest", "rest"]],
		"inten": ["light", "light", "light", "light", "light", "light", "light"],
	},
	"prep": {
		"rota": [["match_prep", "technique"], ["speed", "match_prep"], ["match_prep", "defense"],
			["technique", "match_prep"], ["match_prep", "speed"], ["match_prep", "technique"], ["rest", "rest"]],
		"inten": ["light", "light", "light", "light", "light", "light", "light"],
	},
}

# --- per-Pokémon workload (FM-style individual training intensity) ---------
# Every Pokémon carries its own load setting on top of the squad schedule:
# either a manual step, or "auto" — condition-tied rules that resolve daily
# from current strain and age (see resolve_auto_load). The effective step
# scales BOTH development points and strain for that individual, so a veteran
# on Light and a prospect on Double genuinely train different sessions.
const LOADS := ["auto", "double", "high", "normal", "light", "half", "none"]
const LOAD_LABELS := {"auto": "Automatic", "double": "Double", "high": "High",
	"normal": "Normal", "light": "Light", "half": "Half", "none": "No Training"}
const LOAD_MULT := {"double": 1.5, "high": 1.25, "normal": 1.0,
	"light": 0.7, "half": 0.45, "none": 0.0}       # development multiplier
const LOAD_STRAIN := {"double": 1.9, "high": 1.4, "normal": 1.0,
	"light": 0.65, "half": 0.4, "none": 0.0}       # strain multiplier (double is punishing)
const AUTO_REST_AT := 78.0    # auto: full rest at/above this strain
const AUTO_LIGHT_AT := 60.0   # auto: drop to Light at/above this strain
const AUTO_VET_LIGHT_AT := 45.0  # auto: veterans go Light earlier
const AUTO_FRESH_BELOW := 25.0   # auto: young developers pushed harder when fresh

# Playing a match is itself a physical load: starters take real strain,
# the rest of the travelling squad a little (warm-ups, travel).
const MATCH_STRAIN_STARTER := 13.0
const MATCH_STRAIN_BENCH := 4.0
const PREP_STRAIN := 2.0  # strain per Match Prep session (deliberately light)

# Coaching categories and which staff rating drives each.
const CATEGORIES := ["physical", "special", "defense", "speed", "technique", "recovery"]
const CAT_LABELS := {"physical": "Physical", "special": "Special", "defense": "Defense",
	"speed": "Speed", "technique": "Move Practice", "recovery": "Recovery & Fitness"}
const CAT_SOURCE := {"physical": "attacking", "special": "attacking", "defense": "defending",
	"speed": "fitness", "technique": "judging_ability", "recovery": "fitness"}

const STATS := ["hp", "atk", "def", "spa", "spd", "spe"]
const STAT_LABELS := {"hp": "HP", "atk": "Attack", "def": "Defense",
	"spa": "Sp. Atk", "spd": "Sp. Def", "spe": "Speed"}

const GROWTH_MULT := {"fast": 1.15, "medium_fast": 1.0, "medium_slow": 0.9, "slow": 0.8}

# --- mentoring (the FM Mentoring-tab analog) --------------------------------
# Veterans whose own development has flattened are grouped with rapid
# developers. The junior trains in the mentor's shadow every day: a real
# development multiplier, a growth-focus bias from the mentor's personality,
# and a morale lift on both sides — all applied in the daily tick and
# attributed in the Development report ("learning from X").
const MENTOR_AGE_MULT := 0.7    # age_mult at/below this = veteran, can mentor
const JUNIOR_AGE_MULT := 1.15   # age_mult at/above this = rapid developer, can be mentored
const MENTOR_LEVEL_GAP := 3     # mentor must be at least this many levels above
const MENTOR_AGE_GAP := 24      # ...and this many months older
const MENTOR_MAX_JUNIORS := 2   # attention splits beyond one junior

const MENTOR_BASE_BONUS := 0.12       # every valid pairing: +12% development
const MENTOR_TYPE_BONUS := 0.06       # shared type: the craft transfers directly
const MENTOR_GAP_BONUS_PER_LVL := 0.008  # more to learn from a much stronger mentor
const MENTOR_GAP_BONUS_CAP := 0.08
const MENTOR_SPLIT_PENALTY := 0.04    # mentor watching two juniors at once
const PERSONALITY_STAT_MULT := 1.25   # juniors' work on the mentor's favoured stats
const STUDIOUS_MOVE_MULT := 1.3       # Studious mentors speed up juniors' move drills
const PRO_STRAIN_MULT := 0.9          # Professional mentors teach strain discipline

# A mentor's personality decides which growth focus rubs off on its juniors.
# Derived deterministically from the Pokémon itself (species leaning + uid),
# so it is stable across sessions with no extra saved state.
const PERSONALITIES := {
	"driven": {"label": "Driven", "stats": ["atk", "hp"],
		"desc": "drills relentless physical work — juniors' Attack and HP training bites harder"},
	"calm": {"label": "Calm Mind", "stats": ["spa", "spd"],
		"desc": "steers juniors toward special technique — Sp. Atk and Sp. Def work bites harder"},
	"stoic": {"label": "Stoic", "stats": ["def", "spd"],
		"desc": "teaches juniors to soak punishment — Defense and Sp. Def work bites harder"},
	"lively": {"label": "Lively", "stats": ["spe", "hp"],
		"desc": "keeps juniors quick and sharp — Speed and HP work bites harder"},
	"studious": {"label": "Studious", "stats": [],
		"desc": "passes on technique — juniors master new moves ×1.3 faster"},
	"professional": {"label": "Professional", "stats": [],
		"desc": "models perfect habits — extra development across the board and ×0.9 strain intake"},
}

var state: Dictionary = {}


static var _instance: Node = null


static func ensure() -> Node:
	if _instance != null and is_instance_valid(_instance):
		return _instance
	var root := Engine.get_main_loop().root as Node
	var existing := root.get_node_or_null("TrainingService")
	if existing != null:
		_instance = existing
		return existing
	var svc: Node = load("res://screens/training/training_service.gd").new()
	svc.name = "TrainingService"
	svc.setup()
	_instance = svc
	# Deferred: at boot the shell instances screens while the root is still
	# busy setting up children. The service works before entering the tree.
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


func _on_career_event() -> void:
	# New career started after a save wipe: our last-processed date is in the
	# future relative to the fresh calendar -> reset the model.
	if state.get("last", "") > GameState.current_date:
		state = _default_state()
		save_state()
		training_changed.emit()


func _on_date_changed(_d: String) -> void:
	_catch_up()


func _catch_up() -> void:
	if state.get("last", "") > GameState.current_date:
		_on_career_event()
	var processed := 0
	while state["last"] < GameState.current_date and processed < 400:
		state["last"] = Season.date_add(state["last"], 1)
		_process_day(state["last"])
		processed += 1
	if processed > 0:
		_prune_overrides()
		save_state()
		training_changed.emit()


## Drop per-date plan edits once their date has passed (they already ran).
func _prune_overrides() -> void:
	var ov: Dictionary = state.get("overrides", {})
	for date in ov.keys():
		if str(date) < GameState.current_date:
			ov.erase(date)


# ------------------------------------------------------------------ state

func _default_state() -> Dictionary:
	var sched := {
		"mon": {"am": "physical", "pm": "technique"},
		"tue": {"am": "special", "pm": "speed"},
		"wed": {"am": "defense", "pm": "physical"},
		"thu": {"am": "technique", "pm": "special"},
		"fri": {"am": "speed", "pm": "defense"},
		"sat": {"am": "physical", "pm": "technique"},
		"sun": {"am": "rest", "pm": "rest"},
	}
	var intensity := {}
	for d in DAY_KEYS:
		intensity[d] = "light" if d == "sun" else "normal"
	return {
		"version": 1,
		"last": GameState.current_date,
		"schedule": sched,
		"intensity": intensity,
		"overrides": {},   # per-DATE plan edits: {"2026-09-14": {am, pm, intensity}} (all keys optional)
		"view_weeks": 2,
		"auto_match": true,
		"coaches": _auto_assign_coaches(),
		"mons": {},
		"week_gains": {},
		"mentoring": [],   # groups: [{"mentor": uid, "juniors": [uid, ...]}]
	}


func _auto_assign_coaches() -> Dictionary:
	var out := {}
	var load_by_coach := {}
	for cat in CATEGORIES:
		var best := ""
		var best_score := -999.0
		for s in coaching_staff():
			var r := float(s["ratings"].get(CAT_SOURCE[cat], 5))
			var score := r - 1.6 * float(load_by_coach.get(s["name"], 0))
			if score > best_score:
				best_score = score
				best = s["name"]
		out[cat] = best
		if best != "":
			load_by_coach[best] = int(load_by_coach.get(best, 0)) + 1
	return out


func _load_state() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		var data: Variant = JSON.parse_string(f.get_as_text())
		if typeof(data) == TYPE_DICTIONARY and int(data.get("version", 0)) == 1:
			state = data
			if not state.has("week_gains"):
				state["week_gains"] = {}
			if not state.has("auto_match"):
				state["auto_match"] = true
			if not state.has("overrides"):
				state["overrides"] = {}
			if not state.has("view_weeks"):
				state["view_weeks"] = 2
			if not state.has("mentoring"):
				state["mentoring"] = []
			return
	state = _default_state()
	save_state()


## Set by throwaway verification runs (dev_check): keeps the whole model in
## memory but never writes user://training.json, so an unsaved alternate
## timeline cannot contaminate the real career's training state on disk.
var no_disk := false


func save_state() -> void:
	if no_disk:
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(state))


func mon_state(uid: String) -> Dictionary:
	var mons: Dictionary = state["mons"]
	if not mons.has(uid):
		var inst := _find_instance(uid)
		var fit := float(inst.get("fitness", 85)) if not inst.is_empty() else 85.0
		var acc := {}
		var gained := {}
		for s in STATS:
			acc[s] = 0.0
			gained[s] = 0
		mons[uid] = {
			"focus": "",
			"load": "auto",
			"complained": "",
			"strain": clampf(20.0 + (100.0 - fit) * 0.4, 5.0, 60.0),
			"acc": acc,
			"gained": gained,
			"move": null,
			"snaps": [],
			"learned": [],
			"mentor_pts": 0.0,
			"mentor_ivs": 0,
		}
	var m: Dictionary = mons[uid]
	# migrate pre-workload / pre-mentoring saves in place
	if not m.has("load"):
		m["load"] = "auto"
	if not m.has("complained"):
		m["complained"] = ""
	if not m.has("mentor_pts"):
		m["mentor_pts"] = 0.0
		m["mentor_ivs"] = 0
	return m


# ------------------------------------------------------------------ queries

func squad() -> Array:
	return GameState.player_club().get("squad", [])


func coaching_staff() -> Array:
	return GameState.player_club().get("staff", []).filter(func(s): return s["role"] == "coach")


func staff_by_name(n: String) -> Dictionary:
	for s in GameState.player_club().get("staff", []):
		if s["name"] == n:
			return s
	return {}


func _find_instance(uid: String) -> Dictionary:
	for inst in squad():
		if inst["uid"] == uid:
			return inst
	return {}


func coach_load(coach_name: String) -> int:
	var n := 0
	for cat in CATEGORIES:
		if state["coaches"].get(cat, "") == coach_name:
			n += 1
	return n


## Effective coaching multiplier for a category, including workload penalty.
func coach_mult(cat: String) -> float:
	var cname: String = state["coaches"].get(cat, "")
	var coach := staff_by_name(cname)
	if coach.is_empty():
		return 0.55
	var rating := float(coach["ratings"].get(CAT_SOURCE[cat], 5))
	var mult := 0.68 + 0.036 * rating
	var load := coach_load(cname)
	if load >= 3:
		mult *= 1.0 - 0.07 * float(load - 2)
	return mult


## 0..1 workload penalty fraction for a coach (0 = none).
func workload_penalty(coach_name: String) -> float:
	var load := coach_load(coach_name)
	return 0.07 * float(load - 2) if load >= 3 else 0.0


const GAIN_SCALE := 2.2  # global tuning knob: training points per session weight


# ---------------------------------------------------------- fixture calendar

## The player's fixture on a calendar date (played or not), or {}.
func player_fixture_on(date: String) -> Dictionary:
	var pid: String = GameState.world["meta"]["player_club_id"]
	for f in GameState.fixtures:
		if f["date"] == date and (f["home"] == pid or f["away"] == pid):
			return f
	return {}


## Player fixtures in the next `days` days (including today), unplayed first.
func upcoming_player_fixtures(days: int = 14) -> Array:
	var horizon := Season.date_add(GameState.current_date, days)
	var out: Array = GameState.player_fixtures().filter(func(f):
		return not f["played"] and f["date"] >= GameState.current_date and f["date"] <= horizon)
	out.sort_custom(func(a, b): return str(a["date"]) < str(b["date"]))
	return out


## The 7 real calendar dates projections run over: today .. today+6.
func week_dates() -> Array:
	var out: Array = []
	for i in 7:
		out.append(Season.date_add(GameState.current_date, i))
	return out


## The full visible calendar: `weeks` blocks of 7 dates starting today.
func calendar_dates(weeks: int) -> Array:
	var out: Array = []
	for i in clampi(weeks, 1, 4) * 7:
		out.append(Season.date_add(GameState.current_date, i))
	return out


func view_weeks() -> int:
	return clampi(int(state.get("view_weeks", 2)), 1, 4)


func set_view_weeks(w: int) -> void:
	state["view_weeks"] = clampi(w, 1, 4)
	save_state()


func opponent_of(fx: Dictionary) -> Dictionary:
	var pid: String = GameState.world["meta"]["player_club_id"]
	return GameState.club(fx["away"] if fx["home"] == pid else fx["home"])


func fixture_is_home(fx: Dictionary) -> bool:
	return fx["home"] == GameState.world["meta"]["player_club_id"]


## The plan edits stored for one calendar DATE ({} = none). Partial:
## any of "am", "pm", "intensity" may be present independently.
func date_override(date: String) -> Dictionary:
	return (state.get("overrides", {}) as Dictionary).get(date, {})


## What ACTUALLY happens on a calendar date. Three layers, FM-style:
##   1. the repeating weekday template (the default),
##   2. per-DATE overrides you plan onto the visible calendar — a specific
##      recovery week, a heavy development block, opponent prep, any one day,
##   3. fixture auto-adjust (if on): the matchday itself is always locked
##      (warm-up + MATCH); the day after defaults to enforced recovery and the
##      day before to a light Match Prep day — but a per-date override you set
##      deliberately on those days WINS over the auto default.
## Kinds:
##   normal          — template applies untouched
##   custom          — per-date override in effect (also custom around fixtures)
##   matchday        — no field training: warm-up AM, the match PM (locked)
##   post_match      — auto recovery day after a fixture (editable default)
##   pre_match       — auto light day, PM = Match Prep (editable default)
##   matchday_manual — auto-adjust turned off: your plan runs INTO the match
func effective_plan(date: String) -> Dictionary:
	var day := _weekday_key(date)
	var cell: Dictionary = state["schedule"][day]
	var ov := date_override(date)
	var plan := {
		"date": date, "day": day,
		"kind": "custom" if not ov.is_empty() else "normal",
		"am": ov.get("am", cell["am"]), "pm": ov.get("pm", cell["pm"]),
		"intensity": ov.get("intensity", state["intensity"][day]),
		"fixture": {},
		"ov": {"am": ov.has("am"), "pm": ov.has("pm"), "intensity": ov.has("intensity")},
	}
	var fx := player_fixture_on(date)
	if not fx.is_empty():
		plan["fixture"] = fx
	if not bool(state.get("auto_match", true)):
		if not fx.is_empty():
			plan["kind"] = "matchday_manual"
		return plan
	if not fx.is_empty():
		# The match itself always happens — overrides cannot train through it.
		plan["kind"] = "matchday"
		plan["am"] = "match_prep"
		plan["pm"] = "match"
		plan["intensity"] = "light"
		plan["ov"] = {"am": false, "pm": false, "intensity": false}
		return plan
	if not player_fixture_on(Season.date_add(date, -1)).is_empty():
		# Day after a match: recovery by default; a deliberate date plan wins.
		plan["kind"] = "custom" if not ov.is_empty() else "post_match"
		plan["am"] = ov.get("am", "rest")
		plan["pm"] = ov.get("pm", "rest")
		plan["intensity"] = ov.get("intensity", "light")
		return plan
	if not player_fixture_on(Season.date_add(date, 1)).is_empty():
		# Day before a match: light + PM prep by default; date plan wins.
		plan["kind"] = "custom" if not ov.is_empty() else "pre_match"
		plan["pm"] = ov.get("pm", "match_prep")
		plan["intensity"] = ov.get("intensity", "light")
		return plan
	return plan


## The six most likely starters (mirrors Season.simulate_fixture's pick:
## top of the squad by level, then condition) — they carry real match strain.
func likely_starter_uids() -> Array:
	var sq: Array = squad().duplicate()
	sq.sort_custom(func(a, b):
		if int(a["level"]) != int(b["level"]):
			return int(a["level"]) > int(b["level"])
		return int(a.get("condition", 90)) > int(b.get("condition", 90)))
	return sq.slice(0, 6).map(func(i): return str(i["uid"]))


func age_mult(age_months: int) -> float:
	if age_months <= 30:
		return 1.35
	if age_months <= 48:
		return 1.15
	if age_months <= 66:
		return 0.95
	if age_months <= 84:
		return 0.7
	return 0.45


func growth_mult(growth: String) -> float:
	return float(GROWTH_MULT.get(growth, 1.0))


func iv_cost(iv: int) -> float:
	return 4.0 + 1.0 * float(iv)


func strain(uid: String) -> float:
	return float(mon_state(uid).get("strain", 0.0))


# ------------------------------------------------- per-Pokémon workload

## The stored workload setting for a Pokémon: "auto" or a manual step.
func load_setting(uid: String) -> String:
	var l := str(mon_state(uid).get("load", "auto"))
	return l if l == "auto" or LOAD_MULT.has(l) else "auto"


## Resolve the Automatic rule into a concrete load step for one Pokémon.
## Condition-tied automation, FM-style:
##   strain >= 78            -> No Training (rest until it recovers)
##   strain >= 60            -> Light
##   veteran (age mult<=0.7) -> never above Normal; Light from strain 45
##   fresh (<25) developer   -> High (young bodies soak up work)
##   otherwise               -> Normal
func resolve_auto_load(inst: Dictionary) -> String:
	var s := strain(str(inst["uid"]))
	var a := age_mult(int(inst.get("age_months", 48)))
	if s >= AUTO_REST_AT:
		return "none"
	if s >= AUTO_LIGHT_AT:
		return "light"
	if a <= 0.7:
		return "light" if s >= AUTO_VET_LIGHT_AT else "normal"
	if s < AUTO_FRESH_BELOW and a >= 1.15:
		return "high"
	return "normal"


## Why the Automatic rule chose what it chose (for the UI).
func auto_load_reason(inst: Dictionary) -> String:
	var s := strain(str(inst["uid"]))
	var a := age_mult(int(inst.get("age_months", 48)))
	if s >= AUTO_REST_AT:
		return "strain %d%% ≥ %d — full rest until recovered" % [int(s), int(AUTO_REST_AT)]
	if s >= AUTO_LIGHT_AT:
		return "strain %d%% ≥ %d — dropped to Light" % [int(s), int(AUTO_LIGHT_AT)]
	if a <= 0.7:
		if s >= AUTO_VET_LIGHT_AT:
			return "veteran body at strain %d%% — eased to Light" % int(s)
		return "veteran body — capped at Normal (Light from strain %d)" % int(AUTO_VET_LIGHT_AT)
	if s < AUTO_FRESH_BELOW and a >= 1.15:
		return "fresh (%d%%) rapid developer — pushed to High" % int(s)
	return "standard load at strain %d%%" % int(s)


## The load step actually applied to this Pokémon today.
func effective_load(inst: Dictionary) -> String:
	var l := load_setting(str(inst["uid"]))
	return resolve_auto_load(inst) if l == "auto" else l


func load_mult(inst: Dictionary) -> float:
	return float(LOAD_MULT[effective_load(inst)])


func load_strain_mult(inst: Dictionary) -> float:
	return float(LOAD_STRAIN[effective_load(inst)])


## How the personal load gates move-learning drills: reduced when training
## light, paused entirely when the Pokémon is rested.
func move_load_factor(inst: Dictionary) -> float:
	var lk := effective_load(inst)
	if lk == "none":
		return 0.0
	return 0.5 + 0.5 * float(LOAD_MULT[lk])


## Visible pushback: how this Pokémon feels about a FORCED workload.
## "" (content) | "overworked" (manual heavy load at high strain — morale
## drains, injury risk up) | "wants_more" (young developer held back).
func workload_reaction(inst: Dictionary) -> String:
	var manual := load_setting(str(inst["uid"]))
	if manual == "auto":
		return ""
	var s := strain(str(inst["uid"]))
	if (manual == "double" or manual == "high") and s > 65.0:
		return "overworked"
	if (manual == "none" or manual == "half") and s < 22.0 \
			and age_mult(int(inst.get("age_months", 48))) >= 1.15:
		return "wants_more"
	return ""


# --------------------------------------------------------------- mentoring

func mentor_groups() -> Array:
	if not state.has("mentoring"):
		state["mentoring"] = []
	return state["mentoring"]


## A mentor's personality (stable: species stat leaning + uid hash, no state).
func personality(inst: Dictionary) -> String:
	var sp: Dictionary = DataStore.species(int(inst["species_id"]))
	var best := "atk"
	var best_v := -1
	for s in ["atk", "spa", "def", "spe"]:
		if int(sp["base"][s]) > best_v:
			best_v = int(sp["base"][s])
			best = s
	var lean: String = {"atk": "driven", "spa": "calm", "def": "stoic", "spe": "lively"}[best]
	var pool: Array = [lean, "studious", "professional"]
	return pool[absi(str(inst["uid"]).hash()) % pool.size()]


func personality_label(inst: Dictionary) -> String:
	return str(PERSONALITIES[personality(inst)]["label"])


func mentor_eligible(inst: Dictionary) -> bool:
	return age_mult(int(inst.get("age_months", 48))) <= MENTOR_AGE_MULT


func junior_eligible(inst: Dictionary) -> bool:
	return age_mult(int(inst.get("age_months", 48))) >= JUNIOR_AGE_MULT


## The group a uid belongs to (as mentor or junior), or {}.
func group_of(uid: String) -> Dictionary:
	for g in mentor_groups():
		if str(g["mentor"]) == uid or (g["juniors"] as Array).has(uid):
			return g
	return {}


func is_mentor(uid: String) -> bool:
	for g in mentor_groups():
		if str(g["mentor"]) == uid:
			return true
	return false


## The mentor INSTANCE for a junior uid, or {}.
func mentor_of(uid: String) -> Dictionary:
	for g in mentor_groups():
		if (g["juniors"] as Array).has(uid):
			return _find_instance(str(g["mentor"]))
	return {}


## "" if this pairing is allowed, else the human reason it is not.
func can_mentor(mentor: Dictionary, junior: Dictionary) -> String:
	if not mentor_eligible(mentor):
		return "%s is not a veteran yet — only Pokémon whose own growth has flattened can mentor" % _display_name(mentor)
	if not junior_eligible(junior):
		return "%s is past rapid development — mentoring only accelerates young Pokémon" % _display_name(junior)
	if int(mentor["level"]) - int(junior["level"]) < MENTOR_LEVEL_GAP:
		return "needs a mentor at least %d levels above (%s is Lv %d vs Lv %d)" % [
			MENTOR_LEVEL_GAP, _display_name(mentor), int(mentor["level"]), int(junior["level"])]
	if int(mentor["age_months"]) - int(junior["age_months"]) < MENTOR_AGE_GAP:
		return "age gap under %d months — too close in age to look up to" % MENTOR_AGE_GAP
	return ""


func create_mentor_group(mentor_uid: String) -> String:
	var m := _find_instance(mentor_uid)
	if m.is_empty():
		return "not in the squad"
	if not mentor_eligible(m):
		return "%s is not a veteran yet" % _display_name(m)
	if not group_of(mentor_uid).is_empty():
		return "%s is already in a mentor group" % _display_name(m)
	mentor_groups().append({"mentor": mentor_uid, "juniors": []})
	save_state()
	training_changed.emit()
	return ""


func disband_mentor_group(mentor_uid: String) -> void:
	var groups := mentor_groups()
	for i in range(groups.size() - 1, -1, -1):
		if str(groups[i]["mentor"]) == mentor_uid:
			groups.remove_at(i)
	save_state()
	training_changed.emit()


func add_junior(mentor_uid: String, junior_uid: String) -> String:
	var g := group_of(mentor_uid)
	if g.is_empty() or str(g.get("mentor", "")) != mentor_uid:
		return "no such mentor group"
	if (g["juniors"] as Array).size() >= MENTOR_MAX_JUNIORS:
		return "a mentor can watch at most %d juniors" % MENTOR_MAX_JUNIORS
	if not group_of(junior_uid).is_empty():
		return "already in a mentor group"
	var err := can_mentor(_find_instance(mentor_uid), _find_instance(junior_uid))
	if err != "":
		return err
	(g["juniors"] as Array).append(junior_uid)
	save_state()
	training_changed.emit()
	return ""


func remove_junior(junior_uid: String) -> void:
	for g in mentor_groups():
		(g["juniors"] as Array).erase(junior_uid)
	save_state()
	training_changed.emit()


## The live daily effect of mentoring on a JUNIOR ({} if not mentored):
##   mult       — overall development multiplier (base + type + level gap +
##                personality − attention split)
##   stat_mult  — extra ×1.25 on the stats the mentor's personality favours
##   move_mult  — Studious mentors accelerate the junior's move pipeline
##   strain_mult— Professional mentors teach strain discipline
func mentoring_effect(junior_uid: String) -> Dictionary:
	var m := mentor_of(junior_uid)
	if m.is_empty():
		return {}
	var junior := _find_instance(junior_uid)
	if junior.is_empty() or can_mentor(m, junior) != "":
		return {}
	var g := group_of(junior_uid)
	var pk := personality(m)
	var compat := _shares_type(m, junior)
	var mult := pairing_mult(m, junior, (g["juniors"] as Array).size())
	var stat_mult := {}
	for s in PERSONALITIES[pk]["stats"]:
		stat_mult[s] = PERSONALITY_STAT_MULT
	return {
		"mult": mult, "stat_mult": stat_mult,
		"move_mult": STUDIOUS_MOVE_MULT if pk == "studious" else 1.0,
		"strain_mult": PRO_STRAIN_MULT if pk == "professional" else 1.0,
		"mentor": m, "mentor_name": _display_name(m),
		"personality": pk, "compat": compat,
	}


## The development multiplier a mentor/junior pairing produces at a given
## group size (also used by the UI to preview a pairing before adding it).
func pairing_mult(m: Dictionary, junior: Dictionary, group_size: int) -> float:
	var mult := 1.0 + MENTOR_BASE_BONUS
	if _shares_type(m, junior):
		mult += MENTOR_TYPE_BONUS
	mult += minf(MENTOR_GAP_BONUS_CAP,
		MENTOR_GAP_BONUS_PER_LVL * float(int(m["level"]) - int(junior["level"])))
	if personality(m) == "professional":
		mult += 0.05
	if group_size >= 2:
		mult -= MENTOR_SPLIT_PENALTY
	return mult


func _shares_type(a: Dictionary, b: Dictionary) -> bool:
	var ta: Array = DataStore.species(int(a["species_id"]))["types"]
	var tb: Array = DataStore.species(int(b["species_id"]))["types"]
	for t in ta:
		if tb.has(t):
			return true
	return false


## Keep groups honest as the world moves: drop members who left the squad and
## juniors who have aged out of rapid development (with an inbox note).
func _validate_mentoring(date: String) -> void:
	var groups := mentor_groups()
	var changed := false
	for i in range(groups.size() - 1, -1, -1):
		var g: Dictionary = groups[i]
		var m := _find_instance(str(g["mentor"]))
		if m.is_empty() or not mentor_eligible(m):
			groups.remove_at(i)
			changed = true
			continue
		var juniors: Array = g["juniors"]
		for j in range(juniors.size() - 1, -1, -1):
			var junior := _find_instance(str(juniors[j]))
			if junior.is_empty():
				juniors.remove_at(j)
				changed = true
			elif not junior_eligible(junior):
				GameState.add_inbox_message(date,
					"%s has outgrown mentoring" % _display_name(junior),
					"%s is no longer in rapid development and gains nothing more from shadowing %s. The mentor group has been adjusted." %
					[_display_name(junior), _display_name(m)])
				juniors.remove_at(j)
				changed = true
	if changed:
		training_changed.emit()


## Estimated net strain change per Pokémon for a real calendar DATE,
## using the fixture-adjusted plan (matches add squad-average match strain).
func day_strain_load(date: String) -> float:
	var plan := effective_plan(date)
	var load := 0.0
	for slot in ["am", "pm"]:
		match str(plan[slot]):
			"rest":
				load -= 10.0
			"match":
				load += _avg_match_strain()
			"match_prep":
				load += PREP_STRAIN
			_:
				load += float(INTENSITY_STRAIN[plan["intensity"]])
	if plan["kind"] == "matchday_manual":
		load += _avg_match_strain()  # the match still happens on top of training
	return load - _recovery_rate()


func _avg_match_strain() -> float:
	var n := maxf(1.0, float(squad().size()))
	var starters := minf(6.0, n)
	return (starters * MATCH_STRAIN_STARTER + (n - starters) * MATCH_STRAIN_BENCH) / n


func _recovery_rate() -> float:
	return 6.5 + 2.5 * (coach_mult("recovery") - 0.55) / 0.85


## Net strain across the ACTUAL upcoming week (today .. +6), fixtures included.
## Squad average — individual loads make each Pokémon deviate from this.
func weekly_strain_balance() -> float:
	var total := 0.0
	for date in week_dates():
		total += day_strain_load(date)
	return total


## Net strain change for ONE Pokémon on a date: the fixture-adjusted plan
## scaled by its personal workload, plus its own match role (starter vs bench).
func personal_day_strain(inst: Dictionary, date: String, starters: Array) -> float:
	var plan := effective_plan(date)
	var lk := effective_load(inst)
	var lsm := float(LOAD_STRAIN[lk])
	var is_starter: bool = starters.has(str(inst["uid"]))
	var load := 0.0
	for slot in ["am", "pm"]:
		match str(plan[slot]):
			"rest":
				load -= 10.0
			"match":
				load += MATCH_STRAIN_STARTER if is_starter else MATCH_STRAIN_BENCH
			"match_prep":
				# matches _process_day: a rested individual sits prep out and
				# does recovery work instead.
				load += -6.0 if lk == "none" else PREP_STRAIN
			_:
				if lk == "none":
					load -= 6.0  # rested individuals do recovery work instead
				else:
					load += float(INTENSITY_STRAIN[plan["intensity"]]) * lsm
	if plan["kind"] == "matchday_manual":
		load += MATCH_STRAIN_STARTER if is_starter else MATCH_STRAIN_BENCH
	return load - _recovery_rate()


## Projected net strain for one Pokémon across the upcoming week (today..+6),
## at its current effective load. Feeds the Squad Training Status table.
func personal_week_strain(inst: Dictionary) -> float:
	var starters := likely_starter_uids()
	var total := 0.0
	for date in week_dates():
		total += personal_day_strain(inst, date, starters)
	return total


## Session counts by focus across the actual upcoming week (fixture-adjusted).
## Matches themselves are counted under "match".
func sessions_per_focus() -> Dictionary:
	var counts := {"match": 0}
	for f in FOCUSES:
		counts[f] = 0
	for date in week_dates():
		var plan := effective_plan(date)
		for slot in ["am", "pm"]:
			var f := str(plan[slot])
			counts[f] = int(counts.get(f, 0)) + 1
	return counts


## Projected training points per stat over the ACTUAL upcoming week
## (today .. +6) for an instance: fixture-adjusted plan, coaches, focus.
## A congested week genuinely projects less development than a free one.
func weekly_projection(inst: Dictionary) -> Dictionary:
	var sp: Dictionary = DataStore.species(int(inst["species_id"]))
	var ms := mon_state(inst["uid"])
	var g := growth_mult(sp.get("growth", "medium_fast"))
	var a := age_mult(int(inst.get("age_months", 48)))
	var lm := load_mult(inst)  # personal workload scales the whole projection
	var me := mentoring_effect(str(inst["uid"]))  # mentored juniors project faster
	var pts := {}
	for s in STATS:
		pts[s] = 0.0
	for date in week_dates():
		var plan := effective_plan(date)
		var im := float(INTENSITY_MULT[plan["intensity"]])
		for slot in ["am", "pm"]:
			var f: String = plan[slot]
			var weights: Dictionary = FOCUS_STATS.get(f, {})
			for s in weights:
				var v: float = weights[s] * GAIN_SCALE * im * lm * coach_mult(f) * g * a
				v *= _focus_mult(ms, s) * _youth_bonus(inst, f)
				if not me.is_empty():
					v *= float(me["mult"]) * float((me["stat_mult"] as Dictionary).get(s, 1.0))
				pts[s] += v
	var pen := _strain_penalty(float(ms["strain"]))
	for s in STATS:
		pts[s] *= pen
	return pts


## Rough ETA in days for +1 IV in a stat, given weekly projection. -1 = never.
func eta_days(inst: Dictionary, stat: String) -> int:
	var pts := weekly_projection(inst)
	var per_day := float(pts[stat]) / 7.0
	if per_day <= 0.005:
		return -1
	var iv := int(inst["ivs"].get(stat, 8))
	if iv >= 15:
		return -1
	var need := iv_cost(iv) - float(mon_state(inst["uid"])["acc"][stat])
	return maxi(1, int(ceil(need / per_day)))


func technique_sessions_per_week() -> int:
	return int(sessions_per_focus().get("technique", 0))


## Daily move-learning progress % for an instance. Includes the personal
## workload gate: light loads slow drills, No Training pauses them.
func move_learn_rate(inst: Dictionary) -> float:
	var tech_per_day := float(technique_sessions_per_week()) / 7.0
	var a := 1.15 if int(inst.get("age_months", 48)) <= 40 else (
		1.0 if int(inst.get("age_months", 48)) <= 84 else 0.85)
	var rate := (1.2 + 2.6 * tech_per_day) * coach_mult("technique") * a * move_load_factor(inst)
	# A Studious mentor drills technique into its juniors between sessions.
	var me := mentoring_effect(str(inst["uid"]))
	if not me.is_empty():
		rate *= float(me["move_mult"])
	return rate


func eligible_moves(inst: Dictionary) -> Array:
	var sp: Dictionary = DataStore.species(int(inst["species_id"]))
	var known: Array = inst.get("moves", [])
	var out: Array = []
	for m in sp.get("learnset", []):
		if not known.has(m):
			out.append(m)
	# evolved mons keep their pre-evolution learnset (evolution service seam:
	# it merges those moves into inst["learnset_extra"] for training to offer)
	for m in inst.get("learnset_extra", []):
		if not known.has(m) and not out.has(m) and not DataStore.move(str(m)).is_empty():
			out.append(m)
	return out


# ------------------------------------------------------------------ mutations (UI)

func set_schedule(day: String, slot: String, focus: String) -> void:
	state["schedule"][day][slot] = focus
	save_state()


func set_intensity(day: String, inten: String) -> void:
	state["intensity"][day] = inten
	save_state()


func set_auto_match(on: bool) -> void:
	state["auto_match"] = on
	save_state()


func assign_coach(cat: String, coach_name: String) -> void:
	state["coaches"][cat] = coach_name
	save_state()


func set_focus(uid: String, stat: String) -> void:
	mon_state(uid)["focus"] = stat
	save_state()


func set_load(uid: String, l: String) -> void:
	mon_state(uid)["load"] = l if (l == "auto" or LOAD_MULT.has(l)) else "auto"
	save_state()


func start_move_learning(uid: String, move_name: String, replace_slot: int) -> void:
	mon_state(uid)["move"] = {"name": move_name, "slot": replace_slot, "progress": 0.0}
	save_state()


func cancel_move_learning(uid: String) -> void:
	mon_state(uid)["move"] = null
	save_state()


# --- per-DATE calendar planning (the FM Calendar analog) --------------------

func set_date_session(date: String, slot: String, focus: String) -> void:
	var ov: Dictionary = state["overrides"]
	if not ov.has(date):
		ov[date] = {}
	ov[date][slot] = focus
	save_state()


func set_date_intensity(date: String, inten: String) -> void:
	var ov: Dictionary = state["overrides"]
	if not ov.has(date):
		ov[date] = {}
	ov[date]["intensity"] = inten
	save_state()


## Remove one slot's edit on a date ("am"/"pm"/"intensity") — back to default.
func clear_date_slot(date: String, slot: String) -> void:
	var ov: Dictionary = state["overrides"]
	if ov.has(date):
		(ov[date] as Dictionary).erase(slot)
		if (ov[date] as Dictionary).is_empty():
			ov.erase(date)
	save_state()


func clear_date_override(date: String) -> void:
	(state["overrides"] as Dictionary).erase(date)
	save_state()


## Wipe all per-date edits in the 7 days starting at start_date.
func clear_week_overrides(start_date: String) -> void:
	for i in 7:
		(state["overrides"] as Dictionary).erase(Season.date_add(start_date, i))
	save_state()


## Stamp a preset onto ONE specific calendar week as per-date overrides:
## plan a recovery week before a congested block, a heavy development block
## in a free week, or an opponent-prep week — without touching the template.
func apply_preset_to_week(preset: String, start_date: String) -> void:
	if not PRESET_PLANS.has(preset):
		return
	var plan: Dictionary = PRESET_PLANS[preset]
	var ov: Dictionary = state["overrides"]
	for i in 7:
		var date := Season.date_add(start_date, i)
		ov[date] = {
			"am": plan["rota"][i][0], "pm": plan["rota"][i][1],
			"intensity": plan["inten"][i],
		}
	save_state()


## Opponent-specific prep for ONE big fixture: stamp light, Match-Prep-heavy
## per-date plans on the `days_before` days leading into it (template
## untouched, other matchdays skipped — their auto handling stays in charge).
## Day -1 becomes a full double-prep day, day -2 prep + sharpness work,
## day -3 technique + prep. Match Prep sessions raise condition, which the
## match sim rates battlers by — so prepping into a fixture is a real edge.
func plan_prep_for_fixture(fx_date: String, days_before: int = 3) -> void:
	var ov: Dictionary = state["overrides"]
	var rota := {1: ["match_prep", "match_prep"], 2: ["match_prep", "speed"],
		3: ["technique", "match_prep"]}
	for i in range(1, clampi(days_before, 1, 3) + 1):
		var date := Season.date_add(fx_date, -i)
		if date < GameState.current_date:
			continue
		if not player_fixture_on(date).is_empty():
			continue  # another fixture sits there — leave its auto handling alone
		ov[date] = {"am": rota[i][0], "pm": rota[i][1], "intensity": "light"}
	save_state()


## Copy one visible calendar week (its overrides layered on the template) back
## into the repeating weekday template, then drop those now-redundant edits.
func save_week_as_template(start_date: String) -> void:
	for i in 7:
		var date := Season.date_add(start_date, i)
		var day := _weekday_key(date)
		var ov := date_override(date)
		var cell: Dictionary = state["schedule"][day]
		state["schedule"][day] = {
			"am": ov.get("am", cell["am"]), "pm": ov.get("pm", cell["pm"]),
		}
		state["intensity"][day] = ov.get("intensity", state["intensity"][day])
		(state["overrides"] as Dictionary).erase(date)
	save_state()


## Dates (sorted) with a per-date plan within the next `days` days.
func planned_custom_dates(days: int = 28) -> Array:
	var horizon := Season.date_add(GameState.current_date, days)
	var out: Array = []
	for date in (state.get("overrides", {}) as Dictionary):
		if str(date) >= GameState.current_date and str(date) <= horizon:
			out.append(str(date))
	out.sort()
	return out


## Rewrite the repeating weekday template from a preset plan.
func apply_preset(preset: String) -> void:
	if not PRESET_PLANS.has(preset):
		return
	var plan: Dictionary = PRESET_PLANS[preset]
	for i in DAY_KEYS.size():
		state["schedule"][DAY_KEYS[i]] = {"am": plan["rota"][i][0], "pm": plan["rota"][i][1]}
		state["intensity"][DAY_KEYS[i]] = plan["inten"][i]
	save_state()


# ------------------------------------------------------------------ daily tick

func _weekday_key(date: String) -> String:
	var dict := Time.get_datetime_dict_from_datetime_string(date + "T00:00:00", true)
	# Time weekday: 0 = Sunday .. 6 = Saturday
	var map := ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
	return map[int(dict.get("weekday", 0))]


func _focus_mult(ms: Dictionary, stat: String) -> float:
	var f: String = ms.get("focus", "")
	if f == "":
		return 1.0
	return 1.75 if f == stat else 0.75


func _youth_bonus(inst: Dictionary, cat: String) -> float:
	if int(inst.get("age_months", 48)) > 36:
		return 1.0
	var coach := staff_by_name(state["coaches"].get(cat, ""))
	if not coach.is_empty() and int(coach["ratings"].get("youth", 0)) >= 13:
		return 1.12
	return 1.0


func _strain_penalty(s: float) -> float:
	if s > 85.0:
		return 0.3
	if s > 70.0:
		return 0.6
	return 1.0


func _process_day(date: String) -> void:
	_validate_mentoring(date)
	var plan := effective_plan(date)
	var inten: String = plan["intensity"]
	var im := float(INTENSITY_MULT[inten])
	var is_matchday: bool = plan["kind"] == "matchday" or plan["kind"] == "matchday_manual"
	var starters: Array = likely_starter_uids() if is_matchday else []
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.career_seed + absi(date.hash())

	for inst in squad():
		var uid: String = inst["uid"]
		var ms := mon_state(uid)
		var sp: Dictionary = DataStore.species(int(inst["species_id"]))
		var g := growth_mult(sp.get("growth", "medium_fast"))
		var a := age_mult(int(inst.get("age_months", 48)))
		var pen := _strain_penalty(float(ms["strain"]))
		# Personal workload: resolved from the auto rules (strain/age) or the
		# manual override. Scales this individual's gains AND strain intake.
		var lkey := effective_load(inst)
		var lm := float(LOAD_MULT[lkey])
		var lsm := float(LOAD_STRAIN[lkey])
		# Mentoring: a junior in a group trains in its mentor's shadow — extra
		# development, a growth-focus bias from the mentor's personality, and
		# (Professional mentors) better strain discipline. Attributed below.
		var me := mentoring_effect(uid)
		var strain_delta := 0.0

		for slot in ["am", "pm"]:
			var f: String = plan[slot]
			if f == "rest":
				strain_delta -= 10.0
				continue
			if f == "match":
				continue  # match strain applied once per matchday below
			if f == "match_prep":
				if lkey == "none":
					strain_delta -= 6.0  # sits prep out, does recovery work
					continue
				# Light sharpening work before a fixture: real condition gain
				# (the sim picks and rates battlers by condition), barely any strain.
				strain_delta += PREP_STRAIN
				inst["condition"] = mini(100, int(inst.get("condition", 90))
					+ maxi(1, int(round(1.6 * coach_mult("recovery")))))
				continue
			if lkey == "none":
				# Individually rested: skips the field session entirely and
				# does pool/physio recovery work instead.
				strain_delta -= 6.0
				continue
			var session_strain := float(INTENSITY_STRAIN[inten]) * lsm * (1.15 if a < 0.7 else 1.0)
			if not me.is_empty():
				session_strain *= float(me["strain_mult"])
			strain_delta += session_strain
			if f == "technique":
				continue  # handled by the move pipeline below
			var weights: Dictionary = FOCUS_STATS[f]
			for stat in weights:
				var v: float = weights[stat] * GAIN_SCALE * im * lm * coach_mult(f) * g * a
				v *= _focus_mult(ms, stat) * _youth_bonus(inst, f) * pen
				v *= rng.randf_range(0.85, 1.15)
				if not me.is_empty():
					var mv_ := v * float(me["mult"]) * float((me["stat_mult"] as Dictionary).get(stat, 1.0))
					ms["mentor_pts"] = float(ms.get("mentor_pts", 0.0)) + (mv_ - v)
					v = mv_
				ms["acc"][stat] = float(ms["acc"][stat]) + v
				_maybe_convert_iv(inst, ms, stat, not me.is_empty())

		# --- the fixture itself is a physical load (starters carry most of it)
		if is_matchday:
			strain_delta += MATCH_STRAIN_STARTER if starters.has(uid) else MATCH_STRAIN_BENCH

		# --- move learning pipeline
		if ms["move"] != null:
			var mv: Dictionary = ms["move"]
			mv["progress"] = float(mv["progress"]) + move_learn_rate(inst) * pen * rng.randf_range(0.9, 1.1)
			if float(mv["progress"]) >= 100.0:
				_complete_move(inst, ms, mv, date)

		# --- strain / fitness / knocks
		strain_delta -= _recovery_rate()
		ms["strain"] = clampf(float(ms["strain"]) + strain_delta, 0.0, 100.0)
		var target_fit := 100.0 - float(ms["strain"]) * 0.55
		var fit := float(inst.get("fitness", 85))
		inst["fitness"] = int(round(clampf(fit + clampf((target_fit - fit) * 0.15, -3.0, 2.0), 20.0, 100.0)))
		var knock_risk := (float(ms["strain"]) - 80.0) * 0.006
		if lkey == "double":
			knock_risk *= 1.5  # forcing double sessions on a strained body
		if float(ms["strain"]) > 80.0 and rng.randf() < knock_risk:
			inst["condition"] = maxi(35, int(inst.get("condition", 90)) - rng.randi_range(12, 20))
			ms["strain"] = clampf(float(ms["strain"]) - 25.0, 0.0, 100.0)
			GameState.add_inbox_message(date, "%s picked up a training knock" % _display_name(inst),
				"%s was pushed too hard in %s training and picked up a knock. Condition dropped to %d%%. The physio recommends lowering training intensity or scheduling recovery sessions." %
				[_display_name(inst), FOCUS_LABELS.get(str(plan["am"]), "team"), int(inst["condition"])])

		# --- pushback: individuals react to a FORCED workload (auto never
		# complains — that is the payoff for letting the rules manage them).
		var reaction := workload_reaction(inst)
		if reaction == "overworked":
			if rng.randf() < 0.35:
				inst["morale"] = maxi(20, int(inst.get("morale", 70)) - 1)
			if str(ms.get("complained", "")) == "" \
					or Season.date_add(str(ms["complained"]), 7) <= date:
				ms["complained"] = date
				GameState.add_inbox_message(date,
					"%s is unhappy with the training workload" % _display_name(inst),
					"%s has been forced onto %s training while carrying %d%% strain and is reacting badly — morale is down to %d%% and the physio warns the injury risk is climbing. Drop the individual load to Light, or set it to Automatic and let the staff manage it." %
					[_display_name(inst), LOAD_LABELS[lkey], int(ms["strain"]), int(inst.get("morale", 70))])
		elif reaction == "wants_more":
			if rng.randf() < 0.2:
				inst["morale"] = maxi(20, int(inst.get("morale", 70)) - 1)
			if str(ms.get("complained", "")) == "" \
					or Season.date_add(str(ms["complained"]), 10) <= date:
				ms["complained"] = date
				GameState.add_inbox_message(date,
					"%s wants to train more" % _display_name(inst),
					"%s is fresh (%d%% strain) and at a rapid stage of development, but is being held on a %s individual load. The coaches feel valuable growth is being wasted; morale will suffer if this continues." %
					[_display_name(inst), int(ms["strain"]), LOAD_LABELS[load_setting(uid)]])

		# --- mentoring morale: juniors are lifted by the guidance; the veteran
		# gets renewed purpose from passing its craft on (both capped at 95).
		if not me.is_empty() and rng.randf() < 0.15:
			inst["morale"] = mini(95, int(inst.get("morale", 70)) + 1)
		if is_mentor(uid) and rng.randf() < 0.12:
			inst["morale"] = mini(95, int(inst.get("morale", 70)) + 1)

		# --- daily stat snapshot for the development report (keep ~10 weeks)
		var snaps: Array = ms["snaps"]
		snaps.append({"date": date, "stats": current_stats(inst)})
		if snaps.size() > 70:
			snaps.pop_front()

	# weekly training report to the inbox (Sunday evening)
	if plan["day"] == "sun" and not (state["week_gains"] as Dictionary).is_empty():
		_send_week_report(date)
		state["week_gains"] = {}


func _maybe_convert_iv(inst: Dictionary, ms: Dictionary, stat: String, mentored: bool = false) -> void:
	var iv := int(inst["ivs"].get(stat, 8))
	while iv < 15 and float(ms["acc"][stat]) >= iv_cost(iv):
		ms["acc"][stat] = float(ms["acc"][stat]) - iv_cost(iv)
		iv += 1
		inst["ivs"][stat] = iv
		ms["gained"][stat] = int(ms["gained"][stat]) + 1
		if mentored:
			ms["mentor_ivs"] = int(ms.get("mentor_ivs", 0)) + 1
		var wk: Dictionary = state["week_gains"]
		var key := "%s|%s" % [inst["uid"], stat]
		wk[key] = int(wk.get(key, 0)) + 1
	if iv >= 15:
		ms["acc"][stat] = minf(float(ms["acc"][stat]), 2.0)


func _complete_move(inst: Dictionary, ms: Dictionary, mv: Dictionary, date: String) -> void:
	var moves: Array = inst.get("moves", [])
	var slot := clampi(int(mv["slot"]), 0, 3)
	var old := ""
	if moves.size() >= 4:
		old = str(moves[slot])
		moves[slot] = mv["name"]
	else:
		moves.append(mv["name"])
	inst["moves"] = moves
	(ms["learned"] as Array).append({"move": mv["name"], "date": date})
	ms["move"] = null
	var body := "%s has mastered %s on the training ground" % [_display_name(inst), mv["name"]]
	if old != "":
		body += ", replacing %s" % old
	body += ". The move is available for selection immediately."
	GameState.add_inbox_message(date, "%s has learned %s!" % [_display_name(inst), mv["name"]], body)


func _send_week_report(date: String) -> void:
	var lines: Array = []
	var by_mon := {}
	for key in state["week_gains"]:
		var parts: PackedStringArray = str(key).split("|")
		var inst := _find_instance(parts[0])
		if inst.is_empty():
			continue
		var nm := _display_name(inst)
		var mentor := mentor_of(str(inst["uid"]))
		if not mentor.is_empty():
			nm += " (learning from %s)" % _display_name(mentor)
		if not by_mon.has(nm):
			by_mon[nm] = []
		by_mon[nm].append("%s +%d" % [STAT_LABELS[parts[1]], int(state["week_gains"][key])])
	for nm in by_mon:
		lines.append("%s: %s" % [nm, ", ".join(by_mon[nm])])
	if lines.is_empty():
		return
	GameState.add_inbox_message(date, "Weekly training report",
		"Development gains this week:\n" + "\n".join(lines))


func _display_name(inst: Dictionary) -> String:
	var nn = inst.get("nickname")
	return str(nn) if nn else str(inst.get("species", "?"))


# ------------------------------------------------------------------ report helpers

func current_stats(inst: Dictionary) -> Dictionary:
	var sp: Dictionary = DataStore.species(int(inst["species_id"]))
	var out := {}
	for s in STATS:
		out[s] = DataStore.calc_stat(int(sp["base"][s]), int(inst["ivs"].get(s, 8)),
			int(inst.get("level", 20)), s == "hp")
	return out


## Stat deltas over roughly the last `days` days of snapshots.
func deltas(inst: Dictionary, days: int = 28) -> Dictionary:
	var ms := mon_state(inst["uid"])
	var snaps: Array = ms["snaps"]
	var now := current_stats(inst)
	var out := {}
	if snaps.is_empty():
		for s in STATS:
			out[s] = 0
		return out
	var idx := maxi(0, snaps.size() - days)
	var base: Dictionary = snaps[idx]["stats"]
	for s in STATS:
		out[s] = int(now[s]) - int(base.get(s, now[s]))
	return out


func total_gained(uid: String) -> int:
	var g: Dictionary = mon_state(uid)["gained"]
	var t := 0
	for s in g:
		t += int(g[s])
	return t


func days_tracked(uid: String) -> int:
	return (mon_state(uid)["snaps"] as Array).size()
