extends RefCounted
## Inbox piece: the PEOPLE & MEDIA layer — messages from persons, not club ops.
##
##   mind:<fid>      rival manager mind-games before our fixtures, with brief
##                   reply choices that genuinely nudge squad morale
##   press:<fid>     media reaction pieces after notable results (upsets,
##                   streaks, cup progress) with REAL star ratings from the
##                   deterministic fixture replays (Season.fixture_detail)
##   mon:*           coach notes on individual squad members — delighted with
##                   development / unhappy at a lack of battles — with replies
##                   that mutate that mon's real morale value
##   roundup:<YYYY-MM>  monthly league round-up column with awards (Pokémon of
##                   the Month computed from real per-battle ratings)
##
## Everything is deterministic (career_seed + ids), duplicate-guarded by uid,
## generated only via the documented GameState.add_inbox_message API, and all
## extra keys stored on messages are JSON-safe so they persist in the save.

const PAPER := "The Indigo Gazette"
const JOURNALISTS := ["Marin Kessler", "Tobias Wren", "Ada Okafor", "Ren Kowalski",
	"Petra Lindqvist", "Hugo Beaumont"]

const C_GOOD := "57c979"
const C_BAD := "e06060"
const C_WARN := "e0b050"
const C_DIM := "8b91a8"
const C_ACC := "9d92ff"
const C_WHITE := "e8ebf5"

## Coach note cadence: one welfare check every N days from season start.
const NOTE_PERIOD := 12
## An unreplied welfare complaint goes stale after this many days.
const NOTE_WINDOW := 14

var news: RefCounted   # news_gen.gd (money/display helpers, assistant names)


func _init(news_gen: RefCounted) -> void:
	news = news_gen


# ==================================================================== generate

func generate() -> void:
	var have := {}
	for m in GameState.inbox:
		if m.has("uid"):
			have[m["uid"]] = true
	_gen_mind_games(have)
	_gen_press_reactions(have)
	_gen_coach_notes(have)
	_gen_monthly_roundups(have)
	_refresh_flags()


func _add(have: Dictionary, uid: String, date: String, title: String, body: String, extra: Dictionary) -> void:
	if have.has(uid):
		return
	GameState.add_inbox_message(date, title, body)
	var m: Dictionary = GameState.inbox[0]
	m["uid"] = uid
	for k in extra:
		m[k] = extra[k]
	if date < GameState.current_date and not m.get("urgent", false):
		m["read"] = true
	have[uid] = true


## Keep decision flags honest: mind-games stop demanding a reply once the
## match kicks off; welfare notes go stale after their window.
func _refresh_flags() -> void:
	for m in GameState.inbox:
		var uid := str(m.get("uid", ""))
		if uid.begins_with("mind:"):
			if m.get("replied", "") != "":
				m["urgent"] = false
				continue
			var f := _fixture(uid.trim_prefix("mind:"))
			m["urgent"] = not f.is_empty() and not f.get("played", false)
		elif uid.begins_with("monlow:"):
			if m.get("replied", "") != "":
				m["urgent"] = false
				continue
			m["urgent"] = Season.days_between(str(m["date"]), GameState.current_date) <= NOTE_WINDOW


# ------------------------------------------------------------- rival mind-games

func _gen_mind_games(have: Dictionary) -> void:
	var pc: Dictionary = GameState.player_club()
	for f in GameState.player_fixtures():
		var uid := "mind:%s" % f["id"]
		if have.has(uid):
			continue
		var msg_date: String = Season.date_add(str(f["date"]), -2)
		if msg_date < GameState.season_start:
			msg_date = GameState.season_start
		if msg_date > GameState.current_date:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = GameState.career_seed + absi(("mind" + str(f["id"])).hash())
		var we_home: bool = GameState.is_player_club(f["home"])
		var opp: Dictionary = GameState.club(str(f["away"] if we_home else f["home"]))
		if opp.is_empty():
			continue
		var big_tie: bool = str(f["comp"]) == "cup" and int(f.get("round", 1)) >= 3
		var chance := 0.40 + (0.18 if int(opp["reputation"]) >= int(pc["reputation"]) else 0.0)
		if not big_tie and rng.randf() > chance:
			continue
		var tone := _mind_tone(opp, pc)
		var quote := _mind_quote(tone, pc, rng)
		var title: String
		match tone:
			"dismissive":
				title = "Press: %s writes us off ahead of the %s tie" % [opp["manager"], opp["short"]]
			"wary":
				title = "Press: %s piles the pressure on us before %s clash" % [opp["manager"], opp["short"]]
			_:
				title = "Press: %s stokes the fire ahead of our meeting" % opp["manager"]
		_add(have, uid, msg_date, title,
			"Speaking to %s, %s had plenty to say about the upcoming tie." % [PAPER, opp["manager"]],
			{"cat": "media", "sender": "%s (%s Manager)" % [opp["manager"], opp["name"]],
				"fid": str(f["id"]), "opp_id": str(opp["id"]), "tone": tone, "quote": quote,
				"urgent": not f.get("played", false)})


func _mind_tone(opp: Dictionary, pc: Dictionary) -> String:
	var gap := int(opp["reputation"]) - int(pc["reputation"])
	if gap >= 2:
		return "dismissive"
	if gap <= -2:
		return "wary"
	return "spiky"


