extends Node
## SquadHistory — the squad piece's persistent career-history model.
## Lives at /root/SquadHistory (created lazily, survives screen re-instantiation)
## and persists to user://squad_history.json. It turns every squad member from a
## snapshot into a trajectory, FM-style:
##
##   - career EVENTS per Pokémon: baseline ("at the club when you took charge"),
##     arrivals, contract renewals, transfer listings/unlistings, sales, releases,
##     level changes, moves learned, and training-driven attribute (IV) gains —
##     each recorded on the in-game date it actually happened;
##   - dated attribute SNAPSHOTS (level, IVs, effective stats, value, condition,
##     morale) taken weekly and on every attribute change, powering progression
##     deltas ("since 30 days ago") and sparklines on the profile History tab;
##   - per-SEASON stat aggregates (apps, wins, KOs, damage, faints, rating) keyed
##     by season start, kept live for the running season and frozen for past ones,
##     rendering FM's season-by-season career-stats table.
##
## Nothing here is invented: changes are detected by diffing the live GameState
## squad against the last observed state, and the squad piece's own management
## actions (SquadService) report their events directly.

signal history_changed

const LEGACY_PATH := "user://squad_history.json"   # pre-slots flat file (adopted by the migrated career)


## Per-career state file (saves piece): rides next to the career's save slot,
## so switching careers in Load Game never leaks state between them.
func _state_path() -> String:
	if GameState.save_slot == "":
		return LEGACY_PATH
	return "%s/%s.squad_history.json" % [GameState.SAVE_DIR, GameState.save_slot]

const UI := preload("res://screens/squad/ui_helpers.gd")
const SeasonStats := preload("res://screens/squad/season_stats.gd")

const STAT_KEYS := ["hp", "atk", "def", "spa", "spd", "spe"]
const STAT_SHORT := {"hp": "HP", "atk": "Atk", "def": "Def",
	"spa": "SpA", "spd": "SpD", "spe": "Spe"}

const SNAP_INTERVAL_DAYS := 7
const SNAP_MAX := 160
const EVENTS_MAX := 260

## Event types shown in "Transfers & Contracts":
const CONTRACT_TYPES := ["baseline", "arrived", "renewal", "listed", "unlisted",
	"sold", "released", "contract"]
## Event types shown in "Development log":
const DEV_TYPES := ["development", "move", "level"]

var state: Dictionary = {}

static var _instance: Node = null


static func ensure() -> Node:
	if _instance != null and is_instance_valid(_instance):
		return _instance
	var root := Engine.get_main_loop().root as Node
	var existing := root.get_node_or_null("SquadHistory")
	if existing != null:
		_instance = existing
		return existing
	var svc: Node = load("res://screens/squad/career_history.gd").new()
	svc.name = "SquadHistory"
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
	sync()


# ------------------------------------------------------------------ state

func _default_state() -> Dictionary:
	return {
		"version": 1,
		"last": "",           # last synced in-game date
		"initialised": false, # first-ever sync writes tr("took charge") baselines
		"mons": {},           # uid -> mon history entry (see _mon)
	}


func _load_state() -> void:
	var path := _state_path()
	if not FileAccess.file_exists(path) and GameState.save_slot == "career_legacy" \
			and FileAccess.file_exists(LEGACY_PATH):
		path = LEGACY_PATH   # one-time adoption: re-saved under the slot next write
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		var data: Variant = JSON.parse_string(f.get_as_text())
		if typeof(data) == TYPE_DICTIONARY and int(data.get("version", 0)) == 1:
			state = data
			return
	state = _default_state()


func save_state() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GameState.SAVE_DIR))
	var f := FileAccess.open(_state_path(), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(state))


func _on_career_event() -> void:
	_load_state()   # career switched slots (Load Game): read THAT career's history
	# New career after a save wipe: our last date is in the future -> reset.
	if str(state.get("last", "")) > GameState.current_date:
		state = _default_state()
		save_state()
		history_changed.emit()
	sync()


func _on_date_changed(_d: String) -> void:
	sync()


## uid -> history entry, creating it (with a baseline/arrival event) on demand.
func _mon(uid: String, inst: Dictionary) -> Dictionary:
	var mons: Dictionary = state["mons"]
	if mons.has(uid):
		return mons[uid]
	var date: String = GameState.current_date
	var entry := {
		"name": UI.display_name(inst),
		"species": str(inst["species"]),
		"joined": date,
		"left": "",
		"events": [],
		"snaps": [],
		"cur": _observe(inst),
		"seasons": {},
	}
	mons[uid] = entry
	var text: String
	var etype: String
	if not bool(state.get("initialised", false)) or date <= GameState.season_start:
		etype = "baseline"
		text = tr("At the club when you took charge — Lv %d, contracted at %s/wk to %s.") % [
			int(inst["level"]), UI.money(int(inst["contract"]["salary"])),
			I18n.pretty_date(str(inst["contract"]["expiry"]))]
	else:
		etype = "arrived"
		text = tr("Joined the squad — Lv %d, contracted at %s/wk to %s.") % [
			int(inst["level"]), UI.money(int(inst["contract"]["salary"])),
			I18n.pretty_date(str(inst["contract"]["expiry"]))]
	entry["events"].append({"date": date, "type": etype, "text": text})
	entry["snaps"].append(_snapshot(inst))
	return entry


