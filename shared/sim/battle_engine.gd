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
##   paralyzed, commentary_hook, battle_end, item_used, held_item,
##   ability_triggered, weather_start, weather_end, weather_chip.
## item_used: {side, item, item_name, pokemon, target_index} — trainer action.
## held_item: {side, pokemon, item, item_name, effect, consumed?} — passive fire.
## ability_triggered: {side, pokemon, ability, ability_name, effect} — an
##   ability fired at one of its hooks (entry, immunity, contact, pinch...).
## weather_start: {kind: sun|rain|sand|hail, turns, source: "move"|"ability", pokemon}
## weather_end:   {kind} — the weather ran out at end of turn.
## weather_chip:  {side, pokemon, kind, amount, hp_left, max_hp} — residual damage.
##
## Depth systems (battle-depth piece):
## - Natures: ±10% on one non-HP stat, applied when battlers are initialised
##   (battler["nature"] from DataStore.make_battler; see natures.json).
## - Abilities: battler["ability"] (abilities.json id). All tags in that file
##   are load-bearing; unknown tags stay inert. "Contact" = physical category.
## - Weather: weather() -> ""|"sun"|"rain"|"sand"|"hail", weather_turns_left().
##   Moves last 5 turns, auto-weather abilities 8. Sun: fire x1.5 / water x0.5.
##   Rain: water x1.5 / fire x0.5. Sand: chips non rock/ground/steel 1/16,
##   rock gets SpD x1.5. Hail: chips non-ice 1/16. AI prefers boosted moves.
##
## DOUBLES (2v2) mode — BattleEngine.new(team_a, team_b, seed, "doubles"):
## - Two active slots per side (slots[side] = [party_idx, party_idx]).
## - Per-slot actions. step_turn(a, b) takes, per side, either null (AI runs
##   both slots) or an Array of up to 2 per-slot actions (null = AI that slot).
##   Move actions may carry "target": {"side": s, "slot": k} for single-target
##   moves; legal_actions_slot(side, slot) lists the choosable targets.
## - Spread moves hit both foes at 0.75x (SPREAD_FOES); field quakes like
##   Earthquake/Surf/Explosion also hit the user's ally (SPREAD_ALL).
## - Redirection basics: if the chosen target has fainted by the time the move
##   resolves, it is redirected to the remaining foe; a move with no legal
##   target fizzles ("no_target" event).
## - Faints refill from the bench immediately (best matchup). Entry abilities
##   (Intimidate, auto-weather) fire per slot; Intimidate hits BOTH foes.
## - Doubles events additionally carry "slot" (actor) / "target_slot", and
##   damage events carry "spread": true on multi-target hits.
## - Deterministic exactly like singles: same teams + seed + mode = same log.

const MAX_TURNS := 300
const STAGE_MULT := [0.25, 0.28, 0.33, 0.4, 0.5, 0.66, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0]
const ACC_STAGE_MULT := [0.33, 0.36, 0.43, 0.5, 0.6, 0.75, 1.0, 1.33, 1.66, 2.0, 2.33, 2.66, 3.0]

# Doubles targeting classes. SPREAD_ALL hits both foes AND the user's ally
# (Earthquake-style field moves); SPREAD_FOES hits both opposing slots.
# Spread damage is scaled x0.75 when a move actually hits 2+ targets.
const SPREAD_ALL := ["Earthquake", "Magnitude", "Explosion", "Self-Destruct", "Surf"]
const SPREAD_FOES := ["Rock Slide", "Blizzard", "Icy Wind", "Powder Snow", "Twister",
	"Swift", "Razor Leaf", "Growl", "Tail Whip", "String Shot", "Leer"]
const SPREAD_MULT := 0.75

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
var _weather: String = ""             # "", "sun", "rain", "sand", "hail"
var _weather_turns: int = 0           # end-of-turn countdown; 0 = clear
var mode: String = "singles"          # "singles" | "doubles"
var slots: Array = [[0], [0]]         # active party index per slot, per side


func _init(team_a: Array, team_b: Array, battle_seed: int = 0, battle_mode: String = "singles") -> void:
	rng.seed = battle_seed
	mode = battle_mode if battle_mode in ["singles", "doubles"] else "singles"
	teams[0] = team_a.map(_init_battler)
	teams[1] = team_b.map(_init_battler)
	var start_ev := {"t": "battle_start", "mode": mode,
		"team_a": teams[0].map(func(b): return b["name"]),
		"team_b": teams[1].map(func(b): return b["name"])}
	if mode == "doubles":
		slots = [[0, 1 if teams[0].size() > 1 else -1], [0, 1 if teams[1].size() > 1 else -1]]
		_emit(start_ev)
		for side in 2:
			for k in 2:
				if slots[side][k] >= 0:
					_emit({"t": "switch", "side": side, "slot": k,
						"to": teams[side][slots[side][k]]["name"], "first": true})
		# Entry abilities fire per slot, ordered by effective speed field-wide.
		var order := _field_speed_order()
		for e in order:
			_on_entry_at(e[0], e[1])
		return
	_emit(start_ev)
	_emit({"t": "switch", "side": 0, "to": teams[0][0]["name"], "first": true})
	_emit({"t": "switch", "side": 1, "to": teams[1][0]["name"], "first": true})
	# Entry abilities fire on the initial send-out, faster side first.
	var first: int = 0 if _eff_stat(teams[0][0], "spe") >= _eff_stat(teams[1][0], "spe") else 1
	_on_entry(first)
	_on_entry(1 - first)


func _init_battler(b: Dictionary) -> Dictionary:
	var s: Dictionary = b.duplicate(true)
	# Nature: +10% / -10% on one non-HP stat (natures.json; neutral = no-op).
	var nat: Dictionary = DataStore.nature(str(s.get("nature", "Hardy")))
	if not nat.is_empty():
		var plus: Variant = nat.get("plus")
		var minus: Variant = nat.get("minus")
		if plus != null and str(plus) != "hp" and s["stats"].has(str(plus)):
			s["stats"][str(plus)] = int(floor(float(s["stats"][str(plus)]) * 1.1))
		if minus != null and str(minus) != "hp" and s["stats"].has(str(minus)):
			s["stats"][str(minus)] = maxi(1, int(floor(float(s["stats"][str(minus)]) * 0.9)))
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
	s["ability"] = str(b.get("ability", ""))
	s["flash_fire"] = false  # Flash Fire absorbed a hit: own fire moves x1.5
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


## Current weather: "" (clear), "sun", "rain", "sand" or "hail".
func weather() -> String:
	return _weather


## Turns of weather remaining (counts down at end of turn; 0 = clear).
func weather_turns_left() -> int:
	return _weather_turns


## True when this battle runs the 2v2 doubles ruleset.
func is_doubles() -> bool:
	return mode == "doubles"


## Number of active slots per side (1 in singles, 2 in doubles).
func slot_count() -> int:
	return slots[0].size()


## Party index occupying a slot (-1 = empty).
func slot_index(side: int, slot: int) -> int:
	if slot < 0 or slot >= slots[side].size():
		return -1
	return int(slots[side][slot])


## Live battler dict in a slot ({} if the slot is empty).
func slot_battler(side: int, slot: int) -> Dictionary:
	return _slot_ref(side, slot)


func _slot_ref(side: int, slot: int) -> Dictionary:
	var idx := slot_index(side, slot)
	if idx < 0 or idx >= teams[side].size():
		return {}
	return teams[side][idx]


func _slot_alive(side: int, slot: int) -> bool:
	var b := _slot_ref(side, slot)
	return not b.is_empty() and int(b["hp"]) > 0


## Is this party index currently in an active slot?
func _is_active_index(side: int, idx: int) -> bool:
	return slots[side].has(idx)


