## Season flow service (drop-in sim service, see docs/ARCHITECTURE.md).
##
## Owns everything that happens AFTER matchday 30 — the piece that makes the
## table's coloured zones real and rolls the world into the next season:
##
##   Championship Series  once BOTH championships complete, positions 1-4 of
##                        each league enter a seeded cross-league knockout
##                        (QF -> SF -> Final, weekly, comp == "playoff"):
##                        K1vJ4, J2vK3 | J1vK4, K2vJ3 — champions can only
##                        meet in the Final, which crowns the INDIGO CHAMPION.
##   Danger Zone (14-16)  board consequences at the ceremony: reputation -1,
##                        transfer budget cut 25%, sponsor pullback 3% of the
##                        bank; the player additionally gets a board ultimatum
##                        (tracked and judged NEXT season) and their star
##                        Pokémon demands an exit (morale hit, exit_request).
##   Awards + history     end-of-season ceremony: league champions honoured
##                        (rep +1), Pokémon of the Season + Best Developer
##                        from real match ratings, a season review mail, and
##                        a permanent world.meta.history record (History tab).
##   Rollover             7 days after the Final, GameState.start_new_season()
##                        — fresh fixtures for both leagues + cup, ages tick,
##                        season counter up; squads/finances/development carry.
##
## Deterministic end to end: seeding comes from final tables, tie results from
## the per-fixture seeds, awards from recorded match details. State (phase,
## ultimatum, rollover date) rides world.meta.services.season_flow.
extends RefCounted
class_name SeasonFlowService

## Latest service instance (set on career start / load). UI pieces read this.
static var instance: SeasonFlowService = null

const TOP_N := 4                     ## table positions that enter the Series
const DANGER_FROM := 14              ## Danger Zone: positions 14..16
const ROLLOVER_DELAY_DAYS := 7       ## Final -> new-season preseason
const POS_MIN_BATTLES := 8           ## Pokémon of the Season eligibility
const BREAKOUT_MAX_AGE := 60         ## Best Developer: under 5 years old
const BREAKOUT_MIN_BATTLES := 5
const ULTIMATUM_TARGET := 10         ## "finish 10th or better" board demand

var phase := "regular"               # regular | playoff | offseason
var rollover_date := ""              # set when the phase turns "offseason"
var ultimatum := {}                  # {"season": int, "target": int} on the player
var last_awards := {}                # latest ceremony (convenience copy)


func service_id() -> String:
	return "season_flow"


func save_state() -> Dictionary:
	return {"phase": phase, "rollover_date": rollover_date,
		"ultimatum": ultimatum, "last_awards": last_awards}


func load_state(state: Dictionary) -> void:
	phase = str(state.get("phase", "regular"))
	rollover_date = str(state.get("rollover_date", ""))
	ultimatum = state.get("ultimatum", {}) if typeof(state.get("ultimatum")) == TYPE_DICTIONARY else {}
	if not ultimatum.is_empty():
		ultimatum = {"season": int(ultimatum.get("season", 0)), "target": int(ultimatum.get("target", ULTIMATUM_TARGET))}
	last_awards = state.get("last_awards", {}) if typeof(state.get("last_awards")) == TYPE_DICTIONARY else {}


func on_career_started(gs) -> void:
	instance = self
	_reconcile_phase(gs)


## Derive the phase from the fixture list (covers pre-service saves and any
## state drift): playoff fixtures pending -> playoff; final played but not
## rolled -> offseason; otherwise the regular season.
func _reconcile_phase(gs) -> void:
	var po: Array = Season.playoff_fixtures(gs.fixtures)
	if po.is_empty():
		if phase != "regular":
			phase = "regular"
			rollover_date = ""
		return
	var final_done := _round_fixtures(po, 3).any(func(f): return f["played"])
	if final_done:
		phase = "offseason"
		if rollover_date == "" or rollover_date < gs.current_date:
			rollover_date = Season.date_add(gs.current_date, ROLLOVER_DELAY_DAYS)
	else:
		phase = "playoff"


func on_day(gs, date: String) -> void:
	match phase:
		"regular":
			if Season.league_complete(gs.fixtures):
				_start_playoff(gs)
		"playoff":
			_advance_playoff(gs)
		"offseason":
			if date >= rollover_date:
				rollover_date = ""
				phase = "regular"
				gs.start_new_season()