## The compact "last observed" mirror used for change detection.
func _observe(inst: Dictionary) -> Dictionary:
	var stats := UI.effective_stats(inst)
	var ivs: Dictionary = inst.get("ivs", {})
	var iv_out := {}
	var st_out := {}
	for k in STAT_KEYS:
		iv_out[k] = int(ivs.get(k, 8))
		st_out[k] = int(stats[k])
	return {
		"level": int(inst["level"]),
		"ivs": iv_out,
		"stats": st_out,
		"moves": (inst.get("moves", []) as Array).duplicate(),
		"salary": int(inst["contract"]["salary"]),
		"expiry": str(inst["contract"]["expiry"]),
	}


func _snapshot(inst: Dictionary) -> Dictionary:
	var obs := _observe(inst)
	return {
		"date": GameState.current_date,
		"level": obs["level"],
		"ivs": obs["ivs"],
		"stats": obs["stats"],
		"value": UI.est_value(inst),
		"cond": int(inst["condition"]),
		"morale": int(inst["morale"]),
	}


# ------------------------------------------------------------------ sync (diff live squad vs last observed)

func sync() -> void:
	if GameState.world.is_empty():
		return
	if str(state.get("last", "")) != "" and str(state["last"]) > GameState.current_date:
		_on_career_event()
		return
	var club: Dictionary = GameState.player_club()
	if club.is_empty():
		return
	var changed := false
	var date: String = GameState.current_date
	var seen := {}
	var was_initialised: bool = bool(state.get("initialised", false))

	SeasonStats.player_stats()
	for inst in club.get("squad", []):
		var uid: String = str(inst["uid"])
		seen[uid] = true
		var had := (state["mons"] as Dictionary).has(uid)
		var m := _mon(uid, inst)
		if not had:
			changed = true
		m["name"] = UI.display_name(inst)
		if had:
			changed = _diff_mon(m, inst, date) or changed
		changed = _update_season_row(m, uid, club) or changed
		changed = _maybe_snap(m, inst, date) or changed

	# Departures not already explained by a recorded sale/release.
	for uid in state["mons"]:
		var m: Dictionary = state["mons"][uid]
		if seen.has(uid) or str(m.get("left", "")) != "":
			continue
		m["left"] = date
		(m["events"] as Array).append({"date": date, "type": "contract",
			"text": tr("Left the club.")})
		changed = true

	if not was_initialised:
		state["initialised"] = true
		changed = true
	if str(state.get("last", "")) != date:
		state["last"] = date
		changed = true
	if changed:
		save_state()
		history_changed.emit()


## Compare a squad instance against its mirror; record real change events.
func _diff_mon(m: Dictionary, inst: Dictionary, date: String) -> bool:
	var cur: Dictionary = m["cur"]
	var now := _observe(inst)
	var changed := false
	var events: Array = m["events"]

	# --- level
	if int(now["level"]) != int(cur["level"]):
		events.append({"date": date, "type": "level",
			"text": tr("Reached level %d (was %d).") % [int(now["level"]), int(cur["level"])]})
		changed = true

	# --- attribute gains (training converts progress into IV points)
	var parts: Array = []
	for k in STAT_KEYS:
		var d_iv := int(now["ivs"][k]) - int(cur["ivs"][k])
		if d_iv != 0:
			var d_eff := int(now["stats"][k]) - int(cur["stats"][k])
			var eff_note := ""
			if d_eff != 0:
				eff_note = tr(", eff %d > %d") % [int(cur["stats"][k]), int(now["stats"][k])]
			parts.append("%s %d > %d (%+d%s)" % [STAT_SHORT[k],
				int(cur["ivs"][k]), int(now["ivs"][k]), d_iv, eff_note])
	if not parts.is_empty():
		events.append({"date": date, "type": "development",
			"text": tr("Training gains: ") + " · ".join(PackedStringArray(parts))})
		changed = true

	# --- moves learned / replaced
	var old_moves: Array = cur["moves"]
	var new_moves: Array = now["moves"]
	var added: Array = new_moves.filter(func(mv): return not old_moves.has(mv))
	var removed: Array = old_moves.filter(func(mv): return not new_moves.has(mv))
	for i in added.size():
		var text := I18n.t("Learned %s") % I18n.t(str(added[i]))
		if i < removed.size():
			text += ", replacing %s" % str(removed[i])
		events.append({"date": date, "type": "move", "text": text + "."})
		changed = true

	# --- contract changed outside our own renewal flow (e.g. another piece)
	if int(now["salary"]) != int(cur["salary"]) or str(now["expiry"]) != str(cur["expiry"]):
		events.append({"date": date, "type": "contract",
			"text": tr("Contract updated: %s/wk to %s (was %s/wk to %s).") % [
				UI.money(int(now["salary"])), I18n.pretty_date(str(now["expiry"])),
				UI.money(int(cur["salary"])), I18n.pretty_date(str(cur["expiry"]))]})
		changed = true

	if changed:
		m["cur"] = now
		_trim(events, EVENTS_MAX)
	return changed


