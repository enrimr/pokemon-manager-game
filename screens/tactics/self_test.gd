extends Node
## Headless self-test for the tactics piece (not part of the game UI).
## Run: godot --headless --path . res://screens/tactics/self_test.tscn
## Prints TACTICS TEST OK on success.

const Logic := preload("res://screens/tactics/tactics_logic.gd")
const Brain := preload("res://screens/tactics/tactics_brain.gd")
const Director := preload("res://screens/tactics/tactics_director.gd")

var _fails := 0


## The critical property this piece is judged on: the plan is CONSUMED by the
## match engine — lineup picks the team, order picks the battle line, and the
## six instructions change engine decisions.
func _run_consumption_checks(p: Dictionary) -> void:
	print("=== tactics self_test: plan consumption ===")
	var club: Dictionary = GameState.player_club()
	var tac: Dictionary = Logic.plan_from_preset(p)

	# lineup_instances returns the plan's six, in slot order
	var six: Array = Logic.lineup_instances(tac, club)
	_check(six.size() == 6, "lineup_instances returns six")
	_check(six.map(func(i): return i["uid"]) == p["lineup"], "lineup_instances follows slot order")

	# benching the star: put lineup slot 1..6 = the six LOWEST-level battlers
	var weak: Array = club["squad"].duplicate()
	weak.sort_custom(func(a, b): return int(a["level"]) < int(b["level"]))
	var weak_tac: Dictionary = tac.duplicate(true)
	weak_tac["lineup"] = weak.slice(0, 6).map(func(i): return i["uid"])
	var weak_six: Array = Logic.lineup_instances(weak_tac, club)
	_check(weak_six.map(func(i): return i["uid"]) == weak_tac["lineup"],
		"benched stars stay benched — engine team comes from the plan, not level order")

	# a Brain-driven battle is legal, terminates, and is deterministic
	var opp: Dictionary = GameState.world["clubs"][1] if not GameState.is_player_club(GameState.world["clubs"][1]["id"]) else GameState.world["clubs"][2]
	var r1: Dictionary = Brain.run_fixture(club, opp, 0, tac, 123456)
	var r2: Dictionary = Brain.run_fixture(club, opp, 0, tac, 123456)
	_check(not r1.is_empty() and int(r1["score_home"]) + int(r1["score_away"]) >= 2,
		"Brain-driven best-of-3 completes (%d-%d)" % [int(r1.get("score_home", -1)), int(r1.get("score_away", -1))])
	_check(str(r1) == str(r2), "Brain-driven fixture is deterministic per seed")

	# the lineup changes the result stream (weak six vs strong six)
	var diff_lineup := false
	for s in [111, 222, 333]:
		var ra: Dictionary = Brain.run_fixture(club, opp, 0, tac, s)
		var rb: Dictionary = Brain.run_fixture(club, opp, 0, weak_tac, s)
		if str(ra) != str(rb):
			diff_lineup = true
			break
	_check(diff_lineup, "changing the lineup changes match outcomes")

	# the instructions change engine decisions (same teams, same seeds)
	var hyper: Dictionary = tac.duplicate(true)
	hyper["instructions"] = {"aggression": 4, "switch_threshold": 0,
		"status_priority": 0, "protect_lead": false, "preserve_last": false, "revenge_switch": false}
	var timid: Dictionary = tac.duplicate(true)
	timid["instructions"] = {"aggression": 0, "switch_threshold": 60,
		"status_priority": 2, "protect_lead": true, "preserve_last": true, "revenge_switch": true}
	var diff_instr := false
	for s in [17, 18, 19]:
		var ra: Dictionary = Brain.run_fixture(club, opp, 0, hyper, s)
		var rb: Dictionary = Brain.run_fixture(club, opp, 0, timid, s)
		if str(ra) != str(rb):
			diff_instr = true
			break
	_check(diff_instr, "flipping the six instructions changes engine behaviour")

	# instructions -> live-match touchline policy mapping
	var pol_a: Dictionary = Logic.instructions_to_policy(hyper["instructions"])
	var pol_b: Dictionary = Logic.instructions_to_policy(timid["instructions"])
	_check(pol_a["aggression"] == "attacking" and pol_b["aggression"] == "cautious",
		"aggression maps onto the runner's touchline policy")
	_check(pol_b["switching"] == "eager", "high switch threshold maps to eager switching")

	# director override: an auto-simmed player fixture is re-resolved with the plan
	var opp_id: String = opp["id"]
	var fake := {"id": "TESTX1", "comp": "league", "round": 99, "date": GameState.current_date,
		"home": club["id"], "away": opp_id, "played": true, "score_home": 0, "score_away": 2}
	var res: Dictionary = Director.resolve_with_plan(fake, tac)
	_check(not res.is_empty(), "director resolves a player fixture with the plan")
	_check(int(fake["score_home"]) == int(res["score_home"])
		and int(fake["score_away"]) == int(res["score_away"])
		and maxi(int(fake["score_home"]), int(fake["score_away"])) == 2,
		"plan-driven scores overwrite the fixture in place (%d-%d)" % [int(fake["score_home"]), int(fake["score_away"])])
	var meta_tac: Dictionary = GameState.world["meta"].get("tactics", {})
	_check(not meta_tac.is_empty() and meta_tac["lineup"] == p["lineup"],
		"active plan published for the director to consume")


