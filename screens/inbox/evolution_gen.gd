extends RefCounted
const EvoSvc := preload("res://shared/sim/services/evolution.gd")
## Inbox piece: renders evolution messages — the FM-style "requires your
## decision" approval flow. Three kinds (tagged by the evolution service):
##   evo_ready — a mon met its requirements; Approve / Postpone buttons live
##               here and call EvolutionService directly.
##   evo_stone — staff hint that a stone route exists; Use-Stone button when
##               one is in stock, else a shortcut to the League Store.
##   evo_done  — the transformation report (typing + base-stat deltas).

const C_GOOD := "57c979"
const C_BAD := "e06060"
const C_WARN := "e0b050"
const C_DIM := "8b91a8"
const C_ACC := "9d92ff"
const C_WHITE := "e8ebf5"

const STAT_KEYS := ["hp", "atk", "def", "spa", "spd", "spe"]
const STAT_NAMES := {"hp": "HP", "atk": "Attack", "def": "Defence",
	"spa": "Sp.Atk", "spd": "Sp.Def", "spe": "Speed"}


func _svc() -> RefCounted:
	return EvoSvc.instance


func render(msg: Dictionary) -> Dictionary:
	match str(msg.get("kind", "")):
		"evo_ready":
			return _ready(msg)
		"evo_stone":
			return _stone_hint(msg)
		"evo_done":
			return _done(msg)
	return {"bbcode": "[color=#%s]%s[/color]" % [C_WHITE, str(msg.get("body", ""))],
		"actions": [{"label": I18n.t("View Squad"), "screen": "squad"}], "banner": {}}


# ---------------------------------------------------------------- evo_ready

func _ready(msg: Dictionary) -> Dictionary:
	var svc := _svc()
	var uid := str(msg.get("evo_uid", ""))
	var from_id := int(msg.get("evo_from", 0))
	var to_id := int(msg.get("evo_to", 0))
	var inst: Dictionary = GameState.squad_member(uid)
	var name := _mon_name(inst, msg)

	var bb := I18n.t("[color=#%s][b]COACHES' RECOMMENDATION[/b][/color]\n") % C_DIM
	bb += "[color=#%s]%s[/color]\n\n" % [C_WHITE, str(msg.get("body", ""))]
	bb += _method_block(msg, inst)
	bb += _compare_block(from_id, to_id, inst)

	var decided := str(msg.get("decided", ""))
	var actions: Array = []
	if decided == "" and svc != null and svc.is_pending(uid):
		bb += I18n.t("\n[color=#%s][b]YOUR DECISION[/b][/color]\n") % C_DIM
		bb += (I18n.t("[color=#%s]Approve to transform %s immediately (+%d morale; its old ") +
			I18n.t("learnset stays trainable). Postpone and it loses %d morale — the offer ") +
			I18n.t("returns in %d days if the requirements still hold.[/color]\n")) % \
			[C_WHITE, name, EvoSvc.EVOLVE_MORALE_BOOST,
			EvoSvc.POSTPONE_MORALE_COST, EvoSvc.REOFFER_DAYS]
		actions.append({"kind": "evo_approve", "evo_uid": uid, "style": "good",
			"label": I18n.t("Approve Evolution")})
		actions.append({"kind": "evo_postpone", "evo_uid": uid, "style": "bad",
			"label": I18n.t("Postpone (-%d morale)") % EvoSvc.POSTPONE_MORALE_COST})
	else:
		var word := decided if decided != "" else "resolved"
		var col := C_GOOD if word.begins_with("approved") or word.begins_with("evolved") else C_WARN
		bb += I18n.t("\n[color=#%s][b]DECISION TAKEN — %s[/b]") % [col, word.to_upper()]
		if str(msg.get("decided_on", "")) != "":
			bb += I18n.t(" [color=#%s]on %s[/color]") % [C_DIM, I18n.pretty_date(str(msg["decided_on"]))]
		bb += I18n.t("[/color]\n")
		if word == "postponed" and svc != null:
			bb += I18n.t("[color=#%s]The coaches will raise it again if %s still qualifies.[/color]\n") % [C_DIM, name]
	actions.append({"label": I18n.t("View Squad"), "screen": "squad"})
	return {"bbcode": bb, "actions": actions, "banner": {}}


