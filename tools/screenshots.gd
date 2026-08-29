extends Node
## Screenshot harness for critics. Boots the real shell + GameState, navigates
## to each requested screen, waits for layout, saves 1600x900 PNGs.
##
## Usage (must run WINDOWED — headless cannot render):
##   godot --path <project> res://tools/screenshots.tscn -- --screens=squad,tactics --out=artifacts/run1
##   godot --path <project> res://tools/screenshots.tscn -- --screens=all --out=artifacts/all
##
## Exits 0 on success; nonzero (and prints SCREENSHOT ERROR lines) on any failure.

const SETTLE_FRAMES := 12

var _shell: Control


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := _parse_args()
	var out_dir: String = args.get("out", "artifacts/screens")
	if not out_dir.is_absolute_path():
		out_dir = ProjectSettings.globalize_path("res://").path_join(out_dir)
	var err := DirAccess.make_dir_recursive_absolute(out_dir)
	if err != OK:
		_die("cannot create output dir %s (err %d)" % [out_dir, err])
		return

	# Boot the real shell (GameState autoload already loaded/created a career).
	var packed: PackedScene = load("res://shell/main.tscn")
	if packed == null:
		_die("cannot load res://shell/main.tscn")
		return
	_shell = packed.instantiate()
	get_tree().root.add_child(_shell)
	await _settle()

	var wanted: Array = []
	var screens_arg: String = args.get("screens", "all")
	if screens_arg == "all" or screens_arg == "":
		wanted = _shell.screens.keys()
	else:
		wanted = Array(screens_arg.split(",")).map(func(s): return String(s).strip_edges())

	if wanted.is_empty():
		_die("no screens requested/discovered")
		return

	var failures := 0
	for name in wanted:
		if not _shell.navigate_to(name):
			printerr("SCREENSHOT ERROR: screen '%s' failed to load" % name)
			failures += 1
			continue
		await _settle()
		var img: Image = get_viewport().get_texture().get_image()
		if img == null:
			printerr("SCREENSHOT ERROR: null viewport image for '%s'" % name)
			failures += 1
			continue
		if _is_black(img):
			printerr("SCREENSHOT ERROR: image for '%s' is black — rendering broken?" % name)
			failures += 1
		var path := out_dir.path_join("%s.png" % name)
		if img.save_png(path) != OK:
			printerr("SCREENSHOT ERROR: cannot save %s" % path)
			failures += 1
			continue
		print("screenshot: %s (%dx%d) -> %s" % [name, img.get_width(), img.get_height(), path])

	if failures > 0:
		printerr("SCREENSHOTS FAILED: %d error(s)" % failures)
		get_tree().quit(1)
	else:
		print("SCREENSHOTS OK: %d captured to %s" % [wanted.size(), out_dir])
		get_tree().quit(0)


func _settle() -> void:
	for i in SETTLE_FRAMES:
		await get_tree().process_frame


func _is_black(img: Image) -> bool:
	var total := 0.0
	var n := 0
	for x in range(0, img.get_width(), 64):
		for y in range(0, img.get_height(), 64):
			var c := img.get_pixel(x, y)
			total += c.r + c.g + c.b
			n += 1
	return total / maxf(n, 1) < 0.01


func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv: PackedStringArray = a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1]
	return out


func _die(msg: String) -> void:
	printerr("SCREENSHOT ERROR: %s" % msg)
	get_tree().quit(1)
