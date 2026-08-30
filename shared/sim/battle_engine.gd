class_name BattleEngine
extends RefCounted
## Deterministic 6v6 singles battle engine with benches.
##
## OWNERSHIP: shared core. The "match" piece may extend this file; everyone
## else consumes it read-only. Do not change public method signatures.
##
## Usage:
##   var eng := BattleEngine.new(team_a, team_b, seed)
##   # teams: Array of battler dicts from DataStore.make_battler(instance)
##   # Fast mode:
##   var events := eng.run_to_end()
##   # Step mode (match screen):
##   while not eng.is_over():
##       var turn_events := eng.step_turn(player_action, null)  # null = AI decides
##
## Actions: {"type": "move", "index": 0..3} or {"type": "switch", "index": bench_slot}
##
## Event log: Array[Dictionary], every event has "t" (type) and usually "side" (0/1).
## Event types: battle_start, turn_start, move_used, damage, miss, faint, switch,
##   status_applied, status_tick, stat_change, heal, flinch, confused_hit, asleep,
##   paralyzed, commentary_hook, battle_end.

const MAX_TURNS := 300
const STAGE_MULT := [0.25, 0.28, 0.33, 0.4, 0.5, 0.66, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0]
const ACC_STAGE_MULT := [0.33, 0.36, 0.43, 0.5, 0.6, 0.75, 1.0, 1.33, 1.66, 2.0, 2.33, 2.66, 3.0]

var rng := RandomNumberGenerator.new()
var teams: Array = [[], []]     # two Arrays of battler state dicts
var active: Array = [0, 0]      # active party index per side
var events: Array = []          # full event log
var turn: int = 0
var _over: bool = false
var _winner: int = -1


func _init(team_a: Array, team_b: Array, battle_seed: int = 0) -> void:
	rng.seed = battle_seed
	teams[0] = team_a.map(_init_battler)
	teams[1] = team_b.map(_init_battler)
	_emit({"t": "battle_start",
		"team_a": teams[0].map(func(b): return b["name"]),
		"team_b": teams[1].map(func(b): return b["name"])})
	_emit({"t": "switch", "side": 0, "to": teams[0][0]["name"], "first": true})
	_emit({"t": "switch", "side": 1, "to": teams[1][0]["name"], "first": true})


func _init_battler(b: Dictionary) -> Dictionary:
	var s: Dictionary = b.duplicate(true)
	s["max_hp"] = int(s["stats"]["hp"])
	s["hp"] = s["max_hp"]
	s["status"] = ""         # "", burn, para, sleep, poison, freeze
	s["sleep_turns"] = 0
	s["confused_turns"] = 0
	s["flinched"] = false
	s["stages"] = {"atk": 0, "def": 0, "spa": 0, "spd": 0, "spe": 0, "acc": 0, "eva": 0}
	s["pp"] = {}
	for m in s["moves"]:
		s["pp"][m] = int(DataStore.move(m).get("pp", 10))
	return s


# ------------------------------------------------------------------ public API

func is_over() -> bool:
	return _over


func winner() -> int:
	## -1 while running; 0 or 1 when over.
	return _winner


func active_battler(side: int) -> Dictionary:
	return teams[side][active[side]]


func team_state(side: int) -> Array:
	return teams[side]


## Legal action list for a side (for UIs and AI).
func legal_actions(side: int) -> Array:
	var acts: Array = []
	var me: Dictionary = active_battler(side)
	for i in me["moves"].size():
		if int(me["pp"].get(me["moves"][i], 0)) > 0:
			acts.append({"type": "move", "index": i})
	if acts.is_empty():
		acts.append({"type": "move", "index": 0})  # struggle-ish: allow move 0
	for i in teams[side].size():
		if i != active[side] and int(teams[side][i]["hp"]) > 0:
			acts.append({"type": "switch", "index": i})
	return acts


