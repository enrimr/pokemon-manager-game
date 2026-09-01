## Manager's Protégé service (starter-companion piece; drop-in sim service,
## see docs/ARCHITECTURE.md "Simulation services").
##
## The regional professor entrusts the new manager with a starter Pokémon
## during onboarding (menu/starter_step.gd). This service owns everything
## that happens after the handshake:
##  - the starter joins the ACADEMY at Lv 10 with elite hidden potential and
##    the "Manager's Protégé" trait: +development speed (extra academy XP and,
##    once promoted, extra training points attributed under protege_pts),
##    max loyalty (never requests a transfer/exit; morale floor), and a small
##    squad-morale ripple when it performs well on matchday;
##  - milestone press/inbox arc: selection announcement, first-team debut,
##    first KO, every evolution stage (final form = big media piece);
##  - it follows the MANAGER, not the club: any player club change (the
##    sacking arc's "continue at another club", specifically) moves the
##    protégé to the new employer with a press note;
##  - a RIVAL manager in the player's league is assigned the type-advantaged
##    starter of the same trio as THEIR protégé; head-to-head fixtures come
##    with mind-games mail referencing the protégé rivalry.
## Deterministic under career seed; persisted via save_state()/load_state().
extends RefCounted
class_name ProtegeService

signal protege_changed

## Latest service instance (set on career start / load). UI pieces use this.
static var instance: ProtegeService = null

const TRIOS := {"kanto": [1, 4, 7], "johto": [152, 155, 158]}
## species -> the trio member type-advantaged over it (rival's counter-pick)
const COUNTER := {1: 4, 4: 7, 7: 1, 152: 155, 155: 158, 158: 152}
const PROTEGE_UID := "protege1"
const RIVAL_UID := "rivalpro1"
const JOIN_LEVEL := 10
const ACADEMY_XP_BONUS := 0.32     # extra academy XP per day (+~35%)
const SQUAD_PT_BONUS := 0.35       # extra training points per stat per day
const RIPPLE_COOLDOWN_DAYS := 10   # squad-morale ripple at most this often
const MORALE_FLOOR := 85           # loyalty: the protégé never sulks for long

var _gs = null
var state := {}


func _blank_state() -> Dictionary:
	return {
		"selected": false, "origin_id": 0, "nickname": "", "club_id": "",
		"picked_on": "", "debut": "", "first_ko": "", "evolved_final": "",
		"bonus_xp": 0.0, "bonus_pts": 0.0, "last_ripple": "",
		"rival": {}, "mind": {}, "mind_n": 0, "handled": {},
	}


# ------------------------------------------------------- service lifecycle

func service_id() -> String:
	return "protege"


func on_career_started(gs) -> void:
	_gs = gs
	instance = self
	if state.is_empty():
		state = _blank_state()
	if not gs.career_started.is_connected(_on_career_signal):
		gs.career_started.connect(_on_career_signal)
	if not gs.fixture_played.is_connected(_on_fixture_played):
		gs.fixture_played.connect(_on_fixture_played)
	if EvolutionService.instance != null \
			and not EvolutionService.instance.evolved.is_connected(_on_evolved):
		EvolutionService.instance.evolved.connect(_on_evolved)
	if bool(state["selected"]) and str(state["club_id"]) == "":
		state["club_id"] = _player_club_id()


func on_day(gs, date: String) -> void:
	_gs = gs
	if not bool(state.get("selected", false)):
		return
	_check_club_change(date)
	_restamp_instance()
	_tick_development(date)
	_scan_recent_fixtures(date)
	_maybe_mind_games(date)


func save_state() -> Dictionary:
	return state.duplicate(true)


func load_state(s: Dictionary) -> void:
	state = _blank_state()
	for k in state.keys():
		if s.has(k):
			state[k] = s[k]
	state["selected"] = bool(state["selected"])
	state["origin_id"] = int(state["origin_id"])
	state["bonus_xp"] = float(state["bonus_xp"])
	state["bonus_pts"] = float(state["bonus_pts"])
	state["mind_n"] = int(state["mind_n"])
	var rv: Dictionary = state.get("rival", {})
	if not rv.is_empty():
		rv["species_id"] = int(rv.get("species_id", 0))


# ------------------------------------------------------- selection ceremony

## The trio the professor lays out for a club of the given league.
static func trio_for_league(league_id: String) -> Array:
	return TRIOS.get(league_id, TRIOS["kanto"])


