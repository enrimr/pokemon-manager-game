extends RefCounted
## TacticsBrain — turns the published battle plan (lineup order, per-slot roles
## and the six team instructions) into concrete BattleEngine actions.
##
## Owned by res://screens/tactics/. Uses ONLY the engine's public API
## (legal_actions / preview_move / active_battler / team_state / step_turn)
## plus DataStore, so it never reaches into other pieces' internals.
##
## Every instruction is load-bearing:
##   aggression        0..4  — shifts damage-vs-status weighting, accuracy
##                             tolerance and how willing we are to pivot out.
##   switch_threshold  %HP   — active battler looks for an exit below this line.
##   status_priority   0..2  — multiplier on sleep/para/toxic/setup value.
##   protect_lead      bool  — pulls the slot-1 Lead out of losing matchups.
##   preserve_last     bool  — refuses to feed the final battler; the last one
##                             standing plays for survival (heal/accuracy).
##   revenge_switch    bool  — after losing a battler, brings in the designated
##                             Revenge Killer when it outspeeds and outdamages.
##
## Fully deterministic (no RNG): same engine state + same plan = same action,
## which keeps instant-sim results reproducible from the fixture seed.

const Logic := preload("res://screens/tactics/tactics_logic.gd")

const AGGR_STATUS_MULT := [1.45, 1.2, 1.0, 0.7, 0.45]   # status appetite by aggression
const AGGR_DAMAGE_MULT := [0.9, 0.95, 1.0, 1.08, 1.15]  # damage appetite by aggression
const AGGR_ACC_WEIGHT := [1.0, 0.85, 0.7, 0.5, 0.35]    # how much a miss chance scares us
const STATUS_PRIO_MULT := [0.5, 1.0, 1.65]