# ------------------------------------------------------------------ queries (UI)

## Top-N table rows of a league as club ids (final seeding order).
func league_top(gs, league_id: String, n: int = TOP_N) -> Array:
	var out: Array = []
	var table: Array = gs.league_table(league_id)
	for i in mini(n, table.size()):
		out.append(str(table[i]["club_id"]))
	return out


## Seeded QF pairings [[home, away], ...] from two top-4 lists. Champions are
## kept in opposite halves of the bracket: A1vB4, B2vA3 | B1vA4, A2vB3.
static func seed_pairs(a: Array, b: Array) -> Array:
	if a.size() >= 4 and b.size() >= 4:
		return [[a[0], b[3]], [b[1], a[2]], [b[0], a[3]], [a[1], b[2]]]
	# single-league fallback: top 8, 1v8 4v5 | 2v7 3v6
	var pool: Array = a + b
	if pool.size() >= 8:
		return [[pool[0], pool[7]], [pool[3], pool[4]], [pool[1], pool[6]], [pool[2], pool[5]]]
	return []


# ------------------------------------------------------------------ playoff

func _start_playoff(gs) -> void:
	var lgs: Array = gs.leagues()
	var a := league_top(gs, str(lgs[0]["id"]))
	var b := league_top(gs, str(lgs[1]["id"])) if lgs.size() > 1 else []
	var pairs := seed_pairs(a, b)
	if pairs.is_empty():
		return
	var date: String = Season.date_add(gs.current_date, Season.PLAYOFF_ROUND_STEP)
	gs.fixtures += Season.make_playoff_round(pairs, 1, date, gs.season_id_prefix() + "P")
	phase = "playoff"

	var qualified: Array = []
	for p in pairs:
		qualified += [str(p[0]), str(p[1])]
	var names := ", ".join(qualified.map(func(cid): return str(gs.club(cid).get("name", cid))))
	var player_in: bool = qualified.has(str(gs.world["meta"]["player_club_id"]))
	gs.add_inbox_message(gs.current_date, "%s: the top four of each league are in" % Season.PLAYOFF_NAME,
		("The championships are decided — now the %s begins. The top four of the %s "
		+ "and the %s meet in a seeded cross-league knockout for the %s title. "
		+ "Quarter-finals on %s: %s.%s") % [
		Season.PLAYOFF_NAME, gs.league_name(str(lgs[0]["id"])),
		gs.league_name(str(lgs[1]["id"])) if lgs.size() > 1 else "",
		Season.INDIGO_TITLE, Season.pretty_date(date), names,
		"\n\nWE ARE IN — the board is delighted. Go and win it." if player_in else ""])
	if player_in and not gs.inbox.is_empty():
		gs.inbox[0]["urgent"] = true


func _round_fixtures(po: Array, round_no: int) -> Array:
	return po.filter(func(f): return int(f["round"]) == round_no)


func _advance_playoff(gs) -> void:
	var po: Array = Season.playoff_fixtures(gs.fixtures)
	if po.is_empty():
		phase = "regular"
		return
	var max_round := 0
	for f in po:
		max_round = maxi(max_round, int(f["round"]))
	var current := _round_fixtures(po, max_round)
	if current.any(func(f): return not f["played"]):
		return
	if max_round >= 3:
		_end_of_season(gs, current[0])
		return
	# next round: winners in tie order, adjacent ties feed the same tie
	current.sort_custom(func(x, y): return str(x["id"]) < str(y["id"]))
	var winners: Array = current.map(func(f): return Season.fixture_winner(f))
	var pairs: Array = []
	for i in range(0, winners.size() - 1, 2):
		pairs.append([winners[i], winners[i + 1]])
	var next_round := max_round + 1
	var date: String = Season.date_add(str(current[0]["date"]), Season.PLAYOFF_ROUND_STEP)
	if date <= gs.current_date:
		date = Season.date_add(gs.current_date, Season.PLAYOFF_ROUND_STEP)
	gs.fixtures += Season.make_playoff_round(pairs, next_round, date, gs.season_id_prefix() + "P")
	var names := ", ".join(winners.map(func(cid): return str(gs.club(cid).get("name", cid))))
	gs.add_inbox_message(gs.current_date, "%s: %s line-up set" % [
		Season.PLAYOFF_NAME, Season.playoff_round_name(next_round)],
		"Through to the %s on %s: %s." % [
		Season.playoff_round_name(next_round), Season.pretty_date(date), names])
	if winners.has(str(gs.world["meta"]["player_club_id"])) and not gs.inbox.is_empty():
		gs.inbox[0]["urgent"] = true