func _maybe_snap(m: Dictionary, inst: Dictionary, date: String) -> bool:
	var snaps: Array = m["snaps"]
	if snaps.is_empty():
		snaps.append(_snapshot(inst))
		return true
	var last: Dictionary = snaps[snaps.size() - 1]
	var due := UI.days_between(str(last["date"]), date) >= SNAP_INTERVAL_DAYS
	var moved := int(last["level"]) != int(inst["level"])
	if not moved:
		var ivs: Dictionary = inst.get("ivs", {})
		for k in STAT_KEYS:
			if int((last["ivs"] as Dictionary).get(k, 8)) != int(ivs.get(k, 8)):
				moved = true
				break
	if not (due or moved):
		return false
	snaps.append(_snapshot(inst))
	if snaps.size() > SNAP_MAX:
		# Thin the oldest half, keeping first (baseline) and recency.
		var thinned: Array = [snaps[0]]
		for i in range(1, snaps.size()):
			if i % 2 == 0 or i > snaps.size() - SNAP_MAX / 2:
				thinned.append(snaps[i])
		m["snaps"] = thinned
	return true


func _update_season_row(m: Dictionary, uid: String, club: Dictionary) -> bool:
	var key: String = GameState.season_start
	var row := {
		"season": season_label(key),
		"club": str(club.get("short", "?")),
		"apps": SeasonStats.stat_of(uid, "battles"),
		"wins": SeasonStats.stat_of(uid, "wins"),
		"kos": SeasonStats.stat_of(uid, "kos"),
		"dmg": SeasonStats.stat_of(uid, "dmg"),
		"taken": SeasonStats.stat_of(uid, "taken"),
		"faints": SeasonStats.stat_of(uid, "faints"),
		"rat": SeasonStats.avg_rating(uid),
	}
	var seasons: Dictionary = m["seasons"]
	if seasons.has(key) and _rows_equal(seasons[key], row):
		return false
	seasons[key] = row
	return true


static func _rows_equal(a: Dictionary, b: Dictionary) -> bool:
	for k in ["apps", "wins", "kos", "dmg", "taken", "faints"]:
		if int(a.get(k, -1)) != int(b.get(k, -1)):
			return false
	return true


static func _trim(arr: Array, cap: int) -> void:
	while arr.size() > cap:
		arr.remove_at(0)


static func season_label(season_start: String) -> String:
	var y := int(season_start.substr(0, 4))
	return "%d/%02d" % [y, (y + 1) % 100]


# ------------------------------------------------------------------ action hooks (called by SquadService)

func _push(uid: String, etype: String, text: String) -> void:
	var mons: Dictionary = state["mons"]
	if not mons.has(uid):
		return
	var m: Dictionary = mons[uid]
	(m["events"] as Array).append({"date": GameState.current_date, "type": etype, "text": text})
	_trim(m["events"], EVENTS_MAX)


func on_renewal(inst: Dictionary, old_wage: int, wage: int, years: int, bonus: int) -> void:
	var uid: String = str(inst["uid"])
	_push(uid, "renewal", tr("Signed a new %d-year contract at %s/wk (was %s/wk)%s, running to %s.") % [
		years, UI.money(wage), UI.money(old_wage),
		(tr(" plus a %s signing bonus") % UI.money(bonus)) if bonus > 0 else "",
		I18n.pretty_date(str(inst["contract"]["expiry"]))])
	# Refresh the mirror so sync() does not double-report the contract change.
	if (state["mons"] as Dictionary).has(uid):
		(state["mons"][uid] as Dictionary)["cur"] = _observe(inst)
	save_state()
	history_changed.emit()


func on_listed(inst: Dictionary, ask: int) -> void:
	_push(str(inst["uid"]), "listed",
		tr("Placed on the transfer list at %s (valued %s).") % [UI.money(ask), UI.money(UI.est_value(inst))])
	save_state()
	history_changed.emit()


