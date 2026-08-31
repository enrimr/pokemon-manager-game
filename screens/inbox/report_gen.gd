extends RefCounted
## Inbox piece: renders rich message bodies (BBCode) + banners + actions.
## Match reports are reconstructed by deterministically re-running the exact
## battle simulation GameState used (same seeds), so key events and star
## performers are the REAL events of that match, not flavour text.

const C_GOOD := "57c979"
const C_BAD := "e06060"
const C_WARN := "e0b050"
const C_DIM := "8b91a8"
const C_ACC := "9d92ff"
const C_WHITE := "e8ebf5"

var news: RefCounted           # news_gen.gd instance (shared helpers)
var board: RefCounted          # board_room.gd instance (set by screen.gd)
var economy: RefCounted        # economy.gd instance (set by screen.gd)
var people: RefCounted         # people_gen.gd instance (set by screen.gd)
var evolutions: RefCounted     # evolution_gen.gd instance (set by screen.gd)
var _resim_cache: Dictionary = {}
var _academy_gen: RefCounted   # academy mail renderer (lazy, defensive)
var _academy_tried := false


func _init(news_gen: RefCounted) -> void:
	news = news_gen


## -> {"bbcode": String, "actions": [{"label","screen"}], "banner": Dictionary}
func render(msg: Dictionary) -> Dictionary:
	var uid := str(msg.get("uid", ""))
	# evolution approval flow / staff hints / transformation reports
	if evolutions != null and (uid.begins_with("evo:") or str(msg.get("kind", "")).begins_with("evo_")):
		return evolutions.render(msg)
	# academy piece's rich mail (intake-day reports, promotions, board asks):
	# route to its renderer if the academy screen is installed.
	if uid.begins_with("academy:") or msg.has("academy_kind"):
		var ag := _academy()
		if ag != null:
			return ag.render(msg)
	match str(msg.get("cat", "")):
		"match":
			if uid.begins_with("prematch:"):
				return _prematch(msg)
			return _match_report(msg)
		"cup":
			return _cup_draw(msg)
		"scout":
			return _scout_report(msg)
		"transfer":
			return _transfer_offer(msg)
		"media", "staff":
			if people != null:
				return people.render(msg)
			return _plain(msg)
		"board":
			if uid == "board:preseason" or uid == "board:welcome":
				return _board_preseason(msg)
			if uid.begins_with("boardreq:"):
				return _board_request_ack(msg)
			if uid.begins_with("boarddec:"):
				return _board_decision(msg)
			if uid.begins_with("finrep:"):
				return _finance_report(msg)
			# ONLY genuine monthly reviews get the review card — everything else
			# that fell into the "board" bucket (season-end awards, season
			# review, off-season note, board ultimatums...) keeps its own body.
			if uid.begins_with("board:") or str(msg.get("title", "")).begins_with("Board review"):
				return _board_review(msg)
			return _season_or_plain(msg)
	return _plain(msg)


## Plain body, plus a History deep link for the season-end mail family.
func _season_or_plain(msg: Dictionary) -> Dictionary:
	var out := _plain(msg)
	var title := str(msg.get("title", ""))
	if title.begins_with("End-of-Season Awards") or title.begins_with("Off-season:") \
			or title.begins_with(I18n.t("Off-season:")) \
			or (title.begins_with("Season ") and title.contains("review:")) \
			or (title.begins_with(I18n.t("Season "))):
		out["actions"] = [{"label": I18n.t("Honours & History"), "screen": "competition", "tab": "history"}]
	return out


func _plain(msg: Dictionary) -> Dictionary:
	return {"bbcode": "[color=#%s]%s[/color]" % [C_WHITE, str(msg.get("body", ""))],
		"actions": [], "banner": {}}


## Lazy, defensive handle on the academy piece's mail renderer — the inbox
## keeps working unchanged if that screen is absent.
func _academy() -> RefCounted:
	if not _academy_tried:
		_academy_tried = true
		if ResourceLoader.exists("res://screens/academy/mail_gen.gd"):
			var scr = load("res://screens/academy/mail_gen.gd")
			if scr != null:
				_academy_gen = scr.new()
	return _academy_gen


# ------------------------------------------------------------- match report

func _match_report(msg: Dictionary) -> Dictionary:
	var f := _fixture(msg.get("fid", ""))
	if f.is_empty():
		return _plain(msg)
	var we_home: bool = GameState.is_player_club(f["home"])
	var home: Dictionary = GameState.club(f["home"])
	var away: Dictionary = GameState.club(f["away"])
	var opp: Dictionary = away if we_home else home
	var us: int = f["score_home"] if we_home else f["score_away"]
	var them: int = f["score_away"] if we_home else f["score_home"]
	var won := us > them
	var comp_line: String = (I18n.t("%s · Matchday %d") % [I18n.t(GameState.world["meta"]["league_name"]), int(f["round"])]) \
		if f["comp"] == "league" else ("%s · %s" % [I18n.t("Indigo Cup"), I18n.cup_round(int(f["round"]))])

	var bb := ""
	bb += _prose_result(f, we_home, us, them, opp) + "\n\n"

	var sim := _resim(f)
	var player_side := 0 if we_home else 1
	if not sim.is_empty():
		bb += I18n.t("[color=#%s][b]BATTLE BY BATTLE[/b][/color]\n") % C_DIM
		var battles: Array = sim["battles"]
		for i in battles.size():
			var b: Dictionary = battles[i]
			var w_us: bool = b["winner"] == player_side
			var wcol := C_GOOD if w_us else C_BAD
			var line := I18n.t("[color=#%s]● Battle %d — %s[/color] [color=#%s]in %d turns") % \
				[wcol, i + 1, I18n.t("WON") if w_us else I18n.t("LOST"), C_DIM, b["turns"]]
			var last_ko: Dictionary = b["kos"].back() if not (b["kos"] as Array).is_empty() else {}
			if not last_ko.is_empty():
				line += I18n.t(" · %s sealed it, KO'ing %s with %s") % \
					[last_ko.get("by", "?"), last_ko["victim"], I18n.t(str(last_ko.get("move", "a final blow")))]
			bb += line + "[/color]"
			var wline := _weather_line(b)
			if wline != "":
				bb += "\n" + wline
			bb += "\n"
		bb += I18n.t("\n[color=#%s][b]KEY MOMENTS[/b][/color]\n") % C_DIM
		for line in _key_moments(sim, player_side):
			bb += line + "\n"
		var star := _star_performer(sim, player_side)
		if not star.is_empty():
			bb += I18n.t("\n[color=#%s][b]STAR PERFORMER[/b][/color]\n") % C_DIM
			bb += I18n.t("[color=#%s][b]%s[/b][/color] [color=#%s]— %d KO%s, %d damage dealt across the tie. Rating: [/color][color=#%s][b]%s[/b][/color]\n") % \
				[C_ACC, star["name"], C_WHITE, star["kos"], "" if star["kos"] == 1 else "s",
				star["dmg"], C_GOOD if star["rating"] >= 7.5 else C_WHITE, I18n.decimal(float(star["rating"]), 1)]
	if f["comp"] == "league":
		var pos := _position_after(f)
		if pos > 0:
			bb += I18n.t("\n[color=#%s]The result leaves %s [/color][color=#%s][b]%s[/b][/color][color=#%s] in the %s.[/color]") % \
				[C_DIM, GameState.player_club()["name"], C_WHITE, _ordinal(pos), C_DIM, I18n.t(GameState.world["meta"]["league_name"])]

	return {
		"bbcode": bb,
		"actions": [{"label": I18n.t("Go to Fixture"), "screen": "competition"},
			{"label": I18n.t("View Squad"), "screen": "squad"}],
		"banner": {"home": home["name"], "away": away["name"],
			"sh": int(f["score_home"]), "sa": int(f["score_away"]),
			"comp": comp_line + " · " + I18n.pretty_date(f["date"]), "won": won},
	}


