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
##   Sacking arc         a missed board ultimatum (or a catastrophic season:
##                        dead last with almost nothing won) gets the manager
##                        FIRED at the ceremony: sacking mail, a persistent
##                        game-over record (career summary + offers from 2-3
##                        lesser clubs, rendered by the shell), and the career
##                        continues via GameState.accept_job_offer or a fresh
##                        start. One manager-stint record per season rides
##                        GameState.manager_history().
##   Inbox hygiene       at rollover every ROUTINE mail is auto-marked read
##                        (urgent + open-decision mail stays), the read pile is
##                        trimmed, and one season-digest mail summarises what
##                        was filed — the unread badge stays meaningful.
##   Age plausibility    free-agent/prospect pool ages are clamped to each
##                        species' evolutionary stage (no ten-year-old baby
##                        Pokémon), deterministically, at career start and
##                        after every rollover.
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
const NEWCOMER_MAX_AGE := 24         ## Best Newcomer: academy grads / true rookies
const WALL_MIN_BATTLES := 6          ## Golden Guard eligibility
const CUP_MVP_MIN_BATTLES := 3       ## Cup MVP eligibility (cup battles only)
const CATASTROPHE_MAX_PTS := 18      ## dead last + <= this = sacked on the spot
const OFFER_COUNT := 3               ## lesser clubs that come calling after a sacking
const INBOX_KEEP_MAX := 120          ## read routine mail kept after the rollover trim

var phase := "regular"               # regular | playoff | offseason
var rollover_date := ""              # set when the phase turns "offseason"
var ultimatum := {}                  # {"season": int, "target": int, "club_id": String}
var last_awards := {}                # latest ceremony (convenience copy)
var _evo_loaded := false             # evolutions.json parsed (age-cap maps)
var _evo_parent: Dictionary = {}     # child species id -> pre-evo id
var _evolves: Dictionary = {}        # species id -> true if it evolves further


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
		ultimatum = {"season": int(ultimatum.get("season", 0)),
			"target": int(ultimatum.get("target", ULTIMATUM_TARGET)),
			"club_id": str(ultimatum.get("club_id", ""))}
	last_awards = state.get("last_awards", {}) if typeof(state.get("last_awards")) == TYPE_DICTIONARY else {}


func on_career_started(gs) -> void:
	instance = self
	_reconcile_phase(gs)
	_clamp_pool_ages(gs)


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
				var closed_season: int = gs.season_no()
				var filed := _tidy_inbox(gs)          # mark routine mail read + trim
				gs.start_new_season()
				_send_season_digest(gs, closed_season, filed)
				_clamp_pool_ages(gs)                  # pools aged +12 — re-clamp


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
	gs.add_inbox_message(gs.current_date, I18n.t("%s: the top four of each league are in") % I18n.t(Season.PLAYOFF_NAME),
		(I18n.t("The championships are decided — now the %s begins. The top four of the %s ")
		+ I18n.t("and the %s meet in a seeded cross-league knockout for the %s title. ")
		+ I18n.t("Quarter-finals on %s: %s.%s")) % [
		I18n.t(Season.PLAYOFF_NAME), I18n.t(gs.league_name(str(lgs[0]["id"]))),
		I18n.t(gs.league_name(str(lgs[1]["id"]))) if lgs.size() > 1 else "",
		I18n.t(Season.INDIGO_TITLE), I18n.pretty_date(date), names,
		I18n.t("\n\nWE ARE IN — the board is delighted. Go and win it.") if player_in else ""])
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
	gs.add_inbox_message(gs.current_date, I18n.t("%s: %s line-up set") % [
		I18n.t(Season.PLAYOFF_NAME), I18n.playoff_round(next_round)],
		I18n.t("Through to the %s on %s: %s.") % [
		I18n.playoff_round_prose(next_round), I18n.pretty_date(date), names])
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

	var sack_reason := _judge_previous_ultimatum(gs)
	_apply_danger_zone(gs)
	var entry := _make_history_entry(gs, champion, runner_up, awards)
	gs.add_history_entry(entry)
	_record_stint(gs, entry)
	if sack_reason == "":
		sack_reason = _catastrophe_check(gs, entry)
	_send_awards_mail(gs, entry)
	_send_season_review(gs, entry)
	if sack_reason != "":
		_sack_manager(gs, sack_reason)

	rollover_date = Season.date_add(gs.current_date, ROLLOVER_DELAY_DAYS)
	phase = "offseason"
	# the calendar jumps to the NEW preseason when the rollover fires — quote
	# the date the player will actually land on, not the rollover tick itself
	var new_preseason: String = Season.date_add(str(gs.season_start), 364)
	gs.add_inbox_message(gs.current_date, I18n.t("Off-season: Season %d starts %s") % [
		gs.season_no() + 1, I18n.pretty_date(new_preseason)],
		(I18n.t("The season is complete. The squad gets a break — pressing Continue past %s ")
		+ I18n.t("fast-forwards to preseason on %s, with fresh fixtures for both championships ")
		+ I18n.t("and a new %s draw. Squads, finances and development all carry over.")) % [
		I18n.pretty_date(rollover_date), I18n.pretty_date(new_preseason), I18n.t(gs.cup_name())])