func _mind_quote(tone: String, pc: Dictionary, rng: RandomNumberGenerator) -> String:
	var banks := {
		"dismissive": [
			"I'll be honest — my staff barely needed a briefing for this one. %s are a decent side on their day, but we prepare the same for everyone. I expect us to win, and win comfortably." % pc["name"],
			"With respect, %s are not the calibre of opposition that keeps me up at night. If my trainers do their jobs, the tie is over by the second battle." % pc["name"],
			"People keep asking me about %s. What is there to say? We are the bigger club, we have the better battlers, and on Saturday everyone will see it." % pc["short"],
		],
		"wary": [
			"Everything favours %s — the budget, the squad depth, the expectation. Nobody gives my boys a chance, and that suits me perfectly. All the pressure is on their manager, not on me." % pc["name"],
			"%s should be winning this — the league expects it, their board expects it. If they slip up against us, that's on them. We travel with nothing to lose." % pc["short"],
			"I watched %s closely. Very talented, yes. But talented squads crack when a smaller club refuses to lie down, and I promise you we will not lie down." % pc["name"],
		],
		"spiky": [
			"We've done our homework on %s. There are holes in that lineup — everyone in the league can see them — and we know exactly where this tie will be won." % pc["short"],
			"Two clubs at our level, so it comes down to nerve. I know my dugout holds its nerve. I'm not sure the same can be said across the hall." ,
			"%s talk a good game in the press. Battles aren't won in the press. Saturday will show whose preparation was real." % pc["short"],
		],
	}
	var bank: Array = banks[tone]
	return str(bank[rng.randi_range(0, bank.size() - 1)])


## The manager's reply to a mind-game — a real, morale-moving decision.
func mind_replies(msg: Dictionary) -> Array:
	var f := _fixture(str(msg.get("fid", "")))
	if f.is_empty() or f.get("played", false) or msg.get("replied", "") != "":
		return []
	return [
		{"kind": "reply", "reply": "fire", "style": "warn", "label": "Fire Back in the Press"},
		{"kind": "reply", "reply": "calm", "style": "good", "label": "Praise Your Squad Instead"},
		{"kind": "reply", "reply": "none", "style": "bad", "label": "No Comment"},
	]


# ------------------------------------------------------------- media reactions

func _gen_press_reactions(have: Dictionary) -> void:
	var pc: Dictionary = GameState.player_club()
	var played: Array = GameState.player_fixtures().filter(func(f): return f.get("played", false))
	played.sort_custom(func(a, b): return str(a["date"]) < str(b["date"]))
	var streak := 0
	for f in played:
		var we_home: bool = GameState.is_player_club(f["home"])
		var us := int(f["score_home"] if we_home else f["score_away"])
		var them := int(f["score_away"] if we_home else f["score_home"])
		var won := us > them
		streak = streak + 1 if won else 0
		var uid := "press:%s" % f["id"]
		if have.has(uid):
			continue
		var opp: Dictionary = GameState.club(str(f["away"] if we_home else f["home"]))
		if opp.is_empty():
			continue
		var gap := int(opp["reputation"]) - int(pc["reputation"])
		var kind := ""
		if str(f["comp"]) == "cup" and won and int(f.get("round", 1)) >= 4:
			kind = "champions"
		elif won and gap >= 3:
			kind = "upset"
		elif str(f["comp"]) == "cup" and won and int(f.get("round", 1)) >= 2:
			kind = "cupwin"
		elif won and (streak == 3 or streak == 5 or streak == 8):
			kind = "streak"
		elif not won and gap <= -3:
			kind = "flop"
		if kind == "":
			continue
		var msg_date: String = Season.date_add(str(f["date"]), 1)
		if msg_date > GameState.current_date:
			msg_date = GameState.current_date
		var jn := _journalist(str(f["id"]))
		var title: String
		match kind:
			"champions":
				title = "\"Immortals\" — %s lift the Indigo Cup" % pc["name"]
			"upset":
				title = "Gazette: %s stun %s in the shock of the season" % [pc["short"], opp["name"]]
			"cupwin":
				title = "Cup fever: %s march into the %s" % [pc["short"], Season.cup_round_name(int(f.get("round", 1)) + 1)]
			"streak":
				title = "%d and counting — the league is talking about %s" % [streak, pc["name"]]
			_:
				title = "Gazette verdict: %s humbled by %s" % [pc["short"], opp["short"]]
		_add(have, uid, msg_date, title,
			"%s reacts to the result in %s." % [jn, PAPER],
			{"cat": "media", "sender": "%s — %s" % [jn, PAPER], "fid": str(f["id"]),
				"press_kind": kind, "streak": streak})


func _journalist(salt: String) -> String:
	return JOURNALISTS[absi((str(GameState.career_seed) + salt).hash()) % JOURNALISTS.size()]


# ------------------------------------------------------------- coach mon notes

func _gen_coach_notes(have: Dictionary) -> void:
	var pc: Dictionary = GameState.player_club()
	var days := Season.days_between(GameState.season_start, GameState.current_date)
	var checkpoint := NOTE_PERIOD
	while checkpoint <= days:
		var date := Season.date_add(GameState.season_start, checkpoint)
		var idx := int(round(float(checkpoint) / NOTE_PERIOD))
		if idx % 2 == 1:
			_gen_unhappy_note(have, date, pc)
		else:
			_gen_delighted_note(have, date, pc)
		checkpoint += NOTE_PERIOD


func _played_club_fixtures(club_id: String, upto: String) -> Array:
	return GameState.fixtures.filter(func(f):
		return f.get("played", false) and str(f["date"]) <= upto \
			and (str(f["home"]) == club_id or str(f["away"]) == club_id))


func _appearances(club_id: String, uid: String, upto: String) -> int:
	var n := 0
	for f in _played_club_fixtures(club_id, upto):
		var d: Dictionary = Season.fixture_detail(f)
		if not d.is_empty() and (d["players"] as Dictionary).has(uid):
			n += 1
	return n