func _prose_result(f: Dictionary, we_home: bool, us: int, them: int, opp: Dictionary) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(str(f["id"]).hash())
	var venue: String = I18n.t("at home") if we_home else I18n.t("on the road")
	var rep_gap := int(opp["reputation"]) - int(GameState.player_club()["reputation"])
	var phrase: String
	if us > them and them == 0:
		phrase = [I18n.t("a ruthless straight-battles sweep"), I18n.t("a dominant 2-0 performance"),
			I18n.t("total control from the first battle")][rng.randi_range(0, 2)]
	elif us > them:
		phrase = [I18n.t("a hard-fought win that went the distance"), I18n.t("a nervy decider that fell our way"),
			I18n.t("resilience after losing a battle")][rng.randi_range(0, 2)]
	elif us == 0:
		phrase = [I18n.t("a chastening straight-battles defeat"), I18n.t("a sobering afternoon with no reply"),
			I18n.t("a mismatch we never got a grip on")][rng.randi_range(0, 2)]
	else:
		phrase = [I18n.t("a narrow defeat in the deciding battle"), I18n.t("fine margins in a tie we let slip"),
			I18n.t("a decider that got away from us")][rng.randi_range(0, 2)]
	var extra := ""
	if us > them and rep_gap >= 3:
		extra = I18n.t(" Beating a side of %s's stature will not have gone unnoticed upstairs.") % opp["name"]
	elif us < them and rep_gap <= -3:
		extra = I18n.t(" Losing to a side we were expected to beat raises awkward questions.")
	return I18n.t("[color=#%s]%s %s against [b]%s[/b] %s — %s.%s[/color]") % \
		[C_WHITE, I18n.t("Victory") if us > them else I18n.t("Defeat"), venue, opp["name"],
		I18n.t("in the %s") % (I18n.t("league") if f["comp"] == "league" else I18n.cup_round_prose(int(f["round"]))), phrase, extra]


## Deterministic reconstruction of the instant sim (same seeds as GameState).
func _resim(f: Dictionary) -> Dictionary:
	var fid := str(f["id"])
	if _resim_cache.has(fid):
		return _resim_cache[fid]
	var seed_v: int = GameState.career_seed + absi(fid.hash()) % 1000000
	var home: Dictionary = GameState.club(f["home"])
	var away: Dictionary = GameState.club(f["away"])
	var wins := [0, 0]
	var battles: Array = []
	for i in 3:
		if wins[0] == 2 or wins[1] == 2:
			break
		var th := Season.pick_team(home)
		var ta := Season.pick_team(away)
		if th.is_empty() or ta.is_empty():
			_resim_cache[fid] = {}
			return {}
		var eng := BattleEngine.new(th, ta, seed_v + i * 7919)
		eng.run_to_end()
		var w := eng.winner()
		wins[w] += 1
		battles.append(_digest_battle(eng.events, eng.turn, w))
	var out := {}
	if wins[0] == int(f["score_home"]) and wins[1] == int(f["score_away"]):
		out = {"battles": battles}
	_resim_cache[fid] = out
	return out


## Extract KOs (with attribution) and damage-dealt tallies from an event log.
func _digest_battle(events: Array, turns: int, winner: int) -> Dictionary:
	var kos: Array = []
	var dealt := [{}, {}]         # per side: name -> damage dealt
	var last_move := {}
	var last_hit := {}            # victim name -> {by, move, eff, crit}
	var weather := {}             # first weather spell: {kind, by, source}
	var weather_chip := 0         # total HP lost to sand/hail across the battle
	for e in events:
		match str(e["t"]):
			"weather_start":
				if weather.is_empty():
					weather = {"kind": str(e.get("kind", "")),
						"by": str(e.get("pokemon", "")), "source": str(e.get("source", "move"))}
			"weather_chip":
				weather_chip += int(e.get("amount", 0))
		match str(e["t"]):
			"move_used":
				last_move = e
			"damage":
				if not last_move.is_empty() and int(e["side"]) != int(last_move["side"]):
					var actor: String = last_move["pokemon"]
					var side: int = int(last_move["side"])
					dealt[side][actor] = int(dealt[side].get(actor, 0)) + int(e.get("amount", 0))
					last_hit[e["pokemon"]] = {"by": actor, "move": last_move["move"],
						"eff": float(e.get("effectiveness", 1.0)), "crit": bool(e.get("crit", false))}
			"faint":
				var h: Dictionary = last_hit.get(e["pokemon"], {})
				kos.append({"victim": e["pokemon"], "side": int(e["side"]),
					"by": h.get("by", ""), "move": h.get("move", ""),
					"eff": h.get("eff", 1.0), "crit": h.get("crit", false)})
	return {"winner": winner, "turns": turns, "kos": kos, "dealt": dealt,
		"weather": weather, "weather_chip": weather_chip}


## Weather flavour for one battle digest ("" when the skies stayed clear).
func _weather_line(b: Dictionary) -> String:
	var w: Dictionary = b.get("weather", {})
	if w.is_empty():
		return ""
	var kind := str(w.get("kind", ""))
	var flavour: String = str({
		"sun": I18n.t("harsh sunlight baked the arena"),
		"rain": I18n.t("driving rain swept the arena"),
		"sand": I18n.t("a sandstorm raged over the field"),
		"hail": I18n.t("hail hammered the field"),
	}.get(kind, I18n.t("strange weather set in")))
	var by := str(w.get("by", ""))
	var src := I18n.t(" — %s's doing%s") % [by, I18n.t(" (ability)") if str(w.get("source", "")) == "ability" else ""] \
		if by != "" else ""
	var chip := int(b.get("weather_chip", 0))
	var chip_txt := I18n.t(" %d HP was lost to the elements alone.") % chip if chip > 0 else ""
	return I18n.t("[color=#%s]   ☂ %s%s.%s[/color]") % [C_ACC, flavour[0].to_upper() + flavour.substr(1), src, chip_txt]