func _bump_reputation(gs, club_id: String, delta: int) -> void:
	var c: Dictionary = gs.club(club_id)
	if not c.is_empty():
		c["reputation"] = clampi(int(c["reputation"]) + delta, 1, 20)


## Pure + deterministic (reads recorded match details only) — sim_check calls
## this twice and asserts identical output. Five honours, and NO SWEEPS: each
## award excludes every Pokémon already honoured this ceremony (the exclusion
## is relaxed only if it would leave an award without any qualifier at all).
func compute_awards(gs) -> Dictionary:
	var stats: Dictionary = Season.season_player_stats(gs.fixtures)
	var cup_stats: Dictionary = Season.season_player_stats_comp(gs.fixtures, "cup")
	var owners := _owner_index(gs)
	var taken := {}   # uid -> true (already honoured)

	var pos := _pick_best(stats, owners, taken, POS_MIN_BATTLES, _f_any())
	if pos.is_empty():
		pos = _pick_best(stats, owners, taken, 1, _f_any())
	_take(taken, pos)

	var cup_mvp := _pick_best(cup_stats, owners, taken, CUP_MVP_MIN_BATTLES, _f_any())
	if cup_mvp.is_empty():
		cup_mvp = _pick_best(cup_stats, owners, {}, 1, _f_any())
	_take(taken, cup_mvp)

	var wall := _pick_best(stats, owners, taken, WALL_MIN_BATTLES, _f_any(), "wall")
	if wall.is_empty():
		wall = _pick_best(stats, owners, taken, 1, _f_any(), "wall")
	_take(taken, wall)

	var breakout := _pick_best(stats, owners, taken, BREAKOUT_MIN_BATTLES, _f_max_age(BREAKOUT_MAX_AGE))
	if breakout.is_empty():
		breakout = _pick_best(stats, owners, taken, 1, _f_max_age(BREAKOUT_MAX_AGE))
	_take(taken, breakout)

	var newcomer := _pick_best(stats, owners, taken, 1, _f_newcomer())
	_take(taken, newcomer)

	return {"pokemon_of_season": pos, "best_developer": breakout,
		"cup_mvp": cup_mvp, "golden_guard": wall, "best_newcomer": newcomer}


static func _take(taken: Dictionary, entry: Dictionary) -> void:
	if not entry.is_empty():
		taken[str(entry["uid"])] = true


# eligibility filters (inst -> bool)
func _f_any() -> Callable:
	return func(_inst: Dictionary) -> bool: return true


func _f_max_age(max_age: int) -> Callable:
	return func(inst: Dictionary) -> bool:
		return int(inst.get("age_months", 0)) <= max_age


## Best Newcomer: academy graduates first and foremost; genuine first-year
## rookies (<= NEWCOMER_MAX_AGE months) also qualify so AI clubs can win it.
func _f_newcomer() -> Callable:
	return func(inst: Dictionary) -> bool:
		return bool(inst.get("from_academy", false)) \
			or int(inst.get("age_months", 999)) <= NEWCOMER_MAX_AGE