## "Unhappy at the lack of battles" — the coach flags the most starved mon.
func _gen_unhappy_note(have: Dictionary, date: String, pc: Dictionary) -> void:
	var uid := "monlow:%s" % date
	if have.has(uid):
		return
	var club_matches := _played_club_fixtures(str(pc["id"]), date).size()
	if club_matches < 3:
		return
	var worst: Dictionary = {}
	var worst_apps := 99999
	for inst in pc["squad"]:
		var apps := _appearances(str(pc["id"]), str(inst["uid"]), date)
		if apps < worst_apps or (apps == worst_apps and int(inst["level"]) > int(worst.get("level", 0))):
			worst_apps = apps
			worst = inst
	if worst.is_empty() or float(worst_apps) > float(club_matches) / 3.0:
		return  # everyone is getting minutes — no complaint to pass on
	# don't nag about the same mon while an earlier complaint is still open
	for m in GameState.inbox:
		if str(m.get("uid", "")).begins_with("monlow:") and str(m.get("mon_uid", "")) == str(worst["uid"]) \
			and Season.days_between(str(m["date"]), date) < 28:
			return
	_add(have, uid, date,
		"%s is unhappy at the lack of battles" % news.display_name(worst),
		"%s has asked to speak with you about a member of the squad." % _coach_name(pc),
		{"cat": "staff", "sender": _coach_name(pc), "mon_uid": str(worst["uid"]),
			"apps": worst_apps, "club_matches": club_matches, "urgent": true})


## "Delighted with development" — the coach singles out the form battler.
func _gen_delighted_note(have: Dictionary, date: String, pc: Dictionary) -> void:
	var uid := "monstar:%s" % date
	if have.has(uid):
		return
	var best: Dictionary = {}
	var best_rating := 0.0
	var best_log: Array = []
	for inst in pc["squad"]:
		var log := Season.pokemon_match_log(str(inst["uid"]), str(pc["id"]),
			GameState.fixtures.filter(func(f): return str(f["date"]) <= date))
		if log.size() < 2:
			continue
		var recent: Array = log.slice(maxi(0, log.size() - 4))
		var avg := 0.0
		for e in recent:
			avg += float(e["rating"])
		avg /= recent.size()
		if avg > best_rating:
			best_rating = avg
			best = inst
			best_log = recent
	if best.is_empty() or best_rating < 6.9:
		return
	for m in GameState.inbox:
		if str(m.get("uid", "")).begins_with("monstar:") and str(m.get("mon_uid", "")) == str(best["uid"]) \
			and Season.days_between(str(m["date"]), date) < 35:
			return
	var kos := 0
	for e in best_log:
		kos += int(e["kos"])
	_add(have, uid, date,
		"%s is delighted with %s's development" % [_coach_first_name(pc), news.display_name(best)],
		"A glowing progress note from the coaching staff.",
		{"cat": "staff", "sender": _coach_name(pc), "mon_uid": str(best["uid"]),
			"rating": snappedf(best_rating, 0.01), "recent_kos": kos, "recent_n": best_log.size()})


func _coach_name(pc: Dictionary) -> String:
	for s in pc.get("staff", []):
		if str(s["role"]) == "coach":
			return "%s (Coach)" % s["name"]
	return "Head Coach"


func _coach_first_name(pc: Dictionary) -> String:
	var full := _coach_name(pc).split(" (")[0]
	return full.split(" ")[0]


# ------------------------------------------------------------- monthly round-up

func _gen_monthly_roundups(have: Dictionary) -> void:
	var boundary := "%s-01" % str(GameState.season_start).substr(0, 7)
	for i in 14:
		boundary = "%s-01" % Season.date_add(boundary, 32).substr(0, 7)
		if boundary > GameState.current_date:
			return
		_gen_roundup(have, boundary, Season.date_add(boundary, -1).substr(0, 7))