## Alive foe slot numbers as seen from `side`.
func _alive_slots(side: int) -> Array:
	var out: Array = []
	for k in slots[side].size():
		if _slot_alive(side, k):
			out.append(k)
	return out


## Targeting class of a move in doubles:
## "self" | "field" | "single" | "spread_foes" | "spread_all".
func move_targeting(mname: String) -> String:
	if SPREAD_ALL.has(mname):
		return "spread_all"
	if SPREAD_FOES.has(mname):
		return "spread_foes"
	var mv: Dictionary = DataStore.move(mname)
	if mv.is_empty():
		return "single"
	if str(mv.get("category", "")) != "status":
		return "single"
	var self_only := true
	for f in mv.get("effects", []):
		var parts: PackedStringArray = str(f).split(":")
		match parts[0]:
			"weather":
				return "field"
			"heal", "confuse_self", "priority", "never_miss":
				pass
			"stat":
				if not (parts.size() > 4 and parts[4] == "self"):
					self_only = false
			_:
				self_only = false
	return "self" if self_only else "single"


## Doubles: legal actions for one slot. Move entries carry "move", "targeting"
## and (single-target only) "targets": [{"side","slot","name"}]. Switch entries
## are shared bench mons; use_item entries are side-level (same as singles).
func legal_actions_slot(side: int, slot: int) -> Array:
	if mode != "doubles":
		return legal_actions(side)
	var me := _slot_ref(side, slot)
	if me.is_empty() or int(me["hp"]) <= 0:
		return []
	var acts: Array = []
	for i in me["moves"].size():
		var mname: String = me["moves"][i]
		if int(me["pp"].get(mname, 0)) <= 0 or not _move_allowed(me, mname):
			continue
		acts.append(_slot_move_action(side, i, mname))
	if acts.is_empty():
		for i in me["moves"].size():
			if int(me["pp"].get(me["moves"][i], 0)) > 0:
				acts.append(_slot_move_action(side, i, me["moves"][i]))
	if acts.is_empty():
		acts.append(_slot_move_action(side, 0, me["moves"][0] if me["moves"].size() > 0 else ""))
	for i in teams[side].size():
		if not _is_active_index(side, i) and int(teams[side][i]["hp"]) > 0:
			acts.append({"type": "switch", "index": i})
	acts += _item_actions(side)
	return acts


func _slot_move_action(side: int, idx: int, mname: String) -> Dictionary:
	var tg := move_targeting(mname)
	var act := {"type": "move", "index": idx, "move": mname, "targeting": tg}
	if tg == "single":
		var targets: Array = []
		for fk in _alive_slots(1 - side):
			targets.append({"side": 1 - side, "slot": fk,
				"name": _slot_ref(1 - side, fk)["name"]})
		act["targets"] = targets
	return act


## Legal action list for a side (for UIs and AI).
## Respects Choice move-locks, Assault Vest (no status moves) and the side's
## battle inventory (use_item entries appear for every valid item+target pair).
func legal_actions(side: int) -> Array:
	if mode == "doubles":
		return legal_actions_slot(side, 0)
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
	var is_active: bool = _is_active_index(side, t)
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
	if mode == "doubles":
		return _step_turn_doubles(action_a, action_b)
	turn += 1
	var start := events.size()
	_emit({"t": "turn_start", "turn": turn,
		"hp_a": _team_hp_frac(0), "hp_b": _team_hp_frac(1),
		"active_a": active_battler(0)["name"], "active_b": active_battler(1)["name"],
		"weather": _weather, "weather_turns": _weather_turns})
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
		_tick_weather()
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
	return _preview_calc(side, active_battler(side), 1 - side, active_battler(1 - side), move_idx, 1.0)


## Doubles-aware preview against a specific target slot (0.75x folded in for
## spread moves that would currently hit 2+ targets).
func preview_move_at(side: int, slot: int, move_idx: int, t_side: int, t_slot: int) -> Dictionary:
	var me := _slot_ref(side, slot)
	var foe := _slot_ref(t_side, t_slot)
	if me.is_empty() or foe.is_empty():
		return {}
	var mult := 1.0
	if move_idx >= 0 and move_idx < me["moves"].size():
		var tg := move_targeting(str(me["moves"][move_idx]))
		if tg == "spread_foes" or tg == "spread_all":
			var n := _alive_slots(1 - side).size()
			if tg == "spread_all" and _slot_alive(side, 1 - slot):
				n += 1
			if n > 1:
				mult = SPREAD_MULT
	return _preview_calc(side, me, t_side, foe, move_idx, mult)


func _preview_calc(side: int, me: Dictionary, foe_side: int, foe: Dictionary,
		move_idx: int, spread_mult: float) -> Dictionary:
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
		# Ability immunity/absorb on the target zeroes the estimate.
		var im := _ab_tag(foe, "immune")
		var ab := _ab_tag(foe, "absorb")
		if (im.size() >= 2 and im[1] == str(mv["type"])) \
				or (ab.size() >= 2 and ab[1] == str(mv["type"])):
			return {"eff": 0.0, "stab": stab, "est_frac": 0.0}
		var fixed := _fixed_damage(mv.get("effects", []), me)
		if fixed > 0:
			est = float(fixed) if eff > 0.0 else 0.0
		else:
			var is_phys: bool = mv["category"] == "phys"
			var a := _eff_stat(me, "atk" if is_phys else "spa")
			var d := _eff_stat(foe, "def" if is_phys else "spd")
			var base: float = (2.0 * float(me["level"]) / 5.0 + 2.0) * float(mv["power"]) * a / maxf(d, 1.0) / 50.0 + 2.0
			est = base * (1.5 if stab else 1.0) * eff * 0.925 * spread_mult \
				* _offense_mult(side, me, mv, false) * _defense_mult(foe_side, foe, mv, false)
	return {"eff": eff, "stab": stab, "est_frac": clampf(est / maxf(float(foe["max_hp"]), 1.0), 0.0, 1.0)}


# ------------------------------------------------------------------ abilities & weather

## Effects array of a battler's ability ([] if none).
func _ab_fx(b: Dictionary) -> Array:
	return DataStore.ability(str(b.get("ability", ""))).get("effects", [])


## First ability effect whose tag matches, split into parts (empty if absent).
func _ab_tag(b: Dictionary, tag: String) -> PackedStringArray:
	for f in _ab_fx(b):
		var parts: PackedStringArray = str(f).split(":")
		if parts[0] == tag:
			return parts
	return PackedStringArray()


func _has_ab(b: Dictionary, tag: String) -> bool:
	return not _ab_tag(b, tag).is_empty()


func _emit_ability(side: int, b: Dictionary, effect: String) -> void:
	var aid: String = str(b.get("ability", ""))
	_emit({"t": "ability_triggered", "side": side, "pokemon": b["name"],
		"ability": aid, "ability_name": DataStore.ability_name(aid), "effect": effect})


## Entry abilities: Intimidate-style stat drops and auto-weather setters.
## Fires on the initial send-out, every switch and every forced replacement.
func _on_entry(side: int) -> void:
	_on_entry_at(side, 0)


## Slot-aware entry hook. In doubles, Intimidate-style drops hit BOTH foes.
func _on_entry_at(side: int, slot: int) -> void:
	var b: Dictionary = _slot_ref(side, slot)
	if b.is_empty() or int(b["hp"]) <= 0:
		return
	for f in _ab_fx(b):
		var parts: PackedStringArray = str(f).split(":")
		if parts[0] != "on_switch_in":
			continue
		if parts[1] == "stat" and parts.size() >= 5 and parts[4] == "foe":
			var announced := false
			for fk in slots[1 - side].size():
				var foe: Dictionary = _slot_ref(1 - side, fk)
				if foe.is_empty() or int(foe["hp"]) <= 0:
					continue
				if not announced:
					_emit_ability(side, b, "entry_stat")
					announced = true
				_hook(side, "%s's %s bears down on %s!" %
					[b["name"], DataStore.ability_name(str(b["ability"])), foe["name"]])
				_change_stage(1 - side, foe, parts[2], parts[3].to_int(), true)
		elif parts[1] == "weather" and parts.size() >= 3 and _weather != parts[2]:
			_emit_ability(side, b, "weather")
			_set_weather(parts[2], 8, "ability", side, str(b["name"]))