## uid -> {club_id, inst} across every squad (award winners need an owner).
func _owner_index(gs) -> Dictionary:
	var out := {}
	for c in gs.world["clubs"]:
		for m in c["squad"]:
			out[str(m["uid"])] = {"club_id": str(c["id"]), "inst": m}
	return out


## Best qualifying Pokémon by metric. metric "rating" = avg match rating
## (tiebreaks: rating desc, KOs desc, uid asc); metric "wall" = damage soaked
## per faint (Golden Guard — tiebreaks: score desc, taken desc, uid asc).
## `taken` uids (already-honoured winners) never win again — the no-sweep rule.
func _pick_best(stats: Dictionary, owners: Dictionary, taken: Dictionary,
		min_battles: int, eligible: Callable, metric: String = "rating") -> Dictionary:
	var best := {}
	var best_score := -1.0
	var uids := stats.keys()
	uids.sort()
	for uid in uids:
		var s: Dictionary = stats[uid]
		if int(s["battles"]) < min_battles or not owners.has(str(uid)) or taken.has(str(uid)):
			continue
		var own: Dictionary = owners[str(uid)]
		if not bool(eligible.call(own["inst"])):
			continue
		var rating := float(s["rating_sum"]) / maxi(int(s["battles"]), 1)
		var score := rating
		if metric == "wall":
			if int(s["taken"]) <= 0:
				continue
			score = float(s["taken"]) / float(int(s["faints"]) + 1)
		var second := float(s["kos"]) if metric == "rating" else float(s["taken"])
		if best.is_empty() or score > best_score + 0.0001 \
				or (absf(score - best_score) <= 0.0001 and second > float(best["_second"])):
			best_score = score
			best = _award_entry(str(uid), s, own, rating)
			best["_second"] = second
			if metric == "wall":
				best["soaked"] = int(s["taken"])
				best["faints"] = int(s["faints"])
				best["wall_score"] = snappedf(score, 0.1)
	best.erase("_second")
	return best


## One award-winner record. `display` is pre-deduplicated for UIs: the name,
## plus the species in brackets ONLY when a nickname differs from it — never
## the redundant "Pikachu (Pikachu)".
func _award_entry(uid: String, s: Dictionary, own: Dictionary, rating: float) -> Dictionary:
	var nm := str(s["name"])
	var sp := str(s["species"])
	return {"uid": uid, "name": nm, "species": sp, "level": int(s.get("level", 0)),
		"display": nm if nm == sp else "%s (%s)" % [nm, sp],
		"club_id": str(own["club_id"]),
		"age_months": int(own["inst"].get("age_months", 0)),
		"from_academy": bool(own["inst"].get("from_academy", false)),
		"rating": snappedf(rating, 0.01), "battles": int(s["battles"]), "kos": int(s["kos"])}


# ------------------------------------------------------------------ consequences

## Judge LAST season's board ultimatum against this season's final position.
## Returns "" (survived / no ultimatum) or the sacking reason — a missed
## ultimatum is TERMINAL: the board actually fires the manager.
func _judge_previous_ultimatum(gs) -> String:
	var pc: Dictionary = gs.player_club()
	if ultimatum.is_empty() or int(ultimatum.get("season", 0)) != gs.season_no():
		return ""
	if str(ultimatum.get("club_id", str(pc["id"]))) != str(pc["id"]):
		ultimatum = {}   # ultimatum belonged to a previous employer
		return ""
	var target := int(ultimatum.get("target", ULTIMATUM_TARGET))
	var pos: int = gs.player_table_position()
	ultimatum = {}
	if pos > 0 and pos <= target:
		gs.adjust_transfer_budget(str(pc["id"]), int(int(pc["finances"]["balance"]) * 0.05))
		gs.add_inbox_message(gs.current_date, I18n.t("Board: ultimatum met — well done"),
			(I18n.t("You finished %s — inside the top %d the board demanded after last season's ")
			+ I18n.t("Danger Zone finish. Confidence is restored and extra transfer funds released.")) % [
			I18n.ordinal(pos), target])
		return ""
	_bump_reputation(gs, str(pc["id"]), -1)
	return (I18n.t("the board demanded a top-%d finish and you delivered %s — the ")
		+ I18n.t("second failure in a row")) % [target, I18n.ordinal(pos)]


