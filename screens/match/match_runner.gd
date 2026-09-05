extends RefCounted
## MatchRunner — the persistent state machine behind the player match-day flow.
## Lives in a static var so the match screen can be freely re-instanced by the
## shell (navigation, Continue) without losing a match in progress.
##
## Phases: PRE (lineup + scout) -> LIVE (best-of-3, replayed turn by turn)
##         -> POST (ratings, key events). Results are written back into the
##         GameState fixture the moment the series is decided.
##
## FORMATS: league ties are three games of 6v6 SINGLES. Cup ties are best-of-3
## with GAME 2 played as 2v2 DOUBLES (mode_for_battle) — like a cup replay
## under different rules. (AI-vs-AI instant sims via Season.simulate_fixture
## stay singles-only; the format lives here in the player match flow, since
## season.gd belongs to the competition piece.)
## In doubles the player commands BOTH slots each turn: available_actions_slot /
## submit_slot_action collect one action per living slot (with a target for
## single-target moves), then the whole turn steps at once.

const Commentary := preload("res://screens/match/commentary.gd")

enum Phase { PRE, LIVE, POST }
enum LiveState { REPLAYING, AWAIT_INPUT, BATTLE_OVER }

static var active = null  # MatchRunner or null


# ------------------------------------------------------------------ static API

static func pending_fixture() -> Dictionary:
	## First unplayed player fixture whose date has arrived (or passed).
	for f in GameState.player_fixtures():
		if not f["played"] and str(f["date"]) <= GameState.current_date:
			return f
	return {}


static func begin(fixture: Dictionary):
	var script: GDScript = load("res://screens/match/match_runner.gd")
	var r = script.new()
	r.setup(fixture)
	active = r
	return r


static func clear() -> void:
	active = null


# ------------------------------------------------------------------ state

var fixture: Dictionary
var home_club: Dictionary
var away_club: Dictionary
var player_side: int = 0          # 0 = we are home
var exhibition := false           # demo mode: never writes results/saves
var instant_used := false         # analytics: tie resolved via instant result

var phase: int = Phase.PRE
var live_state: int = LiveState.REPLAYING
var battle_no := 0
var wins := [0, 0]
var battles: Array = []           # [{winner, turns}]
var recorded := false

var starting_six: Array = []      # ordered squad instances (lead first)
var opp_six: Array = []           # opponent battler dicts (display + team source)

var engine: BattleEngine = null
var pending: Array = []           # produced engine events not yet consumed by the view
var slot_actions := {}            # doubles manual mode: slot -> chosen action (this turn)
# Manual combat is the headline flow: full_control defaults ON. The pre-match
# footer (or the Auto-pilot toggle in-game) delegates to the AI coach instead.
var policy := {"aggression": "balanced", "switching": "normal", "full_control": true}
var forced_action = null          # one-shot action override for our side

# Match-day bags (usable items). series_bag = what's left, per side, across the
# whole best-of-3; used_items = what was spent (reported to GameState after).
var series_bag: Array = [{}, {}]
var used_items: Array = [{}, {}]

# View model (what's on screen — trails the engine by `pending`)
var vm := {"teams": [[], []], "active": [0, 0], "actives": [[0], [0]],
	"weather": "", "weather_turns": 0}
var turn_now := 0
var ticker: Array = []            # [{text(bbcode), key, battle, turn}]
var momentum: Array = []          # [{v(-1..1 player-signed), battle, turn}]
var faint_marks: Array = []       # [{idx(into momentum), side}]
var key_events: Array = []        # [{battle, turn, text(bbcode)}]

var _stats := {}                  # "0:Name" -> accumulation dict
var _detail_players := {}         # uid -> Season.fixture_detail-format stats
var _avg_foe_hp := [1.0, 1.0]     # avg opposing max hp, per side
var _cur_active_names := ["", ""]
var _last_damager := ["", ""]     # stats-key of last direct damager of side's active
var _last_v := 0.0
var _rng := RandomNumberGenerator.new()