## Advance one full turn. Pass null for a side to let the AI decide.
## Returns the events generated during this turn.
func step_turn(action_a: Variant = null, action_b: Variant = null) -> Array:
	if _over:
		return []
	turn += 1
	var start := events.size()
	_emit({"t": "turn_start", "turn": turn,
		"hp_a": _team_hp_frac(0), "hp_b": _team_hp_frac(1),
		"active_a": active_battler(0)["name"], "active_b": active_battler(1)["name"]})
	var acts: Array = [
		action_a if action_a != null else ai_choose_action(0),
		action_b if action_b != null else ai_choose_action(1),
	]
	# Switches resolve first, then moves by priority then speed.
	for side in 2:
		if acts[side]["type"] == "switch":
			_do_switch(side, int(acts[side]["index"]))
	var order := _move_order(acts)
	for side in order:
		if _over:
			break
		if acts[side]["type"] == "move":
			_do_move(side, int(acts[side]["index"]))
	if not _over:
		for side in 2:
			_end_of_turn(side)
	_check_end()
	if turn >= MAX_TURNS and not _over:
		_finish(0 if _team_hp_frac(0) >= _team_hp_frac(1) else 1)
	return events.slice(start)


## Run the whole battle with AI on both sides. Returns the full event log.
func run_to_end() -> Array:
	while not _over:
		step_turn(null, null)
	return events


## Simple but sensible AI: best expected damage, switch when hard-countered.
func ai_choose_action(side: int) -> Dictionary:
	var me: Dictionary = active_battler(side)
	var foe: Dictionary = active_battler(1 - side)
	var best_idx := 0
	var best_score := -1.0
	for i in me["moves"].size():
		var mname: String = me["moves"][i]
		if int(me["pp"].get(mname, 0)) <= 0:
			continue
		var score := _move_score(me, foe, mname)
		if score > best_score:
			best_score = score
			best_idx = i
	# Consider switching if we can't hurt them or they wreck us.
	var my_threat := best_score
	var foe_threat := _matchup_threat(foe, me)
	if (my_threat < 12.0 or foe_threat > 2.0 * maxf(my_threat, 1.0)) and rng.randf() < 0.6:
		var best_bench := -1
		var best_bench_score := _matchup_value(me, foe)
		for i in teams[side].size():
			if i == active[side] or int(teams[side][i]["hp"]) <= 0:
				continue
			var v := _matchup_value(teams[side][i], foe)
			if v > best_bench_score + 0.5:
				best_bench_score = v
				best_bench = i
		if best_bench >= 0:
			return {"type": "switch", "index": best_bench}
	return {"type": "move", "index": best_idx}


## Touchline-instruction-aware action chooser (used by the match screen).
## opts: {"aggression": "balanced"|"attacking"|"cautious",
##        "switching":  "normal"|"stay"|"eager"}
## Additive API — everything else keeps using ai_choose_action().
func choose_action_policy(side: int, opts: Dictionary = {}) -> Dictionary:
	var aggression: String = str(opts.get("aggression", "balanced"))
	var switching: String = str(opts.get("switching", "normal"))
	var me: Dictionary = active_battler(side)
	var foe: Dictionary = active_battler(1 - side)
	var best_idx := 0
	var best_score := -1.0
	for i in me["moves"].size():
		var mname: String = me["moves"][i]
		if int(me["pp"].get(mname, 0)) <= 0:
			continue
		var score := _move_score(me, foe, mname)
		var mv: Dictionary = DataStore.move(mname)
		if not mv.is_empty() and mv["category"] == "status":
			if aggression == "attacking":
				score *= 0.35
			elif aggression == "cautious":
				score *= 1.5
		if score > best_score:
			best_score = score
			best_idx = i
	if switching == "stay" or aggression == "attacking":
		return {"type": "move", "index": best_idx}
	# Switch consideration, threshold shaped by instructions.
	var my_threat := _matchup_threat(me, foe)
	var foe_threat := _matchup_threat(foe, me)
	var threat_ratio := 2.0
	var switch_prob := 0.6
	if aggression == "cautious":
		threat_ratio = 1.4
		switch_prob = 0.85
	if switching == "eager":
		threat_ratio = minf(threat_ratio, 1.2)
		switch_prob = 0.95
	if (my_threat < 12.0 or foe_threat > threat_ratio * maxf(my_threat, 1.0)) and rng.randf() < switch_prob:
		var best_bench := -1
		var best_bench_score := _matchup_value(me, foe)
		if switching == "eager":
			best_bench_score -= 0.4
		for i in teams[side].size():
			if i == active[side] or int(teams[side][i]["hp"]) <= 0:
				continue
			var v := _matchup_value(teams[side][i], foe)
			if v > best_bench_score + 0.5:
				best_bench_score = v
				best_bench = i
		if best_bench >= 0:
			return {"type": "switch", "index": best_bench}
	return {"type": "move", "index": best_idx}