## Choose our action for this turn. `tac` is the published plan
## ({lineup, roles, instructions}); `ctx` may carry {"just_fainted": bool}.
static func choose(eng, side: int, tac: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var instr: Dictionary = tac.get("instructions", {})
	var ag := clampi(int(instr.get("aggression", 2)), 0, 4)
	var threshold := clampi(int(instr.get("switch_threshold", 25)), 0, 60)
	var me: Dictionary = eng.active_battler(side)
	var foe: Dictionary = eng.active_battler(1 - side)
	var my_hp := float(me.get("hp", 1)) / maxf(float(me.get("max_hp", 1)), 1.0)

	var acts: Array = eng.legal_actions(side)
	var switch_acts: Array = acts.filter(func(a): return a["type"] == "switch")
	var last_stand := switch_acts.is_empty() and bool(instr.get("preserve_last", false))

	# ---------------- best move on the field
	var best_move := {"type": "move", "index": 0}
	var best_move_v := -1.0
	var kill_available := false
	var foe_hp_frac := float(foe.get("hp", 1)) / maxf(float(foe.get("max_hp", 1)), 1.0)
	for a in acts:
		if a["type"] != "move":
			continue
		var idx := int(a["index"])
		var v := _move_value(eng, side, idx, me, foe, my_hp, ag, instr, tac, last_stand)
		if v > best_move_v:
			best_move_v = v
			best_move = a
		# reliable KO on the field? (accuracy >= 70% so we don't chase longshots)
		var moves: Array = me.get("moves", [])
		if idx < moves.size():
			var mv: Dictionary = DataStore.move(str(moves[idx]))
			if not mv.is_empty() and str(mv.get("category", "")) != "status" \
					and (int(mv.get("accuracy", 100)) <= 0 or int(mv.get("accuracy", 100)) >= 70):
				var pv: Dictionary = eng.preview_move(side, idx)
				if not pv.is_empty() and float(pv.get("est_frac", 0.0)) >= foe_hp_frac:
					kill_available = true

	# A kill in hand beats any pivot: never walk away from a KO.
	if switch_acts.is_empty() or kill_available:
		return best_move
	# Voluntary switching burns a free turn — never do it twice in a row.
	if bool(ctx.get("switched_last", false)):
		return best_move

	# ---------------- switch consideration
	var team: Array = eng.team_state(side)
	var me_on_foe := _incoming(me, foe)
	var foe_on_me := _incoming(foe, me)
	var lead_uid: String = str(tac.get("lineup", [""])[0]) if not tac.get("lineup", []).is_empty() else ""

	# (1) Revenge switching: we just lost a battler — if the designated Revenge
	# Killer (or fastest bench sweeper) beats this threat, bring it in now.
	# Only worth the free turn if it is healthy and clearly outdamages the
	# auto-sent replacement.
	if bool(instr.get("revenge_switch", true)) and bool(ctx.get("just_fainted", false)):
		var rev := _revenge_candidate(team, switch_acts, foe, tac)
		if rev >= 0 and str(team[rev].get("uid", "")) != str(me.get("uid", "x")):
			var cand: Dictionary = team[rev]
			var cand_hp := float(cand.get("hp", 0)) / maxf(float(cand.get("max_hp", 1)), 1.0)
			if cand_hp >= 0.6 and _speed(cand) > _speed(foe) \
					and _incoming(cand, foe) > me_on_foe * 1.25 \
					and _incoming(foe, cand) < cand_hp * 0.6:
				return {"type": "switch", "index": rev}

	var want_switch := false
	var retreat_only := false
	# (2) HP threshold retreat — the plan's own line in the sand.
	if my_hp * 100.0 < float(threshold):
		want_switch = true
		retreat_only = true
	# (3) Protect the lead: never sacrifice the opener to a losing matchup
	# (clearly losing: they hit much harder than we do).
	if bool(instr.get("protect_lead", true)) and str(me.get("uid", "")) == lead_uid \
			and ag < 4 and foe_on_me > 0.3 and me_on_foe < 0.18 \
			and foe_on_me > me_on_foe * 1.6:
		want_switch = true
		retreat_only = false
	# (4) Hopeless matchup (we can't dent them) — cautious plans pivot out.
	if me_on_foe < 0.06 and foe_on_me > 0.12 and ag <= 2:
		want_switch = true
		retreat_only = false
	# (5) Bad trade: they carve us up far faster than we hurt them. Everyone
	# but a hyper-aggressive plan gets out of a 2:1 losing exchange.
	if ag <= 3 and foe_on_me > 2.0 * maxf(me_on_foe, 0.02) and foe_on_me > 0.2:
		want_switch = true
		retreat_only = false

	if not want_switch:
		return best_move

	# Pick the best switch-in by matchup differential (+ role flavour).
	# Candidates must be able to take the entry hit and stay: switching into
	# a battler that immediately wants out just donates free turns.
	var best_idx := -1
	var best_v := me_on_foe - foe_on_me * 0.9 + 0.04   # must beat staying in
	if my_hp * 100.0 < float(threshold):
		best_v = minf(best_v, -0.5)                     # retreating: any real upgrade will do
	for a in switch_acts:
		var i := int(a["index"])
		var cand: Dictionary = team[i]
		var cand_hp := float(cand.get("hp", 0)) / maxf(float(cand.get("max_hp", 1)), 1.0)
		var entry_hit := _incoming(foe, cand)
		if cand_hp < 0.5 or entry_hit >= cand_hp * 0.55:
			continue    # entry hit would cripple it — retreat is worse than trading
		# Retreat economics: a pure HP-threshold retreat must not spend more
		# of the switch-in's HP (the free entry hit) than the active battler
		# even has left — otherwise trading out is a net loss.
		if retreat_only and entry_hit * float(cand.get("max_hp", 1)) \
				> float(me.get("hp", 0)) * 1.1:
			continue
		var v := _incoming(cand, foe) - entry_hit * 0.9
		v += cand_hp * 0.05
		var role: String = str(tac.get("roles", {}).get(str(cand.get("uid", "")), ""))
		if role == "pivot":
			v += 0.06
		elif role == "wall":
			v += 0.03
		# Preserve the last battler: don't feed the final backup while the
		# active can still fight — it is our insurance for the turn cap.
		if bool(instr.get("preserve_last", false)) and switch_acts.size() == 1 \
				and my_hp > 0.2 and entry_hit > _incoming(cand, foe):
			continue
		if v > best_v:
			best_v = v
			best_idx = i
	if best_idx >= 0:
		return {"type": "switch", "index": best_idx}
	return best_move


# ------------------------------------------------------------------ move value

static func _move_value(eng, side: int, idx: int, me: Dictionary, foe: Dictionary,
		my_hp: float, ag: int, instr: Dictionary, tac: Dictionary, last_stand: bool) -> float:
	var moves: Array = me.get("moves", [])
	if idx < 0 or idx >= moves.size():
		return 0.0
	var mv: Dictionary = DataStore.move(str(moves[idx]))
	if mv.is_empty():
		return 0.0
	var role: String = str(tac.get("roles", {}).get(str(me.get("uid", "")), ""))
	var fx: Array = mv.get("effects", [])
	var acc := int(mv.get("accuracy", 100))
	var acc_f := 1.0 if acc <= 0 else float(acc) / 100.0

	if str(mv.get("category", "phys")) != "status":
		var pv: Dictionary = eng.preview_move(side, idx)
		if pv.is_empty():
			return 0.0
		var est := float(pv.get("est_frac", 0.0))
		var foe_hp := float(foe.get("hp", 1)) / maxf(float(foe.get("max_hp", 1)), 1.0)
		var kills := est >= foe_hp and est > 0.0
		var s := minf(est, foe_hp)
		if kills:
			s += 0.35
			if _has(fx, "priority"):
				s += 0.15    # revenge-killer bread and butter: priority finisher
		# accuracy tolerance scales with aggression (cautious = trust the 100% move)
		var acc_w: float = AGGR_ACC_WEIGHT[ag]
		if last_stand:
			acc_w = 1.0
		s *= lerpf(1.0, acc_f, acc_w)
		if _has(fx, "recoil"):
			s *= 0.45 if last_stand else (0.8 if my_hp < 0.35 else 0.95)
		if _has(fx, "drain") and my_hp < 0.55:
			s += 0.08
		return s * AGGR_DAMAGE_MULT[ag]

	# ---- status move
	var v := 0.0
	var foe_status := str(foe.get("status", ""))
	var foe_confused := int(foe.get("confused_turns", 0)) > 0
	for e in fx:
		var parts: Array = str(e).split(":")
		match parts[0]:
			"sleep":
				if foe_status == "":
					v = maxf(v, 0.62)
			"para":
				if foe_status == "":
					v = maxf(v, 0.4)
			"poison", "burn":
				if foe_status == "":
					v = maxf(v, 0.34 if role != "wall" else 0.42)
			"confuse":
				if not foe_confused:
					v = maxf(v, 0.28)
			"heal":
				v = maxf(v, (1.0 - my_hp) * (1.1 if last_stand else 0.85))
			"stat":
				if parts.size() >= 3:
					var self_buff: bool = parts.size() >= 5 and parts[4] == "self"
					var stages := int(parts[2])
					if self_buff and stages > 0:
						if parts[1] in ["atk", "spa", "spe"]:
							# set-up: only worth it while healthy and not under the gun
							if my_hp > 0.6 and _incoming(foe, me) < 0.4 \
									and int(me.get("stages", {}).get(parts[1], 0)) < 2:
								v = maxf(v, 0.5 if role == "sweeper" else 0.36)
						else:
							if my_hp > 0.5 and int(me.get("stages", {}).get(parts[1], 0)) < 2:
								v = maxf(v, 0.26)
					elif not self_buff and stages < 0:
						v = maxf(v, 0.2)
	v *= acc_f
	v *= AGGR_STATUS_MULT[ag] * STATUS_PRIO_MULT[clampi(int(instr.get("status_priority", 1)), 0, 2)]
	match role:
		"cleric":
			v *= 1.25
		"lead":
			v *= 1.15
	return v


# ------------------------------------------------------------------ matchup math

## Rough expected fraction of `def`'s max HP that `att`'s best damaging move
## removes per turn (same shape as the engine's damage formula, no rolls).
static func _incoming(att: Dictionary, def: Dictionary) -> float:
	var best := 0.0
	var def_hp := maxf(float(def.get("max_hp", def.get("stats", {}).get("hp", 1))), 1.0)
	for mname in att.get("moves", []):
		var mv: Dictionary = DataStore.move(str(mname))
		if mv.is_empty() or str(mv.get("category", "")) == "status" or int(mv.get("power", 0)) <= 0:
			continue
		var eff: float = DataStore.effectiveness(str(mv["type"]), def.get("types", []))
		if eff <= 0.0:
			continue
		var stab := 1.5 if att.get("types", []).has(mv["type"]) else 1.0
		var phys: bool = str(mv["category"]) == "phys"
		var a := float(att.get("stats", {}).get("atk" if phys else "spa", 50))
		var d := float(def.get("stats", {}).get("def" if phys else "spd", 50))
		var dmg := ((2.0 * float(att.get("level", 50)) / 5.0 + 2.0)
			* float(mv["power"]) * a / maxf(d, 1.0) / 50.0 + 2.0) * stab * eff * 0.925
		best = maxf(best, dmg / def_hp)
	return best


static func _speed(b: Dictionary) -> float:
	return float(b.get("stats", {}).get("spe", 50))


## Bench index of the designated Revenge Killer (alive), else the fastest
## bench battler that carries a priority move, else -1.
static func _revenge_candidate(team: Array, switch_acts: Array, foe: Dictionary, tac: Dictionary) -> int:
	var roles: Dictionary = tac.get("roles", {})
	var best := -1
	var best_spe := -1.0
	for a in switch_acts:
		var i := int(a["index"])
		var cand: Dictionary = team[i]
		if str(roles.get(str(cand.get("uid", "")), "")) == "revenge":
			return i
		var has_prio := false
		for mname in cand.get("moves", []):
			if _has(DataStore.move(str(mname)).get("effects", []), "priority"):
				has_prio = true
				break
		if has_prio and _speed(cand) > best_spe:
			best_spe = _speed(cand)
			best = i
	return best


static func _has(fx: Array, tag: String) -> bool:
	for e in fx:
		if str(e).begins_with(tag):
			return true
	return false


# ------------------------------------------------------------------ drivers

## Drive one battle to the end with the plan commanding `side`
## (the engine's stock AI plays the other side).
static func drive_battle(eng, side: int, tac: Dictionary) -> void:
	var just_fainted := false
	var switched_last := false
	var guard := 0
	while not eng.is_over() and guard < 350:
		guard += 1
		var act := choose(eng, side, tac,
			{"just_fainted": just_fainted, "switched_last": switched_last})
		switched_last = str(act.get("type", "")) == "switch"
		var evs: Array = eng.step_turn(act, null) if side == 0 else eng.step_turn(null, act)
		just_fainted = false
		for e in evs:
			if str(e.get("t", "")) == "faint" and int(e.get("side", -1)) == side:
				just_fainted = true
				switched_last = false   # forced replacement resets the cooldown


## Full best-of-3 fixture with the plan running our side. Mirrors
## Season.simulate_fixture's seed usage so results stay deterministic.
## Returns {score_home, score_away, battles:[{winner,turns}],
##          our_faints, their_faints, ko_counts: {name: kos_against_us? no—ours}}
static func run_fixture(home_club: Dictionary, away_club: Dictionary,
		our_side: int, tac: Dictionary, match_seed: int) -> Dictionary:
	var wins := [0, 0]
	var battles: Array = []
	var players := {}    # uid -> Season.fixture_detail-format stats
	var our_faints := 0
	var their_faints := 0
	var faint_by := {}   # our battler name -> times it went down
	for i in 3:
		if wins[0] == 2 or wins[1] == 2:
			break
		var ours: Array = []
		for inst in Logic.lineup_instances(tac, home_club if our_side == 0 else away_club):
			var b: Dictionary = DataStore.make_battler(inst)
			if not b.is_empty():
				ours.append(b)
		var theirs: Array = Season.pick_team(away_club if our_side == 0 else home_club)
		if ours.is_empty() or theirs.is_empty():
			return {}
		var team_h := ours if our_side == 0 else theirs
		var team_a := theirs if our_side == 0 else ours
		var eng := BattleEngine.new(team_h, team_a, match_seed + i * 7919)
		drive_battle(eng, our_side, tac)
		var w: int = maxi(eng.winner(), 0)
		wins[w] += 1
		battles.append({"winner": w, "turns": eng.turn})
		Season._tally_battle(eng.events, [team_h, team_a], w, players)
		for e in eng.events:
			if str(e.get("t", "")) == "faint":
				if int(e.get("side", -1)) == our_side:
					our_faints += 1
					var nm := str(e.get("pokemon", "?"))
					faint_by[nm] = int(faint_by.get(nm, 0)) + 1
				else:
					their_faints += 1
	return {"score_home": wins[0], "score_away": wins[1], "battles": battles,
		"players": players,
		"our_faints": our_faints, "their_faints": their_faints, "faint_by": faint_by}