## Apply a stat-stage change; hostile drops respect Guard Spec. and the
## stat-protection abilities. Returns true if the stage actually moved.
func _change_stage(t_side: int, target: Dictionary, stat: String, delta: int, from_foe: bool) -> bool:
	if from_foe and delta < 0:
		if int(target.get("guard_turns", 0)) > 0:
			_hook(t_side, "%s is shielded by Guard Spec. — its stats hold firm!" % target["name"])
			return false
		var blocker := ""
		if _has_ab(target, "no_stat_drop"):
			blocker = "no_stat_drop"
		elif stat == "atk" and _has_ab(target, "no_atk_drop"):
			blocker = "no_atk_drop"
		elif stat == "acc" and _has_ab(target, "no_acc_drop"):
			blocker = "no_acc_drop"
		if blocker != "":
			_emit_ability(t_side, target, blocker)
			_hook(t_side, "%s's %s keeps its stats from dropping!" %
				[target["name"], DataStore.ability_name(str(target["ability"]))])
			return false
	var old := int(target["stages"][stat])
	var new_val: int = clampi(old + delta, -6, 6)
	if new_val == old:
		return false
	target["stages"][stat] = new_val
	_emit({"t": "stat_change", "side": t_side, "pokemon": target["name"],
		"stat": stat, "delta": new_val - old, "stage": new_val})
	return true


func _set_weather(kind: String, turns: int, source: String, side: int, pokemon: String) -> void:
	_weather = kind
	_weather_turns = turns
	_emit({"t": "weather_start", "kind": kind, "turns": turns, "source": source,
		"side": side, "pokemon": pokemon})
	var lines := {"sun": "The sunlight turns harsh!", "rain": "Rain starts pounding the arena!",
		"sand": "A sandstorm whips across the pitch!", "hail": "Hail starts pelting down!"}
	_hook(side, str(lines.get(kind, "The weather shifts!")))


## Ticks the weather countdown once per turn (end of turn, both sides done).
func _tick_weather() -> void:
	if _weather == "":
		return
	_weather_turns -= 1
	if _weather_turns <= 0:
		var was := _weather
		_weather = ""
		_emit({"t": "weather_end", "kind": was})
		var lines := {"sun": "The harsh sunlight faded.", "rain": "The rain let up.",
			"sand": "The sandstorm subsided.", "hail": "The hail stopped."}
		_hook(0, str(lines.get(was, "The skies clear.")))


## Weather damage multiplier for a move type (the sun/rain fire-water swing).
func _weather_move_mult(mtype: String) -> float:
	if _weather == "sun":
		if mtype == "fire":
			return 1.5
		if mtype == "water":
			return 0.5
	elif _weather == "rain":
		if mtype == "water":
			return 1.5
		if mtype == "fire":
			return 0.5
	return 1.0


## Is this battler immune to sand/hail residual damage?
func _weather_chip_immune(b: Dictionary) -> bool:
	if _weather == "sand":
		for t in ["rock", "ground", "steel"]:
			if b["types"].has(t):
				return true
		var sv := _ab_tag(b, "weather_eva")   # Sand Veil shrugs the storm off too
		if sv.size() >= 2 and sv[1] == "sand":
			return true
	elif _weather == "hail":
		if b["types"].has("ice"):
			return true
	return false


## Attacker-side damage multiplier: weather, Flash Fire charge, pinch boosts,
## type-boost items and Life Orb. Pure unless announce (pinch emits an event).
func _offense_mult(side: int, me: Dictionary, mv: Dictionary, announce: bool) -> float:
	var mtype: String = str(mv["type"])
	var m := _weather_move_mult(mtype)
	var tb := _held_tag(me, "type_boost")
	if tb.size() >= 3 and tb[1] == mtype:
		m *= float(tb[2])
	if not _held_tag(me, "life_orb").is_empty():
		m *= 1.3
	if mtype == "fire" and bool(me.get("flash_fire", false)):
		m *= 1.5
	var pb := _ab_tag(me, "pinch_boost")
	if pb.size() >= 3 and pb[1] == mtype and int(me["hp"]) * 3 <= int(me["max_hp"]):
		m *= float(pb[2])
		if announce:
			_emit_ability(side, me, "pinch_boost")
			_hook(side, "Backed into a corner, %s's %s ignites!" %
				[me["name"], DataStore.ability_name(str(me["ability"]))])
	return m


## Defender-side damage multiplier (Thick Fat style resists).
func _defense_mult(foe_side: int, foe: Dictionary, mv: Dictionary, announce: bool) -> float:
	var m := 1.0
	for f in _ab_fx(foe):
		var parts: PackedStringArray = str(f).split(":")
		if parts[0] == "resist" and parts.size() >= 3 and parts[1] == str(mv["type"]):
			m *= float(parts[2])
			if announce:
				_emit_ability(foe_side, foe, "resist")
				_hook(foe_side, "%s's %s blunts the blow!" %
					[foe["name"], DataStore.ability_name(str(foe["ability"]))])
	return m


## Full immunity / absorb abilities (Levitate, Flash Fire, Water/Volt Absorb).
## Returns true if the damaging move was nullified.
func _ability_absorbs(_side: int, _me: Dictionary, foe_side: int, foe: Dictionary, mv: Dictionary) -> bool:
	var mtype: String = str(mv["type"])
	var im := _ab_tag(foe, "immune")
	if im.size() >= 2 and im[1] == mtype:
		_emit_ability(foe_side, foe, "immune")
		_hook(foe_side, "%s's %s renders it untouchable — the %s move has no effect!" %
			[foe["name"], DataStore.ability_name(str(foe["ability"])), mtype])
		return true
	var ab := _ab_tag(foe, "absorb")
	if ab.size() >= 2 and ab[1] == mtype:
		_emit_ability(foe_side, foe, "absorb")
		if ab.size() >= 4 and ab[2] == "heal":
			_heal(foe_side, foe, maxi(1, int(float(foe["max_hp"]) * float(ab[3]))))
			_hook(foe_side, "%s drinks in the attack — %s restores its strength!" %
				[foe["name"], DataStore.ability_name(str(foe["ability"]))])
		else:
			foe["flash_fire"] = true
			_hook(foe_side, "%s's %s soaks up the flames — its own fire is stoked!" %
				[foe["name"], DataStore.ability_name(str(foe["ability"]))])
		return true
	return false