## Expected-damage preview for UIs (move tooltips in full-control mode).
## Returns {"eff": float, "stab": bool, "est_frac": float(0..1 of target max hp)}.
func preview_move(side: int, move_idx: int) -> Dictionary:
	var me: Dictionary = active_battler(side)
	var foe: Dictionary = active_battler(1 - side)
	if move_idx < 0 or move_idx >= me["moves"].size():
		return {}
	var mname: String = me["moves"][move_idx]
	var mv: Dictionary = DataStore.move(mname)
	if mv.is_empty():
		return {}
	var eff: float = DataStore.effectiveness(mv["type"], foe["types"])
	var stab: bool = me["types"].has(mv["type"])
	var est := 0.0
	if mv["category"] != "status":
		var fixed := _fixed_damage(mv.get("effects", []), me)
		if fixed > 0:
			est = float(fixed) if eff > 0.0 else 0.0
		else:
			var is_phys: bool = mv["category"] == "phys"
			var a := _eff_stat(me, "atk" if is_phys else "spa")
			var d := _eff_stat(foe, "def" if is_phys else "spd")
			var base: float = (2.0 * float(me["level"]) / 5.0 + 2.0) * float(mv["power"]) * a / maxf(d, 1.0) / 50.0 + 2.0
			est = base * (1.5 if stab else 1.0) * eff * 0.925
	return {"eff": eff, "stab": stab, "est_frac": clampf(est / maxf(float(foe["max_hp"]), 1.0), 0.0, 1.0)}


# ------------------------------------------------------------------ matchday boot hook
# The "match" piece (owner of this file) uses the documented GameState hook:
# auto_sim_player_matches = false + player_match_due. Installing it from the
# engine's static init guarantees it is active from the very first Continue
# press, before the Match screen has ever been opened. Headless runs
# (smoke test, sim_check) are left untouched.

static func _static_init() -> void:
	if Engine.is_editor_hint():
		return
	Callable(BattleEngine, "_install_matchday_hook").call_deferred()


static func _install_matchday_hook() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return
	var root: Node = (ml as SceneTree).root
	if root == null or root.has_node("MatchDirector") or root.get_node_or_null("GameState") == null:
		return
	var script: GDScript = load("res://screens/match/match_director.gd")
	if script == null:
		return
	var director: Node = script.new()
	director.name = "MatchDirector"
	root.add_child(director)


# ------------------------------------------------------------------ internals

func _move_score(user: Dictionary, target: Dictionary, mname: String) -> float:
	var mv: Dictionary = DataStore.move(mname)
	if mv.is_empty():
		return 0.0
	var acc := float(mv.get("accuracy", 100))
	var acc_f := (acc if acc > 0.0 else 100.0) / 100.0
	if mv["category"] == "status":
		# Value status moves a bit; more if target is healthy and unstatused.
		var v := 20.0 * acc_f
		if target["status"] != "" and _has_status_effect(mv):
			v = 1.0
		return v * (0.5 + 0.5 * float(target["hp"]) / float(target["max_hp"]))
	var eff: float = DataStore.effectiveness(mv["type"], target["types"])
	var stab: float = 1.5 if user["types"].has(mv["type"]) else 1.0
	return float(mv.get("power", 0)) * eff * stab * acc_f


func _has_status_effect(mv: Dictionary) -> bool:
	for fx in mv.get("effects", []):
		var tag: String = str(fx).split(":")[0]
		if tag in ["burn", "para", "sleep", "poison", "freeze", "confuse"]:
			return true
	return false


func _matchup_value(mine: Dictionary, foe: Dictionary) -> float:
	var give := 0.0
	for m in mine["moves"]:
		give = maxf(give, _move_score(mine, foe, m))
	var take := _matchup_threat(foe, mine)
	return give / 40.0 - take / 60.0 + float(mine["hp"]) / float(mine["max_hp"])


func _matchup_threat(attacker: Dictionary, defender: Dictionary) -> float:
	var worst := 0.0
	for m in attacker["moves"]:
		worst = maxf(worst, _move_score(attacker, defender, m))
	return worst


func _move_order(acts: Array) -> Array:
	var prio := [0, 0]
	var spe := [0.0, 0.0]
	for side in 2:
		var me: Dictionary = active_battler(side)
		spe[side] = _eff_stat(me, "spe")
		if me["status"] == "para":
			spe[side] *= 0.25
		if acts[side]["type"] == "move":
			var mname: String = me["moves"][int(acts[side]["index"])] if int(acts[side]["index"]) < me["moves"].size() else ""
			for fx in DataStore.move(mname).get("effects", []):
				var parts: PackedStringArray = str(fx).split(":")
				if parts[0] == "priority":
					prio[side] = int(parts[1])
	if prio[0] != prio[1]:
		return [0, 1] if prio[0] > prio[1] else [1, 0]
	if spe[0] != spe[1]:
		return [0, 1] if spe[0] > spe[1] else [1, 0]
	return [0, 1] if rng.randf() < 0.5 else [1, 0]


