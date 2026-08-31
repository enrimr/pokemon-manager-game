extends Node
## Windowed check (spanish piece): a mid-career language switch must retranslate
## the WHOLE shell chrome instantly — footer, shortcut hints, top bar, sidebar.
## Run: godot --path . res://i18n/switch_check.tscn   (not headless)
## Prints "SWITCH CHECK OK" on success and saves before/after screenshots.

var _fail := false


func _check(cond: bool, what: String) -> void:
	if cond:
		print("  ok: %s" % what)
	else:
		printerr("  SWITCH CHECK FAIL: %s" % what)
		_fail = true


func _settle(frames := 16) -> void:
	for i in frames:
		await get_tree().process_frame


func _shot(shell: Control, path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := shell.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("  shot: %s" % path)


func _find_label(root: Node, needle: String) -> Label:
	for n in root.find_children("*", "Label", true, false):
		if str((n as Label).text).contains(needle):
			return n
	return null


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	print("=== switch check: live locale change retranslates shell chrome ===")
	var shell: Control = load("res://shell/main.tscn").instantiate()
	get_tree().root.add_child(shell)
	await _settle(30)

	Settings.set_setting("locale", "en")
	await _settle()
	var foot := _find_label(shell, "TRAINER MANAGER ·")
	_check(foot != null, "found sidebar footer label")
	var foot_en := str(foot.text) if foot != null else ""
	var hint: Node = shell.find_child("ShortcutHint", true, false)
	_check(hint is Label, "found top-bar shortcut hint")
	var hint_en := str((hint as Label).text) if hint is Label else ""
	_check(hint_en.contains("Continue"), "hint is English while locale=en")
	await _shot(shell, "artifacts/spanish/w3_fix1/switch_before_en.png")

	Settings.set_setting("locale", "es")
	await _settle()
	var hint_es := str((hint as Label).text) if hint is Label else ""
	var side: Node = shell.find_child("SidebarHint", true, false)
	_check(hint_es != hint_en and hint_es.contains("Continuar"),
		"top-bar shortcut hint retranslated instantly (%s)" % hint_es)
	_check(side is Label and str((side as Label).text).contains("Continuar"),
		"sidebar shortcut hint retranslated instantly")
	_check(foot != null and str(foot.text).contains(I18n.t(GameState.world["meta"]["league_name"])),
		"footer league name retranslated instantly")
	await _shot(shell, "artifacts/spanish/w3_fix1/switch_after_es.png")

	# restore the player's real preference (es) and leave the tree clean
	Settings.set_setting("locale", "es")
	if _fail:
		printerr("SWITCH CHECK FAILED")
		get_tree().quit(1)
	else:
		print("SWITCH CHECK OK")
		get_tree().quit(0)
