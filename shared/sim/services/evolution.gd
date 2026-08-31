## Evolution service (drop-in sim service, see docs/ARCHITECTURE.md).
##
## Owns the MECHANICS of Pokémon evolution: gen 1+2 chains (shared/data/
## evolutions.json), eligibility from level + training development + stones,
## the FM-style manager-approval flow (pending -> approve/postpone), instance
## transformation, AI-club autonomous evolutions, and persistence.
## UI surfacing is another piece's job — it consumes this API via
## `EvolutionService.instance` and the signals below.
##
## Eligibility model (levels are static in this world; training development
## is the growth axis):
##   effective_level = instance level + total training development points
##                     gained / DEV_PER_LEVEL (meta.dev_per_level, 6)
##   - "level" evos  : effective_level >= threshold (Tyrogue branches on
##                     base+IV Attack vs Defense, mainline-style)
##   - "development" : trade evos in the mainline — here high-development
##                     milestones (dev points >= dev, level gate); "bond"
##                     (happiness) evos additionally need morale >= 80
##   - "stone"       : manager buys the stone in the shop and spends it via
##                     use_stone() — consumed from club stock, evolves NOW
##                     (using the stone IS the approval)
## Postponing an approval costs POSTPONE_MORALE_COST morale each time (the
## mon feels held back) and the offer returns after REOFFER_DAYS if still
## eligible. Approving grants +EVOLVE_MORALE_BOOST morale.
## Deterministic: AI decisions are seeded from career_seed + date + club id.
extends RefCounted
class_name EvolutionService

signal pending_added(entry: Dictionary)          ## player mon awaits approval
signal pending_changed                           ## any pending list mutation
signal evolved(uid: String, from_id: int, to_id: int, club_id: String)

## Latest service instance (set on career start / load). UI pieces use this.
static var instance: EvolutionService = null

const DATA_PATH := "res://shared/data/evolutions.json"
const REOFFER_DAYS := 14           ## postponed offers return after this
const POSTPONE_MORALE_COST := 3    ## morale lost per postpone
const EVOLVE_MORALE_BOOST := 6     ## morale gained on evolving
const AI_CHECK_CHANCE := 0.08      ## per club per day (seeded, deterministic)
const AI_LEVEL_LAG := 2            ## AI evolves level-evos this late
const AI_TRADE_LEVEL := 34         ## AI proxy for development (trade) evos
const AI_BOND_LEVEL := 24          ## AI proxy for bond evos...
const AI_BOND_MORALE := 78         ## ...plus this much morale
const AI_STONE_LEVEL := 30         ## AI buys+uses a stone from this level
const AI_STONE_RESERVE := 4        ## ...if balance >= price * this

var _gs = null                     # GameState autoload (set by lifecycle hooks)
var _table: Dictionary = {}        # species_id (int) -> Array of option dicts
var _dev_per_level := 6
var _pending: Array = []           # player approval queue (see pending())
var _postponed: Dictionary = {}    # uid -> ISO date the offer returns
var _announced: Dictionary = {}    # "uid|stone_hint" -> true (inbox sent once)
var _log: Array = []               # [{date, club_id, uid, name, from, to, method}]


func _init() -> void:
	_load_table()


