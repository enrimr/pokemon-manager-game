extends Node
## Headless self-check for the training piece (builder verification only).
## Run: Godot --headless res://screens/training/dev_check.tscn
## Advances N days and prints real stat/IV/fitness/move changes, then quits.

const DAYS := 42


func _ready() -> void:
	var svc: Node = load("res://screens/training/training_service.gd").new()
	svc.no_disk = true  # throwaway timeline: never touch the real training.json
	svc.setup()
	var squad: Array = GameState.player_club()["squad"]

	# Set up an individual focus + a move pipeline to verify both paths.
	var first: Dictionary = squad[0]
	svc.set_focus(first["uid"], "spa")
	var elig: Array = svc.eligible_moves(first)
	if not elig.is_empty():
		svc.start_move_learning(first["uid"], elig[0], 0)
		print("PIPELINE: %s learning %s" % [first["species"], elig[0]])

	# --- per-Pokémon workload: unit checks on the auto rules, then live checks
	var rest_mon: Dictionary = squad[1]
	var push_mon: Dictionary = squad[2]
	var rest_ms: Dictionary = svc.mon_state(rest_mon["uid"])
	var saved_strain := float(rest_ms["strain"])
	rest_ms["strain"] = 85.0
	assert(svc.resolve_auto_load(rest_mon) == "none", "auto must rest at 85% strain")
	rest_ms["strain"] = 65.0
	assert(svc.resolve_auto_load(rest_mon) == "light", "auto must go Light at 65% strain")
	rest_ms["strain"] = saved_strain
	for inst in squad:
		print("LOAD %s age=%s strain=%.0f auto->%s (%s) wk %+.0f" % [inst["species"],
			inst["age_months"], svc.strain(inst["uid"]), svc.resolve_auto_load(inst),
			svc.auto_load_reason(inst), svc.personal_week_strain(inst)])
	svc.set_load(rest_mon["uid"], "none")
	svc.set_load(push_mon["uid"], "double")
	print("OVERRIDES: %s -> No Training, %s -> Double" % [rest_mon["species"], push_mon["species"]])

	var before := {}
	for inst in squad:
		before[inst["uid"]] = {
			"stats": svc.current_stats(inst).duplicate(),
			"ivs": (inst["ivs"] as Dictionary).duplicate(),
			"fitness": inst["fitness"],
			"moves": (inst["moves"] as Array).duplicate(),
		}

	var inbox_before: int = GameState.inbox.size()

	# --- fixture-aware calendar check: the effective plan must differ from the
	# template on matchday / the day after / the day before.
	var match_kinds := 0
	for i in 14:
		var date: String = Season.date_add(GameState.current_date, i)
		var plan: Dictionary = svc.effective_plan(date)
		var fx: Dictionary = plan["fixture"]
		var fx_txt := ""
		if not fx.is_empty():
			fx_txt = "  FIXTURE %s vs %s" % [fx["comp"], svc.opponent_of(fx)["name"]]
		print("PLAN %s [%s] am=%s pm=%s inten=%s load=%+.1f%s" % [date, plan["kind"],
			plan["am"], plan["pm"], plan["intensity"], svc.day_strain_load(date), fx_txt])
		if plan["kind"] != "normal":
			match_kinds += 1
		if plan["kind"] == "matchday" and (plan["pm"] != "match" or plan["am"] != "match_prep"):
			print("DEV CHECK FAIL: matchday plan not adjusted")
			get_tree().quit(1)
			return
	print("fixture-adjusted days in next 14: %d" % match_kinds)

	# --- per-DATE calendar overrides (the FM Calendar analog) ---------------
	# 1) a single-date edit must win over the template on that date only
	var free_date := ""
	var post_date := ""
	for i in range(1, 28):
		var d: String = Season.date_add(GameState.current_date, i)
		var k: String = svc.effective_plan(d)["kind"]
		if free_date == "" and k == "normal":
			free_date = d
		if post_date == "" and k == "post_match":
			post_date = d
	assert(free_date != "", "need a free date to test overrides")
	svc.set_date_session(free_date, "am", "rest")
	svc.set_date_session(free_date, "pm", "rest")
	svc.set_date_intensity(free_date, "light")
	var op: Dictionary = svc.effective_plan(free_date)
	assert(op["kind"] == "custom" and op["am"] == "rest" and op["pm"] == "rest"
		and op["intensity"] == "light", "date override must win over template")
	assert(svc.day_strain_load(free_date) < 0.0, "planned rest day must recover strain")
	var next_date: String = Season.date_add(free_date, 1)
	if (svc.date_override(next_date) as Dictionary).is_empty():
		var next_day: Dictionary = svc.effective_plan(next_date)
		assert(not bool(next_day["ov"]["am"]), "override must not leak to other dates")
	print("OVERRIDE: %s planned rest/rest/light [%s] load %+.1f (template untouched elsewhere)" % [
		free_date, op["kind"], svc.day_strain_load(free_date)])
	# 2) a deliberate plan beats the automatic post-match recovery default
	if post_date != "":
		svc.set_date_session(post_date, "am", "technique")
		var pp: Dictionary = svc.effective_plan(post_date)
		assert(pp["kind"] == "custom" and pp["am"] == "technique",
			"date plan must beat the post-match auto default")
		print("OVERRIDE: post-match %s deliberately set to technique [%s]" % [post_date, pp["kind"]])
		svc.clear_date_override(post_date)
	# 3) matchday itself stays locked even with an override on it
	for i in range(1, 28):
		var d: String = Season.date_add(GameState.current_date, i)
		if svc.effective_plan(d)["kind"] == "matchday":
			svc.set_date_session(d, "pm", "physical")
			assert(svc.effective_plan(d)["pm"] == "match", "matchday must stay locked")
			svc.clear_date_override(d)
			print("OVERRIDE: matchday %s correctly locked against edits" % d)
			break
	# 4) preset stamped onto ONE future week: 7 per-date plans, template untouched
	var tpl_before := JSON.stringify(svc.state["schedule"])
	var wk_start: String = Season.date_add(GameState.current_date, 14)
	svc.apply_preset_to_week("recovery", wk_start)
	for i in 7:
		assert(not (svc.date_override(Season.date_add(wk_start, i)) as Dictionary).is_empty(),
			"week preset must lay a dated plan on each of the 7 days")
	assert(JSON.stringify(svc.state["schedule"]) == tpl_before,
		"week preset must NOT touch the weekday template")
	var wk_load := 0.0
	for i in 7:
		wk_load += svc.day_strain_load(Season.date_add(wk_start, i))
	print("OVERRIDE: recovery preset on week %s -> %d planned dates, week load %+.1f" % [
		wk_start, svc.planned_custom_dates(28).size(), wk_load])
	# 5) clearing the week removes its plans
	svc.clear_week_overrides(wk_start)
	for i in 7:
		assert((svc.date_override(Season.date_add(wk_start, i)) as Dictionary).is_empty(),
			"clear_week must drop the 7 plans")
	# 6) save-week-as-template bakes overrides into the weekday default
	var bake_day: String = svc._weekday_key(free_date)
	var bake_start: String = Season.date_add(free_date, -3)
	svc.save_week_as_template(bake_start)
	assert(svc.state["schedule"][bake_day]["am"] == "rest",
		"save_week_as_template must bake the date edit into the template")
	for i in 7:
		assert((svc.date_override(Season.date_add(bake_start, i)) as Dictionary).is_empty(),
			"baked overrides must be consumed")
	svc.apply_preset("balanced")  # restore a sane template for the tick run
	print("OVERRIDE: save-week-as-template baked %s AM=rest, then template reset" % bake_day)
	# 7) opponent-specific prep for one big fixture: the days before it become
	# deliberate Match Prep plans; the fixture itself and other matchdays stay
	# under auto control; the template is untouched.
	var big_fx := ""
	for i in range(4, 28):
		var d: String = Season.date_add(GameState.current_date, i)
		if svc.effective_plan(d)["kind"] == "matchday":
			big_fx = d
			break
	if big_fx != "":
		var tpl_before2 := JSON.stringify(svc.state["schedule"])
		svc.plan_prep_for_fixture(big_fx, 3)
		var eve: Dictionary = svc.effective_plan(Season.date_add(big_fx, -1))
		assert(eve["kind"] == "custom" and eve["am"] == "match_prep" and eve["pm"] == "match_prep",
			"fixture prep must plan a double-prep day before the match")
		assert(svc.effective_plan(big_fx)["pm"] == "match", "fixture itself stays a matchday")
		assert(JSON.stringify(svc.state["schedule"]) == tpl_before2,
			"fixture prep must not touch the weekday template")
		print("OVERRIDE: opponent prep planned into fixture %s (eve = %s/%s %s)" % [
			big_fx, eve["am"], eve["pm"], eve["intensity"]])
		for i in range(1, 4):
			svc.clear_date_override(Season.date_add(big_fx, -i))

	# leave one real override in place across the tick run to verify pruning
	var prune_date: String = Season.date_add(GameState.current_date, 2)
	svc.set_date_session(prune_date, "am", "speed")

	# --- mentoring: eligibility rules, pairing, then real daily effects ------
	var mentor_i: Dictionary = {}
	var junior_i: Dictionary = {}
	for m in squad:
		if not svc.mentor_eligible(m):
			continue
		for j in squad:
			if svc.junior_eligible(j) and svc.can_mentor(m, j) == "":
				mentor_i = m
				junior_i = j
				break
		if not mentor_i.is_empty():
			break
	assert(not mentor_i.is_empty(), "squad must contain a valid mentor/junior pair")
	assert(svc.can_mentor(junior_i, mentor_i) != "", "a junior must not be able to mentor a veteran")
	assert(svc.create_mentor_group(str(mentor_i["uid"])) == "", "group creation must succeed")
	assert(svc.create_mentor_group(str(mentor_i["uid"])) != "", "a mentor cannot lead two groups")
	assert(svc.add_junior(str(mentor_i["uid"]), str(junior_i["uid"])) == "", "junior must join the group")
	assert(svc.add_junior(str(mentor_i["uid"]), str(junior_i["uid"])) != "", "a junior cannot join twice")
	var meff: Dictionary = svc.mentoring_effect(str(junior_i["uid"]))
	assert(not meff.is_empty() and float(meff["mult"]) > 1.1, "mentoring must boost development >10%")
	var mentored_proj: Dictionary = svc.weekly_projection(junior_i)
	print("MENTORING: %s (Lv %d, %s) mentoring %s (Lv %d) -> x%.2f dev, stat bias %s, moves x%.1f, strain x%.2f" % [
		mentor_i["species"], int(mentor_i["level"]), svc.personality_label(mentor_i),
		junior_i["species"], int(junior_i["level"]), float(meff["mult"]),
		str((meff["stat_mult"] as Dictionary).keys()), float(meff["move_mult"]), float(meff["strain_mult"])])
	var junior_morale_before := int(junior_i.get("morale", 70))
	var mentor_morale_before := int(mentor_i.get("morale", 70))
	# projection with the mentor must beat the same squad plan without one
	svc.remove_junior(str(junior_i["uid"]))
	var solo_proj: Dictionary = svc.weekly_projection(junior_i)
	var proj_up := false
	for s in ["hp", "atk", "def", "spa", "spd", "spe"]:
		if float(mentored_proj[s]) > float(solo_proj[s]) + 0.001:
			proj_up = true
	assert(proj_up, "mentored projection must exceed the unmentored one")
	assert(svc.add_junior(str(mentor_i["uid"]), str(junior_i["uid"])) == "", "junior must rejoin")
	print("MENTORING: projection spa %.1f -> %.1f with the mentor watching" % [
		float(solo_proj["spa"]), float(mentored_proj["spa"])])

	# --- projection path (Individual tab): must run clean and reflect the week
	var proj: Dictionary = svc.weekly_projection(first)
	var ptxt: Array = []
	for s in ["hp", "atk", "def", "spa", "spd", "spe"]:
		ptxt.append("%s %.1f (eta %dd)" % [s, float(proj[s]), svc.eta_days(first, s)])
	print("PROJECTION %s: %s" % [first["species"], ", ".join(ptxt)])
	print("weekly strain balance: %+.1f · move rate %.2f%%/day" % [
		svc.weekly_strain_balance(), svc.move_learn_rate(first)])

	for i in DAYS:
		GameState.advance_day()

	print("=== after %d days ===" % DAYS)
	var any_gain := false
	for inst in squad:
		var b: Dictionary = before[inst["uid"]]
		var now: Dictionary = svc.current_stats(inst)
		var diffs: Array = []
		for s in ["hp", "atk", "def", "spa", "spd", "spe"]:
			var d: int = int(now[s]) - int(b["stats"][s])
			if d != 0:
				diffs.append("%s %+d" % [s, d])
				any_gain = true
		var moves_changed: bool = str(inst["moves"]) != str(b["moves"])
		print("%s: stats[%s] strain=%.0f fit %d->%d%s" % [inst["species"],
			", ".join(diffs) if diffs else "no change", svc.strain(inst["uid"]),
			int(b["fitness"]), int(inst["fitness"]),
			"  MOVES CHANGED -> %s" % str(inst["moves"]) if moves_changed else ""])
	print("inbox messages added: %d" % (GameState.inbox.size() - inbox_before))
	for m in GameState.inbox.slice(0, 5):
		print("  INBOX: [%s] %s" % [m["date"], m["title"]])

	# --- override pruning: dated plans are consumed as their day passes
	assert(not (svc.state["overrides"] as Dictionary).has(prune_date),
		"past-date overrides must be pruned after the day runs")
	print("OVERRIDE: %s plan consumed and pruned after advancing %d days" % [prune_date, DAYS])

	# --- mentoring verification: bonus points accrued and attributed, group
	# persisted through the ticks, morale moved on both sides.
	var jms: Dictionary = svc.mon_state(str(junior_i["uid"]))
	assert(float(jms.get("mentor_pts", 0.0)) > 0.0, "mentored junior must accrue attributed bonus points")
	assert(not (svc.group_of(str(junior_i["uid"])) as Dictionary).is_empty(), "mentor group must persist across ticks")
	print("MENTORING: after %d days %s attributed +%.1f pts / %d IVs to learning from %s; morale junior %d->%d, mentor %d->%d" % [
		DAYS, junior_i["species"], float(jms.get("mentor_pts", 0.0)), int(jms.get("mentor_ivs", 0)),
		mentor_i["species"], junior_morale_before, int(junior_i.get("morale", 70)),
		mentor_morale_before, int(mentor_i.get("morale", 70))])
	svc.disband_mentor_group(str(mentor_i["uid"]))
	assert((svc.mentor_of(str(junior_i["uid"])) as Dictionary).is_empty(), "disband must free the juniors")

	# --- workload verification: the rested Pokémon must have gained nothing
	var rest_b: Dictionary = before[rest_mon["uid"]]
	var rest_now: Dictionary = svc.current_stats(rest_mon)
	var rest_gain := 0
	for s in ["hp", "atk", "def", "spa", "spd", "spe"]:
		rest_gain += int(rest_now[s]) - int(rest_b["stats"][s])
	print("WORKLOAD: rested %s gained %d stat points (must be 0), strain %.0f; doubled %s strain %.0f, reaction '%s'" % [
		rest_mon["species"], rest_gain, svc.strain(rest_mon["uid"]),
		push_mon["species"], svc.strain(push_mon["uid"]), svc.workload_reaction(push_mon)])
	svc.set_load(rest_mon["uid"], "auto")
	svc.set_load(push_mon["uid"], "auto")
	if rest_gain != 0:
		print("DEV CHECK FAIL: No Training Pokémon still developed")
		get_tree().quit(1)
		return
	if any_gain:
		print("DEV CHECK OK")
	else:
		print("DEV CHECK FAIL: no stat gains after %d days" % DAYS)
	# Deliberately NOT saving: this is a throwaway verification run and must
	# leave the real career save and training state on disk untouched.
	get_tree().quit(0 if any_gain else 1)