func _key_moments(sim: Dictionary, player_side: int) -> Array:
	var lines: Array = []
	var battles: Array = sim["battles"]
	for i in battles.size():
		var b: Dictionary = battles[i]
		for ko in b["kos"]:
			if lines.size() >= 7:
				break
			var ours: bool = int(ko["side"]) != player_side  # victim on their side = our KO
			var col := C_GOOD if ours else C_BAD
			var tag := ""
			if float(ko["eff"]) > 1.0:
				tag = I18n.t(" [color=#%s](super-effective)[/color]") % C_WARN
			elif bool(ko["crit"]):
				tag = I18n.t(" [color=#%s](critical hit)[/color]") % C_WARN
			var by: String = str(ko["by"]) if str(ko["by"]) != "" else I18n.t("chip damage")
			lines.append(I18n.t("[color=#%s]B%d[/color]  [color=#%s]%s[/color] [color=#%s]KO'd %s%s[/color]%s") % \
				[C_DIM, i + 1, col, by, C_WHITE, ko["victim"],
				(I18n.t(" with %s") % I18n.t(str(ko["move"]))) if str(ko["move"]) != "" else "", tag])
	if lines.is_empty():
		lines.append(I18n.t("[color=#%s]A cagey tie with few clean knockouts either way.[/color]") % C_DIM)
	return lines


func _star_performer(sim: Dictionary, player_side: int) -> Dictionary:
	var totals := {}   # name -> {kos, dmg}
	for b in sim["battles"]:
		for ko in b["kos"]:
			if int(ko["side"]) != player_side and str(ko["by"]) != "":
				var n: String = ko["by"]
				if not totals.has(n):
					totals[n] = {"kos": 0, "dmg": 0}
				totals[n]["kos"] += 1
		var dealt: Dictionary = b["dealt"][player_side]
		for n in dealt:
			if not totals.has(n):
				totals[n] = {"kos": 0, "dmg": 0}
			totals[n]["dmg"] += int(dealt[n])
	var best := ""
	var best_score := -1.0
	for n in totals:
		var s: float = totals[n]["kos"] * 120.0 + totals[n]["dmg"]
		if s > best_score:
			best_score = s
			best = n
	if best == "":
		return {}
	var rating := clampf(6.0 + totals[best]["kos"] * 0.7 + totals[best]["dmg"] / 300.0, 6.0, 9.8)
	return {"name": best, "kos": totals[best]["kos"], "dmg": totals[best]["dmg"], "rating": rating}


func _position_after(f: Dictionary) -> int:
	var upto: Array = GameState.fixtures.filter(func(x): return x["played"] and x["date"] <= f["date"])
	var table := Season.compute_table(GameState.club_ids(), upto)
	for i in table.size():
		if GameState.is_player_club(table[i]["club_id"]):
			return i + 1
	return 0


# ------------------------------------------------------------- pre-match

func _prematch(msg: Dictionary) -> Dictionary:
	var f := _fixture(msg.get("fid", ""))
	if f.is_empty():
		return _plain(msg)
	var we_home: bool = GameState.is_player_club(f["home"])
	var opp: Dictionary = GameState.club(f["away"] if we_home else f["home"])
	var comp_line: String = (I18n.t("%s · Matchday %d") % [I18n.t(GameState.world["meta"]["league_name"]), int(f["round"])]) \
		if f["comp"] == "league" else ("%s · %s" % [I18n.t("Indigo Cup"), I18n.cup_round(int(f["round"]))])
	var bb := I18n.t("[color=#%s]We %s [b]%s[/b] %s on %s. %s are managed by %s, are [b]%s[/b], and carry a reputation of %d/20.[/color]\n\n") % \
		[C_WHITE, I18n.t("host") if we_home else I18n.t("travel to"), opp["name"],
		I18n.t("in the %s") % (I18n.t("league") if f["comp"] == "league" else I18n.cup_round_prose(int(f["round"]))),
		I18n.pretty_date(f["date"]), opp["short"], opp["manager"],
		_pos_text(opp["id"]), int(opp["reputation"])]

	# opponent form
	var form := _club_form(opp["id"], 5)
	bb += I18n.t("[color=#%s][b]THEIR FORM[/b][/color]  ") % C_DIM
	if form.is_empty():
		bb += I18n.t("[color=#%s]No competitive matches yet this season.[/color]\n\n") % C_DIM
	else:
		for r in form:
			bb += I18n.t("[color=#%s][b] %s [/b][/color]") % [C_GOOD if r else C_BAD, I18n.t("W") if r else I18n.t("L")]
		bb += "\n\n"

	# danger battlers
	bb += I18n.t("[color=#%s][b]DANGER BATTLERS[/b][/color]\n") % C_DIM
	var squad: Array = opp["squad"].duplicate()
	squad.sort_custom(func(a, b): return int(a["level"]) > int(b["level"]))
	for inst in squad.slice(0, 3):
		var sp: Dictionary = DataStore.species(int(inst["species_id"]))
		var types := ""
		for t in sp.get("types", []):
			types += I18n.t("[bgcolor=#%s][color=#0d0f16] %s [/color][/bgcolor] ") % [DataStore.type_color(t).to_html(false), I18n.type_name(str(t)).to_upper()]
		bb += I18n.t("[color=#%s][b]%s[/b][/color] [color=#%s]Lv %d[/color]  %s\n") % \
			[C_WHITE, news.display_name(inst), C_DIM, int(inst["level"]), types]

	# our key matchup: best avg effectiveness of our top battlers vs their top-6
	var key := _key_matchup(opp)
	if not key.is_empty():
		bb += I18n.t("\n[color=#%s][b]ASSISTANT'S NOTE[/b][/color]\n[color=#%s]%s's [b]%s[/b] attacks profile well against their likely six (avg %sx effectiveness) — worth a place in the lineup.[/color]\n") % \
			[C_DIM, C_WHITE, key["name"], I18n.type_name(str(key["type"])), I18n.decimal(float(key["avg"]), 1)]

	bb = I18n.t("[color=#%s]%s[/color]\n\n") % [C_DIM, comp_line] + bb
	var actions := [{"label": I18n.t("Go to Fixture"), "screen": "competition"},
		{"label": I18n.t("Tactics"), "screen": "tactics"}, {"label": I18n.t("View Squad"), "screen": "squad"}]
	return {"bbcode": bb, "actions": actions, "banner": {}}


func _key_matchup(opp: Dictionary) -> Dictionary:
	var ours := Season.pick_team(GameState.player_club())
	var theirs := Season.pick_team(opp)
	if ours.is_empty() or theirs.is_empty():
		return {}
	var best := {}
	var best_avg := 0.0
	for b in ours:
		for atk_type in b["types"]:
			var total := 0.0
			for foe in theirs:
				total += DataStore.effectiveness(atk_type, foe["types"])
			var avg := total / theirs.size()
			if avg > best_avg:
				best_avg = avg
				best = {"name": b["name"], "type": atk_type, "avg": avg}
	if best_avg <= 1.0:
		return {}
	return best