## Even without an ultimatum, a truly catastrophic season is a firing offence:
## dead last with almost nothing on the board.
func _catastrophe_check(gs, entry: Dictionary) -> String:
	var p: Dictionary = entry["player"]
	var table_size: int = gs.league_table(str(p["league"])).size()
	if int(p["pos"]) >= table_size and table_size > 0 and int(p["points"]) <= CATASTROPHE_MAX_PTS:
		return I18n.t("a catastrophic season — dead last in the %s with just %d points") % [
			gs.league_name(str(p["league"])), int(p["points"])]
	return ""


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
	ultimatum = {"season": gs.season_no() + 1, "target": ULTIMATUM_TARGET,
		"club_id": str(gs.player_club()["id"])}
	gs.add_inbox_message(gs.current_date, I18n.t("Board ultimatum: finish %s or better next season") %
		I18n.ordinal(ULTIMATUM_TARGET),
		(I18n.t("Finishing %s puts us in the Danger Zone and the board is not hiding its anger: ")
		+ I18n.t("sponsors have pulled back, the transfer budget has been cut by a quarter and the ")
		+ I18n.t("club's reputation has taken a hit. The demand is plain — finish %s or better ")
		+ I18n.t("next season. Fall short and there will be further consequences.")) % [
		I18n.ordinal(pos), I18n.ordinal(ULTIMATUM_TARGET)])
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
		gs.add_inbox_message(gs.current_date, I18n.t("%s is demanding to leave") % nm,
			(I18n.t("Your star %s (Lv %d) has no interest in another Danger Zone fight and has ")
			+ I18n.t("asked to move to a stronger club. Morale has collapsed — win the dressing room ")
			+ I18n.t("back with results, or listen to offers.")) % [str(star["species"]), int(star["level"])])


## Ordinals now come from I18n.ordinal(), which is locale-aware
## ("14th" en / "14.º" es) — no English suffix helper remains here.


# ------------------------------------------------------------------ manager career / sacking

## One manager-stint record per completed season (GameState.manager_history()).
func _record_stint(gs, e: Dictionary) -> void:
	var p: Dictionary = e["player"]
	var pid := str(p["club_id"])
	var wins := 0
	var losses := 0
	for f in gs.fixtures:
		if f.get("played", false) and (str(f["home"]) == pid or str(f["away"]) == pid):
			if Season.fixture_winner(f) == pid:
				wins += 1
			else:
				losses += 1
	var honours: Array = []
	for lid in e["league_champions"]:
		if str(e["league_champions"][lid]["club_id"]) == pid:
			honours.append(I18n.t("%s Champions") % I18n.t(gs.league_name(str(lid))))
	if str(e["cup"]["winner"]) == pid:
		honours.append(I18n.t("%s Winners") % I18n.t(gs.cup_name()))
	if str(e["indigo"]["champion"]) == pid:
		honours.append(I18n.t(Season.INDIGO_TITLE))
	gs.record_manager_stint({"season": gs.season_no(), "club_id": pid,
		"club": str(p["name"]), "league": str(p["league"]), "pos": int(p["pos"]),
		"points": int(p["points"]), "wins": wins, "losses": losses,
		"cup": str(p["cup"]), "honours": honours})


## Whole-career totals for the game-over screen.
func _career_summary(gs) -> Dictionary:
	var hist: Array = gs.manager_history()
	var wins := 0
	var losses := 0
	var honours: Array = []
	var best_pos := 0
	var clubs := {}
	for st in hist:
		wins += int(st.get("wins", 0))
		losses += int(st.get("losses", 0))
		honours += (st.get("honours", []) as Array).map(func(h): return I18n.t("%s (Season %d)") % [str(h), int(st["season"])])
		clubs[str(st.get("club_id", ""))] = str(st.get("club", ""))
		if best_pos == 0 or (int(st.get("pos", 0)) > 0 and int(st["pos"]) < best_pos):
			best_pos = int(st["pos"])
	return {"seasons": hist.size(), "wins": wins, "losses": losses,
		"honours": honours, "best_pos": best_pos, "clubs": clubs.values()}