func _gen_roundup(have: Dictionary, boundary: String, month_key: String) -> void:
	var uid := "roundup:%s" % month_key
	if have.has(uid):
		return
	var in_month: Array = GameState.fixtures.filter(func(f):
		return f.get("played", false) and str(f["date"]).begins_with(month_key))
	var league_n := in_month.filter(func(f): return str(f["comp"]) == "league").size()
	if league_n < 4:
		return

	# ---- club-of-the-month records (league only) + biggest upset
	var recs := {}
	var upset := {}
	var upset_gap := 0
	for f in in_month:
		var h := str(f["home"])
		var a := str(f["away"])
		var hw: bool = int(f["score_home"]) > int(f["score_away"])
		if str(f["comp"]) == "league":
			for cid in [h, a]:
				if not recs.has(cid):
					recs[cid] = {"won": 0, "lost": 0, "bf": 0, "ba": 0}
			recs[h]["bf"] += int(f["score_home"])
			recs[h]["ba"] += int(f["score_away"])
			recs[a]["bf"] += int(f["score_away"])
			recs[a]["ba"] += int(f["score_home"])
			recs[h]["won" if hw else "lost"] += 1
			recs[a]["lost" if hw else "won"] += 1
		var wc: Dictionary = GameState.club(h if hw else a)
		var lc: Dictionary = GameState.club(a if hw else h)
		if not wc.is_empty() and not lc.is_empty():
			var gap := int(lc["reputation"]) - int(wc["reputation"])
			if gap > upset_gap:
				upset_gap = gap
				upset = {"winner": str(wc["name"]), "loser": str(lc["name"]), "gap": gap,
					"score": "%d-%d" % [int(f["score_home"]), int(f["score_away"])],
					"date": str(f["date"]), "comp": str(f["comp"])}
	var totm_id := ""
	for cid in recs:
		if totm_id == "":
			totm_id = cid
			continue
		var x: Dictionary = recs[cid]
		var y: Dictionary = recs[totm_id]
		var dx: int = x["won"] * 3 + (x["bf"] - x["ba"])
		var dy: int = y["won"] * 3 + (y["bf"] - y["ba"])
		if dx > dy or (dx == dy and str(cid) < totm_id):
			totm_id = cid
	var totm := {}
	if totm_id != "":
		totm = {"club": str(GameState.club(totm_id)["name"]), "club_id": totm_id,
			"won": int(recs[totm_id]["won"]), "lost": int(recs[totm_id]["lost"])}

	# ---- Pokémon of the Month: aggregate the REAL replay ratings of every
	# battler in every fixture played this month, league and cup alike
	var agg := {}
	for f in in_month:
		var d: Dictionary = Season.fixture_detail(f)
		if d.is_empty():
			continue
		var players: Dictionary = d["players"]
		for puid in players:
			var p: Dictionary = players[puid]
			var cid := str(f["home"] if int(p["side"]) == 0 else f["away"])
			if not agg.has(puid):
				agg[puid] = {"name": str(p["name"]), "species": str(p["species"]),
					"club_id": cid, "battles": 0, "kos": 0, "dmg": 0, "rating_sum": 0.0}
			var a2: Dictionary = agg[puid]
			a2["battles"] += int(p["battles"])
			a2["kos"] += int(p["kos"])
			a2["dmg"] += int(p["dmg"])
			a2["rating_sum"] += float(p["rating_sum"])
	var ranked: Array = []
	for puid in agg:
		var a3: Dictionary = agg[puid]
		if int(a3["battles"]) >= 4:
			ranked.append(a3)
	if ranked.is_empty():
		for puid in agg:
			ranked.append(agg[puid])
	ranked.sort_custom(func(x, y):
		var rx: float = float(x["rating_sum"]) / maxi(int(x["battles"]), 1)
		var ry: float = float(y["rating_sum"]) / maxi(int(y["battles"]), 1)
		if not is_equal_approx(rx, ry):
			return rx > ry
		return int(x["kos"]) > int(y["kos"]))
	var podium: Array = []
	for a4 in ranked.slice(0, 3):
		var club: Dictionary = GameState.club(str(a4["club_id"]))
		podium.append({"name": str(a4["name"]), "species": str(a4["species"]),
			"club": str(club.get("short", "?")), "club_name": str(club.get("name", "?")),
			"mine": GameState.is_player_club(str(a4["club_id"])),
			"battles": int(a4["battles"]), "kos": int(a4["kos"]), "dmg": int(a4["dmg"]),
			"rating": snappedf(float(a4["rating_sum"]) / maxi(int(a4["battles"]), 1), 0.01)})

	# ---- our month + the leader when the books closed
	var pid: String = str(GameState.world["meta"]["player_club_id"])
	var our: Dictionary = recs.get(pid, {"won": 0, "lost": 0, "bf": 0, "ba": 0})
	var upto: Array = GameState.fixtures.filter(func(f):
		return f.get("played", false) and str(f["date"]) < boundary)
	var table := Season.compute_table(GameState.club_ids(), upto)
	var leader := ""
	var our_pos := 0
	if not table.is_empty():
		leader = str(GameState.club(str(table[0]["club_id"]))["name"])
		for i in table.size():
			if GameState.is_player_club(str(table[i]["club_id"])):
				our_pos = i + 1

	var mname: String = _month_name(month_key)
	var pom_line := ""
	if not podium.is_empty():
		pom_line = "%s (%s)" % [podium[0]["name"], podium[0]["club"]]
	_add(have, uid, boundary,
		"League Review — %s: Pokémon of the Month is %s" % [mname, pom_line],
		"%s's monthly column: awards, the table and the stories of %s." % [PAPER, mname],
		{"cat": "media", "sender": "%s — %s" % [_journalist("roundup" + month_key), PAPER],
			"month": month_key, "podium": podium, "totm": totm, "upset": upset,
			"our_won": int(our["won"]), "our_lost": int(our["lost"]),
			"leader": leader, "our_pos": our_pos, "league_n": league_n})


func _month_name(month_key: String) -> String:
	var names := ["", "January", "February", "March", "April", "May", "June",
		"July", "August", "September", "October", "November", "December"]
	return "%s %s" % [names[int(month_key.split("-")[1])], month_key.substr(0, 4)]


# ==================================================================== replies

## Apply a reply choice to a people message. Mutates real morale values and
## records the outcome on the message. Returns {note, good}.
func apply_reply(msg: Dictionary, action: Dictionary) -> Dictionary:
	if msg.get("replied", "") != "":
		return {"note": "You have already responded to this.", "good": false}
	var choice := str(action.get("reply", ""))
	var uid := str(msg.get("uid", ""))
	var out := {"note": "", "good": true}
	if uid.begins_with("mind:"):
		out = _apply_mind_reply(msg, choice)
	elif uid.begins_with("monlow:"):
		out = _apply_unhappy_reply(msg, choice)
	elif uid.begins_with("monstar:"):
		out = _apply_star_reply(msg, choice)
	msg["replied"] = choice
	msg["reply_note"] = str(out["note"])
	msg["reply_good"] = bool(out["good"])
	msg["urgent"] = false
	GameState.save_game()
	return out


