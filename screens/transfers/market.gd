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
var assignments: Array = []         # [{scout, kind:"target"|"focus", uid, focus_type, region, travel_left, started}]
var reports: Dictionary = {}        # uid -> report dict
var offers_out: Array = []          # our bids / loan offers / contract offers (structured)
var offers_in: Array = []           # AI bids for our squad (structured)
var deals: Array = []               # completed deals, newest first
var payments: Array = []            # scheduled installments [{due, amount, club_id, dir:"out"|"in", name}]
var last_tick: String = ""
var last_window_key: String = "closed"  # open-date of the window we last saw open ("" = between windows)
var offer_recent: Dictionary = {}   # unsolicited-bid cool-downs: "uid:x"/"club:y"/"any" -> last bid date
var _next_id: int = 1

# --- recruitment pipeline (the PUSH side of the market) ---
var shortlist: Array = []           # uids, in priority order (top = highest)
var recs: Array = []                # scout recommendation queue [{id, uid, scout, date, ability, potential, note, status:"new"|"accepted"|"dismissed"}]
var agent_offers: Array = []        # players touted TO us by agents [{id, uid, kind:"fa"|"club", date, expires, ask, pitch, status:"open"|"expired"|"dismissed"}]
var rumours: Array = []             # rumour mill, newest first [{id, date, kind, uid, club_id, other_id, strength, text, came_true, due}]
var listed: Dictionary = {}         # uid -> until-date: transfer-listed by their club (ask price slashed)
var scout_pool: Array = []          # hireable scouts this month [{name, ja, jp, region, wage}]
var scout_pool_month: String = ""
var dof: Dictionary = {}            # Director of Battling delegation flags (see DOF_DEFAULTS)
var dof_log: Array = []             # DoF activity feed, newest first [{date, text}]
var seeded_window: String = ""      # open-date of the window whose rumours were seeded

# --- external world (overseas leagues + regional prospect pools) ---
# The full rosters are regenerated deterministically from the career seed on
# demand; only the uids that LEFT the external world are persisted.
var ext_removed: Dictionary = {}    # uid -> true (signed/hijacked out of the ext world)
var scout_loc: Dictionary = {}      # scout name -> region they are currently in
var _ext_clubs: Array = []          # cached virtual clubs [{id,name,short,reputation,finances,squad,region,league}]
var _ext_prospects: Array = []      # cached prospect insts (carry a "region" field)
var _ext_index: Dictionary = {}     # uid -> {"inst":.., "club_id":.., "pool":..}
var _ext_built_seed: int = -2

const DOF_DEFAULTS := {"handle_bids": false, "pursue_shortlist": false, "auto_scout": false, "max_over_pct": 10}
const LISTING_DISCOUNT := 0.65      # transfer-listed players go for 65% of the normal ask
const AGENT_GREASE := 0.88          # agent-touted deals: the seller's threshold drops to 88%
const MAX_HIRED_SCOUTS := 4

# Scouting regions: every species belongs to one (by primary type). A scout has
# a home region — they work faster there, and a region focus builds a knowledge
# network across it. This is the FM regional-scouting model in Indigo colours.
# The two overseas regions have no type mapping: only externally-generated
# targets (overseas leagues + their prospect pools) live there.
const REGIONS := {
	"Verdant Interior": ["grass", "bug", "poison"],
	"Coastal Circuit": ["water", "ice"],
	"Volcanic Belt": ["fire", "rock", "ground"],
	"Storm Plateau": ["electric", "flying", "dragon"],
	"Old Capital": ["normal", "psychic", "ghost", "fighting"],
	"Sevii Islands": [],
	"Orange Archipelago": [],
}
const OVERSEAS_REGIONS := ["Sevii Islands", "Orange Archipelago"]

# ---- the staged-knowledge economy -----------------------------------------
# Knowledge is a 0..100 ladder climbed in real days, not a binary unlock.
# Each stage unlocks more of the truth; uncertainty bands narrow continuously.
const STAGES := [
	{"min": 0.0, "name": "Untracked", "unlocks": "name and level only"},
	{"min": 1.0, "name": "Rumour", "unlocks": "wide value + attribute bands"},
	{"min": 25.0, "name": "Initial assessment", "unlocks": "bands tighten, region intel"},
	{"min": 50.0, "name": "Part scouted", "unlocks": "move set + interim report (star bands)"},
	{"min": 75.0, "name": "Detailed", "unlocks": "tight bands, reliable wage read"},
	{"min": 100.0, "name": "Full report", "unlocks": "exact attributes, IVs, final stars"},
]
const FOCUS_KNOW_CAP := 60.0        # a focus sweep can never produce a full book
const FOCUS_TARGETS_PER_DAY := 3    # breadth throttle: a sweep touches 3 targets a day
const INTERIM_AT := 50.0            # crossing this files a preliminary report

# Travel: scouts are physically somewhere. Crossing the map costs real days
# before any knowledge flows; the overseas leagues are a boat ride away.
const TRAVEL_DOMESTIC := 2
const TRAVEL_OVERSEAS := 5
const TRAVEL_BETWEEN_OVERSEAS := 4

# Overseas leagues: 2 x 8 clubs whose battlers are transfer-eligible (no
# loans across the water). Generated deterministically from the career seed
# on demand — only departures (ext_removed) are persisted, so saves stay light.
const EXT_LEAGUES := [
	{
		"name": "Sevii Island League", "prefix": "xsev", "region": "Sevii Islands",
		"clubs": [
			["Knot Island Krakens", "KNO"], ["Boon Island Boatmen", "BOO"],
			["Kin Island Kestrels", "KIN"], ["Floe Island Frostbites", "FLO"],
			["Chrono Island Watchers", "CHR"], ["Fortune Island Fates", "FTN"],
			["Quest Island Pilgrims", "QUE"], ["Navel Rock Navigators", "NAV"],
		],
	},
	{
		"name": "Orange Archipelago League", "prefix": "xora", "region": "Orange Archipelago",
		"clubs": [
			["Mikan Mariners", "MIK"], ["Sunburst Athletic", "SUN"],
			["Trovita Tridents", "TRO"], ["Kumquat Kings", "KUM"],
			["Pummelo Stadium", "PUM"], ["Tangelo Bay", "TGB"],
			["Mandarin North", "MDN"], ["Valencia Isle", "VLC"],
		],
	},
]
const EXT_SQUAD_SIZE := 13
# Regional prospect pools: every region runs a youth intake, generated the
# same deterministic way. Domestic pools are bigger than the island ones.
const EXT_PROSPECTS_DOMESTIC := 34
const EXT_PROSPECTS_OVERSEAS := 24

const SCOUT_FIRST := ["Marta", "Kenji", "Rosa", "Dario", "Yuki", "Petra", "Silas", "Noor",
	"Ivo", "Carmen", "Talia", "Bruno", "Sachi", "Olek", "Ines", "Ramon", "Freya", "Goro"]
const SCOUT_LAST := ["Okabe", "Ferreira", "Lindqvist", "Marchetti", "Sunada", "Volkov",
	"Reyes", "Ashford", "Kimura", "Duarte", "Novak", "Grieve", "Tanaka", "Bellamy"]

# Pacing of unsolicited incoming bids (days). Deadline pressure halves them.
const COOLDOWN_ANY := 4             # league-wide: at most one cold bid every N days
const COOLDOWN_MON := 14            # per squad member
const COOLDOWN_CLUB := 10           # per bidding club
const BIG_BID_FACTOR := 1.2         # bid >= 120% of our valuation = board-urgent

# Terminal negotiation stages (an offer in one of these is dead).
const DEAD_STAGES := ["completed", "rejected", "withdrawn", "collapsed", "hijacked"]


func _init() -> void:
	GameState.date_changed.connect(_on_date_changed)
	GameState.career_started.connect(_on_career_started)
	_load_state()
	_seed_window_rumours()


# ------------------------------------------------------------------ persistence