# ------------------------------------------------------------------ ceremony

func _end_of_season(gs, final_f: Dictionary) -> void:
	var champion := Season.fixture_winner(final_f)
	var runner_up: String = str(final_f["away"] if champion == str(final_f["home"]) else final_f["home"])
	var awards := compute_awards(gs)
	last_awards = awards

	# honours: league champions + the Indigo Champion gain standing
	for lg in gs.leagues():
		var t: Array = gs.league_table(str(lg["id"]))
		if not t.is_empty():
			_bump_reputation(gs, str(t[0]["club_id"]), 1)
	_bump_reputation(gs, champion, 1)

	_judge_previous_ultimatum(gs)
	_apply_danger_zone(gs)
	var entry := _make_history_entry(gs, champion, runner_up, awards)
	gs.add_history_entry(entry)
	_send_awards_mail(gs, entry)
	_send_season_review(gs, entry)

	rollover_date = Season.date_add(gs.current_date, ROLLOVER_DELAY_DAYS)
	phase = "offseason"
	# the calendar jumps to the NEW preseason when the rollover fires — quote
	# the date the player will actually land on, not the rollover tick itself
	var new_preseason: String = Season.date_add(str(gs.season_start), 364)
	gs.add_inbox_message(gs.current_date, "Off-season: Season %d starts %s" % [
		gs.season_no() + 1, Season.pretty_date(new_preseason)],
		("The season is complete. The squad gets a break — pressing Continue past %s "
		+ "fast-forwards to preseason on %s, with fresh fixtures for both championships "
		+ "and a new %s draw. Squads, finances and development all carry over.") % [
		Season.pretty_date(rollover_date), Season.pretty_date(new_preseason), gs.cup_name()])


func _bump_reputation(gs, club_id: String, delta: int) -> void:
	var c: Dictionary = gs.club(club_id)
	if not c.is_empty():
		c["reputation"] = clampi(int(c["reputation"]) + delta, 1, 20)


## Pure + deterministic (reads recorded match details only) — sim_check calls
## this twice and asserts identical output.
func compute_awards(gs) -> Dictionary:
	var stats: Dictionary = Season.season_player_stats(gs.fixtures)
	var owners := _owner_index(gs)
	var pos := _pick_award(stats, owners, POS_MIN_BATTLES, 0)
	if pos.is_empty():
		pos = _pick_award(stats, owners, 1, 0)
	var breakout := _pick_award(stats, owners, BREAKOUT_MIN_BATTLES, BREAKOUT_MAX_AGE)
	if breakout.is_empty():
		breakout = _pick_award(stats, owners, 1, BREAKOUT_MAX_AGE)
	return {"pokemon_of_season": pos, "best_developer": breakout}


## uid -> {club_id, inst} across every squad (award winners need an owner).
func _owner_index(gs) -> Dictionary:
	var out := {}
	for c in gs.world["clubs"]:
		for m in c["squad"]:
			out[str(m["uid"])] = {"club_id": str(c["id"]), "inst": m}
	return out


## Best average match rating among qualifying Pokémon. max_age 0 = any age.
## Deterministic tiebreaks: rating desc, KOs desc, uid asc.
func _pick_award(stats: Dictionary, owners: Dictionary, min_battles: int, max_age: int) -> Dictionary:
	var best := {}
	var uids := stats.keys()
	uids.sort()
	for uid in uids:
		var s: Dictionary = stats[uid]
		if int(s["battles"]) < min_battles or not owners.has(str(uid)):
			continue
		var own: Dictionary = owners[str(uid)]
		var age := int(own["inst"].get("age_months", 0))
		if max_age > 0 and age > max_age:
			continue
		var rating := float(s["rating_sum"]) / maxi(int(s["battles"]), 1)
		if best.is_empty() or rating > float(best["rating"]) + 0.0001 \
				or (absf(rating - float(best["rating"])) <= 0.0001 and int(s["kos"]) > int(best["kos"])):
			best = {"uid": str(uid), "name": str(s["name"]), "species": str(s["species"]),
				"club_id": str(own["club_id"]), "age_months": age,
				"rating": snappedf(rating, 0.01), "battles": int(s["battles"]), "kos": int(s["kos"])}
	return best