func _apply_mind_reply(msg: Dictionary, choice: String) -> Dictionary:
	var pc: Dictionary = GameState.player_club()
	var opp: Dictionary = GameState.club(str(msg.get("opp_id", "")))
	var opp_name := str(opp.get("manager", "the rival manager"))
	match choice:
		"fire":
			var rng := RandomNumberGenerator.new()
			rng.seed = GameState.career_seed + absi(("reply" + str(msg.get("fid", ""))).hash())
			if rng.randf() < 0.65:
				_shift_squad_morale(pc, 3)
				return {"note": "Your response makes the back page — the squad walks taller in training (morale +3 across the squad).", "good": true}
			_shift_squad_morale(pc, -2)
			return {"note": "The exchange rattles the dressing room — some battlers look tense in training (morale -2 across the squad).", "good": false}
		"calm":
			_shift_squad_morale(pc, 1)
			return {"note": "You turn the question into public praise of your own squad (morale +1 across the squad). %s got no reaction." % opp_name, "good": true}
		_:
			return {"note": "No comment. The story dies by the weekend — and the squad takes its cue from the match, not the papers.", "good": true}


func _apply_unhappy_reply(msg: Dictionary, choice: String) -> Dictionary:
	var inst := GameState.squad_member(str(msg.get("mon_uid", "")))
	if inst.is_empty():
		return {"note": "That battler is no longer at the club.", "good": false}
	var before := int(inst.get("morale", 70))
	match choice:
		"promise":
			inst["morale"] = mini(100, before + 8)
			return {"note": "You promise %s a run of battles. Morale %d → %d — the coaches will hold you to it." %
				[news.display_name(inst), before, int(inst["morale"])], "good": true}
		_:
			inst["morale"] = maxi(0, before - 5)
			return {"note": "You tell %s to earn the shirt in training. Morale %d → %d — a gamble on their character." %
				[news.display_name(inst), before, int(inst["morale"])], "good": false}


func _apply_star_reply(msg: Dictionary, choice: String) -> Dictionary:
	var inst := GameState.squad_member(str(msg.get("mon_uid", "")))
	if inst.is_empty():
		return {"note": "That battler is no longer at the club.", "good": false}
	var before := int(inst.get("morale", 70))
	match choice:
		"praise":
			inst["morale"] = mini(100, before + 4)
			return {"note": "You pass on the praise personally. %s's morale %d → %d." %
				[news.display_name(inst), before, int(inst["morale"])], "good": true}
		_:
			inst["morale"] = maxi(0, before - 1)
			return {"note": "You keep the praise in-house — no complacency here. Morale %d → %d." %
				[before, int(inst["morale"])], "good": true}


func _shift_squad_morale(pc: Dictionary, delta: int) -> void:
	for inst in pc["squad"]:
		inst["morale"] = clampi(int(inst.get("morale", 70)) + delta, 0, 100)


# ==================================================================== render

## -> {"bbcode": String, "actions": Array, "banner": Dictionary}
func render(msg: Dictionary) -> Dictionary:
	var uid := str(msg.get("uid", ""))
	if uid.begins_with("mind:"):
		return _render_mind(msg)
	if uid.begins_with("press:"):
		return _render_press(msg)
	if uid.begins_with("monlow:"):
		return _render_unhappy(msg)
	if uid.begins_with("monstar:"):
		return _render_star(msg)
	if uid.begins_with("roundup:"):
		return _render_roundup(msg)
	return {"bbcode": "[color=#%s]%s[/color]" % [C_WHITE, str(msg.get("body", ""))],
		"actions": [], "banner": {}}


func _reply_block(msg: Dictionary) -> String:
	if msg.get("replied", "") == "":
		return ""
	var col := C_GOOD if msg.get("reply_good", true) else C_WARN
	return "\n[color=#%s][b]YOUR RESPONSE[/b][/color]\n[color=#%s]%s[/color]\n" % \
		[C_DIM, col, str(msg.get("reply_note", ""))]


# ------------------------------------------------------------- mind-games

func _render_mind(msg: Dictionary) -> Dictionary:
	var f := _fixture(str(msg.get("fid", "")))
	var opp: Dictionary = GameState.club(str(msg.get("opp_id", "")))
	if f.is_empty() or opp.is_empty():
		return {"bbcode": "[color=#%s]%s[/color]" % [C_WHITE, str(msg.get("body", ""))], "actions": [], "banner": {}}
	var pc: Dictionary = GameState.player_club()
	var we_home: bool = GameState.is_player_club(f["home"])
	var comp_line: String = ("%s · Matchday %d" % [GameState.world["meta"]["league_name"], int(f["round"])]) \
		if str(f["comp"]) == "league" else ("Indigo Cup · %s" % Season.cup_round_name(int(f["round"])))

	var bb := "[color=#%s]%s · %s · %s[/color]\n\n" % \
		[C_DIM, comp_line, Season.pretty_date(str(f["date"])), "we host" if we_home else "we travel"]
	bb += "[color=#%s]Speaking to %s ahead of the tie, [b]%s[/b] (%s, %s, reputation %d/20) went on the record:[/color]\n\n" % \
		[C_WHITE, PAPER, opp["manager"], opp["name"], _pos_text(str(opp["id"])), int(opp["reputation"])]
	bb += "[color=#%s][b]\"%s\"[/b][/color]\n\n" % [C_ACC, str(msg.get("quote", ""))]

	# the facts under the noise — real form and standings
	var our_form := Season.club_form(str(pc["id"]), GameState.fixtures, 5)
	var their_form := Season.club_form(str(opp["id"]), GameState.fixtures, 5)
	bb += "[color=#%s][b]THE FACTS[/b][/color]\n" % C_DIM
	bb += "[color=#%s]%s form:[/color]  %s\n" % [C_DIM, pc["short"], _form_bb(our_form)]
	bb += "[color=#%s]%s form:[/color]  %s\n" % [C_DIM, opp["short"], _form_bb(their_form)]
	var morale := _avg_squad_morale(pc)
	bb += "[color=#%s]Squad morale:[/color] [color=#%s][b]%d/100[/b][/color]\n" % \
		[C_DIM, C_GOOD if morale >= 75 else (C_WARN if morale >= 55 else C_BAD), morale]

	if f.get("played", false):
		var us := int(f["score_home"] if we_home else f["score_away"])
		var them := int(f["score_away"] if we_home else f["score_home"])
		bb += "\n[color=#%s]The match has since been played — we %s %d-%d. The talking is over.[/color]\n" % \
			[C_GOOD if us > them else C_BAD, "won" if us > them else "lost", us, them]
	elif msg.get("replied", "") == "":
		bb += "\n[color=#%s][b]The press pack wants your response before kick-off. How you answer will reach the dressing room.[/b][/color]\n" % C_WARN
	bb += _reply_block(msg)

	var actions: Array = mind_replies(msg)
	actions.append({"label": "Go to Fixture", "screen": "competition"})
	actions.append({"label": "Tactics", "screen": "tactics"})
	return {"bbcode": bb, "actions": actions, "banner": {}}