## THE SEAM CHECK: world.meta is the single source of truth, so loading an
## OLDER save must bring back that save's plan everywhere — the engine
## (meta.tactics), the tactics screen (meta.tactics_state) and the squad
## screen's Selection tab all read the same loaded data; a stale sidecar
## from a later session can never shadow it.
func _run_save_load_checks() -> void:
	print("=== tactics self_test: save / load-older-save coherence ===")
	var Selection: GDScript = load("res://screens/squad/selection.gd")
	var state: Dictionary = Logic.load_state()
	var p := Logic.active_preset(state)

	# plan A: distinctive marker, saved
	p["instructions"]["aggression"] = 1
	Logic.save_state(state)          # persists world.meta.tactics_state + plan
	var older := FileAccess.get_file_as_string("user://save.json")
	_check(older != "", "older save captured")

	# plan B: the career moves on, tactic changes, saved again
	var l0 = p["lineup"][0]
	var l1 = p["lineup"][1]
	p["lineup"][0] = l1
	p["lineup"][1] = l0
	p["instructions"]["aggression"] = 3
	Logic.save_state(state)
	_check(int(GameState.world["meta"]["tactics"]["instructions"]["aggression"]) == 3,
		"plan B live before rollback")

	# a stale sidecar from an even newer session lies in wait
	var side := FileAccess.open(Logic.TACTICS_PATH, FileAccess.WRITE)
	side.store_string(JSON.stringify({"version": 1, "active": "Ghost",
		"presets": [{"name": "Ghost", "lineup": [], "bench": [], "roles": {},
			"instructions": {"aggression": 4}}]}))
	side = null

	# roll back to the older save
	var f := FileAccess.open("user://save.json", FileAccess.WRITE)
	f.store_string(older)
	f = null
	_check(GameState.load_game(), "older save loads")
	var meta_tac: Dictionary = GameState.world["meta"].get("tactics", {})
	_check(int(meta_tac.get("instructions", {}).get("aggression", -1)) == 1,
		"engine plan (meta.tactics) is the OLDER save's plan A")
	_check(str(meta_tac["lineup"][0]) == str(l0),
		"older save's lineup order restored")
	var reloaded := Logic.load_state()
	_check(str(reloaded["active"]) != "Ghost"
		and int(Logic.active_preset(reloaded)["instructions"]["aggression"]) == 1,
		"tactics screen state comes from the save, not the stale sidecar")
	var sel: Dictionary = Selection.selection()
	_check(str(sel["source"]) == "tactic", "squad Selection reads a tactic")
	var sel_first := ""
	for u in sel["slot"]:
		if int(sel["slot"][u]) == 1:
			sel_first = str(u)
	_check(sel_first == str(meta_tac["lineup"][0]),
		"squad Selection slot 1 == engine plan slot 1 (same source)")
	Logic.remove_legacy_sidecar()


# ------------------------------------------------------------- save guard

var _save_backup := ""
var _had_save := false


func _backup_save() -> void:
	_had_save = FileAccess.file_exists("user://save.json")
	if _had_save:
		_save_backup = FileAccess.get_file_as_string("user://save.json")


func _restore_save() -> void:
	if _had_save:
		var f := FileAccess.open("user://save.json", FileAccess.WRITE)
		f.store_string(_save_backup)
	elif FileAccess.file_exists("user://save.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.json"))


func _ready() -> void:
	_run.call_deferred()


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: %s" % label)
	else:
		_fails += 1
		printerr("  FAIL: %s" % label)