# ------------------------------------------------------------------ consequences

## Judge LAST season's board ultimatum against this season's final position.
func _judge_previous_ultimatum(gs) -> void:
	if ultimatum.is_empty() or int(ultimatum.get("season", 0)) != gs.season_no():
		return
	var target := int(ultimatum.get("target", ULTIMATUM_TARGET))
	var pos: int = gs.player_table_position()
	var pc: Dictionary = gs.player_club()
	if pos > 0 and pos <= target:
		gs.adjust_transfer_budget(str(pc["id"]), int(int(pc["finances"]["balance"]) * 0.05))
		gs.add_inbox_message(gs.current_date, "Board: ultimatum met — well done",
			("You finished %d%s — inside the top %d the board demanded after last season's "
			+ "Danger Zone finish. Confidence is restored and extra transfer funds released.") % [
			pos, _ord_suffix(pos), target])
	else:
		_bump_reputation(gs, str(pc["id"]), -1)
		gs.add_inbox_message(gs.current_date, "Board: ultimatum missed",
			("The board demanded a top-%d finish; you delivered %d%s. The club's standing "
			+ "takes another hit and patience is close to exhausted.") % [
			target, pos, _ord_suffix(pos)])
		if not gs.inbox.is_empty():
			gs.inbox[0]["urgent"] = true
	ultimatum = {}


## Danger Zone (14-16) is real: reputation and money suffer at every club that
## finishes there; the player also gets a board ultimatum for next season and
## their star Pokémon demands an exit.
func _apply_danger_zone(gs) -> void:
	var pid: String = str(gs.world["meta"]["player_club_id"])
	for lg in gs.leagues():
		var t: Array = gs.league_table(str(lg["id"]))
		for i in range(DANGER_FROM - 1, t.size()):
			var cid := str(t[i]["club_id"])
			var c: Dictionary = gs.club(cid)
			_bump_reputation(gs, cid, -1)
			var fin: Dictionary = c["finances"]
			fin["transfer_budget"] = maxi(0, int(int(fin.get("transfer_budget", 0)) * 0.75))
			fin["balance"] = int(int(fin["balance"]) * 0.97)
			if cid == pid:
				_player_danger_fallout(gs, i + 1)


func _player_danger_fallout(gs, pos: int) -> void:
	ultimatum = {"season": gs.season_no() + 1, "target": ULTIMATUM_TARGET}
	gs.add_inbox_message(gs.current_date, "Board ultimatum: finish %d%s or better next season" % [
		ULTIMATUM_TARGET, _ord_suffix(ULTIMATUM_TARGET)],
		("Finishing %d%s puts us in the Danger Zone and the board is not hiding its anger: "
		+ "sponsors have pulled back, the transfer budget has been cut by a quarter and the "
		+ "club's reputation has taken a hit. The demand is plain — finish %d%s or better "
		+ "next season. Fall short and there will be further consequences.") % [
		pos, _ord_suffix(pos), ULTIMATUM_TARGET, _ord_suffix(ULTIMATUM_TARGET)])
	if not gs.inbox.is_empty():
		gs.inbox[0]["urgent"] = true
	# the star wants out
	var star := {}
	for m in gs.player_club()["squad"]:
		if star.is_empty() or int(m["level"]) > int(star["level"]) \
				or (int(m["level"]) == int(star["level"]) and str(m["uid"]) < str(star["uid"])):
			star = m
	if not star.is_empty():
		star["morale"] = maxi(5, int(star.get("morale", 50)) - 25)
		star["exit_request"] = gs.season_no()
		var nickv: Variant = star.get("nickname")
		var nm := str(nickv) if nickv != null and str(nickv) != "" else str(star["species"])
		gs.add_inbox_message(gs.current_date, "%s is demanding to leave" % nm,
			("Your star %s (Lv %d) has no interest in another Danger Zone fight and has "
			+ "asked to move to a stronger club. Morale has collapsed — win the dressing room "
			+ "back with results, or listen to offers.") % [str(star["species"]), int(star["level"])])