func _form_bb(form: Array) -> String:
	if form.is_empty():
		return "[color=#%s]no matches yet[/color]" % C_DIM
	var out := ""
	for r in form:
		out += "[color=#%s][b] %s [/b][/color]" % [C_GOOD if str(r) == "W" else C_BAD, str(r)]
	return out


func _avg_squad_morale(pc: Dictionary) -> int:
	var total := 0
	var n := 0
	for inst in pc["squad"]:
		total += int(inst.get("morale", 70))
		n += 1
	return int(round(float(total) / maxi(n, 1)))


# ------------------------------------------------------------- press pieces

func _render_press(msg: Dictionary) -> Dictionary:
	var f := _fixture(str(msg.get("fid", "")))
	if f.is_empty():
		return {"bbcode": "[color=#%s]%s[/color]" % [C_WHITE, str(msg.get("body", ""))], "actions": [], "banner": {}}
	var pc: Dictionary = GameState.player_club()
	var we_home: bool = GameState.is_player_club(f["home"])
	var home: Dictionary = GameState.club(str(f["home"]))
	var away: Dictionary = GameState.club(str(f["away"]))
	var opp: Dictionary = away if we_home else home
	var us := int(f["score_home"] if we_home else f["score_away"])
	var them := int(f["score_away"] if we_home else f["score_home"])
	var won := us > them
	var kind := str(msg.get("press_kind", ""))
	var comp_line: String = ("%s · Matchday %d" % [GameState.world["meta"]["league_name"], int(f["round"])]) \
		if str(f["comp"]) == "league" else ("Indigo Cup · %s" % Season.cup_round_name(int(f["round"])))

	var bb := "[color=#%s][i]An opinion piece in %s.[/i][/color]\n\n" % [C_DIM, PAPER]
	match kind:
		"champions":
			bb += "[color=#%s]They will sing about this one for years. [b]%s[/b] beat %s %d-%d in the Indigo Cup Final and the trophy is theirs. Whatever happens in the league now, this season is already immortal.[/color]\n\n" % \
				[C_WHITE, pc["name"], opp["name"], us, them]
		"upset":
			bb += "[color=#%s]Nobody outside the %s dressing room saw this coming. A club with a reputation of %d/20 dismantling [b]%s[/b] (%d/20) by %d-%d is the kind of result that changes how a league talks about you. %s's side played without fear — and the giants blinked first.[/color]\n\n" % \
				[C_WHITE, pc["short"], int(pc["reputation"]), opp["name"], int(opp["reputation"]), us, them, pc["manager"]]
		"cupwin":
			bb += "[color=#%s]The cup run is alive. [b]%s[/b] saw off %s %d-%d in the %s, and the draw for the %s suddenly matters a great deal in this corner of the league.[/color]\n\n" % \
				[C_WHITE, pc["name"], opp["name"], us, them, Season.cup_round_name(int(f["round"])),
				Season.cup_round_name(int(f["round"]) + 1)]
		"streak":
			bb += "[color=#%s][b]%d wins in a row.[/b] Streaks like this are not luck — they are structure, squad depth and a dugout that trusts itself. %s made it %d straight by beating %s %d-%d, and the chasing pack has noticed.[/color]\n\n" % \
				[C_WHITE, int(msg.get("streak", 3)), pc["name"], int(msg.get("streak", 3)), opp["name"], us, them]
		_:
			bb += "[color=#%s]There is no dressing this up. [b]%s[/b] (reputation %d/20) were beaten %d-%d by %s (%d/20) — a side they were built, budgeted and expected to beat. Questions travel fast in this league, and today they are all pointed at %s's office.[/color]\n\n" % \
				[C_WHITE, pc["name"], int(pc["reputation"]), them, us, opp["name"], int(opp["reputation"]), pc["manager"]]

	# the real star of the tie, from the deterministic replay
	var star := _fixture_star(f, 0 if we_home else 1)
	if not star.is_empty():
		bb += "[color=#%s][b]%s OF THE MATCH[/b][/color]\n" % [C_DIM, "STAR" if won else "ONE BRIGHT SPOT"]
		bb += "[color=#%s][b]%s[/b][/color] [color=#%s](%s) — %d KO%s, %d damage across %d battle%s. Match rating [/color][color=#%s][b]%.1f[/b][/color]\n\n" % \
			[C_ACC, star["name"], C_DIM, star["species"], star["kos"], "" if int(star["kos"]) == 1 else "s",
			star["dmg"], star["battles"], "" if int(star["battles"]) == 1 else "s",
			C_GOOD if float(star["rating"]) >= 7.5 else C_WHITE, star["rating"]]

	var pos := GameState.player_table_position()
	if pos > 0 and str(f["comp"]) == "league":
		bb += "[color=#%s]%s currently sit [b]%s[/b] in the %s.[/color]\n" % \
			[C_DIM, pc["short"], _ordinal(pos), GameState.world["meta"]["league_name"]]
	bb += "\n[color=#%s]— %s[/color]" % [C_DIM, str(msg.get("sender", PAPER))]

	return {"bbcode": bb,
		"actions": [{"label": "Go to Fixture", "screen": "competition"},
			{"label": "View Squad", "screen": "squad"}],
		"banner": {"home": home["name"], "away": away["name"],
			"sh": int(f["score_home"]), "sa": int(f["score_away"]),
			"comp": comp_line + " · " + Season.pretty_date(str(f["date"])), "won": won}}


