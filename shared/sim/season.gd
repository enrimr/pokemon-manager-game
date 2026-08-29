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
	out.sort_custom(func(x, y):
		if x["points"] != y["points"]:
			return x["points"] > y["points"]
		var dx: int = x["bf"] - x["ba"]
		var dy: int = y["bf"] - y["ba"]
		if dx != dy:
			return dx > dy
		return x["bf"] > y["bf"])
	return out


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
