extends Node
## Windowed screenshot capture for shell sub-navigation (shell-owned).
## Boots the real shell, deep-links to NON-default tabs the way a sidebar
## sub-item / search result would, and saves PNGs as visual proof.
##
## Run:  Godot --path . res://shell/tab_shots.tscn

const OUT := "artifacts/portraits-check"
const SHOTS := [
	["transfers", "search", "transfers_search"],
	["training", "coaches", "training_coaches"],
]


func _ready() -> void:
	var shell: Control = load("res://shell/main.tscn").instantiate()
	add_child(shell)
	await _frames(24)   # let the shell finish its own boot navigation first
	var dir := ProjectSettings.globalize_path("res://") + OUT
	DirAccess.make_dir_recursive_absolute(dir)
	for s in SHOTS:
		shell.navigate_to(s[0], {"kind": "tab", "tab": s[1], "label": ""})
		await _frames(14)
		var img := get_viewport().get_texture().get_image()
		var path := "%s/%s.png" % [dir, s[2]]
		var err := img.save_png(path)
		if err != OK:
			printerr("TAB SHOT ERROR: %s (%d)" % [path, err])
		else:
			print("tab shot: %s -> %s" % ["%s/%s" % [s[0], s[1]], path])
	print("TAB SHOTS OK")
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