func _club_form(club_id: String, n: int) -> Array:
	var played: Array = GameState.fixtures.filter(func(f):
		return f["played"] and (f["home"] == club_id or f["away"] == club_id))
	played.reverse()
	var out: Array = []
	for f in played.slice(0, n):
		var home: bool = f["home"] == club_id
		out.append((f["score_home"] > f["score_away"]) == home)
	return out


func _club_position(club_id: String) -> int:
	var t: Array = GameState.league_table()
	for i in t.size():
		if t[i]["club_id"] == club_id:
			if int(t[i]["played"]) == 0:
				return 0
			return i + 1
	return 0


func _pos_text(club_id: String) -> String:
	var p := _club_position(club_id)
	return I18n.t("%s in the league") % _ordinal(p) if p > 0 else I18n.t("yet to play in the league")


# ------------------------------------------------------------- cup draw

func _cup_draw(msg: Dictionary) -> Dictionary:
	var rnd := int(msg.get("round", 0))
	if rnd <= 0:
		return _plain(msg)
	var ties: Array = GameState.fixtures.filter(func(f): return f["comp"] == "cup" and int(f["round"]) == rnd)
	if ties.is_empty():
		return _plain(msg)
	var pid: String = GameState.world["meta"]["player_club_id"]
	var our_tie := {}
	for t in ties:
		if t["home"] == pid or t["away"] == pid:
			our_tie = t
	var bb := I18n.t("[color=#%s]The [b]%s[/b] draw for the Indigo Cup has been made. Ties will be played on %s.[/color]\n\n") % \
		[C_WHITE, I18n.cup_round(rnd), I18n.pretty_date(ties[0]["date"])]
	if not our_tie.is_empty():
		var we_home: bool = our_tie["home"] == pid
		var opp: Dictionary = GameState.club(our_tie["away"] if we_home else our_tie["home"])
		bb += I18n.t("[color=#%s]We have been drawn [b]%s[/b] against [b]%s[/b] (%s, reputation %d/20).[/color]\n\n") % \
			[C_ACC, I18n.t("at home") if we_home else I18n.t("away"), opp["name"],
			_pos_text(opp["id"]), int(opp["reputation"])]
	bb += I18n.t("[color=#%s][b]THE DRAW IN FULL[/b][/color]\n") % C_DIM
	for t in ties:
		var h: Dictionary = GameState.club(t["home"])
		var a: Dictionary = GameState.club(t["away"])
		var ours: bool = t["home"] == pid or t["away"] == pid
		var line: String
		if ours:
			line = I18n.t("[color=#%s][b]%s  vs  %s[/b][/color]") % [C_ACC, h["name"], a["name"]]
		else:
			line = I18n.t("[color=#%s]%s  vs  %s[/color]") % [C_DIM, h["name"], a["name"]]
		if t["played"]:
			line += I18n.t("   [color=#%s]%d-%d[/color]") % [C_WHITE, int(t["score_home"]), int(t["score_away"])]
		bb += line + "\n"
	return {"bbcode": bb,
		"actions": [{"label": I18n.t("Go to Fixture"), "screen": "competition"}], "banner": {}}


# ------------------------------------------------------------- scouting

func _scout_report(msg: Dictionary) -> Dictionary:
	var p := {}
	for pr in GameState.prospects():
		if pr["uid"] == msg.get("prospect_uid", ""):
			p = pr
	if p.is_empty():
		return {"bbcode": I18n.t("[color=#%s]This prospect is no longer available — the report has been archived.[/color]") % C_DIM,
			"actions": [{"label": I18n.t("Go to Transfers"), "screen": "transfers"}], "banner": {}}
	var sp: Dictionary = DataStore.species(int(p["species_id"]))
	# The dossier obeys the SAME staged-knowledge ladder as the Transfer
	# Centre (live market knowledge, same mask keys → identical bands):
	# moves + nature at Part scouted 50%, ability at Detailed 75%,
	# exact potential/wage/genetics only with a Full report (100%).
	var mkt: RefCounted = news.market()
	var puid := str(p.get("uid", ""))
	var know: float = mkt.knowledge_of(puid) if mkt != null else float(p.get("scouted_pct", 0))
	var types := ""
	for t in sp.get("types", []):
		types += I18n.t("[bgcolor=#%s][color=#0d0f16] %s [/color][/bgcolor] ") % [DataStore.type_color(t).to_html(false), I18n.type_name(str(t)).to_upper()]
	var pot := int(p.get("potential", 10))
	var stars := int(round(pot / 4.0))
	var star_txt := ""
	for i in 5:
		star_txt += "●" if i < stars else "○"
	var age_m := int(p.get("age_months", 24))
	var ivs: Dictionary = p.get("ivs", {})
	var iv_names := {"hp": I18n.t("constitution"), "atk": I18n.t("physical power"), "def": I18n.t("resilience"),
		"spa": I18n.t("special power"), "spd": I18n.t("special resilience"), "spe": I18n.t("speed")}
	var best_stat := ""
	var best_iv := -1
	for k in ivs:
		if int(ivs[k]) > best_iv:
			best_iv = int(ivs[k])
			best_stat = k
	var verdict: String
	var rec: String
	var rec_col: String
	if pot >= 16:
		verdict = I18n.t("One of the most exciting prospects I have watched this season. The ceiling here is a genuine league star.")
		rec = I18n.t("RECOMMENDATION: SIGN — move before a rival does")
		rec_col = C_GOOD
	elif pot >= 12:
		verdict = I18n.t("Clear first-team potential with the right development plan. Rough edges, but the raw tools are all there.")
		rec = I18n.t("RECOMMENDATION: MONITOR CLOSELY — bid if funds allow")
		rec_col = C_WARN
	else:
		verdict = I18n.t("Honest squad depth at best. I would not commit significant funds at this stage.")
		rec = I18n.t("RECOMMENDATION: PASS — better value elsewhere")
		rec_col = C_BAD

	var bb := I18n.t("[color=#%s][b]%s[/b][/color]  [color=#%s]%s · Lv %d · %d yr %d mo[/color]\n%s\n\n") % \
		[C_WHITE, news.display_name(p), C_DIM, p["species"], int(p["level"]), int(age_m / 12.0), age_m % 12, types]
	var stage_name: String = I18n.t(str(mkt.stage_for(know)["name"])) if mkt != null else I18n.t("Untracked")
	if know >= 100.0:
		bb += I18n.t("[color=#%s][b]POTENTIAL[/b][/color]  [color=#%s][b]%s[/b][/color]  [color=#%s](%d/20)[/color]     [color=#%s][b]SCOUTED[/b][/color]  [color=#%s]%d%% · %s[/color]\n\n") % \
			[C_DIM, C_WARN, star_txt, C_DIM, pot, C_DIM, C_WHITE, int(know), stage_name]
	else:
		var pot_band: String = mkt.masked_int(puid, "pot", pot) if mkt != null else "?"
		bb += I18n.t("[color=#%s][b]POTENTIAL[/b][/color]  [color=#%s][b]est %s/20[/b][/color] [color=#%s](full report pins it)[/color]     [color=#%s][b]SCOUTED[/b][/color]  [color=#%s]%d%% · %s[/color]\n\n") % \
			[C_DIM, C_WARN, pot_band, C_DIM, C_DIM, C_WHITE, int(know), stage_name]
	if know >= 50.0:
		var known_moves: Array = []
		for mv in p.get("moves", []):
			known_moves.append(I18n.move_name(str(mv)))
		bb += "[color=#%s][b]MOVESET[/b][/color]  [color=#%s]%s[/color]\n" % [C_DIM, C_WHITE, ", ".join(known_moves)]
	else:
		bb += I18n.t("[color=#%s][b]MOVESET[/b][/color]  [color=#%s]not yet logged — Part scouted (50%%) reveals it[/color]\n") % [C_DIM, C_DIM]
	# temperament + battle ability: same staged reveal the Transfer Centre uses
	var kn_nat: String = mkt.known_nature(p) if mkt != null else ""
	var kn_ab: String = mkt.known_ability(p) if mkt != null else ""
	if kn_nat != "":
		bb += I18n.t("[color=#%s][b]TEMPERAMENT[/b][/color]  [color=#%s]%s — folded into its battle stats[/color]\n") % \
			[C_DIM, C_WHITE, mkt.nature_text(kn_nat)]
	else:
		bb += I18n.t("[color=#%s][b]TEMPERAMENT[/b][/color]  [color=#%s]unread — Part scouted (50%%) reveals the nature[/color]\n") % [C_DIM, C_DIM]
	if kn_ab != "":
		bb += I18n.t("[color=#%s][b]BATTLE ABILITY[/b][/color]  [color=#%s]%s[/color]\n") % \
			[C_DIM, C_WHITE, I18n.ability_name(kn_ab)]
	else:
		bb += I18n.t("[color=#%s][b]BATTLE ABILITY[/b][/color]  [color=#%s]unconfirmed — a Detailed watch (75%%) pins it[/color]\n") % [C_DIM, C_DIM]
	if best_stat != "":
		if know >= 100.0:
			bb += I18n.t("[color=#%s][b]STANDOUT TRAIT[/b][/color]  [color=#%s]Exceptional %s (%d/15 genetics)[/color]\n") % \
				[C_DIM, C_WHITE, iv_names.get(best_stat, best_stat), best_iv]
		else:
			bb += I18n.t("[color=#%s][b]STANDOUT TRAIT[/b][/color]  [color=#%s]Exceptional %s for its level (genetics confirmed at 100%%)[/color]\n") % \
				[C_DIM, C_WHITE, iv_names.get(best_stat, best_stat)]
	var wage_txt: String = news.money(int(p["contract"]["salary"])) if know >= 100.0 or mkt == null \
		else mkt.masked_money(puid, "wage", int(p["contract"]["salary"])) + I18n.t(" (est.)")
	bb += I18n.t("[color=#%s][b]WAGE DEMAND[/b][/color]  [color=#%s]%s / month[/color]\n\n") % \
		[C_DIM, C_WHITE, wage_txt]
	bb += I18n.t("[color=#%s]\"%s\"[/color]\n\n[color=#%s][b]%s[/b][/color]") % [C_WHITE, verdict, rec_col, rec]
	return {"bbcode": bb,
		"actions": [{"label": I18n.t("Go to Transfers"), "screen": "transfers"}], "banner": {}}


