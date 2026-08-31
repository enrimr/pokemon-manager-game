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
		"weather_start":
			return true
		"ability_triggered":
			return str(e.get("effect", "")) in ["sturdy", "immune", "absorb"]
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
			if str(e.get("mode", "")) == "doubles":
				out.append(_line(I18n.t("[b]Battle %d of 3 is underway — 2v2 DOUBLES! Two on the floor for each side; targeting wins these.[/b]")
					% int(ctx.get("battle_no", 1)), C_ACCENT, true))
			else:
				out.append(_line(I18n.t("[b]Battle %d of 3 is underway.[/b]") % int(ctx.get("battle_no", 1)), C_ACCENT, true))
		"turn_start":
			pass  # the view renders its own divider
		"no_target":
			out.append(_line(I18n.t("%s's %s finds nothing left to hit!") %
				[e.get("pokemon", "?"), I18n.t(str(e.get("move", "?")))], C_DIM, false))
		"move_used":
			var mv: Dictionary = DataStore.move(str(e.get("move", "")))
			if bool(e.get("spread", false)):
				out.append(_line(_pick(rng, [
					I18n.t("%s unleashes %s across the whole field!") % [e["pokemon"], I18n.t(str(e["move"]))],
					I18n.t("%s goes wide with %s — everyone braces!") % [e["pokemon"], I18n.t(str(e["move"]))],
				]), C_TEXT, false))
			elif e.has("target") and not mv.is_empty() and str(mv.get("category", "")) != "status":
				out.append(_line(I18n.t("%s singles out %s — %s!") %
					[e["pokemon"], e["target"], I18n.t(str(e["move"]))], C_TEXT, false))
			elif not mv.is_empty() and str(mv.get("category", "")) == "status":
				out.append(_line(_pick(rng, [
					I18n.t("%s calls for %s.") % [e["pokemon"], I18n.t(str(e["move"]))],
					I18n.t("%s takes a breather and uses %s.") % [e["pokemon"], I18n.t(str(e["move"]))],
					I18n.t("%s goes to the playbook: %s.") % [e["pokemon"], I18n.t(str(e["move"]))],
				]), C_TEXT, false))
		"damage":
			_damage_lines(e, ctx, rng, out)
		"miss":
			out.append(_line(_pick(rng, [
				I18n.t("%s's %s misses the mark!") % [e["pokemon"], I18n.t(str(e["move"]))],
				I18n.t("It sails wide — %s wastes a turn on %s.") % [e["pokemon"], I18n.t(str(e["move"]))],
				I18n.t("%s whiffs %s completely!") % [e["pokemon"], I18n.t(str(e["move"]))],
			]), C_TEXT, false))
		"faint":
			var loser_side := int(e.get("side", 0))
			var club: String = shorts[loser_side]
			var left := maxi(0, int(ctx.get("remaining", [6, 6])[loser_side]))
			var col := C_BAD if loser_side == pside else C_GOOD
			out.append(_line("[b]" + _pick(rng, [
				I18n.t("DOWN GOES %s! %s have %d left standing.") % [str(e["pokemon"]).to_upper(), club, left],
				I18n.t("%s crumples — a real blow for %s. %d remain.") % [e["pokemon"], club, left],
				I18n.t("That's it for %s! The %s bench is down to %d.") % [e["pokemon"], club, left],
			]) + "[/b]", col, true))
		"switch":
			if e.get("first", false):
				out.append(_line(I18n.t("%s send out %s.") % [shorts[int(e["side"])], e["to"]], C_TEXT, false))
			elif e.get("forced", false):
				out.append(_line(_pick(rng, [
					I18n.t("%s is carried off. %s steps up for %s.") % [e.get("from", "?"), e["to"], shorts[int(e["side"])]],
					I18n.t("Forced change for %s — in comes %s.") % [shorts[int(e["side"])], e["to"]],
				]), C_TEXT, false))
			else:
				out.append(_line(_pick(rng, [
					I18n.t("%s roll the dice: %s makes way for %s.") % [shorts[int(e["side"])], e.get("from", "?"), e["to"]],
					I18n.t("Tactical switch — %s is recalled, %s enters the fray.") % [e.get("from", "?"), e["to"]],
					I18n.t("%s off, %s on. The bench gets involved.") % [e.get("from", "?"), e["to"]],
				]), C_ACCENT, false))
		"status_applied":
			_status_lines(e, ctx, rng, out)
		"status_tick":
			out.append(_line(I18n.t("%s is hurt by its %s (-%d%%).") %
				[e["pokemon"], I18n.t("burn") if e["status"] == "burn" else I18n.t("poison"), _pct(e)], C_DIM, false))
		"stat_change":
			var d := int(e.get("delta", 0))
			var verb := (I18n.t("rises sharply") if d >= 2 else I18n.t("rises")) if d > 0 else (I18n.t("falls sharply") if d <= -2 else I18n.t("falls"))
			out.append(_line(I18n.t("%s's %s %s (%+d).") %
				[e["pokemon"], I18n.t(STAT_NAMES.get(str(e["stat"]), str(e["stat"]))), verb, d], C_TEXT, false))
		"heal":
			out.append(_line(_pick(rng, [
				I18n.t("%s recovers %d HP.") % [e["pokemon"], int(e.get("amount", 0))],
				I18n.t("%s drinks in some energy — %d HP restored.") % [e["pokemon"], int(e.get("amount", 0))],
			]), C_GOOD, false))
		"flinch":
			out.append(_line(I18n.t("%s flinches — no attack this turn!") % e["pokemon"], C_TEXT, false))
		"confused_hit":
			out.append(_line(I18n.t("%s hurts itself in its confusion!") % e["pokemon"], C_GOLD, false))
		"asleep":
			if e.get("frozen", false):
				out.append(_line(I18n.t("%s is frozen solid and cannot move.") % e["pokemon"], C_DIM, false))
			else:
				out.append(_line(I18n.t("%s is fast asleep.") % e["pokemon"], C_DIM, false))
		"paralyzed":
			out.append(_line(I18n.t("%s is fully paralysed!") % e["pokemon"], C_GOLD, false))
		"item_used":
			var mine := int(e.get("side", 0)) == pside
			var who: String = I18n.t("You") if mine else str(shorts[int(e.get("side", 0))])
			var cost: String = I18n.t("us") if mine else I18n.t("them")
			var used_item: String = I18n.t(str(e.get("item_name", "an item")))
			out.append(_line("[b]" + _pick(rng, [
				I18n.t("%s reach into the bag — %s used on %s!") % [who, used_item, e.get("pokemon", "?")],
				I18n.t("%s make the call from the dugout: %s for %s!") % [who, used_item, e.get("pokemon", "?")],
				I18n.t("Item play by %s — %s goes to %s. That costs %s the turn.") % [who, used_item, e.get("pokemon", "?"), cost],
			]) + "[/b]", C_ACCENT, true))
		"held_item":
			_held_item_lines(e, rng, out)
		"ability_triggered":
			_ability_lines(e, rng, out)
		"weather_start":
			var wk := str(e.get("kind", ""))
			var opener: String = {
				"sun": I18n.t("The sunlight turns HARSH — fire moves will scorch, water fizzles!"),
				"rain": I18n.t("Rain hammers the arena — water moves surge, fire sputters!"),
				"sand": I18n.t("A sandstorm rips across the pitch — it will rake everything unshielded!"),
				"hail": I18n.t("Hail pelts down — anything that isn't ice will feel it!"),
			}.get(wk, I18n.t("The weather turns!"))
			var src := ""
			if str(e.get("source", "")) == "ability":
				src = I18n.t(" %s's presence did that.") % str(e.get("pokemon", "?"))
			elif e.get("pokemon", null) != null and str(e.get("pokemon", "")) != "":
				src = I18n.t(" %s made it happen.") % str(e.get("pokemon", ""))
			out.append(_line("[b]%s[/b]%s" % [opener, src], C_GOLD, true))
		"weather_end":
			out.append(_line(str({
				"sun": I18n.t("The harsh sunlight fades — conditions level out."),
				"rain": I18n.t("The rain lets up — conditions level out."),
				"sand": I18n.t("The sandstorm subsides — you can see the pitch again."),
				"hail": I18n.t("The hail stops — a mercy for the outfield."),
			}.get(str(e.get("kind", "")), I18n.t("The skies clear."))), C_DIM, false))
		"weather_chip":
			out.append(_line(I18n.t("%s is battered by the %s (-%d%%).") % [e.get("pokemon", "?"),
				I18n.t("sandstorm") if str(e.get("kind", "")) == "sand" else I18n.t("hail"), _pct(e)], C_DIM, false))
		"commentary_hook":
			# Raw engine hook lines are English-only prose; the localized
			# held_item/ability lines reconstruct the same beats, so only
			# pass them through on English locales.
			if TranslationServer.get_locale().begins_with("en") and _hook_worth(str(e.get("text", ""))):
				out.append(_line(str(e["text"]), C_GOLD, false))
		"battle_end":
			var w := int(e.get("winner", 0))
			var wins: Array = ctx.get("wins", [0, 0])
			var col2 := C_GOOD if w == pside else C_BAD
			out.append(_line(I18n.t("[b]BATTLE %d GOES TO %s! Series: %s %d–%d %s (%d turns)[/b]") %
				[int(ctx.get("battle_no", 1)), shorts[w], shorts[0], wins[0], wins[1], shorts[1],
				int(e.get("turns", 0))], col2, true))
	return out


