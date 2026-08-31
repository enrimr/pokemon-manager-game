extends Node
## Autoload: GameState
## The single source of truth for a running career: world data, calendar,
## fixtures, league table, inbox. Screens read from here and connect to
## the signals below. Piece-builders: use the public API, never mutate
## `fixtures`/`world` structurally without going through it.

signal career_started
signal date_changed(new_date: String)
signal fixture_played(fixture: Dictionary)
signal table_updated
signal inbox_updated
signal player_match_due(fixture: Dictionary)
signal inventory_changed
signal season_rolled(season_no: int)   # a new season's fixtures are live
signal settings_changed(key: String)   # a game setting was changed (see `settings`)
signal game_over(info: Dictionary)     # the board sacked the manager (see trigger_game_over)

const SAVE_PATH := "user://save.json"

var world: Dictionary = {}          # deep-copied from world.json, mutated over time
var current_date: String = ""
var season_start: String = ""
var fixtures: Array = []            # league + generated cup fixtures
var cup_round: int = 0              # highest cup round generated so far
var inbox: Array = []               # [{date, title, body, read}]
var career_seed: int = 0
var auto_sim_player_matches := true # match piece can set false and intercept

## Game settings (persisted in the save, survives new careers). Documented keys
## (see docs/ARCHITECTURE.md "Settings" — the platform piece renders these):
##   ai_coach_uses_bag: bool (true) — may the AI coach spend YOUR club's
##       consumable items when a player match is delegated / instant-simmed?
var settings: Dictionary = {}
const SETTINGS_DEFAULTS := {"ai_coach_uses_bag": true}

var _clubs_by_id: Dictionary = {}
var _table_cache: Dictionary = {}   # league_id -> table rows
var _table_dirty := true
var _economy: RefCounted = null     # inbox piece's economy.gd, ticked daily
var _economy_checked := false
var _services: Array = []           # auto-loaded res://shared/sim/services/*.gd (see docs)
var _incompatible_save := false     # a pre-leagues save was found and archived


func _ready() -> void:
	# Boot into a playable state: load save if present, else new career.
	# (Deferred so DataStore's _ready has definitely run first.)
	# The Settings autoload registers AFTER us, so apply the saved language
	# first — boot-time inbox mail must be written in the player's locale.
	I18n.apply_saved_locale()
	boot()


## Load the save if compatible, else start a new career. If an old-format save
## was found, it is replaced gracefully: fresh career + a clear inbox note.
func boot() -> void:
	if load_game():
		return
	var had_old := _incompatible_save
	new_career()
	if had_old:
		add_inbox_message(current_date, I18n.t("Save file from an earlier era"),
			I18n.t("Your previous career predates the two-league world (Kanto League + Johto League with the cross-league Indigo Cup) and could not be carried over. A fresh career has been started at %s — good luck, boss.")
			% player_club()["name"])
		save_game()


# ------------------------------------------------------------------ lifecycle

## Start a fresh career. club_id (optional) picks any club from either league
## (the shell's new-career club picker); default remains Pallet Pioneers.
func new_career(seed_value: int = 20260801, club_id: String = "") -> void:
	career_seed = seed_value
	var f := FileAccess.open("res://shared/data/world.json", FileAccess.READ)
	world = JSON.parse_string(f.get_as_text())
	_index_clubs()
	_sanitize_contract_dates()
	if club_id != "" and _clubs_by_id.has(club_id):
		world["meta"]["player_club_id"] = club_id
	_ensure_item_state()
	_ensure_budget_state()
	_ensure_league_state()
	_ensure_settings()
	season_start = world["meta"]["season_start"]
	current_date = season_start
	fixtures = []
	var prefixes := ["L", "J", "K", "M"]   # unique fixture-id prefixes per league
	var lgs := leagues()
	for i in lgs.size():
		var lid: String = str(lgs[i]["id"])
		fixtures += Season.make_league_fixtures(league_club_ids(lid), season_start,
			prefixes[mini(i, prefixes.size() - 1)], lid)
	cup_round = 1
	fixtures += Season.make_cup_round(all_club_ids(), 1, Season.cup_round_date(season_start, 1), career_seed)
	inbox = []
	add_inbox_message(current_date, I18n.t("Welcome to %s") % player_club()["name"],
		I18n.t("The board expects a solid mid-table finish in the %s. Your first fixture is on %s.") %
		[I18n.t(world["meta"]["league_name"]), I18n.pretty_date(next_player_fixture().get("date", season_start))])
	_table_dirty = true
	_load_services()
	career_started.emit()
	date_changed.emit(current_date)
	table_updated.emit()