# ------------------------------------------------------------- transfers
# Offers carrying an offer_id are LIVE entries in the transfers market's
# offers_in ledger: the pane renders their current negotiation stage and the
# action buttons call the market's accept/counter/reject API for real.

func _transfer_offer(msg: Dictionary) -> Dictionary:
	if msg.has("offer_id"):
		var o: Dictionary = news.offer_by_id(int(msg["offer_id"]))
		if not o.is_empty():
			return _live_offer(msg, o)
	if msg.has("target_uid") and msg.has("fee"):
		return _archived_offer(msg)
	# other market correspondence (AI-to-AI deals, our buying negotiations…)
	var out := _plain(msg)
	out["actions"] = [{"label": I18n.t("Transfer Centre"), "screen": "transfers", "tab": "centre"}]
	return out


func _live_offer(msg: Dictionary, o: Dictionary) -> Dictionary:
	var mkt: RefCounted = news.market()
	var stage := str(o["stage"])
	var t: Dictionary = mkt.find_target(str(o["uid"]))
	var inst: Dictionary = t.get("inst", {})
	var bidder: Dictionary = GameState.club(str(o["club_id"]))
	var pc: Dictionary = GameState.player_club()
	if bidder.is_empty() or inst.is_empty():
		return _archived_offer(msg)
	var fee: int = int(o["ask"]) if stage == "agreed" and int(o["ask"]) > 0 else news.offer_bid(o)
	var valuation: int = mkt.value_of(inst)
	var wage := int(inst["contract"]["salary"])
	var actionable: bool = news.offer_actionable(o)

	var bb := I18n.t("[color=#%s][b]%s[/b] (%s, reputation %d/20, funds %s) %s[/color]\n") % \
		[C_WHITE, bidder["name"], _pos_text(bidder["id"]), int(bidder["reputation"]),
		news.money(int(bidder["finances"]["balance"])),
		I18n.t("have agreed to pay our asking price of") if stage == "agreed" else I18n.t("have a bid on the table of")]
	bb += I18n.t("[color=#%s][b]%s[/b][/color]\n") % [C_GOOD if actionable else C_DIM, news.money(fee)]
	bb += I18n.t("[color=#%s]for [b]%s[/b] (%s, Lv %d — wages %s / month, contracted to %s).[/color]\n\n") % \
		[C_WHITE, news.display_name(inst), inst["species"], int(inst["level"]),
		news.money(wage), I18n.pretty_date(str(inst["contract"]["expiry"]))]

	# finance view against the market's live valuation
	var vs_val: String
	var vs_col: String
	if fee >= int(float(valuation) * 1.15):
		vs_val = I18n.t("comfortably above our %s valuation — hard to turn down") % news.money(valuation)
		vs_col = C_GOOD
	elif fee >= valuation:
		vs_val = I18n.t("in line with our %s valuation") % news.money(valuation)
		vs_col = C_WARN
	else:
		vs_val = I18n.t("below our %s valuation — we hold the cards") % news.money(valuation)
		vs_col = C_BAD
	bb += I18n.t("[color=#%s][b]FINANCE VIEW[/b][/color]  [color=#%s]The fee is %s.[/color]\n") % [C_DIM, vs_col, vs_val]
	# structured packages: only the upfront part lands immediately
	var upfront := fee
	var pkg: Dictionary = o.get("package", {})
	if stage != "agreed" and not pkg.is_empty() and int(pkg.get("inst_amount", 0)) > 0 \
		and mkt.has_method("describe_package"):
		upfront = int(pkg.get("upfront", 0))
		bb += I18n.t("[color=#%s][b]DEAL STRUCTURE[/b][/color]  [color=#%s]%s.[/color]\n") % \
			[C_DIM, C_WHITE, str(mkt.describe_package(pkg))]
	bb += I18n.t("[color=#%s][b]IF WE SELL[/b][/color]  [color=#%s]Balance %s → [b]%s[/b]%s · frees %s / month in wages · squad %d → %d.[/color]\n") % \
		[C_DIM, C_WHITE, news.money(int(pc["finances"]["balance"])),
		news.money(int(pc["finances"]["balance"]) + upfront),
		"" if upfront == fee else I18n.t(" now (rest in installments)"), news.money(wage),
		pc["squad"].size(), pc["squad"].size() - 1]
	if pc["squad"].size() <= 7:
		bb += I18n.t("[color=#%s][b]SQUAD WARNING[/b]  Selling would leave us at the 6-battler league minimum.[/color]\n") % C_WARN
	bb += "\n"

	# negotiation log — the live paper trail shared with the Transfer Centre
	var logs: Array = o.get("log", [])
	if not logs.is_empty():
		bb += I18n.t("[color=#%s][b]NEGOTIATION LOG[/b][/color]\n") % C_DIM
		for line in logs:
			bb += I18n.t("[color=#%s]%s[/color]  [color=#%s]%s[/color]\n") % \
				[C_DIM, I18n.pretty_date(str(line["date"])), C_WHITE, str(line["text"])]
		bb += "\n"

	var actions: Array = []
	match stage:
		"open":
			var days_left := Season.days_between(GameState.current_date, str(o.get("expires_on", GameState.current_date)))
			if days_left >= 0:
				bb += I18n.t("[color=#%s][b]DECISION REQUIRED — offer expires %s (%s).[/b][/color]") % \
					[C_BAD, I18n.pretty_date(str(o["expires_on"])).to_upper(),
					I18n.t("today") if days_left == 0 else I18n.np(days_left, "in %d day", "in %d days")]
				var ask := _suggest_ask(fee, valuation)
				actions = [
					{"kind": "accept", "offer_id": int(o["id"]), "style": "good",
						"label": I18n.t("Accept %s") % news.money(fee)},
					{"kind": "counter", "offer_id": int(o["id"]), "ask": ask, "style": "warn",
						"label": I18n.t("Demand %s") % news.money(ask)},
					{"kind": "reject", "offer_id": int(o["id"]), "style": "bad", "label": I18n.t("Reject Offer")},
				]
			else:
				bb += I18n.t("[color=#%s][b]THIS OFFER HAS EXPIRED[/b] (deadline was %s).[/color]") % \
					[C_DIM, I18n.pretty_date(str(o.get("expires_on", "")))]
		"agreed":
			var so := int(o.get("ask_sell_on", 0))
			bb += I18n.t("[color=#%s][b]DECISION REQUIRED — %s met our demand%s. Confirm the sale or pull out.[/b][/color]") % \
				[C_BAD, bidder["short"], (I18n.t(" (incl. a %d%% sell-on clause)") % so) if so > 0 else ""]
			actions = [
				{"kind": "accept", "offer_id": int(o["id"]), "style": "good",
					"label": I18n.t("Confirm Sale (%s)") % news.money(fee)},
				{"kind": "reject", "offer_id": int(o["id"]), "style": "bad", "label": I18n.t("Pull Out")},
			]
		"counter_pending":
			bb += I18n.t("[color=#%s]We demanded [b]%s[/b]. %s will respond by [b]%s[/b].[/color]") % \
				[C_WHITE, news.money(int(o["ask"])), bidder["short"],
				I18n.pretty_date(str(o.get("respond_on", "")))]
			actions = [{"kind": "reject", "offer_id": int(o["id"]), "style": "bad", "label": I18n.t("End Talks")}]
		"completed":
			bb += I18n.t("[color=#%s][b]SALE COMPLETED.[/b] %s joined %s and %s was credited to our balance (now %s).[/color]") % \
				[C_GOOD, news.display_name(inst), bidder["name"], news.money(fee),
				news.money(int(pc["finances"]["balance"]))]
		"rejected":
			bb += I18n.t("[color=#%s][b]We rejected this offer.[/b] %s stays at the club.[/color]") % [C_DIM, news.display_name(inst)]
		"withdrawn":
			bb += I18n.t("[color=#%s][b]%s walked away[/b] — talks are over.[/color]") % [C_DIM, bidder["name"]]
		"expired":
			bb += I18n.t("[color=#%s][b]This offer expired[/b] without a decision.[/color]") % C_DIM
		_:
			bb += I18n.t("[color=#%s]Negotiation state: %s.[/color]") % [C_DIM, stage]
	actions.append({"label": I18n.t("Transfer Centre"), "screen": "transfers", "tab": "centre"})
	actions.append({"label": I18n.t("View Squad"), "screen": "squad"})
	return {"bbcode": bb, "actions": actions, "banner": {}}


