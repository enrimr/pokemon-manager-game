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
##   or {"type": "use_item", "item": item_id, "target": party_index} — a trainer
##   item (class "usable" in items.json) spent from the side's battle inventory
##   (set_inventory). Using an item costs that side's turn, like the real games.
##
## Items: battlers carry a passive held item ("held_item" from make_battler);
## its effects fire automatically at the right hooks. Trainer items must be
## provided per battle via set_inventory(side, {item_id: count}) — the engine
## consumes from its own copy; read the remainder back with inventory(side).
## The built-in AI uses at most set_ai_item_budget(side, n) items (default 2).
##
## Event log: Array[Dictionary], every event has "t" (type) and usually "side" (0/1).
## Event types: battle_start, turn_start, move_used, damage, miss, faint, switch,
##   status_applied, status_tick, stat_change, heal, flinch, confused_hit, asleep,
##   paralyzed, commentary_hook, battle_end, item_used, held_item.
## item_used: {side, item, item_name, pokemon, target_index} — trainer action.
## held_item: {side, pokemon, item, item_name, effect, consumed?} — passive fire.

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
var _inventory: Array = [{}, {}]      # per-side battle bag: item_id -> count
var _items_used: Array = [0, 0]       # trainer items spent so far per side
var _ai_item_budget: Array = [2, 2]   # cap on AI-initiated item use per side


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
	s["item"] = str(b.get("held_item", ""))
	s["item_consumed"] = false
	s["choice_lock"] = ""    # move name a Choice item has locked in ("" = free)
	s["crit_stage"] = 0      # Dire Hit
	s["guard_turns"] = 0     # Guard Spec.
	s["nfe"] = bool(b.get("nfe", false))
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


## Give a side its battle bag: {item_id: count} of "usable"-class items.
## The engine keeps its own copy and decrements it as items are spent;
## call inventory(side) after the battle to see what is left.
func set_inventory(side: int, inv: Dictionary) -> void:
	_inventory[side] = inv.duplicate(true)


## Remaining battle bag for a side (live dict, mutated by the engine).
func inventory(side: int) -> Dictionary:
	return _inventory[side]


## Trainer items spent by a side so far this battle.
func items_used(side: int) -> int:
	return int(_items_used[side])


## Cap on how many items the built-in AI will use for a side (default 2).
## Explicit use_item actions passed into step_turn are never capped.
func set_ai_item_budget(side: int, n: int) -> void:
	_ai_item_budget[side] = maxi(0, n)


## Legal action list for a side (for UIs and AI).
## Respects Choice move-locks, Assault Vest (no status moves) and the side's
## battle inventory (use_item entries appear for every valid item+target pair).
func legal_actions(side: int) -> Array:
	var acts: Array = []
	var me: Dictionary = active_battler(side)
	for i in me["moves"].size():
		if int(me["pp"].get(me["moves"][i], 0)) > 0 and _move_allowed(me, me["moves"][i]):
			acts.append({"type": "move", "index": i})
	if acts.is_empty():
		# item-constrained but out of options: fall back to any move with PP
		for i in me["moves"].size():
			if int(me["pp"].get(me["moves"][i], 0)) > 0:
				acts.append({"type": "move", "index": i})
	if acts.is_empty():
		acts.append({"type": "move", "index": 0})  # struggle-ish: allow move 0
	for i in teams[side].size():
		if i != active[side] and int(teams[side][i]["hp"]) > 0:
			acts.append({"type": "switch", "index": i})
	acts += _item_actions(side)
	return acts


## Can this battler select this move right now (held-item constraints)?
func _move_allowed(b: Dictionary, mname: String) -> bool:
	var lock: String = str(b.get("choice_lock", ""))
	if lock != "" and mname != lock and not _held_tag(b, "choice").is_empty() \
			and int(b["pp"].get(lock, 0)) > 0:
		return false
	if not _held_tag(b, "assault_vest").is_empty():
		if str(DataStore.move(mname).get("category", "")) == "status":
			return false
	return true