func save_game() -> bool:
	_collect_service_state()
	var data := {
		"version": 2,
		"career_seed": career_seed,
		"current_date": current_date,
		"season_start": season_start,
		"cup_round": cup_round,
		"world": world,
		"fixtures": fixtures,
		"inbox": inbox,
		"settings": settings,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("GameState: cannot write save file")
		return false
	f.store_string(JSON.stringify(data))
	return true


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data == null or typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) != 2:
		# Pre-leagues (v1) or corrupt save: flag it so boot() can route to a
		# graceful new career with a clear inbox note instead of crashing.
		push_warning("GameState: incompatible save file (old version) — starting fresh")
		_incompatible_save = true
		return false
	career_seed = int(data["career_seed"])
	current_date = data["current_date"]
	season_start = data["season_start"]
	cup_round = int(data["cup_round"])
	world = data["world"]
	fixtures = data["fixtures"]
	inbox = data["inbox"]
	if typeof(data.get("settings")) == TYPE_DICTIONARY:
		settings = data["settings"]
	_ensure_settings()
	_index_clubs()
	_sanitize_contract_dates()
	_ensure_item_state()
	_ensure_budget_state()
	_ensure_league_state()
	# Save migration: fixtures played before match details were persisted at
	# play time get reconciled once (adopt a faithful replay, or a score-only
	# stub when squads have drifted) so reports can never contradict scores.
	var rec := Season.reconcile_fixture_details(fixtures)
	if int(rec["adopted"]) + int(rec["cleared"]) > 0:
		save_game()
	_table_dirty = true
	_load_services()
	career_started.emit()
	date_changed.emit(current_date)
	table_updated.emit()
	return true


func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


# ------------------------------------------------------------------ queries

## The PLAYER'S league's club ids (existing single-league callers — table
## screens, position graphs, stats — keep working per-league unchanged).
func club_ids() -> Array:
	return league_club_ids(player_league_id())


## Every club id across every league (cross-league cup, scouting, transfers).
func all_club_ids() -> Array:
	return world["clubs"].map(func(c): return c["id"])


## The league structure: [{id, name}, ...] (kanto + johto).
func leagues() -> Array:
	return world["meta"].get("leagues", [{"id": "kanto", "name": world["meta"]["league_name"]}])


func league_club_ids(league_id: String) -> Array:
	return world["clubs"].filter(func(c): return str(c.get("league", "kanto")) == league_id) \
		.map(func(c): return c["id"])


## League a club plays in ("kanto"/"johto").
func league_of(club_id: String) -> String:
	return str(club(club_id).get("league", "kanto"))


func player_league_id() -> String:
	return league_of(world["meta"]["player_club_id"])


func league_name(league_id: String = "") -> String:
	if league_id == "":
		league_id = player_league_id()
	for lg in leagues():
		if str(lg["id"]) == league_id:
			return str(lg["name"])
	return str(world["meta"]["league_name"])


func cup_name() -> String:
	return str(world["meta"].get("cup_name", "Indigo Cup"))


## 1-based season counter (increments on every rollover — see start_new_season).
func season_no() -> int:
	return int(world["meta"].get("season_no", 1))


## Champions/awards record, one entry per COMPLETED season, oldest first.
## Written by the season_flow service at each end-of-season ceremony.
func season_history() -> Array:
	if not world["meta"].has("history") or typeof(world["meta"]["history"]) != TYPE_ARRAY:
		world["meta"]["history"] = []
	return world["meta"]["history"]


func add_history_entry(entry: Dictionary) -> void:
	season_history().append(entry)


func club(id: String) -> Dictionary:
	return _clubs_by_id.get(id, {})


func player_club() -> Dictionary:
	return club(world["meta"]["player_club_id"])


func is_player_club(id: String) -> bool:
	return id == world["meta"]["player_club_id"]


