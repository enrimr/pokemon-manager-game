extends Node
## Windowed screenshot proof for the title screen + onboarding (menu piece).
## Run:  Godot --path . res://menu/menu_shots.tscn
## Captures, in BOTH locales (en/es): the title with a save (Continue card),
## the title fresh (no save), and each onboarding step. Prints MENU SHOTS OK.
## NOTE: mutates user://save.json — the runner backs it up and restores it.

const OUT := "artifacts/menu"

var _fails := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var dir := ProjectSettings.globalize_path("res://") + OUT
	DirAccess.make_dir_recursive_absolute(dir)
	for loc in ["es", "en"]:
		TranslationServer.set_locale(loc)
		await _frames(2)

		# 1) title WITH a save -> Continue card (club/manager/date/season)
		GameState.world["meta"]["manager_name"] = "Alex Serrano" if loc == "en" else "María Oak"
		GameState.player_club()["manager"] = str(GameState.world["meta"]["manager_name"])
		GameState.save_game()
		var title: Control = await _fresh_title()
		_shot("%s/title_continue_%s.png" % [dir, loc])

		# 2) title with NO save -> New Game is the primary door
		GameState.delete_save()
		_free_title(title)
		title = await _fresh_title()
		_shot("%s/title_fresh_%s.png" % [dir, loc])

		# 3) settings overlay opens the real Settings screen over the title
		title._on_settings()
		await _frames(10)
		_shot("%s/title_settings_%s.png" % [dir, loc])
		if title._settings_overlay != null and is_instance_valid(title._settings_overlay):
			title._settings_overlay.queue_free()
			title._settings_overlay = null
		await _frames(4)

		# 4) onboarding steps
		title._on_new_game()
		await _frames(10)
		var ob: Control = title._onboarding
		if ob == null:
			printerr("MENU SHOT ERROR: onboarding did not open")
			_fails += 1
		else:
			ob._name_edit.text = "Alex Serrano"
			ob._nick_edit.text = "The Prof"
			ob._refresh_footer()
			await _frames(6)
			_shot("%s/onboarding_identity_%s.png" % [dir, loc])
			ob._on_next()
			await _frames(10)
			ob._club_panel.select_club("club05")   # any row: show the detail pane
			await _frames(8)
			_shot("%s/onboarding_club_%s.png" % [dir, loc])
			ob._on_next()
			await _frames(10)
			ob._starter_panel._select(4)   # the starter ceremony: pick Charmander
			ob._starter_panel._nick_edit.text = "Brasa" if loc == "es" else "Ember"
			await _frames(8)
			_shot("%s/onboarding_starter_%s.png" % [dir, loc])
			ob._on_next()
			await _frames(10)
			_shot("%s/onboarding_summary_%s.png" % [dir, loc])
			ob.queue_free()
		_free_title(title)
		await _frames(4)

	# 5) in-shell routing proof: the shell's "New Career" menu item (and the
	# game-over "start fresh" door, same call) opens the onboarding wizard
	TranslationServer.set_locale("es")
	var shell: Control = load("res://shell/main.tscn").instantiate()
	add_child(shell)
	await _frames(12)
	shell._on_menu_id(2)
	await _frames(10)
	if shell._onboarding == null or not is_instance_valid(shell._onboarding):
		printerr("MENU SHOT ERROR: shell New Career did not open the onboarding")
		_fails += 1
	else:
		_shot("%s/onboarding_over_shell_es.png" % dir)
		shell._onboarding.queue_free()
	await _frames(4)
	remove_child(shell)
	shell.free()

	# 6) prove the full start transaction wires the manager into the world
	MenuFlow.start_career("club09", "Alex Serrano", "The Prof", 7, "Burbuja")
	var ok := str(GameState.player_club().get("manager", "")) == "Alex Serrano" \
		and str(GameState.world["meta"].get("manager_name", "")) == "Alex Serrano" \
		and str(GameState.world["meta"].get("manager_nickname", "")) == "The Prof" \
		and MenuFlow.has_save()
	if not ok:
		printerr("MENU SHOT ERROR: manager identity did not flow into the world/save")
		_fails += 1
	var pro = ProtegeService.instance
	if pro == null or not pro.has_protege() or pro.academy_entry().is_empty() \
			or int(pro.academy_entry().get("species_id", 0)) != 7:
		printerr("MENU SHOT ERROR: starter selection did not land in the academy")
		_fails += 1
	GameState.delete_save()   # runner restores the real save afterwards

	if _fails > 0:
		printerr("MENU SHOTS FAILED: %d error(s)" % _fails)
		get_tree().quit(1)
	else:
		print("MENU SHOTS OK")
		get_tree().quit(0)


func _fresh_title() -> Control:
	var t: Control = load("res://menu/title.tscn").instantiate()
	add_child(t)
	await _frames(14)
	return t


func _free_title(t: Control) -> void:
	if t != null and is_instance_valid(t):
		remove_child(t)
		t.free()   # synchronous: its AudioManager must exit before the next boots


func _shot(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	if img == null or img.save_png(path) != OK:
		printerr("MENU SHOT ERROR: %s" % path)
		_fails += 1
	else:
		var black := true
		for x in range(0, img.get_width(), 97):
			if img.get_pixel(x, img.get_height() / 2).get_luminance() > 0.01:
				black = false
				break
		if black:
			printerr("MENU SHOT ERROR: %s rendered black" % path)
			_fails += 1
		print("menu shot: %s" % path)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
