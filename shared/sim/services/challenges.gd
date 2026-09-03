class_name ChallengeService
extends RefCounted
## STREET CHALLENGES (challenges piece) — random exhibition battles OUTSIDE
## the league, as a wink to the original games (user idea): a Bug Catcher
## blocks your path, a Hiker wants a scrap, a gym leader passes through town,
## and — rarely — Ash Ketchum, Gary Oak or Professor Oak himself lays down a
## challenge. Friendlies run on MatchRunner's exhibition mode (never touch
## the table); WINNING pays real money and drops real items into the bag.
##
## Flow: a challenge lands in the inbox (urgent, expires in %EXPIRE_DAYS%d);
## Accept spins up an exhibition MatchRunner (playable live on both shells,
## instant result available); rewards settle when you leave the full-time
## screen. Deterministic per career day, persisted with the save.

const EXPIRE_DAYS := 7
const DAILY_CHANCE := 0.055   # ~ one challenge every 2-3 weeks

static var instance: ChallengeService = null

var _gs = null
var state := {"pending": {}, "next_no": 1, "played": 0, "won": 0}

# ---------------------------------------------------------------- catalogs
## Trainer classes from the original games (levels relative to your top six).
const CLASSES := [
	{"cls": "Bug Catcher", "pool": [10, 11, 12, 13, 14, 15, 123, 127, 165, 166, 167, 168, 204, 214],
		"lv": -4, "money": 9000, "items": ["potion", "chesto_berry"]},
	{"cls": "Hiker", "pool": [66, 67, 68, 74, 75, 76, 95, 111, 112, 185, 231, 232],
		"lv": -3, "money": 11000, "items": ["super_potion", "sitrus_berry"]},
	{"cls": "Fisherman", "pool": [60, 61, 72, 73, 90, 98, 99, 118, 119, 129, 130, 222, 223],
		"lv": -3, "money": 9000, "items": ["potion", "lum_berry"]},
	{"cls": "Swimmer", "pool": [54, 55, 86, 87, 116, 117, 120, 121, 131, 134],
		"lv": -3, "money": 10000, "items": ["super_potion"]},
	{"cls": "Medium", "pool": [63, 64, 65, 79, 80, 96, 97, 102, 103, 122, 196, 203],
		"lv": -2, "money": 13000, "items": ["twisted_spoon"]},
	{"cls": "Black Belt", "pool": [56, 57, 66, 67, 68, 106, 107, 236, 237],
		"lv": -2, "money": 12000, "items": ["dire_hit"]},
	{"cls": "Bird Keeper", "pool": [16, 17, 18, 21, 22, 83, 84, 85, 163, 164, 198, 227],
		"lv": -3, "money": 10000, "items": ["sitrus_berry"]},
	{"cls": "Scientist", "pool": [81, 82, 88, 89, 100, 101, 109, 110, 137, 233],
		"lv": -2, "money": 14000, "items": ["x_sp_atk"]},
	{"cls": "Rocket Grunt", "pool": [19, 20, 23, 24, 27, 28, 41, 42, 52, 53, 88, 89, 109, 110],
		"lv": -2, "money": 16000, "items": ["guard_spec"]},
]

## Gym leaders passing through town (level +2, type-booster prize).
const LEADERS := [
	{"cls": "Gym Leader", "name": "Brock", "pool": [74, 75, 76, 95, 111, 138, 140, 246], "type": "rock"},
	{"cls": "Gym Leader", "name": "Misty", "pool": [54, 55, 120, 121, 130, 131, 116, 117], "type": "water"},
	{"cls": "Gym Leader", "name": "Lt. Surge", "pool": [25, 26, 81, 82, 100, 101, 125, 135], "type": "electric"},
	{"cls": "Gym Leader", "name": "Erika", "pool": [43, 44, 45, 70, 71, 102, 103, 114, 182], "type": "grass"},
	{"cls": "Gym Leader", "name": "Koga", "pool": [23, 24, 41, 42, 88, 89, 109, 110, 169], "type": "poison"},
	{"cls": "Gym Leader", "name": "Sabrina", "pool": [63, 64, 65, 79, 80, 96, 97, 122, 196], "type": "psychic"},
	{"cls": "Gym Leader", "name": "Blaine", "pool": [58, 59, 77, 78, 126, 136, 219, 229], "type": "fire"},
	{"cls": "Gym Leader", "name": "Giovanni", "pool": [31, 34, 51, 105, 111, 112, 115, 128], "type": "ground"},
	{"cls": "Gym Leader", "name": "Falkner", "pool": [16, 17, 18, 21, 22, 83, 163, 164, 227], "type": "flying"},
	{"cls": "Gym Leader", "name": "Bugsy", "pool": [11, 12, 14, 15, 123, 127, 165, 166, 212, 214], "type": "bug"},
	{"cls": "Gym Leader", "name": "Whitney", "pool": [35, 36, 39, 40, 108, 113, 128, 133, 241], "type": "normal"},
	{"cls": "Gym Leader", "name": "Morty", "pool": [92, 93, 94, 200], "type": "ghost"},
	{"cls": "Gym Leader", "name": "Chuck", "pool": [56, 57, 62, 66, 67, 68, 106, 107, 237], "type": "fighting"},
	{"cls": "Gym Leader", "name": "Jasmine", "pool": [81, 82, 95, 205, 208, 227], "type": "steel"},
	{"cls": "Gym Leader", "name": "Pryce", "pool": [86, 87, 91, 124, 131, 215, 220, 221, 225], "type": "ice"},
	{"cls": "Gym Leader", "name": "Clair", "pool": [130, 147, 148, 149, 230], "type": "dragon"},
]

