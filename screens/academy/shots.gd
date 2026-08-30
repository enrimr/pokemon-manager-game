extends Node
## Builder verification: boots the real shell on a throwaway career with two
## intakes banked, opens the Academy screen and screenshots it (windowed run).
##   Godot --path . res://screens/academy/shots.tscn
## The player's real save is backed up in-process and restored before quitting.

const SaveGuard := preload("res://tools/save_guard.gd")
const OUT := "artifacts/academy"
const SETTLE := 14

var _shell: Control


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var out_dir := ProjectSettings.globalize_path("res://").path_join(OUT)
	DirAccess.make_dir_recursive_absolute(out_dir)
	SaveGuard.backup()
	GameState.delete_save()
	GameState.new_career(424242)
	for i in 50:
		GameState.advance_day()
	GameState.player_club()["finances"]["balance"] = 3000000
	var svc: RefCounted = (load("res://shared/sim/services/academy.gd") as GDScript).active
	svc.request_upgrade()
	for i in 16:  # board decision (3d) + L2 construction (10d) -> facilities open
		GameState.advance_day()

	_shell = (load("res://shell/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(_shell)
	await _settle()
	_shell.navigate_to("academy")
	await _settle()
	var screen: Control = _shell.find_child("AcademyScreen", true, false)
	if screen != null:
		var tree: Tree = screen._tree
		var first: TreeItem = tree.get_root().get_first_child()
		if first != null:
			tree.set_selected(first, 0)
			screen._on_row_selected()
	await _settle()
	await _shot(out_dir, "academy_roster")
	_shell.navigate_to("inbox")
	await _settle()
	var inbox_scr: Control = _shell.find_child("InboxScreen", true, false)
	if inbox_scr != null:
		_select_mail(inbox_scr, "intake")
		await _settle()
	await _shot(out_dir, "academy_intake_inbox")
	if inbox_scr != null:
		_select_mail(inbox_scr, "facility_open")
		await _settle()
		await _shot(out_dir, "academy_facility_open_inbox")
		_select_mail(inbox_scr, "preview")
		await _settle()
		await _shot(out_dir, "academy_preview_inbox")
	SaveGuard.restore()
	print("ACADEMY SHOTS OK")
	get_tree().quit(0)


func _select_mail(inbox_scr: Control, kind: String) -> void:
	for m in GameState.inbox:
		if str(m.get("academy_kind", "")) == kind:
			inbox_scr._on_row_pressed(m)
			return


func _shot(out_dir: String, name: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	if img == null or img.save_png(out_dir.path_join(name + ".png")) != OK:
		printerr("ACADEMY SHOT ERROR: %s" % name)
		SaveGuard.restore()
		get_tree().quit(1)
		return
	print("shot: %s" % name)


func _settle() -> void:
	for i in SETTLE:
		await get_tree().process_frame
