extends RefCounted
## Commentary generator for the live match viewer.
## Turns raw BattleEngine events into varied, punchy ticker lines.
## All functions are static; the runner passes a seeded RNG so a given
## match always reads the same way.

const C_DIM := "6a7188"
const C_TEXT := "b9bfd0"
const C_GOOD := "57c979"
const C_BAD := "e06060"
const C_GOLD := "e0b050"
const C_ACCENT := "9a8dff"
const C_WHITE := "f2f4fa"

const STAT_NAMES := {
	"atk": "Attack", "def": "Defence", "spa": "Sp. Attack", "spd": "Sp. Defence",
	"spe": "Speed", "acc": "Accuracy", "eva": "Evasion",
}


## Is this raw engine event a "key moment" for key-moments-only mode?
static func is_key_event(e: Dictionary) -> bool:
	match str(e.get("t", "")):
		"faint", "battle_end", "battle_start":
			return true
		"damage":
			if e.get("recoil", false):
				return false
			var frac := _frac(e)
			return (bool(e.get("crit", false)) and frac >= 0.18) or frac >= 0.38 \
				or float(e.get("effectiveness", 1.0)) >= 2.0 and frac >= 0.25
		"status_applied":
			return str(e.get("status", "")) in ["sleep", "freeze"]
		"switch":
			return bool(e.get("forced", false))
		"item_used":
			return true
		"held_item":
			return str(e.get("effect", "")) == "sash"
	return false


