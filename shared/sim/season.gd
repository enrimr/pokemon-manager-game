class_name Season
extends RefCounted
## Fixture generation, calendar math, league table and instant match simulation.
##
## OWNERSHIP: shared core. The "competition" piece may extend fixture/table
## logic here; coordinate via GameState's API and do NOT change existing
## public signatures. Everyone else consumes this read-only.
##
## Fixture dict schema:
## { "id": "L001", "comp": "league"|"cup", "round": int, "date": "YYYY-MM-DD",
##   "home": club_id, "away": club_id, "played": bool,
##   "score_home": int, "score_away": int }
## League matches are decided by a best-of-3 of 6v6 battles (no draws).

const LEAGUE_ROUND_OFFSET := 7    # first league matchday: start + 7 days
const LEAGUE_ROUND_STEP := 7      # weekly
const CUP_FIRST_OFFSET := 11      # first cup midweek: start + 11 days
const CUP_ROUND_STEP := 28        # every 4 weeks


# ------------------------------------------------------------------ calendar

static func date_add(date_str: String, days: int) -> String:
	var parts := date_str.split("-")
	var dict := {"year": int(parts[0]), "month": int(parts[1]), "day": int(parts[2]),
		"hour": 12, "minute": 0, "second": 0}
	var unix := Time.get_unix_time_from_datetime_dict(dict)
	unix += days * 86400
	var d := Time.get_datetime_dict_from_unix_time(unix)
	return "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]


## ISO date strings compare correctly with plain string comparison.
static func date_before(a: String, b: String) -> bool:
	return a < b


static func pretty_date(date_str: String) -> String:
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var parts := date_str.split("-")
	return "%d %s %s" % [int(parts[2]), months[int(parts[1]) - 1], parts[0]]


# ------------------------------------------------------------------ fixtures

## Double round-robin via the circle method. Returns Array of fixture dicts.
static func make_league_fixtures(club_ids: Array, start_date: String) -> Array:
	var ids := club_ids.duplicate()
	var n := ids.size()
	assert(n % 2 == 0)
	var rounds: Array = []
	var rot := ids.slice(1)
	for r in n - 1:
		var pairs: Array = []
		var left: Array = [ids[0]] + rot.slice(0, (n / 2) - 1)
		var right: Array = rot.slice((n / 2) - 1)
		right.reverse()
		for i in n / 2:
			# alternate home/away so the fixed team isn't always home
			if r % 2 == 0:
				pairs.append([left[i], right[i]])
			else:
				pairs.append([right[i], left[i]])
		rounds.append(pairs)
		rot.push_front(rot.pop_back())
	# second half: mirrored
	var second: Array = []
	for pairs in rounds:
		var mirrored: Array = []
		for p in pairs:
			mirrored.append([p[1], p[0]])
		second.append(mirrored)
	rounds += second

	var fixtures: Array = []
	var idx := 0
	for r in rounds.size():
		var date := date_add(start_date, LEAGUE_ROUND_OFFSET + r * LEAGUE_ROUND_STEP)
		for p in rounds[r]:
			idx += 1
			fixtures.append({
				"id": "L%03d" % idx, "comp": "league", "round": r + 1, "date": date,
				"home": p[0], "away": p[1], "played": false,
				"score_home": 0, "score_away": 0,
			})
	return fixtures