func setup(f: Dictionary) -> void:
	fixture = f
	home_club = GameState.club(f["home"])
	away_club = GameState.club(f["away"])
	player_side = 0 if GameState.is_player_club(f["home"]) else 1
	_rng.seed = GameState.career_seed + absi(str(f["id"]).hash()) % 999983
	starting_six = default_six(player_club())
	opp_six = Season.pick_team(opponent_club())
	phase = Phase.PRE


func player_club() -> Dictionary:
	return home_club if player_side == 0 else away_club


func opponent_club() -> Dictionary:
	return away_club if player_side == 0 else home_club


func club_for_side(side: int) -> Dictionary:
	return home_club if side == 0 else away_club


func shorts() -> Array:
	return [str(home_club.get("short", "HOM")), str(away_club.get("short", "AWY"))]


static func default_six(club: Dictionary) -> Array:
	var squad: Array = club["squad"].duplicate()
	squad.sort_custom(func(a, b):
		if int(a["level"]) != int(b["level"]):
			return int(a["level"]) > int(b["level"])
		return int(a.get("condition", 100)) > int(b.get("condition", 100)))
	return squad.slice(0, mini(6, squad.size()))


## Battle format for game n of this tie. Cup ties are best-of-3 with the
## middle game played 2v2 DOUBLES; league ties are all singles.
func mode_for_battle(n: int) -> String:
	return "doubles" if str(fixture.get("comp", "")) == "cup" and n == 2 else "singles"


## Is the battle currently on the floor a doubles game?
func doubles_now() -> bool:
	return engine != null and engine.is_doubles()


func series_decided() -> bool:
	return wins[0] >= 2 or wins[1] >= 2


func remaining(side: int) -> int:
	var n := 0
	for b in vm["teams"][side]:
		if not b["fainted"]:
			n += 1
	return n


# ------------------------------------------------------------------ lineup / flow

func confirm_lineup() -> void:
	phase = Phase.LIVE
	wins = [0, 0]
	battles = []
	battle_no = 1
	used_items = [{}, {}]
	for side in 2:
		series_bag[side] = usable_only(GameState.club_inventory(str(club_for_side(side)["id"])))
	_start_battle()


static func usable_only(inv: Dictionary) -> Dictionary:
	## Filter a club store down to battle-usable consumables.
	var out := {}
	for iid in inv:
		if int(inv[iid]) > 0 and str(DataStore.item(str(iid)).get("class", "")) == "usable":
			out[str(iid)] = int(inv[iid])
	return out


func next_battle() -> void:
	if series_decided() or phase != Phase.LIVE:
		return
	battle_no += 1
	_start_battle()


func to_post() -> void:
	phase = Phase.POST
	_finalize_result()


func instant_result() -> void:
	instant_used = true
	confirm_lineup()
	skip_series()


func skip_battle() -> void:
	if engine == null:
		return
	while not engine.is_over():
		_step_engine(true)
	while not pending.is_empty():
		_apply(pending.pop_front())


func skip_series() -> void:
	while true:
		skip_battle()
		if series_decided():
			break
		next_battle()
	to_post()


# ------------------------------------------------------------------ live driving

func _player_team() -> Array:
	var t: Array = []
	for inst in starting_six:
		var b: Dictionary = DataStore.make_battler(inst)
		if not b.is_empty():
			t.append(b)
	return t


