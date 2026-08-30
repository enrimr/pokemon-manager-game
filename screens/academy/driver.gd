extends Node
## Headless proof driver for the academy piece (builder verification only).
## Run: Godot --headless --path . res://screens/academy/driver.tscn
## Proves: 3 monthly intakes over a simmed quarter, daily development,
## a promotion (squad-cap aware), a board-funded facility upgrade that
## changes intake quality, breeding-bias weighting, save/load persistence.
## The player's real save is backed up and restored (tools/save_guard.gd).

const SaveGuard := preload("res://tools/save_guard.gd")
const Academy := preload("res://shared/sim/services/academy.gd")

var _log: Array = []
var _fails := 0


func _out(line: String) -> void:
	print(line)
	_log.append(line)


func _check(ok: bool, what: String) -> void:
	_out(("  OK  " if ok else "  FAIL  ") + what)
	if not ok:
		_fails += 1


func _ready() -> void:
	SaveGuard.backup()
	GameState.delete_save()
	GameState.new_career(424242)
	var svc: RefCounted = Academy.active
	_out("=== academy driver (seed 424242, start %s) ===" % GameState.current_date)
	_check(svc != null, "AcademyService discovered by the services convention")
	_check(svc.facility_level == 1, "facility starts at level 1")

	# --- breeding bias: weighted pool sanity -------------------------------
	var squad: Array = GameState.player_club()["squad"]
	var squad_ids := {}
	var squad_types := {}
	for inst in squad:
		squad_ids[int(inst["species_id"])] = true
		for t in DataStore.species(int(inst["species_id"])).get("types", []):
			squad_types[t] = true
	var squad_roots := {}
	for id in squad_ids:
		squad_roots[svc._root_of(int(id))] = true
	var pool: Array = svc._weighted_pool()
	var w_own := -1.0
	var w_plain := -1.0
	for e in pool:
		var id := int(e[0]["id"])
		var shares := false
		for t in e[0]["types"]:
			if squad_types.has(t):
				shares = true
		if squad_roots.has(svc._root_of(id)) and float(e[1]) > w_own:
			w_own = float(e[1])
		if (not squad_roots.has(svc._root_of(id))) and (not shares) and w_plain < 0.0:
			w_plain = float(e[1])
	_check(w_own > w_plain + 10.0, "breeding bias: own-line weight %.1f >> unrelated %.1f" % [w_own, w_plain])

	# --- a simmed quarter: 3 monthly intakes + development ------------------
	var inbox_before := GameState.inbox.size()
	for i in 95:
		GameState.advance_day()
	_out("advanced 95 days -> %s" % GameState.current_date)
	_check(svc.history.size() == 3, "3 monthly intakes over the quarter (got %d)" % svc.history.size())
	_check(svc.roster.size() >= 6, "roster holds the intakes (%d juveniles)" % svc.roster.size())
	var intake_msgs := 0
	for msg in GameState.inbox:
		if String(msg["title"]).begins_with("Youth intake day"):
			intake_msgs += 1
	_check(intake_msgs == 3, "3 FM-style intake reports in the inbox")
	var sizes_ok := true
	for h in svc.history:
		if int(h["count"]) < 2 or int(h["count"]) > 5:
			sizes_ok = false
	_check(sizes_ok, "every intake batch is 2-5 juveniles")
	var grown := 0
	var share := 0
	for m in svc.roster:
		if int(m["level"]) > 6 or float(m["xp"]) > 0.0:
			grown += 1
		for t in DataStore.species(int(m["species_id"])).get("types", []):
			if squad_types.has(t):
				share += 1
				break
	_check(grown == svc.roster.size(), "daily development ticked for every academy mon")
	_out("  info: %d/%d recruits share a type with the first-team squad" % [share, svc.roster.size()])
	var oldest: Dictionary = svc.roster[0]
	_check(int(oldest["level"]) > 6, "oldest recruit levelled up (Lv %d, joined %s)" % [int(oldest["level"]), String(oldest["joined"])])
	_check(int(oldest["pot_max"]) - int(oldest["pot_min"]) <= 8, "coach band narrows with time (width %d)" % (int(oldest["pot_max"]) - int(oldest["pot_min"])))

	# --- promotion -----------------------------------------------------------
	var best: Dictionary = svc.roster[0]
	for m in svc.roster:
		if int(m["pot_max"]) > int(best["pot_max"]):
			best = m
	var uid := String(best["uid"])
	var squad_n := squad.size()
	var err: String = svc.promote(uid)
	_check(err == "", "promotion accepted (%s)" % best["species"])
	_check(squad.size() == squad_n + 1, "first-team squad grew to %d" % squad.size())
	var in_squad := false
	for inst in squad:
		if String(inst["uid"]) == uid:
			in_squad = inst.get("from_academy", false) and inst["contract"]["salary"] > 0
	_check(in_squad, "promoted mon carries a real contract + from_academy flag")
	_check(svc.find(uid).is_empty(), "promoted mon left the academy roster")
	var battler: Dictionary = DataStore.make_battler(GameState.squad_member(uid))
	_check(not battler.is_empty() and battler["stats"]["hp"] > 0, "promoted instance builds a valid battler")
	# squad cap enforcement
	while squad.size() < svc.FIRST_TEAM_CAP:
		squad.append(squad[0].duplicate(true))
	var cap_err: String = svc.promote(String(svc.roster[0]["uid"]))
	_check(cap_err != "", "promotion refused at the %d-mon squad cap" % svc.FIRST_TEAM_CAP)
	while squad.size() > squad_n + 1:
		squad.pop_back()

	# --- facility upgrade via board request ---------------------------------
	GameState.player_club()["finances"]["balance"] = 3000000
	_check(svc.request_upgrade() == "", "board request submitted (L2, %s)" % Academy.format_money(svc.upgrade_cost()))
	_check(svc.request_upgrade() != "", "duplicate request rejected while pending")
	# surgical payment check: fire the decision tick directly, then let the
	# normal daily loop finish construction.
	var fin: Dictionary = GameState.player_club()["finances"]
	var b_before: int = fin["balance"]
	svc._tick_upgrade(String(svc.pending["decide_on"]))
	_check(String(svc.pending.get("status", "")) == "building", "board approved on decision day")
	_check(int(fin["balance"]) == b_before - 250000, "club funds paid exactly the 250k cost")
	for i in 16:
		GameState.advance_day()
	_check(svc.facility_level == 2, "construction complete -> facility level 2")

	# --- facility level changes intake quality (deterministic) --------------
	var lo_svc: RefCounted = Academy.new()
	lo_svc._gs = GameState
	lo_svc.facility_level = 1
	lo_svc._run_intake("2027-03-15")
	var hi_svc: RefCounted = Academy.new()
	hi_svc._gs = GameState
	hi_svc.facility_level = 5
	hi_svc._run_intake("2027-03-15")
	var lo_avg := 0.0
	for m in lo_svc.roster:
		lo_avg += float(m["potential"]) / float(lo_svc.roster.size())
	var hi_avg := 0.0
	for m in hi_svc.roster:
		hi_avg += float(m["potential"]) / float(hi_svc.roster.size())
	_out("  info: same month, facility 1 -> %d recruits avg pot %.1f; facility 5 -> %d avg pot %.1f" % [
		lo_svc.roster.size(), lo_avg, hi_svc.roster.size(), hi_avg])
	_check(hi_avg > lo_avg, "higher facility level -> higher intake potential")
	_check(hi_svc.roster.size() >= lo_svc.roster.size(), "higher facility level -> at least as many recruits")

	# --- save/load roundtrip -------------------------------------------------
	var snap := {
		"fac": svc.facility_level, "n": svc.roster.size(), "hist": svc.history.size(),
		"uid0": String(svc.roster[0]["uid"]), "lv0": int(svc.roster[0]["level"]),
		"focus0": String(svc.roster[0]["focus"]), "next_uid": svc.next_uid,
	}
	svc.set_focus(snap["uid0"], "special")
	snap["focus0"] = "special"
	_check(GameState.save_game(), "save_game succeeds")
	_check(GameState.load_game(), "load_game succeeds")
	var svc2: RefCounted = Academy.active
	_check(svc2 != null and svc2 != svc, "a fresh service instance took over after load")
	_check(svc2.facility_level == snap["fac"] and svc2.roster.size() == snap["n"]
		and svc2.history.size() == snap["hist"] and svc2.next_uid == snap["next_uid"],
		"facility/roster/history/uid counter survive save/load")
	var m0: Dictionary = svc2.find(String(snap["uid0"]))
	_check(not m0.is_empty() and int(m0["level"]) == int(snap["lv0"])
		and String(m0["focus"]) == "special", "per-mon level + training focus survive save/load")
	var d0: String = GameState.current_date
	GameState.advance_day()
	_check(GameState.current_date > d0, "loaded career keeps ticking")

	# --- wrap up -------------------------------------------------------------
	GameState.delete_save()
	SaveGuard.restore()
	var out_dir := ProjectSettings.globalize_path("res://").path_join("artifacts/academy")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var f := FileAccess.open(out_dir.path_join("driver_log.txt"), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_log) + "\n")
	if _fails == 0:
		print("ACADEMY DRIVER OK")
	else:
		print("ACADEMY DRIVER FAILED (%d checks)" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