## One knockout cup round pairing the given clubs (shuffled with seed).
static func make_cup_round(club_ids: Array, round_no: int, date: String, shuffle_seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = shuffle_seed
	var pool := club_ids.duplicate()
	# Fisher-Yates with seeded rng
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	var fixtures: Array = []
	for i in range(0, pool.size() - 1, 2):
		fixtures.append({
			"id": "C%d%02d" % [round_no, i / 2 + 1], "comp": "cup", "round": round_no,
			"date": date, "home": pool[i], "away": pool[i + 1], "played": false,
			"score_home": 0, "score_away": 0,
		})
	return fixtures


static func cup_round_date(start_date: String, round_no: int) -> String:
	return date_add(start_date, CUP_FIRST_OFFSET + (round_no - 1) * CUP_ROUND_STEP)


static func cup_round_name(round_no: int) -> String:
	match round_no:
		1: return "First Round"
		2: return "Quarter-Final"
		3: return "Semi-Final"
		4: return "Final"
	return "Round %d" % round_no


# ------------------------------------------------------------------ table

## League table rows sorted by points, battle difference, battles for.
## Row: {club_id, played, won, lost, bf, ba, points}
static func compute_table(club_ids: Array, fixtures: Array) -> Array:
	var rows := {}
	for id in club_ids:
		rows[id] = {"club_id": id, "played": 0, "won": 0, "lost": 0, "bf": 0, "ba": 0, "points": 0}
	for f in fixtures:
		if f["comp"] != "league" or not f["played"]:
			continue
		var h: Dictionary = rows[f["home"]]
		var a: Dictionary = rows[f["away"]]
		h["played"] += 1
		a["played"] += 1
		h["bf"] += f["score_home"]
		h["ba"] += f["score_away"]
		a["bf"] += f["score_away"]
		a["ba"] += f["score_home"]
		if f["score_home"] > f["score_away"]:
			h["won"] += 1
			h["points"] += 3
			a["lost"] += 1
		else:
			a["won"] += 1
			a["points"] += 3
			h["lost"] += 1
	var out: Array = rows.values()
	_sort_table_rows(out)
	return out


static func _sort_table_rows(out: Array) -> void:
	# Final alphabetical tiebreak keeps the order deterministic — Godot's
	# sort_custom is unstable, so without it fully tied rows (e.g. everyone
	# on 0 points pre-season) shuffle between calls.
	out.sort_custom(func(x, y):
		if x["points"] != y["points"]:
			return x["points"] > y["points"]
		var dx: int = x["bf"] - x["ba"]
		var dy: int = y["bf"] - y["ba"]
		if dx != dy:
			return dx > dy
		if x["bf"] != y["bf"]:
			return x["bf"] > y["bf"]
		return _club_sort_name(str(x["club_id"])) < _club_sort_name(str(y["club_id"])))


static func _club_sort_name(club_id: String) -> String:
	var c: Dictionary = GameState.club(club_id)
	return str(c.get("name", club_id))


# ------------------------------------------------------------------ match sim

## Pick the best (up to) 6 battlers from a club squad, by level then condition.
static func pick_team(club: Dictionary) -> Array:
	var squad: Array = club["squad"].duplicate()
	squad.sort_custom(func(a, b):
		if int(a["level"]) != int(b["level"]):
			return int(a["level"]) > int(b["level"])
		return int(a.get("condition", 100)) > int(b.get("condition", 100)))
	var team: Array = []
	for inst in squad.slice(0, 6):
		var b: Dictionary = DataStore.make_battler(inst)
		if not b.is_empty():
			team.append(b)
	return team


## Instant fixture result: best-of-3 6v6 battles. Returns
## {score_home, score_away, battles: [winner_side, ...], turns: [...]}
static func simulate_fixture(home_club: Dictionary, away_club: Dictionary, match_seed: int) -> Dictionary:
	var wins := [0, 0]
	var battles: Array = []
	var turns: Array = []
	for i in 3:
		if wins[0] == 2 or wins[1] == 2:
			break
		var team_h := pick_team(home_club)
		var team_a := pick_team(away_club)
		if team_h.is_empty() or team_a.is_empty():
			push_error("simulate_fixture: empty team for %s vs %s" % [home_club["name"], away_club["name"]])
			return {"score_home": 2, "score_away": 0, "battles": [], "turns": []}
		var eng := BattleEngine.new(team_h, team_a, match_seed + i * 7919)
		eng.run_to_end()
		var w := eng.winner()
		wins[w] += 1
		battles.append(w)
		turns.append(eng.turn)
	return {"score_home": wins[0], "score_away": wins[1], "battles": battles, "turns": turns}


# =================================================================== competition extensions
# Additive helpers owned by the "competition" piece: calendar deltas, table
# history/form, deterministic fixture replays with per-Pokemon stats, and
# season-wide leader aggregation. No existing signatures changed.

## Whole days from date a to date b (positive if b is later).
static func days_between(a: String, b: String) -> int:
	var pa := a.split("-")
	var pb := b.split("-")
	var ua := Time.get_unix_time_from_datetime_dict({"year": int(pa[0]), "month": int(pa[1]),
		"day": int(pa[2]), "hour": 12, "minute": 0, "second": 0})
	var ub := Time.get_unix_time_from_datetime_dict({"year": int(pb[0]), "month": int(pb[1]),
		"day": int(pb[2]), "hour": 12, "minute": 0, "second": 0})
	return int(round(float(ub - ua) / 86400.0))


## Highest league round in the fixture list.
static func total_league_rounds(fixtures: Array) -> int:
	var r := 0
	for f in fixtures:
		if f["comp"] == "league":
			r = maxi(r, int(f["round"]))
	return r


## Highest league round in which every fixture has been played (0 if none).
static func latest_completed_league_round(fixtures: Array) -> int:
	var unplayed_min := 999
	var played_max := 0
	for f in fixtures:
		if f["comp"] != "league":
			continue
		if f["played"]:
			played_max = maxi(played_max, int(f["round"]))
		else:
			unplayed_min = mini(unplayed_min, int(f["round"]))
	return mini(played_max, unplayed_min - 1)


## Lowest league round that still has an unplayed fixture (season round "now").
static func current_league_round(fixtures: Array) -> int:
	var lo := 999
	var hi := 1
	for f in fixtures:
		if f["comp"] != "league":
			continue
		hi = maxi(hi, int(f["round"]))
		if not f["played"]:
			lo = mini(lo, int(f["round"]))
	return mini(lo, hi)


## Table considering only league fixtures up to and including round_no.
static func compute_table_through_round(club_ids: Array, fixtures: Array, round_no: int) -> Array:
	var subset := fixtures.filter(func(f):
		return f["comp"] == "league" and int(f["round"]) <= round_no)
	return compute_table(club_ids, subset)


## FM-style league table split. mode: "overall" | "home" | "away" | "form".
## "home"/"away" count only each club's home/away league matches; "form"
## counts only each club's most recent `form_count` played league matches.
## Row schema identical to compute_table.
static func compute_table_variant(club_ids: Array, fixtures: Array, mode: String,
		form_count: int = 5) -> Array:
	if mode == "overall":
		return compute_table(club_ids, fixtures)
	var rows := {}
	for id in club_ids:
		rows[id] = {"club_id": id, "played": 0, "won": 0, "lost": 0, "bf": 0, "ba": 0, "points": 0}
	var played: Array = fixtures.filter(func(f):
		return f["comp"] == "league" and f["played"])
	if mode == "form":
		played.sort_custom(func(a, b): return str(a["date"]) < str(b["date"]))
		for id in club_ids:
			var ours: Array = played.filter(func(f): return f["home"] == id or f["away"] == id)
			for f in ours.slice(maxi(0, ours.size() - form_count)):
				_credit_result(rows[id], f, f["home"] == id)
	else:
		for f in played:
			var cid: String = str(f["home"] if mode == "home" else f["away"])
			if rows.has(cid):
				_credit_result(rows[cid], f, mode == "home")
	var out: Array = rows.values()
	_sort_table_rows(out)
	return out


## Add one played fixture to a single club's table row (as home or away side).
static func _credit_result(row: Dictionary, f: Dictionary, as_home: bool) -> void:
	var us := int(f["score_home"] if as_home else f["score_away"])
	var them := int(f["score_away"] if as_home else f["score_home"])
	row["played"] += 1
	row["bf"] += us
	row["ba"] += them
	if us > them:
		row["won"] += 1
		row["points"] += 3
	else:
		row["lost"] += 1


## club_id -> position (1-based) for a table array from compute_table*.
static func table_positions(table: Array) -> Dictionary:
	var out := {}
	for i in table.size():
		out[table[i]["club_id"]] = i + 1
	return out


## Last `count` played league results for a club, oldest first: "W"/"L".
static func club_form(club_id: String, fixtures: Array, count: int = 5) -> Array:
	var played := fixtures.filter(func(f):
		return f["comp"] == "league" and f["played"] and (f["home"] == club_id or f["away"] == club_id))
	played.sort_custom(func(a, b): return a["date"] < b["date"])
	var out: Array = []
	for f in played.slice(maxi(0, played.size() - count)):
		var us: int = f["score_home"] if f["home"] == club_id else f["score_away"]
		var them: int = f["score_away"] if f["home"] == club_id else f["score_home"]
		out.append("W" if us > them else "L")
	return out


## Deterministic per-fixture seed — mirrors GameState._play_fixture.
static func fixture_seed(f: Dictionary, career_seed: int) -> int:
	return career_seed + absi(str(f["id"]).hash()) % 1000000


# ------------------------------------------------------- fixture replay detail

static var _detail_cache: Dictionary = {}    # fixture id -> detail dict
static var _detail_career: String = ""


static func _career_key() -> String:
	return "%d:%s" % [GameState.career_seed, GameState.season_start]


static func _check_career_cache() -> void:
	var key := _career_key()
	if key != _detail_career:
		_detail_career = key
		_detail_cache.clear()
		_agg_processed.clear()
		_agg_players.clear()
		_agg_by_comp.clear()
		_club_stats_cache.clear()


## Replays a played fixture with the real engine (same seed formula GameState
## uses, so identical outcome) and returns per-Pokemon match stats. Cached.
## Returns {} for unplayed fixtures.
## { "score_home", "score_away",
##   "battles": [ {"winner": 0|1, "turns": int} ],
##   "players": { uid: {name, species, side, battles, wins, kos, dmg, taken,
##                      faints, rating_sum} } }
static func fixture_detail(f: Dictionary) -> Dictionary:
	if not f.get("played", false):
		return {}
	_check_career_cache()
	var fid: String = str(f["id"])
	if _detail_cache.has(fid):
		return _detail_cache[fid]
	# Fixtures resolved outside the neutral instant sim (interactive matches,
	# tactics-plan sims) record their REAL detail on the fixture — prefer it,
	# otherwise the replay below could contradict the recorded scoreline.
	var stored: Variant = f.get("detail")
	if stored is Dictionary and stored.has("players") and stored.has("battles"):
		_detail_cache[fid] = stored
		return stored
	var home: Dictionary = GameState.club(f["home"])
	var away: Dictionary = GameState.club(f["away"])
	if home.is_empty() or away.is_empty():
		return {}
	var seed_v := fixture_seed(f, GameState.career_seed)
	var wins := [0, 0]
	var battles: Array = []
	var players: Dictionary = {}
	for i in 3:
		if wins[0] == 2 or wins[1] == 2:
			break
		var team_h := pick_team(home)
		var team_a := pick_team(away)
		if team_h.is_empty() or team_a.is_empty():
			return {}
		var eng := BattleEngine.new(team_h, team_a, seed_v + i * 7919)
		eng.run_to_end()
		var w := maxi(eng.winner(), 0)
		wins[w] += 1
		battles.append({"winner": w, "turns": eng.turn})
		_tally_battle(eng.events, [team_h, team_a], w, players)
	var detail := {"score_home": wins[0], "score_away": wins[1],
		"battles": battles, "players": players}
	_detail_cache[fid] = detail
	return detail


## Parse one battle's event log into per-uid stats, merged into `out`.
static func _tally_battle(events: Array, teams: Array, winner: int, out: Dictionary) -> void:
	# name -> uid per side, plus per-side total max hp for rating context
	var uid_of := [{}, {}]
	var team_hp := [0.0, 0.0]
	for side in 2:
		for b in teams[side]:
			uid_of[side][b["name"]] = b["uid"]
			team_hp[side] += float(b["stats"]["hp"])

	var battle := {}   # uid -> {dmg, taken, kos, fainted, in_battle}
	var ensure := func(side: int, pname: String) -> Dictionary:
		var uid: String = uid_of[side].get(pname, "")
		if uid == "":
			return {}
		if not battle.has(uid):
			var src: Dictionary = {}
			for b in teams[side]:
				if b["uid"] == uid:
					src = b
					break
			battle[uid] = {"side": side, "name": src.get("name", pname),
				"species": src.get("species", pname), "level": int(src.get("level", 0)),
				"dmg": 0, "taken": 0, "kos": 0, "fainted": false, "in_battle": false}
		return battle[uid]

	var last_hitter := [{}, {}]   # victim side -> {"name":..,"side":..}
	for e in events:
		match e["t"]:
			"switch":
				var s: Dictionary = ensure.call(int(e["side"]), str(e["to"]))
				if not s.is_empty():
					s["in_battle"] = true
			"damage":
				var vs := int(e["side"])
				var victim: Dictionary = ensure.call(vs, str(e["pokemon"]))
				if not victim.is_empty():
					victim["taken"] += int(e.get("amount", 0))
					victim["in_battle"] = true
				if e.has("by") and not e.get("recoil", false):
					var atk: Dictionary = ensure.call(int(e["by_side"]), str(e["by"]))
					if not atk.is_empty():
						atk["dmg"] += int(e.get("amount", 0))
					last_hitter[vs] = {"name": str(e["by"]), "side": int(e["by_side"])}
			"status_tick":
				var vict: Dictionary = ensure.call(int(e["side"]), str(e["pokemon"]))
				if not vict.is_empty():
					vict["taken"] += int(e.get("amount", 0))
			"faint":
				var fs := int(e["side"])
				var fb: Dictionary = ensure.call(fs, str(e["pokemon"]))
				if not fb.is_empty():
					fb["fainted"] = true
				var lh: Dictionary = last_hitter[fs]
				if not lh.is_empty() and int(lh["side"]) != fs:
					var koer: Dictionary = ensure.call(int(lh["side"]), str(lh["name"]))
					if not koer.is_empty():
						koer["kos"] += 1

	for uid in battle:
		var s: Dictionary = battle[uid]
		if not s["in_battle"]:
			continue
		var side := int(s["side"])
		var won := side == winner
		var opp_hp: float = maxf(team_hp[1 - side], 1.0)
		var rating: float = 6.0 + 3.4 * float(s["dmg"]) / opp_hp + 0.5 * float(s["kos"])
		rating += 0.4 if won else -0.25
		if s["fainted"]:
			rating -= 0.45
		rating = clampf(rating, 4.5, 10.0)
		if not out.has(uid):
			out[uid] = {"name": s["name"], "species": s["species"], "level": s["level"],
				"side": side, "battles": 0, "wins": 0, "kos": 0, "dmg": 0, "taken": 0,
				"faints": 0, "rating_sum": 0.0}
		var agg: Dictionary = out[uid]
		agg["battles"] += 1
		agg["wins"] += 1 if won else 0
		agg["kos"] += s["kos"]
		agg["dmg"] += s["dmg"]
		agg["taken"] += s["taken"]
		agg["faints"] += 1 if s["fainted"] else 0
		agg["rating_sum"] += rating


# ------------------------------------------------------- season-wide leaders

static var _agg_processed: Dictionary = {}   # fixture id -> true
static var _agg_players: Dictionary = {}     # uid -> aggregate (league + cup)
static var _agg_by_comp: Dictionary = {}     # "league"/"cup" -> {uid -> aggregate}


## Aggregate per-Pokemon stats across every played fixture (league + cup).
## Incremental: only newly played fixtures are replayed on each call.
## uid -> {name, species, level, battles, wins, kos, dmg, taken, faints, rating_sum}
static func season_player_stats(fixtures: Array) -> Dictionary:
	_check_career_cache()
	for f in fixtures:
		if not f.get("played", false):
			continue
		var fid: String = str(f["id"])
		if _agg_processed.has(fid):
			continue
		_agg_processed[fid] = true
		var detail := fixture_detail(f)
		if detail.is_empty():
			continue
		var comp: String = str(f["comp"])
		if not _agg_by_comp.has(comp):
			_agg_by_comp[comp] = {}
		for uid in detail["players"]:
			var p: Dictionary = detail["players"][uid]
			_merge_player_stats(_agg_players, str(uid), p)
			_merge_player_stats(_agg_by_comp[comp], str(uid), p)
	return _agg_players


## Same aggregate restricted to one competition: comp "league" | "cup" | "all".
static func season_player_stats_comp(fixtures: Array, comp: String) -> Dictionary:
	season_player_stats(fixtures)   # ensure incremental aggregation is current
	if comp == "all":
		return _agg_players
	return _agg_by_comp.get(comp, {})


static func _merge_player_stats(target: Dictionary, uid: String, p: Dictionary) -> void:
	if not target.has(uid):
		target[uid] = {"name": p["name"], "species": p["species"],
			"level": p["level"], "battles": 0, "wins": 0, "kos": 0, "dmg": 0,
			"taken": 0, "faints": 0, "rating_sum": 0.0}
	var agg: Dictionary = target[uid]
	for k in ["battles", "wins", "kos", "dmg", "taken", "faints"]:
		agg[k] += p[k]
	agg["rating_sum"] += p["rating_sum"]
	agg["level"] = maxi(int(agg["level"]), int(p["level"]))


## Match-by-match log for one squad member across a club's played fixtures,
## oldest first (drives the Pokémon profile's match history). Each entry:
## {fid, date, comp, round, opp, we_home, us, them, won, battles, kos, dmg,
##  taken, fainted, rating}. Uses the cached deterministic replays.
static func pokemon_match_log(uid: String, club_id: String, fixtures: Array) -> Array:
	var out: Array = []
	var ours := fixtures.filter(func(f):
		return f.get("played", false) and (f["home"] == club_id or f["away"] == club_id))
	ours.sort_custom(func(a, b): return a["date"] < b["date"])
	for f in ours:
		var detail := fixture_detail(f)
		if detail.is_empty() or not detail["players"].has(uid):
			continue
		var p: Dictionary = detail["players"][uid]
		var we_home: bool = f["home"] == club_id
		var us := int(f["score_home"]) if we_home else int(f["score_away"])
		var them := int(f["score_away"]) if we_home else int(f["score_home"])
		out.append({
			"fid": str(f["id"]), "date": str(f["date"]), "comp": str(f["comp"]),
			"round": int(f["round"]), "opp": str(f["away"] if we_home else f["home"]),
			"we_home": we_home, "us": us, "them": them, "won": us > them,
			"battles": int(p["battles"]), "kos": int(p["kos"]), "dmg": int(p["dmg"]),
			"taken": int(p["taken"]), "fainted": int(p["faints"]) > 0,
			"rating": float(p["rating_sum"]) / maxi(int(p["battles"]), 1),
		})
	return out


## Per-club battle record from fixture scores (league + cup).
## club_id -> {matches, mw, ml, bw, bl}
static func club_battle_stats(club_ids: Array, fixtures: Array) -> Dictionary:
	var out := {}
	for id in club_ids:
		out[id] = {"matches": 0, "mw": 0, "ml": 0, "bw": 0, "bl": 0}
	for f in fixtures:
		if not f.get("played", false):
			continue
		if not out.has(f["home"]) or not out.has(f["away"]):
			continue
		var h: Dictionary = out[f["home"]]
		var a: Dictionary = out[f["away"]]
		h["matches"] += 1
		a["matches"] += 1
		h["bw"] += int(f["score_home"])
		h["bl"] += int(f["score_away"])
		a["bw"] += int(f["score_away"])
		a["bl"] += int(f["score_home"])
		if int(f["score_home"]) > int(f["score_away"]):
			h["mw"] += 1
			a["ml"] += 1
		else:
			a["mw"] += 1
			h["ml"] += 1
	return out


# ------------------------------------------------------- club season stats
# Team-level Stats Centre aggregates (competition piece). Combines fixture
# scores (records, splits, streaks) with the deterministic replay details
# (KOs, damage, ratings, turns). Cached per (comp, played-fixture-count).

static var _club_stats_cache: Dictionary = {}   # "comp|n_played" -> {club_id: row}


## Full per-club season statistics. comp: "all" | "league" | "cup".
## club_id -> {
##   matches, mw, ml, pts,                    match record (pts = league only)
##   hm, hw, hl, am, aw, al,                  home / away match splits
##   bw, bl, hbw, hbl, abw, abl,              battle (leg) splits by venue
##   legs, kos, faints, dmg, taken, turns,    replay aggregates (legs = battles played)
##   rating_sum, rating_apps,                 per-Pokemon-appearance match ratings
##   results: ["W","L",...] oldest first,
##   streak: signed current run (+n = won last n, -n = lost last n),
##   best_w, worst_l:  longest win run / longest losing run this season }
static func season_club_stats(club_ids: Array, fixtures: Array, comp: String = "all") -> Dictionary:
	_check_career_cache()
	var played: Array = fixtures.filter(func(f):
		return f.get("played", false) and (comp == "all" or str(f["comp"]) == comp))
	var key := "%s|%d" % [comp, played.size()]
	if _club_stats_cache.has(key):
		return _club_stats_cache[key]
	played.sort_custom(func(a, b):
		if a["date"] != b["date"]:
			return str(a["date"]) < str(b["date"])
		return str(a["id"]) < str(b["id"]))

	var out := {}
	for id in club_ids:
		out[id] = {
			"matches": 0, "mw": 0, "ml": 0, "pts": 0,
			"hm": 0, "hw": 0, "hl": 0, "am": 0, "aw": 0, "al": 0,
			"bw": 0, "bl": 0, "hbw": 0, "hbl": 0, "abw": 0, "abl": 0,
			"legs": 0, "kos": 0, "faints": 0, "dmg": 0, "taken": 0, "turns": 0,
			"rating_sum": 0.0, "rating_apps": 0,
			"results": [], "streak": 0, "best_w": 0, "worst_l": 0,
		}

	for f in played:
		if not out.has(f["home"]) or not out.has(f["away"]):
			continue
		var h: Dictionary = out[f["home"]]
		var a: Dictionary = out[f["away"]]
		var sh := int(f["score_home"])
		var sa := int(f["score_away"])
		h["matches"] += 1
		a["matches"] += 1
		h["hm"] += 1
		a["am"] += 1
		h["bw"] += sh
		h["bl"] += sa
		h["hbw"] += sh
		h["hbl"] += sa
		a["bw"] += sa
		a["bl"] += sh
		a["abw"] += sa
		a["abl"] += sh
		var home_won := sh > sa
		if home_won:
			h["mw"] += 1
			h["hw"] += 1
			a["ml"] += 1
			a["al"] += 1
		else:
			a["mw"] += 1
			a["aw"] += 1
			h["ml"] += 1
			h["hl"] += 1
		if str(f["comp"]) == "league":
			var winner_row: Dictionary = h if home_won else a
			winner_row["pts"] += 3
		h["results"].append("W" if home_won else "L")
		a["results"].append("L" if home_won else "W")

		var detail := fixture_detail(f)
		if not detail.is_empty():
			for uid in detail["players"]:
				var p: Dictionary = detail["players"][uid]
				var row: Dictionary = h if int(p["side"]) == 0 else a
				row["kos"] += int(p["kos"])
				row["faints"] += int(p["faints"])
				row["dmg"] += int(p["dmg"])
				row["taken"] += int(p["taken"])
				row["rating_sum"] += float(p["rating_sum"])
				row["rating_apps"] += int(p["battles"])
			for b in detail["battles"]:
				h["legs"] += 1
				a["legs"] += 1
				h["turns"] += int(b["turns"])
				a["turns"] += int(b["turns"])

	for id in out:
		_compute_streaks(out[id])
	if _club_stats_cache.size() > 6:
		_club_stats_cache.clear()
	_club_stats_cache[key] = out
	return out


## Fill streak / best_w / worst_l from the chronological results list.
static func _compute_streaks(row: Dictionary) -> void:
	var run := 0        # signed running streak
	var best_w := 0
	var worst_l := 0
	for r in row["results"]:
		if r == "W":
			run = run + 1 if run > 0 else 1
			best_w = maxi(best_w, run)
		else:
			run = run - 1 if run < 0 else -1
			worst_l = maxi(worst_l, -run)
	row["streak"] = run
	row["best_w"] = best_w
	row["worst_l"] = worst_l


## Winner club id of a played fixture ("" if unplayed).
static func fixture_winner(f: Dictionary) -> String:
	if not f.get("played", false):
		return ""
	return f["home"] if int(f["score_home"]) > int(f["score_away"]) else f["away"]