func _suggest_ask(bid: int, valuation: int) -> int:
	var ask := int(round(float(valuation) * 1.15 / 1000.0)) * 1000
	if ask <= bid:
		ask = int(round(float(bid) * 1.25 / 1000.0)) * 1000
	return maxi(ask, bid + 1000)


## Historical / unlinked offer mail (target sold, legacy save, market gone).
func _archived_offer(msg: Dictionary) -> Dictionary:
	var bidder: Dictionary = GameState.club(str(msg.get("bidder", "")))
	var fee := int(msg.get("fee", 0))
	var deadline: String = str(msg.get("deadline", ""))
	var bb := "[color=#%s]%s[/color]\n\n" % [C_WHITE, str(msg.get("body", ""))]
	if not bidder.is_empty() and fee > 0:
		bb += I18n.t("[color=#%s][b]OFFER[/b][/color]  [color=#%s]%s from %s.[/color]\n") % \
			[C_DIM, C_WHITE, news.money(fee), bidder["name"]]
	if deadline != "" and GameState.current_date > deadline:
		bb += I18n.t("[color=#%s][b]THIS OFFER HAS EXPIRED[/b] (deadline was %s). No action is possible.[/color]") % \
			[C_DIM, I18n.pretty_date(deadline)]
	else:
		bb += I18n.t("[color=#%s]This item is no longer negotiable — the full record lives in the Transfer Centre.[/color]") % C_DIM
	return {"bbcode": bb,
		"actions": [{"label": I18n.t("Transfer Centre"), "screen": "transfers", "tab": "centre"},
			{"label": I18n.t("View Squad"), "screen": "squad"}], "banner": {}}


# ------------------------------------------------------------- board

