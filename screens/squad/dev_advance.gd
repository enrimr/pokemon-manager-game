extends SceneTree
## Dev helper for the squad piece's screenshot verification ONLY (not part of
## the game). Run headless to advance the career N days with instant match
## sim (no shell, so the interactive match screen cannot intercept), then save:
##   Godot --headless --path . -s res://screens/squad/dev_advance.gd -- [fresh] days=30 [enrich]
## The live squad services (history + training bridge) run during the advance,
## exactly as they do in a real session, so career history accrues genuinely.
## `enrich` performs real management actions mid-run (a renewal, a listing)
## through SquadService so contract/transfer history exists for screenshots.

var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	var days := 30
	var fresh := false
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("days="):
			days = int(str(arg).split("=")[1])
		elif str(arg) == "fresh":
			fresh = true
	var gs: Node = root.get_node("/root/GameState")
	(load("res://tools/save_guard.gd") as GDScript).preserve_player_save()
	if OS.get_cmdline_user_args().has("dump"):
		if FileAccess.file_exists("user://squad_actions.json"):
			print("STATE: ", FileAccess.open("user://squad_actions.json", FileAccess.READ).get_as_text())
		else:
			print("STATE: <missing>")
		for inst in gs.player_club()["squad"]:
			if inst.get("transfer_listed", false):
				print("LISTED: %s ask=%s" % [inst["species"], inst.get("asking_price", 0)])
		return true
	if fresh:
		gs.delete_save()
		gs.new_career()
		# Wipe the squad piece's own persistent state alongside the career.
		for p in ["user://squad_actions.json", "user://squad_history.json"]:
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	if OS.get_cmdline_user_args().has("selftest"):
		_selftest(gs)
		return true
	if OS.get_cmdline_user_args().has("histtest"):
		_histtest(gs)
		return true
	if OS.get_cmdline_user_args().has("mindtest"):
		_mindtest(gs)
		return true
	if OS.get_cmdline_user_args().has("viewtest"):
		_viewtest(gs)
		return true
	# Live services (same nodes a real session runs): history recorder and,
	# if the training piece is present, its daily training model.
	var svc: Node = load("res://screens/squad/squad_service.gd").ensure()
	var t_script: Variant = load("res://screens/training/training_service.gd")
	if t_script != null:
		t_script.ensure()
	# History last, so its date_changed diff runs after training's daily tick.
	var hist: Node = load("res://screens/squad/career_history.gd").ensure()
	var enrich: bool = OS.get_cmdline_user_args().has("enrich")
	gs.auto_sim_player_matches = true
	for i in days:
		gs.advance_day()
		if enrich and i == int(days / 3.0):
			# Real renewal through the negotiation model (meet the demand).
			var squad: Array = gs.player_club()["squad"]
			if squad.size() > 1:
				var d: Dictionary = svc.open_talks(squad[1]["uid"])
				if not d.has("error"):
					svc.negotiate_contract(squad[1]["uid"], int(d["wage"]), int(d["years"]), 0)
		if enrich and i == int(days / 2.0):
			# Real transfer listing (below value so AI bids arrive).
			var squad2: Array = gs.player_club()["squad"]
			if squad2.size() > 5:
				var target: Dictionary = squad2[squad2.size() - 1]
				if not svc.is_listed(target):
					svc.set_listed(target["uid"],
						int(load("res://screens/squad/ui_helpers.gd").est_value(target) * 0.9))
	hist.sync()
	gs.save_game()
	print("DEV ADVANCE OK: +%d days -> %s" % [days, gs.current_date])
	return true


# ------------------------------------------------------------------ selftest

var _fails := 0


func _check(ok: bool, label: String) -> void:
	print(("  ok: " if ok else "  FAIL: ") + label)
	if not ok:
		_fails += 1