## Best-rated battler in a fixture replay; side -1 = either side.
func _fixture_star(f: Dictionary, side: int) -> Dictionary:
	var d: Dictionary = Season.fixture_detail(f)
	if d.is_empty():
		return {}
	var best := {}
	var best_r := 0.0
	var players: Dictionary = d["players"]
	for puid in players:
		var p: Dictionary = players[puid]
		if side >= 0 and int(p["side"]) != side:
			continue
		var r: float = float(p["rating_sum"]) / maxi(int(p["battles"]), 1)
		if r > best_r:
			best_r = r
			best = {"name": str(p["name"]), "species": str(p["species"]), "kos": int(p["kos"]),
				"dmg": int(p["dmg"]), "battles": int(p["battles"]), "rating": snappedf(r, 0.01)}
	return best


# ------------------------------------------------------------- coach notes

func _render_unhappy(msg: Dictionary) -> Dictionary:
	var inst := GameState.squad_member(str(msg.get("mon_uid", "")))
	if inst.is_empty():
		return {"bbcode": "[color=#%s]That battler has since left the club — the matter is closed.[/color]" % C_DIM,
			"actions": [{"label": "View Squad", "screen": "squad"}], "banner": {}}
	var apps := int(msg.get("apps", 0))
	var cm := int(msg.get("club_matches", 0))
	var morale := int(inst.get("morale", 70))
	var bb := "[color=#%s]Boss — a quiet word before this becomes a loud one.[/color]\n\n" % C_WHITE
	bb += "[color=#%s][b]%s[/b][/color] [color=#%s](%s, Lv %d) has featured in [b]%d of our %d[/b] matches this season. The mood around the training pens is turning: less appetite in drills, snapping at the younger battlers. In my experience this only goes one way if it's left alone.[/color]\n\n" % \
		[C_ACC, news.display_name(inst), C_WHITE, inst["species"], int(inst["level"]), apps, cm]
	bb += "[color=#%s][b]CURRENT MORALE[/b][/color]  [color=#%s][b]%d/100[/b][/color]     [color=#%s][b]CONDITION[/b][/color]  [color=#%s]%d[/color]     [color=#%s][b]WAGES[/b][/color]  [color=#%s]%s / mo[/color]\n\n" % \
		[C_DIM, C_BAD if morale < 60 else C_WARN, morale,
		C_DIM, C_WHITE, int(inst.get("condition", 100)),
		C_DIM, C_WHITE, news.money(int(inst["contract"]["salary"]))]
	if msg.get("replied", "") == "":
		if bool(msg.get("urgent", false)):
			bb += "[color=#%s][b]They are waiting on a message from you. What do I tell them?[/b][/color]\n" % C_WARN
		else:
			bb += "[color=#%s]You let it slide — the mood in the gym cooled on its own, but the coach noted your silence.[/color]\n" % C_DIM
	bb += _reply_block(msg)

	var actions: Array = []
	if msg.get("replied", "") == "" and bool(msg.get("urgent", false)):
		actions = [
			{"kind": "reply", "reply": "promise", "style": "good", "label": "Promise More Battles (+morale)"},
			{"kind": "reply", "reply": "patient", "style": "bad", "label": "Tell Them to Earn It (-morale)"},
		]
	actions.append({"label": "View Squad", "screen": "squad"})
	actions.append({"label": "Training", "screen": "training"})
	return {"bbcode": bb, "actions": actions, "banner": {}}


func _render_star(msg: Dictionary) -> Dictionary:
	var inst := GameState.squad_member(str(msg.get("mon_uid", "")))
	if inst.is_empty():
		return {"bbcode": "[color=#%s]That battler has since left the club.[/color]" % C_DIM,
			"actions": [{"label": "View Squad", "screen": "squad"}], "banner": {}}
	var rating := float(msg.get("rating", 7.0))
	var bb := "[color=#%s]Boss — thought you'd want this one in writing.[/color]\n\n" % C_WHITE
	bb += "[color=#%s][b]%s[/b][/color] [color=#%s](%s, Lv %d) has been outstanding. Across the last [b]%d[/b] matches: [b]%d KOs[/b] and an average match rating of [/color][color=#%s][b]%.2f[/b][/color][color=#%s]. Technique, timing, temperament — everything we drill is showing up on matchday.[/color]\n\n" % \
		[C_ACC, news.display_name(inst), C_WHITE, inst["species"], int(inst["level"]),
		int(msg.get("recent_n", 3)), int(msg.get("recent_kos", 0)), C_GOOD, rating, C_WHITE]
	bb += "[color=#%s][b]CURRENT MORALE[/b][/color]  [color=#%s][b]%d/100[/b][/color]     [color=#%s][b]FITNESS[/b][/color]  [color=#%s]%d[/color]\n\n" % \
		[C_DIM, C_GOOD, int(inst.get("morale", 70)), C_DIM, C_WHITE, int(inst.get("fitness", 100))]
	if msg.get("replied", "") == "":
		bb += "[color=#%s]Development like this deserves a word from the manager — your call how loud that word is.[/color]\n" % C_DIM
	bb += _reply_block(msg)

	var actions: Array = []
	if msg.get("replied", "") == "":
		actions = [
			{"kind": "reply", "reply": "praise", "style": "good", "label": "Pass On Your Praise (+morale)"},
			{"kind": "reply", "reply": "grounded", "style": "warn", "label": "Keep Them Grounded"},
		]
	actions.append({"label": "View Squad", "screen": "squad"})
	return {"bbcode": bb, "actions": actions, "banner": {}}


