extends RefCounted
## Squad piece: matchday selection layer + availability flags.
## Reads the saved tactic (published by the Tactics screen into
## GameState.world.meta.tactics; falls back to the preset state saved inside
## the same world.meta — the single source of truth — then to the instant-sim
## auto-pick of the best six by level and condition) and self-heals against
## squad churn the same way the match engine does, so the Picked column
## always matches who would battle.

const UI := preload("res://screens/squad/ui_helpers.gd")

const ROLE_ABBR := {"lead": "LEA", "sweeper": "SWP", "wall": "WAL",
	"pivot": "PIV", "revenge": "REV", "cleric": "CLE"}
const ROLE_NAMES := {"lead": "Lead", "sweeper": "Sweeper", "wall": "Wall",
	"pivot": "Pivot", "revenge": "Revenge Killer", "cleric": "Cleric"}

const COL_STARTER := Color("f2f4fa")
const COL_SUB := Color("8b91a8")


## Selection snapshot for the player squad:
## {name, source: "tactic"|"auto", slot: {uid: 1..6}, sub: {uid: 1..n}, roles: {uid: role}}
static func selection() -> Dictionary:
	var squad: Array = GameState.player_club().get("squad", [])
	var plan := _plan()
	var source := "tactic" if not plan.is_empty() else "auto"
	var by_uid := {}
	for inst in squad:
		by_uid[inst["uid"]] = inst
	var used := {}
	var starters: Array = []
	for u in plan.get("lineup", []):
		if by_uid.has(u) and not used.has(u) and starters.size() < 6:
			starters.append(u)
			used[u] = true
	var subs: Array = []
	for u in plan.get("bench", []):
		if by_uid.has(u) and not used.has(u):
			subs.append(u)
			used[u] = true
	# Anyone the plan doesn't know joins the back of the bench queue,
	# best first (level, then condition) — mirrors the engine's self-heal.
	var rest: Array = squad.filter(func(i): return not used.has(i["uid"]))
	rest.sort_custom(func(a, b):
		if int(a["level"]) != int(b["level"]):
			return int(a["level"]) > int(b["level"])
		return int(a.get("condition", 100)) > int(b.get("condition", 100)))
	for inst in rest:
		subs.append(inst["uid"])
	while starters.size() < mini(6, squad.size()) and not subs.is_empty():
		starters.append(subs.pop_front())
	var slot := {}
	for i in starters.size():
		slot[starters[i]] = i + 1
	var sub := {}
	for i in subs.size():
		sub[subs[i]] = i + 1
	return {"name": str(plan.get("name", "Auto Pick")), "source": source,
		"slot": slot, "sub": sub, "roles": plan.get("roles", {})}


## The active tactic plan, or {} when none has ever been saved.
static func _plan() -> Dictionary:
	var meta: Dictionary = GameState.world.get("meta", {})
	var t: Variant = meta.get("tactics")
	if typeof(t) == TYPE_DICTIONARY and (t as Dictionary).has("lineup"):
		return t
	# Plan not published yet this session: read the preset state saved inside
	# the same world.meta (single source of truth — rides save.json).
	var st: Variant = meta.get("tactics_state")
	if typeof(st) == TYPE_DICTIONARY:
		var presets: Array = st.get("presets", []) if typeof(st.get("presets")) == TYPE_ARRAY else []
		for p in presets:
			if typeof(p) == TYPE_DICTIONARY and str(p.get("name", "")) == str(st.get("active", "")):
				return p
		if not presets.is_empty() and typeof(presets[0]) == TYPE_DICTIONARY:
			return presets[0]
	return {}