## Contact abilities on the defender (contact ≈ physical moves): Static,
## Poison Point, Flame Body, Effect Spore, Cute Charm, Rough Skin.
func _contact_abilities(side: int, me: Dictionary, foe_side: int, foe: Dictionary) -> void:
	var cs := _ab_tag(foe, "contact_status")
	if cs.size() >= 3 and rng.randf() < float(cs[2]):
		var status: String = str(cs[1])
		if status == "spore":
			status = ["sleep", "poison", "para"][rng.randi_range(0, 2)]
		_emit_ability(foe_side, foe, "contact_status")
		if status == "confuse":
			if int(me["confused_turns"]) <= 0 and not _has_ab(me, "immune_confuse"):
				me["confused_turns"] = rng.randi_range(2, 4)
				_emit({"t": "status_applied", "side": side, "pokemon": me["name"], "status": "confused"})
				_hook(side, "%s is left reeling by %s's %s!" %
					[me["name"], foe["name"], DataStore.ability_name(str(foe["ability"]))])
				_check_confuse_berry(side, me)
		else:
			_hook(foe_side, "%s's %s bites back on contact!" %
				[foe["name"], DataStore.ability_name(str(foe["ability"]))])
			_apply_status(side, me, status, foe_side, false, foe)
	var cd := _ab_tag(foe, "contact_damage")
	if cd.size() >= 2 and int(me["hp"]) > 0:
		_emit_ability(foe_side, foe, "contact_damage")
		_hook(side, "%s is raked raw by %s's %s!" %
			[me["name"], foe["name"], DataStore.ability_name(str(foe["ability"]))])
		_apply_damage(side, me, maxi(1, int(float(me["max_hp"]) * float(cd[1]))),
			{"t": "damage", "side": side, "pokemon": me["name"], "effectiveness": 1.0,
			"crit": false, "ability": str(foe["ability"])})


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
		# Weather moves: worth setting when it helps this team, useless twice.
		for f in mv.get("effects", []):
			var parts: PackedStringArray = str(f).split(":")
			if parts[0] == "weather":
				if _weather == parts[1]:
					return 1.0
				var wv := 18.0
				var ws := _ab_tag(user, "weather_speed")   # Swift Swim / Chlorophyll
				if ws.size() >= 2 and ws[1] == parts[1]:
					wv += 12.0
				for m2 in user["moves"]:
					var t2: String = str(DataStore.move(str(m2)).get("type", ""))
					if (parts[1] == "sun" and t2 == "fire") or (parts[1] == "rain" and t2 == "water"):
						wv += 8.0
						break
				return wv
		# Value status moves a bit; more if target is healthy and unstatused.
		var v := 20.0 * acc_f
		if target["status"] != "" and _has_status_effect(mv):
			v = 1.0
		return v * (0.5 + 0.5 * float(target["hp"]) / float(target["max_hp"]))
	var eff: float = DataStore.effectiveness(mv["type"], target["types"])
	var stab: float = 1.5 if user["types"].has(mv["type"]) else 1.0
	# AI weather awareness: prefer rain-boosted water / sun-boosted fire, etc.
	return float(mv.get("power", 0)) * eff * stab * acc_f * _weather_move_mult(str(mv["type"]))


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
		var guts := _ab_tag(b, "status_boost")   # Guts ignores the burn drop
		if not (guts.size() >= 2 and guts[1] == "atk"):
			v *= 0.5
	# abilities
	var mm := _ab_tag(b, "mult")               # Huge Power / Hustle
	if mm.size() >= 3 and mm[1] == stat:
		v *= float(mm[2])
	if str(b.get("status", "")) != "":
		var sb := _ab_tag(b, "status_boost")   # Guts
		if sb.size() >= 3 and sb[1] == stat:
			v *= float(sb[2])
	if stat == "spe":
		var ws := _ab_tag(b, "weather_speed")  # Chlorophyll / Swift Swim
		if ws.size() >= 3 and ws[1] == _weather:
			v *= float(ws[2])
	if stat == "spd" and _weather == "sand" and b["types"].has("rock"):
		v *= 1.5                               # sandstorm shores up Rock types
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
	from["flash_fire"] = false
	if str(from["status"]) != "" and _has_ab(from, "heal_status_on_switch"):
		_emit_ability(side, from, "heal_status_on_switch")
		from["status"] = ""
		from["sleep_turns"] = 0
		_emit({"t": "status_applied", "side": side, "pokemon": from["name"], "status": "cured"})
		_hook(side, "%s's Natural Cure kicks in as it heads to the bench!" % from["name"])
	active[side] = to_idx
	slots[side][0] = to_idx
	_emit({"t": "switch", "side": side, "from": from["name"], "to": active_battler(side)["name"]})
	_hook(side, "%s is recalled — %s takes the field!" % [from["name"], active_battler(side)["name"]])
	_on_entry(side)


func _do_move(side: int, move_idx: int) -> void:
	var me: Dictionary = active_battler(side)
	if int(me["hp"]) <= 0:
		return
	var foe_side := 1 - side
	var foe: Dictionary = active_battler(foe_side)
	if not _pre_move_gate(side, me):
		return
	move_idx = clampi(move_idx, 0, me["moves"].size() - 1)
	var mname: String = me["moves"][move_idx]
	var mv: Dictionary = DataStore.move(mname)
	if mv.is_empty():
		return
	_spend_pp(me, foe, mname)
	_emit({"t": "move_used", "side": side, "pokemon": me["name"], "move": mname})
	if str(me.get("choice_lock", "")) == "" and not _held_tag(me, "choice").is_empty():
		me["choice_lock"] = mname
		_emit_held(side, me, "choice_lock")
	_strike_target(side, me, foe_side, foe, mname, mv, 1.0, true, false, false, -1, -1)


## PP cost for a move (Pressure on the target burns extra PP).
func _spend_pp(me: Dictionary, foe: Dictionary, mname: String) -> void:
	var pp_cost := 1
	var press := _ab_tag(foe, "pp_pressure")   # Pressure: foes burn extra PP
	if press.size() >= 2:
		pp_cost = maxi(1, press[1].to_int())
	me["pp"][mname] = maxi(0, int(me["pp"].get(mname, 1)) - pp_cost)


## Pre-move status gates (flinch, sleep, freeze, para, confusion).
## Returns false when the battler loses its action this turn.
func _pre_move_gate(side: int, me: Dictionary) -> bool:
	if me["flinched"]:
		me["flinched"] = false
		_emit({"t": "flinch", "side": side, "pokemon": me["name"]})
		return false
	if me["status"] == "sleep":
		if _has_ab(me, "sleep_half"):   # Early Bird wakes twice as fast
			_emit_ability(side, me, "sleep_half")
			me["sleep_turns"] -= 2
		else:
			me["sleep_turns"] -= 1
		if me["sleep_turns"] <= 0:
			me["status"] = ""
			_emit({"t": "status_applied", "side": side, "pokemon": me["name"], "status": "woke"})
		else:
			_emit({"t": "asleep", "side": side, "pokemon": me["name"]})
			return false
	if me["status"] == "freeze":
		if rng.randf() < 0.25:
			me["status"] = ""
			_emit({"t": "status_applied", "side": side, "pokemon": me["name"], "status": "thawed"})
		else:
			_emit({"t": "asleep", "side": side, "pokemon": me["name"], "frozen": true})
			return false
	if me["status"] == "para" and rng.randf() < 0.25:
		_emit({"t": "paralyzed", "side": side, "pokemon": me["name"]})
		return false
	if me["confused_turns"] > 0:
		me["confused_turns"] -= 1
		if rng.randf() < 0.33:
			var self_dmg := maxi(1, int(_eff_stat(me, "atk") * 0.4))
			_apply_damage(side, me, self_dmg, {"t": "confused_hit", "side": side, "pokemon": me["name"]})
			return false
	return true


