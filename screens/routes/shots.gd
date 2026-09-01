extends Node
## Builder verification: boots the real shell on a throwaway career with a
## live expedition + a completed one, opens the Routes screen and screenshots
## every tab plus the expedition mail renderers (windowed run).
##   Godot --path . res://screens/routes/shots.tscn
## The player's real save is backed up in-process and restored before quitting.

const SaveGuard := preload("res://tools/save_guard.gd")
const ExpedScript := preload("res://shared/sim/services/expeditions.gd")
const OUT := "artifacts/routes"
const SETTLE := 14

var _shell: Control


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var out_dir := ProjectSettings.globalize_path("res://").path_join(OUT)
	DirAccess.make_dir_recursive_absolute(out_dir)
	SaveGuard.backup()
	GameState.delete_save()
	GameState.new_career(424243)
	var svc: RefCounted = ExpedScript.active
	# a completed Viridian Forest trip (history + knowledge + final mail)...
	var leaders: Array = svc.leaders()
	svc.plan("kanto:viridian_forest", 6, str(leaders[0]["id"]), "balanced", 10, "academy")
	for i in 9:
		GameState.advance_day()
	# ...plus a live one mid-field led by the manager (tracker card).
	svc.plan("kanto:mt_moon", 8, "manager", "aggressive", 12, "academy")
	for i in 5:
		GameState.advance_day()

	_shell = (load("res://shell/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(_shell)
	await _settle()
	_shell.navigate_to("routes")
	await _settle()
	var screen: Control = _shell.find_child("RoutesScreen", true, false)
	if screen == null:
		printerr("ROUTES SHOTS ERROR: screen not found")
		SaveGuard.restore()
		get_tree().quit(1)
		return
	# map tab, Viridian Forest selected (knowledge unlocked after the trip)
	screen.select_tab("map")
	await _settle()
	var tree: Tree = screen._tree
	var it: TreeItem = tree.get_root().get_first_child()
	while it != null and str(it.get_metadata(0)) != "kanto:viridian_forest":
		it = it.get_next()
	if it != null:
		tree.set_selected(it, 0)
	await _settle()
	await _shot(out_dir, "routes_map")
	screen._set_region("johto")
	await _settle()
	await _shot(out_dir, "routes_map_johto")
	screen._set_region("kanto")
	screen.select_tab("expeditions")
	await _settle()
	await _shot(out_dir, "routes_expeditions")
	screen.select_tab("history")
	await _settle()
	await _shot(out_dir, "routes_history")

	_shell.navigate_to("inbox")
	await _settle()
	var inbox_scr: Control = _shell.find_child("InboxScreen", true, false)
	if inbox_scr != null:
		_select_mail(inbox_scr, "day")
		await _settle()
		await _shot(out_dir, "routes_mail_field_report")
		_select_mail(inbox_scr, "final")
		await _settle()
		await _shot(out_dir, "routes_mail_return")
	SaveGuard.restore()
	print("ROUTES SHOTS OK")
	get_tree().quit(0)


func _select_mail(inbox_scr: Control, kind: String) -> void:
	for m in GameState.inbox:
		if str(m.get("exped_kind", "")) == kind:
			inbox_scr._on_row_pressed(m)
			return


func _shot(out_dir: String, name: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	if img == null or img.save_png(out_dir.path_join(name + ".png")) != OK:
		printerr("ROUTES SHOT ERROR: %s" % name)
		SaveGuard.restore()
		get_tree().quit(1)
		return
	print("shot: %s" % name)


func _settle() -> void:
	for i in SETTLE:
		await get_tree().process_frame