## The legends (level +5; stones + premium held items; big appearance money).
const LEGENDS := [
	{"cls": "Pokémon Trainer", "name": "Ash Ketchum", "team": [25, 6, 1, 7, 143, 214]},
	{"cls": "Pokémon Trainer", "name": "Gary Oak", "team": [9, 197, 59, 34, 65, 212]},
	{"cls": "Champion", "name": "Lance", "team": [149, 148, 130, 142, 6, 230]},
	{"cls": "Professor", "name": "Professor Oak", "team": [128, 103, 59, 130, 143, 149]},
	{"cls": "Pokémon Trainer", "name": "Red", "team": [25, 3, 6, 9, 143, 196]},
]
const LEGEND_ITEMS := ["fire_stone", "water_stone", "thunder_stone", "leaf_stone",
	"moon_stone", "sun_stone", "leftovers", "choice_band", "choice_scarf"]


func on_career_started(gs) -> void:
	_gs = gs
	instance = self


func save_state() -> Dictionary:
	return state.duplicate(true)


func load_state(s: Dictionary) -> void:
	state = s
	if not state.has("pending"):
		state["pending"] = {}


# ---------------------------------------------------------------- daily tick

func on_day(gs, date: String) -> void:
	_gs = gs
	instance = self
	var pending: Dictionary = state.get("pending", {})
	if not pending.is_empty():
		if Season.days_between(str(pending.get("date", date)), date) > EXPIRE_DAYS:
			state["pending"] = {}
			gs.add_inbox_message(date, I18n.t("The challenger moved on"),
				I18n.t("%s waited a week at the gates and left. The squad pretends not to feel judged.") %
				_title(pending))
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(gs.career_seed) + absi(("challenge|" + date).hash())
	if rng.randf() > DAILY_CHANCE:
		return
	_spawn(rng, date)


func _spawn(rng: RandomNumberGenerator, date: String) -> void:
	var roll := rng.randf()
	var ch := {}
	var avg := _avg_level()
	if roll < 0.05:
		var lg: Dictionary = LEGENDS[rng.randi() % LEGENDS.size()]
		ch = {"tier": "legend", "cls": str(lg["cls"]), "name": str(lg["name"]),
			"team": (lg["team"] as Array).duplicate(), "level": clampi(avg + 5, 8, 100),
			"money": (16 + int(rng.randi() % 11)) * 10000,
			"items": [str(LEGEND_ITEMS[rng.randi() % LEGEND_ITEMS.size()])]}
	elif roll < 0.30:
		var ld: Dictionary = LEADERS[rng.randi() % LEADERS.size()]
		var team := _pick_team(ld["pool"], 6, rng)
		ch = {"tier": "leader", "cls": str(ld["cls"]), "name": str(ld["name"]),
			"team": team, "level": clampi(avg + 2, 6, 100),
			"money": (45 + int(rng.randi() % 26)) * 1000,
			"items": [_type_booster(str(ld["type"])), "sitrus_berry"]}
	else:
		var cd: Dictionary = CLASSES[rng.randi() % CLASSES.size()]
		var first: Array = Portrait.MASC_FIRST if rng.randi() % 2 == 0 else Portrait.FEM_FIRST
		ch = {"tier": "class", "cls": str(cd["cls"]),
			"name": "%s %s" % [first[rng.randi() % first.size()],
				Portrait.LASTS[rng.randi() % Portrait.LASTS.size()]],
			"team": _pick_team(cd["pool"], 4 + int(rng.randi() % 3), rng),
			"level": clampi(avg + int(cd["lv"]), 4, 100),
			"money": int(cd["money"]) + int(rng.randi() % 4000),
			"items": (cd["items"] as Array).duplicate()}
	ch["no"] = int(state.get("next_no", 1))
	ch["date"] = date
	state["next_no"] = int(state.get("next_no", 1)) + 1
	state["pending"] = ch
	_gs.add_inbox_message(date, I18n.t("Challenge! %s wants a friendly") % _title(ch),
		I18n.t("%s is waiting at the training ground gates. Winner takes %s — and challengers this bold usually carry something interesting in the bag.") %
		[_title(ch), _fmt_money(int(ch["money"]))])
	var m: Dictionary = _gs.inbox[0]
	m["uid"] = "challenge:%d" % int(ch["no"])
	m["cat"] = "match"
	m["urgent"] = true
	m["challenge_no"] = int(ch["no"])