static func professor_for_league(league_id: String) -> String:
	return "Professor Elm" if league_id == "johto" else "Professor Oak"


## The onboarding wizard's contract: called ONCE right after new_career()
## (MenuFlow.start_career). Creates the academy entry, assigns the rival's
## counter-starter and posts the announcement mail. "" = ok, else error.
func select_starter(species_id: int, nickname: String = "") -> String:
	if _gs == null:
		return "no career running"
	if bool(state.get("selected", false)):
		return "a protégé has already been chosen"
	var league := str(_gs.league_of(_player_club_id()))
	if not (species_id in trio_for_league(league)):
		return "that species is not on the professor's table"
	state = _blank_state()
	state["selected"] = true
	state["origin_id"] = species_id
	state["nickname"] = nickname.strip_edges()
	state["club_id"] = _player_club_id()
	state["picked_on"] = str(_gs.current_date)
	_join_academy(species_id)
	_assign_rival(species_id, league)
	_post_selection_mail(league)
	protege_changed.emit()
	return ""


## The starter arrives as an academy juvenile: too green for the first team,
## but with elite hidden potential and a coach band that says as much.
func _join_academy(species_id: int) -> void:
	var aca = AcademyService.active
	if aca == null:
		return
	var sp: Dictionary = DataStore.species(species_id)
	var r := RandomNumberGenerator.new()
	r.seed = int(_gs.career_seed) + hash("protege|ivs|%d" % species_id)
	var ivs := {}
	for k in ["hp", "atk", "def", "spa", "spd", "spe"]:
		ivs[k] = 10 + int(r.randi() % 6)   # 10..15: professor-raised stock
	var moves: Array = []
	for mv in sp.get("learnset", []):
		if moves.size() >= 3:
			break
		if int(DataStore.move(String(mv)).get("power", 0)) <= 60:
			moves.append(mv)
	if moves.is_empty() and not (sp.get("learnset", []) as Array).is_empty():
		moves.append(sp["learnset"][0])
	var nk: Array = DataStore.natures.keys()
	nk.sort()
	var m := {
		"uid": PROTEGE_UID, "species_id": species_id, "species": String(sp["name"]),
		"level": JOIN_LEVEL, "ivs": ivs, "moves": moves,
		"nature": String(nk[r.randi() % nk.size()]),
		"ability": String(sp.get("ability", "")),
		"age_months": 12, "joined": str(_gs.current_date),
		"potential": 19 + int(r.randi() % 2), "pot_min": 17, "pot_max": 20,
		"focus": "balanced", "xp": 0.0, "stars": 0.0, "protege": true,
	}
	if str(state["nickname"]) != "":
		m["nickname"] = str(state["nickname"])
	m["stars"] = float(aca._ability_stars(m))
	aca.roster.append(m)
	aca.academy_changed.emit()


## One rival manager in the player's league takes the type-advantaged member
## of the same trio under their wing. Deterministic under the career seed:
## among the three clubs closest to ours in reputation, the seed picks one.
func _assign_rival(species_id: int, league: String) -> void:
	var counter_id: int = COUNTER.get(species_id, species_id)
	var pc: Dictionary = _gs.player_club()
	var my_rep := int(pc.get("reputation", 10))
	var cands: Array = []
	for cid in _gs.league_club_ids(league):
		if str(cid) == _player_club_id():
			continue
		cands.append(str(cid))
	cands.sort_custom(func(a, b):
		var da: int = absi(int(_gs.club(a).get("reputation", 10)) - my_rep)
		var db: int = absi(int(_gs.club(b).get("reputation", 10)) - my_rep)
		return da < db if da != db else str(a) < str(b))
	var top: Array = cands.slice(0, 3)
	var pick: String = top[absi(int(_gs.career_seed) + species_id) % top.size()]
	var rc: Dictionary = _gs.club(pick)
	var sp: Dictionary = DataStore.species(counter_id)
	var r := RandomNumberGenerator.new()
	r.seed = int(_gs.career_seed) + hash("protege|rival|%d" % counter_id)
	var ivs := {}
	for k in ["hp", "atk", "def", "spa", "spd", "spe"]:
		ivs[k] = 9 + int(r.randi() % 7)
	var moves: Array = []
	for mv in sp.get("learnset", []):
		if moves.size() >= 3:
			break
		if int(DataStore.move(String(mv)).get("power", 0)) <= 60:
			moves.append(mv)
	var nk: Array = DataStore.natures.keys()
	nk.sort()
	var yr := int(str(_gs.current_date).substr(0, 4)) + 3
	rc["squad"].append({
		"uid": RIVAL_UID, "species_id": counter_id, "species": String(sp["name"]),
		"nickname": null, "level": JOIN_LEVEL + 1, "ivs": ivs, "moves": moves,
		"held_item": null, "condition": 85, "fitness": 95, "morale": 90,
		"age_months": 13, "contract": {"salary": 900, "expiry": "%04d-06-30" % yr},
		"nature": String(nk[r.randi() % nk.size()]),
		"ability": String(sp.get("ability", "")), "potential": 19,
		"rival_protege": true,
	})
	state["rival"] = {"club_id": pick, "species_id": counter_id,
		"manager": str(rc.get("manager", ""))}


