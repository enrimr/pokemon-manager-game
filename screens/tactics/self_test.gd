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
	# Deterministic start: earlier runs leave presets behind in user://tactics.json.
	if FileAccess.file_exists(Logic.TACTICS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Logic.TACTICS_PATH))
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

	# instructions persist
	p["instructions"]["aggression"] = 4
	p["instructions"]["protect_lead"] = false
	scr._do_save()
	var f := FileAccess.open("user://tactics.json", FileAccess.READ)
	var disk: Dictionary = JSON.parse_string(f.get_as_text())
	var dp: Dictionary = Logic.active_preset(disk)
	_check(int(dp["instructions"]["aggression"]) == 4, "instructions saved to user://tactics.json")
	_check(dp["lineup"] == p["lineup"], "lineup order saved to disk")
	var gt: Dictionary = GameState.world["meta"]["tactics"]
	_check(gt["lineup"] == p["lineup"], "lineup published to GameState.world.meta.tactics")
	_check(gt["roles"][uid] == "wall", "roles published to GameState")
	var sf := FileAccess.open("user://save.json", FileAccess.READ)
	var save: Dictionary = JSON.parse_string(sf.get_as_text())
	_check(save["world"]["meta"]["tactics"]["lineup"] == p["lineup"],
		"tactics persisted inside save.json")

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

	# Leave the user dir the way a fresh career expects it: default plan,
	# republished, so test edits (hyper-aggression etc.) don't leak into play.
	if FileAccess.file_exists(Logic.TACTICS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Logic.TACTICS_PATH))
	Logic.save_state(Logic.load_state())

	if _fails == 0:
		print("TACTICS TEST OK")
		get_tree().quit(0)
	else:
		printerr("TACTICS TEST FAILED: %d" % _fails)
		get_tree().quit(1)