## All valid {"type":"use_item"} actions for a side given its inventory.
func _item_actions(side: int) -> Array:
	var out: Array = []
	var inv: Dictionary = _inventory[side]
	for iid in inv:
		if int(inv[iid]) <= 0:
			continue
		var it: Dictionary = DataStore.item(str(iid))
		if it.is_empty() or str(it["class"]) != "usable":
			continue
		for t in teams[side].size():
			if _item_target_valid(side, it, t):
				out.append({"type": "use_item", "item": str(iid), "target": t})
	return out


func _item_target_valid(side: int, it: Dictionary, t: int) -> bool:
	var b: Dictionary = teams[side][t]
	var is_active: bool = t == active[side]
	for f in it.get("effects", []):
		var parts: PackedStringArray = str(f).split(":")
		match parts[0]:
			"revive":
				if int(b["hp"]) <= 0:
					return true
			"heal":
				if int(b["hp"]) > 0 and int(b["hp"]) < int(b["max_hp"]):
					return true
			"full_restore":
				if int(b["hp"]) > 0 and (int(b["hp"]) < int(b["max_hp"])
						or str(b["status"]) != "" or int(b["confused_turns"]) > 0):
					return true
			"cure":
				if int(b["hp"]) > 0 and _cure_applies(b, parts[1]):
					return true
			"xstat":
				if is_active and int(b["hp"]) > 0 and int(b["stages"][parts[1]]) < 6:
					return true
			"dire_hit":
				if is_active and int(b["hp"]) > 0 and int(b.get("crit_stage", 0)) < 1:
					return true
			"guard_spec":
				if is_active and int(b["hp"]) > 0 and int(b.get("guard_turns", 0)) <= 0:
					return true
	return false


func _cure_applies(b: Dictionary, what: String) -> bool:
	if what == "all":
		return str(b["status"]) != "" or int(b["confused_turns"]) > 0
	if what == "confuse":
		return int(b["confused_turns"]) > 0
	return str(b["status"]) == what


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
	# Switches resolve first, then trainer items, then moves by priority/speed.
	for side in 2:
		if acts[side]["type"] == "switch":
			_do_switch(side, int(acts[side]["index"]))
	var item_sides: Array = []
	for side in 2:
		if acts[side]["type"] == "use_item":
			item_sides.append(side)
	if item_sides.size() == 2 and _eff_stat(active_battler(1), "spe") > _eff_stat(active_battler(0), "spe"):
		item_sides = [1, 0]
	for side in item_sides:
		_do_use_item(side, acts[side])
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


## Simple but sensible AI: best expected damage, switch when hard-countered,
## reaches into the bag (within its item budget) when the active mon is hurting.
func ai_choose_action(side: int) -> Dictionary:
	var item_act := _ai_item_action(side)
	if not item_act.is_empty():
		return item_act
	var me: Dictionary = active_battler(side)
	var foe: Dictionary = active_battler(1 - side)
	var best_idx := 0
	var best_score := -1.0
	for i in me["moves"].size():
		var mname: String = me["moves"][i]
		if int(me["pp"].get(mname, 0)) <= 0 or not _move_allowed(me, mname):
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
	var item_act := _ai_item_action(side)
	if not item_act.is_empty():
		return item_act
	var aggression: String = str(opts.get("aggression", "balanced"))
	var switching: String = str(opts.get("switching", "normal"))
	var me: Dictionary = active_battler(side)
	var foe: Dictionary = active_battler(1 - side)
	var best_idx := 0
	var best_score := -1.0
	for i in me["moves"].size():
		var mname: String = me["moves"][i]
		if int(me["pp"].get(mname, 0)) <= 0 or not _move_allowed(me, mname):
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


# ------------------------------------------------------------------ items

## Effects array of a battler's held item ([] if none / already consumed).
func _held_fx(b: Dictionary) -> Array:
	var iid: String = str(b.get("item", ""))
	if iid == "" or b.get("item_consumed", false):
		return []
	return DataStore.item(iid).get("effects", [])