## One attacker-vs-one-target strike: accuracy, damage, held/ability hooks,
## secondary effects. Shared by singles (_do_move) and doubles (_do_move_d).
## spread_mult scales damage (0.75 on multi-target hits); first_target gates
## once-per-move user effects (Life Orb, King's Rock); is_ally suppresses
## contact/secondary effects on friendly splash damage; defer_recoil makes
## the function RETURN recoil owed instead of applying it (spread moves apply
## it once after all targets). my_slot/t_slot >= 0 decorate events (doubles).
func _strike_target(side: int, me: Dictionary, foe_side: int, foe: Dictionary,
		mname: String, mv: Dictionary, spread_mult: float, first_target: bool,
		is_ally: bool, defer_recoil: bool, my_slot: int, t_slot: int) -> int:
	var fx: Array = mv.get("effects", [])
	var never_miss := fx.has("never_miss")
	var owed_recoil := 0

	# Accuracy check
	var acc := float(mv.get("accuracy", 100))
	if acc > 0.0 and not never_miss:
		var hit_chance := acc / 100.0
		hit_chance *= ACC_STAGE_MULT[int(me["stages"]["acc"]) + 6]
		hit_chance /= ACC_STAGE_MULT[int(foe["stages"]["eva"]) + 6]
		var bp := _held_tag(foe, "bright_powder")
		if bp.size() >= 2:
			hit_chance *= float(bp[1])
		var am := _ab_tag(me, "acc_mult")   # Hustle (phys) / Compound Eyes (all)
		if am.size() >= 3 and (am[1] == "all" or am[1] == str(mv["category"])):
			hit_chance *= float(am[2])
		var we := _ab_tag(foe, "weather_eva")   # Sand Veil in a sandstorm
		if we.size() >= 3 and we[1] == _weather:
			hit_chance *= float(we[2])
		if rng.randf() > hit_chance:
			var miss_ev := {"t": "miss", "side": side, "pokemon": me["name"], "move": mname}
			if my_slot >= 0:
				miss_ev["slot"] = my_slot
				miss_ev["target_slot"] = t_slot
				miss_ev["target"] = foe["name"]
			_emit(miss_ev)
			return 0

	if mv["category"] == "status":
		_apply_effects(side, me, foe_side, foe, fx, true)
		return 0

	# Ability immunity / absorb (Levitate, Flash Fire, Water/Volt Absorb)
	if _ability_absorbs(side, me, foe_side, foe, mv):
		return 0

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
		# weather + abilities (Flash Fire charge, pinch boosts, Thick Fat) + items
		var item_mult := _offense_mult(side, me, mv, true) * _defense_mult(foe_side, foe, mv, true)
		var base: float = (2.0 * float(me["level"]) / 5.0 + 2.0) * float(mv["power"]) * a / maxf(d, 1.0) / 50.0 + 2.0
		var roll := rng.randf_range(0.85, 1.0)
		dmg = int(base * stab * eff * (1.5 if crit else 1.0) * item_mult * roll * spread_mult)
	if eff == 0.0:
		var imm_ev := {"t": "damage", "side": foe_side, "pokemon": foe["name"], "amount": 0,
			"hp_left": foe["hp"], "effectiveness": 0.0, "crit": false, "move": mname}
		if my_slot >= 0:
			imm_ev["slot"] = t_slot
			imm_ev["by_slot"] = my_slot
		if spread_mult < 1.0:
			imm_ev["spread"] = true
		if is_ally:
			imm_ev["ally_hit"] = true
		_emit(imm_ev)
		_hook(foe_side, "It doesn't affect %s..." % foe["name"])
		return 0
	dmg = maxi(1, dmg)
	# Sturdy: survive a one-hit KO from full HP with 1 HP (ability, reusable)
	var sturdied := false
	if dmg >= int(foe["hp"]) and int(foe["hp"]) == int(foe["max_hp"]) \
			and int(foe["max_hp"]) > 1 and _has_ab(foe, "sturdy"):
		dmg = int(foe["hp"]) - 1
		sturdied = true
	# Focus Sash: survive a KO blow from full HP with 1 HP (single use)
	var sashed := false
	if not sturdied and dmg >= int(foe["hp"]) and int(foe["hp"]) == int(foe["max_hp"]) \
			and int(foe["max_hp"]) > 1 and not _held_tag(foe, "sash").is_empty():
		dmg = int(foe["hp"]) - 1
		sashed = true
	var foe_helmet := _held_tag(foe, "rocky_helmet")
	var dmg_ev := {"t": "damage", "side": foe_side, "pokemon": foe["name"],
		"effectiveness": eff, "crit": crit, "move": mname, "by": me["name"], "by_side": side}
	if my_slot >= 0:
		dmg_ev["slot"] = t_slot
		dmg_ev["by_slot"] = my_slot
	if spread_mult < 1.0:
		dmg_ev["spread"] = true
	if is_ally:
		dmg_ev["ally_hit"] = true
	_apply_damage(foe_side, foe, dmg, dmg_ev)
	if sturdied:
		_emit_ability(foe_side, foe, "sturdy")
		_hook(foe_side, "%s's Sturdy keeps it standing at 1 HP!" % foe["name"])
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

	# Contact abilities on the defender (contact ≈ physical moves)
	if mv["category"] == "phys" and int(me["hp"]) > 0 and not is_ally:
		_contact_abilities(side, me, foe_side, foe)

	# Post-damage held-item effects
	if foe_helmet.size() >= 2 and mv["category"] == "phys" and int(me["hp"]) > 0 and not is_ally:
		_emit_held(foe_side, foe, "rocky_helmet")
		var spikes := maxi(1, int(float(me["max_hp"]) * float(foe_helmet[1])))
		_apply_damage(side, me, spikes, {"t": "damage", "side": side, "pokemon": me["name"],
			"effectiveness": 1.0, "crit": false, "move": mname, "item": "rocky_helmet"})
		_hook(side, "%s is gashed by the Rocky Helmet!" % me["name"])
	var bell := _held_tag(me, "shell_bell")
	if bell.size() >= 2 and int(me["hp"]) > 0 and int(me["hp"]) < int(me["max_hp"]):
		_emit_held(side, me, "shell_bell")
		_heal(side, me, maxi(1, int(float(dmg) * float(bell[1]))))
	if first_target and not _held_tag(me, "life_orb").is_empty() and int(me["hp"]) > 0:
		_emit_held(side, me, "life_orb")
		_apply_damage(side, me, maxi(1, int(me["max_hp"] / 10.0)),
			{"t": "damage", "side": side, "pokemon": me["name"], "effectiveness": 1.0,
			"crit": false, "move": mname, "recoil": true, "item": "life_orb"})
	var kr := _held_tag(me, "kings_rock") if (first_target and not is_ally) else PackedStringArray()
	if kr.size() >= 2 and int(foe["hp"]) > 0 and not foe["flinched"] and rng.randf() < float(kr[1]):
		if _has_ab(foe, "immune_flinch"):
			_emit_ability(foe_side, foe, "immune_flinch")
		else:
			foe["flinched"] = true
			_emit_held(side, me, "kings_rock")

	# Secondary effects, recoil, drain
	for f in fx:
		var parts: PackedStringArray = str(f).split(":")
		match parts[0]:
			"recoil":
				if _has_ab(me, "no_recoil"):   # Rock Head
					_emit_ability(side, me, "no_recoil")
				else:
					var rec := maxi(1, int(dmg * float(parts[1])))
					if defer_recoil:
						owed_recoil += rec
					else:
						_apply_damage(side, me, rec, {"t": "damage", "side": side, "pokemon": me["name"],
							"effectiveness": 1.0, "crit": false, "move": mname, "recoil": true})
			"drain":
				var healed := maxi(1, int(dmg * float(parts[1])))
				me["hp"] = mini(me["max_hp"], int(me["hp"]) + healed)
				_emit({"t": "heal", "side": side, "pokemon": me["name"], "amount": healed, "hp_left": me["hp"]})
	if int(foe["hp"]) > 0 and not is_ally:
		_apply_effects(side, me, foe_side, foe, fx, false)
	return owed_recoil


func _fixed_damage(fx: Array, me: Dictionary) -> int:
	for f in fx:
		var parts: PackedStringArray = str(f).split(":")
		if parts[0] == "fixed":
			return int(me["level"]) if parts[1] == "level" else int(parts[1])
	return 0