# ---------------------------------------------------------------- evo_stone

func _stone_hint(msg: Dictionary) -> Dictionary:
	var svc := _svc()
	var uid := str(msg.get("evo_uid", ""))
	var stone := str(msg.get("evo_stone", ""))
	var inst: Dictionary = GameState.squad_member(uid)
	var name := _mon_name(inst, msg)
	var iname := I18n.t(str(DataStore.item(stone).get("name", stone)))
	var price := int(DataStore.item(stone).get("price", 0))
	var owned := int(GameState.player_inventory().get(stone, 0))

	var bb := I18n.t("[color=#%s][b]STAFF REPORT — EVOLUTION ROUTE[/b][/color]\n") % C_DIM
	bb += "[color=#%s]%s[/color]\n\n" % [C_WHITE, str(msg.get("body", ""))]
	if inst.is_empty():
		bb += I18n.t("[color=#%s]%s is no longer in the squad.[/color]\n") % [C_DIM, name]
		return {"bbcode": bb, "actions": [{"label": I18n.t("View Squad"), "screen": "squad"}], "banner": {}}
	bb += _compare_block(int(msg.get("evo_from", inst.get("species_id", 0))),
		int(msg.get("evo_to", 0)), inst)
	bb += I18n.t("\n[color=#%s][b]THE STONE[/b][/color]\n") % C_DIM
	if owned > 0:
		bb += I18n.t("[color=#%s]%d× %s in the storeroom — you can apply it right now. Using a stone needs no further approval.[/color]\n") % \
			[C_GOOD, owned, iname]
	else:
		bb += I18n.t("[color=#%s]None in stock. The League Store lists the %s at %s.[/color]\n") % \
			[C_WARN, iname, _money(price)]
	var actions: Array = []
	var evolved_already: bool = int(inst.get("species_id", 0)) != int(msg.get("evo_from", inst.get("species_id", 0)))
	if evolved_already:
		bb += I18n.t("[color=#%s]%s has since evolved — this route is closed.[/color]\n") % [C_DIM, name]
	elif owned > 0 and svc != null:
		actions.append({"kind": "evo_stone", "evo_uid": uid, "item": stone,
			"style": "good", "label": I18n.t("Use %s now") % iname})
	else:
		actions.append({"label": I18n.t("Buy in League Store"), "screen": "items"})
	actions.append({"label": I18n.t("View Squad"), "screen": "squad"})
	return {"bbcode": bb, "actions": actions, "banner": {}}

# ----------------------------------------------------------------- evo_done

func _done(msg: Dictionary) -> Dictionary:
	var from_id := int(msg.get("evo_from", 0))
	var to_id := int(msg.get("evo_to", 0))
	var inst: Dictionary = GameState.squad_member(str(msg.get("evo_uid", "")))
	var bb := I18n.t("[color=#%s][b]EVOLUTION COMPLETE[/b][/color]\n") % C_DIM
	bb += "[color=#%s]%s[/color]\n\n" % [C_WHITE, str(msg.get("body", ""))]
	if from_id > 0 and to_id > 0:
		bb += _compare_block(from_id, to_id, inst)
		bb += (I18n.t("\n[color=#%s]Its pre-evolution learnset was merged — the old ") +
			I18n.t("techniques stay available on the training ground.[/color]\n")) % C_DIM
	var actions: Array = [{"label": I18n.t("View Squad"), "screen": "squad"}]
	if not inst.is_empty():
		actions.append({"label": I18n.t("Go to Training"), "screen": "training"})
	return {"bbcode": bb, "actions": actions, "banner": {}}


# ------------------------------------------------------------------ helpers

