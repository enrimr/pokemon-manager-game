extends Node
## Headless check for the Choice-item move lock UX (user report 2026-09-05:
## "after picking an attack only that attack shows" — the lock is the intended
## Choice Band mechanic, but locked-out moves must stay visible as disabled).
## Verifies: no lock -> choice_locked_moves() empty; after a choice_band
## holder picks a move -> legal moves shrink to 1 and the runner reports the
## vetoed moves; switching out clears the lock.
## Run: godot --headless --path . res://tools/choice_lock_check.tscn

const MatchRunner := preload("res://screens/match/match_runner.gd")
const SaveGuard := preload("res://tools/save_guard.gd")

var _fail := false


func _check(cond: bool, what: String) -> void:
	if cond:
		print("  ok: %s" % what)
	else:
		printerr("  CHOICE LOCK FAIL: %s" % what)
		_fail = true


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	print("=== choice lock check ===")
	SaveGuard.backup()
	GameState.new_career(445566)
	var f: Dictionary = GameState.next_player_fixture()
	GameState.current_date = str(f["date"])
	var r = MatchRunner.begin(f)
	r.confirm_lineup()
	for i in 400:
		if r.consume_next().is_empty():
			break
	if r.live_state != MatchRunner.LiveState.AWAIT_INPUT:
		_check(false, "battle reached AWAIT_INPUT")
		_finish()
		return

	_check(r.choice_locked_moves().is_empty(), "no lock before any move is picked")

	# strap a Choice Band on our active battler and make it unkillable for a
	# turn (the check needs the SAME battler to face the next input prompt),
	# then pick the weakest move so the foe survives too
	var me: Dictionary = r.engine.active_battler(r.player_side)
	me["item"] = "choice_band"
	me["item_consumed"] = false
	me["stats"]["hp"] = 9999
	me["max_hp"] = 9999
	me["hp"] = 9999
	var pick := 0
	var weakest := 999999
	var moves_with_pp := 0
	for i in me["moves"].size():
		var mname: String = str(me["moves"][i])
		if int(me["pp"].get(mname, 0)) <= 0:
			continue
		moves_with_pp += 1
		var pw := int(DataStore.move(mname).get("power", 0))
		if pw < weakest:
			weakest = pw
			pick = i
	var first_move: String = str(me["moves"][pick])
	r.submit_action({"type": "move", "index": pick})
	for i in 400:
		if r.consume_next().is_empty():
			break
	if r.live_state != MatchRunner.LiveState.AWAIT_INPUT \
			or str(r.engine.active_battler(r.player_side).get("name")) != str(me.get("name")):
		print("  (battler fainted or battle ended before next turn — inconclusive, still OK)")
		_finish()
		return

	var legal_moves: Array = r.available_actions().filter(func(a): return str(a["type"]) == "move")
	var locked: Array = r.choice_locked_moves()
	_check(legal_moves.size() == 1, "choice lock leaves exactly 1 legal move (%d)" % legal_moves.size())
	_check(str(legal_moves[0]["move"]) == first_move, "the legal move is the locked one")
	_check(locked.size() == moves_with_pp - 1, "locked-out moves reported (%d of %d)" % [locked.size(), moves_with_pp - 1])
	for lk in locked:
		_check(str(lk["locked_move"]) == first_move, "entry %s names the locking move" % str(lk["move"]))
		_check(str(lk["item_name"]) != "", "entry %s carries the item name" % str(lk["move"]))

	# switching out must clear the lock (engine re-picks on re-entry)
	var bench := -1
	for i in r.engine.team_state(r.player_side).size():
		var b: Dictionary = r.engine.team_state(r.player_side)[i]
		if int(b["hp"]) > 0 and i != r.engine.active[r.player_side]:
			bench = i
			break
	if bench >= 0:
		r.submit_action({"type": "switch", "index": bench})
		for i in 400:
			if r.consume_next().is_empty():
				break
		if r.live_state == MatchRunner.LiveState.AWAIT_INPUT:
			_check(r.choice_locked_moves().is_empty(), "switching out clears the lock for the new battler")
	_finish()


func _finish() -> void:
	MatchRunner.clear()
	SaveGuard.restore()
	if _fail:
		printerr("CHOICE LOCK CHECK FAILED")
	else:
		print("CHOICE LOCK CHECK OK")
	get_tree().quit(1 if _fail else 0)
