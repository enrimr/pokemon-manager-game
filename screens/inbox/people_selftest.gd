extends SceneTree
## Headless selftest for the people/media inbox layer. Verifies against the
## LIVE save that:
##   1. all four message families generate (mind-games, press, coach, round-up)
##   2. every people message renders non-empty bbcode without errors
##   3. mind-game replies genuinely move squad morale
##   4. coach-note replies genuinely move that mon's morale
##   5. the round-up podium carries real replay-derived ratings
## Run: godot --headless --path . -s res://screens/inbox/people_selftest.gd
## NOTE: mutates the save (replies are real) — rebuild it afterwards.

var fails := 0


func _init() -> void:
	call_deferred("_run")


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: %s" % label)
	else:
		fails += 1
		printerr("  FAIL: %s" % label)


func _run() -> void:
	var gs := root.get_node_or_null("/root/GameState")
	if gs == null:
		printerr("people_selftest: GameState missing")
		quit(1)
		return
	var news: RefCounted = (load("res://screens/inbox/news_gen.gd") as GDScript).new()
	var people: RefCounted = (load("res://screens/inbox/people_gen.gd") as GDScript).new(news)
	var reports: RefCounted = (load("res://screens/inbox/report_gen.gd") as GDScript).new(news)
	reports.people = people
	news.enrich_existing()
	news.generate()
	people.generate()

	print("=== people_selftest: generation ===")
	var mind: Dictionary = {}
	var press := 0
	var roundup: Dictionary = {}
	var monlow: Dictionary = {}
	var monstar: Dictionary = {}
	for m in gs.inbox:
		var uid := str(m.get("uid", ""))
		if uid.begins_with("mind:") and str(m.get("replied", "")) == "":
			var f: Dictionary = {}
			for fx in gs.fixtures:
				if str(fx["id"]) == str(m.get("fid", "")):
					f = fx
			if not f.is_empty() and not f.get("played", false):
				mind = m
		elif uid.begins_with("press:"):
			press += 1
		elif uid.begins_with("roundup:"):
			roundup = m
		elif uid.begins_with("monlow:") and str(m.get("replied", "")) == "":
			monlow = m
		elif uid.begins_with("monstar:") and str(m.get("replied", "")) == "":
			monstar = m
	_check(not mind.is_empty(), "live (unplayed-fixture) mind-game exists")
	_check(press >= 1, "press reaction pieces exist (%d)" % press)
	_check(not roundup.is_empty(), "monthly round-up column exists")
	_check(not (monlow.is_empty() and monstar.is_empty()), "coach mon note exists")

	print("=== people_selftest: rendering ===")
	var rendered := 0
	for m in gs.inbox:
		if str(m.get("cat", "")) in ["media", "staff"]:
			var r: Dictionary = reports.render(m)
			if str(r.get("bbcode", "")).length() < 40:
				_check(false, "render too short for %s" % str(m.get("uid", "?")))
			rendered += 1
	_check(rendered >= 5, "rendered %d people/media messages" % rendered)
	if not roundup.is_empty():
		var podium: Array = roundup.get("podium", [])
		_check(not podium.is_empty(), "round-up has a Pokémon of the Month podium")
		if not podium.is_empty():
			var top: Dictionary = podium[0]
			_check(float(top.get("rating", 0)) > 4.5 and int(top.get("battles", 0)) > 0,
				"podium winner has real rating (%.2f over %d battles)" %
				[float(top.get("rating", 0)), int(top.get("battles", 0))])

	print("=== people_selftest: mind-game reply moves squad morale ===")
	if not mind.is_empty():
		var pc: Dictionary = gs.player_club()
		var before := 0
		for inst in pc["squad"]:
			before += int(inst.get("morale", 70))
		var replies: Array = people.mind_replies(mind)
		_check(replies.size() == 3, "mind-game offers 3 reply choices")
		var res: Dictionary = people.apply_reply(mind, {"reply": "calm"})
		var after := 0
		for inst in pc["squad"]:
			after += int(inst.get("morale", 70))
		_check(after == before + pc["squad"].size(), "calm reply gave +1 morale to all %d squad members (%d -> %d)" % [pc["squad"].size(), before, after])
		_check(str(mind.get("replied", "")) == "calm" and not mind.get("urgent", true), "reply recorded on message, urgency cleared")
		_check(people.mind_replies(mind).is_empty(), "no second reply allowed")
		_check(str(res.get("note", "")) != "", "reply produced a feedback note")

	print("=== people_selftest: coach note reply moves mon morale ===")
	var note := monlow if not monlow.is_empty() else monstar
	if not note.is_empty():
		var inst: Dictionary = gs.squad_member(str(note.get("mon_uid", "")))
		_check(not inst.is_empty(), "coach note points at a real squad member")
		if not inst.is_empty():
			var b := int(inst.get("morale", 70))
			var choice := "promise" if not monlow.is_empty() else "praise"
			people.apply_reply(note, {"reply": choice})
			var delta := int(inst.get("morale", 70)) - b
			_check(delta > 0, "'%s' reply raised %s's morale by %d (%d -> %d)" %
				[choice, str(inst.get("species", "?")), delta, b, int(inst.get("morale", 70))])

	if fails == 0:
		print("PEOPLE SELFTEST OK")
		quit(0)
	else:
		printerr("PEOPLE SELFTEST FAILED (%d)" % fails)
		quit(1)