## First held effect whose tag matches, split into parts (empty if absent).
func _held_tag(b: Dictionary, tag: String) -> PackedStringArray:
	for f in _held_fx(b):
		var parts: PackedStringArray = str(f).split(":")
		if parts[0] == tag:
			return parts
	return PackedStringArray()


func _emit_held(side: int, b: Dictionary, effect: String, consumed: bool = false) -> void:
	var iid: String = str(b.get("item", ""))
	_emit({"t": "held_item", "side": side, "pokemon": b["name"], "item": iid,
		"item_name": DataStore.item_name(iid), "effect": effect, "consumed": consumed})


func _consume_held(side: int, b: Dictionary, effect: String) -> void:
	_emit_held(side, b, effect, true)
	b["item_consumed"] = true


## Berry check the instant a status lands (Lum/Chesto/Cheri/...).
func _check_status_berry(side: int, b: Dictionary) -> void:
	var cb := _held_tag(b, "cure_berry")
	if cb.size() < 2:
		return
	var status: String = str(b["status"])
	if status == "" or (cb[1] != "all" and cb[1] != status):
		return
	b["status"] = ""
	b["sleep_turns"] = 0
	if cb[1] == "all":
		b["confused_turns"] = 0
	_consume_held(side, b, "cure_berry")
	_emit({"t": "status_applied", "side": side, "pokemon": b["name"], "status": "cured"})
	_hook(side, "%s crunches its %s and shrugs off the %s!" %
		[b["name"], DataStore.item_name(str(b["item"])), status])


## Berry check the instant confusion sets in (Persim/Lum).
func _check_confuse_berry(side: int, b: Dictionary) -> void:
	var cb := _held_tag(b, "cure_berry")
	if cb.size() < 2 or int(b["confused_turns"]) <= 0:
		return
	if cb[1] != "all" and cb[1] != "confuse":
		return
	b["confused_turns"] = 0
	_consume_held(side, b, "cure_berry")
	_hook(side, "%s eats its %s and snaps out of confusion!" %
		[b["name"], DataStore.item_name(str(b["item"]))])


## AI bag decision: heal when low, cure when statused — capped by the budget.
func _ai_item_action(side: int) -> Dictionary:
	if _inventory[side].is_empty() or _items_used[side] >= int(_ai_item_budget[side]):
		return {}
	var me: Dictionary = active_battler(side)
	if int(me["hp"]) <= 0:
		return {}
	var frac := float(me["hp"]) / float(me["max_hp"])
	if frac < 0.35:
		var heal_id := _ai_best_heal(side, me)
		if heal_id != "" and rng.randf() < 0.75:
			return {"type": "use_item", "item": heal_id, "target": active[side]}
	if str(me["status"]) != "" and frac > 0.45:
		var cure_id := _ai_best_cure(side, me)
		if cure_id != "" and rng.randf() < 0.6:
			return {"type": "use_item", "item": cure_id, "target": active[side]}
	return {}


## Smallest heal that (mostly) covers the missing HP, else the biggest owned.
func _ai_best_heal(side: int, b: Dictionary) -> String:
	var missing := float(int(b["max_hp"]) - int(b["hp"]))
	var best_id := ""
	var best_amt := -1.0
	var best_over := INF
	for iid in _inventory[side]:
		if int(_inventory[side][iid]) <= 0:
			continue
		var it: Dictionary = DataStore.item(str(iid))
		for f in it.get("effects", []):
			var parts: PackedStringArray = str(f).split(":")
			if parts[0] != "heal" and parts[0] != "full_restore":
				continue
			var amt := float(b["max_hp"])
			if parts[0] == "heal" and parts[1] != "full":
				amt = float(parts[1])
			if amt >= missing * 0.8 and amt - missing < best_over:
				best_over = amt - missing
				best_id = str(iid)
			elif best_over == INF and amt > best_amt:
				best_amt = amt
				best_id = str(iid)
	return best_id


func _ai_best_cure(side: int, b: Dictionary) -> String:
	var status: String = str(b["status"])
	var fallback := ""
	for iid in _inventory[side]:
		if int(_inventory[side][iid]) <= 0:
			continue
		for f in DataStore.item(str(iid)).get("effects", []):
			var parts: PackedStringArray = str(f).split(":")
			if parts[0] == "cure" and parts[1] == status:
				return str(iid)
			if (parts[0] == "cure" and parts[1] == "all") or parts[0] == "full_restore":
				fallback = str(iid)
	return fallback