func _start_battle() -> void:
	var mine := _player_team()
	var theirs: Array = Season.pick_team(opponent_club())
	var team_h := mine if player_side == 0 else theirs
	var team_a := theirs if player_side == 0 else mine
	var seed_v: int = GameState.career_seed + absi(str(fixture["id"]).hash()) % 1000000 + battle_no * 7919
	engine = BattleEngine.new(team_h, team_a, seed_v, mode_for_battle(battle_no))
	engine.set_inventory(0, series_bag[0])
	engine.set_inventory(1, series_bag[1])
	# Setting "ai_coach_uses_bag" (GameState.settings, default true): when off,
	# the AI coach may never spend YOUR consumables in delegated / instant-sim
	# battles — manual use_item actions from the player still work as normal.
	if not bool(GameState.setting("ai_coach_uses_bag", true)):
		engine.set_ai_item_budget(player_side, 0)
	pending = engine.events.duplicate()
	live_state = LiveState.REPLAYING
	forced_action = null
	slot_actions = {}
	turn_now = 0
	_last_damager = ["", ""]
	_cur_active_names = ["", ""]
	# Fresh view model snapshot (independent of the engine's mutable state).
	for side in 2:
		var arr: Array = []
		for b in engine.team_state(side):
			arr.append({
				"name": b["name"], "species": b.get("species", b["name"]),
				"level": int(b["level"]), "types": b["types"],
				"max_hp": int(b["max_hp"]), "hp": int(b["max_hp"]),
				"status": "", "confused": false, "fainted": false,
				"stages": {"atk": 0, "def": 0, "spa": 0, "spd": 0, "spe": 0, "acc": 0, "eva": 0},
				"moves": b["moves"],
				"pp": (b["pp"].duplicate() if b.has("pp") else {}),
				"item": str(b.get("item", "")), "item_consumed": false,
			})
		vm["teams"][side] = arr
		vm["active"][side] = 0
		if engine.is_doubles():
			vm["actives"][side] = [0, 1 if arr.size() > 1 else -1]
		else:
			vm["actives"][side] = [0]
	vm["weather"] = ""
	vm["weather_turns"] = 0
	# Ratings bookkeeping
	for side in 2:
		var total := 0.0
		for b in vm["teams"][1 - side]:
			total += float(b["max_hp"])
		_avg_foe_hp[side] = maxf(total / maxf(vm["teams"][1 - side].size(), 1.0), 1.0)
		for b in vm["teams"][side]:
			var k := _key(side, b["name"])
			if not _stats.has(k):
				_stats[k] = {"name": b["name"], "side": side, "level": b["level"],
					"max_hp": b["max_hp"], "dealt": 0, "taken": 0, "kos": 0,
					"fainted": 0, "status": 0, "apps": {}}
	_last_v = 0.0


func buffered() -> int:
	return pending.size()


## Pull the next event for the view (already applied to the view model).
## Returns {} when the view must wait (player input or battle over).
func consume_next() -> Dictionary:
	if pending.is_empty():
		_ensure_events()
	if pending.is_empty():
		return {}
	var e: Dictionary = pending.pop_front()
	_apply(e)
	return e


func awaiting_input() -> bool:
	return live_state == LiveState.AWAIT_INPUT and pending.is_empty()


## Legal actions for our side, enriched with previews (full-control mode).
func available_actions() -> Array:
	if engine == null or engine.is_over():
		return []
	var out: Array = []
	for a in engine.legal_actions(player_side):
		var d: Dictionary = a.duplicate()
		if a["type"] == "move":
			var me: Dictionary = engine.active_battler(player_side)
			var mname: String = me["moves"][int(a["index"])]
			d["move"] = mname
			d["pp"] = int(me["pp"].get(mname, 0))
			d["preview"] = engine.preview_move(player_side, int(a["index"]))
		elif a["type"] == "use_item":
			var it: Dictionary = DataStore.item(str(a["item"]))
			d["name"] = str(it.get("name", a["item"]))
			d["desc"] = str(it.get("desc", ""))
			d["count"] = int(engine.inventory(player_side).get(str(a["item"]), 0))
			var tb: Dictionary = engine.team_state(player_side)[int(a["target"])]
			d["target_name"] = str(tb["name"])
			d["target_hp"] = int(tb["hp"])
			d["target_max"] = int(tb["max_hp"])
			d["target_status"] = str(tb["status"])
		else:
			var b: Dictionary = engine.team_state(player_side)[int(a["index"])]
			d["pokemon"] = b["name"]
			d["hp"] = int(b["hp"])
			d["max_hp"] = int(b["max_hp"])
			d["types"] = b["types"]
		out.append(d)
	return out