## 2-3 humbler clubs come calling. Deterministic per (career_seed, season).
func _make_offers(gs) -> Array:
	var pid: String = str(gs.player_club()["id"])
	var my_rep := int(gs.player_club().get("reputation", 10))
	var pool: Array = gs.world["clubs"].filter(func(c):
		return str(c["id"]) != pid and int(c.get("reputation", 10)) < my_rep)
	if pool.size() < 2:   # already at the bottom of the pyramid: any modest club
		pool = gs.world["clubs"].filter(func(c):
			return str(c["id"]) != pid and int(c.get("reputation", 10)) <= my_rep)
	pool.sort_custom(func(a, b): return int(a["reputation"]) < int(b["reputation"]) \
		if int(a["reputation"]) != int(b["reputation"]) else str(a["id"]) < str(b["id"]))
	var r := RandomNumberGenerator.new()
	r.seed = int(gs.career_seed) + gs.season_no() * 7907 + hash("sack_offers")
	var out: Array = []
	# draw from the weaker half of the market — beggars, choosers, etc.
	var half: Array = pool.slice(0, maxi(2, pool.size() / 2 + 1))
	while out.size() < OFFER_COUNT and not half.is_empty():
		var c: Dictionary = half.pop_at(r.randi() % half.size())
		out.append({"club_id": str(c["id"]), "name": str(c["name"]),
			"league": I18n.t(gs.league_name(str(c.get("league", "kanto")))),
			"reputation": int(c.get("reputation", 10))})
	return out


## The board pulls the trigger: sacking mail (urgent, top of the pile), then
## the persistent game-over record the shell renders — career summary and the
## job offers that keep the career alive.
func _sack_manager(gs, reason: String) -> void:
	var pc: Dictionary = gs.player_club()
	var summary := _career_summary(gs)
	var offers := _make_offers(gs)
	var body := (I18n.t("%s\n\nThe board of %s has relieved you of your duties, effective ")
		+ I18n.t("immediately: %s. The dressing room has been informed and a caretaker ")
		+ I18n.t("will see out the off-season.\n\nYour career to date: %s, ")
		+ I18n.t("%d–%d in matches, %s. Clubs lower down the pyramid are ")
		+ I18n.t("already calling — your next move is on the career screen.")) % [
		I18n.t("CONTRACT TERMINATED."), str(pc["name"]), reason,
		I18n.np(int(summary["seasons"]), "%d season", "%d seasons"),
		int(summary["wins"]), int(summary["losses"]),
		I18n.np((summary["honours"] as Array).size(), "%d honour", "%d honours")]
	gs.add_inbox_message(gs.current_date, I18n.t("Sacked: %s dismiss you as manager") % str(pc["name"]), body)
	if not gs.inbox.is_empty():
		gs.inbox[0]["urgent"] = true
		gs.inbox[0]["cat"] = "board"
		gs.inbox[0]["uid"] = "sacked:S%d" % gs.season_no()
	gs.trigger_game_over({"reason": reason, "season": gs.season_no(),
		"club_id": str(pc["id"]), "club": str(pc["name"]),
		"summary": summary, "offers": offers, "date": gs.current_date})


# ------------------------------------------------------------------ inbox hygiene

## Does this mail still owe the manager an answer? (Mirror of the Inbox
## screen's decision test — those must stay unread through any tidy-up.)
func _mail_needs_decision(m: Dictionary) -> bool:
	if m.has("offer_id"):
		return true
	if str(m.get("kind", "")) == "evo_ready":
		return str(m.get("decided", "")) == ""
	if str(m.get("academy_kind", "")) == "cull":
		return not bool(m.get("resolved", false))
	var uid := str(m.get("uid", ""))
	return (uid.begins_with("mind:") or uid.begins_with("monlow:")) \
		and str(m.get("replied", "")) == ""


