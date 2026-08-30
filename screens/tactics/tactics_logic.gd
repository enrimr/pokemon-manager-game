extends RefCounted
## Tactics piece — pure logic: preset persistence, role suitability,
## type-coverage analysis. No UI in here. Owned by res://screens/tactics/.

const TACTICS_PATH := "user://tactics.json"

# ------------------------------------------------------------------ roles

const ROLES := {
	"lead": {
		"name": "Lead",
		"abbr": "LEA",
		"desc": "Opens every battle. Sets the tempo in the first exchanges: outspeeds the opposing opener, disrupts with sleep or paralysis, then pivots out before taking real damage.",
		"wants": "Speed, sleep/paralysis moves, stat drops, screens",
	},
	"sweeper": {
		"name": "Sweeper",
		"abbr": "SWP",
		"desc": "Your win condition. Stays in to snowball: boosts its attacking stats when given a free turn, then cleans up the weakened opposition with raw offensive pressure.",
		"wants": "Speed, Attack/Sp.Atk, set-up moves, high-power STAB",
	},
	"wall": {
		"name": "Wall",
		"abbr": "WAL",
		"desc": "Absorbs the hits the rest of the side cannot. Wears opponents down with poison and burns, recovers HP, and simply refuses to faint while the game turns your way.",
		"wants": "HP, Defence, Sp.Def, recovery, toxic/burn moves",
	},
	"pivot": {
		"name": "Pivot",
		"abbr": "PIV",
		"desc": "The flexible glue. Switches into dangerous matchups thanks to good resistances and balanced bulk, keeps momentum and hands the initiative back to your attackers.",
		"wants": "Resistances, all-round stats, wide move coverage",
	},
	"revenge": {
		"name": "Revenge Killer",
		"abbr": "REV",
		"desc": "Comes in immediately after a faint to outspeed and delete the threat before it moves again. Priority moves let it pick off even faster targets.",
		"wants": "Top speed, priority moves, immediate power",
	},
	"cleric": {
		"name": "Cleric",
		"abbr": "CLE",
		"desc": "The support piece. Heals itself to stay on the field, spreads status to buy turns, and screens the team so your win conditions arrive at full strength.",
		"wants": "Recovery, sleep/paralysis, screens, staying power",
	},
}

const ROLE_ORDER := ["lead", "sweeper", "wall", "pivot", "revenge", "cleric"]

const BANDS := [
	[85, "Natural", Color("57c979")],
	[70, "Accomplished", Color("9ed36a")],
	[55, "Competent", Color("e0b050")],
	[40, "Unconvincing", Color("e08a50")],
	[0, "Awkward", Color("e06060")],
]

const INSTRUCTION_DEFAULTS := {
	"aggression": 2,          # 0..4
	"switch_threshold": 25,   # retreat when HP below this %
	"status_priority": 1,     # 0 low / 1 balanced / 2 high
	"protect_lead": true,     # pull the Lead out of losing matchups
	"preserve_last": false,   # never sacrifice the final battler
	"revenge_switch": true,   # after a faint, send the Revenge Killer
}

const AGGRESSION_LABELS := ["Very Cautious", "Cautious", "Balanced", "Aggressive", "Hyper-Aggressive"]
const STATUS_LABELS := ["Low", "Balanced", "High"]


# ------------------------------------------------------------------ analysis