## Standings. Default: the player's league (existing callers unchanged);
## pass "kanto"/"johto" for either championship.
func league_table(league_id: String = "") -> Array:
	if league_id == "":
		league_id = player_league_id()
	if _table_dirty:
		_table_cache.clear()
		_table_dirty = false
	if not _table_cache.has(league_id):
		_table_cache[league_id] = Season.compute_table(league_club_ids(league_id), fixtures)
	return _table_cache[league_id]


func player_table_position() -> int:
	var t := league_table()
	for i in t.size():
		if is_player_club(t[i]["club_id"]):
			return i + 1
	return 0


func fixtures_on(date: String) -> Array:
	return fixtures.filter(func(f): return f["date"] == date)


func next_player_fixture() -> Dictionary:
	# Earliest by DATE, not array order — cup fixtures are appended after the
	# league list, so a midweek cup tie can be nearer than the next league round.
	var pid: String = world["meta"]["player_club_id"]
	var best: Dictionary = {}
	for f in fixtures:
		if not f["played"] and (f["home"] == pid or f["away"] == pid):
			if best.is_empty() or str(f["date"]) < str(best["date"]):
				best = f
	return best


func player_fixtures() -> Array:
	var pid: String = world["meta"]["player_club_id"]
	return fixtures.filter(func(f): return f["home"] == pid or f["away"] == pid)


func free_agents() -> Array:
	return world["free_agents"]


func prospects() -> Array:
	return world["prospects"]


func unread_inbox_count() -> int:
	return inbox.filter(func(m): return not m.get("read", false)).size()


# ------------------------------------------------------------------ budgets
# FM-style board split: the bank balance is the CLUB's money; the board only
# releases part of it for squad building. finances.transfer_budget is what
# the manager may spend on fees and items; finances.wage_budget caps weekly
# wages (both adjustable via the board-request flow in the Inbox piece).

## The board-imposed transfer budget of a club (spendable, may hit 0).
func transfer_budget(club_id: String) -> int:
	var c := club(club_id)
	if c.is_empty():
		return 0
	return int(c["finances"].get("transfer_budget", 0))


func player_transfer_budget() -> int:
	return transfer_budget(world["meta"]["player_club_id"])


## Move the budget with every fee/purchase (negative delta) or sale/board
## grant (positive). Budget never exceeds the actual bank balance.
func adjust_transfer_budget(club_id: String, delta: int) -> void:
	var c := club(club_id)
	if c.is_empty():
		return
	var fin: Dictionary = c["finances"]
	fin["transfer_budget"] = mini(int(fin.get("transfer_budget", 0)) + delta, int(fin["balance"]))


## Derive the board's initial split for clubs that don't have one yet
## (new careers and pre-split saves): richer, more reputable boards release
## a bigger slice of the bank balance for transfers.
func _ensure_budget_state() -> void:
	for c in world["clubs"]:
		var fin: Dictionary = c["finances"]
		if not fin.has("transfer_budget"):
			var rep := int(c.get("reputation", 10))
			var slice := 0.18 + 0.016 * rep      # rep 1..20 -> 20%..50% of the bank
			var tb := int(round(float(int(fin["balance"])) * slice / 1000.0)) * 1000
			fin["transfer_budget"] = clampi(tb, 0, int(fin["balance"]))


# ------------------------------------------------------------------ items & inventory
# Per-club item store: club["items"] = {item_id: count}. Held items live on the
# squad instance's "held_item" slot (null/"" = bare). Item catalog: DataStore.item().

## A club's item inventory (live dict — mutate only via the API below).
func club_inventory(club_id: String) -> Dictionary:
	var c := club(club_id)
	if c.is_empty():
		return {}
	if not c.has("items") or typeof(c["items"]) != TYPE_DICTIONARY:
		c["items"] = {}
	return c["items"]


func player_inventory() -> Dictionary:
	return club_inventory(world["meta"]["player_club_id"])


## Buy `qty` of an item from the league store with club funds. "" = ok, else error.
func buy_item(item_id: String, qty: int = 1) -> String:
	var it: Dictionary = DataStore.item(item_id)
	if it.is_empty():
		return I18n.t("Unknown item.")
	qty = maxi(1, qty)
	var cost := int(it["price"]) * qty
	var fin: Dictionary = player_club()["finances"]
	var spendable := mini(int(fin["balance"]), int(fin.get("transfer_budget", 0)))
	if spendable < cost:
		return I18n.t("Not enough transfer budget — %s %d needed, %s %d released by the board.") % [
			world["meta"]["currency"], cost, world["meta"]["currency"], maxi(0, spendable)]
	fin["balance"] = int(fin["balance"]) - cost
	fin["transfer_budget"] = int(fin.get("transfer_budget", 0)) - cost
	var inv := player_inventory()
	inv[item_id] = int(inv.get(item_id, 0)) + qty
	inventory_changed.emit()
	return ""