## Moves our active battler cannot pick right now because a Choice item locked
## it into one move ([] when free). The UI shows these disabled instead of
## hiding them — vanishing buttons read as a bug (user report 2026-09-05).
## Each entry: {move, pp, item_name, locked_move}.
func choice_locked_moves() -> Array:
	if engine == null or engine.is_over():
		return []
	var me: Dictionary = engine.active_battler(player_side)
	var lock := str(me.get("choice_lock", ""))
	if lock == "" or int(me["pp"].get(lock, 0)) <= 0:
		return []
	var out: Array = []
	for mname in me["moves"]:
		if str(mname) != lock and int(me["pp"].get(mname, 0)) > 0:
			out.append({"move": str(mname), "pp": int(me["pp"].get(mname, 0)),
				"item_name": DataStore.item_name(str(me.get("item", ""))),
				"locked_move": lock})
	return out


# ---------------------------------------------------------- doubles manual input

## Our slots that still have a standing battler (doubles: 0 and/or 1).
func our_alive_slots() -> Array:
	if engine == null:
		return []
	var out: Array = []
	for k in engine.slot_count():
		if not engine.slot_battler(player_side, k).is_empty() \
				and int(engine.slot_battler(player_side, k).get("hp", 0)) > 0:
			out.append(k)
	return out


## Alive slots that have not been given an order yet this turn.
func slots_awaiting() -> Array:
	return our_alive_slots().filter(func(k): return not slot_actions.has(int(k)))


## Legal actions for one of our doubles slots, enriched with previews.
## Single-target move entries carry "targets": [{side, slot, name, preview}].
func available_actions_slot(slot: int) -> Array:
	if engine == null or engine.is_over():
		return []
	if not engine.is_doubles():
		return available_actions()
	var out: Array = []
	var me: Dictionary = engine.slot_battler(player_side, slot)
	if me.is_empty():
		return []
	for a in engine.legal_actions_slot(player_side, slot):
		var d: Dictionary = a.duplicate(true)
		if a["type"] == "move":
			var mname := str(a.get("move", me["moves"][int(a["index"])]))
			d["move"] = mname
			d["pp"] = int(me["pp"].get(mname, 0))
			if str(d.get("targeting", "")) == "single":
				for t in d.get("targets", []):
					t["preview"] = engine.preview_move_at(player_side, slot,
						int(a["index"]), int(t["side"]), int(t["slot"]))
			else:
				# spread/self preview vs the first standing foe
				var probe := -1
				for fk in engine.slot_count():
					var fb: Dictionary = engine.slot_battler(1 - player_side, fk)
					if not fb.is_empty() and int(fb.get("hp", 0)) > 0:
						probe = fk
						break
				if probe >= 0:
					d["preview"] = engine.preview_move_at(player_side, slot,
						int(a["index"]), 1 - player_side, probe)
		elif a["type"] == "use_item":
			var it: Dictionary = DataStore.item(str(a["item"]))
			d["name"] = str(it.get("name", a["item"]))
			d["desc"] = str(it.get("desc", ""))
			d["count"] = int(engine.inventory(player_side).get(str(a["item"]), 0))
			var tb: Dictionary = engine.team_state(player_side)[int(a["target"])]
			d["target_name"] = str(tb["name"])
			d["target_hp"] = int(tb["hp"])
			d["target_max"] = int(tb["max_hp"])
			d["target_status"] = str(tb["status"])
		else:
			var b: Dictionary = engine.team_state(player_side)[int(a["index"])]
			d["pokemon"] = b["name"]
			d["hp"] = int(b["hp"])
			d["max_hp"] = int(b["max_hp"])
			d["types"] = b["types"]
		out.append(d)
	return out


