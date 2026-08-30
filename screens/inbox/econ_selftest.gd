extends SceneTree
## Inbox piece: headless self-test for economy.gd (operating cash flow).
## Verifies against the CURRENT save that:
##   1. ticking the economy actually moves the player club's bank balance
##   2. the balance delta equals the sum of the recorded ledger entries exactly
##   3. wages/gates/sponsorship/broadcast lines all exist with sane signs
##   4. a second tick is a no-op (duplicate-guarded)
##   5. monthly finance report mail landed for every completed month
##   6. AI club balances move too (whole-league economy)
## Run: godot --headless --path . -s res://screens/inbox/econ_selftest.gd

var _fails := 0


func _init() -> void:
	call_deferred("_run")


func _check(cond: bool, label: String, detail: String = "") -> void:
	if cond:
		print("  ok: %s" % label)
	else:
		_fails += 1
		printerr("  FAIL: %s %s" % [label, detail])


func _run() -> void:
	var gs := root.get_node_or_null("/root/GameState")
	if gs == null:
		printerr("econ_selftest: GameState autoload missing")
		quit(1)
		return
	print("=== econ_selftest @ %s ===" % gs.current_date)
	var news: RefCounted = (load("res://screens/inbox/news_gen.gd") as GDScript).new()
	var economy: RefCounted = (load("res://screens/inbox/economy.gd") as GDScript).new(news)

	var pc: Dictionary = gs.player_club()
	var before := int(pc["finances"]["balance"])
	var ai_before := {}
	for c in gs.world["clubs"]:
		if not gs.is_player_club(str(c["id"])):
			ai_before[str(c["id"])] = int(c["finances"]["balance"])
	var entries_before: int = economy.rows().size()

	economy.tick()

	var after := int(pc["finances"]["balance"])
	var new_entries: Array = economy.rows().slice(0, economy.rows().size() - entries_before)
	var applied := 0
	for e in new_entries:
		applied += int(e["amount"])
	print("  info: balance %d -> %d (delta %d) across %d new ledger lines" %
		[before, after, after - before, new_entries.size()])
	_check(after != before or new_entries.is_empty(),
		"balance moved when entries were recorded")
	_check(after - before == applied,
		"balance delta equals sum of recorded entries",
		"(delta %d vs entries %d)" % [after - before, applied])

	# kinds present with correct signs
	var kinds := {}
	for e in economy.rows():
		var k := str(e["kind"])
		kinds[k] = int(kinds.get(k, 0)) + int(e["amount"])
	for k in ["wages", "upkeep", "ops", "travel"]:
		if kinds.has(k):
			_check(int(kinds[k]) < 0, "'%s' lines are debits (total %d)" % [k, int(kinds[k])])
	for k in ["gate", "sponsor", "broadcast", "prize"]:
		if kinds.has(k):
			_check(int(kinds[k]) > 0, "'%s' lines are credits (total %d)" % [k, int(kinds[k])])
	var played_home := 0
	for f in gs.fixtures:
		if f.get("played", false) and gs.is_player_club(str(f["home"])):
			played_home += 1
	if played_home > 0:
		_check(kinds.has("gate"), "gate receipts exist (%d home fixtures played)" % played_home)
	if str(gs.current_date) > "%s-01" % _next_month(str(gs.season_start).substr(0, 7)):
		_check(kinds.has("wages"), "payroll was debited at a month boundary")
		_check(kinds.has("sponsor") and kinds.has("broadcast"), "monthly sponsor/broadcast income exists")

	# idempotence
	var mid := int(pc["finances"]["balance"])
	var n_mid: int = economy.rows().size()
	economy.tick()
	_check(int(pc["finances"]["balance"]) == mid and economy.rows().size() == n_mid,
		"second tick is a no-op (no double-charging)")

	# monthly report mail for each completed month
	var mk := str(gs.season_start).substr(0, 7)
	var now_mk := str(gs.current_date).substr(0, 7)
	while mk < now_mk:
		var uid := "finrep:%s" % mk
		var found: bool = gs.inbox.any(func(m): return str(m.get("uid", "")) == uid)
		_check(found, "monthly finance report mail exists (%s)" % uid)
		mk = _next_month(mk)

	# the monthly report mail renders a real P&L (report_gen)
	var reports: RefCounted = (load("res://screens/inbox/report_gen.gd") as GDScript).new(news)
	var board: RefCounted = (load("res://screens/inbox/board_room.gd") as GDScript).new(news)
	board.economy = economy
	reports.board = board
	reports.economy = economy
	for m in gs.inbox:
		if str(m.get("uid", "")).begins_with("finrep:"):
			var r: Dictionary = reports.render(m)
			var bb := str(r.get("bbcode", ""))
			_check(bb.contains("INCOME") and bb.contains("EXPENDITURE")
				and bb.contains("OPERATING RESULT") and bb.contains("Payroll"),
				"finance report mail renders full P&L (%s)" % str(m["uid"]))
			break

	# AI clubs run the same economy (only checkable once flows have occurred)
	if not new_entries.is_empty():
		var moved := 0
		for cid in ai_before:
			if int(gs.club(cid)["finances"]["balance"]) != int(ai_before[cid]):
				moved += 1
		_check(moved == ai_before.size(), "all %d AI club balances moved (%d did)" % [ai_before.size(), moved])
	else:
		print("  info: no new flows this run (day-0 career) — AI check skipped")

	gs.save_game()
	if _fails == 0:
		print("ECON SELFTEST OK")
		quit(0)
	else:
		printerr("ECON SELFTEST FAILED (%d)" % _fails)
		quit(1)


func _next_month(mk: String) -> String:
	var y := int(mk.substr(0, 4))
	var m := int(mk.substr(5, 2)) + 1
	if m > 12:
		m = 1
		y += 1
	return "%04d-%02d" % [y, m]