# ------------------------------------------------------- queries

func has_protege() -> bool:
	return bool(state.get("selected", false))


## The protégé's live squad instance ({} if still in the academy).
func find_instance() -> Dictionary:
	if _gs == null:
		return {}
	for inst in _gs.player_club().get("squad", []):
		if str(inst.get("uid", "")) == PROTEGE_UID:
			return inst
	return {}


## The protégé's academy roster entry ({} once promoted).
func academy_entry() -> Dictionary:
	var aca = AcademyService.active
	if aca == null:
		return {}
	return aca.find(PROTEGE_UID)


func is_protege_uid(uid: String) -> bool:
	return has_protege() and uid == PROTEGE_UID


## Display name per the awards convention: nickname, with the species in
## brackets only when they differ ("Fuego (Cyndaquil)", never "Cyndaquil (Cyndaquil)").
func display_name() -> String:
	var m := find_instance()
	if m.is_empty():
		m = academy_entry()
	var species := str(m.get("species", ""))
	var nick := str(state.get("nickname", ""))
	if nick != "" and nick != species:
		return "%s (%s)" % [nick, species]
	return species if species != "" else nick


func rival() -> Dictionary:
	return state.get("rival", {})


func rival_instance() -> Dictionary:
	var rv: Dictionary = rival()
	if rv.is_empty() or _gs == null:
		return {}
	for inst in _gs.club(str(rv["club_id"])).get("squad", []):
		if str(inst.get("uid", "")) == RIVAL_UID:
			return inst
	return {}


func _player_club_id() -> String:
	return str(_gs.world["meta"]["player_club_id"])


# ------------------------------------------------------- follows the manager

func _on_career_signal() -> void:
	if _gs == null or not has_protege():
		return
	_check_club_change(str(_gs.current_date))


## The protégé follows YOU. On any player club change (sacking-arc job offer,
## specifically) the first-team instance transfers automatically; an academy
## protégé rides along with the youth setup (the academy is the manager's).
func _check_club_change(date: String) -> void:
	var now := _player_club_id()
	var was := str(state.get("club_id", ""))
	if was == "" or was == now:
		state["club_id"] = now
		return
	state["club_id"] = now
	var moved := false
	if was != "" and not _gs.club(was).is_empty():
		var old_squad: Array = _gs.club(was).get("squad", [])
		for i in old_squad.size():
			if str(old_squad[i].get("uid", "")) == PROTEGE_UID:
				var inst: Dictionary = old_squad[i]
				old_squad.remove_at(i)
				_gs.player_club()["squad"].append(inst)
				moved = true
				break
	if moved or not academy_entry().is_empty():
		var name := display_name()
		_post_mail(date, I18n.t("%s refuses to be left behind") % name,
			I18n.t("When %s cleared out the office at %s, one member of the travelling party was never in doubt. %s — the professor's gift, the manager's protégé — has followed the boss to %s. \"Where the gaffer goes, I go,\" the handlers translate, roughly.") % [
				_manager_name(), str(_gs.club(was).get("name", was)), name,
				str(_gs.player_club().get("name", now))],
			"media", I18n.t("The Indigo Gazette"), "transfer")
		protege_changed.emit()


func _manager_name() -> String:
	var n := str(_gs.world.get("meta", {}).get("manager_name", ""))
	return n if n != "" else str(_gs.player_club().get("manager", "the manager"))