## Per-mon picked info: {kind: starter|sub, text, rank, color, tip, role}
static func pick_info(uid: String, sel: Dictionary) -> Dictionary:
	var role := str((sel.get("roles", {}) as Dictionary).get(uid, ""))
	var role_name := str(ROLE_NAMES.get(role, ""))
	var plan_note := "the saved tactic '%s'" % sel["name"] if sel["source"] == "tactic" \
		else "the auto-picked six (no tactic saved yet: best available by level and condition)"
	if (sel["slot"] as Dictionary).has(uid):
		var n := int(sel["slot"][uid])
		var abbr := str(ROLE_ABBR.get(role, ""))
		return {"kind": "starter", "rank": n, "role": role_name,
			"text": ("%d · %s" % [n, abbr]) if abbr != "" else str(n),
			"color": COL_STARTER,
			"tip": "Starts Saturday: slot %d of %s%s.%s" % [n, plan_note,
				(" as the %s" % role_name) if role_name != "" else "",
				"\nSlot 1 opens the battle; the order sets who the engine leans on." if n == 1 else ""]}
	var s := int((sel["sub"] as Dictionary).get(uid, 99))
	return {"kind": "sub", "rank": 10 + s, "role": role_name,
		"text": "S%d" % s, "color": COL_SUB,
		"tip": "Not in the picked six — bench slot %d of %s%s. Bench order is the substitution order when a starter is unavailable." %
			[s, plan_note, (", trained as a %s" % role_name) if role_name != "" else ""]}


## Availability flags: [{code, sev(1 warn|2 bad), color, tip}]. Empty = fully available.
static func flags(inst: Dictionary) -> Array:
	var out: Array = []
	var cond := int(inst.get("condition", 100))
	var fit := int(inst.get("fitness", 100))
	var morale := int(inst.get("morale", 100))
	if cond < 45:
		out.append({"code": "EXH", "sev": 2, "color": UI.COL_BAD,
			"tip": "Exhausted — condition %d%%. Battling now invites a poor rating; rest before picking." % cond})
	elif cond < 70:
		out.append({"code": "TRD", "sev": 1, "color": UI.COL_WARN,
			"tip": "Tired — condition %d%%, below matchday freshness." % cond})
	if fit < 50:
		out.append({"code": "UNF", "sev": 2, "color": UI.COL_BAD,
			"tip": "Unfit — fitness %d%%. Needs training time before competitive battles." % fit})
	elif fit < 72:
		out.append({"code": "FIT", "sev": 1, "color": UI.COL_WARN,
			"tip": "Short of match fitness (%d%%)." % fit})
	var ail := str(inst.get("status", ""))
	if ail != "" and ail != "none" and ail != "<null>":
		out.append({"code": ail.substr(0, 3).to_upper(), "sev": 2, "color": UI.COL_BAD,
			"tip": "Carrying a %s ailment into the next match." % ail})
	if bool(inst.get("transfer_listed", false)):
		out.append({"code": "LST", "sev": 1, "color": UI.COL_WARN,
			"tip": "Transfer listed at %s — expects to leave the club." % UI.money(int(inst.get("asking_price", 0)))})
	if morale < 55:
		var bad := morale < 30
		out.append({"code": "UNH", "sev": 2 if bad else 1,
			"color": UI.COL_BAD if bad else UI.COL_WARN,
			"tip": "Unhappy — morale %s (%d). Performances suffer until it lifts." % [UI.morale_word(morale), morale]})
	return out


static func worst_color(flag_list: Array) -> Color:
	var worst := 0
	for fl in flag_list:
		worst = maxi(worst, int(fl["sev"]))
	if worst >= 2:
		return UI.COL_BAD
	if worst == 1:
		return UI.COL_WARN
	return UI.COL_TEXT_DIM


static func flags_text(flag_list: Array) -> String:
	if flag_list.is_empty():
		return "-"
	return " ".join(flag_list.map(func(fl): return str(fl["code"])))


static func flags_tip(flag_list: Array) -> String:
	if flag_list.is_empty():
		return "Fully available for selection."
	return "\n".join(flag_list.map(func(fl): return str(fl["tip"])))
