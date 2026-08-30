extends Node
## Windowed helper: screenshots the Fixtures & Results match-report panel for
## (a) a fixture with a full persisted play-time report and (b) a migrated
## legacy fixture (score-only stub), proving reports match recorded scores.
##   godot --path <project> res://screens/competition/report_shot.tscn -- --out=artifacts/reports
## Optional: --fid=C101 additionally captures that specific fixture's report.

const SETTLE := 14

var _shell: Control


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var out_dir := "artifacts/reports"
	var want_fid := ""
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--out="):
			out_dir = str(a).split("=")[1]
		elif str(a).begins_with("--fid="):
			want_fid = str(a).split("=")[1]
	if not out_dir.is_absolute_path():
		out_dir = ProjectSettings.globalize_path("res://").path_join(out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)

	_shell = (load("res://shell/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(_shell)
	await _settle()
	_shell.navigate_to("competition")
	await _settle()
	var screen: Node = _shell._current_screen_instance()

	var full := {}
	var stub := {}
	for f in GameState.fixtures:
		if not f.get("played", false):
			continue
		var d: Variant = f.get("detail")
		if not (d is Dictionary):
			continue
		if d.get("no_report", false):
			if stub.is_empty():
				stub = f
		elif full.is_empty():
			full = f
	var shots := {"report_full": full, "report_stub": stub}
	if want_fid != "":
		for f in GameState.fixtures:
			if str(f["id"]) == want_fid:
				shots["report_%s" % want_fid] = f
				break
	for name in shots:
		var f: Dictionary = shots[name]
		if f.is_empty():
			print("no fixture for %s — skipped" % name)
			continue
		screen.comp_navigate({"kind": "fixture", "id": str(f["id"])})
		await _settle()
		print("%s: %s recorded %d-%d no_report=%s" % [name, f["id"],
			int(f["score_home"]), int(f["score_away"]),
			str(f["detail"].get("no_report", false))])
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png(out_dir.path_join("%s.png" % name))
		print("saved %s" % out_dir.path_join("%s.png" % name))
	print("REPORT SHOTS OK")
	get_tree().quit(0)


func _settle() -> void:
	for i in SETTLE:
		await get_tree().process_frame