## Execute a trainer use_item action. Costs the side's turn.
func _do_use_item(side: int, act: Dictionary) -> void:
	var iid := str(act.get("item", ""))
	var t := clampi(int(act.get("target", active[side])), 0, teams[side].size() - 1)
	var inv: Dictionary = _inventory[side]
	if int(inv.get(iid, 0)) <= 0:
		return
	var it: Dictionary = DataStore.item(iid)
	if it.is_empty() or str(it["class"]) != "usable":
		return
	if not _item_target_valid(side, it, t):
		return
	var b: Dictionary = teams[side][t]
	inv[iid] = int(inv[iid]) - 1
	_items_used[side] = int(_items_used[side]) + 1
	_emit({"t": "item_used", "side": side, "item": iid, "item_name": it["name"],
		"pokemon": b["name"], "target_index": t})
	_hook(side, "The bench springs into action — %s used on %s!" % [it["name"], b["name"]])
	for f in it.get("effects", []):
		var parts: PackedStringArray = str(f).split(":")
		match parts[0]:
			"heal":
				if int(b["hp"]) > 0:
					var amt: int = int(b["max_hp"]) if parts[1] == "full" else int(parts[1])
					_heal(side, b, amt)
			"full_restore":
				if int(b["hp"]) > 0:
					_cure_status(side, b, "all")
					_heal(side, b, int(b["max_hp"]))
			"cure":
				if int(b["hp"]) > 0:
					_cure_status(side, b, parts[1])
			"revive":
				if int(b["hp"]) <= 0:
					b["hp"] = maxi(1, int(float(b["max_hp"]) * float(parts[1])))
					b["status"] = ""
					b["sleep_turns"] = 0
					b["confused_turns"] = 0
					_emit({"t": "heal", "side": side, "pokemon": b["name"],
						"amount": int(b["hp"]), "hp_left": b["hp"], "revived": true})
					_hook(side, "%s is back on its feet — what a call from the dugout!" % b["name"])
			"xstat":
				var stat: String = parts[1]
				var old := int(b["stages"][stat])
				var new_val: int = clampi(old + int(parts[2]), -6, 6)
				if new_val != old:
					b["stages"][stat] = new_val
					_emit({"t": "stat_change", "side": side, "pokemon": b["name"],
						"stat": stat, "delta": new_val - old, "stage": new_val})
			"dire_hit":
				b["crit_stage"] = maxi(int(b.get("crit_stage", 0)), 1)
				_hook(side, "%s is pumped up — critical hits incoming!" % b["name"])
			"guard_spec":
				b["guard_turns"] = 5
				_hook(side, "A protective veil settles over %s!" % b["name"])


func _cure_status(side: int, b: Dictionary, what: String) -> void:
	var had: String = str(b["status"])
	if what == "all" or what == "confuse":
		b["confused_turns"] = 0
	if what == "all" or (had != "" and what == had):
		b["status"] = ""
		b["sleep_turns"] = 0
	if had != "" and str(b["status"]) == "":
		_emit({"t": "status_applied", "side": side, "pokemon": b["name"], "status": "cured"})


func _heal(side: int, b: Dictionary, amount: int) -> void:
	var before := int(b["hp"])
	b["hp"] = mini(int(b["max_hp"]), before + maxi(1, amount))
	if int(b["hp"]) > before:
		_emit({"t": "heal", "side": side, "pokemon": b["name"],
			"amount": int(b["hp"]) - before, "hp_left": b["hp"]})


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
	var claw := [false, false]
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
			var qc := _held_tag(me, "quick_claw")
			if qc.size() >= 2 and rng.randf() < float(qc[1]):
				claw[side] = true
	if prio[0] != prio[1]:
		return [0, 1] if prio[0] > prio[1] else [1, 0]
	if claw[0] != claw[1]:
		var s: int = 0 if claw[0] else 1
		_emit_held(s, active_battler(s), "quick_claw")
		_hook(s, "%s's Quick Claw glints — it darts in first!" % active_battler(s)["name"])
		return [0, 1] if claw[0] else [1, 0]
	if spe[0] != spe[1]:
		return [0, 1] if spe[0] > spe[1] else [1, 0]
	return [0, 1] if rng.randf() < 0.5 else [1, 0]