## Synthetic momentum-swing line (injected by the runner, not from an engine event).
static func swing_line(toward_short: String, toward_player: bool, rng: RandomNumberGenerator) -> Dictionary:
	var col := C_GOOD if toward_player else C_BAD
	return _line("[b]" + _pick(rng, [
		I18n.t("Momentum swings the way of %s!") % toward_short,
		I18n.t("The tide is turning — %s are on top now!") % toward_short,
		I18n.t("%s have wrestled back control of this battle!") % toward_short,
	]) + "[/b]", col, true)


# ------------------------------------------------------------------ internals

## Engine commentary_hook lines worth printing (item flavour the event stream
## can't otherwise reconstruct). Everything else duplicates our own lines.
static func _hook_worth(text: String) -> bool:
	# NOTE(i18n): engine hook lines are always English — match raw keywords.
	for k in ["Quick Claw", "Focus Sash", "Rocky Helmet", "Guard Spec", "crunches its",
			"eats its", "back on its feet", "pumped up", "protective veil", "shielded by"]:
		if text.contains(k):
			return true
	return false


static func _held_item_lines(e: Dictionary, _rng: RandomNumberGenerator, out: Array) -> void:
	var n := str(e.get("pokemon", "?"))
	var item := I18n.t(str(e.get("item_name", "held item")))
	match str(e.get("effect", "")):
		"end_turn_heal":
			out.append(_line(I18n.t("%s nibbles at its %s and recovers.") % [n, item], C_DIM, false))
		"sitrus":
			out.append(_line(I18n.t("%s bites into its %s at just the right moment!") % [n, item], C_GOLD, false))
		"choice_lock":
			out.append(_line(I18n.t("%s's %s locks it into that move.") % [n, item], C_DIM, false))
		"sash":
			out.append(_line(I18n.t("[b]%s's %s is spent — it survives on 1 HP![/b]") % [n, item], C_GOLD, true))
		"shell_bell":
			out.append(_line(I18n.t("%s's %s chimes — a sliver of HP back.") % [n, item], C_DIM, false))
		"kings_rock":
			out.append(_line(I18n.t("%s's %s rattles its target!") % [n, item], C_DIM, false))
		"bright_powder":
			out.append(_line(I18n.t("%s's %s clouds the attacker's aim!") % [n, item], C_DIM, false))
		"life_orb", "quick_claw", "cure_berry", "rocky_helmet":
			pass  # covered by hooks / recoil / damage lines
		_:
			pass