func _eff_stat(b: Dictionary, stat: String) -> float:
	var v := float(b["stats"][stat])
	v *= STAGE_MULT[int(b["stages"][stat]) + 6]
	if stat == "atk" and b["status"] == "burn":
		v *= 0.5
	return v


func _do_switch(side: int, to_idx: int) -> void:
	if to_idx == active[side] or to_idx < 0 or to_idx >= teams[side].size():
		return
	if int(teams[side][to_idx]["hp"]) <= 0:
		return
	var from: Dictionary = active_battler(side)
	from["stages"] = {"atk": 0, "def": 0, "spa": 0, "spd": 0, "spe": 0, "acc": 0, "eva": 0}
	from["confused_turns"] = 0
	from["flinched"] = false
	active[side] = to_idx
	_emit({"t": "switch", "side": side, "from": from["name"], "to": active_battler(side)["name"]})
	_hook(side, "%s is recalled — %s takes the field!" % [from["name"], active_battler(side)["name"]])


func _do_move(side: int, move_idx: int) -> void:
	var me: Dictionary = active_battler(side)
	if int(me["hp"]) <= 0:
		return
	var foe_side := 1 - side
	var foe: Dictionary = active_battler(foe_side)

	# Pre-move status gates
	if me["flinched"]:
		me["flinched"] = false
		_emit({"t": "flinch", "side": side, "pokemon": me["name"]})
		return
	if me["status"] == "sleep":
		me["sleep_turns"] -= 1
		if me["sleep_turns"] <= 0:
			me["status"] = ""
			_emit({"t": "status_applied", "side": side, "pokemon": me["name"], "status": "woke"})
		else:
			_emit({"t": "asleep", "side": side, "pokemon": me["name"]})
			return
	if me["status"] == "freeze":
		if rng.randf() < 0.25:
			me["status"] = ""
			_emit({"t": "status_applied", "side": side, "pokemon": me["name"], "status": "thawed"})
		else:
			_emit({"t": "asleep", "side": side, "pokemon": me["name"], "frozen": true})
			return
	if me["status"] == "para" and rng.randf() < 0.25:
		_emit({"t": "paralyzed", "side": side, "pokemon": me["name"]})
		return
	if me["confused_turns"] > 0:
		me["confused_turns"] -= 1
		if rng.randf() < 0.33:
			var self_dmg := maxi(1, int(_eff_stat(me, "atk") * 0.4))
			_apply_damage(side, me, self_dmg, {"t": "confused_hit", "side": side, "pokemon": me["name"]})
			return

	move_idx = clampi(move_idx, 0, me["moves"].size() - 1)
	var mname: String = me["moves"][move_idx]
	var mv: Dictionary = DataStore.move(mname)
	if mv.is_empty():
		return
	me["pp"][mname] = maxi(0, int(me["pp"].get(mname, 1)) - 1)
	_emit({"t": "move_used", "side": side, "pokemon": me["name"], "move": mname})

	var fx: Array = mv.get("effects", [])
	var never_miss := fx.has("never_miss")

	# Accuracy check
	var acc := float(mv.get("accuracy", 100))
	if acc > 0.0 and not never_miss:
		var hit_chance := acc / 100.0
		hit_chance *= ACC_STAGE_MULT[int(me["stages"]["acc"]) + 6]
		hit_chance /= ACC_STAGE_MULT[int(foe["stages"]["eva"]) + 6]
		if rng.randf() > hit_chance:
			_emit({"t": "miss", "side": side, "pokemon": me["name"], "move": mname})
			return

	if mv["category"] == "status":
		_apply_effects(side, me, foe_side, foe, fx, true)
		return

	# Damage
	var dmg := 0
	var crit := false
	var eff: float = DataStore.effectiveness(mv["type"], foe["types"])
	var fixed := _fixed_damage(fx, me)
	if fixed > 0:
		dmg = fixed if eff > 0.0 else 0
	else:
		var crit_chance := 1.0 / 16.0
		if fx.has("crit:1"):
			crit_chance = 1.0 / 4.0
		crit = rng.randf() < crit_chance
		var is_phys: bool = mv["category"] == "phys"
		var a := _eff_stat(me, "atk" if is_phys else "spa")
		var d := _eff_stat(foe, "def" if is_phys else "spd")
		if crit:  # crits ignore stages
			a = float(me["stats"]["atk" if is_phys else "spa"])
			d = float(foe["stats"]["def" if is_phys else "spd"])
		var stab: float = 1.5 if me["types"].has(mv["type"]) else 1.0
		var base: float = (2.0 * float(me["level"]) / 5.0 + 2.0) * float(mv["power"]) * a / maxf(d, 1.0) / 50.0 + 2.0
		var roll := rng.randf_range(0.85, 1.0)
		dmg = int(base * stab * eff * (1.5 if crit else 1.0) * roll)
	if eff == 0.0:
		_emit({"t": "damage", "side": foe_side, "pokemon": foe["name"], "amount": 0,
			"hp_left": foe["hp"], "effectiveness": 0.0, "crit": false, "move": mname})
		_hook(foe_side, "It doesn't affect %s..." % foe["name"])
		return
	dmg = maxi(1, dmg)
	_apply_damage(foe_side, foe, dmg, {"t": "damage", "side": foe_side, "pokemon": foe["name"],
		"effectiveness": eff, "crit": crit, "move": mname, "by": me["name"], "by_side": side})
	if crit:
		_hook(side, "A critical hit!")
	if eff > 1.0:
		_hook(side, "It's super effective!")
	elif eff < 1.0:
		_hook(side, "It's not very effective...")
	if dmg >= int(foe["max_hp"] * 0.45):
		_hook(side, "%s is rocked by the sheer force of that %s!" % [foe["name"], mname])
	elif int(foe["hp"]) > 0 and int(foe["hp"]) <= int(foe["max_hp"] * 0.15):
		_hook(foe_side, "%s is hanging on by a thread!" % foe["name"])

	# Secondary effects, recoil, drain
	for f in fx:
		var parts: PackedStringArray = str(f).split(":")
		match parts[0]:
			"recoil":
				var rec := maxi(1, int(dmg * float(parts[1])))
				_apply_damage(side, me, rec, {"t": "damage", "side": side, "pokemon": me["name"],
					"effectiveness": 1.0, "crit": false, "move": mname, "recoil": true})
			"drain":
				var healed := maxi(1, int(dmg * float(parts[1])))
				me["hp"] = mini(me["max_hp"], int(me["hp"]) + healed)
				_emit({"t": "heal", "side": side, "pokemon": me["name"], "amount": healed, "hp_left": me["hp"]})
	if int(foe["hp"]) > 0:
		_apply_effects(side, me, foe_side, foe, fx, false)


