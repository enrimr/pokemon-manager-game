extends Node
## Windowed screenshot proof for the new-career club picker (shell-owned).
## Run:  Godot --path . res://shell/picker_shots.tscn

const OUT := "artifacts/leagues"


func _ready() -> void:
	var shell: Control = load("res://shell/main.tscn").instantiate()
	add_child(shell)
	await _frames(10)
	var dir := ProjectSettings.globalize_path("res://") + OUT
	DirAccess.make_dir_recursive_absolute(dir)

	shell._open_club_picker()
	await _frames(14)
	_shot("%s/picker_kanto.png" % dir)

	var picker: Control = shell._club_picker
	picker._set_league("johto")
	await _frames(6)
	picker._select_club("club25")   # Blackthorn Dragonguard-ish: any johto row
	await _frames(8)
	_shot("%s/picker_johto.png" % dir)

	# actually start the career at the selected Johto club (full FM flow)
	picker.club_chosen.emit("club25")
	await _frames(16)
	if GameState.player_club().get("league", "") != "johto":
		printerr("PICKER SHOT ERROR: career did not start at the chosen Johto club")
	_shot("%s/shell_johto_career.png" % dir)

	GameState.delete_save()   # leave no test career behind
	print("PICKER SHOTS OK")
	get_tree().quit(0)


func _shot(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	if img.save_png(path) != OK:
		printerr("PICKER SHOT ERROR: %s" % path)
	else:
		print("picker shot: %s" % path)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