## Sell surplus stock back at half price. "" = ok, else error.
func sell_item(item_id: String, qty: int = 1) -> String:
	qty = maxi(1, qty)
	var inv := player_inventory()
	if int(inv.get(item_id, 0)) < qty:
		return I18n.t("Not enough of that item in the storeroom.")
	inv[item_id] = int(inv[item_id]) - qty
	if int(inv[item_id]) <= 0:
		inv.erase(item_id)
	var fin: Dictionary = player_club()["finances"]
	var back := int(int(DataStore.item(item_id)["price"]) * 0.5) * qty
	fin["balance"] = int(fin["balance"]) + back
	fin["transfer_budget"] = mini(int(fin.get("transfer_budget", 0)) + back, int(fin["balance"]))
	inventory_changed.emit()
	return ""


## Find a player-squad instance by uid ({} if absent).
func squad_member(uid: String) -> Dictionary:
	for m in player_club()["squad"]:
		if str(m["uid"]) == uid:
			return m
	return {}


## Equip a held item from the storeroom onto a squad Pokémon. Any item it was
## already holding goes back to stock. "" = ok, else error.
func assign_held_item(uid: String, item_id: String) -> String:
	var m := squad_member(uid)
	if m.is_empty():
		return I18n.t("That Pokémon is not in your squad.")
	var it: Dictionary = DataStore.item(item_id)
	if it.is_empty() or str(it["class"]) != "held":
		return I18n.t("Only held-class items can be equipped.")
	var inv := player_inventory()
	if int(inv.get(item_id, 0)) <= 0:
		return I18n.t("None in the storeroom — buy one first.")
	var cur: Variant = m.get("held_item")
	if cur != null and str(cur) != "":
		if str(cur) == item_id:
			return I18n.t("Already holding that item.")
		inv[str(cur)] = int(inv.get(str(cur), 0)) + 1
	inv[item_id] = int(inv[item_id]) - 1
	if int(inv[item_id]) <= 0:
		inv.erase(item_id)
	m["held_item"] = item_id
	inventory_changed.emit()
	return ""


## Take a squad Pokémon's held item back into the storeroom. "" = ok.
func unassign_held_item(uid: String) -> String:
	var m := squad_member(uid)
	if m.is_empty():
		return I18n.t("That Pokémon is not in your squad.")
	var cur: Variant = m.get("held_item")
	if cur == null or str(cur) == "":
		return I18n.t("It isn't holding anything.")
	var inv := player_inventory()
	inv[str(cur)] = int(inv.get(str(cur), 0)) + 1
	m["held_item"] = null
	inventory_changed.emit()
	return ""


## Deduct items a club consumed (e.g. trainer items spent in an interactive
## match — the match screen reports {item_id: count_used} per club afterwards).
func consume_club_items(club_id: String, used: Dictionary) -> void:
	if used.is_empty():
		return
	var inv := club_inventory(club_id)
	for iid in used:
		inv[iid] = int(inv.get(iid, 0)) - int(used[iid])
		if int(inv[iid]) <= 0:
			inv.erase(iid)
	inventory_changed.emit()


## Save-compat / world-compat migration: every club gets an item store and
## every instance a held_item slot, so pre-items careers keep working.
func _ensure_item_state() -> void:
	for c in world["clubs"]:
		if not c.has("items") or typeof(c["items"]) != TYPE_DICTIONARY:
			c["items"] = {"potion": 3, "super_potion": 2, "full_heal": 1}
		for m in c["squad"]:
			if not m.has("held_item"):
				m["held_item"] = null
	for pool in ["free_agents", "prospects"]:
		for m in world.get(pool, []):
			if not m.has("held_item"):
				m["held_item"] = null