func _ord_suffix(n: int) -> String:
	if n % 100 in [11, 12, 13]:
		return "th"
	match n % 10:
		1: return "st"
		2: return "nd"
		3: return "rd"
	return "th"


# ------------------------------------------------------------------ history

func _make_history_entry(gs, champion: String, runner_up: String, awards: Dictionary) -> Dictionary:
	var pid: String = str(gs.world["meta"]["player_club_id"])
	var league_champs := {}
	var top_four := {}
	var danger := {}
	var player_pos := 0
	var player_pts := 0
	for lg in gs.leagues():
		var lid := str(lg["id"])
		var t: Array = gs.league_table(lid)
		if t.is_empty():
			continue
		league_champs[lid] = {"club_id": str(t[0]["club_id"]),
			"name": str(gs.club(str(t[0]["club_id"])).get("name", "?")),
			"points": int(t[0]["points"])}
		top_four[lid] = []
		for i in mini(TOP_N, t.size()):
			top_four[lid].append(str(t[i]["club_id"]))
		danger[lid] = []
		for i in range(DANGER_FROM - 1, t.size()):
			danger[lid].append(str(t[i]["club_id"]))
		for i in t.size():
			if str(t[i]["club_id"]) == pid:
				player_pos = i + 1
				player_pts = int(t[i]["points"])

	# cup: winner of the highest played round (the Final under normal flow)
	var cup: Array = Season.cup_fixtures(gs.fixtures).filter(func(f): return f["played"])
	var cup_winner := ""
	var cup_runner := ""
	var cup_max := 0
	for f in cup:
		cup_max = maxi(cup_max, int(f["round"]))
	for f in cup:
		if int(f["round"]) == cup_max:
			cup_winner = Season.fixture_winner(f)
			cup_runner = str(f["away"] if cup_winner == str(f["home"]) else f["home"])
	var player_cup := "winners" if cup_winner == pid else _cup_exit_text(gs, cup, pid)

	var po_results: Array = []
	for f in Season.playoff_fixtures(gs.fixtures):
		if f["played"]:
			po_results.append({"round": int(f["round"]), "id": str(f["id"]),
				"home": str(f["home"]), "away": str(f["away"]),
				"sh": int(f["score_home"]), "sa": int(f["score_away"])})
	po_results.sort_custom(func(x, y):
		return str(x["id"]) < str(y["id"]) if int(x["round"]) == int(y["round"]) \
			else int(x["round"]) < int(y["round"]))

	return {
		"season": gs.season_no(),
		"start": gs.season_start, "end": gs.current_date,
		"indigo": {"champion": champion, "name": str(gs.club(champion).get("name", "?")),
			"runner_up": runner_up, "runner_up_name": str(gs.club(runner_up).get("name", "?"))},
		"league_champions": league_champs,
		"top_four": top_four,
		"danger": danger,
		"cup": {"winner": cup_winner, "name": str(gs.club(cup_winner).get("name", "?")),
			"runner_up": cup_runner},
		"playoff_results": po_results,
		"awards": awards,
		"player": {"club_id": pid, "name": str(gs.player_club().get("name", "?")),
			"league": gs.player_league_id(), "pos": player_pos, "points": player_pts,
			"cup": player_cup},
	}


func _cup_exit_text(gs, cup_played: Array, pid: String) -> String:
	var out_round := 0
	for f in cup_played:
		if (str(f["home"]) == pid or str(f["away"]) == pid) and Season.fixture_winner(f) != pid:
			out_round = maxi(out_round, int(f["round"]))
	return "out in the %s" % Season.cup_round_name(out_round) if out_round > 0 else "did not lose a tie"


# ------------------------------------------------------------------ mails

