extends SceneTree
## Dev helper for the inbox piece: play one REAL board-request loop against
## the current save (submit -> board deliberates over real days -> decision
## mail + budget mutation), then save. Gives the screenshot harness a live
## board negotiation to render. No mock data — this is the actual mechanic.
## Run: godot --headless --path . -s res://screens/inbox/dev_board_demo.gd

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var gs := root.get_node_or_null("/root/GameState")
	if gs == null:
		push_error("dev_board_demo: GameState autoload missing")
		quit(1)
		return
	# load at runtime: with `-s` these compile only after autoloads exist
	var news: RefCounted = (load("res://screens/inbox/news_gen.gd") as GDScript).new()
	var board: RefCounted = (load("res://screens/inbox/board_room.gd") as GDScript).new(news)
	if not board.pending_request().is_empty():
		print("dev_board_demo: a request is already pending — nothing to do.")
		quit(0)
		return
	# ask for whatever the board currently seems most receptive to
	var kind := ""
	var amount := 0
	for def in board.request_defs():
		for o in def["options"]:
			if str(o["hint"]["word"]) == "receptive":
				kind = str(def["kind"])
				amount = int(o["amount"])
				break
		if kind != "":
			break
	if kind == "":
		kind = "wage"
		amount = int(board.request_defs()[0]["options"][0]["amount"])
	var bal := int(gs.player_club()["finances"]["balance"])
	var bud := int(gs.player_club()["finances"]["wage_budget"])
	var err := str(board.submit(kind, amount))
	if err != "":
		printerr("dev_board_demo: submit failed: %s" % err)
		quit(1)
		return
	var req: Dictionary = board.pending_request()
	print("dev_board_demo: asked the board for %s (%s) on %s, decision due %s" %
		[kind, str(amount), gs.current_date, str(req["decide_on"])])
	while gs.current_date < str(req["decide_on"]):
		gs.advance_day()
	board.tick()
	gs.save_game()
	print("dev_board_demo: outcome=%s granted=%d | balance %d -> %d | wage budget %d -> %d | date %s" %
		[str(req["status"]), int(req["granted"]), bal, int(gs.player_club()["finances"]["balance"]),
		bud, int(gs.player_club()["finances"]["wage_budget"]), gs.current_date])
	quit(0)