func _apply_effects(side: int, me: Dictionary, foe_side: int, foe: Dictionary, fx: Array, is_status_move: bool) -> void:
	# Serene Grace doubles the user's secondary-effect chances (damaging moves).
	var chance_mult := 1.0
	if not is_status_move:
		var sg := _ab_tag(me, "effect_chance_mult")
		if sg.size() >= 2:
			chance_mult = float(sg[1])
	# Shield Dust blocks incoming secondary effects of damaging moves.
	var dust: bool = not is_status_move and _has_ab(foe, "no_secondary_effects")
	for f in fx:
		var parts: PackedStringArray = str(f).split(":")
		var tag: String = parts[0]
		match tag:
			"burn", "para", "sleep", "poison", "freeze":
				var chance := (float(parts[1]) if parts.size() > 1 else 1.0) * chance_mult
				if rng.randf() <= chance:
					if dust:
						_emit_ability(foe_side, foe, "no_secondary_effects")
					else:
						_apply_status(foe_side, foe, tag, side, false, me)
			"confuse":
				var chance2 := (float(parts[1]) if parts.size() > 1 else 1.0) * chance_mult
				if rng.randf() <= chance2 and foe["confused_turns"] <= 0:
					if dust:
						_emit_ability(foe_side, foe, "no_secondary_effects")
					elif _has_ab(foe, "immune_confuse"):
						_emit_ability(foe_side, foe, "immune_confuse")
						_hook(foe_side, "%s's Own Tempo keeps its head clear!" % foe["name"])
					else:
						foe["confused_turns"] = rng.randi_range(2, 4)
						_emit({"t": "status_applied", "side": foe_side, "pokemon": foe["name"], "status": "confused"})
						_check_confuse_berry(foe_side, foe)
			"confuse_self":
				if rng.randf() < 0.5 and me["confused_turns"] <= 0 and not _has_ab(me, "immune_confuse"):
					me["confused_turns"] = rng.randi_range(1, 3)
					_emit({"t": "status_applied", "side": side, "pokemon": me["name"], "status": "confused"})
					_check_confuse_berry(side, me)
			"flinch":
				if rng.randf() <= float(parts[1]) * chance_mult:
					if dust:
						_emit_ability(foe_side, foe, "no_secondary_effects")
					elif _has_ab(foe, "immune_flinch"):
						_emit_ability(foe_side, foe, "immune_flinch")
					else:
						foe["flinched"] = true
			"weather":
				# weather:<sun|rain|sand> — Sunny Day / Rain Dance / Sandstorm
				if _weather == parts[1]:
					_hook(side, "But the weather didn't change!")
				else:
					_set_weather(parts[1], 5, "move", side, str(me["name"]))
			"stat":
				# stat:<name>:<delta>[:chance][:self]
				var stat: String = parts[1]
				var delta := int(parts[2])
				var chance3 := (float(parts[3]) if parts.size() > 3 else 1.0)
				var on_self: bool = parts.size() > 4 and parts[4] == "self"
				if not on_self:
					chance3 *= chance_mult
				if rng.randf() <= chance3:
					if not on_self and dust:
						_emit_ability(foe_side, foe, "no_secondary_effects")
						continue
					var target: Dictionary = me if on_self else foe
					var t_side := side if on_self else foe_side
					_change_stage(t_side, target, stat, delta, not on_self)
			"heal":
				var amount := maxi(1, int(me["max_hp"] * float(parts[1])))
				var before := int(me["hp"])
				me["hp"] = mini(me["max_hp"], before + amount)
				if int(me["hp"]) > before:
					_emit({"t": "heal", "side": side, "pokemon": me["name"],
						"amount": int(me["hp"]) - before, "hp_left": me["hp"]})


## source_side: side of the inflicter (for Synchronize), -1 = environmental.
## reflected guards against Synchronize ping-pong.
func _apply_status(side: int, b: Dictionary, status: String, source_side: int = -1, reflected: bool = false, source: Dictionary = {}) -> void:
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
	# ability immunities (Immunity, Limber, Insomnia, Water Veil, Magma Armor)
	var ims := _ab_tag(b, "immune_status")
	if ims.size() >= 2 and ims[1] == status:
		_emit_ability(side, b, "immune_status")
		_hook(side, "%s's %s wards the %s right off!" %
			[b["name"], DataStore.ability_name(str(b["ability"])), status])
		return
	b["status"] = status
	if status == "sleep":
		b["sleep_turns"] = rng.randi_range(1, 3)
	_emit({"t": "status_applied", "side": side, "pokemon": b["name"], "status": status})
	_hook(side, "%s was hit by %s!" % [b["name"], status])
	# Synchronize: pass burn/poison/para straight back to the inflicter.
	if not reflected and source_side >= 0 and status in ["burn", "poison", "para"] \
			and _has_ab(b, "reflect_status"):
		var src: Dictionary = source if not source.is_empty() else active_battler(source_side)
		if int(src["hp"]) > 0:
			_emit_ability(side, b, "reflect_status")
			_hook(side, "%s's Synchronize throws the %s right back!" % [b["name"], status])
			_apply_status(source_side, src, status, side, true)
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
	if mode == "doubles":
		_refill_slots(side)
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
		slots[side][0] = best
		teams[side][best]["flinched"] = false
		_emit({"t": "switch", "side": side, "from": teams[side][prev]["name"],
			"to": teams[side][best]["name"], "forced": true})
		_on_entry(side)


func _end_of_turn(side: int) -> void:
	_end_of_turn_b(side, active_battler(side))


## End-of-turn residuals for one battler (weather chip, leftovers, status
## ticks, berries, end-of-turn abilities). Doubles runs this per slot.
func _end_of_turn_b(side: int, b: Dictionary) -> void:
	if b.is_empty() or int(b["hp"]) <= 0:
		return
	# Weather chip (sandstorm / hail) hits first
	if _weather in ["sand", "hail"] and not _weather_chip_immune(b):
		_hook(side, "%s is battered by the %s!" %
			[b["name"], "sandstorm" if _weather == "sand" else "hail"])
		_apply_damage(side, b, maxi(1, int(float(b["max_hp"]) / 16.0)),
			{"t": "weather_chip", "side": side, "pokemon": b["name"], "kind": _weather})
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
			"status": b["status"], "amount": tick, "hp_left": b["hp"],
			"hp_before": int(b["hp"]) + tick, "max_hp": b["max_hp"]})
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
	# End-of-turn abilities: Speed Boost, Shed Skin, Rain Dish
	var es := _ab_tag(b, "end_turn_stat")
	if es.size() >= 3 and int(b["stages"][es[1]]) < 6:
		_emit_ability(side, b, "end_turn_stat")
		_hook(side, "%s's %s winds it up another gear!" %
			[b["name"], DataStore.ability_name(str(b["ability"]))])
		_change_stage(side, b, es[1], es[2].to_int(), false)
	var ec := _ab_tag(b, "end_turn_cure")
	if ec.size() >= 2 and str(b["status"]) != "" and rng.randf() < float(ec[1]):
		var had: String = str(b["status"])
		b["status"] = ""
		b["sleep_turns"] = 0
		_emit_ability(side, b, "end_turn_cure")
		_emit({"t": "status_applied", "side": side, "pokemon": b["name"], "status": "cured"})
		_hook(side, "%s sheds its skin and shakes off the %s!" % [b["name"], had])
	var wh := _ab_tag(b, "weather_heal")
	if wh.size() >= 3 and wh[1] == _weather and int(b["hp"]) < int(b["max_hp"]):
		_emit_ability(side, b, "weather_heal")
		_heal(side, b, maxi(1, int(float(b["max_hp"]) * float(wh[2]))))
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

# ------------------------------------------------------------------ doubles (2v2)

## Names currently occupying a side's slots (fainted-but-unreplaced included).
func _slot_names(side: int) -> Array:
	var out: Array = []
	for k in slots[side].size():
		var b := _slot_ref(side, k)
		out.append(str(b.get("name", "")) if not b.is_empty() else "")
	return out