func _pick_team(pool: Array, n: int, rng: RandomNumberGenerator) -> Array:
	var p := pool.duplicate()
	var team: Array = []
	for i in mini(n, p.size()):
		team.append(int(p.pop_at(rng.randi() % p.size())))
	return team


func _avg_level() -> int:
	var levels: Array = _gs.player_club().get("squad", []).map(func(m): return int(m["level"]))
	levels.sort()
	levels.reverse()
	var top: Array = levels.slice(0, 6)
	var total := 0
	for l in top:
		total += int(l)
	return int(round(float(total) / maxf(float(top.size()), 1.0)))


func _type_booster(t: String) -> String:
	for iid in DataStore.items:
		for fx in DataStore.items[iid].get("effects", []):
			if str(fx) == "type_boost:%s:1.2" % t:
				return str(iid)
	return "sitrus_berry"


# ---------------------------------------------------------------- accept/decline

func pending() -> Dictionary:
	return state.get("pending", {})


func _title(ch: Dictionary) -> String:
	if str(ch.get("tier", "")) == "class":
		return "%s %s" % [I18n.t(str(ch.get("cls", "?"))), str(ch.get("name", ""))]
	return str(ch.get("name", "?"))


## Build the exhibition and hand it to MatchRunner (both shells' match views
## drive MatchRunner.active, so this works on desktop and phone alike).
func accept() -> String:
	var ch := pending()
	if ch.is_empty():
		return I18n.t("The challenger is gone.")
	var runner_script: GDScript = load("res://screens/match/match_runner.gd")
	if runner_script.active != null:
		return I18n.t("Finish the match in progress first.")
	var club := _challenger_club(ch)
	var fx := {"id": "EXH%d" % int(ch["no"]), "comp": "exhibition",
		"date": _gs.current_date, "round": 1,
		"home": str(_gs.world["meta"]["player_club_id"]), "away": str(club["id"]),
		"played": false}
	var r = runner_script.begin(fx)
	r.exhibition = true
	r.away_club = club
	r.opp_six = Season.pick_team(club)
	state["pending"]["accepted"] = true
	return ""


func decline() -> void:
	var ch := pending()
	if ch.is_empty():
		return
	state["pending"] = {}
	_gs.add_inbox_message(_gs.current_date, I18n.t("Challenge declined"),
		I18n.t("You send word that the club has nothing to prove. %s leaves — the ball boys look disappointed.") % _title(ch))
	_gs.save_game()


func _challenger_club(ch: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_gs.career_seed) + int(ch["no"]) * 7919
	var squad: Array = []
	var lv := int(ch.get("level", 20))
	for id_v in ch.get("team", []):
		squad.append(_make_member(int(id_v), lv + int(rng.randi() % 3) - 1, rng))
	return {"id": "exhib%d" % int(ch["no"]), "name": _title(ch),
		"short": "EXH", "manager": _title(ch), "reputation": 10,
		"league": str(_gs.player_league_id()),
		"finances": {"balance": 0, "wage_budget": 0}, "staff": [], "squad": squad}


func _make_member(species_id: int, lv: int, rng: RandomNumberGenerator) -> Dictionary:
	var sp: Dictionary = DataStore.species(species_id)
	var ivs := {}
	for k in ["hp", "atk", "def", "spa", "spd", "spe"]:
		ivs[k] = 6 + int(rng.randi() % 9)
	var learnset: Array = sp.get("learnset", [])
	var moves: Array = learnset.slice(maxi(0, learnset.size() - 4))
	var nk: Array = DataStore.natures.keys()
	nk.sort()
	return {"uid": "exh_%d_%d" % [species_id, rng.randi() % 99999],
		"species_id": species_id, "species": str(sp.get("name", "?")),
		"nickname": null, "level": clampi(lv, 3, 100), "ivs": ivs, "moves": moves,
		"nature": str(nk[rng.randi() % nk.size()]), "held_item": null,
		"condition": 100, "fitness": 100, "morale": 80,
		"age_months": 40, "contract": {"salary": 0, "expiry": "2099-01-01"}}