static func _ability_lines(e: Dictionary, rng: RandomNumberGenerator, out: Array) -> void:
	var n := str(e.get("pokemon", "?"))
	var ab := I18n.t(str(e.get("ability_name", e.get("ability", "ability"))))
	match str(e.get("effect", "")):
		"entry_stat":
			out.append(_line(I18n.t("%s's [b]%s[/b] makes itself felt the moment it steps on!") % [n, ab], C_ACCENT, false))
		"weather":
			pass  # the weather_start line right after credits the Pokémon
		"immune":
			out.append(_line(I18n.t("[b]No effect — %s's %s shrugs the attack off completely![/b]") % [n, ab], C_GOLD, true))
		"absorb":
			out.append(_line(I18n.t("[b]%s's %s drinks the attack right up![/b]") % [n, ab], C_GOLD, true))
		"sturdy":
			out.append(_line(I18n.t("[b]%s refuses to go down — %s keeps it standing on 1 HP![/b]") % [n, ab], C_GOLD, true))
		"contact_status", "contact_damage":
			out.append(_line(I18n.t("%s's [b]%s[/b] punishes the contact!") % [n, ab], C_ACCENT, false))
		"pinch_boost":
			out.append(_line(I18n.t("%s is in trouble — and its [b]%s[/b] roars to life!") % [n, ab], C_ACCENT, false))
		"resist":
			out.append(_line(I18n.t("%s's [b]%s[/b] blunts the blow.") % [n, ab], C_ACCENT, false))
		"reflect_status":
			out.append(_line(I18n.t("%s's [b]%s[/b] throws the condition right back!") % [n, ab], C_ACCENT, false))
		"heal_status_on_switch":
			out.append(_line(I18n.t("%s's [b]%s[/b] cures it on the way to the bench.") % [n, ab], C_ACCENT, false))
		"end_turn_stat", "end_turn_cure", "weather_heal":
			out.append(_line(_pick(rng, [
				I18n.t("%s's [b]%s[/b] ticks over at the end of the turn.") % [n, ab],
				I18n.t("End of the turn — %s's [b]%s[/b] does its quiet work.") % [n, ab],
			]), C_ACCENT, false))
		"sleep_half":
			out.append(_line(I18n.t("%s's [b]%s[/b] shakes off the drowsiness early.") % [n, ab], C_ACCENT, false))
		"no_stat_drop", "no_atk_drop", "no_acc_drop":
			out.append(_line(I18n.t("%s's [b]%s[/b] blocks the stat drop.") % [n, ab], C_ACCENT, false))
		"immune_status", "immune_flinch", "immune_confuse", "no_secondary_effects":
			out.append(_line(I18n.t("%s's [b]%s[/b] protects it — no dice.") % [n, ab], C_ACCENT, false))
		"no_recoil":
			pass  # silent quality-of-life ability; a line every hit would spam
		_:
			out.append(_line(I18n.t("%s's [b]%s[/b] comes into play.") % [n, ab], C_ACCENT, false))


