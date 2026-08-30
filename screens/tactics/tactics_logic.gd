extends RefCounted
## Tactics piece — pure logic: preset persistence, role suitability,
## type-coverage analysis. No UI in here. Owned by res://screens/tactics/.
##
## PERSISTENCE: the single source of truth is GameState.world.meta —
##   meta["tactics_state"]  full preset state {version, active, presets}
##   meta["tactics"]        the active plan (wire format, engine-consumed)
## Both live inside world, so they ride save.json and can never desync from
## a loaded save. The legacy sidecar user://tactics.json is read ONCE as a
## migration source for pre-single-source careers, then deleted.

const TACTICS_PATH := "user://tactics.json"   # legacy sidecar (migration only)

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
	# Nature-adjust the stats HERE, exactly like BattleEngine._init_battler,
	# so every number the tactics board shows is the one that fights.
	battler["stats"] = apply_nature(battler.get("stats", {}), str(battler.get("nature", "Hardy")))
	var ability := str(battler.get("ability", ""))
	var a := {
		"uid": inst.get("uid", ""),
		"inst": inst,
		"battler": battler,
		"ability": ability,
		"ability_name": DataStore.ability_name(ability) if ability != "" else "—",
		"nature": str(battler.get("nature", "Hardy")),
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
	# defensive typing quality — ability-aware (Levitate holders are NOT weak
	# to ground; Water/Volt Absorb & Flash Fire zero out their types; Thick
	# Fat halves fire/ice), matching what the engine actually applies.
	var resists := 0
	var weaks := 0
	for t in DataStore.types:
		var eff := def_mult(a, t)
		if eff < 1.0: resists += 1
		elif eff > 1.0: weaks += 1
	a["resists"] = resists
	a["weaks"] = weaks
	return a


## Engine-identical nature math: +10% floored / -10% floored (min 1), never HP.
static func apply_nature(stats: Dictionary, nature_name: String) -> Dictionary:
	var out := stats.duplicate()
	var nat: Dictionary = DataStore.nature(nature_name)
	if nat.is_empty():
		return out
	var plus: Variant = nat.get("plus")
	var minus: Variant = nat.get("minus")
	if plus != null and str(plus) != "hp" and out.has(str(plus)):
		out[str(plus)] = int(floor(float(out[str(plus)]) * 1.1))
	if minus != null and str(minus) != "hp" and out.has(str(minus)):
		out[str(minus)] = maxi(1, int(floor(float(out[str(minus)]) * 0.9)))
	return out


## Ability-aware defensive multiplier for an analysis dict: type chart x
## ability immunity (immune:t / absorb:t -> 0) x ability resist (resist:t:f).
static func def_mult(a: Dictionary, atk_type: String) -> float:
	var m := DataStore.effectiveness(atk_type, a["types"])
	for e in DataStore.ability(str(a.get("ability", ""))).get("effects", []):
		var parts: Array = str(e).split(":")
		if parts[0] in ["immune", "absorb"] and parts.size() >= 2 and str(parts[1]) == atk_type:
			return 0.0
		if parts[0] == "resist" and parts.size() >= 3 and str(parts[1]) == atk_type:
			m *= float(parts[2])
	return m


## Attack types this analysis' ability makes it fully immune to.
static func ability_immunities(a: Dictionary) -> Array:
	var out: Array = []
	for e in DataStore.ability(str(a.get("ability", ""))).get("effects", []):
		var parts: Array = str(e).split(":")
		if parts[0] in ["immune", "absorb"] and parts.size() >= 2:
			out.append(str(parts[1]))
	return out


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
	# battle-depth: the ability and nature shift how well a role fits.
	for adj in _depth_role_adj(role, a):
		s += float(adj[0])
		why.append(str(adj[1]))
	if why.is_empty():
		why.append("No attributes that fit this role")
	return {"score": int(clampf(s, 1, 99)), "why": why}


## Ability + nature adjustments for one role: Array of [delta, reason].
## Modest nudges (±4..10) mirroring what the engine actually rewards.
static func _depth_role_adj(role: String, a: Dictionary) -> Array:
	var out: Array = []
	var ab_name := str(a.get("ability_name", ""))
	var immunities: Array = []
	for e in DataStore.ability(str(a.get("ability", ""))).get("effects", []):
		var parts: Array = str(e).split(":")
		match parts[0]:
			"on_switch_in":
				if parts.size() >= 2 and parts[1] == "stat" and role in ["lead", "pivot"]:
					out.append([10 if role == "lead" else 6,
						"%s softens whatever it faces on entry" % ab_name])
				elif parts.size() >= 2 and parts[1] == "weather" and role == "lead":
					out.append([6, "%s sets the weather from turn one" % ab_name])
			"end_turn_stat":
				if parts.size() >= 3 and parts[1] == "spe" and role in ["sweeper", "revenge"]:
					out.append([10 if role == "sweeper" else 5,
						"%s snowballs its Speed every turn" % ab_name])
			"mult":
				if parts.size() >= 2 and parts[1] in ["atk", "spa"] and role == "sweeper":
					out.append([8, "%s multiplies its attacking power" % ab_name])
			"immune", "absorb":
				if parts.size() >= 2:
					immunities.append(str(parts[1]))
			"heal_status_on_switch":
				if role in ["pivot", "cleric"]:
					out.append([6, "%s sheds status on the switch out" % ab_name])
			"sturdy":
				if role in ["lead", "wall"]:
					out.append([5 if role == "lead" else 4,
						"%s guarantees it survives the first blow" % ab_name])
			"end_turn_cure":
				if role == "wall":
					out.append([5, "%s throws off status over time" % ab_name])
			"no_stat_drop":
				if role == "wall":
					out.append([4, "%s can't be softened up" % ab_name])
			"contact_status", "contact_damage":
				if role == "wall":
					out.append([4, "%s punishes physical contact" % ab_name])
			"status_boost":
				if role == "sweeper":
					out.append([4, "%s turns status against the attacker" % ab_name])
	if not immunities.is_empty() and role in ["pivot", "wall"]:
		out.append([mini(5 * immunities.size(), 10) if role == "pivot" else 4,
			"%s grants free switch-ins vs %s" % [ab_name, "/".join(immunities)]])
	# nature: does the +10%/-10% land on this role's key stats?
	var off_key := "atk" if int(a["base"]["atk"]) >= int(a["base"]["spa"]) else "spa"
	var keys: Array = {
		"lead": ["spe"], "sweeper": [off_key, "spe"], "wall": ["def", "spd"],
		"pivot": ["def", "spd"], "revenge": ["spe", off_key], "cleric": ["def", "spd"],
	}.get(role, [])
	var nat: Dictionary = DataStore.nature(str(a.get("nature", "Hardy")))
	var plus := str(nat.get("plus", "")) if nat.get("plus") != null else ""
	var minus := str(nat.get("minus", "")) if nat.get("minus") != null else ""
	if plus in keys:
		out.append([5, "%s nature (+10%% %s) suits the role" % [a.get("nature", ""), plus.to_upper()]])
	if minus in keys:
		out.append([-5, "%s nature (−10%% %s) works against the role" % [a.get("nature", ""), minus.to_upper()]])
	return out


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


# ------------------------------------------------------------------ weather

## Does the selected six deliberately set weather, and who gains from it?
## -> {} when no starter sets weather, else:
##    {kind, setters: ["Politoed (Drizzle)", "Sunflora (Sunny Day)"...],
##     boosts: [strings], risks: [strings]}
static func weather_plan(analyses: Dictionary, lineup: Array) -> Dictionary:
	var setters := {}          # kind -> Array of "Name (How)"
	for uid in lineup:
		var a: Dictionary = analyses.get(uid, {})
		if a.is_empty():
			continue
		var nm := str(a["battler"].get("name", a["inst"].get("species", "?")))
		for e in DataStore.ability(str(a.get("ability", ""))).get("effects", []):
			var parts: Array = str(e).split(":")
			if parts[0] == "on_switch_in" and parts.size() >= 3 and parts[1] == "weather":
				var k := str(parts[2])
				if not setters.has(k):
					setters[k] = []
				setters[k].append("%s (%s)" % [nm, a.get("ability_name", "ability")])
		for mn in a["battler"].get("moves", []):
			for e in DataStore.move(mn).get("effects", []):
				var parts: Array = str(e).split(":")
				if parts[0] == "weather" and parts.size() >= 2:
					var k := str(parts[1])
					if not setters.has(k):
						setters[k] = []
					setters[k].append("%s (%s)" % [nm, mn])
	if setters.is_empty():
		return {}
	var kind := ""
	for k in setters:      # primary plan = the kind with the most setters
		if kind == "" or (setters[k] as Array).size() > (setters[kind] as Array).size():
			kind = k
	var boosts: Array = []
	var risks: Array = []
	for uid in lineup:
		var a: Dictionary = analyses.get(uid, {})
		if a.is_empty():
			continue
		var nm := str(a["battler"].get("name", a["inst"].get("species", "?")))
		var ab := str(a.get("ability", ""))
		for e in DataStore.ability(ab).get("effects", []):
			var parts: Array = str(e).split(":")
			if parts[0] == "weather_speed" and parts.size() >= 2 and str(parts[1]) == kind:
				boosts.append("%s doubles its Speed (%s)" % [nm, a.get("ability_name", "")])
			elif parts[0] == "weather_heal" and parts.size() >= 2 and str(parts[1]) == kind:
				boosts.append("%s heals every turn (%s)" % [nm, a.get("ability_name", "")])
			elif parts[0] == "weather_eva" and parts.size() >= 2 and str(parts[1]) == kind:
				boosts.append("%s gets harder to hit (%s)" % [nm, a.get("ability_name", "")])
		var atk_types: Dictionary = a.get("attack_types", {})
		if kind == "sun":
			if atk_types.has("fire"):
				boosts.append("%s's Fire attacks hit ×1.5" % nm)
			if atk_types.has("water"):
				risks.append("%s's Water attacks fall to ×0.5" % nm)
		elif kind == "rain":
			if atk_types.has("water"):
				boosts.append("%s's Water attacks hit ×1.5" % nm)
			if atk_types.has("fire"):
				risks.append("%s's Fire attacks fall to ×0.5" % nm)
		elif kind == "sand":
			var types: Array = a.get("types", [])
			var safe := false
			for t in types:
				if str(t) in ["rock", "ground", "steel"]:
					safe = true
			if types.has("rock"):
				boosts.append("%s gains ×1.5 Sp. Def (Rock type)" % nm)
			if not safe and str(ab) != "sand_veil":
				risks.append("%s takes 1/16 chip damage each turn" % nm)
	return {"kind": kind, "setters": setters[kind], "boosts": boosts, "risks": risks}


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

## Load the tactic state from the save (world.meta.tactics_state). Falls back
## ONCE to the legacy user://tactics.json sidecar for careers saved before the
## single-source change, then the sidecar is retired. Always returns a state
## validated against the current squad, and stores it back into world.meta so
## in-place edits are already part of the world the next save_game persists.
static func load_state() -> Dictionary:
	var meta: Dictionary = GameState.world.get("meta", {})
	var state := {}
	var in_save: Variant = meta.get("tactics_state")
	if typeof(in_save) == TYPE_DICTIONARY and int(in_save.get("version", 0)) == 1 \
			and typeof(in_save.get("presets")) == TYPE_ARRAY and not (in_save["presets"] as Array).is_empty():
		state = in_save
	if state.is_empty():
		state = _read_legacy_sidecar()
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
	meta["tactics_state"] = state
	return state


## Legacy migration source: pre-single-source careers kept presets in a
## user:// sidecar. Read it if present; save_state deletes it afterwards.
static func _read_legacy_sidecar() -> Dictionary:
	if not FileAccess.file_exists(TACTICS_PATH):
		return {}
	var f := FileAccess.open(TACTICS_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY and int(parsed.get("version", 0)) == 1:
		return parsed
	return {}


static func save_state(state: Dictionary) -> void:
	GameState.world["meta"]["tactics_state"] = state
	remove_legacy_sidecar()
	apply_to_gamestate(state)


## The sidecar is no longer a source of truth — remove it so a stale copy can
## never shadow what an older save actually contains.
static func remove_legacy_sidecar() -> void:
	if FileAccess.file_exists(TACTICS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TACTICS_PATH))


## Publish the active tactic into GameState so the match engine / other pieces
## can read GameState.world["meta"]["tactics"] (persists inside save.json).
## `persist=false` republishes without touching the save file (boot path).
static func apply_to_gamestate(state: Dictionary, persist: bool = true) -> void:
	var p := active_preset(state)
	GameState.world["meta"]["tactics_state"] = state
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