func _board_preseason(msg: Dictionary) -> Dictionary:
	var pc: Dictionary = GameState.player_club()
	var fin: Dictionary = news.finance_summary()
	var bb := "[color=#%s]%s[/color]\n\n" % [C_WHITE, str(msg.get("body", ""))]
	bb += I18n.t("[color=#%s][b]SEASON OBJECTIVES[/b][/color]\n") % C_DIM
	bb += I18n.t("[color=#%s]● League:[/color] [color=#%s][b]%s[/b][/color]\n") % [C_DIM, C_WHITE, news.league_expectation_text().capitalize()]
	bb += I18n.t("[color=#%s]● Cup:[/color] [color=#%s][b]%s[/b][/color]\n\n") % [C_DIM, C_WHITE, news.cup_expectation_text().capitalize()]
	bb += I18n.t("[color=#%s][b]RESOURCES[/b][/color]\n") % C_DIM
	bb += I18n.t("[color=#%s]● Bank balance:[/color] [color=#%s][b]%s[/b][/color]\n") % [C_DIM, C_WHITE, news.money(fin["balance"])]
	bb += I18n.t("[color=#%s]● Transfer budget:[/color] [color=#%s][b]%s[/b][/color] [color=#%s](released by the board for fees and equipment)[/color]\n") % \
		[C_DIM, C_WHITE, news.money(maxi(0, int(fin.get("transfer_budget", 0)))), C_DIM]
	bb += I18n.t("[color=#%s]● Wage budget:[/color] [color=#%s][b]%s / month[/b][/color] [color=#%s](current bill %s)[/color]\n\n") % \
		[C_DIM, C_WHITE, news.money(fin["wage_budget"]), C_DIM, news.money(fin["wage_bill"])]
	bb += I18n.t("[color=#%s]The board will formally review progress at the start of each month. Expected league position based on club stature: [b]%s[/b].[/color]") % \
		[C_DIM, _ordinal(news.expected_position())]
	return {"bbcode": bb,
		"actions": [{"label": I18n.t("Board & Finances"), "screen": "@board"},
			{"label": I18n.t("Go to Fixture"), "screen": "competition"}], "banner": {}}


func _board_review(msg: Dictionary) -> Dictionary:
	var conf: Dictionary = news.board_confidence()
	var fin: Dictionary = news.finance_summary()
	var form: Array = news.recent_results(5)
	var wins := 0
	for r in form:
		if r["won"]:
			wins += 1
	var bb := I18n.t("[color=#%s]The board has completed its scheduled review of the club's progress.[/color]\n\n") % C_WHITE
	bb += I18n.t("[color=#%s][b]CONFIDENCE[/b][/color]  [color=#%s][b]%s[/b][/color] [color=#%s](%d%%)[/color]\n") % \
		[C_DIM, conf["color"].to_html(false), str(conf["word"]).to_upper(), C_DIM, int(conf["score"])]
	bb += I18n.t("[color=#%s]%s[/color]\n\n") % [C_WHITE, conf["statement"]]
	if int(conf["played"]) == 0:
		bb += I18n.t("[color=#%s][b]LEAGUE[/b][/color]  [color=#%s]No league matches played yet — the board expects around [b]%s[/b] once the season is under way.[/color]\n") % \
			[C_DIM, C_WHITE, _ordinal(conf["expected"])]
	else:
		bb += I18n.t("[color=#%s][b]LEAGUE[/b][/color]  [color=#%s]Currently [b]%s[/b] — the board expected around [b]%s[/b].[/color]\n") % \
			[C_DIM, C_WHITE, _ordinal(conf["pos"]), _ordinal(conf["expected"])]
	if not form.is_empty():
		bb += I18n.t("[color=#%s][b]FORM[/b][/color]  ") % C_DIM
		for r in form:
			bb += I18n.t("[color=#%s][b] %s [/b][/color]") % [C_GOOD if r["won"] else C_BAD, I18n.t("W") if r["won"] else I18n.t("L")]
		bb += I18n.t("  [color=#%s](%d of last %d won)[/color]\n") % [C_DIM, wins, form.size()]
	bb += I18n.t("[color=#%s][b]CUP[/b][/color]  [color=#%s]%s[/color]\n\n") % [C_DIM, C_WHITE, news.cup_status()["text"]]
	var over: bool = int(fin["wage_bill"]) > int(fin["wage_budget"])
	bb += I18n.t("[color=#%s][b]FINANCES[/b][/color]  [color=#%s]Balance [b]%s[/b] · transfer budget [b]%s[/b] · wage bill [b]%s[/b] of the %s budget[/color] [color=#%s]%s[/color]") % \
		[C_DIM, C_WHITE, news.money(fin["balance"]), news.money(maxi(0, int(fin.get("transfer_budget", 0)))),
		news.money(fin["wage_bill"]),
		news.money(fin["wage_budget"]), C_BAD if over else C_GOOD,
		I18n.t("(OVER BUDGET)") if over else I18n.t("(within budget)")]
	return {"bbcode": bb,
		"actions": [{"label": I18n.t("Board & Finances"), "screen": "@board"}], "banner": {}}


## Monthly finance report — the closed books for one calendar month, straight
## from the operating ledger (every line here actually moved the balance).
func _finance_report(msg: Dictionary) -> Dictionary:
	var month_key := str(msg.get("month", str(msg.get("uid", "")).trim_prefix("finrep:")))
	if economy == null or board == null or month_key.length() != 7:
		return _plain(msg)
	var mname: String = I18n.t(economy.MONTH_NAMES[int(month_key.split("-")[1])])
	# everything that hit the bank in that month: operations + transfers + board
	var lines: Array = board.ledger_rows(999).filter(func(r):
		return str(r["date"]).begins_with(month_key) and int(r["amount"]) != 0)
	lines.sort_custom(func(a, b): return str(a["date"]) < str(b["date"]))
	if lines.is_empty():
		return _plain(msg)
	var income := 0
	var expense := 0
	for r in lines:
		var a := int(r["amount"])
		if a > 0:
			income += a
		else:
			expense += -a
	var net := income - expense
	var fin: Dictionary = news.finance_summary()

	var bb := I18n.t("[color=#%s]The finance office has closed the books on [b]%s[/b].[/color]\n\n") % [C_WHITE, mname]
	bb += I18n.t("[color=#%s][b]INCOME[/b][/color]   [color=#%s][b]+%s[/b][/color]\n") % [C_DIM, C_GOOD, news.money(income)]
	for r in lines:
		if int(r["amount"]) > 0:
			bb += I18n.t("[color=#%s]●[/color] [color=#%s]%s[/color]  [color=#%s]+%s[/color]\n") % \
				[C_DIM, C_WHITE, str(r["text"]), C_GOOD, news.money(int(r["amount"]))]
	bb += I18n.t("\n[color=#%s][b]EXPENDITURE[/b][/color]   [color=#%s][b]-%s[/b][/color]\n") % [C_DIM, C_BAD, news.money(expense)]
	for r in lines:
		if int(r["amount"]) < 0:
			bb += I18n.t("[color=#%s]●[/color] [color=#%s]%s[/color]  [color=#%s]%s[/color]\n") % \
				[C_DIM, C_WHITE, str(r["text"]), C_BAD, news.money(int(r["amount"]))]
	bb += I18n.t("\n[color=#%s][b]OPERATING RESULT[/b][/color]  [color=#%s][b]%s%s[/b][/color]\n") % \
		[C_DIM, C_GOOD if net >= 0 else C_BAD, "+" if net >= 0 else "", news.money(net)]
	var over: bool = int(fin["wage_bill"]) > int(fin["wage_budget"])
	bb += I18n.t("[color=#%s]Bank balance now [b]%s[/b] · wage bill %s of the %s budget %s.[/color]\n") % \
		[C_DIM, news.money(int(fin["balance"])), news.money(int(fin["wage_bill"])),
		news.money(int(fin["wage_budget"])), I18n.t("(OVER)") if over else I18n.t("(within budget)")]
	if net < 0:
		bb += I18n.t("[color=#%s]A losing month — home gates, cup runs or player sales must cover the shortfall.[/color]") % C_WARN
	else:
		bb += I18n.t("[color=#%s]A profitable month — the operating surplus is yours to reinvest.[/color]") % C_DIM
	return {"bbcode": bb,
		"actions": [{"label": I18n.t("Board & Finances"), "screen": "@board"},
			{"label": I18n.t("Transfer Centre"), "screen": "transfers", "tab": "centre"}], "banner": {}}