## All occupied, standing slots field-wide, fastest first (deterministic ties).
func _field_speed_order() -> Array:
	var entries: Array = []
	for side in 2:
		for k in slots[side].size():
			var b := _slot_ref(side, k)
			if not b.is_empty() and int(b["hp"]) > 0:
				entries.append([side, k, _eff_stat(b, "spe")])
	entries.sort_custom(func(x, y):
		if x[2] != y[2]:
			return x[2] > y[2]
		if x[0] != y[0]:
			return x[0] < y[0]
		return x[1] < y[1])
	return entries


## One full doubles turn. Per side: null (AI both slots) or Array of up to 2
## per-slot actions (null entry = AI that slot). Switches resolve first, then
## trainer items, then moves by priority / Quick Claw / speed across 4 actors.
func _step_turn_doubles(action_a: Variant, action_b: Variant) -> Array:
	turn += 1
	var start := events.size()
	_emit({"t": "turn_start", "turn": turn,
		"hp_a": _team_hp_frac(0), "hp_b": _team_hp_frac(1),
		"active_a": active_battler(0)["name"], "active_b": active_battler(1)["name"],
		"actives_a": _slot_names(0), "actives_b": _slot_names(1),
		"weather": _weather, "weather_turns": _weather_turns})
	var raw := [action_a, action_b]
	var acts := [[null, null], [null, null]]   # [side][slot]
	for side in 2:
		var v: Variant = raw[side]
		if v is Array:
			for k in mini((v as Array).size(), 2):
				acts[side][k] = v[k]
		elif v is Dictionary:
			acts[side][0] = v
	# Fill AI slots; two switches on one side never chase the same bench mon.
	for side in 2:
		var reserved: Array = []
		for k in 2:
			if acts[side][k] is Dictionary and str(acts[side][k].get("type", "")) == "switch":
				reserved.append(int(acts[side][k].get("index", -1)))
		for k in 2:
			if acts[side][k] == null and _slot_alive(side, k):
				acts[side][k] = ai_choose_action_slot(side, k, reserved)
				if str(acts[side][k].get("type", "")) == "switch":
					reserved.append(int(acts[side][k].get("index", -1)))
	# 1) Switches, faster actors first.
	var switchers: Array = []
	for side in 2:
		for k in 2:
			var a: Variant = acts[side][k]
			if a is Dictionary and str(a.get("type", "")) == "switch" and _slot_alive(side, k):
				switchers.append([side, k, _eff_stat(_slot_ref(side, k), "spe")])
	switchers.sort_custom(func(x, y): return x[2] > y[2])
	for s in switchers:
		_do_switch_d(s[0], s[1], int(acts[s[0]][s[1]].get("index", -1)))
	# 2) Trainer items, faster actors first.
	var item_users: Array = []
	for side in 2:
		for k in 2:
			var a2: Variant = acts[side][k]
			if a2 is Dictionary and str(a2.get("type", "")) == "use_item" and _slot_alive(side, k):
				item_users.append([side, k, _eff_stat(_slot_ref(side, k), "spe")])
	item_users.sort_custom(func(x, y): return x[2] > y[2])
	for s in item_users:
		_do_use_item(s[0], acts[s[0]][s[1]])
	# 3) Moves.
	var movers: Array = []
	for side in 2:
		for k in 2:
			var a3: Variant = acts[side][k]
			if not (a3 is Dictionary) or str(a3.get("type", "")) != "move":
				continue
			var me := _slot_ref(side, k)
			if me.is_empty() or int(me["hp"]) <= 0 or me["moves"].is_empty():
				continue
			var spe := _eff_stat(me, "spe")
			if me["status"] == "para":
				spe *= 0.25
			var idx := clampi(int(a3.get("index", 0)), 0, me["moves"].size() - 1)
			var prio := 0
			for fxx in DataStore.move(str(me["moves"][idx])).get("effects", []):
				var parts: PackedStringArray = str(fxx).split(":")
				if parts[0] == "priority":
					prio = parts[1].to_int()
			var claw := 0
			var qc := _held_tag(me, "quick_claw")
			if qc.size() >= 2 and rng.randf() < float(qc[1]):
				claw = 1
				_emit_held(side, me, "quick_claw")
				_hook(side, "%s's Quick Claw glints — it darts in first!" % me["name"])
			movers.append({"side": side, "slot": k, "b": me, "prio": prio,
				"claw": claw, "spe": spe, "tie": rng.randf(), "act": a3})
	movers.sort_custom(func(x, y):
		if x["prio"] != y["prio"]:
			return x["prio"] > y["prio"]
		if x["claw"] != y["claw"]:
			return x["claw"] > y["claw"]
		if x["spe"] != y["spe"]:
			return x["spe"] > y["spe"]
		return x["tie"] > y["tie"])
	for mvr in movers:
		if _over:
			break
		# Actor must still be the mon that chose the action, and still standing.
		if int(mvr["b"]["hp"]) <= 0 or not is_same(_slot_ref(mvr["side"], mvr["slot"]), mvr["b"]):
			continue
		_do_move_d(mvr["side"], mvr["slot"], mvr["act"])
	if not _over:
		for side in 2:
			for k in 2:
				if _over:
					break
				_end_of_turn_b(side, _slot_ref(side, k))
		if not _over:
			_tick_weather()
	_check_end()
	if turn >= MAX_TURNS and not _over:
		_finish(0 if _team_hp_frac(0) >= _team_hp_frac(1) else 1)
	return events.slice(start)


## Doubles switch: bring a bench mon into a specific slot.
func _do_switch_d(side: int, slot: int, to_idx: int) -> void:
	if to_idx < 0 or to_idx >= teams[side].size() or _is_active_index(side, to_idx):
		return
	if int(teams[side][to_idx]["hp"]) <= 0:
		return
	var from := _slot_ref(side, slot)
	if from.is_empty():
		return
	from["stages"] = {"atk": 0, "def": 0, "spa": 0, "spd": 0, "spe": 0, "acc": 0, "eva": 0}
	from["confused_turns"] = 0
	from["flinched"] = false
	from["choice_lock"] = ""
	from["flash_fire"] = false
	if str(from["status"]) != "" and _has_ab(from, "heal_status_on_switch"):
		_emit_ability(side, from, "heal_status_on_switch")
		from["status"] = ""
		from["sleep_turns"] = 0
		_emit({"t": "status_applied", "side": side, "pokemon": from["name"], "status": "cured"})
		_hook(side, "%s's Natural Cure kicks in as it heads to the bench!" % from["name"])
	slots[side][slot] = to_idx
	if slot == 0:
		active[side] = to_idx
	_emit({"t": "switch", "side": side, "slot": slot,
		"from": from["name"], "to": teams[side][to_idx]["name"]})
	_hook(side, "%s is recalled — %s takes the field!" % [from["name"], teams[side][to_idx]["name"]])
	_on_entry_at(side, slot)


## Refill any slot whose occupant has fainted (best matchup vs a standing foe).
func _refill_slots(side: int) -> void:
	for k in slots[side].size():
		if _slot_alive(side, k):
			continue
		var foe: Dictionary = {}
		for fk in slots[1 - side].size():
			if _slot_alive(1 - side, fk):
				foe = _slot_ref(1 - side, fk)
				break
		var best := -1
		var best_v := -INF
		for i in teams[side].size():
			if _is_active_index(side, i) or int(teams[side][i]["hp"]) <= 0:
				continue
			var v := _matchup_value(teams[side][i], foe) if not foe.is_empty() \
				else float(teams[side][i]["hp"])
			if v > best_v:
				best_v = v
				best = i
		if best < 0:
			continue
		var prev := slot_index(side, k)
		slots[side][k] = best
		if k == 0:
			active[side] = best
		teams[side][best]["flinched"] = false
		_emit({"t": "switch", "side": side, "slot": k, "forced": true,
			"from": teams[side][prev]["name"] if prev >= 0 else "",
			"to": teams[side][best]["name"]})
		_on_entry_at(side, k)


