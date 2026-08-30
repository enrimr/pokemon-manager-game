extends Node
## PROOF DRIVER for the scouting discovery economy. Run:
##   Godot --headless --path . res://screens/transfers/coverage_driver.tscn
##
## Simulates 60 real career days with ONE scout permanently busy on dedicated
## target watches (auto-reassigned to the next priority target the moment a
## full report lands). Proves:
##   1. the scoutable universe is season-sized (600+ targets),
##   2. knowledge climbs in visible STAGES (rumour -> interim -> full),
##   3. one scout deep-covers only a tiny fraction of the market in 60 days,
##   4. determinism + save/load integrity of the whole knowledge base.
## Prints COVERAGE DRIVER OK on success.

const Market := preload("res://screens/transfers/market.gd")
const SaveGuard := preload("res://tools/save_guard.gd")

var _fail := 0


func _ok(cond: bool, label: String) -> void:
	if cond:
		print("  ok: %s" % label)
	else:
		_fail += 1
		printerr("  FAIL: %s" % label)


func _stage_histogram(m: RefCounted, targets: Array) -> Dictionary:
	var hist := {}
	for s in m.STAGES:
		hist[String(s["name"])] = 0
	for t in targets:
		var nm := String(m.stage_for(m.knowledge_of(String(t["inst"]["uid"])))["name"])
		hist[nm] = int(hist[nm]) + 1
	return hist


func _hist_line(hist: Dictionary) -> String:
	var parts: Array = []
	for k in hist:
		if int(hist[k]) > 0:
			parts.append("%s %d" % [k, int(hist[k])])
	return " · ".join(parts)


func _ready() -> void:
	await get_tree().process_frame
	SaveGuard.backup()
	GameState.delete_save()
	GameState.auto_sim_player_matches = true
	GameState.new_career()
	if FileAccess.file_exists("user://transfers.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://transfers.json"))
	Market._inst = null
	var m: RefCounted = Market.instance()

	print("=== coverage driver: 60 days, one scout, the whole market ===")
	var targets: Array = m.all_targets()
	var market_n: int = targets.size()
	_ok(market_n > 600, "scoutable universe: %d targets" % market_n)

	# one scout — the best judge on staff — works dedicated watches non-stop
	var scouts: Array = m.player_scouts()
	scouts.sort_custom(func(a, b): return int(a["ratings"]["judging_ability"]) > int(b["ratings"]["judging_ability"]))
	var scout: Dictionary = scouts[0]
	var sname := String(scout["name"])
	print("  scout: %s (JA %d, home %s)" % [sname, int(scout["ratings"]["judging_ability"]), m.scout_region(scout)])

	# priority queue: highest-value club targets first (what a manager would do)
	var queue: Array = targets.filter(func(t): return t["pool"] == "club")
	queue.sort_custom(func(a, b): return m.value_of(a["inst"]) > m.value_of(b["inst"]))
	var qi := 0

	var seen_stages := {}
	for day in 60:
		if m.assignment_for_scout(sname).is_empty():
			while qi < queue.size():
				var uid := String(queue[qi]["inst"]["uid"])
				qi += 1
				if m.knowledge_of(uid) < 100.0 and m.assign_scout_to_target(sname, uid) == "":
					break
		GameState.advance_day()
		var a: Dictionary = m.assignment_for_scout(sname)
		if not a.is_empty():
			seen_stages[String(m.knowledge_stage(String(a["uid"]))["name"])] = true
		if (day + 1) % 15 == 0:
			var hist := _stage_histogram(m, m.all_targets())
			print("  day %2d: %s" % [day + 1, _hist_line(hist)])

	var final_targets: Array = m.all_targets()
	var hist := _stage_histogram(m, final_targets)
	var full := 0
	var touched := 0
	for t in final_targets:
		var k: float = m.knowledge_of(String(t["inst"]["uid"]))
		if k >= 100.0:
			full += 1
		if k > 0.0:
			touched += 1
	var pct := float(full) / float(market_n) * 100.0
	print("  after 60 days: %d full reports, %d targets touched, market %d" % [full, touched, market_n])
	print("  deep coverage by one scout in 60 days: %d/%d = %.1f%% of the market" % [full, market_n, pct])
	_ok(full >= 2, "the scout DID produce full reports (%d)" % full)
	_ok(pct < 3.0, "one scout deep-covers under 3%% of the market in 60 days (%.1f%%)" % pct)
	_ok(seen_stages.size() >= 3, "knowledge stages visibly progressed through the run: %s" % ", ".join(seen_stages.keys()))
	_ok(int(hist.get("Rumour", 0)) + int(hist.get("Initial assessment", 0)) + int(hist.get("Part scouted", 0))
		+ int(hist.get("Detailed", 0)) >= 1, "intermediate stages present at day 60 (%s)" % _hist_line(hist))
	_ok(int(hist.get("Untracked", 0)) > market_n / 2, "most of the market is still dark — a season of prioritisation ahead")

	print("=== coverage driver: interim reports + bands ===")
	var interim := 0
	var full_r := 0
	for uidr in m.reports:
		var r: Dictionary = m.reports[uidr]
		if String(r.get("stage", "")) == "interim":
			interim += 1
			_ok(float(r["ability_lo"]) <= float(r["ability_hi"]), "interim band well-formed for %s" % r["name"])
			break
	for uidr2 in m.reports:
		if String(m.reports[uidr2].get("stage", "")) == "full":
			full_r += 1
	_ok(full_r >= 2, "full written reports on file (%d)" % full_r)

	print("=== coverage driver: determinism + save/load ===")
	var know_snapshot := {}
	for k2 in m.knowledge:
		know_snapshot[k2] = float(m.knowledge[k2])
	var ext_uid_0 := String(m.ext_clubs()[0]["squad"][0]["uid"])
	var ext_lv_0 := int(m.ext_clubs()[0]["squad"][0]["level"])
	m.save_state()
	m._load_state()
	var same := true
	for k3 in know_snapshot:
		if absf(float(m.knowledge.get(k3, -1.0)) - float(know_snapshot[k3])) > 0.001:
			same = false
	_ok(same and m.knowledge.size() == know_snapshot.size(), "knowledge base survives save/load byte-true (%d entries)" % m.knowledge.size())
	m._ext_built_seed = -2
	m._ensure_ext_world()
	_ok(String(m.ext_clubs()[0]["squad"][0]["uid"]) == ext_uid_0 and int(m.ext_clubs()[0]["squad"][0]["level"]) == ext_lv_0,
		"external world regenerates identically from the career seed")

	SaveGuard.restore()
	if _fail == 0:
		print("COVERAGE DRIVER OK")
		get_tree().quit(0)
	else:
		printerr("COVERAGE DRIVER FAILED (%d)" % _fail)
		get_tree().quit(1)