func _load_table() -> void:
	if not FileAccess.file_exists(DATA_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not (parsed is Dictionary):
		return
	_dev_per_level = maxi(1, int((parsed["meta"] as Dictionary).get("dev_per_level", 6)))
	var raw: Dictionary = parsed.get("evolutions", {})
	for k in raw:
		_table[int(str(k))] = raw[k]


# ------------------------------------------------------- service lifecycle

func service_id() -> String:
	return "evolution"


func on_career_started(gs) -> void:
	_gs = gs
	instance = self
	_prune_pending()
	_retro_tag_inbox()


func on_day(gs, date: String) -> void:
	_gs = gs
	_prune_pending()
	_scan_player(date)
	_ai_evolutions(date)


func save_state() -> Dictionary:
	return {
		"pending": _pending.duplicate(true),
		"postponed": _postponed.duplicate(true),
		"announced": _announced.duplicate(true),
		"log": _log.duplicate(true),
	}


func load_state(state: Dictionary) -> void:
	_pending = []
	for e in state.get("pending", []):
		var d: Dictionary = e
		d["from_id"] = int(d.get("from_id", 0))
		d["to_id"] = int(d.get("to_id", 0))
		_pending.append(d)
	_postponed = {}
	for uid in state.get("postponed", {}):
		_postponed[str(uid)] = str(state["postponed"][uid])
	_announced = {}
	for k in state.get("announced", {}):
		_announced[str(k)] = true
	_log = []
	for e in state.get("log", []):
		var d2: Dictionary = e
		d2["from"] = int(d2.get("from", 0))
		d2["to"] = int(d2.get("to", 0))
		_log.append(d2)

# ------------------------------------------------------------------ queries

## Raw evolution options for a species id: [{to, method, level?, stone?,
## dev?, morale?, cond?, kind?}]. Empty array = final form.
func chain_of(species_id: int) -> Array:
	return _table.get(species_id, [])


## Training development points this player mon has earned (0 if the training
## service hasn't tracked it). Read-only view of the training piece's data.
func dev_points(uid: String) -> int:
	var t := _training_service()
	if t == null:
		return 0
	return int(t.total_gained(uid))


## Extra levels granted by development: dev_points / DEV_PER_LEVEL.
func dev_levels(uid: String) -> int:
	return floori(dev_points(uid) / float(_dev_per_level))


## Level + development growth — what "level" evolutions test against.
func effective_level(inst: Dictionary) -> int:
	return int(inst.get("level", 1)) + dev_levels(str(inst.get("uid", "")))


## The player's approval queue: [{uid, name, club_id, from_id, to_id,
## to_name, method, date}]. Order = discovery order.
func pending() -> Array:
	return _pending


func is_pending(uid: String) -> bool:
	return not pending_for(uid).is_empty()


func pending_for(uid: String) -> Dictionary:
	for e in _pending:
		if str(e["uid"]) == uid:
			return e
	return {}


## Per-option eligibility report for a player instance. Each row:
## {to, to_name, method, ok, why} — why = "" when ok, else a human reason
## ("needs Lv 16 (now 14+1)", "needs a Fire Stone in stock", ...).
func eligibility(inst: Dictionary) -> Array:
	var out: Array = []
	for o in chain_of(int(inst.get("species_id", 0))):
		var row := {
			"to": int(o["to"]),
			"to_name": str(DataStore.species(int(o["to"])).get("name", "?")),
			"method": str(o["method"]),
		}
		var why := _option_gap(inst, o)
		row["ok"] = why == ""
		row["why"] = why
		out.append(row)
	return out


## Stone routes for a player mon: [{item_id, item_name, to, to_name, owned}].
func stone_options(uid: String) -> Array:
	var inst := _player_instance(uid)
	if inst.is_empty():
		return []
	var inv: Dictionary = _gs.player_inventory() if _gs != null else {}
	var out: Array = []
	for o in chain_of(int(inst.get("species_id", 0))):
		if str(o["method"]) != "stone":
			continue
		var iid := str(o["stone"])
		out.append({
			"item_id": iid,
			"item_name": str(DataStore.item(iid).get("name", iid)),
			"to": int(o["to"]),
			"to_name": str(DataStore.species(int(o["to"])).get("name", "?")),
			"owned": int(inv.get(iid, 0)),
		})
	return out


## Recent evolutions across the whole world (for news/UI): newest last.
func recent_evolutions(days: int = 7) -> Array:
	if _gs == null:
		return []
	var cutoff: String = Season.date_add(_gs.current_date, -days)
	return _log.filter(func(e): return str(e["date"]) >= cutoff)


func evolution_log() -> Array:
	return _log


# ----------------------------------------------------- eligibility internals

## "" when the option is satisfied for this PLAYER instance, else the gap.
func _option_gap(inst: Dictionary, o: Dictionary) -> String:
	var uid := str(inst.get("uid", ""))
	match str(o["method"]):
		"level":
			if not _cond_holds(inst, str(o.get("cond", ""))):
				return I18n.t("wrong stat balance (%s)") % str(o["cond"])
			var eff := effective_level(inst)
			if eff < int(o["level"]):
				return I18n.t("needs Lv %d (now %d+%d from training)") % [
					int(o["level"]), int(inst.get("level", 1)), dev_levels(uid)]
			return ""
		"development":
			var need_dev := int(o.get("dev", 0))
			var have_dev := dev_points(uid)
			if have_dev < need_dev:
				return I18n.t("needs %d development points from training (has %d)") % [need_dev, have_dev]
			if int(inst.get("level", 1)) < int(o.get("level", 0)):
				return I18n.t("needs Lv %d") % int(o["level"])
			if inst.get("morale", 100) < int(o.get("morale", 0)):
				return I18n.t("needs %d morale (bond)") % int(o["morale"])
			return ""
		"stone":
			var iid := str(o["stone"])
			var inv: Dictionary = _gs.player_inventory() if _gs != null else {}
			if int(inv.get(iid, 0)) <= 0:
				return "needs a %s in stock" % str(DataStore.item(iid).get("name", iid))
			return ""
	return I18n.t("unknown method")


## Tyrogue-style branch conditions: base stat + IV comparison.
func _cond_holds(inst: Dictionary, cond: String) -> bool:
	if cond == "":
		return true
	var base: Dictionary = DataStore.species(int(inst.get("species_id", 0))).get("base", {})
	var ivs: Dictionary = inst.get("ivs", {})
	var atk := int(base.get("atk", 0)) + int(ivs.get("atk", 0))
	var def := int(base.get("def", 0)) + int(ivs.get("def", 0))
	match cond:
		"atk>def": return atk > def
		"def>atk": return def > atk
		"atk=def": return atk == def
	return false

# ------------------------------------------------------------------ actions

## Approve a pending evolution. Returns "" on success, else an error string.
## Transforms the instance in place, +morale, inbox follow-up, emits evolved.
func approve(uid: String) -> String:
	var e := pending_for(uid)
	if e.is_empty():
		return I18n.t("no evolution pending for this Pokémon")
	var inst := _player_instance(uid)
	if inst.is_empty():
		return I18n.t("Pokémon is no longer in the squad")
	var old_name := _display_name(inst)
	_transform(inst, int(e["to_id"]), str(_gs.world["meta"]["player_club_id"]),
			str(e["method"]), _gs.current_date)
	_pending.erase(e)
	_postponed.erase(uid)
	_gs.add_inbox_message(_gs.current_date, I18n.t("%s has evolved into %s!") % [old_name, str(inst["species"])],
		I18n.t("The whole squad gathered to watch. %s is transformed — new presence, new power, and a fresh set of techniques it can now be drilled in. Morale is up.") % str(inst["species"]))
	_tag_last_message({"cat": "staff", "uid": "evo:done:%s|%s" % [uid, _gs.current_date],
		"sender": I18n.t("Coaching staff"), "kind": "evo_done", "evo_uid": uid,
		"evo_from": int(e["from_id"]), "evo_to": int(e["to_id"]),
		"evo_method": str(e["method"])})
	_resolve_ready_messages(uid, "approved")
	pending_changed.emit()
	return ""


## Postpone a pending evolution. The mon loses POSTPONE_MORALE_COST morale
## (it feels held back — that's the documented tradeoff) and the offer
## returns after REOFFER_DAYS if still eligible. Returns "" on success.
func postpone(uid: String) -> String:
	var e := pending_for(uid)
	if e.is_empty():
		return I18n.t("no evolution pending for this Pokémon")
	var inst := _player_instance(uid)
	if not inst.is_empty():
		inst["morale"] = maxi(0, int(inst.get("morale", 70)) - POSTPONE_MORALE_COST)
	_pending.erase(e)
	_postponed[uid] = Season.date_add(_gs.current_date, REOFFER_DAYS)
	_resolve_ready_messages(uid, "postponed")
	pending_changed.emit()
	return ""


## Spend an evolution stone from club stock on a squad mon. Using the stone
## IS the approval: consumes 1x item_id and evolves immediately.
## Returns "" on success, else an error string.
func use_stone(uid: String, item_id: String) -> String:
	if _gs == null:
		return I18n.t("no career running")
	var inst := _player_instance(uid)
	if inst.is_empty():
		return I18n.t("Pokémon is not in the squad")
	var opt := {}
	for o in chain_of(int(inst["species_id"])):
		if str(o["method"]) == "stone" and str(o["stone"]) == item_id:
			opt = o
			break
	if opt.is_empty():
		return "%s has no effect on %s" % [str(DataStore.item(item_id).get("name", item_id)), _display_name(inst)]
	var pid: String = str(_gs.world["meta"]["player_club_id"])
	if int(_gs.player_inventory().get(item_id, 0)) <= 0:
		return "no %s in stock — buy one in the shop" % str(DataStore.item(item_id).get("name", item_id))
	_gs.consume_club_items(pid, {item_id: 1})
	var old_name := _display_name(inst)
	# a pending offer for another route is void once the species changes
	var e := pending_for(uid)
	if not e.is_empty():
		_pending.erase(e)
	_postponed.erase(uid)
	var from_id_used := int(inst["species_id"])
	_transform(inst, int(opt["to"]), pid, "stone", _gs.current_date)
	_gs.add_inbox_message(_gs.current_date, I18n.t("%s has evolved into %s!") % [old_name, str(inst["species"])],
		I18n.t("The %s glowed, was consumed, and %s stands transformed. New typing, new power — and a fresh set of techniques it can now be drilled in.") %
		[str(DataStore.item(item_id).get("name", item_id)), str(inst["species"])])
	_tag_last_message({"cat": "staff", "uid": "evo:done:%s|%s" % [uid, _gs.current_date],
		"sender": I18n.t("Coaching staff"), "kind": "evo_done", "evo_uid": uid,
		"evo_from": from_id_used, "evo_to": int(opt["to"]),
		"evo_method": "stone", "evo_stone": item_id})
	_resolve_ready_messages(uid, "evolved via %s" % str(DataStore.item(item_id).get("name", item_id)))
	pending_changed.emit()
	return ""


# ------------------------------------------------------- the transformation

## Transform an instance in place: species/base stats/types come from the new
## species id, ability updates (unless custom), learnset merges (old species'
## moves stay available via "learnset_extra"; current moves are kept), the
## display name follows unless nicknamed, morale rises.
func _transform(inst: Dictionary, to_id: int, club_id: String, method: String, date: String) -> void:
	var from_id := int(inst["species_id"])
	var from_sp: Dictionary = DataStore.species(from_id)
	var to_sp: Dictionary = DataStore.species(to_id)
	if to_sp.is_empty():
		return
	# learnset merge: pre-evo moves not in the new learnset remain learnable
	var extra: Array = inst.get("learnset_extra", [])
	for mv in from_sp.get("learnset", []):
		if not to_sp.get("learnset", []).has(mv) and not extra.has(mv):
			extra.append(mv)
	inst["learnset_extra"] = extra
	# name follows the species unless the mon carries a real nickname
	var nick: Variant = inst.get("nickname")
	if nick != null and str(nick) == str(from_sp.get("name", "")):
		inst["nickname"] = null
	# ability follows the species unless it was customised away from default
	if str(inst.get("ability", "")) == str(from_sp.get("ability", "")) or str(inst.get("ability", "")) == "":
		inst["ability"] = str(to_sp.get("ability", ""))
	inst["species_id"] = to_id
	inst["species"] = str(to_sp["name"])
	inst["morale"] = mini(100, int(inst.get("morale", 70)) + EVOLVE_MORALE_BOOST)
	_log.append({"date": date, "club_id": club_id, "uid": str(inst.get("uid", "")),
		"name": _display_name(inst), "from": from_id, "to": to_id, "method": method})
	evolved.emit(str(inst.get("uid", "")), from_id, to_id, club_id)


# ------------------------------------------------- player scan (daily tick)

func _scan_player(date: String) -> void:
	if _gs == null or _gs.world.is_empty():
		return
	for inst in _gs.player_club().get("squad", []):
		var uid := str(inst.get("uid", ""))
		if uid == "" or is_pending(uid):
			continue
		if _postponed.has(uid) and date < str(_postponed[uid]):
			continue
		var opts := chain_of(int(inst.get("species_id", 0)))
		if opts.is_empty():
			continue
		var offered := false
		for o in opts:
			if str(o["method"]) == "stone":
				_maybe_announce_stone(inst, o, date)
				continue
			if not offered and _option_gap(inst, o) == "":
				_offer(inst, o, date)
				offered = true


func _offer(inst: Dictionary, o: Dictionary, date: String) -> void:
	var to_sp: Dictionary = DataStore.species(int(o["to"]))
	var entry := {
		"uid": str(inst["uid"]),
		"name": _display_name(inst),
		"club_id": str(_gs.world["meta"]["player_club_id"]),
		"from_id": int(inst["species_id"]),
		"to_id": int(o["to"]),
		"to_name": str(to_sp.get("name", "?")),
		"method": str(o["method"]),
		"date": date,
	}
	_pending.append(entry)
	var how := ""
	match str(o["method"]):
		"level":
			how = I18n.t("Its training has pushed it past the threshold (effective Lv %d).") % effective_level(inst)
		"development":
			how = (I18n.t("It has hit a major development milestone (%d development points).") % dev_points(str(inst["uid"]))) \
				if str(o.get("kind", "")) == "trade" \
				else I18n.t("Its development and bond with the staff have blossomed.")
	_gs.add_inbox_message(date, I18n.t("%s is ready to evolve into %s") % [entry["name"], entry["to_name"]],
		I18n.t("%s The coaches await your decision — approve the evolution or postpone it. Postponing costs a little morale (-%d); the offer returns in %d days.") %
		[how, POSTPONE_MORALE_COST, REOFFER_DAYS])
	_tag_last_message({"cat": "staff", "uid": "evo:ready:%s|%s" % [entry["uid"], date],
		"sender": I18n.t("Coaching staff"), "urgent": true, "kind": "evo_ready",
		"evo_uid": str(entry["uid"]), "evo_from": int(entry["from_id"]),
		"evo_to": int(entry["to_id"]), "evo_to_name": str(entry["to_name"]),
		"evo_method": str(entry["method"])})
	pending_added.emit(entry)
	pending_changed.emit()


## One-time inbox hint that a stone route exists for this mon.
func _maybe_announce_stone(inst: Dictionary, o: Dictionary, date: String) -> void:
	var key := "%s|%s" % [str(inst["uid"]), str(o["stone"])]
	if _announced.has(key):
		return
	_announced[key] = true
	var iname := str(DataStore.item(str(o["stone"])).get("name", str(o["stone"])))
	var to_name := str(DataStore.species(int(o["to"])).get("name", "?"))
	_gs.add_inbox_message(date, I18n.t("%s could evolve with a %s") % [_display_name(inst), iname],
		I18n.t("Our staff report that %s would evolve into %s if exposed to a %s. Stones are stocked in the club shop; use one from the storeroom whenever you choose.") %
		[_display_name(inst), to_name, iname])
	_tag_last_message({"cat": "staff", "uid": "evo:stone:%s" % key,
		"sender": I18n.t("Coaching staff"), "kind": "evo_stone",
		"evo_uid": str(inst["uid"]), "evo_stone": str(o["stone"]),
		"evo_from": int(inst["species_id"]), "evo_to": int(o["to"]),
		"evo_to_name": to_name})

# ------------------------------------------------- AI clubs (daily tick)

## AI clubs evolve autonomously: each club gets a seeded daily check
## (career_seed + date + club id — deterministic) and evolves at most one
## eligible mon. Level evos wait AI_LEVEL_LAG past the threshold, trade evos
## wait for AI_TRADE_LEVEL (their development proxy), bond evos need morale,
## stone evos cost the club the stone's price (bought and used same day).
func _ai_evolutions(date: String) -> void:
	if _gs == null or _gs.world.is_empty():
		return
	for c in _gs.world["clubs"]:
		var cid := str(c["id"])
		if _gs.is_player_club(cid):
			continue
		var r := RandomNumberGenerator.new()
		r.seed = int(_gs.career_seed) + (date + "|evo|" + cid).hash()
		if r.randf() > AI_CHECK_CHANCE:
			continue
		for inst in c.get("squad", []):
			var picked := _ai_pick_option(inst, c)
			if picked.is_empty():
				continue
			if str(picked["method"]) == "stone":
				var price := int(DataStore.item(str(picked["stone"])).get("price", 0))
				c["finances"]["balance"] = int(c["finances"]["balance"]) - price
			_transform(inst, int(picked["to"]), cid, str(picked["method"]), date)
			break  # one evolution per club per day


func _ai_pick_option(inst: Dictionary, c: Dictionary) -> Dictionary:
	var lvl := int(inst.get("level", 1))
	for o in chain_of(int(inst.get("species_id", 0))):
		match str(o["method"]):
			"level":
				if lvl >= int(o["level"]) + AI_LEVEL_LAG and _cond_holds(inst, str(o.get("cond", ""))):
					return o
			"development":
				if str(o.get("kind", "")) == "bond":
					if lvl >= AI_BOND_LEVEL and int(inst.get("morale", 0)) >= AI_BOND_MORALE:
						return o
				elif lvl >= AI_TRADE_LEVEL:
					return o
			"stone":
				var price := int(DataStore.item(str(o["stone"])).get("price", 0))
				if lvl >= AI_STONE_LEVEL and int(c["finances"]["balance"]) >= price * AI_STONE_RESERVE:
					return o
	return {}


# ------------------------------------------------------- inbox surfacing

## Tag the message just posted via add_inbox_message (inbox[0]) with routing
## metadata: category/sender for the inbox list, `kind`/`evo_*` fields so the
## inbox piece can render live Approve/Postpone/Use-Stone decision buttons.
func _tag_last_message(extra: Dictionary) -> void:
	if _gs == null or _gs.inbox.is_empty():
		return
	var m: Dictionary = _gs.inbox[0]
	for k in extra:
		m[k] = extra[k]


## Close any open "ready to evolve" messages for this mon: record the outcome,
## clear the DECISION REQUIRED urgency. The message stays as a paper trail.
func _resolve_ready_messages(uid: String, outcome: String) -> void:
	if _gs == null:
		return
	var touched := false
	for m in _gs.inbox:
		if str(m.get("kind", "")) == "evo_ready" and str(m.get("evo_uid", "")) == uid \
				and str(m.get("decided", "")) == "":
			m["decided"] = outcome
			m["decided_on"] = _gs.current_date
			m["urgent"] = false
			touched = true
	if touched:
		_gs.inbox_updated.emit()


## Older saves carry evolution messages posted before inbox surfacing existed —
## tag them by title so they route to the evolution renderer instead of the
## generic board fallback.
func _retro_tag_inbox() -> void:
	if _gs == null:
		return
	var i := 0
	for m in _gs.inbox:
		i += 1
		if m.has("cat"):
			continue
		var title := str(m.get("title", ""))
		if title.contains(" is ready to evolve into "):
			m["cat"] = "staff"
			m["sender"] = I18n.t("Coaching staff")
			m["kind"] = "evo_ready"
			m["uid"] = "evo:ready:legacy%d" % i
			var matched := false
			for e in _pending:
				if title.begins_with(str(e["name"]) + " is ready to evolve into"):
					m["evo_uid"] = str(e["uid"])
					m["evo_from"] = int(e["from_id"])
					m["evo_to"] = int(e["to_id"])
					m["evo_to_name"] = str(e["to_name"])
					m["evo_method"] = str(e["method"])
					m["urgent"] = true
					matched = true
					break
			if not matched:
				m["decided"] = "resolved"
		elif title.contains(" has evolved into "):
			m["cat"] = "staff"
			m["sender"] = I18n.t("Coaching staff")
			m["kind"] = "evo_done"
			m["uid"] = "evo:done:legacy%d" % i
		elif title.contains(" could evolve with a "):
			m["cat"] = "staff"
			m["sender"] = I18n.t("Coaching staff")
			m["kind"] = "evo_stone"
			m["uid"] = "evo:stone:legacy%d" % i
			for inst in _gs.player_club().get("squad", []):
				if not title.begins_with(_display_name(inst) + " could evolve"):
					continue
				for o in chain_of(int(inst.get("species_id", 0))):
					if str(o["method"]) != "stone":
						continue
					var iname := str(DataStore.item(str(o["stone"])).get("name", ""))
					if title.ends_with(I18n.t("with a %s") % iname):
						m["evo_uid"] = str(inst["uid"])
						m["evo_stone"] = str(o["stone"])
						m["evo_from"] = int(inst["species_id"])
						m["evo_to"] = int(o["to"])
						m["evo_to_name"] = str(DataStore.species(int(o["to"])).get("name", "?"))
						break
				break


# ------------------------------------------------------------------ helpers

func _prune_pending() -> void:
	if _gs == null or _gs.world.is_empty():
		return
	var uids := {}
	for inst in _gs.player_club().get("squad", []):
		uids[str(inst.get("uid", ""))] = true
	var before: Array = _pending.duplicate()
	_pending = _pending.filter(func(e):
		return uids.has(str(e["uid"])) and not chain_of(int(e["from_id"])).is_empty())
	# also drop offers whose species already changed (evolved by stone etc.)
	_pending = _pending.filter(func(e):
		var inst := _player_instance(str(e["uid"]))
		return int(inst.get("species_id", 0)) == int(e["from_id"]))
	if _pending.size() != before.size():
		for e in before:
			if not _pending.has(e):
				_resolve_ready_messages(str(e["uid"]), I18n.t("no longer available"))
		pending_changed.emit()


func _player_instance(uid: String) -> Dictionary:
	if _gs == null or _gs.world.is_empty():
		return {}
	for inst in _gs.player_club().get("squad", []):
		if str(inst.get("uid", "")) == uid:
			return inst
	return {}


## The training piece keeps its service as a /root node ("TrainingService")
## — added deferred, so we also fall back to the script's static _instance
## (set synchronously by ensure()). Read-only access; absent (pure sim)
## means development reads as 0.
const TRAINING_SCRIPT_PATH := "res://screens/training/training_service.gd"


func _training_service() -> Node:
	var ml := Engine.get_main_loop()
	if ml != null and ml is SceneTree:
		var n: Node = (ml as SceneTree).root.get_node_or_null("TrainingService")
		if n != null:
			return n
	if ResourceLoader.exists(TRAINING_SCRIPT_PATH):
		var scr: Variant = load(TRAINING_SCRIPT_PATH)
		if scr is GDScript:
			var inst: Variant = (scr as GDScript).get("_instance")
			if inst is Node and is_instance_valid(inst):
				return inst
	return null


func _display_name(inst: Dictionary) -> String:
	var nick: Variant = inst.get("nickname")
	if nick != null and str(nick) != "":
		return str(nick)
	return str(inst.get("species", "?"))