## Record one slot's order. When every living slot has one, the doubles turn
## executes as a whole (a second switch aimed at an already-claimed bench mon
## is rejected by the engine and that slot's AI covers it).
func submit_slot_action(slot: int, action: Dictionary) -> void:
	if engine == null or engine.is_over() or not engine.is_doubles():
		return
	slot_actions[int(slot)] = action
	if not slots_awaiting().is_empty():
		return
	var arr: Array = [null, null]
	for k in slot_actions:
		if int(k) >= 0 and int(k) < 2:
			arr[int(k)] = slot_actions[k]
	slot_actions = {}
	live_state = LiveState.REPLAYING
	_step_with(arr)


## Undo a pending doubles order (the two-step UI's "back" affordance).
func retract_slot_action(slot: int) -> void:
	slot_actions.erase(int(slot))


## Remaining match-day bag for our side (live view of the series bag).
func our_bag() -> Dictionary:
	return series_bag[player_side]


func items_spent(side: int) -> int:
	var n := 0
	for iid in used_items[side]:
		n += int(used_items[side][iid])
	return n


func submit_action(action: Dictionary) -> void:
	if engine == null or engine.is_over():
		return
	if engine.is_doubles():
		# route through the per-slot collector (fills the first waiting slot)
		var waiting: Array = slots_awaiting()
		submit_slot_action(int(waiting[0]) if not waiting.is_empty() else 0, action)
		return
	live_state = LiveState.REPLAYING
	_step_with(action)


func force_switch(team_index: int) -> void:
	forced_action = {"type": "switch", "index": team_index}
	if live_state == LiveState.AWAIT_INPUT:
		submit_action(forced_action)
		forced_action = null


func add_note(text: String) -> void:
	_push_lines([{"text": "[color=#9a8dff]Touchline: %s[/color]" % text, "key": false}])


func set_policy(key: String, value) -> void:
	policy[key] = value
	if key == "full_control" and value == false and live_state == LiveState.AWAIT_INPUT:
		live_state = LiveState.REPLAYING


func _ensure_events(min_buffer: int = 4) -> void:
	while pending.size() < min_buffer and engine != null and not engine.is_over() \
			and live_state == LiveState.REPLAYING:
		if not _step_engine(false):
			break


## Advance the engine one turn using touchline policy. Returns false when
## waiting for player input instead. `ignore_control` bypasses full control
## (used by skip).
func _step_engine(ignore_control: bool) -> bool:
	var a = null
	if forced_action != null:
		a = forced_action
		forced_action = null
	elif policy["full_control"] and not ignore_control:
		live_state = LiveState.AWAIT_INPUT
		return false
	elif not engine.is_doubles() \
			and (policy["aggression"] != "balanced" or policy["switching"] != "normal"):
		a = engine.choose_action_policy(player_side,
			{"aggression": policy["aggression"], "switching": policy["switching"]})
	_step_with(a)
	return true


func _step_with(our_action) -> void:
	if engine.is_doubles() and our_action is Dictionary:
		our_action = [our_action, null]   # single order: AI covers the other slot
	var evs: Array
	if player_side == 0:
		evs = engine.step_turn(our_action, null)
	else:
		evs = engine.step_turn(null, our_action)
	pending.append_array(evs)


# ------------------------------------------------------------------ event application

func _key(side: int, name: String) -> String:
	return "%d:%s" % [side, name]


func _find_vm(side: int, name: String) -> Dictionary:
	for b in vm["teams"][side]:
		if b["name"] == name:
			return b
	return {}


func _ctx() -> Dictionary:
	return {"player_side": player_side, "short": shorts(),
		"remaining": [remaining(0), remaining(1)],
		"battle_no": battle_no, "wins": wins, "turn": turn_now}