## AI clubs occasionally shop: equip a bare key battler or restock trainer
## items. Deterministic per (career_seed, date, club).
func _ai_daily_items() -> void:
	for c in world["clubs"]:
		if is_player_club(c["id"]):
			continue
		var r := RandomNumberGenerator.new()
		r.seed = career_seed + (current_date + "|items|" + str(c["id"])).hash()
		if r.randf() > 0.06:
			continue
		var fin: Dictionary = c["finances"]
		var bare: Array = c["squad"].filter(func(m):
			return m.get("held_item") == null or str(m.get("held_item", "")) == "")
		bare.sort_custom(func(a, b): return int(a["level"]) > int(b["level"]))
		if not bare.is_empty() and r.randf() < 0.65:
			var m: Dictionary = bare[0]
			var iid := _ai_pick_held_item(m, r)
			var price := int(DataStore.item(iid).get("price", 0))
			if price > 0 and int(fin["balance"]) >= price * 5:
				fin["balance"] = int(fin["balance"]) - price
				m["held_item"] = iid
		else:
			var pool := ["potion", "super_potion", "hyper_potion", "full_heal", "revive", "x_attack"]
			var iid2: String = pool[r.randi_range(0, pool.size() - 1)]
			var price2 := int(DataStore.item(iid2).get("price", 0))
			if price2 > 0 and int(fin["balance"]) >= price2 * 5:
				fin["balance"] = int(fin["balance"]) - price2
				var inv := club_inventory(str(c["id"]))
				inv[iid2] = int(inv.get(iid2, 0)) + 1


func _ai_pick_held_item(m: Dictionary, r: RandomNumberGenerator) -> String:
	var sp: Dictionary = DataStore.species(int(m["species_id"]))
	if sp.is_empty():
		return "leftovers"
	var base: Dictionary = sp["base"]
	var cands: Array = ["leftovers", "sitrus_berry", "lum_berry", "quick_claw"]
	for t in sp["types"]:
		for iid in DataStore.items:
			for fx in DataStore.items[iid].get("effects", []):
				if str(fx) == "type_boost:%s:1.2" % str(t):
					cands.append(str(iid))
	if int(base["atk"]) >= int(base["spa"]) + 15:
		cands.append("choice_band")
	elif int(base["spa"]) >= int(base["atk"]) + 15:
		cands.append("choice_specs")
	if int(base["spe"]) >= 100:
		cands.append("choice_scarf")
	if bool(sp.get("evolves", false)):
		cands.append("eviolite")
	return str(cands[r.randi_range(0, cands.size() - 1)])


# ------------------------------------------------------------------ time

## Advance the calendar one day; sim any fixtures due. Returns events of the day.
func advance_day() -> Array:
	current_date = Season.date_add(current_date, 1)
	var day_events: Array = []
	for f in fixtures_on(current_date):
		if f["played"]:
			continue
		var involves_player: bool = is_player_club(f["home"]) or is_player_club(f["away"])
		if involves_player and not auto_sim_player_matches:
			player_match_due.emit(f)
			day_events.append({"t": "player_match_due", "fixture": f})
			continue
		_play_fixture(f)
		day_events.append({"t": "fixture_played", "fixture": f})
	_maybe_generate_next_cup_round()
	_ai_daily_items()
	_settle_economy()
	_tick_services()
	date_changed.emit(current_date)
	return day_events


## Daily economy settlement (gates, travel, payroll, sponsorship, prize
## money). The model lives in the inbox piece (economy.gd) with its ledger
## stored in world.meta.economy; ticking it here means pure-sim timelines
## accrue money without the Inbox screen ever instantiating — the screen
## just renders the ledger. Duplicate-guarded inside tick(), so the Inbox
## re-ticking on load is a no-op.
func _settle_economy() -> void:
	if _economy == null and not _economy_checked:
		_economy_checked = true
		var econ_path := "res://screens/inbox/economy.gd"
		var news_path := "res://screens/inbox/news_gen.gd"
		if ResourceLoader.exists(econ_path) and ResourceLoader.exists(news_path):
			var econ: Variant = load(econ_path)
			var news: Variant = load(news_path)
			if econ is GDScript and news is GDScript:
				_economy = (econ as GDScript).new((news as GDScript).new())
	if _economy != null:
		_economy.tick()