func save_state() -> void:
	var data := {
		"version": 5,
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
		"offer_recent": offer_recent,
		"next_id": _next_id,
		"shortlist": shortlist,
		"recs": recs,
		"agent_offers": agent_offers,
		"rumours": rumours,
		"listed": listed,
		"scout_pool": scout_pool,
		"scout_pool_month": scout_pool_month,
		"dof": dof,
		"dof_log": dof_log,
		"seeded_window": seeded_window,
		"ext_removed": ext_removed,
		"scout_loc": scout_loc,
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
	if data == null or typeof(data) != TYPE_DICTIONARY or not (int(data.get("version", 0)) in [1, 2, 3, 4, 5]):
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
	offer_recent = data.get("offer_recent", {}) if typeof(data.get("offer_recent")) == TYPE_DICTIONARY else {}
	_next_id = int(data.get("next_id", 1))
	shortlist = data.get("shortlist", [])
	recs = data.get("recs", [])
	agent_offers = data.get("agent_offers", [])
	rumours = data.get("rumours", [])
	listed = data.get("listed", {}) if typeof(data.get("listed")) == TYPE_DICTIONARY else {}
	scout_pool = data.get("scout_pool", [])
	scout_pool_month = String(data.get("scout_pool_month", ""))
	dof = DOF_DEFAULTS.duplicate()
	var saved_dof: Variant = data.get("dof", {})
	if typeof(saved_dof) == TYPE_DICTIONARY:
		for k in saved_dof:
			dof[k] = saved_dof[k]
	dof_log = data.get("dof_log", [])
	seeded_window = String(data.get("seeded_window", ""))
	ext_removed = data.get("ext_removed", {}) if typeof(data.get("ext_removed")) == TYPE_DICTIONARY else {}
	scout_loc = data.get("scout_loc", {}) if typeof(data.get("scout_loc")) == TYPE_DICTIONARY else {}
	if int(data.get("version", 0)) == 1:
		_migrate_v1_offers()
	if int(data.get("version", 0)) <= 4:
		_migrate_v4_assignments()


func _migrate_v4_assignments() -> void:
	# Pre-v5 target assignments were a fixed countdown to a 100% unlock; lift
	# them into the staged model (already-arrived, progress rides `knowledge`).
	for a in assignments:
		if not a.has("travel_left"):
			a["travel_left"] = 0
		if not a.has("region"):
			var t := find_target(String(a.get("uid", "")))
			a["region"] = region_of(t["inst"]) if not t.is_empty() else ""
		a.erase("days_left")
		a.erase("days_total")


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
	offer_recent = {}
	_next_id = 1
	shortlist = []
	recs = []
	agent_offers = []
	rumours = []
	listed = {}
	scout_pool = []
	scout_pool_month = ""
	dof = DOF_DEFAULTS.duplicate()
	dof_log = []
	seeded_window = ""
	ext_removed = {}
	scout_loc = {}
	_ext_built_seed = -2


func _on_career_started() -> void:
	_load_state()
	_seed_window_rumours()
	market_updated.emit()


# ------------------------------------------------------------------ external world
# The domestic league alone is ~260 targets — a fortnight of scouting. The
# external world (2 overseas leagues + 7 regional prospect pools) pushes the
# scoutable universe to ~700, regenerated deterministically from the career
# seed so only DEPARTURES are ever saved.

func is_ext_uid(uid: String) -> bool:
	return uid.begins_with("x")


func is_ext_club(club_id: String) -> bool:
	return club_id.begins_with("x")


func _ensure_ext_world() -> void:
	if _ext_built_seed == GameState.career_seed:
		return
	_ext_built_seed = GameState.career_seed
	_ext_clubs = []
	_ext_prospects = []
	_ext_index = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.career_seed ^ 0x5EA5C0DE
	# species tiers by BST (no Mewtwo/Mew/Ditto), mirroring the domestic gen
	var usable: Array = DataStore.pokemon.filter(func(p): return not (int(p["id"]) in [150, 151, 132]))
	usable = usable.duplicate()
	usable.sort_custom(func(a, b):
		var sa := 0
		for k in a["base"]:
			sa += int(a["base"][k])
		var sb := 0
		for k in b["base"]:
			sb += int(b["base"][k])
		return sa < sb)
	# --- overseas leagues
	for lg in EXT_LEAGUES:
		var n := 0
		for cdef in lg["clubs"]:
			n += 1
			var cid: String = "%sc%d" % [String(lg["prefix"]), n]
			var rep := 5 + int(rng.randi() % 10)
			var lo := mini(usable.size() - 40, maxi(0, (rep - 5) * 9))
			var pool: Array = usable.slice(lo, lo + 70)
			var squad: Array = []
			for s in EXT_SQUAD_SIZE:
				var sp: Dictionary = pool[rng.randi() % pool.size()]
				squad.append(_make_ext_instance(rng, sp, 20 + rep, mini(58, 30 + rep * 2),
					String(lg["region"]), "%sm%d_%d" % [String(lg["prefix"]), n, s]))
			_ext_clubs.append({
				"id": cid, "name": String(cdef[0]), "short": String(cdef[1]),
				"reputation": rep, "region": String(lg["region"]), "league": String(lg["name"]),
				"finances": {"balance": (150 + int(rng.randi() % 700)) * 1000 + rep * 40000},
				"squad": squad, "staff": [],
			})
	# --- regional prospect pools (youth intakes everywhere, FM-style)
	var ri := 0
	for reg in REGIONS:
		ri += 1
		var count: int = EXT_PROSPECTS_OVERSEAS if reg in OVERSEAS_REGIONS else EXT_PROSPECTS_DOMESTIC
		var reg_pool: Array = usable
		if not REGIONS[reg].is_empty():
			reg_pool = usable.filter(func(p): return String(p["types"][0]) in REGIONS[reg])
			if reg_pool.is_empty():
				reg_pool = usable
		for k in count:
			var sp2: Dictionary = reg_pool[rng.randi() % reg_pool.size()]
			var inst := _make_ext_instance(rng, sp2, 5, 20, String(reg), "xyth%d_%d" % [ri, k])
			inst["potential"] = 6 + int(rng.randi() % 15)
			inst["scouted_pct"] = 0
			inst["age_months"] = 12 + int(rng.randi() % 34)
			inst["contract"]["salary"] = maxi(50, int(float(inst["contract"]["salary"]) * 0.35))
			_ext_prospects.append(inst)
	# strip anything that already left the external world, then index
	for c in _ext_clubs:
		c["squad"] = c["squad"].filter(func(i): return not ext_removed.has(String(i["uid"])))
		for inst in c["squad"]:
			_ext_index[String(inst["uid"])] = {"inst": inst, "club_id": String(c["id"]), "pool": "club"}
	_ext_prospects = _ext_prospects.filter(func(i): return not ext_removed.has(String(i["uid"])))
	for inst in _ext_prospects:
		_ext_index[String(inst["uid"])] = {"inst": inst, "club_id": "", "pool": "prospect"}


func _make_ext_instance(rng: RandomNumberGenerator, sp: Dictionary, lvl_lo: int, lvl_hi: int,
		region: String, uid: String) -> Dictionary:
	var level := lvl_lo + int(rng.randi() % maxi(1, lvl_hi - lvl_lo + 1))
	var ivs := {}
	for k in ["hp", "atk", "def", "spa", "spd", "spe"]:
		ivs[k] = int(rng.randi() % 16)
	var learn: Array = sp["learnset"].duplicate()
	var moves: Array = []
	while moves.size() < mini(4, learn.size()) and not learn.is_empty():
		moves.append(learn.pop_at(rng.randi() % learn.size()))
	var b := 0
	for k in sp["base"]:
		b += int(sp["base"][k])
	var salary := int(float(b * 2 + level * 40) * (0.75 + rng.randf() * 0.4))
	var exp_m := 10 + int(rng.randi() % 37)
	var yr := 2026 + int(float(7 + exp_m) / 12.0)
	var mo := (7 + exp_m) % 12 + 1
	return {
		"uid": uid, "species_id": int(sp["id"]), "species": String(sp["name"]),
		"nickname": null, "level": level, "ivs": ivs, "moves": moves,
		"held_item": null, "condition": 70 + int(rng.randi() % 31),
		"fitness": 75 + int(rng.randi() % 26), "morale": 50 + int(rng.randi() % 46),
		"age_months": 12 + int(rng.randi() % 109), "region": region,
		"contract": {"salary": salary, "expiry": "%04d-%02d-30" % [yr, mo]},
	}


func ext_clubs() -> Array:
	_ensure_ext_world()
	return _ext_clubs


func _remove_ext(uid: String) -> void:
	## A battler leaves the external world for good (signed by us, or poached
	## into the domestic league). Only this delta is persisted.
	ext_removed[uid] = true
	var e: Dictionary = _ext_index.get(uid, {})
	if e.is_empty():
		return
	if String(e["club_id"]) != "":
		for c in _ext_clubs:
			if String(c["id"]) == String(e["club_id"]):
				c["squad"].erase(e["inst"])
	else:
		_ext_prospects.erase(e["inst"])
	_ext_index.erase(uid)


func club_of(club_id: String) -> Dictionary:
	## GameState.club plus the virtual overseas clubs. Use this anywhere a
	## club_id might belong to the external world.
	if is_ext_club(club_id):
		_ensure_ext_world()
		for c in _ext_clubs:
			if String(c["id"]) == club_id:
				return c
		return {}
	return GameState.club(club_id)


# ------------------------------------------------------------------ world queries

func find_target(uid: String) -> Dictionary:
	## Returns {inst, club_id ("" if unattached), pool: "club"|"fa"|"prospect"|"mine"} or {}.
	if is_ext_uid(uid):
		_ensure_ext_world()
		var e: Dictionary = _ext_index.get(uid, {})
		if not e.is_empty():
			return {"inst": e["inst"], "club_id": e["club_id"], "pool": e["pool"]}
		# fall through: an ext-born battler may since have joined a domestic club
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
	## Everything on the market: other clubs' squads + free agents + prospects
	## + the whole external world (overseas leagues, regional prospect pools).
	_ensure_ext_world()
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
	for c in _ext_clubs:
		for inst in c["squad"]:
			out.append({"inst": inst, "club_id": c["id"], "pool": "club"})
	for inst in _ext_prospects:
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
	var v := value_of(inst) * importance_of(inst, club_of(club_id))
	if is_listed(String(inst["uid"])):
		v *= LISTING_DISCOUNT   # club wants them gone — the rumour mill told you first
	return int(round(v / 1000.0)) * 1000


func is_listed(uid: String) -> bool:
	return listed.has(uid) and String(listed[uid]) >= GameState.current_date


func wage_bill(club: Dictionary) -> int:
	var s := 0
	for inst in club["squad"]:
		var sal := int(inst["contract"]["salary"])
		if inst.has("loan") and GameState.is_player_club(club["id"]):
			s += int(round(float(sal) * float(inst["loan"].get("wage_split", 100)) / 100.0))
		else:
			s += sal
	for st in club["staff"]:
		s += int(st.get("wage", 0))   # hired scouts draw from the same wage budget
	return s


func wage_room() -> int:
	var pc: Dictionary = GameState.player_club()
	return int(pc["finances"]["wage_budget"]) - wage_bill(pc)


## What the manager may actually put into a deal right now: the board's
## transfer budget, never more than the cash physically in the bank.
func spendable_budget() -> int:
	var fin: Dictionary = GameState.player_club()["finances"]
	return mini(int(fin["balance"]), int(fin.get("transfer_budget", int(fin["balance"]))))


## Mirror a player-club cash move into the board's transfer budget:
## fees/bonuses paid reduce it, sales/sell-ons/installments received top it
## back up (capped at the bank balance inside GameState).
func _adjust_player_budget(delta: int) -> void:
	GameState.adjust_transfer_budget(GameState.world["meta"]["player_club_id"], delta)


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
		_seed_window_rumours()
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
	var seller: Dictionary = club_of(t["club_id"])
	var pc: Dictionary = GameState.player_club()
	var rep_factor := 1.0 + float(int(seller["reputation"]) - int(pc["reputation"])) * 0.015
	var base := float(ask_price(t["inst"], t["club_id"])) * rep_factor
	if not agent_offer_for(uid).is_empty():
		base *= AGENT_GREASE   # the agent has done half the negotiating already
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
	if is_ext_club(String(t["club_id"])):
		return "Negotiators: overseas clubs will not loan battlers abroad — a permanent deal is the only route."
	var imp := importance_of(t["inst"], club_of(t["club_id"]))
	if imp >= 1.5 or club_of(t["club_id"])["squad"].size() <= 8:
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
	var k := float(knowledge.get(uid, -1.0))
	if k >= 100.0:
		return 100.0
	var t := find_target(uid)
	if not t.is_empty() and t["pool"] == "mine":
		return 100.0
	if k >= 0.0:
		return k
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


func assignment_eta(a: Dictionary) -> int:
	## Estimated days (travel + fieldwork) until this target watch files its
	## full report. -1 for focus assignments / dead targets.
	if String(a.get("kind", "")) != "target":
		return -1
	var scout := _scout_by_name(String(a["scout"]))
	var t := find_target(String(a.get("uid", "")))
	if scout.is_empty() or t.is_empty():
		return -1
	var work := int(ceil((100.0 - knowledge_of(String(a["uid"]))) / scout_daily_rate(scout, region_of(t["inst"]))))
	return int(a.get("travel_left", 0)) + maxi(0, work)


func region_of(inst: Dictionary) -> String:
	# External-world targets carry their region; domestic ones map by primary type.
	if inst.has("region"):
		return String(inst["region"])
	var sp: Dictionary = DataStore.species(int(inst["species_id"]))
	var t0 := String(sp["types"][0])
	for r in REGIONS:
		if t0 in REGIONS[r]:
			return r
	return "Old Capital"


func is_domestic_region(region: String) -> bool:
	return not (region in OVERSEAS_REGIONS)


func travel_days(from_region: String, to_region: String) -> int:
	## Real days in transit before a scout can work the new patch.
	if from_region == to_region or from_region == "" or to_region == "":
		return 0
	if is_domestic_region(from_region) and is_domestic_region(to_region):
		return TRAVEL_DOMESTIC
	if not is_domestic_region(from_region) and not is_domestic_region(to_region):
		return TRAVEL_BETWEEN_OVERSEAS
	return TRAVEL_OVERSEAS


func scout_location(scout: Dictionary) -> String:
	## Where the scout physically is right now (home region until they move).
	return String(scout_loc.get(String(scout["name"]), scout_region(scout)))


func scout_region(scout: Dictionary) -> String:
	## A scout's home network. Hired scouts carry it; legacy coach-scouts get a
	## deterministic DOMESTIC one so the region system covers everybody.
	if scout.has("region"):
		return String(scout["region"])
	var names: Array = REGIONS.keys().filter(func(r): return is_domestic_region(String(r)))
	return names[absi(String(scout["name"]).hash() + GameState.career_seed) % names.size()]


func scout_familiarity(scout: Dictionary, region: String) -> float:
	## Speed/accuracy multiplier for THIS scout working THIS region.
	## Home network 1.3x; another domestic patch baseline; overseas cold 0.7x.
	if scout_region(scout) == region:
		return 1.3
	if region in OVERSEAS_REGIONS:
		return 0.7
	return 1.0


func scout_daily_rate(scout: Dictionary, region: String) -> float:
	## Knowledge points gained per working day on a dedicated target watch.
	## Even an elite scout on home turf needs ~9-10 days for a full book;
	## a journeyman working cold overseas needs three weeks plus the boat.
	var ja := int(scout["ratings"]["judging_ability"])
	return (2.5 + float(ja) * 0.32) * scout_familiarity(scout, region)


func scout_days_for(scout: Dictionary, uid: String = "") -> int:
	## Estimated TOTAL days (travel + fieldwork) to take this target from
	## current knowledge to a full report.
	var region := scout_location(scout)
	var know := 0.0
	if uid != "":
		var t := find_target(uid)
		if not t.is_empty():
			region = region_of(t["inst"])
			know = knowledge_of(uid)
	var work := int(ceil((100.0 - know) / scout_daily_rate(scout, region)))
	return travel_days(scout_location(scout), region) + maxi(1, work)


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
	var reg := region_of(t["inst"])
	assignments.append({
		"scout": scout_name, "kind": "target", "uid": uid, "focus_type": "",
		"region": reg, "travel_left": travel_days(scout_location(scout), reg),
		"started": GameState.current_date,
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
	# Region focuses require presence: the scout travels there first.
	var dest := ""
	if REGIONS.has(focus_type):
		dest = focus_type
	assignments.append({
		"scout": scout_name, "kind": "focus", "uid": "", "focus_type": focus_type,
		"region": dest, "travel_left": travel_days(scout_location(scout), dest) if dest != "" else 0,
		"started": GameState.current_date,
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


func knowledge_stage(uid: String) -> Dictionary:
	return stage_for(knowledge_of(uid))


func stage_for(know: float) -> Dictionary:
	## The knowledge stage a 0..100 value sits in: {idx, name, unlocks, min}.
	var best := 0
	for i in STAGES.size():
		if know >= float(STAGES[i]["min"]):
			best = i
	var s: Dictionary = STAGES[best].duplicate()
	s["idx"] = best
	return s


func full_report_count() -> int:
	var n := 0
	for uid in knowledge:
		if float(knowledge[uid]) >= 100.0:
			n += 1
	return n


func _bump_knowledge(uid: String, gain: float, scout_name: String, from_focus: bool) -> void:
	## The single choke point every knowledge gain flows through. Fires the
	## stage transitions: interim report at 50, full report + unlock at 100.
	var before := knowledge_of(uid)
	var cap := FOCUS_KNOW_CAP if from_focus else 100.0
	if before >= cap:
		return
	var now := minf(cap, before + gain)
	knowledge[uid] = now
	if before < INTERIM_AT and now >= INTERIM_AT:
		_generate_report(uid, scout_name, false)
		var t := find_target(uid)
		if not t.is_empty():
			GameState.add_inbox_message(GameState.current_date,
				"Interim scout report: %s (part scouted)" % display_name(t["inst"]),
				"%s has filed a preliminary assessment of %s — move set confirmed, star ratings given as a RANGE that narrows with more time in the field. Full attributes still need a completed watch. See Transfers > Scouting." % [
					scout_name, display_name(t["inst"])])
	if before < 100.0 and now >= 100.0:
		_generate_report(uid, scout_name, true)


func _tick_scouting(_rng: RandomNumberGenerator) -> void:
	var done: Array = []
	for a in assignments:
		var scout := _scout_by_name(String(a["scout"]))
		if scout.is_empty():
			done.append(a)   # scout left the club — assignment dies
			continue
		# travel first: no knowledge flows while the scout is in transit
		if int(a.get("travel_left", 0)) > 0:
			a["travel_left"] = int(a["travel_left"]) - 1
			if int(a["travel_left"]) <= 0 and String(a.get("region", "")) != "":
				scout_loc[String(scout["name"])] = String(a["region"])
			continue
		if a["kind"] == "target":
			var uid: String = a["uid"]
			var t := find_target(uid)
			if t.is_empty() or t["pool"] == "mine":
				done.append(a)
				GameState.add_inbox_message(GameState.current_date,
					"Scouting mission over: target unavailable",
					"%s's watch has ended — the target is no longer on the market." % String(a["scout"]))
				continue
			var reg := region_of(t["inst"])
			_bump_knowledge(uid, scout_daily_rate(scout, reg), String(a["scout"]), false)
			if knowledge_of(uid) >= 100.0:
				done.append(a)
				GameState.add_inbox_message(GameState.current_date,
					"Full scout report: %s" % display_name(t["inst"]),
					"%s has completed the watch on %s. Exact attributes, genetics and final star ratings are unlocked in Transfers." % [
						String(a["scout"]), display_name(t["inst"])])
		else:
			# Region/type focus: a broad sweep. Builds knowledge on a few
			# matching targets a day, but can NEVER take anyone past the
			# focus cap — depth demands a dedicated target watch.
			var pool := all_targets().filter(func(t2):
				return knowledge_of(t2["inst"]["uid"]) < FOCUS_KNOW_CAP and _matches_focus(t2["inst"], a["focus_type"]))
			pool.sort_custom(func(x, y):
				return knowledge_of(x["inst"]["uid"]) > knowledge_of(y["inst"]["uid"]))
			for i in mini(FOCUS_TARGETS_PER_DAY, pool.size()):
				var inst2: Dictionary = pool[i]["inst"]
				var gain := (1.2 + float(int(scout["ratings"]["judging_ability"])) * 0.14) \
					* scout_familiarity(scout, region_of(inst2))
				_bump_knowledge(String(inst2["uid"]), gain, String(a["scout"]), true)
	for a in done:
		assignments.erase(a)


func _matches_focus(inst: Dictionary, focus_type: String) -> bool:
	if focus_type == "Any":
		return true
	if focus_type == "Prospects":
		return inst.has("potential")
	if focus_type == "Free agents":
		var t := find_target(inst["uid"])
		return not t.is_empty() and t["pool"] == "fa"
	if focus_type == "Shortlist":
		return String(inst["uid"]) in shortlist
	if REGIONS.has(focus_type):
		return region_of(inst) == focus_type
	var sp: Dictionary = DataStore.species(int(inst["species_id"]))
	return focus_type in sp["types"]


func _generate_report(uid: String, scout_name: String, final: bool = true) -> void:
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
	# Interim reports quote the CURRENT uncertainty band, never the exact figure.
	var sv := func(k: String) -> String:
		return str(int(stats[k])) if final else masked_int(uid, k, int(stats[k]))
	pros.append("Standout %s (%s) for its level" % [names[ranked[0]], sv.call(ranked[0])])
	if int(stats[ranked[1]]) > 60:
		pros.append("Strong secondary %s (%s)" % [names[ranked[1]], sv.call(ranked[1])])
	if int(stats["spe"]) >= int(stats[ranked[1]]):
		pros.append("Wins the speed tie in most match-ups")
	if final and iv_total(inst) >= 60:
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
	cons.append("Weak %s (%s) is exploitable" % [names[ranked[5]], sv.call(ranked[5])])
	if int(stats[ranked[4]]) < 45:
		cons.append("Below-par %s (%s) too" % [names[ranked[4]], sv.call(ranked[4])])
	if final and iv_total(inst) < 35:
		cons.append("Modest genetics (IV %d/90) cap its ceiling" % iv_total(inst))
	if not final:
		cons.append("Genetics unread — a full watch is needed to grade the IVs")
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

	# Uncertainty bands: an interim report gives star RANGES, not points.
	# Band width shrinks with knowledge and with the scout's skill; working an
	# unfamiliar region widens the read further. Fully-scouted = exact.
	var know := knowledge_of(uid)
	var fam := 1.0 if scout.is_empty() else scout_familiarity(scout, region_of(inst))
	var band := 0.0
	if not final:
		band = (0.5 + (100.0 - know) / 100.0 * 1.3 + float(20 - ja) * 0.04) / fam
		verdict = "PRELIMINARY (%d%% scouted) — the bands below narrow as the watch continues. %s" % [int(know), verdict]

	reports[uid] = {
		"uid": uid, "date": GameState.current_date, "scout": scout_name,
		"name": display_name(inst), "species": inst["species"],
		"types": sp["types"], "level": int(inst["level"]),
		"ability_stars": snappedf(ability, 0.5), "potential_stars": snappedf(pot, 0.5),
		"ability_lo": snappedf(clampf(ability - band, 0.5, 5.0), 0.5),
		"ability_hi": snappedf(clampf(ability + band, 0.5, 5.0), 0.5),
		"potential_lo": snappedf(clampf(pot - band * 1.2, 0.5, 5.0), 0.5),
		"potential_hi": snappedf(clampf(pot + band * 1.2, 0.5, 5.0), 0.5),
		"stage": "full" if final else "interim", "knowledge": know,
		"pros": pros, "cons": cons, "verdict": verdict,
	}
	if final:
		_maybe_recommend(uid, scout_name)


func _maybe_recommend(uid: String, scout_name: String) -> void:
	## Scouts PUSH: a strong report lands in the recommendation queue, waiting
	## for the manager to shortlist or dismiss — the FM recruitment-meeting loop.
	var r: Dictionary = reports.get(uid, {})
	if r.is_empty():
		return
	var ab := float(r["ability_stars"])
	var pot := float(r["potential_stars"])
	if ab < 3.0 and pot < 3.5:
		return
	if uid in shortlist:
		return
	for rc in recs:
		if String(rc["uid"]) == uid and String(rc["status"]) == "new":
			return
	var note: String
	if ab >= 4.0:
		note = "%s: \"A genuine difference-maker — take this to the board.\"" % scout_name
	elif ab >= 3.0:
		note = "%s: \"Would improve our first team today.\"" % scout_name
	else:
		note = "%s: \"One for the future — the ceiling is %s.\"" % [scout_name, _star_txt(pot)]
	recs.push_front({
		"id": _next_id, "uid": uid, "scout": scout_name, "date": GameState.current_date,
		"ability": ab, "potential": pot, "note": note, "status": "new",
	})
	_next_id += 1
	if recs.size() > 30:
		recs.resize(30)
	GameState.add_inbox_message(GameState.current_date,
		"Scout recommendation: %s (%s / %s)" % [String(r["name"]), _star_txt(ab), _star_txt(pot)],
		"%s Review the recommendation queue in Transfers > Recruitment — shortlist them or pass." % note)


func _star_txt(v: float) -> String:
	var full := int(v)
	var s := ""
	for i in full:
		s += "★"
	if v - float(full) >= 0.45:
		s += "½"
	return s


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
	o["log"].append(_log_line("Offered %s to %s." % [describe_package(o["package"]), club_of(t["club_id"])["name"]]))
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
	if is_ext_club(String(t["club_id"])):
		return "Overseas clubs will not loan battlers abroad — only a permanent transfer can bring them over."
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
	o["log"].append(_log_line("Loan proposed to %s — %s." % [club_of(t["club_id"])["short"], describe_loan(o["loan_terms"])]))
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
	if up > spendable_budget():
		return "Up-front fee exceeds our transfer budget (%s released by the board)." % fmt_money(spendable_budget())
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
	var seller: Dictionary = club_of(String(o["club_id"]))
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
	if int(pkg.get("upfront", 0)) > spendable_budget():
		return "Our transfer budget cannot cover the up-front part of that package (%s)." % fmt_money(int(pkg.get("upfront", 0)))
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
	var cash_needed := bonus + int(o["package"].get("upfront", 0))
	if cash_needed > spendable_budget():
		return "Signing bonus plus the up-front fee exceeds our transfer budget (%s)." % fmt_money(spendable_budget())
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
	if fee + bonus > spendable_budget():
		return "Compensation plus signing bonus (%s) exceeds our transfer budget (%s)." % [
			fmt_money(fee + bonus), fmt_money(spendable_budget())]
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
	var seller: Dictionary = club_of(o["club_id"])
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
	# An agent touting the player to US greases the deal: the client is pushing
	# to join, so the seller's resolve softens.
	if not agent_offer_for(String(o["uid"])).is_empty():
		threshold = int(float(threshold) * AGENT_GREASE)
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
	var seller: Dictionary = club_of(o["club_id"])
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
		shortlist.erase(String(inst["uid"]))
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

	if upfront + bonus > spendable_budget() or int(con.get("wage", 0)) > wage_room():
		o["stage"] = "collapsed"
		o["log"].append(_log_line("Deal collapsed — the transfer or wage budget no longer covers the terms."))
		return

	# Move the instance to our squad.
	match String(o["kind"]):
		"buy":
			var seller: Dictionary = club_of(o["club_id"])
			if is_ext_club(String(o["club_id"])):
				_remove_ext(String(inst["uid"]))
			else:
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
			if is_ext_uid(String(inst["uid"])):
				_remove_ext(String(inst["uid"]))
			else:
				GameState.world["prospects"].erase(inst)
	inst.erase("scouted_pct")
	inst["contract"]["salary"] = int(con.get("wage", 0))
	inst["contract"]["expiry"] = "%d-06-30" % (int(GameState.current_date.substr(0, 4)) + clampi(int(con.get("years", 3)), 1, 4))
	inst["squad_status"] = String(con.get("status", "First team"))
	pc["squad"].append(inst)
	pc["finances"]["balance"] = int(pc["finances"]["balance"]) - upfront - bonus
	_adjust_player_budget(-(upfront + bonus))
	knowledge[inst["uid"]] = 100.0
	shortlist.erase(String(inst["uid"]))
	o["stage"] = "completed"
	o["log"].append(_log_line("Deal done. %s joins %s." % [o["name"], pc["short"]]))
	var from_name: String = "Free agency" if o["club_id"] == "" else String(club_of(o["club_id"])["name"])
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
		if GameState.is_player_club(String(seller["id"])):
			_adjust_player_budget(-cut)
		if GameState.is_player_club(owner_id):
			var pc: Dictionary = GameState.player_club()
			pc["finances"]["balance"] = int(pc["finances"]["balance"]) + cut
			_adjust_player_budget(cut)
			GameState.add_inbox_message(GameState.current_date,
				"Sell-on clause pays out: %s (%s)" % [display_name(inst), fmt_money(cut)],
				"Our %d%% sell-on clause on %s has paid out %s from their %s move." % [
					int(so.get("pct", 0)), display_name(inst), fmt_money(cut), fmt_money(fee)])
		else:
			var owner: Dictionary = club_of(owner_id)
			if not owner.is_empty():
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
			if fee > spendable_budget():
				return "Our transfer budget cannot cover the option fee (%s)." % fmt_money(fee)
			var owner_id := String(inst["loan"]["owner"])
			var owner: Dictionary = GameState.club(owner_id)
			pc["finances"]["balance"] = int(pc["finances"]["balance"]) - fee
			_adjust_player_budget(-fee)
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
		var other: Dictionary = club_of(String(p["club_id"])) if String(p["club_id"]) != "" else {}
		if String(p["dir"]) == "out":
			pc["finances"]["balance"] = int(pc["finances"]["balance"]) - amount
			_adjust_player_budget(-amount)
			if not other.is_empty():
				other["finances"]["balance"] = int(other["finances"]["balance"]) + amount
			GameState.add_inbox_message(GameState.current_date, "Installment paid: %s (%s)" % [String(p["name"]), fmt_money(amount)],
				"A scheduled transfer installment of %s for %s has been paid%s." % [
					fmt_money(amount), String(p["name"]),
					(" to %s" % other["name"]) if not other.is_empty() else ""])
		else:
			pc["finances"]["balance"] = int(pc["finances"]["balance"]) + amount
			_adjust_player_budget(amount)
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
	var seller: Dictionary = club_of(String(o["club_id"]))
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
	var seller: Dictionary = club_of(String(o["club_id"]))
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
	var seller: Dictionary = club_of(String(o["club_id"]))
	var buyer: Dictionary = GameState.club(String(rv["club_id"]))
	var fee := mini(int(rv["value"]), int(buyer["finances"]["balance"]))
	if is_ext_club(String(o["club_id"])):
		_remove_ext(String(inst["uid"]))   # poached out of the external world for good
	else:
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
	o["routine"] = false   # the manager engaged — follow-ups deserve attention
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
	_adjust_player_budget(upfront)   # sales feed the board's transfer kitty
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


# --- unsolicited-bid pacing ------------------------------------------------
# FM clubs don't phone every other day. Cool-downs (per mon, per bidding
# club, league-wide) gate cold bids; deadline pressure halves them so the
# window run-in still feels alive. Routine bids arrive as non-urgent mail;
# only genuinely big money (see bid_is_big) stops the Continue loop.

func offer_cooldown_ok(uid: String, club_id: String) -> bool:
	var scale := 0.5 if days_to_deadline() >= 0 and days_to_deadline() <= 2 else 1.0
	var gates := [["any", int(COOLDOWN_ANY * scale)],
		["uid:%s" % uid, int(COOLDOWN_MON * scale)],
		["club:%s" % club_id, int(COOLDOWN_CLUB * scale)]]
	for g in gates:
		var last := str(offer_recent.get(g[0], ""))
		if last != "" and Season.days_between(last, GameState.current_date) < int(g[1]):
			return false
	return true


func note_unsolicited_offer(uid: String, club_id: String) -> void:
	offer_recent["any"] = GameState.current_date
	offer_recent["uid:%s" % uid] = GameState.current_date
	offer_recent["club:%s" % club_id] = GameState.current_date


## A bid big enough that the manager must hear about it IMMEDIATELY:
## well above our valuation, or any deadline-day panic money.
func bid_is_big(inst: Dictionary, total: int) -> bool:
	if days_to_deadline() >= 0 and days_to_deadline() <= 1:
		return true
	return total >= int(float(value_of(inst)) * BIG_BID_FACTOR)


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
	# Rumoured bids for OUR squad land first — the mill predicts the phone call.
	if _resolve_our_player_rumours(rng):
		return
	# New incoming bids only arrive while the window is open — and pour in near
	# the deadline (panic buys can go well above our valuation). Cool-downs
	# per mon / per club / league-wide keep the phone from ringing daily.
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
				if not offer_cooldown_ok(str(inst["uid"]), str(buyer2["id"])):
					return
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
				var big := bid_is_big(inst, package_total(pkg))
				offers_in.append({
					"id": _next_id, "uid": inst["uid"], "club_id": buyer2["id"],
					"package": pkg, "ask": 0, "ask_sell_on": 0, "stage": "open", "name": display_name(inst),
					"respond_on": "", "expires_on": expires, "routine": not big,
					"log": [_log_line("%s bid %s.%s" % [buyer2["short"], describe_package(pkg),
						" DEADLINE-DAY BID — decide today." if panic else ""])],
				})
				_next_id += 1
				note_unsolicited_offer(str(inst["uid"]), str(buyer2["id"]))
				if big:
					GameState.add_inbox_message(GameState.current_date,
						"%s: %s bid %s for %s" % ["DEADLINE-DAY OFFER" if panic else "Transfer offer",
							buyer2["short"], fmt_money(package_total(pkg)), display_name(inst)],
						"%s have offered %s for %s (our valuation: %s). Accept, reject or negotiate — you can demand more cash and a sell-on clause — before %s.%s" % [
							buyer2["name"], describe_package(pkg), display_name(inst),
							fmt_money(value_of(inst)), Season.pretty_date(expires),
							" The window shuts tonight: this bid dies at midnight." if panic else ""])
				else:
					# Routine interest: logged and waiting in the Transfer Centre,
					# but it does not stop the manager's week.
					GameState.add_inbox_message(GameState.current_date,
						"Transfer interest: %s bid %s for %s" % [
							buyer2["short"], fmt_money(package_total(pkg)), display_name(inst)],
						"%s have lodged an offer of %s for %s (our valuation: %s). Nothing that demands an immediate answer — it sits in the Transfer Centre until %s if you want to deal." % [
							buyer2["name"], describe_package(pkg), display_name(inst),
							fmt_money(value_of(inst)), Season.pretty_date(expires)])


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
	# A ripe interest rumour comes true first — the mill is foreshadowing, not noise.
	var rum := _ripe_interest_rumour()
	if not rum.is_empty():
		if rng.randf() < float(RUMOUR_TRUTH.get(String(rum["strength"]), 0.5)) and _complete_rumoured_deal(rum, rng):
			return
		rum["dud"] = true
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
	# Transfer-listed battlers are the ones actually in the shop window.
	var on_list: Array = sellable.filter(func(i): return is_listed(String(i["uid"])))
	if not on_list.is_empty() and rng.randf() < 0.6:
		sellable = on_list
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
	_alert_shortlist_sold(inst, buyer)
	if fee >= 250000 or is_deadline_day():
		GameState.add_inbox_message(GameState.current_date,
			"%s: %s sign %s" % ["Deadline-day move" if is_deadline_day() else "Market news",
				buyer["short"], display_name(inst)],
			"%s have paid %s a fee of %s for %s (Lv %d)%s. One to watch when we face them." % [
				buyer["name"], seller["name"], fmt_money(fee), display_name(inst), int(inst["level"]),
				" as the window slams shut" if is_deadline_day() else ""])


func _complete_rumoured_deal(rum: Dictionary, rng: RandomNumberGenerator) -> bool:
	## Executes the transfer an interest rumour foreshadowed. False if the world
	## moved on (target sold, buyer broke) — the rumour then dies a dud.
	var t := find_target(String(rum["uid"]))
	if t.is_empty() or t["pool"] != "club" or String(t["club_id"]) != String(rum["club_id"]):
		return false
	var seller: Dictionary = GameState.club(String(rum["club_id"]))
	var buyer: Dictionary = GameState.club(String(rum["other_id"]))
	if buyer.is_empty() or seller["squad"].size() <= 9:
		return false
	var inst: Dictionary = t["inst"]
	# Don't gazump the manager silently: live player negotiations go through the rival system instead.
	if not offer_for_target(String(inst["uid"])).is_empty():
		return false
	var fee := int(round(float(ask_price(inst, String(seller["id"]))) * (0.9 + rng.randf() * 0.2) / 1000.0)) * 1000
	if fee > int(float(buyer["finances"]["balance"]) * 0.6):
		return false
	seller["squad"].erase(inst)
	buyer["squad"].append(inst)
	buyer["finances"]["balance"] = int(buyer["finances"]["balance"]) - fee
	seller["finances"]["balance"] = int(seller["finances"]["balance"]) + fee
	_pay_sell_on(inst, fee, seller)
	rum["came_true"] = true
	_log_deal(display_name(inst), seller["name"], buyer["name"], fee,
		int(inst["contract"]["salary"]), "ai", fmt_money(fee) + " cash — as rumoured")
	_alert_shortlist_sold(inst, buyer)
	GameState.add_inbox_message(GameState.current_date,
		"Rumour confirmed: %s sign %s" % [buyer["short"], display_name(inst)],
		"The paper talk was right — %s have completed a %s deal for %s from %s." % [
			buyer["name"], fmt_money(fee), display_name(inst), seller["name"]])
	return true


func _alert_shortlist_sold(inst: Dictionary, buyer: Dictionary) -> void:
	if not shortlisted(String(inst["uid"])):
		return
	GameState.add_inbox_message(GameState.current_date,
		"SHORTLIST: we lost %s to %s" % [display_name(inst), String(buyer["short"])],
		"Our shortlisted target %s has signed for %s while we sat on our hands. The shortlist only works if we act on the alerts." % [
			display_name(inst), String(buyer["name"])])


# ------------------------------------------------------------------ shortlist
# The manager's target board. Everything in the pipeline pushes INTO it
# (scout recommendations, agent offers) and everything watching the market
# reports ON it (rumours, listings, rival interest, DoF delegation).

func shortlisted(uid: String) -> bool:
	return uid in shortlist


func toggle_shortlist(uid: String) -> String:
	if uid in shortlist:
		shortlist.erase(uid)
	else:
		var t := find_target(uid)
		if t.is_empty() or t["pool"] == "mine":
			return "Only market targets can be shortlisted."
		if shortlist.size() >= 12:
			return "Shortlist is full (12) — remove a target first."
		shortlist.append(uid)
	save_state()
	market_updated.emit()
	return ""


func shortlist_targets() -> Array:
	## Live target dicts, pruning anything that left the market (sold to us, etc.).
	var out: Array = []
	var stale: Array = []
	for uid in shortlist:
		var t := find_target(String(uid))
		if t.is_empty() or t["pool"] == "mine":
			stale.append(uid)
		else:
			out.append(t)
	for uid in stale:
		shortlist.erase(uid)
	return out


# ------------------------------------------------------------------ scout recommendation queue

func new_recs() -> Array:
	return recs.filter(func(r): return String(r["status"]) == "new" and not find_target(String(r["uid"])).is_empty())


func rec_accept(rec_id: int) -> String:
	for r in recs:
		if int(r["id"]) == rec_id and String(r["status"]) == "new":
			r["status"] = "accepted"
			var err := toggle_shortlist(String(r["uid"]))
			if err != "":
				r["status"] = "new"
				return err
			return ""
	return "Recommendation no longer available."


func rec_dismiss(rec_id: int) -> void:
	for r in recs:
		if int(r["id"]) == rec_id:
			r["status"] = "dismissed"
	save_state()
	market_updated.emit()


# ------------------------------------------------------------------ agent-offered players
# Agents phone the club to tout clients: free agents hawking for a contract,
# and contracted players whose agent says they want OUT — those deals come
# pre-greased (the selling club's resolve is softened while the offer stands).

func open_agent_offers() -> Array:
	return agent_offers.filter(func(a):
		return String(a["status"]) == "open" and String(a["expires"]) >= GameState.current_date \
			and not find_target(String(a["uid"])).is_empty())


func agent_offer_for(uid: String) -> Dictionary:
	for a in open_agent_offers():
		if String(a["uid"]) == uid:
			return a
	return {}


func dismiss_agent_offer(agent_id: int) -> void:
	for a in agent_offers:
		if int(a["id"]) == agent_id:
			a["status"] = "dismissed"
	save_state()
	market_updated.emit()


func _tick_agents(rng: RandomNumberGenerator) -> void:
	for a in agent_offers:
		if String(a["status"]) == "open" and String(a["expires"]) < GameState.current_date:
			a["status"] = "expired"
	if agent_offers.size() > 24:
		agent_offers.resize(24)
	if open_agent_offers().size() >= 5:
		return
	var factor := deadline_factor()
	var chance := 0.05 + 0.06 * factor if factor > 0.0 else 0.05
	if rng.randf() >= chance:
		return
	var want_club := factor > 0.0 and rng.randf() < 0.6
	var pc: Dictionary = GameState.player_club()
	if want_club:
		var pool := all_targets().filter(func(t):
			if t["pool"] != "club" or not agent_offer_for(t["inst"]["uid"]).is_empty():
				return false
			if not offer_for_target(t["inst"]["uid"]).is_empty():
				return false
			var c: Dictionary = club_of(t["club_id"])
			return c["squad"].size() > 8 and importance_of(t["inst"], c) < 1.35)
		pool = pool.filter(func(t): return ask_price(t["inst"], t["club_id"]) <= int(float(spendable_budget()) * 1.6))
		if pool.is_empty():
			return
		var t: Dictionary = pool[rng.randi() % pool.size()]
		var inst: Dictionary = t["inst"]
		var uid := String(inst["uid"])
		var guide := int(round(float(ask_price(inst, t["club_id"])) * AGENT_GREASE / 1000.0)) * 1000
		var pitches := [
			"\"My client feels he has taken %s as far as he can. Move now and this is a smooth deal.\"",
			"\"He has told %s he wants a new challenge. They will not stand in his way at the right price.\"",
			"\"The relationship with %s has run its course. You will not get better access than this.\"",
		]
		var pitch: String = String(pitches[rng.randi() % pitches.size()]) % String(club_of(t["club_id"])["short"])
		agent_offers.push_front({
			"id": _next_id, "uid": uid, "kind": "club", "date": GameState.current_date,
			"expires": _offer_expiry(7), "ask": guide, "pitch": pitch, "status": "open",
		})
		_next_id += 1
		var sl := shortlisted(uid)
		GameState.add_inbox_message(GameState.current_date,
			"%sAgent offer: %s available from %s" % ["SHORTLIST ALERT — " if sl else "",
				display_name(inst), String(club_of(t["club_id"])["short"])],
			"%s's agent has offered him to %s. %s A deal near %s should do it while the offer stands (until %s) — the agent's pressure softens %s at the table. See Transfers > Recruitment." % [
				display_name(inst), pc["name"], pitch, fmt_money(guide),
				Season.pretty_date(_offer_expiry(7)), String(club_of(t["club_id"])["short"])])
	else:
		var fas: Array = GameState.world["free_agents"].filter(func(i):
			return agent_offer_for(String(i["uid"])).is_empty() and offer_for_target(String(i["uid"])).is_empty())
		if fas.is_empty():
			return
		fas.sort_custom(func(a, b): return value_of(a) > value_of(b))
		var inst2: Dictionary = fas[rng.randi() % mini(8, fas.size())]
		var uid2 := String(inst2["uid"])
		var wage_guide := int(round(float(inst2["contract"]["salary"]) * (0.95 + rng.randf() * 0.2) / 10.0)) * 10
		agent_offers.push_front({
			"id": _next_id, "uid": uid2, "kind": "fa", "date": GameState.current_date,
			"expires": Season.date_add(GameState.current_date, 10),
			"ask": wage_guide, "pitch": "\"He is training alone and hungry. Around %s/wk signs him this week.\"" % fmt_money(wage_guide),
			"status": "open",
		})
		_next_id += 1
		GameState.add_inbox_message(GameState.current_date,
			"Agent touting a free agent: %s" % display_name(inst2),
			"An agent has offered free agent %s (Lv %d) to us directly — around %s/wk gets it done. No fee, signable any time. See Transfers > Recruitment." % [
				display_name(inst2), int(inst2["level"]), fmt_money(wage_guide)])


# ------------------------------------------------------------------ rumour mill
# The league's gossip layer. Rumours are not set dressing: listings genuinely
# slash ask prices, interest rumours ripen into real AI-to-AI transfers, and
# "preparing a bid" whispers about OUR squad turn into actual incoming offers.

const RUMOUR_STRENGTHS := ["Whisper", "Warm", "Strong"]
const RUMOUR_TRUTH := {"Whisper": 0.3, "Warm": 0.55, "Strong": 0.8}


func rumours_for(uid: String) -> Array:
	return rumours.filter(func(r): return String(r.get("uid", "")) == uid)


func _add_rumour(kind: String, uid: String, club_id: String, other_id: String,
		strength: String, text: String, due: String = "") -> Dictionary:
	var r := {
		"id": _next_id, "date": GameState.current_date, "kind": kind, "uid": uid,
		"club_id": club_id, "other_id": other_id, "strength": strength,
		"text": text, "came_true": false, "dud": false, "due": due,
	}
	_next_id += 1
	rumours.push_front(r)
	if rumours.size() > 40:
		rumours.resize(40)
	return r


func _tick_rumours(rng: RandomNumberGenerator) -> void:
	# purge expired listings
	for uid in listed.keys():
		if String(listed[uid]) < GameState.current_date:
			listed.erase(uid)
	var factor := deadline_factor()
	var chance := 0.85 if factor >= 2.0 else (0.5 if factor > 0.0 else 0.14)
	if rng.randf() >= chance:
		return
	if factor <= 0.0:
		_rumour_interest(rng)   # between windows: only next-window whispers
		return
	var roll := rng.randf()
	if roll < 0.40:
		_rumour_interest(rng)
	elif roll < 0.62:
		_rumour_listing(rng)
	elif roll < 0.84:
		_rumour_our_player(rng)
	else:
		_rumour_war_chest(rng)


func _rumour_listing(rng: RandomNumberGenerator) -> void:
	## A club transfer-lists a fringe battler — TRUE by construction: the ask
	## price is slashed while the listing stands.
	var clubs: Array = GameState.world["clubs"].filter(func(c):
		return not GameState.is_player_club(c["id"]) and c["squad"].size() > 9)
	if clubs.is_empty():
		return
	var club: Dictionary = clubs[rng.randi() % clubs.size()]
	var fringe: Array = club["squad"].filter(func(i):
		return importance_of(i, club) < 1.15 and not is_listed(String(i["uid"])))
	if fringe.is_empty():
		return
	var inst: Dictionary = fringe[rng.randi() % fringe.size()]
	var uid := String(inst["uid"])
	listed[uid] = Season.date_add(GameState.current_date, 28)
	var new_ask := ask_price(inst, String(club["id"]))
	var r := _add_rumour("listing", uid, String(club["id"]), "", "Strong",
		"%s have made %s (Lv %d) available for transfer — around %s would do it." % [
			String(club["short"]), display_name(inst), int(inst["level"]), fmt_money(new_ask)])
	r["came_true"] = true
	if shortlisted(uid):
		GameState.add_inbox_message(GameState.current_date,
			"SHORTLIST ALERT: %s transfer-listed by %s" % [display_name(inst), String(club["short"])],
			"Our shortlisted target %s has been made available — %s's ask drops to about %s while the listing stands. Move before a rival does." % [
				display_name(inst), String(club["name"]), fmt_money(new_ask)])


func _rumour_interest(rng: RandomNumberGenerator) -> void:
	## Club A eyeing a battler at club B. Ripens into a REAL AI deal via
	## _ai_club_deal — strong rumours usually come true.
	var clubs: Array = GameState.world["clubs"].filter(func(c): return not GameState.is_player_club(c["id"]))
	var seller: Dictionary = clubs[rng.randi() % clubs.size()]
	if seller["squad"].size() <= 9:
		return
	var buyers: Array = clubs.filter(func(c): return String(c["id"]) != String(seller["id"]))
	var buyer: Dictionary = buyers[rng.randi() % buyers.size()]
	var pool: Array = seller["squad"].filter(func(i): return importance_of(i, seller) < 1.35)
	if pool.is_empty():
		return
	var inst: Dictionary = pool[rng.randi() % pool.size()]
	var uid := String(inst["uid"])
	var strength: String = RUMOUR_STRENGTHS[rng.randi() % 3]
	var verbs := {"Whisper": "are said to be monitoring", "Warm": "are weighing a move for", "Strong": "are preparing a bid for"}
	_add_rumour("interest", uid, String(seller["id"]), String(buyer["id"]), strength,
		"%s %s %s (%s)." % [String(buyer["short"]), verbs[strength], display_name(inst), String(seller["short"])],
		Season.date_add(GameState.current_date, 2 + int(rng.randi() % 5)))
	if shortlisted(uid):
		GameState.add_inbox_message(GameState.current_date,
			"SHORTLIST ALERT: %s circling %s" % [String(buyer["short"]), display_name(inst)],
			"The rumour mill says %s %s our shortlisted target %s. If we want him, the safe move is to bid before they do." % [
				String(buyer["name"]), verbs[strength], display_name(inst)])


func _rumour_our_player(rng: RandomNumberGenerator) -> void:
	## A rival is preparing a bid for OUR squad — often followed by the real thing.
	var pc: Dictionary = GameState.player_club()
	if pc["squad"].size() <= 6:
		return
	var pool: Array = pc["squad"].filter(func(i): return not i.has("loan"))
	if pool.is_empty():
		return
	pool.sort_custom(func(a, b): return value_of(a) > value_of(b))
	var inst: Dictionary = pool[rng.randi() % mini(5, pool.size())]
	var uid := String(inst["uid"])
	for r0 in rumours:
		if String(r0.get("kind", "")) == "our_player" and String(r0.get("uid", "")) == uid \
				and not bool(r0.get("came_true", false)) and not bool(r0.get("dud", false)):
			return
	var buyers: Array = GameState.world["clubs"].filter(func(c):
		return not GameState.is_player_club(c["id"]) and int(c["finances"]["balance"]) > int(float(value_of(inst)) * 0.8))
	if buyers.is_empty():
		return
	var buyer: Dictionary = buyers[rng.randi() % buyers.size()]
	var strength: String = RUMOUR_STRENGTHS[rng.randi() % 3]
	_add_rumour("our_player", uid, String(pc["id"]), String(buyer["id"]), strength,
		"%s are rumoured to be readying an offer for OUR %s." % [String(buyer["short"]), display_name(inst)],
		Season.date_add(GameState.current_date, 2 + int(rng.randi() % 4)))
	GameState.add_inbox_message(GameState.current_date,
		"Paper talk: %s linked with our %s" % [String(buyer["short"]), display_name(inst)],
		"The rumour mill has %s preparing a bid for %s. Nothing official yet — but if you would sell, decide your price now; if not, brace for the phone call." % [
			String(buyer["name"]), display_name(inst)])


func _rumour_war_chest(rng: RandomNumberGenerator) -> void:
	var clubs: Array = GameState.world["clubs"].filter(func(c): return not GameState.is_player_club(c["id"]))
	var club: Dictionary = clubs[rng.randi() % clubs.size()]
	_add_rumour("war_chest", "", String(club["id"]), "", "Whisper",
		"%s's board is said to have released a war chest — expect them to be busy this window." % String(club["short"]))


func _seed_window_rumours() -> void:
	## The moment a window opens the mill starts grinding, so the Recruitment
	## hub is never dead on day one. Guarded per window.
	var w := current_window()
	if w.is_empty() or seeded_window == String(w["open"]):
		return
	seeded_window = String(w["open"])
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.career_seed ^ ("seed|" + seeded_window).hash()
	_rumour_listing(rng)
	_rumour_listing(rng)
	_rumour_interest(rng)
	_rumour_war_chest(rng)


func _resolve_our_player_rumours(rng: RandomNumberGenerator) -> bool:
	## Ripe "preparing a bid for OUR player" rumours become real incoming offers.
	## Returns true if a bid landed today (the cold-bid generator then stands down).
	for r in rumours:
		if String(r.get("kind", "")) != "our_player" or bool(r.get("came_true", false)) or bool(r.get("dud", false)):
			continue
		if String(r.get("due", "9999")) > GameState.current_date:
			continue
		if not window_open():
			r["dud"] = true
			continue
		var t := find_target(String(r["uid"]))
		var buyer: Dictionary = GameState.club(String(r["other_id"]))
		if t.is_empty() or t["pool"] != "mine" or buyer.is_empty() \
				or not offer_for_target(String(r["uid"])).is_empty() \
				or rng.randf() >= float(RUMOUR_TRUTH.get(String(r["strength"]), 0.5)):
			r["dud"] = true
			continue
		var inst: Dictionary = t["inst"]
		var bid := int(round(float(value_of(inst)) * (0.85 + rng.randf() * 0.35) / 1000.0)) * 1000
		bid = mini(bid, int(buyer["finances"]["balance"]))
		if bid < 1000:
			r["dud"] = true
			continue
		r["came_true"] = true
		var pkg := blank_package(bid)
		var expires := _offer_expiry(6)
		var big := bid_is_big(inst, bid)
		offers_in.append({
			"id": _next_id, "uid": inst["uid"], "club_id": buyer["id"],
			"package": pkg, "ask": 0, "ask_sell_on": 0, "stage": "open", "name": display_name(inst),
			"respond_on": "", "expires_on": expires, "routine": not big,
			"log": [_log_line("%s bid %s — just as the rumour mill predicted." % [buyer["short"], fmt_money(bid)])],
		})
		_next_id += 1
		note_unsolicited_offer(String(inst["uid"]), String(buyer["id"]))
		GameState.add_inbox_message(GameState.current_date,
			"The rumours were true: %s bid %s for %s" % [buyer["short"], fmt_money(bid), display_name(inst)],
			"%s have followed up the paper talk with a real offer of %s for %s (our valuation: %s). It waits in the Transfer Centre until %s." % [
				buyer["name"], fmt_money(bid), display_name(inst), fmt_money(value_of(inst)), Season.pretty_date(expires)])
		return true
	return false


func _ripe_interest_rumour() -> Dictionary:
	for r in rumours:
		if String(r.get("kind", "")) == "interest" and not bool(r.get("came_true", false)) \
				and not bool(r.get("dud", false)) and String(r.get("due", "9999")) <= GameState.current_date:
			return r
	return {}


# ------------------------------------------------------------------ scout market (hiring a network)

func hired_scouts() -> Array:
	return GameState.player_club()["staff"].filter(func(s): return bool(s.get("hired", false)))


func scout_market() -> Array:
	## This month's hireable dedicated scouts (deterministic per career+month).
	var mkey := GameState.current_date.substr(0, 7)
	if scout_pool_month != mkey:
		scout_pool_month = mkey
		scout_pool = []
		var rng := RandomNumberGenerator.new()
		rng.seed = GameState.career_seed ^ mkey.hash()
		var regions: Array = REGIONS.keys()
		var offset := int(rng.randi() % regions.size())
		var used := {}
		for i in 6:
			var nm := ""
			for attempt in 20:
				nm = "%s %s" % [SCOUT_FIRST[rng.randi() % SCOUT_FIRST.size()], SCOUT_LAST[rng.randi() % SCOUT_LAST.size()]]
				if not used.has(nm) and _scout_by_name(nm).is_empty():
					break
			used[nm] = true
			var ja := 8 + int(rng.randi() % 12)
			var jp := 6 + int(rng.randi() % 14)
			var region := String(regions[(i + offset) % regions.size()])
			var wage := int(round(float((ja * 2 + jp) * 13 + 80 + int(rng.randi() % 90)) / 10.0)) * 10
			if region in OVERSEAS_REGIONS:
				wage += 60   # island natives charge a premium — they unlock a whole market
			scout_pool.append({"name": nm, "ja": ja, "jp": jp, "region": region, "wage": wage})
		save_state()
	return scout_pool.filter(func(s): return _scout_by_name(String(s["name"])).is_empty())


func hire_scout(scout_name: String) -> String:
	var cand: Dictionary = {}
	for s in scout_market():
		if String(s["name"]) == scout_name:
			cand = s
			break
	if cand.is_empty():
		return "That scout is no longer on the market."
	if hired_scouts().size() >= MAX_HIRED_SCOUTS:
		return "Scouting department is full (%d hired scouts). Release one first." % MAX_HIRED_SCOUTS
	if int(cand["wage"]) > wage_room():
		return "Their %s/wk wage breaks our wage budget (room: %s/wk)." % [fmt_money(int(cand["wage"])), fmt_money(wage_room())]
	GameState.player_club()["staff"].append({
		"name": scout_name, "role": "scout", "hired": true,
		"wage": int(cand["wage"]), "region": String(cand["region"]),
		"ratings": {"judging_ability": int(cand["ja"]), "judging_potential": int(cand["jp"])},
	})
	GameState.add_inbox_message(GameState.current_date, "Scout hired: %s (%s)" % [scout_name, String(cand["region"])],
		"%s joins our scouting department on %s/wk. Home network: %s — assignments there run days faster and region focuses build knowledge across the whole patch." % [
			scout_name, fmt_money(int(cand["wage"])), String(cand["region"])])
	GameState.save_game()
	save_state()
	market_updated.emit()
	return ""


func fire_scout(scout_name: String) -> String:
	var pc: Dictionary = GameState.player_club()
	for s in pc["staff"]:
		if String(s["name"]) == scout_name and bool(s.get("hired", false)):
			recall_scout(scout_name)
			scout_loc.erase(scout_name)
			var severance := int(s.get("wage", 0)) * 4
			pc["finances"]["balance"] = int(pc["finances"]["balance"]) - severance
			pc["staff"].erase(s)
			GameState.add_inbox_message(GameState.current_date, "Scout released: %s" % scout_name,
				"%s has left the scouting department (severance: %s)." % [scout_name, fmt_money(severance)])
			GameState.save_game()
			save_state()
			market_updated.emit()
			return ""
	return "Only hired scouts can be released — club coaches stay."


func region_coverage() -> Dictionary:
	## Per-region market knowledge — the "how good is my network here" board.
	var acc := {}
	for r in REGIONS:
		acc[r] = {"know": 0.0, "targets": 0, "scouts": 0}
	for t in all_targets():
		var r2 := region_of(t["inst"])
		acc[r2]["know"] += knowledge_of(String(t["inst"]["uid"]))
		acc[r2]["targets"] += 1
	for s in player_scouts():
		acc[scout_region(s)]["scouts"] += 1
	for r3 in acc:
		if int(acc[r3]["targets"]) > 0:
			acc[r3]["know"] = acc[r3]["know"] / float(acc[r3]["targets"])
	return acc


# ------------------------------------------------------------------ Director of Battling (delegation)
# FM's DoF: tick the boxes and the club works the market without you —
# lowball bids get swatted, idle scouts chase the shortlist, and the DoF
# opens, negotiates and closes shortlist deals inside sane limits.

func set_dof(key: String, value: Variant) -> void:
	dof[key] = value
	save_state()
	market_updated.emit()


func _dof_note(text: String) -> void:
	dof_log.push_front({"date": GameState.current_date, "text": text})
	if dof_log.size() > 24:
		dof_log.resize(24)


func _tick_dof(rng: RandomNumberGenerator) -> void:
	if bool(dof.get("auto_scout", false)):
		_dof_auto_scout()
	if bool(dof.get("handle_bids", false)):
		_dof_handle_bids()
	if bool(dof.get("pursue_shortlist", false)):
		_dof_progress_deals()
		if window_open():
			_dof_open_deal(rng)


func _dof_auto_scout() -> void:
	for t in shortlist_targets():
		var uid := String(t["inst"]["uid"])
		if knowledge_of(uid) >= 100.0 or not assignment_for_target(uid).is_empty():
			continue
		var idle: Array = player_scouts().filter(func(s): return assignment_for_scout(String(s["name"])).is_empty())
		if idle.is_empty():
			return
		var reg := region_of(t["inst"])
		idle.sort_custom(func(a, b):
			if (scout_region(a) == reg) != (scout_region(b) == reg):
				return scout_region(a) == reg
			return int(a["ratings"]["judging_ability"]) > int(b["ratings"]["judging_ability"]))
		if assign_scout_to_target(String(idle[0]["name"]), uid) == "":
			_dof_note("Sent %s to scout shortlisted %s." % [String(idle[0]["name"]), display_name(t["inst"])])


func _dof_handle_bids() -> void:
	for o in offers_in:
		if String(o["stage"]) != "open" or not bool(o.get("routine", false)):
			continue
		var t := find_target(String(o["uid"]))
		if t.is_empty() or t["pool"] != "mine":
			continue
		if package_total(o["package"]) < int(float(value_of(t["inst"])) * 0.92):
			o["stage"] = "rejected"
			o["log"].append(_log_line("DoF rejected the bid — below our valuation."))
			_dof_note("Rejected %s's %s bid for %s (valuation %s)." % [
				String(GameState.club(String(o["club_id"]))["short"]), fmt_money(package_total(o["package"])),
				String(o["name"]), fmt_money(value_of(t["inst"]))])


func _dof_live_deals() -> Array:
	return offers_out.filter(func(o): return bool(o.get("dof", false)) and not (String(o["stage"]) in DEAD_STAGES))


func _dof_progress_deals() -> void:
	var limit_mult := 1.0 + float(int(dof.get("max_over_pct", 10))) / 100.0
	for o in _dof_live_deals():
		var t := find_target(String(o["uid"]))
		if t.is_empty():
			continue
		var cap := int(float(value_of(t["inst"])) * limit_mult)
		match String(o["stage"]):
			"countered":
				if o["kind"] != "buy":
					continue
				var take := ""
				var alt: Dictionary = o.get("alt_package", {})
				if not alt.is_empty() and package_total(alt) <= cap and int(alt.get("upfront", 0)) <= spendable_budget():
					take = "alt"
				elif package_total(o.get("ask_package", {})) <= cap and int(o["ask_package"].get("upfront", 0)) <= spendable_budget():
					take = "ask"
				if take != "":
					if accept_package(int(o["id"]), take) == "":
						_dof_note("Accepted %s's proposal for %s (%s)." % [
							String(club_of(String(o["club_id"]))["short"]), String(o["name"]),
							describe_package(o["package"])])
				else:
					withdraw_offer(int(o["id"]))
					_dof_note("Walked away from %s — their demands broke the board's limit (%s)." % [String(o["name"]), fmt_money(cap)])
			"fee_agreed", "wage_countered":
				var demand: Dictionary = o.get("contract_demand", {})
				var wage := int(demand.get("wage", 0))
				if wage <= 0:
					continue
				if wage <= wage_room():
					if offer_contract(int(o["id"]), {"wage": wage, "years": int(demand.get("years", 3)),
							"bonus": 0, "status": String(demand.get("status", "First team"))}) == "":
						_dof_note("Offered %s the %s/wk terms his camp asked for." % [String(o["name"]), fmt_money(wage)])
				else:
					withdraw_offer(int(o["id"]))
					_dof_note("Pulled out of the %s deal — his %s/wk demand breaks the wage budget." % [String(o["name"]), fmt_money(wage)])


func _dof_open_deal(_rng: RandomNumberGenerator) -> void:
	if _dof_live_deals().size() >= 2:
		return
	for t in shortlist_targets():
		var uid := String(t["inst"]["uid"])
		if not offer_for_target(uid).is_empty():
			continue
		var err := ""
		var opened := ""
		if t["pool"] == "club":
			var ask := ask_price(t["inst"], String(t["club_id"]))
			if int(float(ask) * 0.7) > spendable_budget():
				continue
			var up := mini(int(round(float(ask) * 0.68 / 1000.0)) * 1000, spendable_budget())
			var pkg := {"upfront": up, "inst_amount": int(round(float(ask) * 0.27 / 1000.0)) * 1000,
				"inst_years": 2, "sell_on": 0}
			err = make_offer(uid, pkg)
			opened = "Opened talks with %s for %s — %s." % [
				String(club_of(String(t["club_id"]))["short"]), display_name(t["inst"]), describe_package(_norm_package(pkg))]
		else:
			if t["pool"] == "prospect" and not window_open():
				continue
			var wage := int(round(float(t["inst"]["contract"]["salary"]) * 1.2 / 10.0)) * 10
			if wage > wage_room():
				continue
			err = sign_free_agent(uid, {"wage": wage, "years": 3, "bonus": 0, "status": "Rotation"})
			opened = "Opened contract talks with %s (%s/wk)." % [display_name(t["inst"]), fmt_money(wage)]
		if err == "":
			var o := offer_for_target(uid)
			if not o.is_empty():
				o["dof"] = true
			_dof_note(opened)
			GameState.add_inbox_message(GameState.current_date, "DoF: talks opened for %s" % display_name(t["inst"]),
				"%s Your Director of Battling is handling the negotiation — limits: %d%% over valuation, board budgets. Watch it in the Transfer Centre or take over any time." % [
					opened, int(dof.get("max_over_pct", 10))])
			return


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
	_tick_agents(rng)
	_tick_rumours(rng)
	_tick_dof(rng)
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