func _apply_synthetic(e: Dictionary) -> void:
	_push_lines(Commentary.lines_for(e, _ctx(), _rng))


func _push_lines(lines: Array) -> void:
	for l in lines:
		var entry := {"text": l["text"], "key": bool(l["key"]), "battle": battle_no, "turn": turn_now}
		ticker.append(entry)
		if entry["key"]:
			key_events.append(entry)
	if ticker.size() > 700:
		ticker = ticker.slice(ticker.size() - 700)


func _apply(e: Dictionary) -> void:
	var t := str(e.get("t", ""))
	match t:
		"move_used":
			var bm := _find_vm(int(e.get("side", 0)), str(e.get("pokemon", "")))
			var mv := str(e.get("move", ""))
			if not bm.is_empty() and bm["pp"].has(mv):
				bm["pp"][mv] = maxi(0, int(bm["pp"][mv]) - 1)
		"turn_start":
			turn_now = int(e["turn"])
			if e.has("weather"):
				vm["weather"] = str(e["weather"])
				vm["weather_turns"] = int(e.get("weather_turns", 0))
			var hp_p := float(e.get("hp_a", 0.0)) if player_side == 0 else float(e.get("hp_b", 0.0))
			var hp_o := float(e.get("hp_b", 0.0)) if player_side == 0 else float(e.get("hp_a", 0.0))
			var v := hp_p - hp_o
			momentum.append({"v": v, "battle": battle_no, "turn": turn_now})
			if signf(v) != signf(_last_v) and absf(v) >= 0.06 and absf(_last_v) >= 0.02:
				var toward := player_side if v > 0.0 else 1 - player_side
				_push_lines([Commentary.swing_line(shorts()[toward], toward == player_side, _rng)])
			_last_v = v
		"switch":
			var side := int(e["side"])
			var to_name := str(e["to"])
			var slot := int(e.get("slot", 0))
			for i in vm["teams"][side].size():
				var b: Dictionary = vm["teams"][side][i]
				if b["name"] == to_name and not b["fainted"]:
					if slot < vm["actives"][side].size():
						vm["actives"][side][slot] = i
					if slot == 0:
						vm["active"][side] = i
					break
			_cur_active_names[side] = to_name
			var k := _key(side, to_name)
			if _stats.has(k):
				_stats[k]["apps"][battle_no] = true
			# switching resets volatile state on the one leaving
			if e.has("from"):
				var fb := _find_vm(side, str(e["from"]))
				if not fb.is_empty():
					fb["stages"] = {"atk": 0, "def": 0, "spa": 0, "spd": 0, "spe": 0, "acc": 0, "eva": 0}
					fb["confused"] = false
		"damage":
			var side2 := int(e["side"])
			var b2 := _find_vm(side2, str(e["pokemon"]))
			var amount := int(e.get("amount", 0))
			if not b2.is_empty():
				amount = mini(amount, int(e.get("hp_before", b2["hp"])))
				b2["hp"] = int(e.get("hp_left", b2["hp"]))
				if b2["hp"] <= 0:
					b2["fainted"] = true
			if e.get("recoil", false):
				_bump(_key(side2, str(e["pokemon"])), "taken", amount)
			elif float(e.get("effectiveness", 1.0)) > 0.0 and amount > 0:
				_bump(_key(side2, str(e["pokemon"])), "taken", amount)
				var atk_key := _key(int(e.get("by_side", 1 - side2)), str(e.get("by", "")))
				_bump(atk_key, "dealt", amount)
				_last_damager[side2] = atk_key
		"weather_start":
			vm["weather"] = str(e.get("kind", ""))
			vm["weather_turns"] = int(e.get("turns", 0))
		"weather_end":
			vm["weather"] = ""
			vm["weather_turns"] = 0
		"weather_chip", "status_tick", "confused_hit":
			var side3 := int(e["side"])
			var b3 := _find_vm(side3, str(e["pokemon"]))
			if not b3.is_empty():
				b3["hp"] = int(e.get("hp_left", maxi(0, b3["hp"] - int(e.get("amount", 0)))))
				if b3["hp"] <= 0:
					b3["fainted"] = true
			_bump(_key(side3, str(e["pokemon"])), "taken", int(e.get("amount", 0)))
		"heal":
			var b4 := _find_vm(int(e["side"]), str(e["pokemon"]))
			if not b4.is_empty():
				b4["hp"] = int(e.get("hp_left", b4["hp"]))
				if b4["hp"] > 0 and b4["fainted"]:
					b4["fainted"] = false  # revive
					b4["status"] = ""
					b4["confused"] = false
		"item_used":
			var side_i := int(e["side"])
			var iid := str(e["item"])
			series_bag[side_i][iid] = maxi(0, int(series_bag[side_i].get(iid, 0)) - 1)
			if int(series_bag[side_i][iid]) <= 0:
				series_bag[side_i].erase(iid)
			used_items[side_i][iid] = int(used_items[side_i].get(iid, 0)) + 1
		"held_item":
			if bool(e.get("consumed", false)):
				var bh := _find_vm(int(e["side"]), str(e["pokemon"]))
				if not bh.is_empty():
					bh["item_consumed"] = true
		"faint":
			var side5 := int(e["side"])
			var b5 := _find_vm(side5, str(e["pokemon"]))
			if not b5.is_empty():
				b5["hp"] = 0
				b5["fainted"] = true
			_bump(_key(side5, str(e["pokemon"])), "fainted", 1)
			if _last_damager[side5] != "":
				_bump(_last_damager[side5], "kos", 1)
			if not momentum.is_empty():
				faint_marks.append({"idx": momentum.size() - 1, "side": side5})
		"status_applied":
			var side6 := int(e["side"])
			var b6 := _find_vm(side6, str(e["pokemon"]))
			var st := str(e.get("status", ""))
			if not b6.is_empty():
				match st:
					"burn", "para", "sleep", "poison", "freeze":
						b6["status"] = st
					"confused":
						b6["confused"] = true
					"woke", "thawed":
						b6["status"] = ""
					"cured":
						b6["status"] = ""
						b6["confused"] = false
			if st in ["burn", "para", "sleep", "poison", "freeze", "confused"]:
				var inflictor := _key(1 - side6, _cur_active_names[1 - side6])
				_bump(inflictor, "status", 1)
		"stat_change":
			var b7 := _find_vm(int(e["side"]), str(e["pokemon"]))
			if not b7.is_empty():
				b7["stages"][str(e["stat"])] = int(e.get("stage", 0))
		"battle_end":
			var w := int(e["winner"])
			wins[w] += 1
			battles.append({"winner": w, "turns": int(e.get("turns", turn_now))})
			# Tally the REAL battle into fixture-detail format so Competition's
			# match report / season stats show what actually happened here
			# instead of a neutral replay (see Season.fixture_detail).
			if engine != null:
				Season._tally_battle(engine.events,
					[engine.team_state(0), engine.team_state(1)], w, _detail_players)
			live_state = LiveState.BATTLE_OVER
			if series_decided():
				_finalize_result()
	# Commentary after state update so remaining-counts etc. are fresh.
	_push_lines(Commentary.lines_for(e, _ctx(), _rng))