## Continue button behaviour: advance until something notable happens
## (player fixture played/due or new inbox item), capped at `max_days`.
func advance_to_next_event(max_days: int = 14) -> void:
	var pid: String = world["meta"]["player_club_id"]
	var stop := false
	for i in max_days:
		var day_events := advance_day()
		for e in day_events:
			if e["t"] == "player_match_due":
				stop = true
			elif e["t"] == "fixture_played":
				var f: Dictionary = e["fixture"]
				if f["home"] == pid or f["away"] == pid:
					stop = true
		if stop:
			break
	save_game()


func _play_fixture(f: Dictionary) -> void:
	var seed_v: int = career_seed + absi(str(f["id"]).hash()) % 1000000
	var result := Season.simulate_fixture(club(f["home"]), club(f["away"]), seed_v)
	f["played"] = true
	f["score_home"] = result["score_home"]
	f["score_away"] = result["score_away"]
	# Persist the play-time match report (single source of truth for the
	# Competition screen's reports and season stats — never re-derived later).
	f["detail"] = result["detail"]
	_table_dirty = true
	fixture_played.emit(f)
	table_updated.emit()
	if is_player_club(f["home"]) or is_player_club(f["away"]):
		var we_home := is_player_club(f["home"])
		var us: int = f["score_home"] if we_home else f["score_away"]
		var them: int = f["score_away"] if we_home else f["score_home"]
		var opp: String = club(f["away"] if we_home else f["home"])["name"]
		add_inbox_message(current_date, I18n.t("Match report: %d-%d vs %s") % [us, them, opp],
			I18n.t("We won the %s tie against %s, %d-%d in battles." if us > them
				else "We lost the %s tie against %s, %d-%d in battles.") % [I18n.t(str(f["comp"])), opp, us, them])


func _maybe_generate_next_cup_round() -> void:
	var current := fixtures.filter(func(f): return f["comp"] == "cup" and int(f["round"]) == cup_round)
	if current.is_empty() or current.any(func(f): return not f["played"]):
		return
	if current.size() <= 1:
		return  # final played, cup over
	var winners: Array = current.map(func(f):
		return f["home"] if f["score_home"] > f["score_away"] else f["away"])
	cup_round += 1
	fixtures += _season_tag_ids(Season.make_cup_round(winners, cup_round,
		Season.cup_round_date(season_start, cup_round), career_seed + cup_round))
	add_inbox_message(current_date, I18n.t("%s draw: %s") % [I18n.t(cup_name()), I18n.cup_round(cup_round)],
		I18n.t("The %s %s draw has been made — clubs from both leagues remain in the hat.") %
		[I18n.t(cup_name()), I18n.cup_round(cup_round)])


# ------------------------------------------------------------------ season rollover

## Fixture-id prefix that keeps ids unique across seasons ("" in season 1, so
## every existing id — and everything keyed on them, e.g. the economy's
## settled-fixture guard — is untouched; "S2" etc. afterwards).
func season_id_prefix() -> String:
	return "" if season_no() <= 1 else "S%d" % season_no()


func _season_tag_ids(fx: Array) -> Array:
	var prefix := season_id_prefix()
	if prefix != "":
		for f in fx:
			f["id"] = prefix + str(f["id"])
	return fx


## Roll the world into the NEXT season (called by the season_flow service once
## the Championship Series final has been played and the ceremony is done):
## season counter up, calendar jumps a year forward to the new preseason,
## fresh fixtures for both leagues + a new cup draw, every Pokémon a year
## older. Squads, finances, development and inbox history all carry over.
func start_new_season() -> void:
	world["meta"]["season_no"] = season_no() + 1
	season_start = Season.date_add(season_start, 364)   # keeps weekday cadence
	world["meta"]["season_start"] = season_start
	current_date = season_start

	fixtures = []
	var prefixes := ["L", "J", "K", "M"]
	var lgs := leagues()
	for i in lgs.size():
		var lid: String = str(lgs[i]["id"])
		fixtures += Season.make_league_fixtures(league_club_ids(lid), season_start,
			season_id_prefix() + prefixes[mini(i, prefixes.size() - 1)], lid)
	cup_round = 1
	fixtures += _season_tag_ids(Season.make_cup_round(all_club_ids(), 1,
		Season.cup_round_date(season_start, 1), career_seed + season_no() * 104729))

	# a year passes: everyone ages 12 months (contract expiry dates simply come
	# a year closer — they are calendar dates and the calendar just jumped).
	for c in world["clubs"]:
		for m in c["squad"]:
			m["age_months"] = int(m.get("age_months", 0)) + 12
	for pool in ["free_agents", "prospects"]:
		for m in world.get(pool, []):
			m["age_months"] = int(m.get("age_months", 0)) + 12

	_table_dirty = true
	add_inbox_message(current_date, I18n.t("Season %d is under way") % season_no(),
		I18n.t("Preseason at %s. Both championships have published their fixtures and the %s first-round draw has been made. Your league opener is on %s.") % [
		player_club()["name"], I18n.t(cup_name()),
		I18n.pretty_date(next_player_fixture().get("date", season_start))])
	season_rolled.emit(season_no())
	date_changed.emit(current_date)
	table_updated.emit()