func _fixed_damage(fx: Array, me: Dictionary) -> int:
	for f in fx:
		var parts: PackedStringArray = str(f).split(":")
		if parts[0] == "fixed":
			return int(me["level"]) if parts[1] == "level" else int(parts[1])
	return 0


func _apply_effects(side: int, me: Dictionary, foe_side: int, foe: Dictionary, fx: Array, is_status_move: bool) -> void:
	for f in fx:
		var parts: PackedStringArray = str(f).split(":")
		var tag: String = parts[0]
		match tag:
			"burn", "para", "sleep", "poison", "freeze":
				var chance := float(parts[1]) if parts.size() > 1 else 1.0
				if rng.randf() <= chance:
					_apply_status(foe_side, foe, tag)
			"confuse":
				var chance2 := float(parts[1]) if parts.size() > 1 else 1.0
				if rng.randf() <= chance2 and foe["confused_turns"] <= 0:
					foe["confused_turns"] = rng.randi_range(2, 4)
					_emit({"t": "status_applied", "side": foe_side, "pokemon": foe["name"], "status": "confused"})
			"confuse_self":
				if rng.randf() < 0.5 and me["confused_turns"] <= 0:
					me["confused_turns"] = rng.randi_range(1, 3)
					_emit({"t": "status_applied", "side": side, "pokemon": me["name"], "status": "confused"})
			"flinch":
				if rng.randf() <= float(parts[1]):
					foe["flinched"] = true
			"stat":
				# stat:<name>:<delta>[:chance][:self]
				var stat: String = parts[1]
				var delta := int(parts[2])
				var chance3 := float(parts[3]) if parts.size() > 3 else 1.0
				var on_self: bool = parts.size() > 4 and parts[4] == "self"
				if rng.randf() <= chance3:
					var target: Dictionary = me if on_self else foe
					var t_side := side if on_self else foe_side
					var old := int(target["stages"][stat])
					var new_val: int = clampi(old + delta, -6, 6)
					if new_val != old:
						target["stages"][stat] = new_val
						_emit({"t": "stat_change", "side": t_side, "pokemon": target["name"],
							"stat": stat, "delta": new_val - old, "stage": new_val})
			"heal":
				var amount := maxi(1, int(me["max_hp"] * float(parts[1])))
				var before := int(me["hp"])
				me["hp"] = mini(me["max_hp"], before + amount)
				if int(me["hp"]) > before:
					_emit({"t": "heal", "side": side, "pokemon": me["name"],
						"amount": int(me["hp"]) - before, "hp_left": me["hp"]})


