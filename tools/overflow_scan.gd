extends Node
## Layout audit for the Spanish min-width bug class (five user reports —
## see prematch_overflow_check.gd for the single-view original): boots the
## REAL shell in Spanish AND English, walks every screen and every tab, and
## fails if any visible control's rect crosses the canvas' right edge.
## Run: godot --headless --path . res://tools/overflow_scan.tscn
## Prints one line per view; "OVERFLOW SCAN OK" and exit 0 when clean.

const SaveGuard := preload("res://tools/save_guard.gd")
const SETTLE := 8
const TOLERANCE := 1.5

var _fails := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	SaveGuard.backup()
	GameState.new_career(778899)
	for locale in ["es", "en"]:
		TranslationServer.set_locale(locale)
		var shell: Control = (load("res://shell/main.tscn") as PackedScene).instantiate()
		get_tree().root.add_child(shell)
		await _settle()
		var limit := get_viewport().get_visible_rect().size.x
		for name in shell.screens.keys():
			var tabs: Array = [""]
			for t in shell.screens[name].get("tabs", []):
				tabs.append(str(t["id"]))
			for tab in tabs:
				var ctx := {"kind": "tab", "tab": tab, "label": tab} if tab != "" else {}
				if not shell.navigate_to(name, ctx):
					printerr("  SCAN FAIL [%s] %s/%s: navigation failed" % [locale, name, tab])
					_fails += 1
					continue
				await _settle()
				_scan_view(shell, "%s%s" % [name, "/" + tab if tab != "" else ""], locale, limit)
		shell.queue_free()
		await _settle()
	SaveGuard.restore()
	if _fails == 0:
		print("OVERFLOW SCAN OK")
	else:
		printerr("OVERFLOW SCAN FAILED: %d view(s)" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)


func _settle() -> void:
	for i in SETTLE:
		await get_tree().process_frame


func _scan_view(root: Node, view: String, locale: String, limit: float) -> void:
	var offenders: Array = []
	_walk(root, limit, offenders)
	if offenders.is_empty():
		print("  ok [%s] %s" % [locale, view])
		return
	_fails += 1
	offenders.sort_custom(func(a, b): return a["x"] > b["x"])
	printerr("  SCAN FAIL [%s] %s: %d control(s) past x=%.0f" % [locale, view, offenders.size(), limit])
	for o in offenders.slice(0, 12):
		printerr("      x=%.0f (+%.0f)  %s" % [o["x"], o["x"] - limit, o["path"]])


func _walk(n: Node, limit: float, out: Array) -> void:
	if n is Control:
		var c: Control = n
		if not c.is_visible_in_tree():
			return
		# a control's own rect past the edge is the defect; children of
		# scrolling containers are judged by their (clipped) parents
		var right := c.get_global_rect().end.x
		if right > limit + TOLERANCE:
			out.append({"x": right, "path": String(c.get_path()).replace("/root/", "")})
	if n is ScrollContainer:
		return   # inner content pans by design
	for child in n.get_children():
		_walk(child, limit, out)