# ------------------------------------------------------------------ services
# Auto-loaded simulation services (the drop-in convention for later builders).
# Any script at res://shared/sim/services/*.gd is instantiated at career start
# (new career AND load), ticked daily, and persisted inside the save. See
# docs/ARCHITECTURE.md ("Simulation services") for the exact interface. All
# hooks are optional (duck-typed via has_method) — GameState never needs edits.

## Discover + instantiate every service, restore its saved state, then start it.
func _load_services() -> void:
	_services.clear()
	var dir_path := "res://shared/sim/services"
	var states: Dictionary = world["meta"].get("services", {})
	var dir := DirAccess.open(dir_path)
	if dir != null:
		var files := Array(dir.get_files())
		files.sort()
		for fname in files:
			if not str(fname).ends_with(".gd"):
				continue
			var script: Variant = load("%s/%s" % [dir_path, fname])
			if not (script is GDScript):
				continue
			var svc: Variant = (script as GDScript).new()
			_services.append(svc)
	for svc in _services:
		var sid := _service_id(svc)
		if svc.has_method("load_state") and states.has(sid):
			svc.load_state(states[sid])
	for svc in _services:
		if svc.has_method("on_career_started"):
			svc.on_career_started(self)


## Manual registration (tests / screens that want the same lifecycle).
func register_service(svc: Object) -> void:
	_services.append(svc)
	var states: Dictionary = world["meta"].get("services", {})
	var sid := _service_id(svc)
	if svc.has_method("load_state") and states.has(sid):
		svc.load_state(states[sid])
	if svc.has_method("on_career_started"):
		svc.on_career_started(self)


func _service_id(svc: Object) -> String:
	if svc.has_method("service_id"):
		return str(svc.service_id())
	var script: Script = svc.get_script()
	if script != null:
		return str(script.resource_path.get_file().get_basename())
	return "service"


func _tick_services() -> void:
	for svc in _services:
		if svc.has_method("on_day"):
			svc.on_day(self, current_date)


## Gather every service's state into world.meta.services (rides the world save).
func _collect_service_state() -> void:
	if world.is_empty():
		return
	var states: Dictionary = world["meta"].get("services", {})
	for svc in _services:
		if svc.has_method("save_state"):
			states[_service_id(svc)] = svc.save_state()
	if not states.is_empty():
		world["meta"]["services"] = states


## World-compat: clubs get a league id, meta gets the league structure + cup
## name, and meta.league_name always names the PLAYER'S league (the string
## every existing screen renders as its competition title).
func _ensure_league_state() -> void:
	for c in world["clubs"]:
		if not c.has("league"):
			c["league"] = "kanto"
	if not world["meta"].has("leagues"):
		world["meta"]["leagues"] = [
			{"id": "kanto", "name": str(world["meta"].get("league_name", "Kanto League"))}]
	if not world["meta"].has("cup_name"):
		world["meta"]["cup_name"] = "Indigo Cup"
	if not world["meta"].has("season_no"):
		world["meta"]["season_no"] = 1
	world["meta"]["league_name"] = league_name(player_league_id())


# ------------------------------------------------------------------ inbox

func add_inbox_message(date: String, title: String, body: String) -> void:
	inbox.push_front({"date": date, "title": title, "body": body, "read": false})
	inbox_updated.emit()


func _index_clubs() -> void:
	_clubs_by_id.clear()
	for c in world["clubs"]:
		_clubs_by_id[c["id"]] = c