## Everything role scoring and coverage needs about one squad instance.
static func analyze(inst: Dictionary) -> Dictionary:
	var sp: Dictionary = DataStore.species(int(inst["species_id"]))
	var base: Dictionary = sp.get("base", {"hp": 50, "atk": 50, "def": 50, "spa": 50, "spd": 50, "spe": 50})
	var battler: Dictionary = DataStore.make_battler(inst)
	var a := {
		"uid": inst.get("uid", ""),
		"inst": inst,
		"battler": battler,
		"types": sp.get("types", ["normal"]),
		"base": base,
		"n_spe": _nb(base["spe"]), "n_atk": _nb(base["atk"]), "n_spa": _nb(base["spa"]),
		"n_off": _nb(maxi(int(base["atk"]), int(base["spa"]))),
		"n_bulk": (_nb(base["hp"]) + _nb(base["def"]) + _nb(base["spd"])) / 3.0,
		"has_sleep": false, "has_para": false, "has_tox": false, "has_heal": false,
		"has_drain": false, "has_priority": false, "has_setup": false, "has_screen": false,
		"has_drop": false, "status_moves": 0, "best_power": 0.0, "attack_types": {},
		"move_notes": {},
	}
	for mn in battler.get("moves", []):
		var mv: Dictionary = DataStore.move(mn)
		if mv.is_empty():
			continue
		var cat: String = mv.get("category", "phys")
		var pw := int(mv.get("power", 0))
		if cat == "status":
			a["status_moves"] += 1
		if cat != "status" or pw > 0:
			var stab := 1.5 if a["types"].has(mv["type"]) else 1.0
			a["best_power"] = maxf(a["best_power"], pw * stab)
			var cur: String = a["attack_types"].get(mv["type"], "")
			if cur == "" or int(DataStore.move(cur).get("power", 0)) < pw:
				a["attack_types"][mv["type"]] = mn
		for e in mv.get("effects", []):
			var parts: Array = str(e).split(":")
			match parts[0]:
				"sleep":
					a["has_sleep"] = true
				"para":
					if cat == "status" or float(parts[1]) >= 0.3:
						a["has_para"] = true
				"poison", "burn":
					if cat == "status":
						a["has_tox"] = true
				"heal":
					a["has_heal"] = true
				"drain":
					a["has_drain"] = true
				"priority":
					a["has_priority"] = true
				"stat":
					var self_buff: bool = parts.size() >= 5 and parts[4] == "self"
					var stages := int(parts[2])
					if self_buff and stages > 0:
						if parts[1] in ["atk", "spa", "spe"]:
							a["has_setup"] = true
						if parts[1] in ["def", "spd", "eva"]:
							a["has_screen"] = true
					elif not self_buff and stages < 0 and cat == "status":
						a["has_drop"] = true
	# defensive typing quality
	var resists := 0
	var weaks := 0
	for t in DataStore.types:
		var eff := DataStore.effectiveness(t, a["types"])
		if eff < 1.0: resists += 1
		elif eff > 1.0: weaks += 1
	a["resists"] = resists
	a["weaks"] = weaks
	return a


static func _nb(base_stat) -> float:
	return clampf((float(base_stat) - 30.0) / 100.0, 0.0, 1.0)


## Role suitability 0..100 plus human-readable reasons.
static func role_score(role: String, a: Dictionary) -> Dictionary:
	var s := 0.0
	var why: Array = []
	var spe := int(a["base"]["spe"])
	match role:
		"lead":
			s = 100.0 * (0.48 * a["n_spe"] + 0.17 * a["n_bulk"])
			if a["n_spe"] > 0.6: why.append("Fast opener (SPE %d)" % spe)
			if a["has_sleep"]: s += 22; why.append("Can put the opposing lead to sleep")
			if a["has_para"]: s += 12; why.append("Spreads paralysis")
			if a["has_drop"]: s += 8; why.append("Softens up with stat drops")
			if a["has_screen"]: s += 6; why.append("Sets defensive screens")
			if a["has_priority"]: s += 5; why.append("Priority move for safe chip damage")
		"sweeper":
			s = 100.0 * (0.38 * a["n_off"] + 0.32 * a["n_spe"])
			if a["n_off"] > 0.65: why.append("Big attacking stat (%d)" % maxi(int(a["base"]["atk"]), int(a["base"]["spa"])))
			if a["n_spe"] > 0.6: why.append("Outspeeds most of the league")
			if a["has_setup"]: s += 18; why.append("Set-up move to snowball")
			s += clampf(a["best_power"], 0, 150) / 150.0 * 14.0
			if a["best_power"] >= 100: why.append("High-power STAB attack")
			if a["has_drain"]: s += 4; why.append("Drains HP to stay healthy")
		"wall":
			s = 100.0 * (0.62 * a["n_bulk"])
			if a["n_bulk"] > 0.55: why.append("Genuinely bulky (HP/DEF/SPD)")
			if a["has_heal"]: s += 22; why.append("Reliable recovery")
			if a["has_tox"]: s += 12; why.append("Wears attackers down with status")
			if a["has_screen"]: s += 8; why.append("Boosts its own defences")
			if a["has_drain"]: s += 5; why.append("Drain moves extend its stay")
		"pivot":
			s = 100.0 * (0.32 * a["n_bulk"] + 0.16 * a["n_spe"])
			s += clampf(a["resists"] * 3.2, 0, 26)
			if a["resists"] >= 5: why.append("Resists %d attack types" % a["resists"])
			if a["attack_types"].size() >= 3: s += 10; why.append("Coverage across %d attack types" % a["attack_types"].size())
			if a["weaks"] <= 2: s += 8; why.append("Few exploitable weaknesses")
			if a["has_para"] or a["has_drop"]: s += 5; why.append("Disrupts on the switch")
		"revenge":
			s = 100.0 * (0.46 * a["n_spe"] + 0.24 * a["n_off"])
			if a["n_spe"] > 0.7: why.append("Elite speed (SPE %d)" % spe)
			if a["has_priority"]: s += 22; why.append("Priority move beats anything")
			s += clampf(a["best_power"], 0, 150) / 150.0 * 8.0
			if a["best_power"] >= 100: why.append("Hits hard immediately")
		"cleric":
			s = 100.0 * (0.26 * a["n_bulk"] + 0.10 * a["n_spe"])
			if a["has_heal"]: s += 30; why.append("Recovery keeps it on the field")
			if a["has_sleep"]: s += 12; why.append("Sleep buys free turns")
			if a["has_para"]: s += 10; why.append("Paralysis support")
			if a["has_screen"]: s += 10; why.append("Screens protect the team")
			s += clampf(a["status_moves"] * 4.0, 0, 12)
			if a["status_moves"] >= 2: why.append("%d support moves" % a["status_moves"])
	if why.is_empty():
		why.append("No attributes that fit this role")
	return {"score": int(clampf(s, 1, 99)), "why": why}


