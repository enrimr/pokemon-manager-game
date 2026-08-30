extends Node
## Inbox piece self-test: proves the evolution approval flow is reachable in
## the REAL game UI — the "ready to evolve" mail renders Approve/Postpone
## decision buttons through the actual inbox screen, pressing them transforms
## (or postpones) the live squad instance, and stone mail/Use-Stone works.
## Run: godot --headless --path . res://screens/inbox/evo_selftest.tscn

const EvoScript := preload("res://shared/sim/services/evolution.gd")

var _fails := 0


func _ready() -> void:
	call_deferred("_run")


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: %s" % label)
	else:
		_fails += 1
		printerr("  FAIL: %s" % label)


func _mk(uid: String, sid: int, name: String, lvl: int, moves: Array) -> Dictionary:
	var ivs := {}
	for s in ["hp", "atk", "def", "spa", "spd", "spe"]:
		ivs[s] = 10
	return {"uid": uid, "species_id": sid, "species": name, "nickname": null,
		"level": lvl, "ivs": ivs, "moves": moves, "held_item": null,
		"condition": 96, "fitness": 90, "morale": 84, "age_months": 16,
		"contract": {"salary": 2400, "expiry": "2027-06-30"},
		"nature": "Hardy", "ability": str(DataStore.species(sid).get("ability", ""))}


func _evo_msg(kind: String, uid: String) -> Dictionary:
	for m in GameState.inbox:
		if str(m.get("kind", "")) == kind and str(m.get("evo_uid", "")) == uid:
			return m
	return {}


## All Buttons currently in the screen's reading pane, by visible text.
func _pane_buttons(scr: Control) -> Dictionary:
	var out := {}
	for b in scr._read_pane.find_children("", "Button", true, false):
		out[str((b as Button).text).strip_edges()] = b
	return out


func _run() -> void:
	var guard: GDScript = load("res://tools/save_guard.gd")
	guard.backup()
	GameState.new_career(909090)
	var evo: RefCounted = EvoScript.instance
	var squad: Array = GameState.player_club()["squad"]
	squad.append(_mk("t_char", 4, "Charmander", 17, ["Ember", "Quick Attack", "Screech", "Flame Wheel"]))
	squad.append(_mk("t_bulba", 1, "Bulbasaur", 19, ["Vine Whip", "Tackle", "Leech Seed", "Growth"]))
	squad.append(_mk("t_eevee", 133, "Eevee", 24, ["Quick Attack", "Bite", "Swift", "Sand Attack"]))
	GameState.advance_day()
	_check(evo.is_pending("t_char") and evo.is_pending("t_bulba"), "two pending approvals after the daily scan")

	# ---- 1. the mail is tagged for decision rendering
	var msg := _evo_msg("evo_ready", "t_char")
	_check(not msg.is_empty(), "'ready to evolve' mail tagged with kind/evo_uid")
	_check(bool(msg.get("urgent", false)), "decision mail is urgent")
	_check(str(msg.get("cat", "")) == "staff", "mail categorised under Coach")

	# ---- 2. drive the REAL inbox screen: buttons exist in the reading pane
	var scr: Control = (load("res://screens/inbox/screen.tscn") as PackedScene).instantiate()
	add_child(scr)
	await get_tree().process_frame
	scr._on_row_pressed(msg)
	await get_tree().process_frame
	var btns := _pane_buttons(scr)
	var approve_key := ""
	var postpone_key := ""
	for k in btns:
		if str(k).begins_with("Approve Evolution"):
			approve_key = k
		if str(k).begins_with("Postpone"):
			postpone_key = k
	_check(approve_key != "", "Approve button rendered in the reading pane")
	_check(postpone_key != "", "Postpone button rendered in the reading pane")

	# ---- 3. PRESS Approve: the squad instance really transforms
	var inst: Dictionary = GameState.squad_member("t_char")
	var morale_before := int(inst["morale"])
	(btns[approve_key] as Button).pressed.emit()
	await get_tree().process_frame
	_check(str(inst["species"]) == "Charmeleon" and int(inst["species_id"]) == 5,
		"pressing Approve evolved Charmander -> Charmeleon")
	_check(int(inst["morale"]) == mini(100, morale_before + EvoScript.EVOLVE_MORALE_BOOST),
		"approval morale boost applied")
	_check(str(msg.get("decided", "")) == "approved" and not bool(msg.get("urgent", false)),
		"mail marked decided + urgency cleared")
	_check(not _evo_msg("evo_done", "t_char").is_empty(), "evolution follow-up mail arrived (tagged)")

	# ---- 4. PRESS Postpone on the second mon: morale cost + offer withdrawn
	var msg2 := _evo_msg("evo_ready", "t_bulba")
	scr._on_row_pressed(msg2)
	await get_tree().process_frame
	var btns2 := _pane_buttons(scr)
	var pp := ""
	for k in btns2:
		if str(k).begins_with("Postpone"):
			pp = k
	_check(pp != "", "Postpone button rendered for the second decision")
	var inst2: Dictionary = GameState.squad_member("t_bulba")
	var m_before := int(inst2["morale"])
	(btns2[pp] as Button).pressed.emit()
	await get_tree().process_frame
	_check(str(inst2["species"]) == "Bulbasaur", "postponed mon did NOT evolve")
	_check(int(inst2["morale"]) == m_before - EvoScript.POSTPONE_MORALE_COST,
		"postpone morale cost applied")
	_check(not evo.is_pending("t_bulba"), "offer withdrawn while postponed")
	_check(str(msg2.get("decided", "")) == "postponed", "mail records the postponement")

	# ---- 5. stone mail: shop shortcut without stock, Use button with stock
	var smsg := _evo_msg("evo_stone", "t_eevee")
	_check(not smsg.is_empty(), "stone-route staff hint mail tagged")
	scr._on_row_pressed(smsg)
	await get_tree().process_frame
	# (nav buttons need the live shell — assert via the real render pipeline)
	var racts: Array = scr.reports.render(smsg)["actions"]
	_check(racts.any(func(a): return str(a.get("screen", "")) == "items"),
		"no stock -> mail offers the League Store shortcut")
	var b3 := _pane_buttons(scr)
	_check(GameState.buy_item(str(smsg["evo_stone"]), 1) == "", "stone bought from the shop")
	scr._on_row_pressed(smsg)
	await get_tree().process_frame
	b3 = _pane_buttons(scr)
	var use_key := ""
	for k in b3:
		if str(k).begins_with("Use "):
			use_key = k
	_check(use_key != "", "stone in stock -> Use button rendered")
	(b3[use_key] as Button).pressed.emit()
	await get_tree().process_frame
	var eevee: Dictionary = GameState.squad_member("t_eevee")
	_check(int(eevee["species_id"]) != 133, "pressing Use evolved Eevee (%s)" % str(eevee["species"]))
	_check(int(GameState.player_inventory().get(str(smsg["evo_stone"]), 0)) == 0, "stone consumed from stock")

	scr.queue_free()
	guard.restore()
	if _fails == 0:
		print("INBOX EVO SELFTEST OK")
		get_tree().quit(0)
	else:
		printerr("INBOX EVO SELFTEST FAILED (%d)" % _fails)
		get_tree().quit(1)