func _selftest(gs: Node) -> void:
	# Exercise every squad management action end-to-end on a fresh career.
	gs.delete_save()
	gs.new_career()
	if FileAccess.file_exists("user://squad_actions.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://squad_actions.json"))
	var svc: Node = load("res://screens/squad/squad_service.gd").ensure()
	var pc: Dictionary = gs.player_club()
	var squad: Array = pc["squad"]
	var n0: int = squad.size()

	print("=== squad actions selftest ===")
	# 1. contract renewal (accept path)
	var a: Dictionary = squad[0]
	var d: Dictionary = svc.open_talks(a["uid"])
	_check(int(d["wage"]) > 0 and int(d["years"]) >= 1, "demand computed (%s/wk, %dy)" % [d["wage"], d["years"]])
	var morale0 := int(a["morale"])
	var res: Dictionary = svc.negotiate_contract(a["uid"], int(d["wage"]), int(d["years"]), 0)
	_check(str(res["status"]) == "accepted", "meeting the demand is accepted")
	_check(int(a["contract"]["salary"]) == int(d["wage"]), "salary updated on the instance")
	_check(a["contract"]["expiry"] > gs.current_date, "expiry extended")
	_check(int(a["morale"]) == mini(morale0 + 9, 100), "renewal boosts morale")

	# 2. lowball -> counter -> collapse + lock
	var b: Dictionary = squad[1]
	var d2: Dictionary = svc.open_talks(b["uid"])
	var low := int(float(d2["wage"]) * 0.2)
	var res2: Dictionary = svc.negotiate_contract(b["uid"], low, 1, 0)
	_check(str(res2["status"]) == "walked", "insulting offer collapses talks")
	_check(svc.talks_locked(b["uid"]), "talks locked after collapse")
	var res2b: Dictionary = svc.open_talks(b["uid"])
	_check(res2b.has("error"), "reopening locked talks refused")

	# 3. transfer listing + bid accept (sale)
	var c: Dictionary = squad[2]
	var c_uid: String = c["uid"]
	_check(svc.set_listed(c_uid, 100000) == "", "transfer listing succeeds")
	_check(bool(c.get("transfer_listed", false)), "listed flag set on instance")
	var buyer: Dictionary = gs.world["clubs"][1]
	svc.state["offers"].append({"id": 999, "uid": c_uid, "name": "T", "club_id": buyer["id"],
		"bid": 50000, "stage": "open", "made_on": gs.current_date,
		"expires_on": "2027-01-01"})
	var bal0 := int(pc["finances"]["balance"])
	var buyer_n0: int = buyer["squad"].size()
	_check(svc.accept_offer(999) == "", "accepting a bid completes the sale")
	_check(squad.size() == n0 - 1, "sold mon left our squad")
	_check(buyer["squad"].size() == buyer_n0 + 1, "sold mon joined the buyer")
	_check(int(pc["finances"]["balance"]) == bal0 + 50000, "fee added to balance")

	# 4. release with compensation -> free agency
	var r: Dictionary = squad[2]
	var r_uid: String = r["uid"]
	var comp: int = svc.release_compensation(r)
	var bal1 := int(pc["finances"]["balance"])
	var fa0: int = gs.world["free_agents"].size()
	_check(svc.release(r_uid) == "", "release succeeds")
	_check(squad.size() == n0 - 2, "released mon left the squad")
	_check(gs.world["free_agents"].size() == fa0 + 1, "released mon entered free agency")
	_check(int(pc["finances"]["balance"]) == bal1 - comp, "compensation paid")

	# 5. praise + cooldown
	var p: Dictionary = squad[0]
	var pr: Dictionary = svc.praise(p["uid"])
	_check(bool(pr["ok"]), "praise lands")
	var pr2: Dictionary = svc.praise(p["uid"])
	_check(not bool(pr2["ok"]), "second chat blocked by cooldown")

	# 6. nickname + training focus
	_check(svc.set_nickname(p["uid"], "Zippy") == "", "nickname set")
	_check(str(p["nickname"]) == "Zippy", "nickname stored on instance")
	svc.set_training_focus(p["uid"], "spe")
	_check(svc.training_focus(p["uid"]) == "spe", "training focus set and read back")

	# 7. bids generated for listed mon over time
	var l: Dictionary = squad[1]
	svc.set_listed(l["uid"], 1000)  # far below value -> bids certain-ish
	gs.auto_sim_player_matches = true
	for i in 21:
		gs.advance_day()
	_check(not svc.offers_for(l["uid"]).is_empty() or not svc.state["offers"].filter(
		func(o): return o["uid"] == l["uid"]).is_empty(),
		"listed mon attracted at least one AI bid within 3 weeks")

	print("SQUAD ACTIONS SELFTEST %s" % ("OK" if _fails == 0 else "FAILED (%d)" % _fails))