func _bump(key: String, field: String, amount: int) -> void:
	if _stats.has(key):
		_stats[key][field] += amount


# ------------------------------------------------------------------ ratings / result

func rating_rows(side: int) -> Array:
	# Numbers come from the SAME per-battle tally that gets recorded on the
	# fixture (Season._tally_battle -> fixture["detail"]), so the post-match
	# screen, the competition's match report and the season stats all agree
	# exactly. Falls back to the live _stats tally if no battle has finished.
	var rows: Array = []
	for uid in _detail_players:
		var s: Dictionary = _detail_players[uid]
		if int(s["side"]) != side or int(s.get("battles", 0)) == 0:
			continue
		rows.append({
			"uid": str(uid),
			"name": s["name"], "level": s["level"], "dealt": int(s["dmg"]),
			"taken": int(s["taken"]), "kos": int(s["kos"]),
			"fainted": int(s.get("faints", 0)), "status": 0,
			"apps": int(s["battles"]),
			"rating": snappedf(float(s.get("rating_sum", 6.0)) / maxf(1.0, float(s["battles"])), 0.1),
		})
	if rows.is_empty():
		for k in _stats:
			var s: Dictionary = _stats[k]
			if int(s["side"]) != side or s["apps"].is_empty():
				continue
			rows.append({
				"name": s["name"], "level": s["level"], "dealt": s["dealt"], "taken": s["taken"],
				"kos": s["kos"], "fainted": s["fainted"], "status": s["status"],
				"apps": s["apps"].size(), "rating": _rating(s),
			})
	rows.sort_custom(func(a, b): return a["rating"] > b["rating"])
	return rows


