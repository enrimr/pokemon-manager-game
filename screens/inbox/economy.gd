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
## SETTLEMENT runs on the daily advance tick (GameState.advance_day calls
## tick() through its economy hook), so wages/gates/prize money accrue even
## in pure-sim timelines that never open the Inbox — the Inbox merely renders
## the ledger. Deterministic (career_seed + fixture id / calendar),
## duplicate-guarded by fixture id + last settled date. State lives INSIDE
## the save (world.meta.economy) so balances and ledger can never desync
## across save/load; the legacy user://inbox_economy.json sidecar is read
## once as a migration source, then deleted.

const STATE_PATH := "user://inbox_economy.json"   # legacy sidecar (migration only)

## Cup prize money by round (paid to the tie winner).
const CUP_PRIZE := {1: 12000, 2: 20000, 3: 35000, 4: 75000}

const MONTH_NAMES := ["", "January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December"]

var news: RefCounted                 # news_gen.gd (money formatting, helpers)


func _init(news_gen: RefCounted) -> void:
	news = news_gen


# ------------------------------------------------------------------ persistence
# The ledger lives in GameState.world.meta.economy:
#   {last_settled: String, done_fids: {fid: true}, entries: [{date, text, amount, kind}]}
# It rides save.json with the balances it explains, so multiple economy
# instances (GameState's daily hook, the Inbox screen) share one truth and
# loading any save restores a ledger consistent with that save's money.

func _state() -> Dictionary:
	var meta: Dictionary = GameState.world["meta"]
	var st: Variant = meta.get("economy")
	if typeof(st) == TYPE_DICTIONARY and typeof((st as Dictionary).get("entries")) == TYPE_ARRAY:
		return st
	var fresh := _migrate_sidecar()
	if fresh.is_empty():
		fresh = {"last_settled": "", "done_fids": {}, "entries": []}
	meta["economy"] = fresh
	return fresh


## One-time adoption of the legacy user://inbox_economy.json sidecar, for
## careers whose balances already include its settlements. Rejected if it
## belongs to another career or claims dates beyond today (stale/rolled back
## timeline — safer to rebuild than to double-count is impossible either way,
## since rebuild is what pre-sidecar careers get too).
func _migrate_sidecar() -> Dictionary:
	if not FileAccess.file_exists(STATE_PATH):
		return {}
	var f := FileAccess.open(STATE_PATH, FileAccess.READ)
	var data: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) != 1:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(STATE_PATH))
		return {}
	if int(data.get("career_seed", 0)) != GameState.career_seed:
		return {}  # foreign career (e.g. a test run) — leave the file for its owner
	var last := str(data.get("last_settled", ""))
	var entries: Array = data.get("entries", []) if typeof(data.get("entries")) == TYPE_ARRAY else []
	if last > GameState.current_date or entries.any(func(e): return str(e["date"]) > GameState.current_date):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(STATE_PATH))
		return {}  # sidecar is ahead of this timeline — rebuild deterministically
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STATE_PATH))
	return {"last_settled": last,
		"done_fids": data.get("done_fids", {}) if typeof(data.get("done_fids")) == TYPE_DICTIONARY else {},
		"entries": entries}


# ------------------------------------------------------------------ the tick

