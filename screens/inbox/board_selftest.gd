extends Node
## Inbox piece self-test: proves the Board & Finances tab is a TWO-WAY
## negotiation surface — a submitted board request is deliberated for real
## days, the decision arrives as inbox mail, and a grant MUTATES the club's
## actual wage budget / bank balance / prospect scouting knowledge.
## Run: godot --headless --path . res://screens/inbox/board_selftest.tscn
## (Run against a scratch save — this mutates game state on purpose.)

const NewsGen := preload("res://screens/inbox/news_gen.gd")
const BoardRoom := preload("res://screens/inbox/board_room.gd")

var _fails := 0


func _ready() -> void:
	call_deferred("_run")


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: %s" % label)
	else:
		_fails += 1
		printerr("  FAIL: %s" % label)


func _msg_with_uid(uid: String) -> Dictionary:
	for m in GameState.inbox:
		if str(m.get("uid", "")) == uid:
			return m
	return {}


func _decide(board: RefCounted, req: Dictionary) -> void:
	# advance the calendar past the deliberation window, then tick
	while GameState.current_date < str(req["decide_on"]):
		GameState.advance_day()
	board.tick()


func _run() -> void:
	# snapshot the real save + board state so this test leaves no trace
	var save_snapshot := _read_file(GameState.SAVE_PATH)
	var board_snapshot := _read_file(BoardRoom.STATE_PATH)
	if FileAccess.file_exists(BoardRoom.STATE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(BoardRoom.STATE_PATH))
	# fresh, deterministic career + clean board state
	GameState.new_career()
	var news: RefCounted = NewsGen.new()
	var board: RefCounted = BoardRoom.new(news)
	var pc: Dictionary = GameState.player_club()

	# ---- 1. submit a modest wage request: pending state + ack mail
	var defs: Array = board.request_defs()
	_check(defs.size() == 3, "three request types offered (wage / funds / scouting)")
	var wage_ask := int(defs[0]["options"][0]["amount"])
	var budget_before := int(pc["finances"]["wage_budget"])
	var err := str(board.submit("wage", wage_ask))
	_check(err == "", "wage request submitted (err='%s')" % err)
	var req: Dictionary = board.pending_request()
	_check(not req.is_empty(), "request is pending")
	_check(str(req["decide_on"]) > GameState.current_date, "board deliberates for real days (until %s)" % req["decide_on"])
	var ack := _msg_with_uid("boardreq:%d" % int(req["id"]))
	_check(not ack.is_empty(), "acknowledgement mail created")
	_check(int(pc["finances"]["wage_budget"]) == budget_before, "budget NOT changed before the board decides")
	err = str(board.submit("funds", 50000))
	_check(err != "", "second request blocked while one is pending")

	# ---- 2. decision day: outcome applied to the REAL wage budget + mail
	_decide(board, req)
	_check(str(req["status"]) != "pending", "request resolved on decision day (-> %s)" % req["status"])
	var dec := _msg_with_uid("boarddec:%d" % int(req["id"]))
	_check(not dec.is_empty(), "decision mail arrived")
	_check(bool(dec.get("urgent", false)), "decision mail flagged urgent (Continue stops)")
	var granted := int(req["granted"])
	if str(req["status"]) in ["granted", "partial"]:
		_check(granted > 0, "granted amount recorded (%d)" % granted)
		_check(int(pc["finances"]["wage_budget"]) == budget_before + granted,
			"REAL wage budget mutated %d -> %d" % [budget_before, budget_before + granted])
	else:
		_check(int(pc["finances"]["wage_budget"]) == budget_before, "denied request leaves budget untouched")
	_check(not (req["reasons"] as Array).is_empty(), "board recorded its reasoning")

	# ---- 3. funds injection: balance actually rises on a grant
	var f_req := _run_kind(board, pc, "funds", int(pc["reputation"]) * 9000)
	if str(f_req["status"]) in ["granted", "partial"]:
		_check(int(pc["finances"]["balance"]) == int(f_req["before"]) + int(f_req["granted"]),
			"funds injection credited to the REAL balance (+%d)" % int(f_req["granted"]))
		_check(board.ledger_rows(99).any(func(r): return str(r["kind"]) == "injection"),
			"injection recorded in the income & expenditure ledger")
	else:
		_check(int(pc["finances"]["balance"]) == int(f_req["before"]), "denied injection leaves balance untouched")

	# ---- 4. scouting investment: costs cash, boosts every prospect file
	var know_before := {}
	for p in GameState.prospects():
		know_before[str(p["uid"])] = int(p.get("scouted_pct", 0))
	var s_req := _run_kind(board, pc, "scouting", int(pc["reputation"]) * 5000)
	var still: Array = GameState.prospects().filter(func(p): return know_before.has(str(p["uid"])))
	if str(s_req["status"]) == "granted":
		_check(int(pc["finances"]["balance"]) == int(s_req["before"]) - int(s_req["granted"]),
			"scouting spend debited from the REAL balance (-%d)" % int(s_req["granted"]))
		_check(not still.is_empty() and still.all(func(p):
			return int(p.get("scouted_pct", 0)) == mini(100, int(know_before[str(p["uid"])]) + BoardRoom.SCOUT_KNOWLEDGE_GAIN)),
			"every prospect file's scouting knowledge actually increased")
	else:
		_check(still.all(func(p): return int(p.get("scouted_pct", 0)) == int(know_before[str(p["uid"])])),
			"denied scouting leaves knowledge untouched")

	# ---- 5. fatigue: three asks in quick succession are held against us
	var a1: Dictionary = board._assess("funds", 20000)
	_check((a1["reasons"] as Array).any(func(x): return str(x).contains("requests in the last 60 days")),
		"request fatigue enters the board's reasoning")

	# ---- 6. persistence + determinism: reload state, same records
	var board2: RefCounted = BoardRoom.new(news)
	_check(board2.requests.size() == board.requests.size(), "state file round-trips (%d requests)" % board.requests.size())
	if not board2.requests.is_empty() and not board.requests.is_empty():
		_check(str(board2.requests[0]["status"]) == str(board.requests[0]["status"]),
			"resolved outcomes persist across reload")

	# put the player's real save + board state back exactly as we found them
	GameState.delete_save()
	if FileAccess.file_exists(BoardRoom.STATE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(BoardRoom.STATE_PATH))
	_write_file(GameState.SAVE_PATH, save_snapshot)
	_write_file(BoardRoom.STATE_PATH, board_snapshot)

	if _fails == 0:
		print("INBOX BOARD SELFTEST OK")
		get_tree().quit(0)
	else:
		printerr("INBOX BOARD SELFTEST FAILED (%d)" % _fails)
		get_tree().quit(1)


func _read_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.open(path, FileAccess.READ).get_as_text()


func _write_file(path: String, content: String) -> void:
	if content == "":
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(content)


## Submit kind/amount, fast-forward to the decision, return the record.
func _run_kind(board: RefCounted, _pc: Dictionary, kind: String, amount: int) -> Dictionary:
	var err := str(board.submit(kind, amount))
	_check(err == "", "%s request submitted (err='%s')" % [kind, err])
	var req: Dictionary = board.pending_request()
	if req.is_empty():
		return {"status": "error", "before": 0, "granted": 0}
	_decide(board, req)
	print("  info: %s request -> %s (asked %d, granted %d, score %.1f)" %
		[kind, req["status"], amount, int(req["granted"]), float(req["score"])])
	return req