## Rollover housekeeping: mark every ROUTINE unread mail read (urgent news and
## open decisions survive), then trim the read backlog so ten-season careers
## don't drag a thousand-mail inbox around. Returns what was filed, for the
## digest: {"total": int, "by_cat": {cat: int}, "trimmed": int}.
func _tidy_inbox(gs) -> Dictionary:
	var filed := {"total": 0, "by_cat": {}, "trimmed": 0}
	for m in gs.inbox:
		if bool(m.get("read", false)):
			continue
		if _mail_needs_decision(m) or bool(m.get("urgent", false)):
			continue
		m["read"] = true
		filed["total"] = int(filed["total"]) + 1
		var cat := str(m.get("cat", ""))
		if cat == "":   # GameState-posted mail the news enricher hasn't seen yet
			var t := str(m.get("title", ""))
			if t.begins_with("Match report:"):
				cat = "match"
			elif t.contains("Cup") or t.contains("cup"):
				cat = "cup"
			elif t.begins_with("Board"):
				cat = "board"
			else:
				cat = "news"
		filed["by_cat"][cat] = int(filed["by_cat"].get(cat, 0)) + 1
	if gs.inbox.size() > INBOX_KEEP_MAX:
		var kept: Array = []
		var read_kept := 0
		for m in gs.inbox:
			if not bool(m.get("read", false)) or _mail_needs_decision(m) or read_kept < INBOX_KEEP_MAX:
				kept.append(m)
				if bool(m.get("read", false)):
					read_kept += 1
			else:
				filed["trimmed"] = int(filed["trimmed"]) + 1
		gs.inbox.assign(kept)
	gs.inbox_updated.emit()
	return filed


const CAT_LABELS := {"match": "match reports", "cup": "cup news", "media": "media & league news",
	"staff": "staff updates", "scout": "scouting", "transfer": "transfer market",
	"board": "boardroom", "news": "club news"}


## One mail replaces the pile: what was auto-filed, plus the season's headlines.
func _send_season_digest(gs, closed_season: int, filed: Dictionary) -> void:
	var lines: Array = []
	var by_cat: Dictionary = filed["by_cat"]
	var cats := by_cat.keys()
	cats.sort()
	for c in cats:
		lines.append("- %s: %d" % [I18n.t(str(CAT_LABELS.get(str(c), str(c)))), int(by_cat[c])])
	var body := I18n.t("Season %d is in the books. Your secretary has archived the routine correspondence — %s marked read%s so the inbox opens clean for the new campaign:\n\n%s") % [
		closed_season, I18n.np(int(filed["total"]), "%d message", "%d messages"),
		(I18n.t(" (%d old read items filed away)") % int(filed["trimmed"])) if int(filed["trimmed"]) > 0 else "",
		"\n".join(lines) if not lines.is_empty() else I18n.t("- nothing needed filing")]
	var hist: Array = gs.season_history()
	if not hist.is_empty():
		var e: Dictionary = hist[-1]
		var p: Dictionary = e["player"]
		body += I18n.t("\n\nSeason %d in one line: finished %s in the %s (%d pts), %s in the %s; %s were crowned %s.") % [
			closed_season, I18n.ordinal(int(p["pos"])),
			I18n.t(gs.league_name(str(p["league"]))), int(p["points"]),
			str(p["cup"]), I18n.t(gs.cup_name()), str(e["indigo"]["name"]), I18n.t(Season.INDIGO_TITLE)]
	body += I18n.t("\n\nAnything urgent or awaiting a decision was left untouched at the top of your inbox.")
	gs.add_inbox_message(gs.current_date, I18n.t("Season %d digest — your inbox has been tidied") % closed_season, body)
	if not gs.inbox.is_empty():
		gs.inbox[0]["cat"] = "media"
		gs.inbox[0]["sender"] = I18n.t("Club secretary")
		gs.inbox[0]["uid"] = "digest:S%d" % closed_season
	gs.inbox_updated.emit()


# ------------------------------------------------------------------ age plausibility

