extends RefCounted
## Inbox piece: the OPERATING ECONOMY — the club's real cash flow.
##
## FM clubs live and die by a monthly P&L: wages actually leave the bank,
## matchdays actually put money in it. This module makes that true here.
## Every club in the league (not just ours) runs the same economy:
##
##   per played fixture   gate receipts to the home club (attendance from
##                        reputation/league position, deterministic), matchday
##                        operating costs, away-side travel costs; cup ties
##                        split the gate and pay round prize money to the winner
##   on the 1st of month  payroll (the REAL sum of squad contract salaries),
##                        facilities upkeep, sponsorship and broadcast/merit
##                        payments settled for the month just ended
##
## All flows mutate club["finances"]["balance"] in GameState.world — the same
## ledger the top bar, the transfers market and board_room read — and the
## player club's lines are recorded so the Board & Finances tab can show a
## living income & expenditure statement. A monthly finance report lands in
## the inbox when the books close.
##
## Deterministic (career_seed + fixture id / calendar), duplicate-guarded by
## fixture id + last settled date, persisted to user://inbox_economy.json
## (the board_room.gd state pattern), auto-resetting on a new career.

const STATE_PATH := "user://inbox_economy.json"

## Cup prize money by round (paid to the tie winner).
const CUP_PRIZE := {1: 12000, 2: 20000, 3: 35000, 4: 75000}

const MONTH_NAMES := ["", "January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December"]

var news: RefCounted                 # news_gen.gd (money formatting, helpers)

var last_settled := ""               # calendar processed up to this date (inclusive)
var done_fids: Dictionary = {}       # fixture id -> true (already settled)
var entries: Array = []              # player-club lines: {date, text, amount, kind}


func _init(news_gen: RefCounted) -> void:
	news = news_gen
	_load_state()


# ------------------------------------------------------------------ persistence

func save_state() -> void:
	var f := FileAccess.open(STATE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("economy: cannot write %s" % STATE_PATH)
		return
	f.store_string(JSON.stringify({
		"version": 1,
		"career_seed": GameState.career_seed,
		"last_settled": last_settled,
		"done_fids": done_fids,
		"entries": entries,
	}))


func _load_state() -> void:
	if not FileAccess.file_exists(STATE_PATH):
		return
	var f := FileAccess.open(STATE_PATH, FileAccess.READ)
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) != 1:
		return
	if int(data.get("career_seed", 0)) != GameState.career_seed:
		return  # different career — start clean
	last_settled = str(data.get("last_settled", ""))
	done_fids = data.get("done_fids", {})
	entries = data.get("entries", [])


## Records dated after "today" can only mean the career was restarted with the
## same seed (same detection board_room.gd uses). Wipe and rebuild from scratch.
func _guard_career_restart() -> void:
	var stale := last_settled > GameState.current_date \
		or entries.any(func(e): return str(e["date"]) > GameState.current_date)
	if stale:
		last_settled = ""
		done_fids = {}
		entries = []
		save_state()


# ------------------------------------------------------------------ the tick

## Catch the economy up to today. Called on every date change / screen load;
## backfills the full season history on first run so an existing career gets
## a correct retroactive ledger (and the correct bank balance) immediately.
func tick() -> void:
	_guard_career_restart()
	if last_settled == "":
		last_settled = GameState.season_start
	var changed := false
	var positions := _table_positions()

	# 1. matchday flows for every settled-but-unprocessed fixture
	for f in GameState.fixtures:
		if not f.get("played", false) or str(f["date"]) > GameState.current_date:
			continue
		var fid := str(f["id"])
		if done_fids.has(fid):
			continue
		_settle_fixture(f, positions)
		done_fids[fid] = true
		changed = true

	# 2. monthly settlements at each month boundary crossed since last tick
	while last_settled < GameState.current_date:
		last_settled = Season.date_add(last_settled, 1)
		changed = true
		if last_settled.ends_with("-01"):
			_settle_month(last_settled, positions)

	if changed:
		save_state()
		GameState.save_game()


# ------------------------------------------------------------------ matchdays

func _settle_fixture(f: Dictionary, positions: Dictionary) -> void:
	var home: Dictionary = GameState.club(str(f["home"]))
	var away: Dictionary = GameState.club(str(f["away"]))
	if home.is_empty() or away.is_empty():
		return
	var we_home: bool = GameState.is_player_club(str(f["home"]))
	var we_away: bool = GameState.is_player_club(str(f["away"]))
	var is_cup: bool = str(f["comp"]) == "cup"

	var att := _attendance(f, home, away, positions)
	var price := 3.0 + int(home["reputation"]) * 0.10
	var gross := int(round(att * price / 10.0)) * 10
	var ops := int(round(gross * 0.34 / 10.0)) * 10          # stewards, venue, medics
	var travel := (900 + int(away["reputation"]) * 60)        # away side's coach + lodging
	var date := str(f["date"])
	var opp_h := str(away["name"])
	var opp_a := str(home["name"])

	if is_cup:
		# cup gates are pooled: 15% competition levy, the rest split evenly
		var share := int(round(gross * 0.425 / 10.0)) * 10
		_move(home, share - ops)
		_move(away, share - travel)
		if we_home:
			_record(date, "Cup gate share — vs %s (att %s)" % [opp_h, _fmt_att(att)], share, "gate")
			_record(date, "Matchday operations — vs %s" % opp_h, -ops, "ops")
		elif we_away:
			_record(date, "Cup gate share — at %s (att %s)" % [opp_a, _fmt_att(att)], share, "gate")
			_record(date, "Team travel — at %s" % opp_a, -travel, "travel")
		# round prize money to the winner
		var rnd := int(f.get("round", 1))
		var prize := int(CUP_PRIZE.get(rnd, 75000))
		var home_won: bool = int(f["score_home"]) > int(f["score_away"])
		var winner := home if home_won else away
		_move(winner, prize)
		if (we_home and home_won) or (we_away and not home_won):
			_record(date, "Prize money — %s won" % Season.cup_round_name(rnd), prize, "prize")
	else:
		_move(home, gross - ops)
		_move(away, -travel)
		if we_home:
			_record(date, "Gate receipts — vs %s (att %s)" % [opp_h, _fmt_att(att)], gross, "gate")
			_record(date, "Matchday operations — vs %s" % opp_h, -ops, "ops")
		elif we_away:
			_record(date, "Team travel — at %s" % opp_a, -travel, "travel")