func _run() -> void:
	await get_tree().process_frame
	# Protect the player's real career: everything below mutates + saves.
	_backup_save()
	# Deterministic start: wipe any preset state left by earlier runs
	# (single source of truth lives in world.meta; legacy sidecar removed too).
	GameState.world["meta"].erase("tactics_state")
	GameState.world["meta"].erase("tactics")
	Logic.remove_legacy_sidecar()
	var scr: Control = load("res://screens/tactics/screen.tscn").instantiate()
	get_tree().root.add_child(scr)
	await get_tree().process_frame
	await get_tree().process_frame

	var p: Dictionary = Logic.active_preset(scr._state)
	_check(p["lineup"].size() == 6, "lineup has 6 slots")
	_check(p["lineup"].size() + p["bench"].size() == GameState.player_club()["squad"].size(),
		"lineup+bench covers whole squad")

	# swap within starters
	var a0: String = p["lineup"][0]
	var a2: String = p["lineup"][2]
	scr._swap(a0, a2)
	_check(p["lineup"][0] == a2 and p["lineup"][2] == a0, "starter<->starter swap")

	# swap starter <-> bench
	var s5: String = p["lineup"][5]
	var b0: String = p["bench"][0]
	scr._swap(s5, b0)
	_check(p["lineup"][5] == b0 and p["bench"][0] == s5, "starter<->bench swap")

	# nudge
	var l1: String = p["lineup"][1]
	scr._nudge(l1, -1)
	_check(p["lineup"][0] == l1, "nudge up moves slot 2 to slot 1")
	scr._nudge(l1, -1)
	_check(p["lineup"][0] == l1, "nudge up at slot 1 is a no-op")

	# role change
	var uid: String = p["lineup"][3]
	scr._on_role_changed(uid, "wall")
	_check(p["roles"][uid] == "wall", "role assignment stored")

	# role scoring sanity
	var inst_by_uid := {}
	for inst in GameState.player_club()["squad"]:
		inst_by_uid[inst["uid"]] = inst
	var an: Dictionary = Logic.analyze(inst_by_uid[uid])
	for rid in Logic.ROLE_ORDER:
		var sc: int = Logic.role_score(rid, an)["score"]
		_check(sc >= 1 and sc <= 99, "role %s score in range (%d)" % [rid, sc])

	# instructions persist — SINGLE SOURCE OF TRUTH: everything in the save
	p["instructions"]["aggression"] = 4
	p["instructions"]["protect_lead"] = false
	scr._do_save()
	_check(not FileAccess.file_exists(Logic.TACTICS_PATH),
		"legacy sidecar user://tactics.json is retired (not written)")
	var sf := FileAccess.open("user://save.json", FileAccess.READ)
	var save: Dictionary = JSON.parse_string(sf.get_as_text())
	var dp: Dictionary = Logic.active_preset(save["world"]["meta"]["tactics_state"])
	_check(int(dp["instructions"]["aggression"]) == 4, "instructions saved inside save.json (meta.tactics_state)")
	_check(dp["lineup"] == p["lineup"], "lineup order saved inside save.json")
	var gt: Dictionary = GameState.world["meta"]["tactics"]
	_check(gt["lineup"] == p["lineup"], "lineup published to GameState.world.meta.tactics")
	_check(gt["roles"][uid] == "wall", "roles published to GameState")
	_check(save["world"]["meta"]["tactics"]["lineup"] == p["lineup"],
		"active plan persisted inside save.json")

	# preset create / rename / switch / delete
	var before: int = scr._state["presets"].size()
	scr._on_new_preset()
	_check(scr._state["presets"].size() == before + 1, "new preset created")
	scr._rename_edit.text = "Cup Special"
	scr._do_rename()
	_check(scr._state["active"] == "Cup Special", "preset renamed + active")
	scr._on_preset_pick(0)
	_check(scr._state["active"] == scr._state["presets"][0]["name"], "preset switch")
	scr._on_preset_pick(1)
	scr._do_delete()
	_check(scr._state["presets"].size() == before, "preset deleted")
	_check(scr._state["active"] == scr._state["presets"][0]["name"], "active falls back after delete")

	# auto-pick keeps a full lineup and a lead in slot 1
	scr._on_auto_pick()
	p = Logic.active_preset(scr._state)
	_check(p["lineup"].size() == 6, "auto-pick fills six")
	_check(p["roles"][p["lineup"][0]] == "lead", "auto-pick assigns Lead to slot 1")
	scr._do_save()

	_run_consumption_checks(p)
	_run_save_load_checks()

	# Restore the player's real save so test edits don't leak into play.
	_restore_save()

	if _fails == 0:
		print("TACTICS TEST OK")
		get_tree().quit(0)
	else:
		printerr("TACTICS TEST FAILED: %d" % _fails)
		get_tree().quit(1)