## Generate 0..n bbcode ticker lines for an event.
## ctx: {player_side, short:[String,String], remaining:[int,int],
##       battle_no, wins:[int,int], turn}
static func lines_for(e: Dictionary, ctx: Dictionary, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var pside := int(ctx.get("player_side", 0))
	var shorts: Array = ctx.get("short", ["HOM", "AWY"])
	match str(e.get("t", "")):
		"battle_start":
			out.append(_line("[b]Battle %d of 3 is underway.[/b]" % int(ctx.get("battle_no", 1)), C_ACCENT, true))
		"turn_start":
			pass  # the view renders its own divider
		"move_used":
			var mv: Dictionary = DataStore.move(str(e.get("move", "")))
			if not mv.is_empty() and str(mv.get("category", "")) == "status":
				out.append(_line(_pick(rng, [
					"%s calls for %s." % [e["pokemon"], e["move"]],
					"%s takes a breather and uses %s." % [e["pokemon"], e["move"]],
					"%s goes to the playbook: %s." % [e["pokemon"], e["move"]],
				]), C_TEXT, false))
		"damage":
			_damage_lines(e, ctx, rng, out)
		"miss":
			out.append(_line(_pick(rng, [
				"%s's %s misses the mark!" % [e["pokemon"], e["move"]],
				"It sails wide — %s wastes a turn on %s." % [e["pokemon"], e["move"]],
				"%s whiffs %s completely!" % [e["pokemon"], e["move"]],
			]), C_TEXT, false))
		"faint":
			var loser_side := int(e.get("side", 0))
			var club: String = shorts[loser_side]
			var left := maxi(0, int(ctx.get("remaining", [6, 6])[loser_side]))
			var col := C_BAD if loser_side == pside else C_GOOD
			out.append(_line("[b]" + _pick(rng, [
				"DOWN GOES %s! %s have %d left standing." % [str(e["pokemon"]).to_upper(), club, left],
				"%s crumples — a real blow for %s. %d remain." % [e["pokemon"], club, left],
				"That's it for %s! The %s bench is down to %d." % [e["pokemon"], club, left],
			]) + "[/b]", col, true))
		"switch":
			if e.get("first", false):
				out.append(_line("%s send out %s." % [shorts[int(e["side"])], e["to"]], C_TEXT, false))
			elif e.get("forced", false):
				out.append(_line(_pick(rng, [
					"%s is carried off. %s steps up for %s." % [e.get("from", "?"), e["to"], shorts[int(e["side"])]],
					"Forced change for %s — in comes %s." % [shorts[int(e["side"])], e["to"]],
				]), C_TEXT, false))
			else:
				out.append(_line(_pick(rng, [
					"%s roll the dice: %s makes way for %s." % [shorts[int(e["side"])], e.get("from", "?"), e["to"]],
					"Tactical switch — %s is recalled, %s enters the fray." % [e.get("from", "?"), e["to"]],
					"%s off, %s on. The bench gets involved." % [e.get("from", "?"), e["to"]],
				]), C_ACCENT, false))
		"status_applied":
			_status_lines(e, ctx, rng, out)
		"status_tick":
			out.append(_line("%s is hurt by its %s (-%d%%)." %
				[e["pokemon"], "burn" if e["status"] == "burn" else "poison", _pct(e)], C_DIM, false))
		"stat_change":
			var d := int(e.get("delta", 0))
			var verb := ("rises sharply" if d >= 2 else "rises") if d > 0 else ("falls sharply" if d <= -2 else "falls")
			out.append(_line("%s's %s %s (%+d)." %
				[e["pokemon"], STAT_NAMES.get(str(e["stat"]), str(e["stat"])), verb, d], C_TEXT, false))
		"heal":
			out.append(_line(_pick(rng, [
				"%s recovers %d HP." % [e["pokemon"], int(e.get("amount", 0))],
				"%s drinks in some energy — %d HP restored." % [e["pokemon"], int(e.get("amount", 0))],
			]), C_GOOD, false))
		"flinch":
			out.append(_line("%s flinches — no attack this turn!" % e["pokemon"], C_TEXT, false))
		"confused_hit":
			out.append(_line("%s hurts itself in its confusion!" % e["pokemon"], C_GOLD, false))
		"asleep":
			if e.get("frozen", false):
				out.append(_line("%s is frozen solid and cannot move." % e["pokemon"], C_DIM, false))
			else:
				out.append(_line("%s is fast asleep." % e["pokemon"], C_DIM, false))
		"paralyzed":
			out.append(_line("%s is fully paralysed!" % e["pokemon"], C_GOLD, false))
		"item_used":
			var mine := int(e.get("side", 0)) == pside
			var who: String = "You" if mine else str(shorts[int(e.get("side", 0))])
			var cost: String = "us" if mine else "them"
			out.append(_line("[b]" + _pick(rng, [
				"%s reach into the bag — %s used on %s!" % [who, e.get("item_name", "an item"), e.get("pokemon", "?")],
				"%s make the call from the dugout: %s for %s!" % [who, e.get("item_name", "an item"), e.get("pokemon", "?")],
				"Item play by %s — %s goes to %s. That costs %s the turn." % [who, e.get("item_name", "an item"), e.get("pokemon", "?"), cost],
			]) + "[/b]", C_ACCENT, true))
		"held_item":
			_held_item_lines(e, rng, out)
		"commentary_hook":
			if _hook_worth(str(e.get("text", ""))):
				out.append(_line(str(e["text"]), C_GOLD, false))
		"battle_end":
			var w := int(e.get("winner", 0))
			var wins: Array = ctx.get("wins", [0, 0])
			var col2 := C_GOOD if w == pside else C_BAD
			out.append(_line("[b]BATTLE %d GOES TO %s! Series: %s %d–%d %s (%d turns)[/b]" %
				[int(ctx.get("battle_no", 1)), shorts[w], shorts[0], wins[0], wins[1], shorts[1],
				int(e.get("turns", 0))], col2, true))
	return out


## Synthetic momentum-swing line (injected by the runner, not from an engine event).
static func swing_line(toward_short: String, toward_player: bool, rng: RandomNumberGenerator) -> Dictionary:
	var col := C_GOOD if toward_player else C_BAD
	return _line("[b]" + _pick(rng, [
		"Momentum swings the way of %s!" % toward_short,
		"The tide is turning — %s are on top now!" % toward_short,
		"%s have wrestled back control of this battle!" % toward_short,
	]) + "[/b]", col, true)


# ------------------------------------------------------------------ internals

## Engine commentary_hook lines worth printing (item flavour the event stream
## can't otherwise reconstruct). Everything else duplicates our own lines.
static func _hook_worth(text: String) -> bool:
	for k in ["Quick Claw", "Focus Sash", "Rocky Helmet", "Guard Spec", "crunches its",
			"eats its", "back on its feet", "pumped up", "protective veil", "shielded by"]:
		if text.contains(k):
			return true
	return false


static func _held_item_lines(e: Dictionary, _rng: RandomNumberGenerator, out: Array) -> void:
	var n := str(e.get("pokemon", "?"))
	var item := str(e.get("item_name", "held item"))
	match str(e.get("effect", "")):
		"end_turn_heal":
			out.append(_line("%s nibbles at its %s and recovers." % [n, item], C_DIM, false))
		"sitrus":
			out.append(_line("%s bites into its %s at just the right moment!" % [n, item], C_GOLD, false))
		"choice_lock":
			out.append(_line("%s's %s locks it into that move." % [n, item], C_DIM, false))
		"sash":
			out.append(_line("[b]%s's %s is spent — it survives on 1 HP![/b]" % [n, item], C_GOLD, true))
		"shell_bell":
			out.append(_line("%s's %s chimes — a sliver of HP back." % [n, item], C_DIM, false))
		"kings_rock":
			out.append(_line("%s's %s rattles its target!" % [n, item], C_DIM, false))
		"bright_powder":
			out.append(_line("%s's %s clouds the attacker's aim!" % [n, item], C_DIM, false))
		"life_orb", "quick_claw", "cure_berry", "rocky_helmet":
			pass  # covered by hooks / recoil / damage lines
		_:
			pass

static func _damage_lines(e: Dictionary, ctx: Dictionary, rng: RandomNumberGenerator, out: Array) -> void:
	var pside := int(ctx.get("player_side", 0))
	if e.get("recoil", false):
		out.append(_line("%s is hurt by recoil (-%d%%)." % [e["pokemon"], _pct(e)], C_DIM, false))
		return
	var eff := float(e.get("effectiveness", 1.0))
	var atk := str(e.get("by", "?"))
	var mv := str(e.get("move", "?"))
	var vic := str(e.get("pokemon", "?"))
	if eff == 0.0:
		out.append(_line("%s's %s has no effect on %s — poor call!" % [atk, mv, vic], C_DIM, false))
		return
	var frac := _frac(e)
	var pct := _pct(e)
	var crit := bool(e.get("crit", false))
	var good_for_player: bool = int(e.get("by_side", 1 - int(e.get("side", 0)))) == pside
	var body: String
	if frac >= 0.45:
		body = _pick(rng, [
			"HUGE hit! %s's %s tears into %s — %d%% gone in one blow!" % [atk, mv, vic, pct],
			"%s unloads %s and %s takes a massive %d%% hit!" % [atk, mv, vic, pct],
			"%s is rocked! %s's %s rips away %d%% of its health!" % [vic, atk, mv, pct],
		])
	elif frac >= 0.22:
		body = _pick(rng, [
			"%s's %s slams into %s for %d%%." % [atk, mv, vic, pct],
			"Heavy blow — %s catches %s with %s (%d%%)." % [atk, vic, mv, pct],
			"%s connects with %s and %s feels it: -%d%%." % [atk, mv, vic, pct],
		])
	elif frac >= 0.08:
		body = _pick(rng, [
			"%s lands %s on %s (-%d%%)." % [atk, mv, vic, pct],
			"%s's %s finds its target — %s down %d%%." % [atk, mv, vic, pct],
		])
	else:
		body = _pick(rng, [
			"%s chips away with %s (-%d%%)." % [atk, mv, pct],
			"%s's %s barely scratches %s." % [atk, mv, vic],
		])
	var prefix := ""
	if crit:
		prefix = "[color=#%s][b]CRIT![/b][/color] " % C_GOLD
	var suffix := ""
	if eff >= 2.0:
		suffix = " " + _pick(rng, ["It's super effective!", "%s never saw it coming!" % vic, "A brutal type matchup!"])
	elif eff < 1.0:
		suffix = " ...but it's resisted."
	var col := C_TEXT
	var key := is_key_event(e)
	if key:
		col = C_GOOD if good_for_player else C_BAD
	out.append(_line(prefix + body + suffix, col, key))
	var hp_left := float(e.get("hp_left", 0))
	var max_hp := maxf(float(e.get("max_hp", 1)), 1.0)
	if hp_left > 0 and hp_left / max_hp <= 0.15 and frac >= 0.08:
		out.append(_line("%s clings on at %d%%!" % [vic, int(100.0 * hp_left / max_hp)], C_GOLD, false))


static func _status_lines(e: Dictionary, _ctx: Dictionary, rng: RandomNumberGenerator, out: Array) -> void:
	var n := str(e.get("pokemon", "?"))
	match str(e.get("status", "")):
		"burn":
			out.append(_line("%s is scorched — that burn will bite every turn." % n, C_GOLD, false))
		"para":
			out.append(_line(_pick(rng, ["%s is paralysed! Its legs buckle." % n,
				"%s seizes up — paralysis!" % n]), C_GOLD, false))
		"sleep":
			out.append(_line("[b]%s falls fast asleep — a huge opening here![/b]" % n, C_GOLD, true))
		"poison":
			out.append(_line("%s is poisoned — the clock is ticking." % n, C_GOLD, false))
		"freeze":
			out.append(_line("[b]%s is frozen solid![/b]" % n, C_GOLD, true))
		"confused":
			out.append(_line("%s is confused and staggering!" % n, C_GOLD, false))
		"woke":
			out.append(_line("%s wakes up!" % n, C_TEXT, false))
		"thawed":
			out.append(_line("%s thaws out!" % n, C_TEXT, false))


static func _line(text: String, color: String, key: bool) -> Dictionary:
	return {"text": "[color=#%s]%s[/color]" % [color, text], "key": key}


static func _pick(rng: RandomNumberGenerator, options: Array) -> String:
	return options[rng.randi() % options.size()]


static func _frac(e: Dictionary) -> float:
	## Fraction of max HP actually removed (overkill clamped to what was left).
	var amount := float(e.get("amount", 0))
	if e.has("hp_before"):
		amount = minf(amount, float(e["hp_before"]))
	return amount / maxf(float(e.get("max_hp", 1)), 1.0)


static func _pct(e: Dictionary) -> int:
	return int(round(100.0 * _frac(e)))