func _rating(s: Dictionary) -> float:
	var apps := maxi(1, s["apps"].size())
	var foe_hp: float = _avg_foe_hp[int(s["side"])]
	var r := 6.0
	r += float(s["dealt"]) / (foe_hp * apps) * 1.0
	r += float(s["kos"]) * 0.45
	r += float(s["status"]) * 0.25
	r -= float(s["taken"]) / maxf(float(s["max_hp"]) * apps, 1.0) * 0.9
	r -= float(s["fainted"]) * 0.4
	return snappedf(clampf(r, 4.8, 9.8), 0.1)


func man_of_the_match() -> Dictionary:
	var best := {}
	for side in 2:
		for row in rating_rows(side):
			if best.is_empty() or row["rating"] > best["rating"]:
				best = row.duplicate()
				best["side"] = side
	return best


func player_won() -> bool:
	return wins[player_side] > wins[1 - player_side]


func _finalize_result() -> void:
	if recorded or exhibition:
		return
	recorded = true
	fixture["played"] = true
	fixture["score_home"] = wins[0]
	fixture["score_away"] = wins[1]
	fixture["detail"] = {"score_home": wins[0], "score_away": wins[1],
		"battles": battles.duplicate(true), "players": _detail_players}
	GameState.apply_match_progression(fixture)   # match XP -> level-ups
	for side in 2:
		GameState.consume_club_items(str(club_for_side(side)["id"]), used_items[side])
	GameState._table_dirty = true
	GameState.fixture_played.emit(fixture)
	GameState.table_updated.emit()
	var us: int = wins[player_side]
	var them: int = wins[1 - player_side]
	var mode := "instant" if instant_used else \
		("manual" if bool(policy["full_control"]) else "coach")
	Analytics.match_played(mode, str(fixture.get("comp", "")), us, them)
	var opp: String = opponent_club()["name"]
	var verdict := "won" if us > them else "lost"
	var motm := man_of_the_match()
	var motm_txt := ""
	if not motm.is_empty():
		motm_txt = tr(" %s was the standout performer (%.1f).") % [motm["name"], motm["rating"]]
	var item_txt := ""
	if items_spent(player_side) > 0:
		var parts: Array = []
		for iid in used_items[player_side]:
			parts.append("%dx %s" % [int(used_items[player_side][iid]), tr(DataStore.item_name(str(iid)))])
		item_txt = tr(" Bag used: %s.") % ", ".join(parts)
	GameState.add_inbox_message(GameState.current_date,
		tr("Match report: %d-%d vs %s") % [us, them, opp],
		tr("We won the %s tie against %s, %d-%d in battles.%s%s" if us > them
			else "We lost the %s tie against %s, %d-%d in battles.%s%s") %
		[tr(str(fixture["comp"])), opp, us, them, motm_txt, item_txt])
	GameState.save_game()
