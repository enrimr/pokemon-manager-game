extends Node
## Windowed screenshot proof for the mobile-first portrait shell (mobile
## piece). Run WINDOWED with the mobile flag and a phone-portrait window:
##   TM_MOBILE=1 Godot --path . res://mobile/mobile_shots.tscn
## Captures every tab plus the inbox/squad detail views to artifacts/mobile/.
## Save-safe: SaveGuard backs up user://save.json and restores it on exit.

const SaveGuard := preload("res://tools/save_guard.gd")
const OUT := "artifacts/mobile"

var _fails := 0


func _ready() -> void:
	SaveGuard.backup()
	get_window().size = Vector2i(390, 844)
	_run.call_deferred()


func _run() -> void:
	var dir := ProjectSettings.globalize_path("res://") + OUT
	DirAccess.make_dir_recursive_absolute(dir)
	if GameState.player_club().is_empty():
		GameState.new_career()

	# the title screen is the phone's front door — prove the portrait layout
	var title: Control = load("res://menu/title.tscn").instantiate()
	add_child(title)
	await _frames(14)
	_shot("%s/title.png" % dir)

	# Load Game overlay, portrait (saves piece): slot list must fit the phone
	GameState.save_game()   # ensure at least one listed slot (SaveGuard restores)
	title._on_load_game()
	await _frames(10)
	_shot("%s/title_load.png" % dir)
	if title._load_overlay != null and is_instance_valid(title._load_overlay):
		title._load_overlay.queue_free()
		title._load_overlay = null
	await _frames(4)

	# settings overlay, portrait (user report: it ran off the phone screen)
	title._on_settings()
	await _frames(12)
	_shot("%s/settings.png" % dir)
	if title._settings_overlay != null and is_instance_valid(title._settings_overlay):
		title._settings_overlay.queue_free()
		title._settings_overlay = null
	await _frames(4)

	# onboarding, portrait: all four steps must fit the phone (user report:
	# the panel used to run off the right edge)
	title._on_new_game()
	await _frames(12)
	var ob: Control = title._onboarding
	if ob == null:
		printerr("MOBILE SHOT ERROR: onboarding did not open")
		_fails += 1
	else:
		ob._name_edit.text = "Maximiliano Fernández de Oak"   # long-name stress (summary wrap)
		await _frames(4)
		_shot("%s/onboarding_1.png" % dir)
		ob._on_next()
		await _frames(12)
		ob._club_panel.select_club("club05")
		await _frames(8)
		_shot("%s/onboarding_2.png" % dir)
		ob._on_next()
		await _frames(12)
		ob._starter_panel._select(4)
		await _frames(8)
		_shot("%s/onboarding_3.png" % dir)
		ob._on_next()
		await _frames(10)
		_shot("%s/onboarding_4.png" % dir)
		ob.queue_free()
		await _frames(4)
	remove_child(title)
	title.free()

	var shell: Control = load("res://mobile/shell.tscn").instantiate()
	add_child(shell)
	await _frames(12)
	_shot("%s/home.png" % dir)

	for tab in ["inbox", "squad", "league", "more", "items", "routes"]:
		shell.open_tab(tab)
		await _frames(10)
		_shot("%s/%s.png" % [dir, tab])

	# inbox detail: open the first message the way a tap would
	shell.open_tab("inbox")
	await _frames(6)
	var inbox_page: Node = shell._pages["inbox"]
	if not GameState.inbox.is_empty():
		inbox_page._selected = GameState.inbox[0]
		GameState.inbox[0]["read"] = true
		inbox_page.refresh()
		await _frames(10)
		_shot("%s/inbox_detail.png" % dir)

	# squad detail
	shell.open_tab("squad")
	await _frames(6)
	var squad_page: Node = shell._pages["squad"]
	var squad: Array = GameState.player_club().get("squad", [])
	if not squad.is_empty():
		squad_page._selected = squad[0]
		squad_page.refresh()
		await _frames(10)
		_shot("%s/squad_detail.png" % dir)

	# battle: the core loop, phone-native (prematch -> live -> full time)
	GameState.auto_sim_player_matches = false
	var due := {}
	for i in 30:
		for e in GameState.advance_day():
			if str(e["t"]) == "player_match_due":
				due = e["fixture"]
		if not due.is_empty():
			break
	if due.is_empty():
		printerr("MOBILE SHOT ERROR: no player fixture became due")
		_fails += 1
	else:
		shell.open_battle(due)
		await _frames(10)
		_shot("%s/battle_pre.png" % dir)
		var bp: Node = shell._battle_page
		bp.runner.confirm_lineup()
		bp.refresh()
		for i in 900:   # play the stream until the engine asks for our order
			await get_tree().process_frame
			if bp.runner.awaiting_input():
				break
		await _frames(12)   # let the action grid build
		_shot("%s/battle_live.png" % dir)
		bp.runner.skip_series()
		bp.runner.to_post()
		bp.refresh()
		await _frames(10)
		_shot("%s/battle_post.png" % dir)
		shell.close_battle()
		await _frames(4)

	# club profile drill-down (scout & bid from the phone)
	shell.open_tab("league")
	await _frames(4)
	var lp: Node = shell._pages["league"]
	lp._club = GameState.club(str(GameState.club_ids()[0]))
	lp.refresh()
	await _frames(10)
	_shot("%s/league_club.png" % dir)
	lp._club = {}

	# league fixtures mode
	shell.open_tab("league")
	await _frames(4)
	var league_page: Node = shell._pages["league"]
	league_page._mode = "fixtures"
	league_page.refresh()
	await _frames(8)
	_shot("%s/league_fixtures.png" % dir)

	SaveGuard.restore()
	if _fails > 0:
		printerr("MOBILE SHOTS FAILED: %d error(s)" % _fails)
		get_tree().quit(1)
	else:
		print("MOBILE SHOTS OK")
		get_tree().quit(0)


func _shot(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	if img == null or img.save_png(path) != OK:
		printerr("MOBILE SHOT ERROR: %s" % path)
		_fails += 1
		return
	var black := true
	for x in range(0, img.get_width(), 61):
		if img.get_pixel(x, img.get_height() / 2).get_luminance() > 0.01:
			black = false
			break
	if black:
		printerr("MOBILE SHOT ERROR (black frame): %s" % path)
		_fails += 1
	else:
		print("mobile shot: %s" % path)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