# ------------------------------------------------------------- monthly column

func _render_roundup(msg: Dictionary) -> Dictionary:
	var mname := _month_name(str(msg.get("month", "")))
	var bb := "[color=#%s][i]%s's monthly league column.[/i][/color]\n\n" % [C_DIM, PAPER]
	bb += "[color=#%s]The books are closed on [b]%s[/b] — %d league matchdays of it. Here is how the month will be remembered.[/color]\n\n" % \
		[C_WHITE, mname, int(msg.get("league_n", 0))]

	# --- Pokémon of the Month podium (real replay ratings)
	var podium: Array = msg.get("podium", [])
	if not podium.is_empty():
		bb += "[color=#%s][b]POKÉMON OF THE MONTH[/b][/color]\n" % C_WARN
		var medals := ["1st", "2nd", "3rd"]
		for i in podium.size():
			var p: Dictionary = podium[i]
			var name_col := C_ACC if bool(p.get("mine", false)) else C_WHITE
			bb += "[color=#%s]%s[/color]  [color=#%s][b]%s[/b][/color] [color=#%s](%s, %s) — %d battles, %d KOs, %d dmg · avg rating [/color][color=#%s][b]%.2f[/b][/color]%s\n" % \
				[C_DIM, medals[i], name_col, str(p["name"]), C_DIM, str(p["species"]), str(p["club"]),
				int(p["battles"]), int(p["kos"]), int(p["dmg"]),
				C_GOOD if float(p["rating"]) >= 7.0 else C_WHITE, float(p["rating"]),
				"  [color=#%s][b]← OURS[/b][/color]" % C_GOOD if bool(p.get("mine", false)) else ""]
		var w: Dictionary = podium[0]
		bb += "[color=#%s]\"%s was simply a level above everything else on the circuit this month.\"[/color]\n\n" % \
			[C_DIM, str(w["name"])]

	# --- Team of the Month
	var totm: Dictionary = msg.get("totm", {})
	if not totm.is_empty():
		var mine: bool = GameState.is_player_club(str(totm.get("club_id", "")))
		bb += "[color=#%s][b]TEAM OF THE MONTH[/b][/color]  [color=#%s][b]%s[/b][/color] [color=#%s](%d-%d in the league)%s[/color]\n" % \
			[C_WARN, C_ACC if mine else C_WHITE, str(totm["club"]), C_DIM,
			int(totm["won"]), int(totm["lost"]), " — yes, YOUR team" if mine else ""]

	# --- upset of the month
	var upset: Dictionary = msg.get("upset", {})
	if not upset.is_empty():
		bb += "[color=#%s][b]SHOCK OF THE MONTH[/b][/color]  [color=#%s]%s toppling %s (%s, %s) — a %d-point reputation gap bridged in an afternoon.[/color]\n" % \
			[C_WARN, C_WHITE, str(upset["winner"]), str(upset["loser"]), str(upset["score"]),
			Season.pretty_date(str(upset["date"])), int(upset["gap"])]

	# --- the state of the race + our month
	bb += "\n[color=#%s][b]THE TABLE[/b][/color]  [color=#%s][b]%s[/b] led the league as the month closed" % \
		[C_DIM, C_WHITE, str(msg.get("leader", "?"))]
	var our_pos := int(msg.get("our_pos", 0))
	if our_pos > 0:
		bb += "; %s sat [b]%s[/b]" % [GameState.player_club()["short"], _ordinal(our_pos)]
	bb += ".[/color]\n"
	var ow := int(msg.get("our_won", 0))
	var ol := int(msg.get("our_lost", 0))
	var our_col := C_GOOD if ow > ol else (C_WARN if ow == ol else C_BAD)
	bb += "[color=#%s][b]OUR MONTH[/b][/color]  [color=#%s][b]%d won, %d lost[/b] in the league — %s.[/color]\n" % \
		[C_DIM, our_col, ow, ol,
		"a month to build on" if ow > ol else ("honours even" if ow == ol else "a month to forget")]
	bb += "\n[color=#%s]— %s[/color]" % [C_DIM, str(msg.get("sender", PAPER))]
	return {"bbcode": bb,
		"actions": [{"label": "League Table", "screen": "competition"},
			{"label": "View Squad", "screen": "squad"}], "banner": {}}


# ==================================================================== helpers

func _fixture(fid: String) -> Dictionary:
	if fid == "":
		return {}
	for f in GameState.fixtures:
		if str(f["id"]) == fid:
			return f
	return {}


func _pos_text(club_id: String) -> String:
	var t: Array = GameState.league_table()
	for i in t.size():
		if str(t[i]["club_id"]) == club_id:
			if int(t[i]["played"]) == 0:
				return "yet to play in the league"
			return "%s in the league" % _ordinal(i + 1)
	return "unranked"


func _ordinal(n: int) -> String:
	if n <= 0:
		return "—"
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1: suffix = "st"
			2: suffix = "nd"
			3: suffix = "rd"
	return "%d%s" % [n, suffix]