static func _damage_lines(e: Dictionary, ctx: Dictionary, rng: RandomNumberGenerator, out: Array) -> void:
	var pside := int(ctx.get("player_side", 0))
	if e.get("recoil", false):
		out.append(_line(I18n.t("%s is hurt by recoil (-%d%%).") % [e["pokemon"], _pct(e)], C_DIM, false))
		return
	if e.get("ally_hit", false):
		if float(e.get("effectiveness", 1.0)) == 0.0:
			out.append(_line(I18n.t("%s's own %s washes over %s — no harm done.") %
				[e.get("by", "?"), I18n.t(str(e.get("move", "?"))), e["pokemon"]], C_DIM, false))
		else:
			out.append(_line(I18n.t("FRIENDLY FIRE — %s's %s clips its own partner %s (-%d%%)!") %
				[e.get("by", "?"), I18n.t(str(e.get("move", "?"))), e["pokemon"], _pct(e)], C_GOLD, false))
		return
	var eff := float(e.get("effectiveness", 1.0))
	var atk := str(e.get("by", "?"))
	var mv := str(I18n.t(str(e.get("move", "?"))))
	var vic := str(e.get("pokemon", "?"))
	if eff == 0.0:
		out.append(_line(I18n.t("%s's %s has no effect on %s — poor call!") % [atk, mv, vic], C_DIM, false))
		return
	var frac := _frac(e)
	var pct := _pct(e)
	var crit := bool(e.get("crit", false))
	var good_for_player: bool = int(e.get("by_side", 1 - int(e.get("side", 0)))) == pside
	var body: String
	if frac >= 0.45:
		body = _pick(rng, [
			I18n.t("HUGE hit! %s's %s tears into %s — %d%% gone in one blow!") % [atk, mv, vic, pct],
			I18n.t("%s unloads %s and %s takes a massive %d%% hit!") % [atk, mv, vic, pct],
			I18n.t("%s is rocked! %s's %s rips away %d%% of its health!") % [vic, atk, mv, pct],
		])
	elif frac >= 0.22:
		body = _pick(rng, [
			I18n.t("%s's %s slams into %s for %d%%.") % [atk, mv, vic, pct],
			I18n.t("Heavy blow — %s catches %s with %s (%d%%).") % [atk, vic, mv, pct],
			I18n.t("%s connects with %s and %s feels it: -%d%%.") % [atk, mv, vic, pct],
		])
	elif frac >= 0.08:
		body = _pick(rng, [
			I18n.t("%s lands %s on %s (-%d%%).") % [atk, mv, vic, pct],
			I18n.t("%s's %s finds its target — %s down %d%%.") % [atk, mv, vic, pct],
		])
	else:
		body = _pick(rng, [
			I18n.t("%s chips away with %s (-%d%%).") % [atk, mv, pct],
			I18n.t("%s's %s barely scratches %s.") % [atk, mv, vic],
		])
	var prefix := ""
	if crit:
		prefix = I18n.t("[color=#%s][b]CRIT![/b][/color] ") % C_GOLD
	var suffix := ""
	if eff >= 2.0:
		suffix = " " + _pick(rng, [I18n.t("It's super effective!"), I18n.t("%s never saw it coming!") % vic, I18n.t("A brutal type matchup!")])
	elif eff < 1.0:
		suffix = I18n.t(" ...but it's resisted.")
	var col := C_TEXT
	var key := is_key_event(e)
	if key:
		col = C_GOOD if good_for_player else C_BAD
	out.append(_line(prefix + body + suffix, col, key))
	var hp_left := float(e.get("hp_left", 0))
	var max_hp := maxf(float(e.get("max_hp", 1)), 1.0)
	if hp_left > 0 and hp_left / max_hp <= 0.15 and frac >= 0.08:
		out.append(_line(I18n.t("%s clings on at %d%%!") % [vic, int(100.0 * hp_left / max_hp)], C_GOLD, false))


static func _status_lines(e: Dictionary, _ctx: Dictionary, rng: RandomNumberGenerator, out: Array) -> void:
	var n := str(e.get("pokemon", "?"))
	match str(e.get("status", "")):
		"burn":
			out.append(_line(I18n.t("%s is scorched — that burn will bite every turn.") % n, C_GOLD, false))
		"para":
			out.append(_line(_pick(rng, [I18n.t("%s is paralysed! Its legs buckle.") % n,
				I18n.t("%s seizes up — paralysis!") % n]), C_GOLD, false))
		"sleep":
			out.append(_line(I18n.t("[b]%s falls fast asleep — a huge opening here![/b]") % n, C_GOLD, true))
		"poison":
			out.append(_line(I18n.t("%s is poisoned — the clock is ticking.") % n, C_GOLD, false))
		"freeze":
			out.append(_line(I18n.t("[b]%s is frozen solid![/b]") % n, C_GOLD, true))
		"confused":
			out.append(_line(I18n.t("%s is confused and staggering!") % n, C_GOLD, false))
		"woke":
			out.append(_line(I18n.t("%s wakes up!") % n, C_TEXT, false))
		"thawed":
			out.append(_line(I18n.t("%s thaws out!") % n, C_TEXT, false))


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