# ------------------------------------------------------- trait upkeep

## Keep the trait alive across promotion (academy promote() rebuilds the
## instance from scratch) and season events: protege flag, nickname, loyalty
## (no exit requests, morale floor). Idempotent, runs daily.
func _restamp_instance() -> void:
	var inst := find_instance()
	if inst.is_empty():
		return
	if not bool(inst.get("protege", false)):
		inst["protege"] = true
		inst["potential"] = 20
		if str(state["debut"]) == "":
			_post_mail(str(_gs.current_date),
				I18n.t("%s joins the first-team squad") % display_name(),
				I18n.t("The manager's protégé has been promoted from the academy. The coaching staff report the whole group trained sharper the day the youngster's locker was moved upstairs — now the town wants to see a debut."),
				"staff", _youth_coach())
	if str(state["nickname"]) != "":
		inst["nickname"] = str(state["nickname"])
	if inst.has("exit_request"):
		inst.erase("exit_request")   # max loyalty: never asks out
	if int(inst.get("morale", 70)) < MORALE_FLOOR:
		inst["morale"] = MORALE_FLOOR


## +development speed, attributed: extra academy XP while a juvenile; extra
## training points (protege_pts, mirroring mentor_pts) once in the first team.
func _tick_development(date: String) -> void:
	var entry := academy_entry()
	if not entry.is_empty():
		entry["xp"] = float(entry["xp"]) + ACADEMY_XP_BONUS
		state["bonus_xp"] = float(state["bonus_xp"]) + ACADEMY_XP_BONUS
		return
	if find_instance().is_empty():
		return
	var root: Node = Engine.get_main_loop().root if Engine.get_main_loop() is SceneTree else null
	if root == null:
		return
	var tsvc := root.get_node_or_null("TrainingService")
	if tsvc == null:
		return
	var ms: Dictionary = tsvc.mon_state(PROTEGE_UID)
	for s in ["hp", "atk", "def", "spa", "spd", "spe"]:
		ms["acc"][s] = float(ms["acc"][s]) + SQUAD_PT_BONUS
	ms["protege_pts"] = float(ms.get("protege_pts", 0.0)) + SQUAD_PT_BONUS * 6.0
	state["bonus_pts"] = float(state["bonus_pts"]) + SQUAD_PT_BONUS * 6.0
	var _d := date  # (date reserved for future pacing rules)


# ------------------------------------------------------- matchday milestones

func _on_fixture_played(f: Dictionary) -> void:
	if _gs == null or not has_protege():
		return
	if _gs.is_player_club(str(f.get("home", ""))) or _gs.is_player_club(str(f.get("away", ""))):
		_scan_fixture(f)


## Interactive matches can settle between service ticks — sweep the last few
## days so no milestone is ever missed, whatever path played the fixture.
func _scan_recent_fixtures(date: String) -> void:
	for f in _gs.player_fixtures():
		if not bool(f.get("played", false)):
			continue
		var fd := str(f.get("date", ""))
		if fd > date or Season.date_add(fd, 6) < date:
			continue
		_scan_fixture(f)


func _scan_fixture(f: Dictionary) -> void:
	var fid := str(f.get("id", ""))
	if fid == "" or (state["handled"] as Dictionary).has(fid):
		return
	var detail: Dictionary = Season.fixture_detail(f)
	var p: Dictionary = (detail.get("players", {}) as Dictionary).get(PROTEGE_UID, {})
	if p.is_empty() or int(p.get("battles", 0)) <= 0:
		return
	state["handled"][fid] = true
	var name := display_name()
	var opp_id: String = str(f["away"]) if _gs.is_player_club(str(f["home"])) else str(f["home"])
	var opp := str(_gs.club(opp_id).get("name", opp_id))
	var kos := int(p.get("kos", 0))
	if str(state["debut"]) == "":
		state["debut"] = str(f.get("date", _gs.current_date))
		_post_mail(str(_gs.current_date), I18n.t("A debut to remember: %s") % name,
			I18n.t("Every manager remembers the day they hand the kid the ball. Against %s, %s gave %s a first-team debut — the professor's starter, raised in the club's own academy, finally under the matchday lights. The bench was on its feet for every exchange.") % [
				opp, _manager_name(), name],
			"media", I18n.t("The Indigo Gazette"), "debut")
	if kos > 0 and str(state["first_ko"]) == "":
		state["first_ko"] = str(f.get("date", _gs.current_date))
		_post_mail(str(_gs.current_date), I18n.t("First career KO for %s") % name,
			I18n.t("It happened. %s recorded a first competitive knockout against %s, and the dugout celebrated like a title had been won. The manager's protégé is a protégé no more — it is a first-team battler with a taste for the big stage. The dressing room is buzzing.") % [
				name, opp],
			"media", I18n.t("The Indigo Gazette"), "first_ko")
	if kos > 0:
		_morale_ripple(str(f.get("date", _gs.current_date)))