## Deterministic crowd: club stature, the visitors' pull, league standing,
## a cup bump, and a stable per-fixture wobble.
func _attendance(f: Dictionary, home: Dictionary, away: Dictionary, positions: Dictionary) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.career_seed + absi(str(f["id"]).hash())
	var base := int(home["reputation"]) * 340 + int(away["reputation"]) * 110
	var pos := int(positions.get(str(home["id"]), 8))
	base += (17 - pos) * 40
	if str(f["comp"]) == "cup":
		base = int(base * (1.0 + 0.06 * int(f.get("round", 1))))
	return maxi(400, int(base * rng.randf_range(0.92, 1.08)))


# ------------------------------------------------------------------ month end

## Settle the month that ended the day before `boundary` (a "YYYY-MM-01").
## Lines are dated on the last day of the settled month so each calendar
## month's P&L is self-contained.
func _settle_month(boundary: String, positions: Dictionary) -> void:
	var closing := Season.date_add(boundary, -1)      # e.g. 2026-08-31
	var month_key := closing.substr(0, 7)
	var mname: String = MONTH_NAMES[int(closing.split("-")[1])]

	for c in GameState.world["clubs"]:
		var rep := int(c["reputation"])
		var payroll := 0
		for inst in c["squad"]:
			payroll += int(inst["contract"]["salary"])
		var upkeep := 3200 + rep * 520
		var sponsor := rep * 1150
		var pos := int(positions.get(str(c["id"]), 8))
		var broadcast := 6000 + (16 - pos) * 550
		_move(c, sponsor + broadcast - payroll - upkeep)
		if GameState.is_player_club(str(c["id"])):
			_record(closing, "Payroll — squad wages, %s (%d battlers)" %
				[mname, c["squad"].size()], -payroll, "wages")
			_record(closing, "Facilities & staff upkeep — %s" % mname, -upkeep, "upkeep")
			_record(closing, "Sponsorship — %s" % mname, sponsor, "sponsor")
			_record(closing, "League broadcast & merit payment — %s (%s)" %
				[mname, _ord(pos)], broadcast, "broadcast")
	_send_month_report(boundary, month_key, mname)


## The finance office closes the books: a monthly P&L report in the inbox.
func _send_month_report(boundary: String, month_key: String, mname: String) -> void:
	var uid := "finrep:%s" % month_key
	for m in GameState.inbox:
		if str(m.get("uid", "")) == uid:
			return
	var t := month_totals(month_key)
	var net := int(t["net"])
	var pc: Dictionary = GameState.player_club()
	GameState.add_inbox_message(boundary,
		"Monthly finance report: %s (%s%s)" % [mname, "+" if net >= 0 else "", news.money(net)],
		"The finance office has closed the books on %s. Operating result: %s." %
			[mname, news.money(net)])
	var m: Dictionary = GameState.inbox[0]
	m["uid"] = uid
	m["cat"] = "board"
	m["sender"] = "%s Finance Office" % pc["name"]
	m["month"] = month_key
	if boundary < GameState.current_date:
		m["read"] = true   # backfilled history arrives read, like other news


# ------------------------------------------------------------------ queries

## Player-club operating lines, newest first (merged into board_room's ledger).
func rows() -> Array:
	return entries


## All lines of one calendar month ("YYYY-MM"), oldest first.
func month_rows(month_key: String) -> Array:
	var out: Array = entries.filter(func(e): return str(e["date"]).begins_with(month_key))
	out.sort_custom(func(a, b): return str(a["date"]) < str(b["date"]))
	return out


func month_totals(month_key: String) -> Dictionary:
	var inc := 0
	var exp := 0
	for e in month_rows(month_key):
		var a := int(e["amount"])
		if a > 0:
			inc += a
		else:
			exp += -a
	return {"income": inc, "expense": exp, "net": inc - exp}


## Net operating cash flow over the trailing `days` days.
func operating_net(days: int) -> int:
	var floor_date := Season.date_add(GameState.current_date, -days)
	var net := 0
	for e in entries:
		if str(e["date"]) > floor_date:
			net += int(e["amount"])
	return net


# ------------------------------------------------------------------ internals

func _move(club: Dictionary, amount: int) -> void:
	if amount == 0:
		return
	var fin: Dictionary = club["finances"]
	fin["balance"] = int(fin["balance"]) + amount


func _record(date: String, text: String, amount: int, kind: String) -> void:
	entries.push_front({"date": date, "text": text, "amount": amount, "kind": kind})


func _table_positions() -> Dictionary:
	var out := {}
	var t: Array = GameState.league_table()
	for i in t.size():
		out[str(t[i]["club_id"])] = i + 1
	return out


func _fmt_att(n: int) -> String:
	var s := str(n)
	if s.length() > 3:
		s = s.substr(0, s.length() - 3) + "," + s.substr(s.length() - 3)
	return s


func _ord(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1: suffix = "st"
			2: suffix = "nd"
			3: suffix = "rd"
	return "%d%s" % [n, suffix]