## Species-stage age caps for GENERATED pools: a Pokémon that still has
## evolving to do cannot plausibly be an old campaigner. Base stage of an
## evolving line -> 4y, middle stage -> 7y, final/standalone forms -> uncapped.
func _age_cap_months(species_id: int) -> int:
	if not _evo_loaded:
		_evo_loaded = true
		var f := FileAccess.open("res://shared/data/evolutions.json", FileAccess.READ)
		if f != null:
			var data: Variant = JSON.parse_string(f.get_as_text())
			var evos: Dictionary = data.get("evolutions", {}) if data is Dictionary else {}
			for from_id in evos:
				_evolves[int(from_id)] = true
				for e in evos[from_id]:
					_evo_parent[int(e["to"])] = int(from_id)
	if not _evolves.has(species_id):
		return 0   # final form / standalone species: any age is plausible
	return 84 if _evo_parent.has(species_id) else 48


## Deterministically re-house implausible ages in the free-agent/prospect
## pools (rollover ages them +12 every season, and world-gen rolled some
## ancient juveniles). Squads are left alone — evolution handles those.
func _clamp_pool_ages(gs) -> int:
	var changed := 0
	for pool_name in ["free_agents", "prospects"]:
		for m in gs.world.get(pool_name, []):
			var cap := _age_cap_months(int(m.get("species_id", 0)))
			if cap > 0 and int(m.get("age_months", 0)) > cap:
				var span := cap - 11
				m["age_months"] = 12 + posmod(int(m["age_months"]) * 131 + hash(str(m.get("uid", ""))), span)
				changed += 1
	return changed


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
		"awards": _history_awards(awards),
		"player": {"club_id": pid, "name": str(gs.player_club().get("name", "?")),
			"league": gs.player_league_id(), "pos": player_pos, "points": player_pts,
			"cup": player_cup},
	}


## The copy of the awards stored in the permanent history record. The roll of
## honour renders winners as "name (species)" — for a Pokémon with no nickname
## that's the redundant "Jumpluff (Jumpluff)", so the stored species slot
## becomes the level tag instead ("Jumpluff (Lv 34)"). Nicknamed winners keep
## their species in brackets. compute_awards / last_awards stay untouched.
func _history_awards(awards: Dictionary) -> Dictionary:
	var out := {}
	for k in awards:
		var a: Dictionary = (awards[k] as Dictionary).duplicate()
		if not a.is_empty() and str(a.get("species", "")) == str(a.get("name", "?")):
			a["species"] = I18n.t("Lv %d") % int(a.get("level", 0))
		out[k] = a
	return out


func _cup_exit_text(gs, cup_played: Array, pid: String) -> String:
	var out_round := 0
	for f in cup_played:
		if (str(f["home"]) == pid or str(f["away"]) == pid) and Season.fixture_winner(f) != pid:
			out_round = maxi(out_round, int(f["round"]))
	return I18n.t("out in the %s") % I18n.cup_round_prose(out_round) if out_round > 0 else I18n.t("did not lose a tie")


# ------------------------------------------------------------------ mails

## "Name (Species), Club" with the species shown only when a nickname differs
## from it — never the redundant "Pikachu (Pikachu)".
func _award_line_name(gs, a: Dictionary) -> String:
	var nm := str(a.get("display", a.get("name", "?")))
	return "%s, %s" % [nm, str(gs.club(str(a.get("club_id", ""))).get("name", "?"))]