# ---------------------------------------------------------------- settle

## Called when leaving the full-time screen (mobile _leave / desktop _finish).
## Grants money + items + match XP on a WIN; a loss just stings.
func settle(runner) -> void:
	if runner == null or not bool(runner.exhibition):
		return
	var ch := pending()
	if ch.is_empty() or str(runner.fixture.get("id", "")) != "EXH%d" % int(ch.get("no", -1)):
		return
	if runner.phase != runner.Phase.POST:
		return
	state["pending"] = {}
	state["played"] = int(state.get("played", 0)) + 1
	var won: bool = runner.player_won()
	var pc: Dictionary = _gs.player_club()
	# match XP flows even in friendlies (appearances are appearances)
	var xp_fx := {"home": str(pc["id"]), "away": "exhibition",
		"detail": {"players": runner._detail_players}}
	_gs.apply_match_progression(xp_fx)
	var ups_txt := ""
	for u in xp_fx.get("level_ups", []):
		ups_txt += "\n▲ " + I18n.t("%s climbs to Lv %d") % [str(u.get("name", "?")), int(u.get("to", 0))]
	if won:
		state["won"] = int(state.get("won", 0)) + 1
		var prize := int(ch.get("money", 10000))
		pc["finances"]["balance"] = int(pc["finances"]["balance"]) + prize
		var inv: Dictionary = _gs.player_inventory()
		var item_names: Array = []
		for iid in ch.get("items", []):
			inv[str(iid)] = int(inv.get(str(iid), 0)) + 1
			item_names.append(I18n.item_name(str(iid)))
		_gs.inventory_changed.emit()
		for m in pc["squad"]:
			m["morale"] = clampi(int(m.get("morale", 70)) + 2, 0, 100)
		_gs.add_inbox_message(_gs.current_date, I18n.t("Friendly won! %s pays up") % _title(ch),
			I18n.t("The gates open and the challenger keeps their word: %s in prize money%s. Squad morale +2 — nothing bonds a dressing room like beating a stranger.%s") % [
				_fmt_money(prize),
				(" " + I18n.t("and the bag drops: %s") % ", ".join(item_names)) if not item_names.is_empty() else "",
				ups_txt])
	else:
		_gs.add_inbox_message(_gs.current_date, I18n.t("Friendly lost to %s") % _title(ch),
			I18n.t("No fee, no drops, and a challenger walking away whistling. The squad trains in silence.%s") % ups_txt)
	_gs.save_game()


func _fmt_money(v: int) -> String:
	return "%s%s" % [str(_gs.world["meta"].get("currency", "P$")), I18n.number(v)]


# ---------------------------------------------------------------- mail render

## Rich body + Accept/Decline actions for the "challenge:" inbox mail
## (routed here by report_gen; both inbox UIs handle the action kinds).
func render(msg: Dictionary) -> Dictionary:
	var ch := pending()
	var live: bool = not ch.is_empty() and int(ch.get("no", -1)) == int(msg.get("challenge_no", -2)) \
		and not bool(ch.get("accepted", false))
	var tier := str(ch.get("tier", "class")) if live else ""
	var bb := "[color=#e8ebf5]%s[/color]\n\n" % str(msg.get("body", ""))
	if live:
		bb += "[color=#8b91a8]%s[/color]\n" % (I18n.t("Team of %d · around Lv %d · expires %s") % [
			(ch.get("team", []) as Array).size(), int(ch.get("level", 20)),
			I18n.pretty_date(Season.date_add(str(ch.get("date", _gs.current_date)), EXPIRE_DAYS))])
		if tier == "legend":
			bb += "[color=#e0b050][b]%s[/b][/color]\n" % I18n.t("The whole league would hear about beating this one.")
	else:
		bb += "[color=#8b91a8]%s[/color]\n" % I18n.t("This challenge has been dealt with.")
	var actions: Array = []
	if live:
		actions = [
			{"kind": "challenge_accept", "style": "good", "label": I18n.t("Accept the friendly")},
			{"kind": "challenge_decline", "style": "bad", "label": I18n.t("Turn them away")},
		]
	return {"bbcode": bb, "actions": actions, "banner": {}}
