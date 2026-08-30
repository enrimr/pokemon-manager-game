extends Node
## Headless verification of the competition screen's click-through navigation
## (club/Pokémon profiles, breadcrumb stack, fixture jump). Run:
##   Godot --headless --path . res://screens/competition/nav_check.tscn
## Prints "NAV CHECK OK" and exits 0 on success.

var _fails := 0


func _check(cond: bool, what: String) -> void:
	if cond:
		print("  ok: %s" % what)
	else:
		_fails += 1
		printerr("  FAIL: %s" % what)


func _ready() -> void:
	await _run()
	if _fails == 0:
		print("NAV CHECK OK")
	get_tree().quit(0 if _fails == 0 else 1)


func _run() -> void:
	var shell: Node = load("res://shell/main.tscn").instantiate()
	add_child(shell)
	await get_tree().process_frame
	await get_tree().process_frame

	shell.navigate_to("competition")
	await get_tree().process_frame
	var screen: Node = shell._current_screen_instance()
	_check(screen != null and screen.has_method("comp_navigate"),
		"competition screen exposes comp_navigate")
	if screen == null:
		return

	# --- club profile drill-down
	var cid: String = str(GameState.club_ids()[2])
	screen.comp_navigate({"kind": "club", "id": cid})
	await get_tree().process_frame
	_check(screen._profile_wrap.visible, "club link opens profile view")
	_check(screen._nav_stack.size() == 1, "nav stack has 1 entry")
	_check(screen._profile.title_text() == str(GameState.club(cid)["name"]),
		"profile shows the clicked club")

	# --- pokemon profile pushed on top
	var uid: String = str(GameState.club(cid)["squad"][0]["uid"])
	screen.comp_navigate({"kind": "pokemon", "id": uid})
	await get_tree().process_frame
	_check(screen._nav_stack.size() == 2, "pokemon link pushes onto stack")
	_check(str(screen._nav_stack.back()["id"]) == uid, "top of stack is the pokemon")

	# --- pokemon match log data exists for a squad member that has played
	var stats: Dictionary = Season.season_player_stats(GameState.fixtures)
	var played_uid := ""
	for suid in stats:
		if UI_club_of(suid) == cid:
			played_uid = str(suid)
			break
	if played_uid != "":
		var log: Array = Season.pokemon_match_log(played_uid, cid, GameState.fixtures)
		_check(not log.is_empty(), "pokemon match log computed from replays")
		if not log.is_empty():
			_check(log[0].has("rating") and log[0].has("opp"), "match log rows carry rating + opponent")

	# --- back navigation pops the stack
	screen._profile_back()
	await get_tree().process_frame
	_check(screen._nav_stack.size() == 1, "back pops to club profile")
	screen._profile_back()
	await get_tree().process_frame
	_check(not screen._profile_wrap.visible, "back again closes profile")
	_check(screen._views[screen._current].visible, "tab view restored after close")

	# --- fixture link jumps to Fixtures & Results with the row selected
	var target := {}
	for f in GameState.fixtures:
		if f["played"]:
			target = f
			break
	if target.is_empty():
		for f in GameState.fixtures:
			target = f
			break
	screen.comp_navigate({"kind": "fixture", "id": str(target["id"])})
	await get_tree().process_frame
	await get_tree().process_frame
	_check(screen._current == "fixtures", "fixture link selects Fixtures & Results tab")
	_check(str(screen._views["fixtures"]._selected_fid) == str(target["id"]),
		"fixture link selects the exact match for its report")

	# --- shell global-search context is honoured
	screen.reveal_search_target({"kind": "club", "id": cid})
	await get_tree().process_frame
	_check(screen._profile_wrap.visible and str(screen._nav_stack.back()["id"]) == cid,
		"reveal_search_target(club) opens the club profile")

	# --- tab click closes profiles
	screen._select_tab("table")
	await get_tree().process_frame
	_check(not screen._profile_wrap.visible, "tab switch closes profile view")


func UI_club_of(uid: String) -> String:
	for c in GameState.world["clubs"]:
		for inst in c["squad"]:
			if str(inst["uid"]) == str(uid):
				return str(c["id"])
	return ""