## Execute one doubles move action: resolve targets (with redirection), spend
## PP once, then strike every target (0.75x when 2+ actually get hit).
func _do_move_d(side: int, slot: int, act: Dictionary) -> void:
	var me := _slot_ref(side, slot)
	if me.is_empty() or int(me["hp"]) <= 0 or me["moves"].is_empty():
		return
	if not _pre_move_gate(side, me):
		return
	var move_idx := clampi(int(act.get("index", 0)), 0, me["moves"].size() - 1)
	var mname: String = me["moves"][move_idx]
	var mv: Dictionary = DataStore.move(mname)
	if mv.is_empty():
		return
	var foe_side := 1 - side
	var tg := move_targeting(mname)
	# Resolve targets now — fainted picks are redirected to the other foe.
	var targets: Array = []   # [{side, slot, b, ally}]
	match tg:
		"self", "field":
			pass
		"spread_foes", "spread_all":
			for fk in _alive_slots(foe_side):
				targets.append({"side": foe_side, "slot": fk,
					"b": _slot_ref(foe_side, fk), "ally": false})
			if tg == "spread_all" and _slot_alive(side, 1 - slot):
				targets.append({"side": side, "slot": 1 - slot,
					"b": _slot_ref(side, 1 - slot), "ally": true})
		_:
			var want: Variant = act.get("target")
			var tslot: int = int(want.get("slot", -1)) if want is Dictionary else -1
			if tslot < 0 or tslot >= slots[foe_side].size() or not _slot_alive(foe_side, tslot):
				var alive := _alive_slots(foe_side)
				if not alive.is_empty():
					if tslot >= 0:
						_hook(side, "%s's target is gone — the attack is redirected!" % me["name"])
					tslot = alive[0]
				else:
					tslot = -1
			if tslot >= 0:
				targets.append({"side": foe_side, "slot": tslot,
					"b": _slot_ref(foe_side, tslot), "ally": false})
	# Pressure: any standing foe with it taxes the move's PP.
	var pp_foe: Dictionary = me
	for fk in _alive_slots(foe_side):
		var fb := _slot_ref(foe_side, fk)
		if is_same(pp_foe, me) or _has_ab(fb, "pp_pressure"):
			pp_foe = fb
	_spend_pp(me, pp_foe, mname)
	var mu := {"t": "move_used", "side": side, "slot": slot,
		"pokemon": me["name"], "move": mname, "targeting": tg}
	if targets.size() == 1 and not bool(targets[0]["ally"]):
		mu["target"] = targets[0]["b"]["name"]
		mu["target_slot"] = int(targets[0]["slot"])
	elif targets.size() > 1:
		mu["spread"] = true
	_emit(mu)
	if str(me.get("choice_lock", "")) == "" and not _held_tag(me, "choice").is_empty():
		me["choice_lock"] = mname
		_emit_held(side, me, "choice_lock")
	if tg == "self" or tg == "field":
		var probe: Dictionary = me
		var alive2 := _alive_slots(foe_side)
		if not alive2.is_empty():
			probe = _slot_ref(foe_side, alive2[0])
		_strike_target(side, me, foe_side, probe, mname, mv, 1.0, true, false, false, slot, -1)
		return
	if targets.is_empty():
		_emit({"t": "no_target", "side": side, "slot": slot, "pokemon": me["name"], "move": mname})
		_hook(side, "But there was no target...")
		return
	var mult := SPREAD_MULT if targets.size() > 1 else 1.0
	var defer := targets.size() > 1
	var owed := 0
	var first := true
	for t in targets:
		if _over or int(me["hp"]) <= 0:
			break
		var tb: Dictionary = t["b"]
		if int(tb["hp"]) <= 0:
			continue
		owed += _strike_target(side, me, int(t["side"]), tb, mname, mv, mult, first,
			bool(t["ally"]), defer, slot, int(t["slot"]))
		first = false
	if owed > 0 and int(me["hp"]) > 0:
		_apply_damage(side, me, owed, {"t": "damage", "side": side, "slot": slot,
			"pokemon": me["name"], "effectiveness": 1.0, "crit": false,
			"move": mname, "recoil": true})


## Doubles AI for one slot: best (move, target) by expected damage — spread
## moves score both foes minus friendly-fire, single-target moves prefer
## weakened foes (finish the kill). `reserved` = bench indices already claimed
## by the other slot's switch this turn. Uses the bag like the singles AI.
func ai_choose_action_slot(side: int, slot: int, reserved: Array = []) -> Dictionary:
	var me := _slot_ref(side, slot)
	if me.is_empty() or int(me["hp"]) <= 0:
		return {"type": "pass"}
	var item_act := _ai_item_action_slot(side, slot)
	if not item_act.is_empty():
		return item_act
	var foe_side := 1 - side
	var foes := _alive_slots(foe_side)
	var ally := _slot_ref(side, 1 - slot) if slots[side].size() > 1 else {}
	var best := {"type": "move", "index": 0}
	var best_score := -INF
	for i in me["moves"].size():
		var mname: String = me["moves"][i]
		if int(me["pp"].get(mname, 0)) <= 0 or not _move_allowed(me, mname):
			continue
		var tg := move_targeting(mname)
		match tg:
			"self", "field":
				var probe: Dictionary = _slot_ref(foe_side, foes[0]) if not foes.is_empty() else me
				var s := _move_score(me, probe, mname)
				if s > best_score:
					best_score = s
					best = {"type": "move", "index": i}
			"spread_foes", "spread_all":
				var s2 := 0.0
				for fk in foes:
					s2 += _move_score(me, _slot_ref(foe_side, fk), mname) * 0.85
				if tg == "spread_all" and not ally.is_empty() and int(ally["hp"]) > 0:
					var pen := _move_score(me, ally, mname) * 0.9
					var im := _ab_tag(ally, "immune")
					if im.size() >= 2 and im[1] == str(DataStore.move(mname).get("type", "")):
						pen = 0.0   # ally is ability-immune: quake away
					s2 -= pen
				if s2 > best_score:
					best_score = s2
					best = {"type": "move", "index": i}
			_:
				for fk in foes:
					var fb := _slot_ref(foe_side, fk)
					var s3 := _move_score(me, fb, mname)
					# prefer finishing weakened targets
					s3 *= 1.0 + 0.35 * (1.0 - float(fb["hp"]) / maxf(float(fb["max_hp"]), 1.0))
					if s3 > best_score:
						best_score = s3
						best = {"type": "move", "index": i,
							"target": {"side": foe_side, "slot": fk}}
	# Nothing lands (all-immune matchup): try a bench switch instead.
	if best_score <= 0.0:
		for i in teams[side].size():
			if _is_active_index(side, i) or reserved.has(i) or int(teams[side][i]["hp"]) <= 0:
				continue
			return {"type": "switch", "index": i}
	return best


## Slot-aware AI bag decision (same budget/odds as the singles AI).
func _ai_item_action_slot(side: int, slot: int) -> Dictionary:
	if _inventory[side].is_empty() or _items_used[side] >= int(_ai_item_budget[side]):
		return {}
	var me := _slot_ref(side, slot)
	if me.is_empty() or int(me["hp"]) <= 0:
		return {}
	var frac := float(me["hp"]) / float(me["max_hp"])
	if frac < 0.35:
		var heal_id := _ai_best_heal(side, me)
		if heal_id != "" and rng.randf() < 0.75:
			return {"type": "use_item", "item": heal_id, "target": slot_index(side, slot)}
	if str(me["status"]) != "" and frac > 0.45:
		var cure_id := _ai_best_cure(side, me)
		if cure_id != "" and rng.randf() < 0.6:
			return {"type": "use_item", "item": cure_id, "target": slot_index(side, slot)}
	return {}