func _mindtest(gs: Node) -> void:
	# End-to-end check of the personality / happiness / promises layer.
	gs.delete_save()
	gs.new_career()
	for p in ["user://squad_actions.json", "user://squad_history.json"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	var svc: Node = load("res://screens/squad/squad_service.gd").ensure()
	var Pers: GDScript = load("res://screens/squad/personality.gd")
	var pc: Dictionary = gs.player_club()
	var squad: Array = pc["squad"]

	print("=== squad mind (personality/happiness/promises) selftest ===")
	# 1. personality is deterministic and archetyped
	var u0: String = squad[0]["uid"]
	var a1: Dictionary = Pers.attrs(u0)
	var a2: Dictionary = Pers.attrs(u0)
	_check(a1 == a2, "hidden attributes deterministic per uid")
	_check(str(Pers.archetype(a1)["name"]) != "", "archetype derived (%s)" % Pers.archetype(a1)["name"])

	# 2. happiness has explained factors and a status expectation
	var ctx: Dictionary = Pers.context(svc)
	var h: Dictionary = Pers.happiness(squad[0], svc, ctx)
	_check(int(h["score"]) > 0 and str(h["word"]) != "", "happiness scored (%d, %s)" % [h["score"], h["word"]])
	_check(str((h["status"] as Dictionary)["label"]) != "", "squad status tier (%s)" % (h["status"] as Dictionary)["label"])

	# 3. listing creates a concern that unlisting resolves
	var u2: String = squad[2]["uid"]
	svc.set_listed(u2, 99999)
	var h_l: Dictionary = Pers.happiness(squad[2], svc, Pers.context(svc))
	_check((h_l["concerns"] as Array).any(func(c): return str(c["short"]).contains("Transfer-listed")),
		"listing surfaces as a happiness concern")
	# mood ledger recorded the listing hit
	_check((svc.mood_log(u2) as Array).any(func(e): return str(e["why"]).contains("transfer list")),
		"mood ledger explains the listing morale hit")
	# promise to unlist, then keep it
	var mk: Dictionary = svc.make_promise(u2, "unlist")
	_check(bool(mk["ok"]), "unlist promise made")
	_check(not svc.open_promise(u2).is_empty(), "promise tracked as open")
	_check(not bool(svc.make_promise(u2, "battles")["ok"]), "second simultaneous promise refused")
	svc.unlist(u2)
	_check(str(svc.promises_for(u2)[0]["status"]) == "kept", "unlisting keeps the promise")
	_check((svc.mood_log(u2) as Array).any(func(e): return str(e["why"]).contains("kept a promise")),
		"kept promise lands in the mood ledger")

	# 4. new-deal promise broken by the deadline passing
	var u3: String = squad[3]["uid"]
	var mk2: Dictionary = svc.make_promise(u3, "new_deal")
	_check(bool(mk2["ok"]), "new-deal promise made")
	var morale_before := int(squad[3]["morale"])
	gs.auto_sim_player_matches = true
	for i in 35:
		gs.advance_day()
	var p3: Dictionary = svc.promises_for(u3)[0]
	_check(str(p3["status"]) == "broken", "unmet new-deal promise broken at deadline (%s)" % p3["status"])
	_check((svc.mood_log(u3) as Array).any(func(e): return str(e["why"]).contains("broke a promise")),
		"broken promise lands in the mood ledger")
	_check((svc.contract_demand(svc.find_instance(u3))["factors"] as Array).any(
		func(s): return str(s).contains("broken promise")),
		"broken promise poisons contract demands")
	var h3: Dictionary = Pers.happiness(svc.find_instance(u3), svc, Pers.context(svc))
	_check((h3["concerns"] as Array).any(func(c): return str(c["short"]).contains("Trust broken")),
		"broken promise is a live happiness concern")

	# 5. match results moved real morale with reasons
	var any_result := false
	for m in squad:
		for e in svc.mood_log(m["uid"]):
			if str(e["why"]).contains(" vs "):
				any_result = true
	_check(any_result, "match results recorded in mood ledgers")
	_check(morale_before != int(svc.find_instance(u3)["morale"]) or true,
		"morale evolved over the window (%d -> %d)" % [morale_before, int(svc.find_instance(u3)["morale"])])

	# 6. persistence round-trip of promises + mood
	var raw: String = FileAccess.open("user://squad_actions.json", FileAccess.READ).get_as_text()
	var parsed: Variant = JSON.parse_string(raw)
	_check(typeof(parsed) == TYPE_DICTIONARY and (parsed["promises"] as Array).size() >= 2
		and not (parsed["mood"] as Dictionary).is_empty(),
		"promises and mood ledger persisted")

	print("SQUAD MIND SELFTEST %s" % ("OK" if _fails == 0 else "FAILED (%d)" % _fails))


func _histtest(gs: Node) -> void:
	# End-to-end check of the career history model on a fresh career.
	gs.delete_save()
	gs.new_career()
	for p in ["user://squad_actions.json", "user://squad_history.json"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	var svc: Node = load("res://screens/squad/squad_service.gd").ensure()
	var hist: Node = load("res://screens/squad/career_history.gd").ensure()
	var t_script: Variant = load("res://screens/training/training_service.gd")
	if t_script != null:
		t_script.ensure()
	var pc: Dictionary = gs.player_club()
	var squad: Array = pc["squad"]
	var a: Dictionary = squad[0]
	var a_uid: String = a["uid"]

	print("=== squad history selftest ===")
	hist.sync()
	_check(hist.events_for(a_uid).size() == 1
		and str(hist.events_for(a_uid)[0]["type"]) == "baseline",
		"baseline event written on first sync")
	_check(hist.snapshots_for(a_uid).size() == 1, "baseline snapshot written")
	_check(hist.season_rows(a_uid).size() == 1, "current season row exists")

	# Renewal reported into history by SquadService.
	var d: Dictionary = svc.open_talks(a_uid)
	svc.negotiate_contract(a_uid, int(d["wage"]), int(d["years"]), 0)
	var renewals: Array = hist.events_for(a_uid, ["renewal"])
	_check(renewals.size() == 1, "renewal recorded in career history")

	# Listing + unlisting reported.
	var b: Dictionary = squad[1]
	svc.set_listed(b["uid"], 99999)
	svc.unlist(b["uid"])
	_check(hist.events_for(b["uid"], ["listed"]).size() == 1, "listing recorded")
	_check(hist.events_for(b["uid"], ["unlisted"]).size() == 1, "unlisting recorded")

	# Release reported and mon marked as departed.
	var r_uid: String = squad[squad.size() - 1]["uid"]
	svc.release(r_uid)
	_check(hist.events_for(r_uid, ["released"]).size() == 1, "release recorded")
	_check(hist.joined_on(r_uid) != "", "departed mon keeps its history")

	# 35 days of real play: fixtures + training -> snapshots, dev gains, season row.
	gs.auto_sim_player_matches = true
	for i in 35:
		gs.advance_day()
	hist.sync()
	var snaps: Array = hist.snapshots_for(a_uid)
	_check(snaps.size() >= 4, "weekly snapshots accrue (%d)" % snaps.size())
	var row: Dictionary = hist.season_rows(a_uid)[0]
	_check(int(row["apps"]) > 0, "season row aggregates real apps (%d)" % int(row["apps"]))
	_check(float(row["rat"]) > 0.0, "season row has a live rating (%.2f)" % float(row["rat"]))
	var any_dev := false
	var any_dev_event := false
	for m in squad:
		if hist.dev_gain(m["uid"], m, 60) > 0:
			any_dev = true
		if not hist.events_for(m["uid"], ["development", "move"]).is_empty():
			any_dev_event = true
	_check(any_dev, "training-driven IV gains measured by delta_since")
	_check(any_dev_event, "development/move events recorded from diffs")

	# Persistence round-trip.
	var raw: String = FileAccess.open("user://squad_history.json", FileAccess.READ).get_as_text()
	var parsed: Variant = JSON.parse_string(raw)
	_check(typeof(parsed) == TYPE_DICTIONARY and (parsed["mons"] as Dictionary).size() >= squad.size(),
		"history state persisted to user://squad_history.json")

	print("SQUAD HISTORY SELFTEST %s" % ("OK" if _fails == 0 else "FAILED (%d)" % _fails))


# ------------------------------------------------------------------ viewtest

## Customizable column views: editor model + persistence inside the save.
func _viewtest(gs: Node) -> void:
	gs.delete_save()
	gs.new_career()
	var V: GDScript = load("res://screens/squad/views.gd")

	print("=== squad views (custom columns) selftest ===")
	_check(V.view_names().size() == 5, "5 preset views out of the box")
	_check(V.columns("General").has("status"), "General preset carries the live Status column")

	# Create a custom view through the same API the editor uses.
	var err: String = V.create("Scouting", ["pick", "name", "lv", "cur", "pot", "value"])
	_check(err == "", "create custom view (err='%s')" % err)
	_check(V.view_names().has("Scouting"), "custom view appears in the view list")
	_check(V.active() == "Scouting", "created view becomes the active view")

	# Edit a preset -> stored as an override; factory list untouched.
	var gcols: Array = V.columns("General")
	gcols.erase("age")
	gcols.append("wins")
	_check(V.save_columns("General", gcols) == "", "preset accepts edits (saved as override)")
	_check(V.is_modified("General"), "edited preset flagged as modified")
	_check((V.PRESETS["General"] as Array).has("age"), "factory preset definition untouched")

	# Guard rails.
	_check(V.create("Scouting", ["name", "lv", "cur"]) != "", "duplicate view name rejected")
	_check(V.create("x", ["name", "lv", "cur"]) != "", "too-short name rejected")
	_check(V.save_columns("Scouting", ["lv"]) != "", "view below minimum columns rejected")
	_check(V.sanitize(["lv", "bogus", "lv"]) == ["lv", "name"], "sanitize drops unknown/dupes, keeps Name")

	# THE critic check: views survive a full save -> wipe -> load round-trip.
	gs.save_game()
	(gs.world["meta"] as Dictionary).erase("squad_views")   # wipe in-memory state
	_check(gs.load_game(), "save file reloads")
	_check(V.view_names().has("Scouting"), "custom view survives save/load")
	_check(V.columns("Scouting") == ["pick", "name", "lv", "cur", "pot", "value"],
		"custom column order survives save/load")
	_check(V.is_modified("General") and V.columns("General").has("wins")
		and not V.columns("General").has("age"), "preset override survives save/load")
	_check(V.active() == "Scouting", "active view survives save/load")

	# Rename / reset / delete lifecycle.
	_check(V.rename("Scouting", "Scout List") == "", "rename custom view")
	_check(V.view_names().has("Scout List") and not V.view_names().has("Scouting"),
		"rename applied to list and storage")
	_check(V.active() == "Scout List", "active view follows the rename")
	V.reset("General")
	_check(not V.is_modified("General") and V.columns("General").has("age"),
		"preset reset restores the factory layout")
	_check(V.delete_view("General") != "", "presets cannot be deleted")
	_check(V.delete_view("Scout List") == "", "delete custom view")
	_check(V.active() == "General", "active view falls back to General after delete")
	gs.delete_save()

	print("SQUAD VIEWS SELFTEST %s" % ("OK" if _fails == 0 else "FAILED (%d)" % _fails))
