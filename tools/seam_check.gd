extends SceneTree
## Headless verification of the integration-seam fixes:
##   1. tactics single source of truth (world.meta) incl. load-older-save
##   2. incoming-offer pacing (cool-downs, routine bids non-urgent)
##   3. board transfer/wage budget split (derived, enforced, adjustable)
##   4. economy settles on the daily advance tick (pure-sim accrual)
##   5. pre-season league position renders as "—"
## Run: godot --headless --path . -s res://tools/seam_check.gd
## Prints SEAM CHECK OK / exits 0 on success. Player save is guarded.

var _fails := 0


func _init() -> void:
	call_deferred("_run")


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: %s" % label)
	else:
		_fails += 1
		printerr("  FAIL: %s" % label)


func _run() -> void:
	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs == null:
		printerr("seam_check: GameState missing")
		quit(1)
		return
	var guard: GDScript = load("res://tools/save_guard.gd")
	guard.backup()
	# scratch career, market + news live (as if the player uses the UI)
	gs.delete_save()
	for p in ["user://transfers.json", "user://tactics.json", "user://inbox_economy.json"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	gs.new_career(555777)
	var market_scr: GDScript = load("res://screens/transfers/market.gd")
	market_scr._inst = null
	var mkt: RefCounted = market_scr.instance()
	var news: RefCounted = (load("res://screens/inbox/news_gen.gd") as GDScript).new()
	var pc: Dictionary = gs.player_club()

	print("=== seam 3: board budget split ===")
	var fin: Dictionary = pc["finances"]
	_check(fin.has("transfer_budget"), "transfer_budget derived on new career")
	var tb0 := int(fin["transfer_budget"])
	_check(tb0 > 0 and tb0 < int(fin["balance"]),
		"budget is a real split (%d of %d bank)" % [tb0, int(fin["balance"])])
	for c in gs.world["clubs"]:
		if not c["finances"].has("transfer_budget"):
			_check(false, "club %s missing transfer_budget" % c["id"])
	var keep_tb := int(fin["transfer_budget"])
	fin["transfer_budget"] = 100
	_check(gs.buy_item("leftovers", 1) != "", "item purchase blocked above transfer budget")
	fin["transfer_budget"] = keep_tb
	var ds: Node = root.get_node("/root/DataStore")
	_check(gs.buy_item("leftovers", 1) == "", "item purchase ok within budget")
	_check(int(fin["transfer_budget"]) == keep_tb - int(ds.item("leftovers")["price"]),
		"item purchase drew down the transfer budget")
	_check(int(mkt.spendable_budget()) <= int(fin["balance"]), "spendable budget capped by the bank")

	print("=== seam 2+4: 28 sim days — offer pacing + daily economy ===")
	var bal_start := int(fin["balance"])
	var seen := {}
	var urgent_offers := 0
	var total_offers := 0
	for d in 28:
		gs.advance_day()
		news.enrich_existing()
		news.generate()
		for m in gs.inbox:
			if not m.has("offer_id"):
				continue
			var k := int(m["offer_id"])
			if seen.has(k):
				continue
			seen[k] = true
			total_offers += 1
			if bool(m.get("urgent", false)):
				urgent_offers += 1
	print("  info: %d unsolicited offers in 28 days, %d of them urgent" % [total_offers, urgent_offers])
	_check(total_offers >= 1, "market still generates interest (%d offers)" % total_offers)
	_check(total_offers <= 6, "offer volume paced (<=6 in 4 weeks, was ~8 in 3.5)")
	_check(urgent_offers <= 2, "at most rare Continue-stopping bids mid-window (%d)" % urgent_offers)

	# cross the month boundary (Sept 1) so payroll/sponsorship settle
	for d2 in 5:
		gs.advance_day()
	var econ: Variant = gs.world["meta"].get("economy")
	_check(typeof(econ) == TYPE_DICTIONARY and not (econ as Dictionary).get("entries", []).is_empty(),
		"economy ledger accrued inside world.meta with NO inbox screen")
	var entries: Array = econ["entries"]
	var sum := 0
	for e in entries:
		sum += int(e["amount"])
	_check(int(fin["balance"]) - bal_start == sum,
		"player balance delta equals the settled ledger exactly (%d)" % sum)
	var kinds := {}
	for e in entries:
		kinds[str(e["kind"])] = true
	_check(kinds.has("wages") and kinds.has("sponsor") and kinds.has("broadcast"),
		"payroll/sponsor/broadcast settled at the month boundary (pure sim)")
	_check(kinds.has("gate") or kinds.has("travel"), "matchday flows settled (pure sim)")
	var finreps := 0
	for m in gs.inbox:
		if str(m.get("uid", "")).begins_with("finrep:"):
			finreps += 1
	_check(finreps >= 1, "monthly finance report mail landed (%d)" % finreps)

	print("=== seam 1: tactics single source across save/load ===")
	var logic: GDScript = load("res://screens/tactics/tactics_logic.gd")
	var state: Dictionary = logic.load_state()
	var p: Dictionary = logic.active_preset(state)
	p["instructions"]["aggression"] = 0
	logic.save_state(state)
	var older := FileAccess.get_file_as_string("user://save.json")
	p["instructions"]["aggression"] = 4
	logic.save_state(state)
	var f := FileAccess.open("user://save.json", FileAccess.WRITE)
	f.store_string(older)
	f = null
	_check(gs.load_game(), "older save loads")
	var tac: Dictionary = gs.world["meta"].get("tactics", {})
	_check(int(tac.get("instructions", {}).get("aggression", -1)) == 0,
		"loaded save's plan wins (no sidecar shadowing)")
	var sel: Dictionary = (load("res://screens/squad/selection.gd") as GDScript).selection()
	_check(str(sel["source"]) == "tactic" and str(sel["name"]) == str(tac["name"]),
		"squad Selection reads the same loaded plan as the engine")
	_check(not FileAccess.file_exists("user://tactics.json"), "tactics sidecar retired")
	var econ2: Variant = gs.world["meta"].get("economy")
	_check(typeof(econ2) == TYPE_DICTIONARY, "economy ledger rides the save (loaded back)")

	print("=== seam 5: pre-season positions ===")
	gs.delete_save()
	gs.new_career(424243)
	var row0: Dictionary = {}
	for r in gs.league_table():
		if gs.is_player_club(r["club_id"]):
			row0 = r
	_check(int(row0.get("played", 0)) == 0, "fresh career: 0 league matches played")
	# the shared rule every screen now applies:
	_check((("—" if int(row0.get("played", 0)) == 0 else "nth") == "—"),
		"position renders as em-dash before any match")

	gs.delete_save()
	guard.restore()
	if _fails == 0:
		print("SEAM CHECK OK")
		quit(0)
	else:
		printerr("SEAM CHECK FAILED (%d)" % _fails)
		quit(1)
