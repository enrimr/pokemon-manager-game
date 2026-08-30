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

const SAVE_PATH := "user://save.json"

var world: Dictionary = {}          # deep-copied from world.json, mutated over time
var current_date: String = ""
var season_start: String = ""
var fixtures: Array = []            # league + generated cup fixtures
var cup_round: int = 0              # highest cup round generated so far
var inbox: Array = []               # [{date, title, body, read}]
var career_seed: int = 0
var auto_sim_player_matches := true # match piece can set false and intercept

var _clubs_by_id: Dictionary = {}
var _table_cache: Array = []
var _table_dirty := true
var _economy: RefCounted = null     # inbox piece's economy.gd, ticked daily
var _economy_checked := false


func _ready() -> void:
	# Boot into a playable state: load save if present, else new career.
	# (Deferred so DataStore's _ready has definitely run first.)
	if not load_game():
		new_career()


# ------------------------------------------------------------------ lifecycle

func new_career(seed_value: int = 20260801) -> void:
	career_seed = seed_value
	var f := FileAccess.open("res://shared/data/world.json", FileAccess.READ)
	world = JSON.parse_string(f.get_as_text())
	_index_clubs()
	_ensure_item_state()
	_ensure_budget_state()
	season_start = world["meta"]["season_start"]
	current_date = season_start
	fixtures = Season.make_league_fixtures(club_ids(), season_start)
	cup_round = 1
	fixtures += Season.make_cup_round(club_ids(), 1, Season.cup_round_date(season_start, 1), career_seed)
	inbox = []
	add_inbox_message(current_date, "Welcome to %s" % player_club()["name"],
		"The board expects a solid mid-table finish in the %s. Your first fixture is on %s." %
		[world["meta"]["league_name"], Season.pretty_date(next_player_fixture().get("date", season_start))])
	_table_dirty = true
	career_started.emit()
	date_changed.emit(current_date)
	table_updated.emit()


func save_game() -> bool:
	var data := {
		"version": 1,
		"career_seed": career_seed,
		"current_date": current_date,
		"season_start": season_start,
		"cup_round": cup_round,
		"world": world,
		"fixtures": fixtures,
		"inbox": inbox,
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
	if data == null or typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) != 1:
		push_warning("GameState: ignoring incompatible save file")
		return false
	career_seed = int(data["career_seed"])
	current_date = data["current_date"]
	season_start = data["season_start"]
	cup_round = int(data["cup_round"])
	world = data["world"]
	fixtures = data["fixtures"]
	inbox = data["inbox"]
	_index_clubs()
	_ensure_item_state()
	_ensure_budget_state()
	# Save migration: fixtures played before match details were persisted at
	# play time get reconciled once (adopt a faithful replay, or a score-only
	# stub when squads have drifted) so reports can never contradict scores.
	var rec := Season.reconcile_fixture_details(fixtures)
	if int(rec["adopted"]) + int(rec["cleared"]) > 0:
		save_game()
	_table_dirty = true
	career_started.emit()
	date_changed.emit(current_date)
	table_updated.emit()
	return true


func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


# ------------------------------------------------------------------ queries

func club_ids() -> Array:
	return world["clubs"].map(func(c): return c["id"])


func club(id: String) -> Dictionary:
	return _clubs_by_id.get(id, {})


func player_club() -> Dictionary:
	return club(world["meta"]["player_club_id"])


func is_player_club(id: String) -> bool:
	return id == world["meta"]["player_club_id"]


func league_table() -> Array:
	if _table_dirty:
		_table_cache = Season.compute_table(club_ids(), fixtures)
		_table_dirty = false
	return _table_cache


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
		return "Unknown item."
	qty = maxi(1, qty)
	var cost := int(it["price"]) * qty
	var fin: Dictionary = player_club()["finances"]
	var spendable := mini(int(fin["balance"]), int(fin.get("transfer_budget", 0)))
	if spendable < cost:
		return "Not enough transfer budget — %s %d needed, %s %d released by the board." % [
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
		return "Not enough of that item in the storeroom."
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
		return "That Pokémon is not in your squad."
	var it: Dictionary = DataStore.item(item_id)
	if it.is_empty() or str(it["class"]) != "held":
		return "Only held-class items can be equipped."
	var inv := player_inventory()
	if int(inv.get(item_id, 0)) <= 0:
		return "None in the storeroom — buy one first."
	var cur: Variant = m.get("held_item")
	if cur != null and str(cur) != "":
		if str(cur) == item_id:
			return "Already holding that item."
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
		return "That Pokémon is not in your squad."
	var cur: Variant = m.get("held_item")
	if cur == null or str(cur) == "":
		return "It isn't holding anything."
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
		var verdict := "won" if us > them else "lost"
		add_inbox_message(current_date, "Match report: %d-%d vs %s" % [us, them, opp],
			"We %s the %s tie against %s, %d-%d in battles." % [verdict, f["comp"], opp, us, them])


func _maybe_generate_next_cup_round() -> void:
	var current := fixtures.filter(func(f): return f["comp"] == "cup" and int(f["round"]) == cup_round)
	if current.is_empty() or current.any(func(f): return not f["played"]):
		return
	if current.size() <= 1:
		return  # final played, cup over
	var winners: Array = current.map(func(f):
		return f["home"] if f["score_home"] > f["score_away"] else f["away"])
	cup_round += 1
	fixtures += Season.make_cup_round(winners, cup_round,
		Season.cup_round_date(season_start, cup_round), career_seed + cup_round)
	add_inbox_message(current_date, "Cup draw: %s" % Season.cup_round_name(cup_round),
		"The %s draw has been made." % Season.cup_round_name(cup_round))


# ------------------------------------------------------------------ inbox

func add_inbox_message(date: String, title: String, body: String) -> void:
	inbox.push_front({"date": date, "title": title, "body": body, "read": false})
	inbox_updated.emit()


func _index_clubs() -> void:
	_clubs_by_id.clear()
	for c in world["clubs"]:
		_clubs_by_id[c["id"]] = c