func _apply_status(side: int, b: Dictionary, status: String) -> void:
	if b["status"] != "" or int(b["hp"]) <= 0:
		return
	# type immunities
	if status == "burn" and b["types"].has("fire"):
		return
	if status == "poison" and (b["types"].has("poison") or b["types"].has("ghost")):
		return
	if status == "para" and b["types"].has("electric"):
		return
	if status == "freeze" and b["types"].has("ice"):
		return
	b["status"] = status
	if status == "sleep":
		b["sleep_turns"] = rng.randi_range(1, 3)
	_emit({"t": "status_applied", "side": side, "pokemon": b["name"], "status": status})
	_hook(side, "%s was hit by %s!" % [b["name"], status])


func _apply_damage(side: int, b: Dictionary, dmg: int, event: Dictionary) -> void:
	event["hp_before"] = int(b["hp"])
	b["hp"] = maxi(0, int(b["hp"]) - dmg)
	event["amount"] = dmg
	event["hp_left"] = b["hp"]
	event["max_hp"] = b["max_hp"]
	_emit(event)
	if int(b["hp"]) <= 0:
		_emit({"t": "faint", "side": side, "pokemon": b["name"]})
		_hook(side, "%s fainted!" % b["name"])
		_after_faint(side)


func _after_faint(side: int) -> void:
	if _all_fainted(side):
		_finish(1 - side)
		return
	# auto-send the best matchup replacement
	var foe: Dictionary = active_battler(1 - side)
	var best := -1
	var best_v := -INF
	for i in teams[side].size():
		if int(teams[side][i]["hp"]) <= 0:
			continue
		var v := _matchup_value(teams[side][i], foe)
		if v > best_v:
			best_v = v
			best = i
	if best >= 0:
		var prev: int = active[side]
		active[side] = best
		teams[side][best]["flinched"] = false
		_emit({"t": "switch", "side": side, "from": teams[side][prev]["name"],
			"to": teams[side][best]["name"], "forced": true})


func _end_of_turn(side: int) -> void:
	var b: Dictionary = active_battler(side)
	if int(b["hp"]) <= 0:
		return
	if b["status"] in ["burn", "poison"]:
		var tick := maxi(1, int(b["max_hp"] / 12.0))
		b["hp"] = maxi(0, int(b["hp"]) - tick)
		_emit({"t": "status_tick", "side": side, "pokemon": b["name"],
			"status": b["status"], "amount": tick, "hp_left": b["hp"]})
		if int(b["hp"]) <= 0:
			_emit({"t": "faint", "side": side, "pokemon": b["name"]})
			_hook(side, "%s fainted!" % b["name"])
			_after_faint(side)
	b["flinched"] = false


func _all_fainted(side: int) -> bool:
	for b in teams[side]:
		if int(b["hp"]) > 0:
			return false
	return true


func _team_hp_frac(side: int) -> float:
	var cur := 0.0
	var total := 0.0
	for b in teams[side]:
		cur += float(b["hp"])
		total += float(b["max_hp"])
	return cur / maxf(total, 1.0)


func _check_end() -> void:
	if _over:
		return
	if _all_fainted(0):
		_finish(1)
	elif _all_fainted(1):
		_finish(0)


func _finish(w: int) -> void:
	if _over:
		return
	_over = true
	_winner = w
	_emit({"t": "battle_end", "winner": w, "turns": turn})


func _emit(e: Dictionary) -> void:
	events.append(e)


func _hook(side: int, text: String) -> void:
	_emit({"t": "commentary_hook", "side": side, "text": text})