## Catch the economy up to today. Called from GameState's daily advance hook
## (and defensively on Inbox screen load); backfills the full season history
## on first run so an existing career gets a correct retroactive ledger (and
## the correct bank balance) immediately. Duplicate-guarded, so running it
## any number of times a day is safe.
func tick() -> void:
	var st := _state()
	if str(st["last_settled"]) == "":
		st["last_settled"] = GameState.season_start
	var positions := _table_positions()
	var done: Dictionary = st["done_fids"]

	# 1. matchday flows for every settled-but-unprocessed fixture
	for f in GameState.fixtures:
		if not f.get("played", false) or str(f["date"]) > GameState.current_date:
			continue
		var fid := str(f["id"])
		if done.has(fid):
			continue
		_settle_fixture(f, positions)
		done[fid] = true

	# 2. monthly settlements at each month boundary crossed since last tick
	while str(st["last_settled"]) < GameState.current_date:
		st["last_settled"] = Season.date_add(str(st["last_settled"]), 1)
		if str(st["last_settled"]).ends_with("-01"):
			_settle_month(str(st["last_settled"]), positions)


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
			_record(date, I18n.t("Cup gate share — vs %s (att %s)") % [opp_h, _fmt_att(att)], share, "gate")
			_record(date, I18n.t("Matchday operations — vs %s") % opp_h, -ops, "ops")
		elif we_away:
			_record(date, I18n.t("Cup gate share — at %s (att %s)") % [opp_a, _fmt_att(att)], share, "gate")
			_record(date, I18n.t("Team travel — at %s") % opp_a, -travel, "travel")
		# round prize money to the winner
		var rnd := int(f.get("round", 1))
		var prize := int(CUP_PRIZE.get(rnd, 75000))
		var home_won: bool = int(f["score_home"]) > int(f["score_away"])
		var winner := home if home_won else away
		_move(winner, prize)
		if (we_home and home_won) or (we_away and not home_won):
			_record(date, I18n.t("Prize money — %s won") % I18n.cup_round(rnd), prize, "prize")
	else:
		_move(home, gross - ops)
		_move(away, -travel)
		if we_home:
			_record(date, I18n.t("Gate receipts — vs %s (att %s)") % [opp_h, _fmt_att(att)], gross, "gate")
			_record(date, I18n.t("Matchday operations — vs %s") % opp_h, -ops, "ops")
		elif we_away:
			_record(date, I18n.t("Team travel — at %s") % opp_a, -travel, "travel")


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
	var mname: String = I18n.t(MONTH_NAMES[int(closing.split("-")[1])])

	for c in GameState.world["clubs"]:
		var rep := int(c["reputation"])
		var payroll := 0
		for inst in c["squad"]:
			payroll += int(inst["contract"]["salary"])
		var upkeep := 3200 + rep * 520
		var sponsor := rep * 1150
		var pos := int(positions.get(str(c["id"]), 8))
		var broadcast := 6000 + (16 - pos) * 550
		if GameState.league_tier(str(c.get("league", "kanto"))) == 2:
			broadcast = int(broadcast * 0.45)   # D2 TV money is a different world
		_move(c, sponsor + broadcast - payroll - upkeep)
		if GameState.is_player_club(str(c["id"])):
			_record(closing, I18n.t("Payroll — squad wages, %s (%d battlers)") %
				[mname, c["squad"].size()], -payroll, "wages")
			_record(closing, I18n.t("Facilities & staff upkeep — %s") % mname, -upkeep, "upkeep")
			_record(closing, I18n.t("Sponsorship — %s") % mname, sponsor, "sponsor")
			_record(closing, I18n.t("League broadcast & merit payment — %s (%s)") %
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
		I18n.t("Monthly finance report: %s (%s%s)") % [mname, "+" if net >= 0 else "", news.money(net)],
		I18n.t("The finance office has closed the books on %s. Operating result: %s.") %
			[mname, news.money(net)])
	var m: Dictionary = GameState.inbox[0]
	m["uid"] = uid
	m["cat"] = "board"
	m["sender"] = I18n.t("%s Finance Office") % pc["name"]
	m["month"] = month_key
	if boundary < GameState.current_date:
		m["read"] = true   # backfilled history arrives read, like other news


# ------------------------------------------------------------------ queries

## Player-club operating lines, newest first (merged into board_room's ledger).
func rows() -> Array:
	return _state()["entries"]


## All lines of one calendar month ("YYYY-MM"), oldest first.
func month_rows(month_key: String) -> Array:
	var out: Array = rows().filter(func(e): return str(e["date"]).begins_with(month_key))
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
	for e in rows():
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
	(_state()["entries"] as Array).push_front({"date": date, "text": text, "amount": amount, "kind": kind})


func _table_positions() -> Dictionary:
	var out := {}
	var t: Array = GameState.league_table()
	for i in t.size():
		out[str(t[i]["club_id"])] = i + 1
	return out


func _fmt_att(n: int) -> String:
	return I18n.number(n)


func _ord(n: int) -> String:
	return I18n.ordinal(n)