static func band(score: int) -> Array:  # [label, Color]
	for b in BANDS:
		if score >= int(b[0]):
			return [b[1], b[2]]
	return ["Awkward", Color("e06060")]


static func best_role(a: Dictionary) -> String:
	var best := "pivot"
	var best_s := -1
	for r in ROLE_ORDER:
		var s: int = role_score(r, a)["score"]
		if s > best_s:
			best_s = s
			best = r
	return best


# ------------------------------------------------------------------ coverage

## Best offensive multiplier of this battler's damaging moves vs a defending type.
## Returns {mult, move}.
static func offense_vs(a: Dictionary, def_type: String) -> Dictionary:
	var best := {"mult": 0.0, "move": ""}
	for atk_type in a["attack_types"]:
		var m := DataStore.effectiveness(atk_type, [def_type])
		if m > best["mult"]:
			best = {"mult": m, "move": a["attack_types"][atk_type]}
	return best


# ------------------------------------------------------------------ persistence

static func load_state() -> Dictionary:
	var state := {}
	if FileAccess.file_exists(TACTICS_PATH):
		var f := FileAccess.open(TACTICS_PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY and int(parsed.get("version", 0)) == 1:
			state = parsed
	if state.is_empty():
		state = {"version": 1, "active": "", "presets": []}
	var squad: Array = GameState.player_club().get("squad", [])
	for p in state["presets"]:
		validate_preset(p, squad)
	if state["presets"].is_empty():
		state["presets"].append(default_preset("Primary Plan", squad))
	var names: Array = state["presets"].map(func(p): return p["name"])
	if not names.has(state["active"]):
		state["active"] = names[0]
	return state


static func save_state(state: Dictionary) -> void:
	var f := FileAccess.open(TACTICS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(state))
	apply_to_gamestate(state)


## Publish the active tactic into GameState so the match engine / other pieces
## can read GameState.world["meta"]["tactics"] (persists inside save.json).
## `persist=false` republishes without touching the save file (boot path).
static func apply_to_gamestate(state: Dictionary, persist: bool = true) -> void:
	var p := active_preset(state)
	GameState.world["meta"]["tactics"] = plan_from_preset(p)
	if persist:
		GameState.save_game()


## The wire format consumed by TacticsDirector / TacticsBrain.
static func plan_from_preset(p: Dictionary) -> Dictionary:
	return {
		"name": p["name"],
		"lineup": p["lineup"].duplicate(),
		"bench": p["bench"].duplicate(),
		"roles": p["roles"].duplicate(),
		"instructions": p["instructions"].duplicate(),
	}


## Ordered squad instances for the plan's starting six. Self-healing against
## squad churn: unknown uids are dropped and gaps are filled by the best
## remaining battlers (level, then condition) so the engine always gets a team.
static func lineup_instances(tac: Dictionary, club: Dictionary) -> Array:
	var squad: Array = club.get("squad", [])
	var by_uid := {}
	for inst in squad:
		by_uid[inst["uid"]] = inst
	var out: Array = []
	var used := {}
	for u in tac.get("lineup", []):
		if by_uid.has(u) and not used.has(u):
			out.append(by_uid[u])
			used[u] = true
		if out.size() == 6:
			break
	if out.size() < mini(6, squad.size()):
		for u in tac.get("bench", []):        # bench order = substitution order
			if out.size() == 6:
				break
			if by_uid.has(u) and not used.has(u):
				out.append(by_uid[u])
				used[u] = true
		var rest: Array = squad.filter(func(i): return not used.has(i["uid"]))
		rest.sort_custom(func(a, b):
			if int(a["level"]) != int(b["level"]):
				return int(a["level"]) > int(b["level"])
			return int(a.get("condition", 100)) > int(b.get("condition", 100)))
		for inst in rest:
			if out.size() == 6:
				break
			out.append(inst)
	return out


## Map the plan's instructions onto the engine/match-runner touchline policy
## vocabulary ({"aggression": balanced|attacking|cautious, "switching":
## normal|stay|eager}). The live match's default-AI turns use this; instant
## sims get the full instruction set via TacticsBrain.
static func instructions_to_policy(instr: Dictionary) -> Dictionary:
	var ag := clampi(int(instr.get("aggression", 2)), 0, 4)
	var thr := clampi(int(instr.get("switch_threshold", 25)), 0, 60)
	var aggression := "balanced"
	if ag <= 1:
		aggression = "cautious"
	elif ag >= 3:
		aggression = "attacking"
	var switching := "normal"
	if thr >= 35 or (bool(instr.get("revenge_switch", true)) and thr >= 30):
		switching = "eager"
	elif thr <= 10 and not bool(instr.get("protect_lead", true)):
		switching = "stay"
	return {"aggression": aggression, "switching": switching}


static func active_preset(state: Dictionary) -> Dictionary:
	for p in state["presets"]:
		if p["name"] == state["active"]:
			return p
	return state["presets"][0]


static func default_preset(pname: String, squad: Array) -> Dictionary:
	var ordered := squad.duplicate()
	ordered.sort_custom(func(x, y):
		if int(x["level"]) != int(y["level"]):
			return int(x["level"]) > int(y["level"])
		return int(x.get("condition", 100)) > int(y.get("condition", 100)))
	var uids: Array = ordered.map(func(i): return i["uid"])
	var roles := {}
	for inst in ordered:
		roles[inst["uid"]] = best_role(analyze(inst))
	# put the most natural Lead of the six in slot 1
	var six: Array = uids.slice(0, 6)
	var best_i := 0
	var best_s := -1
	var by_uid := {}
	for inst in ordered:
		by_uid[inst["uid"]] = inst
	for i in six.size():
		var s: int = role_score("lead", analyze(by_uid[six[i]]))["score"]
		if s > best_s:
			best_s = s
			best_i = i
	if best_i > 0:
		var tmp = six[0]
		six[0] = six[best_i]
		six[best_i] = tmp
	if not six.is_empty():
		roles[six[0]] = "lead"
	uids = six + uids.slice(6)
	return {
		"name": pname,
		"lineup": uids.slice(0, 6),
		"bench": uids.slice(6),
		"roles": roles,
		"instructions": INSTRUCTION_DEFAULTS.duplicate(),
	}


## Repair a preset against the current squad (transfers in/out, corrupt data).
static func validate_preset(p: Dictionary, squad: Array) -> void:
	var squad_uids: Array = squad.map(func(i): return i["uid"])
	for k in ["lineup", "bench"]:
		if typeof(p.get(k)) != TYPE_ARRAY:
			p[k] = []
		p[k] = p[k].filter(func(u): return squad_uids.has(u))
	if typeof(p.get("roles")) != TYPE_DICTIONARY:
		p["roles"] = {}
	var seen: Array = []
	p["lineup"] = p["lineup"].filter(func(u):
		if seen.has(u): return false
		seen.append(u); return true)
	p["bench"] = p["bench"].filter(func(u):
		if seen.has(u): return false
		seen.append(u); return true)
	for u in squad_uids:          # new arrivals go on the bench
		if not seen.has(u):
			p["bench"].append(u)
	while p["lineup"].size() < 6 and not p["bench"].is_empty():
		p["lineup"].append(p["bench"].pop_front())
	var by_uid := {}
	for inst in squad:
		by_uid[inst["uid"]] = inst
	for u in squad_uids:
		if not ROLES.has(p["roles"].get(u, "")):
			p["roles"][u] = best_role(analyze(by_uid[u]))
	var instr: Dictionary = p.get("instructions", {}) if typeof(p.get("instructions")) == TYPE_DICTIONARY else {}
	for k in INSTRUCTION_DEFAULTS:
		if not instr.has(k):
			instr[k] = INSTRUCTION_DEFAULTS[k]
	instr["aggression"] = clampi(int(instr["aggression"]), 0, 4)
	instr["switch_threshold"] = clampi(int(instr["switch_threshold"]), 0, 60)
	instr["status_priority"] = clampi(int(instr["status_priority"]), 0, 2)
	p["instructions"] = instr