func _send_awards_mail(gs, e: Dictionary) -> void:
	var lines: Array = []
	lines.append(I18n.t("%s: %s (def. %s in the Final)") % [I18n.t(Season.INDIGO_TITLE),
		e["indigo"]["name"], e["indigo"]["runner_up_name"]])
	for lg in gs.leagues():
		var lid := str(lg["id"])
		if e["league_champions"].has(lid):
			lines.append(I18n.t("%s champions: %s (%d pts)") % [I18n.t(str(lg["name"])),
				e["league_champions"][lid]["name"], int(e["league_champions"][lid]["points"])])
	if str(e["cup"]["winner"]) != "":
		lines.append(I18n.t("%s winners: %s") % [I18n.t(gs.cup_name()), e["cup"]["name"]])
	var pos: Dictionary = e["awards"].get("pokemon_of_season", {})
	if not pos.is_empty():
		lines.append(I18n.t("Pokémon of the Season: %s — avg rating %s over %d battles") % [
			_award_line_name(gs, pos), I18n.decimal(float(pos["rating"]), 2), int(pos["battles"])])
	var mvp: Dictionary = e["awards"].get("cup_mvp", {})
	if not mvp.is_empty():
		lines.append(I18n.t("%s MVP: %s — %s avg rating in the cup") % [
			I18n.t(gs.cup_name()), _award_line_name(gs, mvp), I18n.decimal(float(mvp["rating"]), 2)])
	var wall: Dictionary = e["awards"].get("golden_guard", {})
	if not wall.is_empty():
		lines.append(I18n.t("Golden Guard (wall of the season): %s — soaked %d damage across %d battles") % [
			_award_line_name(gs, wall), int(wall.get("soaked", 0)), int(wall["battles"])])
	var dev: Dictionary = e["awards"].get("best_developer", {})
	if not dev.is_empty():
		lines.append(I18n.t("Best Developer (young Pokémon of the season): %s — %s avg rating at %d months old") % [
			_award_line_name(gs, dev), I18n.decimal(float(dev["rating"]), 2), int(dev["age_months"])])
	var newc: Dictionary = e["awards"].get("best_newcomer", {})
	if not newc.is_empty():
		lines.append(I18n.t("Best Newcomer%s: %s — %s avg rating in a debut season") % [
			I18n.t(" (academy graduate)") if bool(newc.get("from_academy", false)) else "",
			_award_line_name(gs, newc), I18n.decimal(float(newc["rating"]), 2)])
	gs.add_inbox_message(gs.current_date, I18n.t("End-of-Season Awards — Season %d") % gs.season_no(),
		I18n.t("The league has held its end-of-season ceremony.\n\n") + "\n".join(lines)
		+ I18n.t("\n\nAll honours are recorded permanently in Competition > History."))
	if not gs.inbox.is_empty():
		gs.inbox[0]["urgent"] = true


func _send_season_review(gs, e: Dictionary) -> void:
	var p: Dictionary = e["player"]
	var pid := str(p["club_id"])
	var po_text := I18n.t("did not qualify for the %s") % I18n.t(Season.PLAYOFF_NAME)
	if str(e["indigo"]["champion"]) == pid:
		po_text = I18n.t("won the %s — %s!") % [I18n.t(Season.PLAYOFF_NAME), I18n.t(Season.INDIGO_TITLE)]
	elif str(e["indigo"]["runner_up"]) == pid:
		po_text = I18n.t("reached the %s Final") % I18n.t(Season.PLAYOFF_NAME)
	else:
		for r in e["playoff_results"]:
			if (str(r["home"]) == pid or str(r["away"]) == pid):
				var won: bool = (int(r["sh"]) > int(r["sa"])) == (str(r["home"]) == pid)
				if not won:
					po_text = I18n.t("went out of the %s in the %s") % [
						I18n.t(Season.PLAYOFF_NAME), I18n.playoff_round_prose(int(r["round"]))]
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
	var body := (I18n.t("Season %d review, %s:\n\n- League: finished %s in the %s with %d points\n")
		+ I18n.t("- %s: %s\n- %s: we %s")) % [
		gs.season_no(), str(p["name"]), I18n.ordinal(int(p["pos"])),
		I18n.t(gs.league_name(str(p["league"]))), int(p["points"]),
		I18n.t(gs.cup_name()), str(p["cup"]), I18n.t(Season.PLAYOFF_NAME), po_text]
	if not best.is_empty():
		body += I18n.t("\n- Star performer: %s (%s avg rating, %d battles)") % [
			best["name"], I18n.decimal(float(best["rating"]), 2), int(best["battles"])]
	body += I18n.t("\n\nPreseason starts %s. The full honours list lives in Competition > History.") \
		% I18n.pretty_date(Season.date_add(str(gs.season_start), 364))
	gs.add_inbox_message(gs.current_date, I18n.t("Season %d review: %s") % [gs.season_no(), str(p["name"])], body)