## Small squad-morale ripple when the protégé performs: the squad loves the
## kid. Rate-limited; caps below the mentoring ceiling so it never dominates.
func _morale_ripple(date: String) -> void:
	var last := str(state.get("last_ripple", ""))
	if last != "" and Season.date_add(last, RIPPLE_COOLDOWN_DAYS) > date:
		return
	state["last_ripple"] = date
	for inst in _gs.player_club().get("squad", []):
		if str(inst.get("uid", "")) == PROTEGE_UID:
			continue
		inst["morale"] = mini(92, int(inst.get("morale", 70)) + 1)


# ------------------------------------------------------- evolution milestones

func _on_evolved(uid: String, from_id: int, to_id: int, club_id: String) -> void:
	if _gs == null or not has_protege():
		return
	var to_name := str(DataStore.species(to_id).get("name", ""))
	var from_name := str(DataStore.species(from_id).get("name", ""))
	var is_final: bool = EvolutionService.instance != null \
		and (EvolutionService.instance.chain_of(to_id) as Array).is_empty()
	if uid == PROTEGE_UID and _gs.is_player_club(club_id):
		var name := display_name()
		if is_final:
			state["evolved_final"] = str(_gs.current_date)
			_post_mail(str(_gs.current_date), I18n.t("FULL CIRCLE: %s reaches its final form") % name,
				I18n.t("Front-page material. The starter that %s carried out of the professor's lab has completed its journey: %s is now a fully evolved %s. From a Lv %d juvenile in the academy beds to the club's beating heart — this is the protégé story every manager dreams of writing. The town is planning a mural.") % [
					_manager_name(), name, to_name, JOIN_LEVEL],
				"media", I18n.t("The Indigo Gazette"), "final_form")
		else:
			_post_mail(str(_gs.current_date), I18n.t("The protégé grows: %s evolved into %s") % [name, to_name],
				I18n.t("A landmark day on the training ground: the manager's protégé evolved from %s into %s in front of the whole first-team squad. The coaches noted the applause lasted a while. The professor has asked for a photograph.") % [
					from_name, to_name],
				"media", I18n.t("The Indigo Gazette"), "evolution")
		protege_changed.emit()
	elif uid == RIVAL_UID and str(rival().get("club_id", "")) == club_id:
		var rc := str(_gs.club(club_id).get("name", club_id))
		_post_mail(str(_gs.current_date), I18n.t("Rival watch: %s's protégé evolved") % str(rival().get("manager", rc)),
			I18n.t("Word from %s: the counter-starter %s has been grooming since the day you got yours has evolved into %s. The rivalry the press manufactured is starting to look real. Yours had better keep pace.") % [
				rc, str(rival().get("manager", "their manager")), to_name],
			"media", I18n.t("The Indigo Gazette"), "rival_evolution")
		if not rival().is_empty():
			state["rival"]["species_id"] = to_id


# ------------------------------------------------------- rivalry mind-games