# ------------------------------------------------------------------ settings
# ADDITIVE (polish piece). `settings` is a flat JSON-safe dict persisted in the
# save. Screens read via setting()/settings and write via set_setting().

## World data generated before 2026-08-31 could carry impossible contract
## expiry dates ("YYYY-02-30"), which crash Time.get_unix_time_from_datetime_dict
## in every date-diff helper. Clamp the day to the month's real length so both
## old saves and the shipped world.json heal on load.
func _sanitize_contract_dates() -> void:
	var mdays := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	var pools: Array = []
	for c in world["clubs"]:
		pools.append(c["squad"])
	pools.append(world["free_agents"])
	pools.append(world["prospects"])
	for pool in pools:
		for inst in pool:
			if typeof(inst.get("contract")) != TYPE_DICTIONARY:
				continue
			var parts: PackedStringArray = str(inst["contract"].get("expiry", "")).split("-")
			if parts.size() != 3:
				continue
			var mo := int(parts[1])
			var dmax: int = mdays[clampi(mo, 1, 12) - 1]
			if mo == 2 and int(parts[0]) % 4 == 0:
				dmax = 29
			if int(parts[2]) > dmax:
				inst["contract"]["expiry"] = "%s-%s-%02d" % [parts[0], parts[1], dmax]


func _ensure_settings() -> void:
	for k in SETTINGS_DEFAULTS:
		if not settings.has(k):
			settings[k] = SETTINGS_DEFAULTS[k]


func setting(key: String, default: Variant = null) -> Variant:
	_ensure_settings()
	return settings.get(key, default if default != null else SETTINGS_DEFAULTS.get(key))


func set_setting(key: String, value: Variant) -> void:
	_ensure_settings()
	settings[key] = value
	settings_changed.emit(key)


# ------------------------------------------------------------------ manager career & game over
# ADDITIVE (polish piece). The manager's own career record — one stint entry
# per completed season, written by the season_flow service at each ceremony —
# and the sacking pathway: the board fires the manager, the shell shows a
# career-summary game-over screen, then offers from lesser clubs continue the
# career (accept_job_offer) or the player starts fresh.

## Manager career history (oldest first). Entry (written by season_flow):
## {season, club_id, club, league, pos, points, wins, losses, cup, honours:[..]}
func manager_history() -> Array:
	if typeof(world["meta"].get("manager_history")) != TYPE_ARRAY:
		world["meta"]["manager_history"] = []
	return world["meta"]["manager_history"]


func record_manager_stint(entry: Dictionary) -> void:
	manager_history().append(entry)


func is_game_over() -> bool:
	return typeof(world.get("meta", {}).get("game_over")) == TYPE_DICTIONARY \
		and not (world["meta"]["game_over"] as Dictionary).is_empty()


## {reason, season, club_id, club, summary:{seasons, record, honours:[..]},
##  offers:[{club_id, name, league, reputation}]} — set by the season_flow
## service the moment the board pulls the trigger.
func game_over_info() -> Dictionary:
	return world["meta"].get("game_over", {}) if is_game_over() else {}


## The board fires the manager. Persists the moment in world.meta.game_over
## (so a reload lands back on the game-over screen) and signals the shell.
func trigger_game_over(info: Dictionary) -> void:
	world["meta"]["game_over"] = info
	game_over.emit(info)


## Continue the career at one of the offered clubs. "" = ok, else error.
func accept_job_offer(club_id: String) -> String:
	if not is_game_over():
		return I18n.t("There is no offer on the table.")
	var offers: Array = game_over_info().get("offers", [])
	if not offers.any(func(o): return str(o.get("club_id", "")) == club_id):
		return I18n.t("That club has not made an offer.")
	var old_club: String = str(world["meta"].get("player_club_id", ""))
	world["meta"]["game_over"] = {}
	world["meta"]["player_club_id"] = club_id
	_ensure_league_state()   # league_name follows the player's league
	_table_dirty = true
	add_inbox_message(current_date, I18n.t("A new chapter: welcome to %s") % player_club().get("name", club_id),
		I18n.t("The board of %s has taken a chance on you after your dismissal at %s. Expectations are humbler here — rebuild your reputation, one matchday at a time.") % [
		player_club().get("name", club_id), str(club(old_club).get("name", old_club))])
	career_started.emit()
	date_changed.emit(current_date)
	table_updated.emit()
	save_game()
	return ""
