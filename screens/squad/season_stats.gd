extends RefCounted
## Squad piece: per-Pokémon season statistics.
##
## GameState instant-sims fixtures deterministically (career_seed + fixture id hash),
## so we can replay each played player fixture through the real BattleEngine and
## aggregate genuine per-battler numbers: battles, wins, KOs, damage dealt/taken,
## faints and an FM-style 4.5-10.0 match rating. Results are cached per fixture id
## for the lifetime of the process and invalidated if the career changes.

static var _processed: Dictionary = {}   # fixture id -> true
static var _by_uid: Dictionary = {}      # uid -> aggregate dict
static var _form: Dictionary = {}        # uid -> Array of per-fixture entries
static var _career_key: String = ""


static func _blank() -> Dictionary:
	return {"battles": 0, "wins": 0, "kos": 0, "dmg": 0, "taken": 0,
		"faints": 0, "rating_sum": 0.0}


## uid -> {battles, wins, kos, dmg, taken, faints, rating_sum}
static func player_stats() -> Dictionary:
	var key := "%d:%s" % [GameState.career_seed, GameState.season_start]
	if key != _career_key:
		_career_key = key
		_processed.clear()
		_by_uid.clear()
		_form.clear()
	for f in GameState.player_fixtures():
		if f.get("played", false) and not _processed.has(f["id"]):
			_processed[f["id"]] = true
			_replay_fixture(f)
	return _by_uid


static func avg_rating(uid: String) -> float:
	var s: Dictionary = _by_uid.get(uid, {})
	if s.is_empty() or int(s["battles"]) == 0:
		return 0.0
	return float(s["rating_sum"]) / float(s["battles"])


static func stat_of(uid: String, field: String) -> int:
	var s: Dictionary = _by_uid.get(uid, {})
	return int(s.get(field, 0))


## Per-fixture form entries for a battler, newest first:
## {date, comp, opp_short, us, them, battles, kos, dmg, rating}
static func form_of(uid: String) -> Array:
	var out: Array = (_form.get(uid, []) as Array).duplicate()
	out.sort_custom(func(a, b): return str(a["date"]) > str(b["date"]))
	return out


static func _replay_fixture(f: Dictionary) -> void:
	var home: Dictionary = GameState.club(f["home"])
	var away: Dictionary = GameState.club(f["away"])
	if home.is_empty() or away.is_empty():
		return
	var seed_v: int = GameState.career_seed + absi(str(f["id"]).hash()) % 1000000
	var ps := 0 if GameState.is_player_club(f["home"]) else 1
	var wins := [0, 0]
	var fixture_tally := {}   # uid -> {battles, kos, dmg, rating_sum}
	for i in 3:
		if wins[0] == 2 or wins[1] == 2:
			break
		var team_h := Season.pick_team(home)
		var team_a := Season.pick_team(away)
		if team_h.is_empty() or team_a.is_empty():
			return
		var eng := BattleEngine.new(team_h, team_a, seed_v + i * 7919)
		eng.run_to_end()
		var w := eng.winner()
		wins[maxi(w, 0)] += 1
		var mine: Array = team_h if ps == 0 else team_a
		var foes: Array = team_a if ps == 0 else team_h
		_parse_battle(eng.events, ps, mine, foes, w == ps, fixture_tally)

	var opp: Dictionary = away if ps == 0 else home
	for uid in fixture_tally:
		var ft: Dictionary = fixture_tally[uid]
		if not _form.has(uid):
			_form[uid] = []
		_form[uid].append({
			"date": f["date"], "comp": f["comp"],
			"opp_short": opp.get("short", "?"),
			"us": wins[ps], "them": wins[1 - ps],
			"battles": ft["battles"], "kos": ft["kos"], "dmg": ft["dmg"],
			"rating": float(ft["rating_sum"]) / maxf(float(ft["battles"]), 1.0),
		})


static func _parse_battle(events: Array, ps: int, mine: Array, foes: Array, won: bool,
		fixture_tally: Dictionary) -> void:
	var uid_of := {}
	for b in mine:
		if not uid_of.has(b["name"]):
			uid_of[b["name"]] = b["uid"]
	var foe_hp_total := 0
	for b in foes:
		foe_hp_total += int(b["stats"]["hp"])
	var foe_avg_hp := maxf(float(foe_hp_total) / maxf(foes.size(), 1.0), 1.0)

	var active := ["", ""]
	var tally := {}   # my battler name -> {dmg, taken, kos, faints}
	for e in events:
		match e["t"]:
			"switch":
				var s := int(e["side"])
				active[s] = e["to"]
				if s == ps and not tally.has(e["to"]):
					tally[e["to"]] = {"dmg": 0, "taken": 0, "kos": 0, "faints": 0}
			"damage", "confused_hit", "status_tick":
				var amount := int(e.get("amount", 0))
				var victim_side := int(e["side"])
				if victim_side == ps:
					if tally.has(e["pokemon"]):
						tally[e["pokemon"]]["taken"] += amount
				elif tally.has(active[ps]):
					tally[active[ps]]["dmg"] += amount
			"faint":
				if int(e["side"]) == ps:
					if tally.has(e["pokemon"]):
						tally[e["pokemon"]]["faints"] += 1
				elif tally.has(active[ps]):
					tally[active[ps]]["kos"] += 1

	for pname in tally:
		var t: Dictionary = tally[pname]
		var uid: String = uid_of.get(pname, "")
		if uid == "":
			continue
		if not _by_uid.has(uid):
			_by_uid[uid] = _blank()
		var agg: Dictionary = _by_uid[uid]
		agg["battles"] += 1
		if won:
			agg["wins"] += 1
		agg["kos"] += t["kos"]
		agg["dmg"] += t["dmg"]
		agg["taken"] += t["taken"]
		agg["faints"] += t["faints"]
		var rating: float = 6.0 + float(t["dmg"]) / foe_avg_hp * 0.9 \
			+ float(t["kos"]) * 0.55 - float(t["faints"]) * 0.6 \
			+ (0.35 if won else -0.25)
		var clamped := clampf(rating, 4.5, 10.0)
		agg["rating_sum"] += clamped
		if not fixture_tally.has(uid):
			fixture_tally[uid] = {"battles": 0, "kos": 0, "dmg": 0, "rating_sum": 0.0}
		var ft: Dictionary = fixture_tally[uid]
		ft["battles"] += 1
		ft["kos"] += t["kos"]
		ft["dmg"] += t["dmg"]
		ft["rating_sum"] += clamped