func on_unlisted(inst: Dictionary) -> void:
	_push(str(inst["uid"]), "unlisted", I18n.t("Removed from the transfer list."))
	save_state()
	history_changed.emit()


func on_sold(inst: Dictionary, buyer_name: String, fee: int) -> void:
	var uid: String = str(inst["uid"])
	_push(uid, "sold", tr("Sold to %s for %s.") % [buyer_name, UI.money(fee)])
	if (state["mons"] as Dictionary).has(uid):
		(state["mons"][uid] as Dictionary)["left"] = GameState.current_date
	save_state()
	history_changed.emit()


func on_released(inst: Dictionary, comp: int) -> void:
	var uid: String = str(inst["uid"])
	_push(uid, "released", tr("Contract terminated%s; entered free agency.") %
		((tr(" (%s compensation paid)") % UI.money(comp)) if comp > 0 else ""))
	if (state["mons"] as Dictionary).has(uid):
		(state["mons"][uid] as Dictionary)["left"] = GameState.current_date
	save_state()
	history_changed.emit()


# ------------------------------------------------------------------ queries (profile / table)

func joined_on(uid: String) -> String:
	var m: Dictionary = (state["mons"] as Dictionary).get(uid, {})
	return str(m.get("joined", ""))


## Events for a squad member, newest first, optionally filtered by type list.
func events_for(uid: String, types: Array = []) -> Array:
	var m: Dictionary = (state["mons"] as Dictionary).get(uid, {})
	var out: Array = (m.get("events", []) as Array).duplicate()
	if not types.is_empty():
		out = out.filter(func(e): return types.has(str(e["type"])))
	out.reverse()
	return out


## Attribute snapshots, oldest first.
func snapshots_for(uid: String) -> Array:
	var m: Dictionary = (state["mons"] as Dictionary).get(uid, {})
	return m.get("snaps", []) as Array


## Change since ~`days` ago (vs the newest snapshot at/before the cutoff, or the
## oldest snapshot if history is younger than the window). Compares against the
## LIVE instance. Returns {has, from, level, value, ivs:{k:d}, stats:{k:d}, iv_total}.
func delta_since(uid: String, inst: Dictionary, days: int = 30) -> Dictionary:
	var snaps := snapshots_for(uid)
	if snaps.is_empty() or inst.is_empty():
		return {"has": false}
	var cutoff := Season.date_add(GameState.current_date, -days)
	var base: Dictionary = snaps[0]
	for s in snaps:
		if str(s["date"]) <= cutoff:
			base = s
		else:
			break
	var now := _observe(inst)
	var d_ivs := {}
	var d_stats := {}
	var iv_total := 0
	for k in STAT_KEYS:
		d_ivs[k] = int(now["ivs"][k]) - int((base["ivs"] as Dictionary).get(k, 8))
		d_stats[k] = int(now["stats"][k]) - int((base["stats"] as Dictionary).get(k, 0))
		iv_total += int(d_ivs[k])
	return {
		"has": true,
		"from": str(base["date"]),
		"base_ivs": base["ivs"], "base_stats": base["stats"],
		"level": int(now["level"]) - int(base["level"]),
		"value": UI.est_value(inst) - int(base["value"]),
		"ivs": d_ivs, "stats": d_stats, "iv_total": iv_total,
	}


## Total IV points gained in the window — the squad table's "Dev" column.
func dev_gain(uid: String, inst: Dictionary, days: int = 30) -> int:
	var d := delta_since(uid, inst, days)
	return int(d.get("iv_total", 0)) if bool(d.get("has", false)) else 0


## Season-by-season career stat rows, oldest first.
func season_rows(uid: String) -> Array:
	var m: Dictionary = (state["mons"] as Dictionary).get(uid, {})
	var seasons: Dictionary = m.get("seasons", {})
	var keys := seasons.keys()
	keys.sort()
	var out: Array = []
	for k in keys:
		out.append(seasons[k])
	return out


func career_totals(uid: String) -> Dictionary:
	var tot := {"apps": 0, "wins": 0, "kos": 0, "dmg": 0, "taken": 0, "faints": 0,
		"rat_sum": 0.0, "seasons": 0}
	for row in season_rows(uid):
		tot["seasons"] += 1
		for k in ["apps", "wins", "kos", "dmg", "taken", "faints"]:
			tot[k] += int(row[k])
		tot["rat_sum"] += float(row["rat"]) * float(int(row["apps"]))
	tot["rat"] = (float(tot["rat_sum"]) / float(tot["apps"])) if int(tot["apps"]) > 0 else 0.0
	return tot