## Ahead of any head-to-head with the rival manager: one mind-games mail per
## fixture, template rotated by encounter count (no verbatim repeats).
func _maybe_mind_games(date: String) -> void:
	var rv := rival()
	if rv.is_empty():
		return
	var f: Dictionary = _gs.next_player_fixture()
	if f.is_empty():
		return
	var opp_id: String = str(f["away"]) if _gs.is_player_club(str(f["home"])) else str(f["home"])
	if opp_id != str(rv["club_id"]):
		return
	var fid := str(f.get("id", ""))
	if fid == "" or (state["mind"] as Dictionary).has(fid) or Season.days_between(date, str(f["date"])) > 3:
		return
	state["mind"][fid] = true
	state["mind_n"] = int(state["mind_n"]) + 1
	var mgr := str(rv.get("manager", "the rival manager"))
	var mine := display_name()
	var theirs_inst := rival_instance()
	var theirs := str(theirs_inst.get("species", DataStore.species(int(rv["species_id"])).get("name", "")))
	var lv := int(theirs_inst.get("level", JOIN_LEVEL))
	var quotes := [
		I18n.t("\"Tell %s I still think they picked the wrong one off the professor's table. My %s (Lv %d) has type advantage written all over this tie — and my protégé does not get nervous.\""),
		I18n.t("\"Two managers, two starters, one professor. %s can polish %s all they like; my %s (Lv %d) was born with the matchup in its favour. See you at the arena.\""),
		I18n.t("\"I hear the academy raves about %s's little project. Sweet. When my %s (Lv %d) is across the field, sentiment is a weakness — the chart does not lie.\""),
		I18n.t("\"%s and I both left that lab with a Poké Ball and a promise. Difference is, my %s (Lv %d) eats theirs for breakfast. Nothing personal, boss — it's the rivalry the fans deserve.\""),
	]
	var quote: String
	match int(state["mind_n"] - 1) % 4:
		0: quote = quotes[0] % [_manager_name(), theirs, lv]
		1: quote = quotes[1] % [_manager_name(), mine, theirs, lv]
		2: quote = quotes[2] % [_manager_name(), theirs, lv]
		_: quote = quotes[3] % [_manager_name(), theirs, lv]
	_post_mail(date, I18n.t("Protégé rivalry: %s stokes the fire") % mgr,
		I18n.t("Ahead of the %s tie, %s went to the press about the starter rivalry the whole league has adopted:\n\n%s\n\nYour %s will hear about it. How the tie goes may echo in both dressing rooms.") % [
			str(_gs.club(opp_id).get("name", opp_id)), mgr, quote, mine],
		"media", I18n.t("%s (%s Manager)") % [mgr, str(_gs.club(opp_id).get("name", opp_id))], "mind")


# ------------------------------------------------------- selection mail + post

func _post_selection_mail(league: String) -> void:
	var prof := professor_for_league(league)
	var name := display_name()
	var rv := rival()
	var rival_line := ""
	if not rv.is_empty():
		rival_line = I18n.t("\n\nOne more thing, straight from the lab: %s of %s collected the %s from the same bench — the one with the type advantage over yours. The professor smiled when asked if that was deliberate.") % [
			str(rv.get("manager", "?")), str(_gs.club(str(rv["club_id"])).get("name", "?")),
			str(DataStore.species(int(rv["species_id"])).get("name", "?"))]
	_post_mail(str(_gs.current_date), I18n.t("%s entrusts you with %s") % [prof, name],
		I18n.t("%s shook your hand a moment longer than protocol demands. \"This one is special. Raise it your way.\" %s (Lv %d) has been registered to the club's academy as your personal protégé: elite potential in the coaches' book, fiercely loyal to you — and to you alone. Bring it up through the youth beds, hand it a debut when it's ready, and it will follow you for the rest of your career.%s") % [
			prof, name, JOIN_LEVEL, rival_line]
		+ "\n\n" + I18n.t("Where is it now? In your YOUTH ACADEMY — it will not appear in the first-team squad until you promote it. Open the Academy screen to follow its development."),
		"media", prof, "selection")


## Post an inbox mail with routing keys attached (academy _post_mail pattern:
## the snapshot rides the message, protege_kind routes it to the renderer).
func _post_mail(date: String, title: String, body: String, cat: String,
		sender: String, kind: String = "note") -> void:
	_gs.add_inbox_message(date, title, body)
	var m: Dictionary = _gs.inbox[0]
	if str(m.get("title", "")) == title:
		var inst := find_instance()
		if inst.is_empty():
			inst = academy_entry()
		m.merge({
			"cat": cat, "sender": sender, "protege_kind": kind,
			"uid": "protege:%s:%s" % [kind, date],
			"species": str(inst.get("species", "")),
			"species_id": int(inst.get("species_id", state.get("origin_id", 0))),
			"nickname": str(state.get("nickname", "")),
			"level": int(inst.get("level", JOIN_LEVEL)),
			"in_academy": not academy_entry().is_empty(),
		}, true)
		_gs.inbox_updated.emit()


func _youth_coach() -> String:
	var aca = AcademyService.active
	return str(aca.head_youth_coach()) if aca != null else I18n.t("the coaching staff")