func _send_awards_mail(gs, e: Dictionary) -> void:
	var lines: Array = []
	lines.append("%s: %s (def. %s in the Final)" % [Season.INDIGO_TITLE,
		e["indigo"]["name"], e["indigo"]["runner_up_name"]])
	for lg in gs.leagues():
		var lid := str(lg["id"])
		if e["league_champions"].has(lid):
			lines.append("%s champions: %s (%d pts)" % [str(lg["name"]),
				e["league_champions"][lid]["name"], int(e["league_champions"][lid]["points"])])
	if str(e["cup"]["winner"]) != "":
		lines.append("%s winners: %s" % [gs.cup_name(), e["cup"]["name"]])
	var pos: Dictionary = e["awards"].get("pokemon_of_season", {})
	if not pos.is_empty():
		lines.append("Pokémon of the Season: %s (%s, %s) — avg rating %.2f over %d battles" % [
			pos["name"], pos["species"], str(gs.club(str(pos["club_id"])).get("name", "?")),
			float(pos["rating"]), int(pos["battles"])])
	var dev: Dictionary = e["awards"].get("best_developer", {})
	if not dev.is_empty():
		lines.append("Best Developer (young Pokémon of the season): %s (%s, %s) — %.2f avg rating at %d months old" % [
			dev["name"], dev["species"], str(gs.club(str(dev["club_id"])).get("name", "?")),
			float(dev["rating"]), int(dev["age_months"])])
	gs.add_inbox_message(gs.current_date, "End-of-Season Awards — Season %d" % gs.season_no(),
		"The league has held its end-of-season ceremony.\n\n" + "\n".join(lines)
		+ "\n\nAll honours are recorded permanently in Competition > History.")
	if not gs.inbox.is_empty():
		gs.inbox[0]["urgent"] = true


func _send_season_review(gs, e: Dictionary) -> void:
	var p: Dictionary = e["player"]
	var pid := str(p["club_id"])
	var po_text := "did not qualify for the %s" % Season.PLAYOFF_NAME
	if str(e["indigo"]["champion"]) == pid:
		po_text = "won the %s — %s!" % [Season.PLAYOFF_NAME, Season.INDIGO_TITLE]
	elif str(e["indigo"]["runner_up"]) == pid:
		po_text = "reached the %s Final" % Season.PLAYOFF_NAME
	else:
		for r in e["playoff_results"]:
			if (str(r["home"]) == pid or str(r["away"]) == pid):
				var won: bool = (int(r["sh"]) > int(r["sa"])) == (str(r["home"]) == pid)
				if not won:
					po_text = "went out of the %s in the %s" % [
						Season.PLAYOFF_NAME, Season.playoff_round_name(int(r["round"]))]
	# our best performer this season (any age, our squad only)
	var stats: Dictionary = Season.season_player_stats(gs.fixtures)
	var owners := _owner_index(gs)
	var best := {}
	var uids := stats.keys()
	uids.sort()
	for uid in uids:
		if not owners.has(str(uid)) or str(owners[str(uid)]["club_id"]) != pid:
			continue
		var s: Dictionary = stats[uid]
		if int(s["battles"]) < 3:
			continue
		var rating := float(s["rating_sum"]) / maxi(int(s["battles"]), 1)
		if best.is_empty() or rating > float(best["rating"]):
			best = {"name": str(s["name"]), "rating": rating, "battles": int(s["battles"])}
	var body := ("Season %d review, %s:\n\n- League: finished %d%s in the %s with %d points\n"
		+ "- %s: %s\n- %s: we %s") % [
		gs.season_no(), str(p["name"]), int(p["pos"]), _ord_suffix(int(p["pos"])),
		gs.league_name(str(p["league"])), int(p["points"]),
		gs.cup_name(), str(p["cup"]), Season.PLAYOFF_NAME, po_text]
	if not best.is_empty():
		body += "\n- Star performer: %s (%.2f avg rating, %d battles)" % [
			best["name"], float(best["rating"]), int(best["battles"])]
	body += "\n\nPreseason starts %s. The full honours list lives in Competition > History." \
		% Season.pretty_date(Season.date_add(str(gs.season_start), 364))
	gs.add_inbox_message(gs.current_date, "Season %d review: %s" % [gs.season_no(), str(p["name"])], body)