## Where the mon stands right now: level / effective level / dev / morale.
func _method_block(msg: Dictionary, inst: Dictionary) -> String:
	if inst.is_empty():
		return I18n.t("[color=#%s]%s is no longer in the squad — the offer lapsed.[/color]\n") % \
			[C_DIM, _mon_name(inst, msg)]
	var svc := _svc()
	var uid := str(inst.get("uid", ""))
	var bb := I18n.t("[color=#%s][b]WHERE IT STANDS[/b][/color]\n") % C_DIM
	var lv := int(inst.get("level", 1))
	if svc != null:
		bb += I18n.t("[color=#%s]Lv %d — effective Lv [b]%d[/b] with +%d from %d training development points · morale %d · condition %d%%[/color]\n") % \
			[C_WHITE, lv, svc.effective_level(inst), svc.dev_levels(uid),
			svc.dev_points(uid), int(inst.get("morale", 0)), int(inst.get("condition", 0))]
	match str(msg.get("evo_method", "")):
		"level":
			bb += I18n.t("[color=#%s]Route: level threshold reached through matches and training.[/color]\n") % C_DIM
		"development":
			bb += I18n.t("[color=#%s]Route: development milestone — the staff's long-term work paying off.[/color]\n") % C_DIM
	return bb + "\n"


## Side-by-side species block: typing + every base stat with its delta.
func _compare_block(from_id: int, to_id: int, _inst: Dictionary) -> String:
	var f: Dictionary = DataStore.species(from_id)
	var t: Dictionary = DataStore.species(to_id)
	if f.is_empty() or t.is_empty():
		return ""
	var fb: Dictionary = f.get("base", {})
	var tb: Dictionary = t.get("base", {})
	var f_tot := 0
	var t_tot := 0
	for k in STAT_KEYS:
		f_tot += int(fb.get(k, 0))
		t_tot += int(tb.get(k, 0))
	var bb := I18n.t("[color=#%s][b]WHAT CHANGES[/b][/color]\n") % C_DIM
	bb += I18n.t("[color=#%s][b]%s[/b][/color] [color=#%s](%s · base %d)[/color]  ->  [color=#%s][b]%s[/b][/color] [color=#%s](%s · base %d, %+d)[/color]\n") % \
		[C_WHITE, str(f.get("name", "?")), C_DIM, _types(f), f_tot,
		C_ACC, str(t.get("name", "?")), C_DIM, _types(t), t_tot, t_tot - f_tot]
	var parts: Array = []
	for k in STAT_KEYS:
		var d := int(tb.get(k, 0)) - int(fb.get(k, 0))
		var col := C_GOOD if d > 0 else (C_BAD if d < 0 else C_DIM)
		parts.append(I18n.t("[color=#%s]%s %d -> %d (%+d)[/color]") % [col, I18n.t(str(STAT_NAMES[k])),
			int(fb.get(k, 0)), int(tb.get(k, 0)), d])
	bb += "  ".join(PackedStringArray(parts)) + "\n"
	var f_ab := str(f.get("ability", ""))
	var t_ab := str(t.get("ability", ""))
	if f_ab != t_ab:
		bb += I18n.t("[color=#%s]Ability: %s -> %s[/color]\n") % [C_DIM,
			DataStore.ability_name(f_ab), DataStore.ability_name(t_ab)]
	var extra: Array = []
	for mv in t.get("learnset", []):
		if not f.get("learnset", []).has(mv):
			extra.append(str(mv))
	if not extra.is_empty():
		bb += I18n.t("[color=#%s]Unlocks in training: %s[/color]\n") % [C_DIM,
			", ".join(PackedStringArray(extra.slice(0, 8))) + (I18n.t(" +%d more") % (extra.size() - 8) if extra.size() > 8 else "")]
	return bb


func _types(sp: Dictionary) -> String:
	return I18n.types_join(sp.get("types", []) as Array, " / ")


func _mon_name(inst: Dictionary, msg: Dictionary) -> String:
	if not inst.is_empty():
		var nick: Variant = inst.get("nickname")
		if nick != null and str(nick) != "":
			return str(nick)
		return str(inst.get("species", "?"))
	var title := str(msg.get("title", ""))
	var cut := title.find(I18n.t(" is ready"))
	if cut < 0:
		cut = title.find(I18n.t(" could evolve"))
	return title.substr(0, cut) if cut > 0 else I18n.t("The Pokémon")


func _money(v: int) -> String:
	var cur := str(GameState.world["meta"].get("currency", "$"))
	return cur + I18n.number(absi(v))
