extends Node
## Builder utility (training piece): boot the real shell, open the Training
## screen, switch to a given tab and save a PNG — verification of tabs the
## generic harness cannot reach. Must run WINDOWED.
## Run: Godot --path . res://screens/training/tab_shot.tscn -- --tab=mentoring --out=artifacts/training/feature/mentoring.png

var _shell: Control


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var tab := "mentoring"
	var out := "artifacts/training/feature/tab.png"
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--tab="):
			tab = str(a).split("=")[1]
		elif str(a).begins_with("--out="):
			out = str(a).split("=")[1]
	if not out.is_absolute_path():
		out = ProjectSettings.globalize_path("res://").path_join(out)
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())

	_shell = (load("res://shell/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(_shell)
	await _settle()
	if not _shell.navigate_to("training"):
		printerr("TAB SHOT ERROR: training screen failed to load")
		get_tree().quit(1)
		return
	await _settle()
	# find the live training screen instance and switch its tab
	var scr: Node = _find_training(get_tree().root)
	if scr == null:
		printerr("TAB SHOT ERROR: no training screen instance found")
		get_tree().quit(1)
		return
	scr._switch_tab(tab)
	await _settle()
	var img: Image = get_viewport().get_texture().get_image()
	if img == null or img.save_png(out) != OK:
		printerr("TAB SHOT ERROR: cannot save %s" % out)
		get_tree().quit(1)
		return
	print("TAB SHOT OK: %s -> %s" % [tab, out])
	get_tree().quit(0)


func _find_training(n: Node) -> Node:
	if n.get_script() != null and str((n.get_script() as Script).resource_path) == "res://screens/training/screen.gd":
		return n
	for c in n.get_children():
		var f := _find_training(c)
		if f != null:
			return f
	return null


func _settle() -> void:
	for i in 14:
		await get_tree().process_frame
