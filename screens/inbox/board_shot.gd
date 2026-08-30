extends Node
## Inbox piece: screenshot helper for the Board & Finances tab (the stock
## harness can't select sub-tabs). Boots the real shell, deep-links to
## inbox > board, saves a 1600x900 PNG. Must run WINDOWED.
## Run: godot --path . res://screens/inbox/board_shot.tscn -- --out=artifacts/inbox/fix2/inbox_board.png

const SETTLE_FRAMES := 12


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := "artifacts/inbox/board_tab.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	if not out.is_absolute_path():
		out = ProjectSettings.globalize_path("res://").path_join(out)
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())

	var shell: Control = (load("res://shell/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(shell)
	await _settle()
	if not shell.navigate_to("inbox", {"kind": "tab", "tab": "board", "label": "Board & Finances"}):
		printerr("BOARD SHOT ERROR: navigation failed")
		get_tree().quit(1)
		return
	await _settle()
	var img: Image = get_viewport().get_texture().get_image()
	if img == null or img.save_png(out) != OK:
		printerr("BOARD SHOT ERROR: cannot save %s" % out)
		get_tree().quit(1)
		return
	print("BOARD SHOT OK: %s" % out)
	get_tree().quit(0)


func _settle() -> void:
	for i in SETTLE_FRAMES:
		await get_tree().process_frame