func _eff_stat(b: Dictionary, stat: String) -> float:
	var v := float(b["stats"][stat])
	v *= STAGE_MULT[int(b["stages"][stat]) + 6]
	if stat == "atk" and b["status"] == "burn":
		v *= 0.5
	# held items
	var ch := _held_tag(b, "choice")
	if ch.size() >= 3 and ch[1] == stat:
		v *= float(ch[2])
	if stat == "spd" and not _held_tag(b, "assault_vest").is_empty():
		v *= 1.5
	if (stat == "def" or stat == "spd") and b.get("nfe", false) \
			and not _held_tag(b, "eviolite").is_empty():
		v *= 1.5
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
	from["choice_lock"] = ""   # Choice items re-pick on re-entry
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
	if str(me.get("choice_lock", "")) == "" and not _held_tag(me, "choice").is_empty():
		me["choice_lock"] = mname
		_emit_held(side, me, "choice_lock")

	var fx: Array = mv.get("effects", [])
	var never_miss := fx.has("never_miss")

	# Accuracy check
	var acc := float(mv.get("accuracy", 100))
	if acc > 0.0 and not never_miss:
		var hit_chance := acc / 100.0
		hit_chance *= ACC_STAGE_MULT[int(me["stages"]["acc"]) + 6]
		hit_chance /= ACC_STAGE_MULT[int(foe["stages"]["eva"]) + 6]
		var bp := _held_tag(foe, "bright_powder")
		if bp.size() >= 2:
			hit_chance *= float(bp[1])
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
		if not _held_tag(me, "scope_lens").is_empty():
			crit_chance *= 2.0
		crit_chance = minf(crit_chance * pow(2.0, float(me.get("crit_stage", 0))), 0.5)
		crit = rng.randf() < crit_chance
		var is_phys: bool = mv["category"] == "phys"
		var a := _eff_stat(me, "atk" if is_phys else "spa")
		var d := _eff_stat(foe, "def" if is_phys else "spd")
		if crit:  # crits ignore stages
			a = float(me["stats"]["atk" if is_phys else "spa"])
			d = float(foe["stats"]["def" if is_phys else "spd"])
		var stab: float = 1.5 if me["types"].has(mv["type"]) else 1.0
		var item_mult := 1.0
		var tb := _held_tag(me, "type_boost")
		if tb.size() >= 3 and tb[1] == str(mv["type"]):
			item_mult *= float(tb[2])
		if not _held_tag(me, "life_orb").is_empty():
			item_mult *= 1.3
		var base: float = (2.0 * float(me["level"]) / 5.0 + 2.0) * float(mv["power"]) * a / maxf(d, 1.0) / 50.0 + 2.0
		var roll := rng.randf_range(0.85, 1.0)
		dmg = int(base * stab * eff * (1.5 if crit else 1.0) * item_mult * roll)
	if eff == 0.0:
		_emit({"t": "damage", "side": foe_side, "pokemon": foe["name"], "amount": 0,
			"hp_left": foe["hp"], "effectiveness": 0.0, "crit": false, "move": mname})
		_hook(foe_side, "It doesn't affect %s..." % foe["name"])
		return
	dmg = maxi(1, dmg)
	# Focus Sash: survive a KO blow from full HP with 1 HP (single use)
	var sashed := false
	if dmg >= int(foe["hp"]) and int(foe["hp"]) == int(foe["max_hp"]) \
			and int(foe["max_hp"]) > 1 and not _held_tag(foe, "sash").is_empty():
		dmg = int(foe["hp"]) - 1
		sashed = true
	var foe_helmet := _held_tag(foe, "rocky_helmet")
	_apply_damage(foe_side, foe, dmg, {"t": "damage", "side": foe_side, "pokemon": foe["name"],
		"effectiveness": eff, "crit": crit, "move": mname, "by": me["name"], "by_side": side})
	if sashed:
		_consume_held(foe_side, foe, "sash")
		_hook(foe_side, "%s hangs on with its Focus Sash!" % foe["name"])
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

	# Post-damage held-item effects
	if foe_helmet.size() >= 2 and mv["category"] == "phys" and int(me["hp"]) > 0:
		_emit_held(foe_side, foe, "rocky_helmet")
		var spikes := maxi(1, int(float(me["max_hp"]) * float(foe_helmet[1])))
		_apply_damage(side, me, spikes, {"t": "damage", "side": side, "pokemon": me["name"],
			"effectiveness": 1.0, "crit": false, "move": mname, "item": "rocky_helmet"})
		_hook(side, "%s is gashed by the Rocky Helmet!" % me["name"])
	var bell := _held_tag(me, "shell_bell")
	if bell.size() >= 2 and int(me["hp"]) > 0 and int(me["hp"]) < int(me["max_hp"]):
		_emit_held(side, me, "shell_bell")
		_heal(side, me, maxi(1, int(float(dmg) * float(bell[1]))))
	if not _held_tag(me, "life_orb").is_empty() and int(me["hp"]) > 0:
		_emit_held(side, me, "life_orb")
		_apply_damage(side, me, maxi(1, int(me["max_hp"] / 10.0)),
			{"t": "damage", "side": side, "pokemon": me["name"], "effectiveness": 1.0,
			"crit": false, "move": mname, "recoil": true, "item": "life_orb"})
	var kr := _held_tag(me, "kings_rock")
	if kr.size() >= 2 and int(foe["hp"]) > 0 and not foe["flinched"] and rng.randf() < float(kr[1]):
		foe["flinched"] = true
		_emit_held(side, me, "kings_rock")

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
					_check_confuse_berry(foe_side, foe)
			"confuse_self":
				if rng.randf() < 0.5 and me["confused_turns"] <= 0:
					me["confused_turns"] = rng.randi_range(1, 3)
					_emit({"t": "status_applied", "side": side, "pokemon": me["name"], "status": "confused"})
					_check_confuse_berry(side, me)
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
					if not on_self and delta < 0 and int(target.get("guard_turns", 0)) > 0:
						_hook(t_side, "%s is shielded by Guard Spec. — its stats hold firm!" % target["name"])
						continue
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
	_check_status_berry(side, b)


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
	# Leftovers-style regeneration first — it can keep the holder out of tick range
	var lh := _held_tag(b, "end_turn_heal")
	if lh.size() >= 2 and int(b["hp"]) < int(b["max_hp"]):
		_emit_held(side, b, "end_turn_heal")
		_heal(side, b, maxi(1, int(float(b["max_hp"]) * float(lh[1]))))
	if b["status"] in ["burn", "poison"]:
		var tick := maxi(1, int(b["max_hp"] / 12.0))
		b["hp"] = maxi(0, int(b["hp"]) - tick)
		_emit({"t": "status_tick", "side": side, "pokemon": b["name"],
			"status": b["status"], "amount": tick, "hp_left": b["hp"]})
		if int(b["hp"]) <= 0:
			_emit({"t": "faint", "side": side, "pokemon": b["name"]})
			_hook(side, "%s fainted!" % b["name"])
			_after_faint(side)
			return
	# Sitrus Berry: emergency ration at half HP or below (single use)
	var st := _held_tag(b, "sitrus")
	if st.size() >= 2 and int(b["hp"]) > 0 and int(b["hp"]) * 2 <= int(b["max_hp"]):
		_consume_held(side, b, "sitrus")
		_heal(side, b, maxi(1, int(float(b["max_hp"]) * float(st[1]))))
		_hook(side, "%s wolfs down its Sitrus Berry!" % b["name"])
	if int(b.get("guard_turns", 0)) > 0:
		b["guard_turns"] = int(b["guard_turns"]) - 1
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