# ------------------------------------------------------------- board requests
# These messages are the paper trail of the board_room request system: the
# acknowledgement while the board deliberates, and the decision — whose
# "granted" numbers are the REAL before/after of the club's finances.

func _board_request_ack(msg: Dictionary) -> Dictionary:
	var r: Dictionary = {} if board == null else board.request_by_id(int(msg.get("req_id", -1)))
	if r.is_empty():
		return _plain(msg)
	var conf: Dictionary = news.board_confidence()
	var ask_txt := _req_ask_text(r)
	var bb := I18n.t("[color=#%s]Your request — [b]%s[/b] — has been tabled for the board's next sitting.[/color]\n\n") % \
		[C_WHITE, ask_txt]
	if str(r["status"]) == "pending":
		bb += I18n.t("[color=#%s][b]STATUS[/b][/color]  [color=#%s]Under consideration — a decision is expected by [b]%s[/b].[/color]\n") % \
			[C_DIM, C_WARN, I18n.pretty_date(str(r["decide_on"]))]
	else:
		bb += I18n.t("[color=#%s][b]STATUS[/b][/color]  [color=#%s]Answered on %s — see the board's reply in your inbox.[/color]\n") % \
			[C_DIM, C_DIM, I18n.pretty_date(str(r["decided_on"]))]
	bb += I18n.t("[color=#%s][b]MOOD IN THE ROOM[/b][/color]  [color=#%s]The board is currently [b]%s[/b] (%d%%) — that will weigh heavily on the answer.[/color]") % \
		[C_DIM, conf["color"].to_html(false), str(conf["word"]).to_lower(), int(conf["score"])]
	return {"bbcode": bb,
		"actions": [{"label": I18n.t("Board & Finances"), "screen": "@board"}], "banner": {}}


func _board_decision(msg: Dictionary) -> Dictionary:
	var r: Dictionary = {} if board == null else board.request_by_id(int(msg.get("req_id", -1)))
	if r.is_empty():
		return _plain(msg)
	var status := str(r["status"])
	var granted := int(r["granted"])
	var head: String
	var head_col: String
	match status:
		"granted":
			head = I18n.t("REQUEST GRANTED IN FULL")
			head_col = C_GOOD
		"partial":
			head = I18n.t("PARTIALLY GRANTED")
			head_col = C_WARN
		_:
			head = I18n.t("REQUEST REFUSED")
			head_col = C_BAD
	var bb := I18n.t("[color=#%s][b]%s[/b][/color]\n") % [head_col, head]
	bb += I18n.t("[color=#%s]You asked for [b]%s[/b] on %s.[/color]\n\n") % \
		[C_WHITE, _req_ask_text(r), I18n.pretty_date(str(r["date"]))]

	bb += I18n.t("[color=#%s][b]THE BOARD'S REASONING[/b][/color]\n") % C_DIM
	for line in r.get("reasons", []):
		bb += I18n.t("[color=#%s]●[/color] [color=#%s]%s[/color]\n") % [C_DIM, C_WHITE, str(line)]
	bb += "\n"

	match status:
		"granted", "partial":
			bb += I18n.t("[color=#%s][b]WHAT CHANGES[/b][/color]\n") % C_DIM
			match str(r["kind"]):
				"wage":
					bb += I18n.t("[color=#%s]Monthly wage budget: %s → [b]%s[/b] (+%s).[/color]\n") % \
						[C_GOOD, news.money(int(r["before"])), news.money(int(r["after"])), news.money(granted)]
				"funds":
					bb += I18n.t("[color=#%s]Bank balance: %s → [b]%s[/b] — %s of the owners' money, available to spend now.[/color]\n") % \
						[C_GOOD, news.money(int(r["before"])), news.money(int(r["after"])), news.money(granted)]
				"scouting":
					bb += I18n.t("[color=#%s]Bank balance: %s → [b]%s[/b]. All %d prospect files gained +%d%% scouting knowledge.[/color]\n") % \
						[C_GOOD, news.money(int(r["before"])), news.money(int(r["after"])),
						int(r.get("prospects_updated", 0)), board.SCOUT_KNOWLEDGE_GAIN]
			if status == "partial":
				bb += I18n.t("[color=#%s]That is [b]%s[/b] of the %s you asked for — the board would not stretch further.[/color]\n") % \
					[C_WARN, news.money(granted), news.money(int(r["amount"]))]
		_:
			bb += I18n.t("[color=#%s]Nothing changes. Pushing again soon will only harden the board's stance.[/color]\n") % C_DIM
	var actions := [{"label": I18n.t("Board & Finances"), "screen": "@board"}]
	if str(r["kind"]) == "funds" and status != "denied":
		actions.append({"label": I18n.t("Go to Transfers"), "screen": "transfers"})
	if str(r["kind"]) == "scouting" and status != "denied":
		actions.append({"label": I18n.t("View Prospects"), "screen": "transfers"})
	return {"bbcode": bb, "actions": actions, "banner": {}}


func _req_ask_text(r: Dictionary) -> String:
	match str(r["kind"]):
		"wage":
			return I18n.t("a wage budget increase of %s / month") % news.money(int(r["amount"]))
		"funds":
			return I18n.t("a funds injection of %s") % news.money(int(r["amount"]))
		"scouting":
			return I18n.t("a %s scouting network investment") % news.money(int(r["amount"]))
	return str(r.get("label", "a request"))


# ------------------------------------------------------------- misc

func _fixture(fid: String) -> Dictionary:
	if fid == "":
		return {}
	for f in GameState.fixtures:
		if f["id"] == fid:
			return f
	return {}


func _ordinal(n: int) -> String:
	if n <= 0:
		return "—"
	return I18n.ordinal(n)
